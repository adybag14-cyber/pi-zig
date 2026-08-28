//! Native adapter for extension-defined `streamSimple(model, context, options)`.
//!
//! The provider registry owns callback descriptors and persistent JavaScript
//! workers. ClientPool owns provider/model selection. This module is the
//! cycle-free boundary between them: it projects native messages and request
//! metadata into the upstream Pi shape, validates/acknowledges every ordered
//! event, and converts the terminal AssistantMessage into a native
//! `ai.ModelResponse` only after the JavaScript iterator has fully completed.
const std = @import("std");
const ai = @import("../ai/root.zig");
const pi_messages = @import("../ai/pi_messages.zig");
const metadata = @import("../ai/request_metadata.zig");
const thinking_mod = @import("../ai/thinking.zig");
const live_state = @import("../coding_agent/live_state.zig");
const provider_registry = @import("provider_registry.zig");
const js_runtime = @import("js_runtime.zig");

const TerminalKind = enum { done, err };
const BlockKind = enum { text, thinking, tool_call };

const RequestDocuments = struct {
    context_json: []u8,
    options_json: []u8,

    fn deinit(self: *RequestDocuments, gpa: std.mem.Allocator) void {
        gpa.free(self.context_json);
        gpa.free(self.options_json);
        self.* = undefined;
    }
};

const ToolBlock = struct {
    id: []u8 = &.{},
    name: []u8 = &.{},
    arguments: std.ArrayList(u8) = .empty,
    emitted_len: usize = 0,

    fn deinit(self: *ToolBlock, gpa: std.mem.Allocator) void {
        if (self.id.len > 0) gpa.free(self.id);
        if (self.name.len > 0) gpa.free(self.name);
        self.arguments.deinit(gpa);
        self.* = undefined;
    }
};

const ContentBlock = struct {
    kind: BlockKind,
    saw_delta: bool = false,
    tool: ToolBlock = .{},

    fn deinit(self: *ContentBlock, gpa: std.mem.Allocator) void {
        self.tool.deinit(gpa);
        self.* = undefined;
    }
};

const StreamState = struct {
    gpa: std.mem.Allocator,
    request: live_state.ExtensionStreamRequest,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    acc: ai.stream.Accumulator,
    blocks: std.AutoHashMap(usize, ContentBlock),
    started: bool = false,
    terminal_kind: ?TerminalKind = null,
    terminal_reason: []u8 = &.{},
    terminal_message_json: []u8 = &.{},

    fn init(
        gpa: std.mem.Allocator,
        request: live_state.ExtensionStreamRequest,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) StreamState {
        return .{
            .gpa = gpa,
            .request = request,
            .on_delta = on_delta,
            .delta_ctx = delta_ctx,
            .acc = ai.stream.Accumulator.init(gpa),
            .blocks = std.AutoHashMap(usize, ContentBlock).init(gpa),
        };
    }

    fn deinit(self: *StreamState) void {
        var iterator = self.blocks.valueIterator();
        while (iterator.next()) |block| block.deinit(self.gpa);
        self.blocks.deinit();
        self.acc.deinit();
        if (self.terminal_reason.len > 0) self.gpa.free(self.terminal_reason);
        if (self.terminal_message_json.len > 0) self.gpa.free(self.terminal_message_json);
        self.* = undefined;
    }

    fn emit(self: *StreamState, delta: ai.StreamDelta) !void {
        try self.acc.onDelta(delta);
        if (self.on_delta) |handler| handler(self.delta_ctx, delta);
    }

    fn handleEvent(raw: ?*anyopaque, sequence: u64, event_json: []const u8) anyerror!void {
        _ = sequence;
        const self: *StreamState = @ptrCast(@alignCast(raw orelse return error.MissingProviderStreamState));
        return self.handle(event_json);
    }

    fn handle(self: *StreamState, event_json: []const u8) !void {
        if (self.terminal_kind != null) return error.ProviderStreamEventAfterTerminal;
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, event_json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidProviderStreamEvent;
        const typ = requiredString(parsed.value.object, "type") orelse return error.InvalidProviderStreamEvent;

        if (std.mem.eql(u8, typ, "start")) {
            if (self.started) return error.DuplicateProviderStreamStart;
            self.started = true;
            return;
        }
        if (!self.started) return error.ProviderStreamEventBeforeStart;

        if (std.mem.eql(u8, typ, "text_start")) return self.startBlock(parsed.value.object, .text);
        if (std.mem.eql(u8, typ, "thinking_start")) return self.startBlock(parsed.value.object, .thinking);
        if (std.mem.eql(u8, typ, "toolcall_start")) return self.startBlock(parsed.value.object, .tool_call);
        if (std.mem.eql(u8, typ, "text_delta")) return self.textDelta(parsed.value.object, .text);
        if (std.mem.eql(u8, typ, "thinking_delta")) return self.textDelta(parsed.value.object, .thinking);
        if (std.mem.eql(u8, typ, "toolcall_delta")) return self.toolDelta(parsed.value.object);
        if (std.mem.eql(u8, typ, "text_end")) return self.textEnd(parsed.value.object, .text);
        if (std.mem.eql(u8, typ, "thinking_end")) return self.textEnd(parsed.value.object, .thinking);
        if (std.mem.eql(u8, typ, "toolcall_end")) return self.toolEnd(parsed.value.object);
        if (std.mem.eql(u8, typ, "done")) return self.terminal(parsed.value.object, .done);
        if (std.mem.eql(u8, typ, "error")) return self.terminal(parsed.value.object, .err);
        return error.UnsupportedProviderStreamEvent;
    }

    fn startBlock(self: *StreamState, object: std.json.ObjectMap, kind: BlockKind) !void {
        const index = try contentIndex(object);
        if (self.blocks.contains(index)) return error.DuplicateProviderStreamContentIndex;
        var block = ContentBlock{ .kind = kind };
        errdefer block.deinit(self.gpa);
        if (kind == .tool_call) try updateToolIdentityFromPartial(self.gpa, &block.tool, object, index);
        try self.blocks.put(index, block);
    }

    fn textDelta(self: *StreamState, object: std.json.ObjectMap, kind: BlockKind) !void {
        const index = try contentIndex(object);
        const block = self.blocks.getPtr(index) orelse return error.ProviderStreamContentIndexNotOpen;
        if (block.kind != kind) return error.ProviderStreamContentKindMismatch;
        const delta = requiredString(object, "delta") orelse return error.InvalidProviderStreamEvent;
        block.saw_delta = true;
        if (delta.len == 0) return;
        if (kind == .text) {
            try self.emit(.{ .kind = .text_delta, .text = delta });
        } else {
            try self.emit(.{ .kind = .thinking_delta, .thinking = delta });
        }
    }

    fn toolDelta(self: *StreamState, object: std.json.ObjectMap) !void {
        const index = try contentIndex(object);
        const block = self.blocks.getPtr(index) orelse return error.ProviderStreamContentIndexNotOpen;
        if (block.kind != .tool_call) return error.ProviderStreamContentKindMismatch;
        const delta = requiredString(object, "delta") orelse return error.InvalidProviderStreamEvent;
        block.saw_delta = true;
        try block.tool.arguments.appendSlice(self.gpa, delta);
        try updateToolIdentityFromPartial(self.gpa, &block.tool, object, index);
        try self.flushToolArguments(&block.tool);
    }

    fn textEnd(self: *StreamState, object: std.json.ObjectMap, kind: BlockKind) !void {
        const index = try contentIndex(object);
        const content = requiredString(object, "content") orelse return error.InvalidProviderStreamEvent;
        const removed = self.blocks.fetchRemove(index) orelse return error.ProviderStreamContentIndexNotOpen;
        var block = removed.value;
        defer block.deinit(self.gpa);
        if (block.kind != kind) return error.ProviderStreamContentKindMismatch;
        if (!block.saw_delta and content.len > 0) {
            if (kind == .text) {
                try self.emit(.{ .kind = .text_delta, .text = content });
            } else {
                try self.emit(.{ .kind = .thinking_delta, .thinking = content });
            }
        }
    }

    fn toolEnd(self: *StreamState, object: std.json.ObjectMap) !void {
        const index = try contentIndex(object);
        const tool_call = object.get("toolCall") orelse return error.InvalidProviderStreamEvent;
        if (tool_call != .object) return error.InvalidProviderStreamEvent;
        const final_id = requiredString(tool_call.object, "id") orelse return error.InvalidProviderStreamToolCall;
        const final_name = requiredString(tool_call.object, "name") orelse return error.InvalidProviderStreamToolCall;
        if (final_id.len == 0 or final_name.len == 0) return error.InvalidProviderStreamToolCall;

        const removed = self.blocks.fetchRemove(index) orelse return error.ProviderStreamContentIndexNotOpen;
        var block = removed.value;
        defer block.deinit(self.gpa);
        if (block.kind != .tool_call) return error.ProviderStreamContentKindMismatch;
        try setToolIdentity(self.gpa, &block.tool, final_id, final_name);

        if (tool_call.object.get("arguments")) |arguments| {
            const final_arguments = try stringifyValue(self.gpa, arguments);
            defer self.gpa.free(final_arguments);
            if (!block.saw_delta) {
                try block.tool.arguments.appendSlice(self.gpa, final_arguments);
            } else if (!jsonSemanticallyEqual(self.gpa, block.tool.arguments.items, final_arguments)) {
                return error.ProviderStreamToolArgumentsMismatch;
            }
        } else if (!block.saw_delta) {
            try block.tool.arguments.appendSlice(self.gpa, "{}");
        }
        try self.flushToolArguments(&block.tool);
    }

    fn terminal(self: *StreamState, object: std.json.ObjectMap, kind: TerminalKind) !void {
        if (self.blocks.count() != 0) return error.ProviderStreamTerminalWithOpenBlocks;
        const reason = requiredString(object, "reason") orelse return error.InvalidProviderStreamEvent;
        const message_value = object.get(if (kind == .done) "message" else "error") orelse return error.InvalidProviderStreamEvent;
        if (message_value != .object) return error.InvalidProviderStreamEvent;
        const message_json = try stringifyValue(self.gpa, message_value);
        errdefer self.gpa.free(message_json);
        self.terminal_reason = try self.gpa.dupe(u8, reason);
        self.terminal_message_json = message_json;
        self.terminal_kind = kind;
    }

    fn flushToolArguments(self: *StreamState, tool: *ToolBlock) !void {
        if (tool.id.len == 0 or tool.name.len == 0 or tool.emitted_len >= tool.arguments.items.len) return;
        const fragment = tool.arguments.items[tool.emitted_len..];
        try self.emit(.{
            .kind = .tool_call_delta,
            .tool_call_id = tool.id,
            .tool_name = tool.name,
            .tool_arguments = fragment,
        });
        tool.emitted_len = tool.arguments.items.len;
    }
};

pub const Runtime = struct {
    gpa: std.mem.Allocator,
    registry: *provider_registry.Registry,

    pub fn init(gpa: std.mem.Allocator, registry: *provider_registry.Registry) Runtime {
        return .{ .gpa = gpa, .registry = registry };
    }

    pub fn bridge(self: *Runtime) live_state.ExtensionStreamBridge {
        return .{
            .context = self,
            .supports_fn = supportsThunk,
            .supports_fetch_deferred_fn = supportsFetchDeferredThunk,
            .supports_cancel_deferred_fn = supportsCancelDeferredThunk,
            .complete_fn = completeThunk,
            .fetch_deferred_fn = fetchDeferredThunk,
            .cancel_deferred_fn = cancelDeferredThunk,
        };
    }

    pub fn supports(self: *const Runtime, provider_id: []const u8) bool {
        return self.registry.hasProviderMethod(provider_id, "streamSimple");
    }

    pub fn supportsFetchDeferred(self: *const Runtime, provider_id: []const u8) bool {
        return self.registry.hasProviderMethod(provider_id, "fetchDeferred");
    }

    pub fn supportsCancelDeferred(self: *const Runtime, provider_id: []const u8) bool {
        return self.registry.hasProviderMethod(provider_id, "cancelDeferred");
    }

    fn supportsThunk(raw: ?*anyopaque, provider_id: []const u8) bool {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return false));
        return self.supports(provider_id);
    }

    fn supportsFetchDeferredThunk(raw: ?*anyopaque, provider_id: []const u8) bool {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return false));
        return self.supportsFetchDeferred(provider_id);
    }

    fn supportsCancelDeferredThunk(raw: ?*anyopaque, provider_id: []const u8) bool {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return false));
        return self.supportsCancelDeferred(provider_id);
    }

    fn completeThunk(
        raw: ?*anyopaque,
        allocator: std.mem.Allocator,
        request: live_state.ExtensionStreamRequest,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
        abort_flag: ?*bool,
    ) anyerror!ai.ModelResponse {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return error.MissingProviderStreamRuntime));
        return self.complete(allocator, request, messages, tools_json, on_delta, delta_ctx, abort_flag);
    }

    fn fetchDeferredThunk(
        raw: ?*anyopaque,
        allocator: std.mem.Allocator,
        request: live_state.ExtensionStreamRequest,
        handle_json: []const u8,
        options_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
        abort_flag: ?*bool,
    ) anyerror!ai.ModelResponse {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return error.MissingProviderStreamRuntime));
        return self.fetchDeferred(allocator, request, handle_json, options_json, on_delta, delta_ctx, abort_flag);
    }

    fn cancelDeferredThunk(
        raw: ?*anyopaque,
        request: live_state.ExtensionStreamRequest,
        handle_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
    ) anyerror!void {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return error.MissingProviderStreamRuntime));
        return self.cancelDeferred(request, handle_json, options_json, abort_flag);
    }

    pub fn complete(
        self: *Runtime,
        allocator: std.mem.Allocator,
        request: live_state.ExtensionStreamRequest,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
        abort_flag: ?*bool,
    ) !ai.ModelResponse {
        if (!self.supports(request.provider_id)) return error.ExtensionProviderStreamUnavailable;
        if (abortRequested(abort_flag)) return makeFailureResponse(allocator, request, null, "Operation aborted", true, on_delta, delta_ctx);

        const model_json = try buildModelJson(self.gpa, self.registry, request);
        defer self.gpa.free(model_json);
        var documents = try buildRequestDocuments(self.gpa, request, messages, tools_json);
        defer documents.deinit(self.gpa);

        var state = StreamState.init(allocator, request, on_delta, delta_ctx);
        defer state.deinit();
        const protocol_summary = self.registry.streamSimple(
            request.provider_id,
            model_json,
            documents.context_json,
            documents.options_json,
            abort_flag,
            StreamState.handleEvent,
            &state,
        ) catch |err| {
            if (err == error.OutOfMemory) return err;
            const message = self.registry.providerMethodLastError(request.provider_id, "streamSimple") orelse @errorName(err);
            return makeFailureResponse(allocator, request, &state, message, abortRequested(abort_flag), on_delta, delta_ctx);
        };
        defer self.gpa.free(protocol_summary);
        validateProtocolSummary(self.gpa, protocol_summary, state.terminal_kind, state.terminal_reason) catch |err| {
            if (err == error.OutOfMemory) return err;
            return makeFailureResponse(allocator, request, &state, @errorName(err), false, on_delta, delta_ctx);
        };
        if (state.terminal_kind == null or state.terminal_message_json.len == 0) {
            return makeFailureResponse(allocator, request, &state, "provider stream ended without a terminal event", false, on_delta, delta_ctx);
        }

        var response = parseAssistantMessage(allocator, state.terminal_message_json, request, state.terminal_reason) catch |err| {
            if (err == error.OutOfMemory) return err;
            return makeFailureResponse(allocator, request, &state, @errorName(err), false, on_delta, delta_ctx);
        };
        errdefer response.deinit(allocator);
        const terminal_kind = state.terminal_kind.?;
        if (terminal_kind == .err) {
            if (response.stop_reason.len == 0 or (!std.mem.eql(u8, response.stop_reason, "error") and !std.mem.eql(u8, response.stop_reason, "aborted"))) {
                if (response.stop_reason.len > 0) allocator.free(response.stop_reason);
                response.stop_reason = try allocator.dupe(u8, if (std.mem.eql(u8, state.terminal_reason, "aborted")) "aborted" else "error");
            }
            if (on_delta) |handler| handler(delta_ctx, .{ .kind = .err, .text = response.error_message });
        } else {
            if (on_delta) |handler| handler(delta_ctx, .{ .kind = .done });
        }
        return response;
    }

    pub fn fetchDeferred(
        self: *Runtime,
        allocator: std.mem.Allocator,
        request: live_state.ExtensionStreamRequest,
        handle_json: []const u8,
        options_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
        abort_flag: ?*bool,
    ) !ai.ModelResponse {
        if (!self.supportsFetchDeferred(request.provider_id)) return error.DeferredResponsesUnsupported;
        if (abortRequested(abort_flag)) return makeFailureResponse(allocator, request, null, "Operation aborted", true, on_delta, delta_ctx);
        const model_json = try buildModelJson(self.gpa, self.registry, request);
        defer self.gpa.free(model_json);

        var state = StreamState.init(allocator, request, on_delta, delta_ctx);
        defer state.deinit();
        const protocol_summary = self.registry.fetchDeferred(
            request.provider_id,
            model_json,
            handle_json,
            options_json,
            abort_flag,
            StreamState.handleEvent,
            &state,
        ) catch |err| {
            if (err == error.OutOfMemory) return err;
            const message = self.registry.providerMethodLastError(request.provider_id, "fetchDeferred") orelse @errorName(err);
            return makeFailureResponse(allocator, request, &state, message, abortRequested(abort_flag), on_delta, delta_ctx);
        };
        defer self.gpa.free(protocol_summary);
        validateProtocolSummary(self.gpa, protocol_summary, state.terminal_kind, state.terminal_reason) catch |err| {
            if (err == error.OutOfMemory) return err;
            return makeFailureResponse(allocator, request, &state, @errorName(err), false, on_delta, delta_ctx);
        };
        if (state.terminal_kind == null or state.terminal_message_json.len == 0) {
            return makeFailureResponse(allocator, request, &state, "provider deferred fetch ended without a terminal event", false, on_delta, delta_ctx);
        }
        var response = parseAssistantMessage(allocator, state.terminal_message_json, request, state.terminal_reason) catch |err| {
            if (err == error.OutOfMemory) return err;
            return makeFailureResponse(allocator, request, &state, @errorName(err), false, on_delta, delta_ctx);
        };
        errdefer response.deinit(allocator);
        if (state.terminal_kind.? == .err) {
            if (on_delta) |handler| handler(delta_ctx, .{ .kind = .err, .text = response.error_message });
        } else if (on_delta) |handler| {
            handler(delta_ctx, .{ .kind = .done });
        }
        return response;
    }

    pub fn cancelDeferred(
        self: *Runtime,
        request: live_state.ExtensionStreamRequest,
        handle_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
    ) !void {
        if (!self.supportsCancelDeferred(request.provider_id)) return error.DeferredResponsesUnsupported;
        if (abortRequested(abort_flag)) return error.Canceled;
        const model_json = try buildModelJson(self.gpa, self.registry, request);
        defer self.gpa.free(model_json);
        try self.registry.cancelDeferred(request.provider_id, model_json, handle_json, options_json, abort_flag);
    }
};

fn abortRequested(abort_flag: ?*const bool) bool {
    return if (abort_flag) |flag| @atomicLoad(bool, flag, .acquire) else false;
}

fn contentIndex(object: std.json.ObjectMap) !usize {
    const value = object.get("contentIndex") orelse return error.InvalidProviderStreamContentIndex;
    if (value != .integer or value.integer < 0) return error.InvalidProviderStreamContentIndex;
    return std.math.cast(usize, value.integer) orelse error.InvalidProviderStreamContentIndex;
}

fn requiredString(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn updateToolIdentityFromPartial(gpa: std.mem.Allocator, tool: *ToolBlock, object: std.json.ObjectMap, index: usize) !void {
    const partial = object.get("partial") orelse return;
    if (partial != .object) return;
    const content = partial.object.get("content") orelse return;
    if (content != .array or index >= content.array.items.len) return;
    const item = content.array.items[index];
    if (item != .object) return;
    const typ = requiredString(item.object, "type") orelse return;
    if (!std.mem.eql(u8, typ, "toolCall")) return;
    const id = requiredString(item.object, "id") orelse "";
    const name = requiredString(item.object, "name") orelse "";
    if (id.len == 0 or name.len == 0) return;
    try setToolIdentity(gpa, tool, id, name);
}

fn setToolIdentity(gpa: std.mem.Allocator, tool: *ToolBlock, id: []const u8, name: []const u8) !void {
    if (tool.id.len > 0 and !std.mem.eql(u8, tool.id, id)) return error.ProviderStreamToolIdentityMismatch;
    if (tool.name.len > 0 and !std.mem.eql(u8, tool.name, name)) return error.ProviderStreamToolIdentityMismatch;
    if (tool.id.len == 0) tool.id = try gpa.dupe(u8, id);
    if (tool.name.len == 0) tool.name = try gpa.dupe(u8, name);
}

fn jsonSemanticallyEqual(gpa: std.mem.Allocator, a: []const u8, b: []const u8) bool {
    var left = std.json.parseFromSlice(std.json.Value, gpa, a, .{}) catch return false;
    defer left.deinit();
    var right = std.json.parseFromSlice(std.json.Value, gpa, b, .{}) catch return false;
    defer right.deinit();
    return valuesEqual(left.value, right.value);
}

fn valuesEqual(a: std.json.Value, b: std.json.Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) {
        if (a == .integer and b == .float) return @as(f64, @floatFromInt(a.integer)) == b.float;
        if (a == .float and b == .integer) return a.float == @as(f64, @floatFromInt(b.integer));
        return false;
    }
    return switch (a) {
        .null => true,
        .bool => a.bool == b.bool,
        .integer => a.integer == b.integer,
        .float => a.float == b.float,
        .number_string => std.mem.eql(u8, a.number_string, b.number_string),
        .string => std.mem.eql(u8, a.string, b.string),
        .array => blk: {
            if (a.array.items.len != b.array.items.len) break :blk false;
            for (a.array.items, b.array.items) |left, right| if (!valuesEqual(left, right)) break :blk false;
            break :blk true;
        },
        .object => blk: {
            if (a.object.count() != b.object.count()) break :blk false;
            var iterator = a.object.iterator();
            while (iterator.next()) |entry| {
                const other = b.object.get(entry.key_ptr.*) orelse break :blk false;
                if (!valuesEqual(entry.value_ptr.*, other)) break :blk false;
            }
            break :blk true;
        },
    };
}

fn stringifyValue(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn buildRequestDocuments(
    gpa: std.mem.Allocator,
    request: live_state.ExtensionStreamRequest,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
) !RequestDocuments {
    const payload = try pi_messages.buildRequestBody(gpa, request.model_id, messages, tools_json, .{
        .thinking = request.thinking,
        .max_tokens = request.max_tokens,
        .session_id = request.session_id,
        .cache_retention = request.cache_retention,
    });
    defer gpa.free(payload);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidProviderStreamContext;
    const context = parsed.value.object.get("context") orelse return error.InvalidProviderStreamContext;
    const base_options = parsed.value.object.get("options") orelse return error.InvalidProviderStreamOptions;
    if (context != .object or base_options != .object) return error.InvalidProviderStreamContext;

    var result: RequestDocuments = undefined;
    result.context_json = try stringifyValue(gpa, context);
    errdefer gpa.free(result.context_json);
    result.options_json = try buildOptionsJson(gpa, base_options.object, request);
    return result;
}

fn buildOptionsJson(gpa: std.mem.Allocator, base: std.json.ObjectMap, request: live_state.ExtensionStreamRequest) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeByte('{');
    var first = true;
    var iterator = base.iterator();
    while (iterator.next()) |entry| {
        try writeFieldPrefix(w, &first, entry.key_ptr.*);
        try std.json.Stringify.value(entry.value_ptr.*, .{}, w);
    }
    if (request.api_key) |api_key| {
        try writeFieldPrefix(w, &first, "apiKey");
        try std.json.Stringify.value(api_key, .{}, w);
    }
    if (request.headers.len > 0) {
        try writeFieldPrefix(w, &first, "headers");
        try writeHeaders(w, request.headers);
    }
    if (request.sampling_params.len > 0) {
        try writeFieldPrefix(w, &first, "samplingParams");
        try writeSamplingParams(w, request.sampling_params);
    }
    try w.writeByte('}');
    return out.toOwnedSlice();
}

fn buildModelJson(
    gpa: std.mem.Allocator,
    registry: *provider_registry.Registry,
    request: live_state.ExtensionStreamRequest,
) ![]u8 {
    var raw_model_doc: ?std.json.Parsed(std.json.Value) = null;
    defer if (raw_model_doc) |*doc| doc.deinit();
    var raw_model: ?std.json.ObjectMap = null;
    const models_json = registry.providerModelsJson(request.provider_id) catch null;
    defer if (models_json) |value| gpa.free(value);
    if (models_json) |value| {
        raw_model_doc = std.json.parseFromSlice(std.json.Value, gpa, value, .{}) catch null;
        if (raw_model_doc) |*doc| if (doc.value == .array) {
            for (doc.value.array.items) |candidate| {
                if (candidate != .object) continue;
                const id = requiredString(candidate.object, "id") orelse continue;
                if (std.mem.eql(u8, id, request.model_id)) {
                    raw_model = candidate.object;
                    break;
                }
            }
        };
    }

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeByte('{');
    var first = true;
    if (raw_model) |object| {
        var iterator = object.iterator();
        while (iterator.next()) |entry| {
            if (isStandardModelField(entry.key_ptr.*)) continue;
            try writeFieldPrefix(w, &first, entry.key_ptr.*);
            try std.json.Stringify.value(entry.value_ptr.*, .{}, w);
        }
    }

    try writeStringField(w, &first, "id", request.model_id);
    const name = if (raw_model) |object| requiredString(object, "name") orelse modelDisplay(registry, request.provider_id, request.model_id) else modelDisplay(registry, request.provider_id, request.model_id);
    try writeStringField(w, &first, "name", name);
    try writeStringField(w, &first, "api", request.api);
    try writeStringField(w, &first, "provider", request.provider_id);
    try writeStringField(w, &first, "baseUrl", request.base_url);
    try writeFieldPrefix(w, &first, "reasoning");
    try w.writeAll(if (request.reasoning) "true" else "false");
    if (request.thinking_level_map) |map| {
        try writeFieldPrefix(w, &first, "thinkingLevelMap");
        try writeThinkingLevelMap(w, map);
    }
    try writeFieldPrefix(w, &first, "input");
    try w.writeAll(if (request.input_image) "[\"text\",\"image\"]" else "[\"text\"]");
    try writeFieldPrefix(w, &first, "cost");
    try writeModelCost(w, request.model_cost);
    try writeNumberField(w, &first, "contextWindow", request.context_window);
    try writeNumberField(w, &first, "maxTokens", request.max_tokens);
    if (request.sampling_params.len > 0) {
        try writeFieldPrefix(w, &first, "samplingParams");
        try writeSamplingParams(w, request.sampling_params);
    }
    if (request.headers.len > 0) {
        try writeFieldPrefix(w, &first, "headers");
        try writeHeaders(w, request.headers);
    }
    if (compatHasFields(request.compat)) {
        try writeFieldPrefix(w, &first, "compat");
        try writeCompat(w, request.compat);
    } else if (raw_model) |object| if (object.get("compat")) |compat| {
        try writeFieldPrefix(w, &first, "compat");
        try std.json.Stringify.value(compat, .{}, w);
    };
    try w.writeByte('}');
    return out.toOwnedSlice();
}

fn isStandardModelField(name: []const u8) bool {
    const fields = [_][]const u8{
        "id", "name", "api", "provider", "baseUrl", "reasoning", "thinkingLevelMap", "input", "cost", "contextWindow", "maxTokens", "samplingParams", "headers", "compat",
    };
    for (fields) |field| if (std.mem.eql(u8, name, field)) return true;
    return false;
}

fn modelDisplay(registry: *const provider_registry.Registry, provider_id: []const u8, model_id: []const u8) []const u8 {
    for (registry.catalog()) |model| {
        if (std.ascii.eqlIgnoreCase(model.providerName(), provider_id) and std.mem.eql(u8, model.id, model_id)) return model.display;
    }
    return model_id;
}

fn writeFieldPrefix(w: *std.Io.Writer, first: *bool, name: []const u8) !void {
    if (!first.*) try w.writeByte(',');
    first.* = false;
    try std.json.Stringify.value(name, .{}, w);
    try w.writeByte(':');
}

fn writeStringField(w: *std.Io.Writer, first: *bool, name: []const u8, value: []const u8) !void {
    try writeFieldPrefix(w, first, name);
    try std.json.Stringify.value(value, .{}, w);
}

fn writeNumberField(w: *std.Io.Writer, first: *bool, name: []const u8, value: u64) !void {
    try writeFieldPrefix(w, first, name);
    try w.print("{d}", .{value});
}

fn writeHeaders(w: *std.Io.Writer, headers: []const metadata.Header) !void {
    try w.writeByte('{');
    for (headers, 0..) |header, index| {
        if (index > 0) try w.writeByte(',');
        try std.json.Stringify.value(header.name, .{}, w);
        try w.writeByte(':');
        try std.json.Stringify.value(header.value, .{}, w);
    }
    try w.writeByte('}');
}

fn writeSamplingParams(w: *std.Io.Writer, params: []const metadata.SamplingParam) !void {
    try w.writeByte('{');
    for (params, 0..) |param, index| {
        if (index > 0) try w.writeByte(',');
        try std.json.Stringify.value(param.name, .{}, w);
        try w.writeByte(':');
        try w.writeAll(param.value_json);
    }
    try w.writeByte('}');
}

fn writeModelCost(w: *std.Io.Writer, cost: @import("../ai/providers.zig").ModelCost) !void {
    try w.writeAll("{\"input\":");
    try std.json.Stringify.value(cost.input, .{}, w);
    try w.writeAll(",\"output\":");
    try std.json.Stringify.value(cost.output, .{}, w);
    try w.writeAll(",\"cacheRead\":");
    try std.json.Stringify.value(cost.cache_read, .{}, w);
    try w.writeAll(",\"cacheWrite\":");
    try std.json.Stringify.value(cost.cache_write, .{}, w);
    if (cost.tiers.len > 0) {
        try w.writeAll(",\"tiers\":[");
        for (cost.tiers, 0..) |tier, index| {
            if (index > 0) try w.writeByte(',');
            try w.writeAll("{\"inputTokensAbove\":");
            try w.print("{d}", .{tier.input_tokens_above});
            try w.writeAll(",\"input\":");
            try std.json.Stringify.value(tier.input, .{}, w);
            try w.writeAll(",\"output\":");
            try std.json.Stringify.value(tier.output, .{}, w);
            try w.writeAll(",\"cacheRead\":");
            try std.json.Stringify.value(tier.cache_read, .{}, w);
            try w.writeAll(",\"cacheWrite\":");
            try std.json.Stringify.value(tier.cache_write, .{}, w);
            try w.writeByte('}');
        }
        try w.writeByte(']');
    }
    try w.writeByte('}');
}

fn writeThinkingLevelMap(w: *std.Io.Writer, map: thinking_mod.ThinkingLevelMap) !void {
    try w.writeByte('{');
    var first = true;
    inline for (thinking_mod.extended_levels) |level| {
        switch (map.entry(level)) {
            .absent => {},
            .unsupported => {
                try writeFieldPrefix(w, &first, @tagName(level));
                try w.writeAll("null");
            },
            .mapped => |value| {
                try writeFieldPrefix(w, &first, @tagName(level));
                try std.json.Stringify.value(value, .{}, w);
            },
        }
    }
    try w.writeByte('}');
}

fn compatHasFields(compat: metadata.Compat) bool {
    inline for (std.meta.fields(metadata.Compat)) |field| if (@field(compat, field.name) != null) return true;
    return false;
}

fn writeCompat(w: *std.Io.Writer, compat: metadata.Compat) !void {
    try w.writeByte('{');
    var first = true;
    try writeOptionalBool(w, &first, "supportsStore", compat.supports_store);
    try writeOptionalBool(w, &first, "supportsDeveloperRole", compat.supports_developer_role);
    try writeOptionalBool(w, &first, "supportsReasoningEffort", compat.supports_reasoning_effort);
    try writeOptionalBool(w, &first, "supportsUsageInStreaming", compat.supports_usage_in_streaming);
    try writeOptionalBool(w, &first, "supportsFinishReason", compat.supports_finish_reason);
    try writeOptionalBool(w, &first, "zaiToolStream", compat.zai_tool_stream);
    try writeOptionalBool(w, &first, "supportsStrictMode", compat.supports_strict_mode);
    try writeOptionalBool(w, &first, "supportsOpenAIGrammarTools", compat.supports_openai_grammar_tools);
    try writeOptionalBool(w, &first, "supportsToolSearch", compat.supports_tool_search);
    try writeOptionalBool(w, &first, "supportsToolReferences", compat.supports_tool_references);
    try writeOptionalBool(w, &first, "supportsEagerToolInputStreaming", compat.supports_eager_tool_input_streaming);
    try writeOptionalBool(w, &first, "supportsCacheControlOnTools", compat.supports_cache_control_on_tools);
    try writeOptionalBool(w, &first, "supportsTemperature", compat.supports_temperature);
    try writeOptionalBool(w, &first, "forceAdaptiveThinking", compat.force_adaptive_thinking);
    try writeOptionalBool(w, &first, "supportsStrictTools", compat.supports_strict_tools);
    if (compat.deferred_tools_mode) |value| try writeStringField(w, &first, "deferredToolsMode", @tagName(value));
    if (compat.max_tokens_field) |value| try writeStringField(w, &first, "maxTokensField", value.jsonName());
    try writeOptionalBool(w, &first, "requiresToolResultName", compat.requires_tool_result_name);
    try writeOptionalBool(w, &first, "requiresAssistantAfterToolResult", compat.requires_assistant_after_tool_result);
    try writeOptionalBool(w, &first, "requiresThinkingAsText", compat.requires_thinking_as_text);
    try writeOptionalBool(w, &first, "requiresReasoningContentOnAssistantMessages", compat.requires_reasoning_content_on_assistant_messages);
    try writeOptionalBool(w, &first, "allowEmptySignature", compat.allow_empty_signature);
    try writeOptionalBool(w, &first, "supportsLongCacheRetention", compat.supports_long_cache_retention);
    try writeOptionalBool(w, &first, "supportsExplicitPromptCacheMode", compat.supports_explicit_prompt_cache_mode);
    try writeOptionalBool(w, &first, "sendSessionAffinityHeaders", compat.send_session_affinity_headers);
    if (compat.session_affinity_format) |value| {
        const text = switch (value) {
            .openai => "openai",
            .openai_nosession => "openai-nosession",
            .openrouter => "openrouter",
        };
        try writeStringField(w, &first, "sessionAffinityFormat", text);
    }
    if (compat.cache_control_format) |value| try writeStringField(w, &first, "cacheControlFormat", @tagName(value));
    if (compat.thinking_format) |value| {
        const text = switch (value) {
            .chat_template => "chat-template",
            .qwen_chat_template => "qwen-chat-template",
            .string_thinking => "string-thinking",
            .ant_ling => "ant-ling",
            else => @tagName(value),
        };
        try writeStringField(w, &first, "thinkingFormat", text);
    }
    if (compat.chat_template_kwargs) |value| {
        try writeFieldPrefix(w, &first, "chatTemplateKwargs");
        try std.json.Stringify.value(std.json.Value{ .object = value }, .{}, w);
    }
    if (compat.chat_template_args) |value| {
        try writeFieldPrefix(w, &first, "chatTemplateArgs");
        try std.json.Stringify.value(std.json.Value{ .object = value }, .{}, w);
    }
    if (compat.openrouter_routing) |value| {
        try writeFieldPrefix(w, &first, "openRouterRouting");
        try writeOpenRouterRouting(w, value);
    }
    if (compat.vercel_gateway_routing) |value| {
        try writeFieldPrefix(w, &first, "vercelGatewayRouting");
        try writeVercelRouting(w, value);
    }
    try w.writeByte('}');
}

fn writeOptionalBool(w: *std.Io.Writer, first: *bool, name: []const u8, value: ?bool) !void {
    if (value) |present| {
        try writeFieldPrefix(w, first, name);
        try w.writeAll(if (present) "true" else "false");
    }
}

fn writeOpenRouterRouting(w: *std.Io.Writer, value: metadata.OpenRouterRouting) !void {
    try w.writeByte('{');
    var first = true;
    try writeOptionalBool(w, &first, "allowFallbacks", value.allow_fallbacks);
    try writeOptionalBool(w, &first, "requireParameters", value.require_parameters);
    if (value.data_collection) |field| try writeStringField(w, &first, "dataCollection", field);
    try writeOptionalBool(w, &first, "zdr", value.zdr);
    try writeOptionalBool(w, &first, "enforceDistillableText", value.enforce_distillable_text);
    try writeOptionalJsonSlice(w, &first, "order", value.order);
    try writeOptionalJsonSlice(w, &first, "only", value.only);
    try writeOptionalJsonSlice(w, &first, "ignore", value.ignore);
    try writeOptionalJsonSlice(w, &first, "quantizations", value.quantizations);
    if (value.sort) |field| {
        try writeFieldPrefix(w, &first, "sort");
        try std.json.Stringify.value(field, .{}, w);
    }
    if (value.max_price) |field| {
        try writeFieldPrefix(w, &first, "maxPrice");
        try std.json.Stringify.value(std.json.Value{ .object = field }, .{}, w);
    }
    if (value.preferred_min_throughput) |field| {
        try writeFieldPrefix(w, &first, "preferredMinThroughput");
        try std.json.Stringify.value(field, .{}, w);
    }
    if (value.preferred_max_latency) |field| {
        try writeFieldPrefix(w, &first, "preferredMaxLatency");
        try std.json.Stringify.value(field, .{}, w);
    }
    try w.writeByte('}');
}

fn writeVercelRouting(w: *std.Io.Writer, value: metadata.VercelGatewayRouting) !void {
    try w.writeByte('{');
    var first = true;
    try writeOptionalJsonSlice(w, &first, "only", value.only);
    try writeOptionalJsonSlice(w, &first, "order", value.order);
    try w.writeByte('}');
}

fn writeOptionalJsonSlice(w: *std.Io.Writer, first: *bool, name: []const u8, values: ?[]const std.json.Value) !void {
    if (values) |items| {
        try writeFieldPrefix(w, first, name);
        try w.writeByte('[');
        for (items, 0..) |item, index| {
            if (index > 0) try w.writeByte(',');
            try std.json.Stringify.value(item, .{}, w);
        }
        try w.writeByte(']');
    }
}

fn validateProtocolSummary(gpa: std.mem.Allocator, summary_json: []const u8, terminal: ?TerminalKind, reason: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, summary_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidProviderStreamSummary;
    const terminal_text = requiredString(parsed.value.object, "terminal") orelse return error.InvalidProviderStreamSummary;
    const expected = switch (terminal orelse return error.InvalidProviderStreamSummary) {
        .done => "done",
        .err => "error",
    };
    if (!std.mem.eql(u8, terminal_text, expected)) return error.ProviderStreamTerminalMismatch;
    if (requiredString(parsed.value.object, "reason")) |summary_reason| {
        if (!std.mem.eql(u8, summary_reason, reason)) return error.ProviderStreamTerminalMismatch;
    }
}

fn parseAssistantMessage(
    allocator: std.mem.Allocator,
    message_json: []const u8,
    request: live_state.ExtensionStreamRequest,
    terminal_reason: []const u8,
) !ai.ModelResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, message_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidProviderAssistantMessage;
    const object = parsed.value.object;
    const role = requiredString(object, "role") orelse return error.InvalidProviderAssistantMessage;
    if (!std.mem.eql(u8, role, "assistant")) return error.InvalidProviderAssistantMessage;
    const content = object.get("content") orelse return error.InvalidProviderAssistantMessage;
    if (content != .array) return error.InvalidProviderAssistantMessage;

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(allocator);
    var thinking: std.ArrayList(u8) = .empty;
    defer thinking.deinit(allocator);
    var tool_calls: std.ArrayList(ai.ToolCall) = .empty;
    errdefer {
        for (tool_calls.items) |*call| call.deinit(allocator);
        tool_calls.deinit(allocator);
    }
    var thinking_signature: []u8 = &.{};
    errdefer if (thinking_signature.len > 0) allocator.free(thinking_signature);

    for (content.array.items) |item| {
        if (item != .object) return error.InvalidProviderAssistantContent;
        const typ = requiredString(item.object, "type") orelse return error.InvalidProviderAssistantContent;
        if (std.mem.eql(u8, typ, "text")) {
            const value = requiredString(item.object, "text") orelse return error.InvalidProviderAssistantContent;
            try text.appendSlice(allocator, value);
            continue;
        }
        if (std.mem.eql(u8, typ, "thinking")) {
            const value = requiredString(item.object, "thinking") orelse return error.InvalidProviderAssistantContent;
            try thinking.appendSlice(allocator, value);
            if (requiredString(item.object, "thinkingSignature")) |signature| if (signature.len > 0) {
                if (thinking_signature.len > 0) allocator.free(thinking_signature);
                thinking_signature = try allocator.dupe(u8, signature);
            };
            continue;
        }
        if (std.mem.eql(u8, typ, "toolCall")) {
            const id = requiredString(item.object, "id") orelse return error.InvalidProviderAssistantToolCall;
            const name = requiredString(item.object, "name") orelse return error.InvalidProviderAssistantToolCall;
            if (id.len == 0 or name.len == 0) return error.InvalidProviderAssistantToolCall;
            const arguments_value = item.object.get("arguments") orelse return error.InvalidProviderAssistantToolCall;
            if (arguments_value != .object) return error.InvalidProviderAssistantToolCall;
            var arguments_writer: std.Io.Writer.Allocating = .init(allocator);
            errdefer arguments_writer.deinit();
            try std.json.Stringify.value(arguments_value, .{}, &arguments_writer.writer);
            const arguments = try arguments_writer.toOwnedSlice();
            errdefer allocator.free(arguments);
            const signature = requiredString(item.object, "thoughtSignature") orelse "";
            try tool_calls.append(allocator, .{
                .id = try allocator.dupe(u8, id),
                .name = try allocator.dupe(u8, name),
                .arguments = arguments,
                .thought_signature = if (signature.len > 0) try allocator.dupe(u8, signature) else "",
            });
            continue;
        }
        return error.UnsupportedProviderAssistantContent;
    }

    const owned_tools = try tool_calls.toOwnedSlice(allocator);
    errdefer {
        for (owned_tools) |*call| call.deinit(allocator);
        allocator.free(owned_tools);
    }
    const content_text = try text.toOwnedSlice(allocator);
    errdefer allocator.free(content_text);
    const thinking_text = if (thinking.items.len > 0) try thinking.toOwnedSlice(allocator) else "";
    errdefer if (thinking_text.len > 0) allocator.free(thinking_text);

    var response = ai.ModelResponse{
        .content = content_text,
        .thinking = thinking_text,
        .thinking_signature = thinking_signature,
        .tool_calls = owned_tools,
        .provider = try allocator.dupe(u8, requiredString(object, "provider") orelse request.provider_id),
        .api = try allocator.dupe(u8, requiredString(object, "api") orelse request.api),
        .model = try allocator.dupe(u8, requiredString(object, "model") orelse request.model_id),
        .stop_reason = try allocator.dupe(u8, requiredString(object, "stopReason") orelse terminal_reason),
    };
    errdefer response.deinit(allocator);
    if (requiredString(object, "responseId")) |value| {
        if (value.len > 0) response.response_id = try allocator.dupe(u8, value);
    }
    if (requiredString(object, "responseModel")) |value| {
        if (value.len > 0) response.response_model = try allocator.dupe(u8, value);
    }
    if (requiredString(object, "errorMessage")) |value| {
        if (value.len > 0) response.error_message = try allocator.dupe(u8, value);
    }
    if (requiredString(object, "rawStopReason")) |value| {
        if (value.len > 0) response.raw_stop_reason = try allocator.dupe(u8, value);
    }
    if (object.get("diagnostics")) |value| {
        if (value == .array and value.array.items.len > 0) response.diagnostics_json = try stringifyValue(allocator, value);
    }
    if (object.get("usage")) |value| {
        if (value == .object) response.usage = parseUsage(value.object);
    }
    return response;
}

fn parseUsage(object: std.json.ObjectMap) ai.Usage {
    var usage: ai.Usage = .{};
    if (object.get("input")) |value| usage.input = numberToU64(value);
    if (object.get("output")) |value| usage.output = numberToU64(value);
    if (object.get("cacheRead")) |value| usage.cache_read = numberToU64(value);
    if (object.get("cacheWrite")) |value| usage.cache_write = numberToU64(value);
    if (object.get("cacheWrite1h")) |value| usage.cache_write_1h = numberToU64(value);
    if (object.get("reasoning")) |value| usage.reasoning = numberToU64(value);
    if (object.get("totalTokens")) |value| usage.total_tokens = numberToU64(value);
    if (object.get("cost")) |cost| if (cost == .object) {
        if (cost.object.get("input")) |value| usage.cost.input = numberToF64(value);
        if (cost.object.get("output")) |value| usage.cost.output = numberToF64(value);
        if (cost.object.get("cacheRead")) |value| usage.cost.cache_read = numberToF64(value);
        if (cost.object.get("cacheWrite")) |value| usage.cost.cache_write = numberToF64(value);
        if (cost.object.get("total")) |value| usage.cost.total = numberToF64(value);
    };
    if (usage.total_tokens == 0) usage.normalizeTotal();
    return usage;
}

fn numberToU64(value: std.json.Value) u64 {
    return switch (value) {
        .integer => |number| if (number > 0) @intCast(number) else 0,
        .float => |number| if (number > 0) @intFromFloat(number) else 0,
        else => 0,
    };
}

fn numberToF64(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => 0,
    };
}

fn makeFailureResponse(
    allocator: std.mem.Allocator,
    request: live_state.ExtensionStreamRequest,
    state: ?*StreamState,
    message: []const u8,
    aborted: bool,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
) !ai.ModelResponse {
    var response = if (state) |stream_state|
        try stream_state.acc.finish()
    else
        ai.ModelResponse{ .content = try allocator.dupe(u8, ""), .tool_calls = try allocator.alloc(ai.ToolCall, 0) };
    errdefer response.deinit(allocator);
    // Never expose incomplete tool calls from a failed iterator to the agent's
    // execution loop. Text/thinking deltas remain useful diagnostic context.
    for (response.tool_calls) |*call| call.deinit(allocator);
    allocator.free(response.tool_calls);
    response.tool_calls = try allocator.alloc(ai.ToolCall, 0);
    response.provider = try allocator.dupe(u8, request.provider_id);
    response.api = try allocator.dupe(u8, request.api);
    response.model = try allocator.dupe(u8, request.model_id);
    response.stop_reason = try allocator.dupe(u8, if (aborted) "aborted" else "error");
    response.raw_stop_reason = try allocator.dupe(u8, if (aborted) "aborted" else "error");
    if (aborted) {
        if (response.content.len == 0) {
            allocator.free(response.content);
            response.content = try allocator.dupe(u8, "aborted");
        }
    } else {
        response.error_message = try allocator.dupe(u8, message);
        if (response.content.len == 0) {
            allocator.free(response.content);
            response.content = try allocator.dupe(u8, message);
        }
    }
    if (on_delta) |handler| handler(delta_ctx, .{ .kind = .err, .text = if (aborted) "aborted" else message });
    return response;
}

fn manifestProviderConfig(gpa: std.mem.Allocator, manifest_json: []const u8, provider_name: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidJavaScriptExtensionHandshake;
    const providers_value = parsed.value.object.get("providers") orelse return error.InvalidJavaScriptExtensionHandshake;
    if (providers_value != .array) return error.InvalidJavaScriptExtensionHandshake;
    for (providers_value.array.items) |entry| {
        if (entry != .object) continue;
        const name = requiredString(entry.object, "name") orelse continue;
        if (!std.mem.eql(u8, name, provider_name)) continue;
        const config = entry.object.get("config") orelse return error.InvalidJavaScriptExtensionHandshake;
        return stringifyValue(gpa, config);
    }
    return error.ExtensionProviderNotRegistered;
}

test "extension stream adapter selects a live ModelClient and defers terminal delivery" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { createAssistantMessageEventStream } from '@mariozechner/pi-ai';
        \\const usage = { input: 5, output: 7, cacheRead: 1, cacheWrite: 2, totalTokens: 15, cost: { input: 0.1, output: 0.2, cacheRead: 0.01, cacheWrite: 0.02, total: 0.33 } };
        \\const message = (content, stopReason = 'pending') => ({ role: 'assistant', content, api: 'openai-completions', provider: 'native-stream', model: 'stream-model', usage, stopReason, responseId: 'response-185', timestamp: 185 });
        \\export default function(pi) {
        \\  pi.registerProvider('native-stream', {
        \\    name: 'Native Stream', api: 'openai-completions', baseUrl: 'https://stream.invalid/v1', apiKey: 'extension-key', headers: { 'x-stream': 'yes' },
        \\    models: [{ id: 'stream-model', name: 'Stream Display', reasoning: true, input: ['text', 'image'], cost: { input: 1, output: 2, cacheRead: 0.1, cacheWrite: 0.2 }, contextWindow: 8192, maxTokens: 1024, samplingParams: { top_p: 0.8 } }],
        \\    streamSimple(model, context, options) {
        \\      if (model.name !== 'Stream Display' || model.contextWindow !== 8192 || model.input[1] !== 'image') throw new Error('bad model projection');
        \\      if (context.systemPrompt !== 'system' || context.tools[0].name !== 'probe') throw new Error('bad context projection');
        \\      if (options.apiKey !== 'extension-key' || options.reasoning !== 'high' || options.maxTokens !== 1024 || options.headers['x-stream'] !== 'yes' || options.samplingParams.top_p !== 0.8) throw new Error('bad options projection');
        \\      const mode = context.messages[0].content;
        \\      const partial = message([]);
        \\      if (mode === 'terminal-throw') return (async function*() {
        \\        yield { type: 'start', partial };
        \\        yield { type: 'text_start', contentIndex: 0, partial };
        \\        yield { type: 'text_delta', contentIndex: 0, delta: 'partial-before-throw', partial };
        \\        yield { type: 'text_end', contentIndex: 0, content: 'partial-before-throw', partial };
        \\        yield { type: 'done', reason: 'stop', message: message([{ type: 'text', text: 'partial-before-throw' }], 'stop') };
        \\        throw new Error('provider-terminal-after-185');
        \\      })();
        \\      if (mode === 'abort') return (async function*() {
        \\        yield { type: 'start', partial };
        \\        yield { type: 'text_start', contentIndex: 0, partial };
        \\        yield { type: 'text_delta', contentIndex: 0, delta: 'partial-before-abort', partial };
        \\        await new Promise((resolve, reject) => {
        \\          if (options.signal.aborted) return reject(options.signal.reason);
        \\          options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true });
        \\        });
        \\      })();
        \\      if (mode === 'unicode') {
        \\        const stream = createAssistantMessageEventStream();
        \\        stream.push({ type: 'start', partial });
        \\        stream.push({ type: 'thinking_start', contentIndex: 0, partial });
        \\        stream.push({ type: 'text_start', contentIndex: 1, partial });
        \\        stream.push({ type: 'text_delta', contentIndex: 1, delta: 'A\uD83D', partial });
        \\        stream.push({ type: 'thinking_delta', contentIndex: 0, delta: 'plan', partial });
        \\        stream.push({ type: 'text_delta', contentIndex: 1, delta: '\uDE80B', partial });
        \\        stream.push({ type: 'thinking_end', contentIndex: 0, content: 'plan', partial });
        \\        stream.push({ type: 'text_end', contentIndex: 1, content: 'A🚀B', partial });
        \\        stream.push({ type: 'toolcall_start', contentIndex: 2, partial });
        \\        stream.push({ type: 'toolcall_delta', contentIndex: 2, delta: '{"b":2,"a":1}', partial });
        \\        const call = { type: 'toolCall', id: 'unicode-call-185', name: 'probe', arguments: { a: 1, b: 2 } };
        \\        stream.push({ type: 'toolcall_end', contentIndex: 2, toolCall: call, partial });
        \\        stream.push({ type: 'done', reason: 'toolUse', message: message([{ type: 'thinking', thinking: 'plan', thinkingSignature: 'unicode-sig-185' }, { type: 'text', text: 'A🚀B' }, call], 'toolUse') });
        \\        return stream;
        \\      }
        \\      if (mode !== 'hello') throw new Error(`unexpected stream mode: ${mode}`);
        \\      const stream = createAssistantMessageEventStream();
        \\      stream.push({ type: 'start', partial });
        \\      stream.push({ type: 'text_start', contentIndex: 0, partial });
        \\      stream.push({ type: 'text_delta', contentIndex: 0, delta: 'hello ', partial });
        \\      stream.push({ type: 'thinking_start', contentIndex: 1, partial });
        \\      stream.push({ type: 'thinking_delta', contentIndex: 1, delta: 'plan', partial });
        \\      stream.push({ type: 'thinking_end', contentIndex: 1, content: 'plan', partial });
        \\      stream.push({ type: 'text_delta', contentIndex: 0, delta: 'world', partial });
        \\      stream.push({ type: 'text_end', contentIndex: 0, content: 'hello world', partial });
        \\      stream.push({ type: 'toolcall_start', contentIndex: 2, partial });
        \\      stream.push({ type: 'toolcall_delta', contentIndex: 2, delta: '{\"path\":\"a.txt\"}', partial });
        \\      const call = { type: 'toolCall', id: 'call-185', name: 'probe', arguments: { path: 'a.txt' } };
        \\      stream.push({ type: 'toolcall_end', contentIndex: 2, toolCall: call, partial });
        \\      stream.push({ type: 'done', reason: 'toolUse', message: message([{ type: 'text', text: 'hello world' }, { type: 'thinking', thinking: 'plan', thinkingSignature: 'sig-185' }, call], 'toolUse') });
        \\      return stream;
        \\    },
        \\    fetchDeferred(model, handle, options) {
        \\      if (model.id !== 'stream-model' || handle.id !== 'job-186' || options.wait !== 25 || !(options.signal instanceof AbortSignal)) throw new Error('bad deferred fetch projection');
        \\      const stream = createAssistantMessageEventStream();
        \\      const partial = message([]);
        \\      stream.push({ type: 'start', partial });
        \\      stream.push({ type: 'text_start', contentIndex: 0, partial });
        \\      stream.push({ type: 'text_delta', contentIndex: 0, delta: 'deferred-ready', partial });
        \\      stream.push({ type: 'text_end', contentIndex: 0, content: 'deferred-ready', partial });
        \\      stream.push({ type: 'done', reason: 'stop', message: message([{ type: 'text', text: 'deferred-ready' }], 'stop') });
        \\      return stream;
        \\    },
        \\    async cancelDeferred(model, handle, options) {
        \\      if (model.id !== 'stream-model' || handle.id !== 'job-186' || options.reason !== 'user' || !(options.signal instanceof AbortSignal)) throw new Error('bad deferred cancel projection');
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "native-stream.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "native-stream.mjs" });
    defer gpa.free(path);

    var started = try js_runtime.Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config_json = try manifestProviderConfig(gpa, started.manifest_json, "native-stream");
    defer gpa.free(config_json);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = provider_registry.Registry.init(gpa, io, &env, null, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("native-stream", config_json, started.runtime);
    try std.testing.expectEqual(@as(usize, 1), registry.runtimes().len);
    try std.testing.expectEqualStrings("stream-model", registry.runtimes()[0].model_id.?);
    try std.testing.expectEqual(@as(usize, 1), registry.runtimes()[0].sampling_params.len);
    try std.testing.expectEqualStrings("top_p", registry.runtimes()[0].sampling_params[0].name);
    try std.testing.expectEqualStrings("0.8", registry.runtimes()[0].sampling_params[0].value_json);
    var runtime = Runtime.init(gpa, &registry);
    var pool: live_state.ClientPool = .{ .gpa = gpa, .io = io };
    defer pool.deinit();
    pool.setRuntimeProviders(registry.runtimes());
    pool.setExtensionStreamBridge(runtime.bridge());
    pool.setThinking(.high);
    try pool.switchToIdentity("native-stream", .openai, "stream-model");

    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "hello" },
    };
    const tools = "[{\"type\":\"function\",\"function\":{\"name\":\"probe\",\"description\":\"probe\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";
    const DeltaLog = struct {
        text: std.ArrayList(u8) = .empty,
        thinking: std.ArrayList(u8) = .empty,
        tool_arguments: std.ArrayList(u8) = .empty,
        terminal_count: usize = 0,
        fn onDelta(raw: ?*anyopaque, delta: ai.StreamDelta) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            switch (delta.kind) {
                .text_delta => self.text.appendSlice(std.testing.allocator, delta.text) catch unreachable,
                .thinking_delta => self.thinking.appendSlice(std.testing.allocator, delta.thinking) catch unreachable,
                .tool_call_delta => self.tool_arguments.appendSlice(std.testing.allocator, delta.tool_arguments) catch unreachable,
                .done, .err => self.terminal_count += 1,
            }
        }
        fn deinit(self: *@This()) void {
            self.text.deinit(std.testing.allocator);
            self.thinking.deinit(std.testing.allocator);
            self.tool_arguments.deinit(std.testing.allocator);
        }
    };
    var log: DeltaLog = .{};
    defer log.deinit();
    var response = try pool.client.completeStreaming(gpa, &messages, tools, DeltaLog.onDelta, &log);
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("hello world", response.content);
    try std.testing.expectEqualStrings("plan", response.thinking);
    try std.testing.expectEqualStrings("sig-185", response.thinking_signature);
    try std.testing.expectEqualStrings("toolUse", response.stop_reason);
    try std.testing.expectEqualStrings("response-185", response.response_id);
    try std.testing.expectEqual(@as(usize, 1), response.tool_calls.len);
    try std.testing.expectEqualStrings("call-185", response.tool_calls[0].id);
    try std.testing.expectEqualStrings("probe", response.tool_calls[0].name);
    try std.testing.expectEqualStrings("{\"path\":\"a.txt\"}", response.tool_calls[0].arguments);
    try std.testing.expectEqualStrings("hello world", log.text.items);
    try std.testing.expectEqualStrings("plan", log.thinking.items);
    try std.testing.expectEqualStrings("{\"path\":\"a.txt\"}", log.tool_arguments.items);
    try std.testing.expectEqual(@as(usize, 1), log.terminal_count);

    try std.testing.expect(pool.client.fetchDeferredFn != null);
    try std.testing.expect(pool.client.cancelDeferredFn != null);
    var deferred_log: DeltaLog = .{};
    defer deferred_log.deinit();
    var deferred_response = try pool.client.fetchDeferred(
        gpa,
        "{\"id\":\"job-186\"}",
        "{\"wait\":25}",
        DeltaLog.onDelta,
        &deferred_log,
    );
    defer deferred_response.deinit(gpa);
    try std.testing.expectEqualStrings("deferred-ready", deferred_response.content);
    try std.testing.expectEqualStrings("stop", deferred_response.stop_reason);
    try std.testing.expectEqualStrings("deferred-ready", deferred_log.text.items);
    try std.testing.expectEqual(@as(usize, 1), deferred_log.terminal_count);
    try pool.client.cancelDeferred("{\"id\":\"job-186\"}", "{\"reason\":\"user\"}");

    // Real JavaScript UTF-16 halves may arrive in separate delta events. Keep
    // the pending high surrogate inside the worker until the low half arrives,
    // while independently tracking out-of-order content indices and comparing
    // tool arguments semantically rather than by object key order.
    const unicode_messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "unicode" },
    };
    var unicode_log: DeltaLog = .{};
    defer unicode_log.deinit();
    var unicode_response = try pool.client.completeStreaming(gpa, &unicode_messages, tools, DeltaLog.onDelta, &unicode_log);
    defer unicode_response.deinit(gpa);
    try std.testing.expectEqualStrings("A🚀B", unicode_response.content);
    try std.testing.expectEqualStrings("plan", unicode_response.thinking);
    try std.testing.expectEqualStrings("unicode-sig-185", unicode_response.thinking_signature);
    try std.testing.expectEqualStrings("toolUse", unicode_response.stop_reason);
    try std.testing.expectEqual(@as(usize, 1), unicode_response.tool_calls.len);
    try std.testing.expectEqualStrings("unicode-call-185", unicode_response.tool_calls[0].id);
    try std.testing.expectEqualStrings("{\"a\":1,\"b\":2}", unicode_response.tool_calls[0].arguments);
    try std.testing.expectEqualStrings("A🚀B", unicode_log.text.items);
    try std.testing.expectEqualStrings("plan", unicode_log.thinking.items);
    try std.testing.expectEqualStrings("{\"b\":2,\"a\":1}", unicode_log.tool_arguments.items);
    try std.testing.expectEqual(@as(usize, 1), unicode_log.terminal_count);

    // A terminal event is not delivered to the caller until iterator.next()
    // confirms completion. A provider that throws after yielding done therefore
    // becomes one error response with the already-observed partial text.
    const terminal_messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "terminal-throw" },
    };
    var terminal_log: DeltaLog = .{};
    defer terminal_log.deinit();
    var terminal_response = try pool.client.completeStreaming(gpa, &terminal_messages, tools, DeltaLog.onDelta, &terminal_log);
    defer terminal_response.deinit(gpa);
    try std.testing.expectEqualStrings("partial-before-throw", terminal_response.content);
    try std.testing.expectEqualStrings("error", terminal_response.stop_reason);
    try std.testing.expect(std.mem.indexOf(u8, terminal_response.error_message, "provider-terminal-after-185") != null);
    try std.testing.expectEqualStrings("partial-before-throw", terminal_log.text.items);
    try std.testing.expectEqual(@as(usize, 1), terminal_log.terminal_count);

    // Cancellation races a blocked iterator.next(), preserves prior text, emits
    // exactly one error terminal, and leaves the persistent worker reusable.
    const AbortTask = struct {
        fn run(task_io: std.Io, flag: *bool) std.Io.Cancelable!void {
            const pause: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(40), .clock = .awake } };
            try pause.sleep(task_io);
            @atomicStore(bool, flag, true, .release);
        }
    };
    var abort_flag = false;
    pool.setAbortFlag(&abort_flag);
    var group: std.Io.Group = .init;
    group.async(io, AbortTask.run, .{ io, &abort_flag });
    const abort_messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "abort" },
    };
    var abort_log: DeltaLog = .{};
    defer abort_log.deinit();
    var abort_response = try pool.client.completeStreaming(gpa, &abort_messages, tools, DeltaLog.onDelta, &abort_log);
    defer abort_response.deinit(gpa);
    try group.await(io);
    try std.testing.expectEqualStrings("partial-before-abort", abort_response.content);
    try std.testing.expectEqualStrings("aborted", abort_response.stop_reason);
    try std.testing.expectEqualStrings("partial-before-abort", abort_log.text.items);
    try std.testing.expectEqual(@as(usize, 1), abort_log.terminal_count);

    @atomicStore(bool, &abort_flag, false, .release);
    var reused_log: DeltaLog = .{};
    defer reused_log.deinit();
    var reused_response = try pool.client.completeStreaming(gpa, &messages, tools, DeltaLog.onDelta, &reused_log);
    defer reused_response.deinit(gpa);
    try std.testing.expectEqualStrings("hello world", reused_response.content);
    try std.testing.expectEqualStrings("toolUse", reused_response.stop_reason);
    try std.testing.expectEqual(@as(usize, 1), reused_log.terminal_count);
}

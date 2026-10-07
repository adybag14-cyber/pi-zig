//! Native SDK OpenAI-compatible HTTP/SSE adapter. Worker callbacks own only
//! native deltas; the VM owner publishes every JavaScript stream event.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const chat = @import("native_sdk_chat.zig");
const engine_mod = @import("engine.zig");
const ai = @import("../ai/root.zig");
const metadata = @import("../ai/request_metadata.zig");
const c = engine_mod.c;

pub fn install(engine: *engine_mod.Engine, provider: c.JSValue) !void {
    try sdk.put(engine, provider, "streamSimple", try engine.checked(c.pi_js_function_magic(engine.context, callback, "streamSimple", 3, 0)));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (argc < 2) return sdk.fail(engine, error.NativeSDKMissingArgument);
    return enqueue(engine, args[0], args[1], if (argc > 2) args[2] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn enqueue(engine: *engine_mod.Engine, model: c.JSValue, context: c.JSValue, options: c.JSValue) !c.JSValue {
    const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
    const output = try sdk.invoke(engine, exports, "createAssistantMessageEventStream", &.{});
    errdefer engine.freeValue(output);
    var task = [_]c.JSValue{ model, context, options, output };
    if (c.JS_EnqueueJob(engine.context, job, task.len, &task) < 0) return error.OutOfMemory;
    return output;
}
fn job(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    execute(engine, args[0], args[1], args[2], args[3]) catch |err| {
        chat.finishError(engine, args[0], args[3], err) catch |failure| return chat.retireFailure(engine, args[3], failure);
    };
    return c.pi_js_undefined();
}

const Delta = struct {
    value: ai.StreamDelta,
    fn init(gpa: std.mem.Allocator, value: ai.StreamDelta) !Delta {
        var result = value;
        result.text = try gpa.dupe(u8, value.text);
        errdefer gpa.free(result.text);
        result.thinking = try gpa.dupe(u8, value.thinking);
        errdefer gpa.free(result.thinking);
        result.tool_call_id = try gpa.dupe(u8, value.tool_call_id);
        errdefer gpa.free(result.tool_call_id);
        result.tool_name = try gpa.dupe(u8, value.tool_name);
        errdefer gpa.free(result.tool_name);
        result.tool_arguments = try gpa.dupe(u8, value.tool_arguments);
        return .{ .value = result };
    }
    fn deinit(self: *Delta, gpa: std.mem.Allocator) void {
        inline for (.{ "text", "thinking", "tool_call_id", "tool_name", "tool_arguments" }) |field| gpa.free(@field(self.value, field));
    }
};
const Work = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    client: *ai.openai.OpenAIClient,
    messages: []const ai.ChatMessage,
    tools: []const u8,
    mutex: std.Io.Mutex = .init,
    deltas: std.ArrayList(Delta) = .empty,
    failure: ?anyerror = null,
    queued_bytes: usize = 0,
    done: std.atomic.Value(bool) = .init(false),
    aborted: bool = false,
    fn run(self: *Work) anyerror!ai.ModelResponse {
        defer self.done.store(true, .release);
        return self.client.client().completeStreaming(self.gpa, self.messages, self.tools, onDelta, self);
    }
    fn onDelta(pointer: ?*anyopaque, value: ai.StreamDelta) void {
        const self: *Work = @ptrCast(@alignCast(pointer.?));
        if (value.kind == .done or value.kind == .err) return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure != null) return;
        const bytes = value.text.len + value.thinking.len + value.tool_call_id.len + value.tool_name.len + value.tool_arguments.len;
        if (self.deltas.items.len >= 65536 or bytes > 16 * 1024 * 1024 -| self.queued_bytes) {
            self.failure = error.NativeSDKStreamLimit;
            @atomicStore(bool, &self.aborted, true, .release);
            return;
        }
        var delta = Delta.init(self.gpa, value) catch |err| {
            self.failure = err;
            @atomicStore(bool, &self.aborted, true, .release);
            return;
        };
        self.deltas.append(self.gpa, delta) catch |err| {
            delta.deinit(self.gpa);
            self.failure = err;
            @atomicStore(bool, &self.aborted, true, .release);
            return;
        };
        self.queued_bytes += bytes;
    }
    fn take(self: *Work) ?Delta {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.deltas.items.len == 0) return null;
        const delta = self.deltas.orderedRemove(0);
        self.queued_bytes -= delta.value.text.len + delta.value.thinking.len + delta.value.tool_call_id.len + delta.value.tool_name.len + delta.value.tool_arguments.len;
        return delta;
    }
    fn deinit(self: *Work) void {
        for (self.deltas.items) |*value| value.deinit(self.gpa);
        self.deltas.deinit(self.gpa);
    }
};

fn execute(engine: *engine_mod.Engine, model: c.JSValue, context: c.JSValue, options: c.JSValue, output: c.JSValue) !void {
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const raw_model = try engine.stringify(model);
    defer engine.gpa.free(raw_model);
    const raw_context = try engine.stringify(context);
    defer engine.gpa.free(raw_context);
    const raw_options = try engine.stringify(options);
    defer engine.gpa.free(raw_options);
    const info = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_model, .{});
    const input = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_context, .{});
    const config = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_options, .{});
    if (info != .object or input != .object or config != .object) return error.NativeSDKInvalidModelRequest;
    const api = string(info.object, "api") orelse return error.NativeSDKInvalidModelRequest;
    if (!std.mem.eql(u8, api, "openai-completions")) return error.NativeSDKChatApiNotImplemented;
    const id = string(info.object, "id") orelse return error.NativeSDKInvalidModelRequest;
    const provider = string(info.object, "provider") orelse return error.NativeSDKInvalidModelRequest;
    const base = string(info.object, "baseUrl") orelse return error.NativeSDKMissingBaseUrl;
    const key = string(config.object, "apiKey") orelse "";
    var headers: std.ArrayList(metadata.Header) = .empty;
    if (config.object.get("headers")) |fields| if (fields == .object) {
        var iterator = fields.object.iterator();
        while (iterator.next()) |field| if (field.value_ptr.* == .string) try headers.append(allocator, .{ .name = field.key_ptr.*, .value = field.value_ptr.string });
    };
    var client: ai.openai.OpenAIClient = .{ .gpa = engine.gpa, .io = io, .api_key = key, .base_url = base, .provider_id = provider, .api_id = api, .model = id, .custom_headers = headers.items };
    client.max_tokens = integer(info.object, "maxTokens") orelse 0;
    client.context_window = integer(info.object, "contextWindow") orelse 0;
    client.reasoning = boolean(info.object, "reasoning");
    client.compat = metadata.detectOpenAICompat(provider, base, id);
    client.compat.supports_developer_role = client.reasoning and client.compat.supports_developer_role == true;
    if (info.object.get("cost")) |cost| if (cost == .object) {
        client.model_cost = .{ .input = number(cost.object.get("input") orelse .null) orelse 0, .output = number(cost.object.get("output") orelse .null) orelse 0, .cache_read = number(cost.object.get("cacheRead") orelse .null) orelse 0, .cache_write = number(cost.object.get("cacheWrite") orelse .null) orelse 0 };
    };
    if (integer(config.object, "maxRetries")) |count| client.provider_retry.max_retries = @intCast(count);
    if (integer(config.object, "maxTokens")) |count| client.max_tokens = count;
    var messages: std.ArrayList(ai.ChatMessage) = .empty;
    var section_prompt: ?[]const u8 = null;
    if (input.object.get("messages")) |rows| if (rows == .array) for (rows.array.items) |row| {
        if (row != .object) continue;
        const role = string(row.object, "role") orelse continue;
        if (!std.mem.eql(u8, role, "system")) continue;
        if (row.object.get("sections")) |sections| if (sections == .object) {
            var combined: std.ArrayList(u8) = .empty;
            var iterator = sections.object.iterator();
            while (iterator.next()) |field| if (field.value_ptr.* == .string and field.value_ptr.string.len != 0) {
                if (combined.items.len != 0) try combined.appendSlice(allocator, "\n\n");
                try combined.appendSlice(allocator, field.value_ptr.string);
            };
            section_prompt = combined.items;
        };
    };
    const system = section_prompt orelse string(input.object, "systemPrompt") orelse "";
    if (system.len != 0) try messages.append(allocator, .{ .role = "system", .content = system });
    if (input.object.get("messages")) |rows| if (rows == .array) for (rows.array.items) |row| {
        if (row != .object) return error.NativeSDKInvalidChatContext;
        const role = string(row.object, "role") orelse return error.NativeSDKInvalidChatContext;
        const content = row.object.get("content") orelse .null;
        const text = try contentText(allocator, content);
        if (std.mem.eql(u8, role, "system") and text.len == 0) continue;
        try messages.append(allocator, .{ .role = if (std.mem.eql(u8, role, "toolResult")) "tool" else role, .content = text, .content_as_array = content == .array and std.mem.eql(u8, role, "user"), .tool_call_id = string(row.object, "toolCallId"), .tool_name = string(row.object, "toolName") });
    };
    const tools = if (input.object.get("tools")) |rows| try std.json.Stringify.valueAlloc(allocator, rows, .{}) else "[]";
    const partial = try initialMessage(engine, model);
    defer engine.freeValue(partial);
    try publish(engine, output, "start", partial, null, null);
    var work: Work = .{ .io = io, .gpa = engine.gpa, .client = &client, .messages = messages.items, .tools = tools };
    defer work.deinit();
    client.abort_flag = &work.aborted;
    var future = try io.concurrent(Work.run, .{&work});
    var consumed = false;
    errdefer if (!consumed) {
        @atomicStore(bool, &work.aborted, true, .release);
        if (future.cancel(io)) |value| {
            var owned = value;
            owned.deinit(engine.gpa);
        } else |_| {}
    };
    const signal = try sdk.get(engine, options, "signal");
    defer engine.freeValue(signal);
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(engine.gpa);
    var text_started = false;
    while (!work.done.load(.acquire)) {
        try drain(engine, &work, output, partial, &content, &text_started);
        if (c.JS_IsObject(signal)) {
            const aborted = try sdk.get(engine, signal, "aborted");
            defer engine.freeValue(aborted);
            if (c.JS_ToBool(engine.context, aborted) == 1) {
                @atomicStore(bool, &work.aborted, true, .release);
                consumed = true;
                if (future.cancel(io)) |value| {
                    var cancelled = value;
                    cancelled.deinit(engine.gpa);
                } else |err| switch (err) {
                    error.Canceled => {},
                    else => return err,
                }
                try abortResult(engine, options, output, partial);
                return;
            }
        }
        if (engine.host_await_deadline_ms) |deadline| if (std.Io.Clock.awake.now(io).toMilliseconds() >= deadline) return error.NativeHostPromiseTimeout;
        _ = try @import("timers.zig").pumpReady(engine);
        _ = try engine.drainReadyJobs();
        if (!work.done.load(.acquire)) try io.sleep(.fromMilliseconds(1), .awake);
    }
    consumed = true;
    var response = try future.await(io);
    defer response.deinit(engine.gpa);
    if (work.failure) |err| return err;
    try drain(engine, &work, output, partial, &content, &text_started);
    try complete(engine, model, options, output, partial, response, &content, text_started);
}
fn drain(engine: *engine_mod.Engine, work: *Work, output: c.JSValue, partial: c.JSValue, content: *std.ArrayList(u8), started: *bool) !void {
    while (work.take()) |item| {
        var delta = item;
        defer delta.deinit(engine.gpa);
        if (delta.value.kind != .text_delta) return error.NativeSDKChatContentNotImplemented;
        try content.appendSlice(engine.gpa, delta.value.text);
        try setContent(engine, partial, content.items);
        if (!started.*) {
            try publish(engine, output, "text_start", partial, null, null);
            started.* = true;
        }
        try publish(engine, output, "text_delta", partial, delta.value.text, null);
    }
}
fn initialMessage(engine: *engine_mod.Engine, model: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "role", try sdk.text(engine, "assistant"));
    try sdk.put(engine, result, "content", try sdk.array(engine));
    inline for (.{ .{ "api", "api" }, .{ "provider", "provider" }, .{ "model", "id" } }) |field| try sdk.put(engine, result, field[0], try sdk.get(engine, model, field[1]));
    try sdk.put(engine, result, "usage", try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"));
    try sdk.put(engine, result, "stopReason", try sdk.text(engine, "pending"));
    try sdk.put(engine, result, "timestamp", c.JS_NewInt64(engine.context, if (engine.native_io) |io| std.Io.Clock.real.now(io).toMilliseconds() else 0));
    return result;
}
fn setContent(engine: *engine_mod.Engine, message: c.JSValue, text: []const u8) !void {
    const array = try sdk.array(engine);
    defer engine.freeValue(array);
    if (text.len == 0) {
        try sdk.put(engine, message, "content", c.JS_DupValue(engine.context, array));
        return;
    }
    const block = try sdk.object(engine);
    defer engine.freeValue(block);
    try sdk.put(engine, block, "type", try sdk.text(engine, "text"));
    try sdk.put(engine, block, "text", try sdk.text(engine, text));
    try sdk.append(engine, array, c.JS_DupValue(engine.context, block));
    try sdk.put(engine, message, "content", c.JS_DupValue(engine.context, array));
}
fn abortResult(engine: *engine_mod.Engine, options: c.JSValue, output: c.JSValue, partial: c.JSValue) !void {
    try sdk.put(engine, partial, "stopReason", try sdk.text(engine, "aborted"));
    try sdk.put(engine, partial, "errorMessage", try sdk.text(engine, "Request aborted"));
    const thinking = try sdk.get(engine, options, "reasoning");
    defer engine.freeValue(thinking);
    if (!c.JS_IsUndefined(thinking)) try sdk.put(engine, partial, "thinkingLevel", c.JS_DupValue(engine.context, thinking));
    try publish(engine, output, "error", partial, null, "aborted");
    const ended = try sdk.invoke(engine, output, "end", &.{});
    engine.freeValue(ended);
}
fn publish(engine: *engine_mod.Engine, output: c.JSValue, kind: []const u8, partial: c.JSValue, delta: ?[]const u8, reason: ?[]const u8) !void {
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, kind));
    if (reason) |value| {
        try sdk.put(engine, event, "reason", try sdk.text(engine, value));
        try sdk.put(engine, event, if (std.mem.eql(u8, kind, "done")) "message" else "error", c.JS_DupValue(engine.context, partial));
    } else {
        try sdk.put(engine, event, "partial", c.JS_DupValue(engine.context, partial));
        if (!std.mem.eql(u8, kind, "start")) try sdk.put(engine, event, "contentIndex", c.pi_js_int32(engine.context, 0));
    }
    if (delta) |value| try sdk.put(engine, event, if (std.mem.eql(u8, kind, "text_end")) "content" else "delta", try sdk.text(engine, value));
    const result = try sdk.invoke(engine, output, "push", &.{event});
    engine.freeValue(result);
}
fn complete(engine: *engine_mod.Engine, _: c.JSValue, options: c.JSValue, output: c.JSValue, partial: c.JSValue, response: ai.ModelResponse, _: *std.ArrayList(u8), started: bool) !void {
    try setContent(engine, partial, response.content);
    var raw_usage: std.json.ObjectMap = .empty;
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    inline for (.{ .{ "input", response.usage.input }, .{ "output", response.usage.output }, .{ "cacheRead", response.usage.cache_read }, .{ "cacheWrite", response.usage.cache_write }, .{ "reasoning", response.usage.reasoning orelse 0 }, .{ "totalTokens", response.usage.total() } }) |field| try raw_usage.put(allocator, field[0], .{ .integer = @intCast(field[1]) });
    var cost: std.json.ObjectMap = .empty;
    inline for (.{ .{ "input", response.usage.cost.input }, .{ "output", response.usage.cost.output }, .{ "cacheRead", response.usage.cost.cache_read }, .{ "cacheWrite", response.usage.cost.cache_write }, .{ "total", response.usage.cost.total } }) |field| try cost.put(allocator, field[0], .{ .float = field[1] });
    try raw_usage.put(allocator, "cost", .{ .object = cost });
    try sdk.put(engine, partial, "usage", try engine.fromJsonValue(.{ .object = raw_usage }));
    const stop = if (response.stop_reason.len != 0) response.stop_reason else "stop";
    try sdk.put(engine, partial, "stopReason", try sdk.text(engine, stop));
    if (response.response_id.len != 0) try sdk.put(engine, partial, "responseId", try sdk.text(engine, response.response_id));
    if (response.response_model.len != 0) try sdk.put(engine, partial, "responseModel", try sdk.text(engine, response.response_model));
    if (response.raw_stop_reason.len != 0) try sdk.put(engine, partial, "rawStopReason", try sdk.text(engine, response.raw_stop_reason));
    if (response.error_message.len != 0) try sdk.put(engine, partial, "errorMessage", try sdk.text(engine, response.error_message));
    const thinking = try sdk.get(engine, options, "reasoning");
    defer engine.freeValue(thinking);
    if (!c.JS_IsUndefined(thinking)) try sdk.put(engine, partial, "thinkingLevel", c.JS_DupValue(engine.context, thinking));
    if (started) try publish(engine, output, "text_end", partial, response.content, null);
    const failed = std.mem.eql(u8, stop, "error") or std.mem.eql(u8, stop, "aborted");
    try publish(engine, output, if (failed) "error" else "done", partial, null, stop);
    const result = try sdk.invoke(engine, output, "end", &.{});
    engine.freeValue(result);
}
fn contentText(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
    if (value == .string) return value.string;
    if (value != .array) return "";
    var result: std.ArrayList(u8) = .empty;
    for (value.array.items) |block| if (block == .object) {
        if (string(block.object, "text")) |text| try result.appendSlice(allocator, text);
    };
    return result.items;
}
fn string(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return if (value == .string) value.string else null;
}
fn number(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => null,
    };
}
fn integer(object: std.json.ObjectMap, key: []const u8) ?u64 {
    const value = object.get(key) orelse return null;
    return if (value == .integer and value.integer >= 0) @intCast(value.integer) else null;
}
fn boolean(object: std.json.ObjectMap, key: []const u8) bool {
    const value = object.get(key) orelse return false;
    return value == .bool and value.bool;
}

test "SDK worker deltas own every fragment and release each failed allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var owned = try Delta.init(gpa, .{ .kind = .tool_call_delta, .text = "text", .thinking = "thought", .tool_call_id = "call", .tool_name = "tool", .tool_arguments = "{\"value\":1}" });
            defer owned.deinit(gpa);
            var queued: std.ArrayList(Delta) = .empty;
            defer queued.deinit(gpa);
            try queued.append(gpa, owned);
            try std.testing.expectEqualStrings("call", queued.items[0].value.tool_call_id);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

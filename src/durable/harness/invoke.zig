//! Native tool invocation lifetime, schema admission  and  bounded output result.
const std = @import("std");
const registry = @import("registry.zig");
const json = registry.json;
const core_tools = @import("../../agent/tools.zig");
const schema_policy = @import("schema.zig");
const types = @import("../types.zig");
const output = @import("../output_window.zig");
const values = @import("../tool_types.zig");
const session_module = @import("../session.zig");
pub const ProgressOptions = struct { partialIntervalMs: ?u64 = null, outputIntervalMs: ?u64 = null };
pub fn resolveProgress(options: ProgressOptions) types.ProgressPolicy {
    return .{ .partialIntervalMs = options.partialIntervalMs orelse 100, .outputIntervalMs = options.outputIntervalMs orelse 100 };
}
pub const Api = struct {
    gpa: std.mem.Allocator,
    owned: json.Owned,
    buffer: output.OutputBuffer,
    reported: values.ToolResult = .{},
    detailsValue: ?json.Value = null,
    active: bool = true,
    refs: std.atomic.Value(usize) = .init(1),
    session: ?*session_module.Session = null,
    scope: session_module.Scope = .{},
    gate: output.ProgressGate = .{},
    outputIntervalMs: u64 = 100,
    ownerThread: std.Thread.Id,
    fn create(gpa: std.mem.Allocator, limits: output.Limits, settings: ProgressOptions, session: ?*session_module.Session, scope: session_module.Scope) !*Api {
        const self = try gpa.create(Api);
        errdefer gpa.destroy(self);
        const owned = try json.Owned.empty(gpa);
        const progress = resolveProgress(settings);
        self.* = .{ .gpa = gpa, .owned = owned, .buffer = output.OutputBuffer.init(gpa, limits), .session = session, .scope = scope, .gate = .{ .minIntervalMs = progress.outputIntervalMs }, .outputIntervalMs = progress.outputIntervalMs, .ownerThread = std.Thread.getCurrentId() };
        return self;
    }
    pub fn retain(self: *Api) *Api {
        _ = self.refs.fetchAdd(1, .monotonic);
        return self;
    }
    pub fn release(self: *Api) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            const gpa = self.gpa;
            self.reported.deinit(gpa);
            self.buffer.deinit();
            self.owned.deinit();
            gpa.destroy(self);
        }
    }
    fn live(self: *Api) !void {
        if (self.ownerThread != std.Thread.getCurrentId()) return error.WrongInvocationThread;
        if (!self.active) return error.ToolInvocationSettled;
    }
    pub fn outputText(self: *Api, text: []const u8, skip: ?output.ShellOutputSkip) !void {
        try self.live();
        const converted = try json.usv(self.gpa, text);
        defer self.gpa.free(converted);
        if (try self.buffer.pushText(converted, skip)) self.gate.mark();
    }
    pub fn outputBytes(self: *Api, bytes: []const u8, skip: ?output.ShellOutputSkip) !void {
        try self.live();
        if (try self.buffer.pushBytes(bytes, skip)) self.gate.mark();
    }
    pub fn diagnostic(self: *Api, severity: values.Severity, code: ?[]const u8, message: []const u8) !void {
        try self.live();
        try self.reported.diagnostic(self.gpa, severity, if (code) |name| try self.owned.arena.allocator().dupe(u8, name) else null, try self.gpa.dupe(u8, message));
        self.gate.mark();
    }
    pub fn details(self: *Api, value: json.Value, context: types.Context) !void {
        try self.live();
        if (context.aborted()) return error.Canceled;
        self.detailsValue = try json.clone(self.owned.arena.allocator(), value);
        self.gate.mark();
    }
    pub fn commit(self: *Api, callback: session_module.CommitFn, state: ?*anyopaque, context: types.Context) !session_module.Result {
        try self.live();
        const session = self.session orelse return error.NoSessionConfigured;
        return session.commit(callback, state, self.scope, context);
    }
    pub fn outputWindow(self: *const Api) ?output.ShellOutputWindow {
        return if (self.buffer.limits.retain == .tail) .{ .maxBytes = self.buffer.limits.maxBytes, .maxLines = self.buffer.limits.maxLines, .minIntervalMs = self.outputIntervalMs, .bytesPerSecond = 100 * 1024 } else null;
    }
};
pub const Outcome = struct {
    value: json.Owned,
    cause: ?anyerror = null,
    entryId: ?u64 = null,
    pub fn deinit(self: *Outcome) void {
        self.value.deinit();
    }
};
pub const Options = struct { extensions: ?[]const []const u8 = null, progress: ProgressOptions = .{}, session: ?*session_module.Session = null, scope: session_module.Scope = .{}, conversationId: ?u64 = null, callId: ?[]const u8 = null };
fn invalid(gpa: std.mem.Allocator, message: []const u8, cause: ?anyerror) !Outcome {
    return harnessError(gpa, "invalid_arguments", message, cause);
}
fn harnessError(gpa: std.mem.Allocator, code: []const u8, message: []const u8, cause: ?anyerror) !Outcome {
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const allocator = owned.arena.allocator();
    var result: json.Value = .{ .object = .empty };
    try result.object.put(allocator, "isError", .{ .bool = true });
    try result.object.put(allocator, "content", .{ .array = .init(allocator) });
    var diagnostic: json.Value = .{ .object = .empty };
    try diagnostic.object.put(allocator, "severity", .{ .string = "error" });
    try diagnostic.object.put(allocator, "code", .{ .string = try allocator.dupe(u8, code) });
    try diagnostic.object.put(allocator, "message", .{ .string = try allocator.dupe(u8, message) });
    var list: std.array_list.Managed(json.Value) = .init(allocator);
    try list.append(diagnostic);
    try result.object.put(allocator, "diagnostics", .{ .array = list });
    owned.value = result;
    return .{ .value = owned, .cause = cause };
}
pub fn invoke(gpa: std.mem.Allocator, snapshot: *registry.Snapshot, name: []const u8, args: json.Value, options: Options, context: types.Context) !Outcome {
    const held = snapshot.retain();
    defer held.release();
    const implementation = held.findTool(name, options.extensions) orelse {
        const message = try std.fmt.allocPrint(gpa, "Tool {s} is not available", .{name});
        defer gpa.free(message);
        return harnessError(gpa, "tool_unavailable", message, error.ToolNotFound);
    };
    var input = try json.Owned.empty(gpa);
    defer input.deinit();
    input.value = try json.clone(input.arena.allocator(), args);
    if (!schema_policy.supported(implementation.tool.parameters)) return invalid(gpa, "Tool schema uses an unsupported validation keyword", error.UnsupportedToolSchema);
    if (implementation.tool.prepare) |prepare| input.value = prepare(implementation.tool.resource.context, input.arena.allocator(), input.value, context) catch |err| {
        if (err == error.OutOfMemory) return err;
        return invalid(gpa, @errorName(err), err);
    };
    input.value = try schema_policy.convert(input.arena.allocator(), implementation.tool.parameters, input.value);
    if (try core_tools.validateSchemaValue(gpa, implementation.tool.parameters, input.value, "root")) |message| {
        defer gpa.free(message);
        return invalid(gpa, message, error.InvalidToolArguments);
    }
    if (context.aborted()) return error.Canceled;
    const api = try Api.create(gpa, implementation.tool.limits, options.progress, options.session, options.scope);
    defer api.release();
    defer api.active = false;
    var executed = implementation.tool.execute(implementation.tool.resource.context, input.value, api, context) catch |err| blk: {
        if (err == error.OutOfMemory) return err;
        break :blk registry.Execution{ .result = try values.messageFailure(gpa, @errorName(err), err) };
    };
    defer executed.result.deinit(gpa);
    api.active = false;
    try api.buffer.end();
    var outcome: Outcome = .{ .value = try json.Owned.empty(gpa) };
    errdefer outcome.deinit();
    const allocator = outcome.value.arena.allocator();
    var value: json.Value = .{ .object = .empty };
    var diagnostics: std.array_list.Managed(json.Value) = .init(allocator);
    for (api.reported.diagnostics.items) |item| try diagnostics.append(try diagnosticValue(allocator, item));
    var text: ?[]const u8 = null;
    var content: ?json.Value = executed.content;
    var retained: ?output.Snapshot = null;
    defer if (retained) |*slice| slice.deinit(gpa);
    if (executed.result == .value) {
        const result = executed.result.value;
        text = result.text;
        if (result.isError) try value.object.put(allocator, "isError", .{ .bool = true });
        for (result.diagnostics.items) |item| try diagnostics.append(try diagnosticValue(allocator, item));
    } else {
        const failure = executed.result.failure;
        outcome.cause = failure.cause;
        try value.object.put(allocator, "isError", .{ .bool = true });
        for (failure.diagnostics.items) |item| try diagnostics.append(try diagnosticValue(allocator, item));
        try diagnostics.append(try diagnosticValue(allocator, .{ .severity = .err, .code = "tool_error", .message = failure.message }));
    }
    if (content == null) {
        var parts: std.array_list.Managed(json.Value) = .init(allocator);
        if (text == null and !executed.contentProvided) {
            retained = try api.buffer.snapshot();
            text = retained.?.text;
        }
        if (text) |bytes| if (bytes.len != 0) {
            var item: json.Value = .{ .object = .empty };
            try item.object.put(allocator, "type", .{ .string = "text" });
            try item.object.put(allocator, "text", .{ .string = try allocator.dupe(u8, bytes) });
            try parts.append(item);
        };
        content = .{ .array = parts };
    }
    const bounded = try boundContent(allocator, content.?, implementation.tool.limits);
    try value.object.put(allocator, "content", bounded.content);
    if (retained) |slice| if (slice.droppedBytes > 0) try diagnostics.append(try truncationDiagnostic(allocator, slice.droppedBytes, slice.droppedLines, implementation.tool.limits.retain));
    if (bounded.bytes > 0) try diagnostics.append(try truncationDiagnostic(allocator, bounded.bytes, bounded.lines, implementation.tool.limits.retain));
    try value.object.put(allocator, "diagnostics", .{ .array = diagnostics });
    if (executed.details orelse api.detailsValue) |details| try value.object.put(allocator, "details", try json.clone(allocator, details)) else if (executed.result == .value and executed.result.value.details != null) {
        const details = executed.result.value.details.?;
        switch (details) {
            .edit => |edit| {
                var encoded: json.Value = .{ .object = .empty };
                try encoded.object.put(allocator, "diff", .{ .string = try allocator.dupe(u8, edit.diff) });
                try encoded.object.put(allocator, "patch", .{ .string = try allocator.dupe(u8, edit.patch) });
                if (edit.firstChangedLine) |line| try encoded.object.put(allocator, "firstChangedLine", .{ .integer = @intCast(line) });
                try value.object.put(allocator, "details", encoded);
            },
            .truncation => |truncation| {
                const bytes = try std.json.Stringify.valueAlloc(gpa, truncation, .{ .emit_null_optional_fields = true });
                defer gpa.free(bytes);
                var encoded: json.Value = .{ .object = .empty };
                try encoded.object.put(allocator, "truncation", try json.parseLeaky(allocator, bytes));
                try value.object.put(allocator, "details", encoded);
            },
        }
    }
    if (executed.control) |control| try value.object.put(allocator, "control", try json.clone(allocator, control));
    outcome.value.value = value;
    if (options.session) |session| if (options.conversationId) |conversation| {
        var state: Persist = .{ .value = value, .conversation = conversation, .name = name, .callId = options.callId orelse name };
        var committed = try session.commit(Persist.append, &state, options.scope, context);
        defer committed.deinit();
        outcome.entryId = try json.asInteger(committed.value.value);
    };
    return outcome;
}
fn diagnosticValue(gpa: std.mem.Allocator, item: values.Diagnostic) !json.Value {
    var value: json.Value = .{ .object = .empty };
    try value.object.put(gpa, "severity", .{ .string = if (item.severity == .err) "error" else @tagName(item.severity) });
    if (item.code) |code| try value.object.put(gpa, "code", .{ .string = try gpa.dupe(u8, code) });
    try value.object.put(gpa, "message", .{ .string = try gpa.dupe(u8, item.message) });
    return value;
}
fn truncationDiagnostic(gpa: std.mem.Allocator, bytes: u64, lines: u64, retain: output.Retention) !json.Value {
    return diagnosticValue(gpa, .{ .severity = .warn, .code = "truncated", .message = try std.fmt.allocPrint(gpa, "Output truncated to its {s}: {d} lines, {d} bytes dropped", .{ if (retain == .head) "beginning" else "end", lines, bytes }) });
}
const Bounded = struct { content: json.Value, bytes: u64 = 0, lines: u64 = 0 };
fn boundContent(gpa: std.mem.Allocator, content: json.Value, limits: output.Limits) !Bounded {
    if (content != .array) return error.InvalidToolContent;
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(gpa);
    var text_count: usize = 0;
    for (content.array.items) |item| if (json.get(item, "type")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "text")) {
        if (text_count != 0) try joined.append(gpa, '\n');
        const converted = try json.usv(gpa, try json.asString(try json.required(item, "text")));
        defer gpa.free(converted);
        try joined.appendSlice(gpa, converted);
        text_count += 1;
    };
    const cut = try output.boundOutput(gpa, joined.items, limits);
    if (cut.droppedBytes == 0) return .{ .content = try json.clone(gpa, content) };
    var parts: std.array_list.Managed(json.Value) = .init(gpa);
    var index: usize = 0;
    for (content.array.items) |item| {
        const kind = json.get(item, "type");
        const is_text = kind != null and kind.? == .string and std.mem.eql(u8, kind.?.string, "text");
        if (!is_text) {
            try parts.append(try json.clone(gpa, item));
            continue;
        }
        index += 1;
        if ((limits.retain == .head and index == 1) or (limits.retain == .tail and index == text_count)) {
            var kept: json.Value = .{ .object = .empty };
            try kept.object.put(gpa, "type", .{ .string = "text" });
            try kept.object.put(gpa, "text", .{ .string = cut.text });
            try parts.append(kept);
        }
    }
    return .{ .content = .{ .array = parts }, .bytes = cut.droppedBytes, .lines = cut.droppedLines };
}
const Persist = struct {
    value: json.Value,
    conversation: u64,
    name: []const u8,
    callId: []const u8,
    fn append(state: ?*anyopaque, tx: *session_module.Transaction, _: types.Context) !json.Value {
        const self: *@This() = @ptrCast(@alignCast(state.?));
        const allocator = tx.owned.arena.allocator();
        var draft: json.Value = .{ .object = .empty };
        try draft.object.put(allocator, "kind", .{ .string = "pi.tool-result" });
        var data: json.Value = .{ .object = .empty };
        try data.object.put(allocator, "diagnostics", try json.clone(allocator, try json.required(self.value, "diagnostics")));
        try draft.object.put(allocator, "data", data);
        var message: json.Value = .{ .object = .empty };
        try message.object.put(allocator, "role", .{ .string = "toolResult" });
        try message.object.put(allocator, "toolCallId", .{ .string = try allocator.dupe(u8, self.callId) });
        try message.object.put(allocator, "toolName", .{ .string = try allocator.dupe(u8, self.name) });
        var content = try json.clone(allocator, try json.required(self.value, "content"));
        const diagnostics = try json.required(self.value, "diagnostics");
        if (diagnostics.array.items.len != 0) {
            var rendered: std.ArrayList(u8) = .empty;
            defer rendered.deinit(allocator);
            try rendered.appendSlice(allocator, "<harness>\n");
            for (diagnostics.array.items, 0..) |diagnostic, index| {
                if (index != 0) try rendered.append(allocator, '\n');
                const line = try std.fmt.allocPrint(allocator, "[{s}] {s}", .{ try json.asString(try json.required(diagnostic, "severity")), try json.asString(try json.required(diagnostic, "message")) });
                try rendered.appendSlice(allocator, line);
            }
            try rendered.appendSlice(allocator, "\n</harness>");
            var item: json.Value = .{ .object = .empty };
            try item.object.put(allocator, "type", .{ .string = "text" });
            try item.object.put(allocator, "text", .{ .string = try rendered.toOwnedSlice(allocator) });
            try content.array.append(item);
        }
        try message.object.put(allocator, "content", content);
        if (json.get(self.value, "details")) |details| try message.object.put(allocator, "details", try json.clone(allocator, details));
        try message.object.put(allocator, "isError", json.get(self.value, "isError") orelse .{ .bool = false });
        try message.object.put(allocator, "timestamp", .{ .integer = std.Io.Clock.real.now(tx.session.io).toMilliseconds() });
        var model: std.array_list.Managed(json.Value) = .init(allocator);
        try model.append(message);
        try draft.object.put(allocator, "model", .{ .array = model });
        const entry = try tx.appendEntry(self.conversation, draft);
        return json.required(entry, "id");
    }
};

test "durable Harness snapshots retain capabilities and native tool admission preserves invocation lifetime" {
    const gpa = std.testing.allocator;
    const Fixture = struct {
        refs: usize = 1,
        calls: usize = 0,
        retained: ?*Api = null,
        fn retain(state: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            self.refs += 1;
        }
        fn release(state: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            self.refs -= 1;
        }
        fn prepare(_: ?*anyopaque, allocator: std.mem.Allocator, input: json.Value, _: types.Context) !json.Value {
            var result = try json.clone(allocator, input);
            try result.object.put(allocator, "value", .{ .integer = 2 });
            return result;
        }
        fn execute(state: ?*anyopaque, args: json.Value, opaque_api: *anyopaque, _: types.Context) !registry.Execution {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            self.calls += 1;
            try std.testing.expect(self.refs > 1);
            try std.testing.expectEqual(@as(u64, 2), try json.asInteger(try json.required(args, "value")));
            const api: *Api = @ptrCast(@alignCast(opaque_api));
            self.retained = api.retain();
            try api.outputText("lead", null);
            try api.outputBytes(&.{ 239, 187, 191, 'x' }, null);
            try api.diagnostic(.info, "probe", "reported");
            return .{ .result = .{ .value = .{} } };
        }
    };
    var fixture: Fixture = .{};
    var registry_owner = try registry.Registry.init(gpa, std.testing.io);
    defer registry_owner.deinit();
    var schema = try json.Owned.parse(gpa, "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"integer\"}},\"required\":[\"value\"],\"additionalProperties\":false}");
    defer schema.deinit();
    const tool: registry.Tool = .{ .name = "probe", .parameters = schema.value, .prepare = Fixture.prepare, .execute = Fixture.execute, .resource = .{ .context = &fixture, .retain = Fixture.retain, .release = Fixture.release }, .limits = .{ .retain = .tail } };
    try registry_owner.install(.{ .name = "extension", .tools = &.{tool} });
    var snapshot = registry_owner.snapshot();
    defer snapshot.release();
    try registry_owner.uninstall("extension");
    try std.testing.expectEqual(@as(usize, 2), fixture.refs);
    var args = try json.Owned.parse(gpa, "{\"value\":1}");
    defer args.deinit();
    var result = try invoke(gpa, snapshot, "probe", args.value, .{}, .{});
    defer result.deinit();
    defer fixture.retained.?.release();
    try std.testing.expectEqual(@as(u64, 1), try json.asInteger(try json.required(args.value, "value")));
    const content = try json.required(result.value.value, "content");
    try std.testing.expectEqualStrings("lead\xef\xbb\xbfx", try json.asString(try json.required(content.array.items[0], "text")));
    try std.testing.expectEqual(@as(usize, 1), fixture.calls);
    try std.testing.expectError(error.ToolInvocationSettled, fixture.retained.?.outputText("late", null));
    try std.testing.expectEqual(@as(u64, 100), resolveProgress(.{}).partialIntervalMs);
    try std.testing.expectEqual(@as(u64, 100), resolveProgress(.{ .partialIntervalMs = 0 }).outputIntervalMs);
    try std.testing.expectEqual(@as(u64, 0), resolveProgress(.{ .partialIntervalMs = 0 }).partialIntervalMs);
}

test "durable Harness rejects schema before callbacks and persists bounded results into Session" {
    const gpa = std.testing.allocator;
    var memory = try @import("../backend/memory.zig").Memory.init(gpa);
    defer memory.deinit();
    var session = session_module.Session.init(gpa, std.testing.io, .{ .memory = &memory });
    defer session.deinit();
    const Root = struct {
        fn create(_: ?*anyopaque, tx: *session_module.Transaction, _: types.Context) !json.Value {
            return tx.createRootConversation();
        }
    };
    var root = try session.commit(Root.create, null, .{}, .{});
    defer root.deinit();
    const Tool = struct {
        fn execute(_: ?*anyopaque, _: json.Value, opaque_api: *anyopaque, _: types.Context) !registry.Execution {
            const api: *Api = @ptrCast(@alignCast(opaque_api));
            try api.outputText("one\ntwo\nthree\n", null);
            return .{ .result = .{ .value = .{} } };
        }
    };
    var schema = try json.Owned.parse(gpa, "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"integer\"}},\"required\":[\"value\"]}");
    defer schema.deinit();
    var owner = try registry.Registry.init(gpa, std.testing.io);
    defer owner.deinit();
    try owner.install(.{ .name = "extension", .tools = &.{.{ .name = "probe", .parameters = schema.value, .execute = Tool.execute, .limits = .{ .maxBytes = 20, .maxLines = 1, .retain = .tail } }} });
    const snapshot = owner.snapshot();
    defer snapshot.release();
    var bad = try json.Owned.parse(gpa, "{}");
    defer bad.deinit();
    var invalid_result = try invoke(gpa, snapshot, "probe", bad.value, .{}, .{});
    defer invalid_result.deinit();
    try std.testing.expect((try json.required(invalid_result.value.value, "isError")).bool);
    var input = try json.Owned.parse(gpa, "{\"value\":1}");
    defer input.deinit();
    var result = try invoke(gpa, snapshot, "probe", input.value, .{ .session = &session, .conversationId = 1, .callId = "call-1" }, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(?u64, 2), result.entryId);
    const content = try json.required(result.value.value, "content");
    try std.testing.expectEqualStrings("three\n", try json.asString(try json.required(content.array.items[0], "text")));
    var entry = (try memory.readRecord(gpa, 2)).?;
    defer entry.deinit();
    try std.testing.expectEqualStrings("pi.tool-result", try json.asString(try json.required(entry.value, "kind")));
    const message = (try json.required(entry.value, "model")).array.items[0];
    const model_content = try json.required(message, "content");
    try std.testing.expectEqual(@as(usize, 2), model_content.array.items.len);
    try std.testing.expect(std.mem.startsWith(u8, try json.asString(try json.required(model_content.array.items[1], "text")), "<harness>\n[warn] Output truncated to its end:"));
}

test "durable Harness allocation failures and original execute errors release all retained resources" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            const Tool = struct {
                fn execute(_: ?*anyopaque, _: json.Value, opaque_api: *anyopaque, _: types.Context) !registry.Execution {
                    const api: *Api = @ptrCast(@alignCast(opaque_api));
                    try api.outputText("one\ntwo\nthree", null);
                    try api.diagnostic(.info, "reported", "progress");
                    return error.OriginalExecute;
                }
            };
            var owner = try registry.Registry.init(gpa, std.testing.io);
            defer owner.deinit();
            var schema = try json.Owned.parse(gpa, "{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"integer\"}},\"required\":[\"n\"]}");
            defer schema.deinit();
            try owner.install(.{ .name = "extension", .tools = &.{.{ .name = "probe", .parameters = schema.value, .execute = Tool.execute, .limits = .{ .maxBytes = 20, .maxLines = 1, .retain = .tail } }} });
            const snapshot = owner.snapshot();
            defer snapshot.release();
            var input = try json.Owned.parse(gpa, "{\"n\":\"2\"}");
            defer input.deinit();
            var result = try invoke(gpa, snapshot, "probe", input.value, .{}, .{});
            defer result.deinit();
            if (result.cause) |cause| if (cause == error.OutOfMemory) return error.OutOfMemory;
            try std.testing.expectEqual(error.OriginalExecute, result.cause.?);
            try std.testing.expect((try json.required(result.value.value, "isError")).bool);
            try std.testing.expectEqualStrings("three", try json.asString(try json.required((try json.required(result.value.value, "content")).array.items[0], "text")));
        }
    }.run, .{});
}

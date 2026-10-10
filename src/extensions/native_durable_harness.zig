//! Public Harness creation and conversation handles over the native Session line.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const backend = @import("../durable/backend/root.zig");
const scans = @import("../durable/backend/source_scan.zig");
const json = backend.json;
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const State = struct { engine: *Engine, session: c.JSValue, options: c.JSValue, conversation: ?u64 = null };
const Method = enum(c_int) { commit, close, root, conversation, createConversation, getTask, entries, fork, subscribeCommits, subscribeClose, @"resume", waitForTask, waitForIdle, abortTask, snapshot, snapshotAsOf, unloadDocuments, watchDoc, documentState, resolveAgent, agent, configure, context, submit, submission, compact, reset, viewState, watch };
pub fn state(engine: *Engine, receiver: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, engine.native_durable_harness_class) orelse return error.InvalidHarnessReceiver));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_harness_class) orelse return));
    c.JS_FreeValueRT(runtime, self.session);
    c.JS_FreeValueRT(runtime, self.options);
    engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_harness_class) orelse return));
    c.JS_MarkValue(runtime, self.session, marker);
    c.JS_MarkValue(runtime, self.options, marker);
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    if (engine.native_durable_harness_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_harness_class);
    const definition: c.JSClassDef = .{ .class_name = "Native durable Harness", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_harness_class) and c.JS_NewClass(engine.runtime, engine.native_durable_harness_class, &definition) < 0) return error.OutOfMemory;
    const harness = try sdk.object(engine);
    defer engine.freeValue(harness);
    try sdk.put(engine, harness, "open", try engine.checked(c.JS_NewCFunction(engine.context, open, "open", 3)));
    try sdk.put(engine, exports, "Harness", c.JS_DupValue(engine.context, harness));
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn open(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const result = openOwned(engine, argv[0..@intCast(argc)]) catch |err| return durable.rejectedPromise(engine, err);
    defer engine.freeValue(result);
    return sdk.promise(engine, result) catch |err| durable.rejectedPromise(engine, err);
}
fn openOwned(engine: *Engine, args: []const c.JSValue) !c.JSValue {
    try durable.checkCancellation(engine, argument(args, 2));
    const options = argument(args, 1);
    const registry = try sdk.get(engine, options, "registry");
    defer engine.freeValue(registry);
    const snapshot = try sdk.invoke(engine, registry, "snapshot", &.{});
    defer engine.freeValue(snapshot);
    for ([_][]const u8{ "pi.generation", "pi.tool", "pi.compaction" }) |name| {
        const key = try sdk.text(engine, name);
        defer engine.freeValue(key);
        const task = try sdk.invoke(engine, snapshot, "task", &.{key});
        defer engine.freeValue(task);
        if (c.JS_IsUndefined(task)) return error.RegistryLacksBuiltinTasks;
    }
    const session = try durable.sessionObject(engine, argument(args, 0));
    defer engine.freeValue(session);
    const result = try object(engine, session, options, null);
    errdefer engine.freeValue(result);
    const owner = try durable.state(engine, session);
    owner.creation_owner = c.JS_DupValue(engine.context, result);
    owner.creation_hook = created;
    owner.finish_hook = finish;
    try @import("native_durable_tasks.zig").attach(engine, session, options, argument(args, 2));
    owner.task_creator = @import("native_durable_tasks.zig").createTask;
    return result;
}
pub fn object(engine: *Engine, session: c.JSValue, options: c.JSValue, conversation: ?u64) !c.JSValue {
    const result = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_harness_class));
    errdefer engine.freeValue(result);
    const self = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(self);
    const methods = if (conversation != null) &[_]Method{ .commit, .entries, .fork, .waitForIdle, .agent, .configure, .context, .submit, .compact, .reset, .viewState, .watch } else &[_]Method{ .commit, .close, .root, .conversation, .createConversation, .getTask, .subscribeCommits, .subscribeClose, .@"resume", .waitForTask, .waitForIdle, .abortTask, .snapshot, .snapshotAsOf, .unloadDocuments, .watchDoc, .documentState, .resolveAgent, .submission };
    for (methods) |operation| {
        const name = try engine.gpa.dupeZ(u8, @tagName(operation));
        defer engine.gpa.free(name);
        try sdk.put(engine, result, name, try engine.checked(c.pi_js_function_magic(engine.context, method, name, 1, @intFromEnum(operation))));
    }
    if (conversation) |id| {
        if (c.JS_DefinePropertyValueStr(engine.context, result, "id", c.JS_NewInt64(engine.context, @intCast(id)), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    }
    self.* = .{ .engine = engine, .session = c.JS_DupValue(engine.context, session), .options = c.JS_DupValue(engine.context, options), .conversation = conversation };
    _ = c.JS_SetOpaque(result, self);
    return result;
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const operation: Method = @enumFromInt(magic);
    return dispatch(engine, receiver, operation, argv[0..@intCast(argc)]) catch |err| if (operation == .subscribeCommits or operation == .subscribeClose) durable.reject(engine, err) else durable.rejectedPromise(engine, err);
}
fn dispatch(engine: *Engine, receiver: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    const self = try state(engine, receiver);
    const session = try durable.state(engine, self.session);
    if (operation == .viewState or operation == .watch) {
        const id = c.JS_NewInt64(engine.context, @intCast(self.conversation.?));
        defer engine.freeValue(id);
        return @import("native_durable_views.zig").acquire(engine, self.session, self.options, id, argument(args, 0), operation == .watch);
    }
    if (operation == .submit) {
        const id = c.JS_NewInt64(engine.context, @intCast(self.conversation.?));
        defer engine.freeValue(id);
        return @import("native_durable_submission_handle.zig").submit(engine, self.session, self.options, id, argument(args, 0), argument(args, 1));
    }
    if (operation == .submission) return @import("native_durable_submission_handle.zig").get(engine, self.session, self.options, argument(args, 0), argument(args, 1));
    if (operation == .compact or operation == .reset) {
        const id = c.JS_NewInt64(engine.context, @intCast(self.conversation.?));
        defer engine.freeValue(id);
        return if (operation == .compact) @import("native_durable_submission_handle.zig").compact(engine, self.session, self.options, id, argument(args, 0), argument(args, 1)) else @import("native_durable_submission_handle.zig").reset(engine, self.session, self.options, id, argument(args, 0), argument(args, 1));
    }
    if (operation == .context) {
        const options = argument(args, 1);
        const at = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "at");
        defer engine.freeValue(at);
        const id = c.JS_NewInt64(engine.context, @intCast(self.conversation.?));
        defer engine.freeValue(id);
        return @import("native_durable_context_view.zig").queued(engine, self.session, id, argument(args, 0), at);
    }
    if (operation == .agent or operation == .resolveAgent) {
        const id = if (self.conversation) |id| c.JS_NewInt64(engine.context, @intCast(id)) else c.JS_DupValue(engine.context, argument(args, 0));
        defer engine.freeValue(id);
        return @import("native_durable_agent.zig").resolveConversation(engine, self.session, self.options, id, if (operation == .agent) c.pi_js_undefined() else argument(args, 1), argument(args, if (operation == .agent) 0 else 2));
    }
    if (operation == .configure) {
        const id = c.JS_NewInt64(engine.context, @intCast(self.conversation.?));
        defer engine.freeValue(id);
        const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
        const token = try sdk.get(engine, exports, "AgentDoc");
        defer engine.freeValue(token);
        var captures = [_]c.JSValue{ id, argument(args, 0), token };
        const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, configureCallback, 1, 0, captures.len, &captures));
        defer engine.freeValue(callback);
        return durable.sessionDispatchScoped(session, self.session, .commit, &.{ callback, argument(args, 1) }, self.conversation);
    }
    if (operation == .documentState) return durable.sessionDispatch(session, self.session, .documentState, args);
    if (operation == .watchDoc) return durable.sessionDispatch(session, self.session, .watchDoc, args);
    if (operation == .unloadDocuments) return durable.sessionDispatch(session, self.session, .unloadDocuments, args);
    if (operation == .snapshot) return durable.sessionDispatch(session, self.session, .snapshot, args);
    if (operation == .snapshotAsOf) return durable.sessionDispatch(session, self.session, .snapshotAsOf, args);
    const tasks = @import("native_durable_tasks.zig");
    if (operation == .@"resume") {
        try (try tasks.getManager(engine, self.session)).@"resume"();
        return c.pi_js_undefined();
    }
    if (operation == .waitForTask or operation == .waitForIdle) {
        const owner = try tasks.getManager(engine, self.session);
        return tasks.wait(owner, if (operation == .waitForTask) try durable.number(engine, argument(args, 0)) else null, self.conversation, argument(args, if (operation == .waitForTask) 1 else 0));
    }
    if (operation == .close) {
        const result = try durable.sessionDispatch(session, self.session, .close, args);
        errdefer engine.freeValue(result);
        (try tasks.getManager(engine, self.session)).close();
        return result;
    }
    if (operation == .abortTask) {
        const owner = try tasks.getManager(engine, self.session);
        try durable.checkCancellation(engine, argument(args, 1));
        const id = try durable.number(engine, argument(args, 0));
        var record = (try owner.lease.value.storage.readTableRecord(engine.gpa, .task, id)) orelse return error.UnknownTask;
        defer record.deinit();
        const terminal = std.mem.eql(u8, try json.asString(try json.required(try json.required(record.value, "state"), "status")), "terminal");
        try owner.scheduler.abort(id);
        const result = try sdk.text(engine, if (terminal) "terminal" else "marked");
        defer engine.freeValue(result);
        return sdk.promise(engine, result);
    }
    if (operation == .subscribeCommits or operation == .subscribeClose) return sdk.invoke(engine, self.session, if (operation == .subscribeCommits) "subscribeCommits" else "subscribeClose", args);
    if (operation == .commit or operation == .close) return durable.sessionDispatchScoped(session, self.session, if (operation == .commit) .commit else .close, args, self.conversation);
    if (session.closing) return error.HarnessClosed;
    var data = [_]c.JSValue{ receiver, argument(args, 0), argument(args, 1), argument(args, 2) };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, onLine, 1, @intFromEnum(operation), data.len, &data));
    defer engine.freeValue(callback);
    const context = argument(args, switch (operation) {
        .root => 0,
        .createConversation, .conversation, .getTask => 1,
        .entries => 3,
        .fork => 2,
        else => unreachable,
    });
    return durable.sessionDispatch(session, self.session, .commit, &.{ callback, context });
}
fn configureCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc == 0) return durable.reject(engine, error.TransactionRequired);
    return @import("native_durable_agent.zig").configureOwned(engine, argv[0], data[0], data[1], data[2]) catch |err| durable.reject(engine, err);
}
fn onLine(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return onLineOwned(engine, data, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn onLineOwned(engine: *Engine, data: [*c]c.JSValue, operation: Method, transaction: c.JSValue) !c.JSValue {
    const self = try state(engine, data[0]);
    const tx = try durable.state(engine, transaction);
    const native = tx.transaction.?;
    if (operation == .getTask) {
        const record = try native.readRecord(.task, try durable.number(engine, data[1]));
        return if (record) |value| durable.jsValue(engine, value) else c.pi_js_undefined();
    }
    if (operation == .conversation) {
        const id = try durable.number(engine, data[1]);
        if (try native.readRecord(.conversation, id) == null) return c.pi_js_undefined();
        return object(engine, self.session, self.options, id);
    }
    if (operation == .entries) {
        var filters = try durable.owned(engine, data[1]);
        defer filters.deinit();
        try filters.value.object.put(filters.arena.allocator(), "conversationId", .{ .integer = @intCast(self.conversation.?) });
        var cursor: ?json.Owned = if (c.JS_IsUndefined(data[3])) null else try durable.owned(engine, data[3]);
        defer if (cursor) |*value| value.deinit();
        var snapshot: backend.memory.Memory = .{ .gpa = engine.gpa, .state = try native.session.storage.snapshot(engine.gpa) };
        defer snapshot.deinit();
        var page = try scans.scan(engine.gpa, &snapshot, .entry, filters.value, try durable.number(engine, data[2]), if (cursor) |value| value.value else null);
        defer page.deinit();
        return durable.jsValue(engine, page.value);
    }
    if (operation == .root and try native.readRecord(.conversation, 1) != null) return object(engine, self.session, self.options, 1);
    const method_name: [*:0]const u8 = if (operation == .root) "createRootConversation" else if (operation == .fork) "forkConversation" else "createConversation";
    const options = if (operation == .root) data[2] else if (operation == .fork) data[2] else data[1];
    const id_value = if (operation == .fork) try engine.checked(c.JS_NewInt64(engine.context, @intCast(self.conversation.?))) else c.pi_js_undefined();
    defer engine.freeValue(id_value);
    const pending = try sdk.invoke(engine, transaction, method_name, if (operation == .root) &.{} else if (operation == .fork) &.{ id_value, data[1], options } else &.{options});
    defer engine.freeValue(pending);
    const record = try engine.awaitValue(pending);
    defer engine.freeValue(record);
    const id = try sdk.get(engine, record, "id");
    defer engine.freeValue(id);
    if (!c.JS_IsUndefined(options)) {
        const agent = try sdk.get(engine, options, "agent");
        defer engine.freeValue(agent);
        if (!c.JS_IsUndefined(agent)) try configurePlan(engine, tx, try durable.number(engine, id), agent);
        const init = try sdk.get(engine, options, "init");
        defer engine.freeValue(init);
        if (!c.JS_IsUndefined(init)) {
            var args = [_]c.JSValue{ transaction, id };
            const pending_init = try engine.checked(c.JS_Call(engine.context, init, c.pi_js_undefined(), args.len, &args));
            defer engine.freeValue(pending_init);
            const settled = try engine.awaitValue(pending_init);
            engine.freeValue(settled);
        }
    }
    return object(engine, self.session, self.options, try durable.number(engine, id));
}
fn created(engine: *Engine, owner: c.JSValue, transaction: c.JSValue, record: json.Value) !void {
    const self = try state(engine, owner);
    const tx = try durable.state(engine, transaction);
    const conversation = try json.asInteger(try json.required(record, "id"));
    for ([_][]const u8{ "pi.live", "pi.inbox", "pi.usage", "pi.provider", "pi.agent" }) |kind| {
        if (std.mem.eql(u8, kind, "pi.agent") and json.get(record, "parent") != null) continue;
        var plan = try json.Owned.empty(engine.gpa);
        errdefer plan.deinit();
        const a = plan.arena.allocator();
        plan.value = .{ .object = .empty };
        var scope: json.Value = .{ .object = .empty };
        try scope.object.put(a, "kind", .{ .string = "conversation" });
        try scope.object.put(a, "conversationId", .{ .integer = @intCast(conversation) });
        var create: json.Value = .{ .object = .empty };
        try create.object.put(a, "id", .{ .integer = @intCast(try tx.transaction.?.session.storage.mintId()) });
        try create.object.put(a, "kind", .{ .string = kind });
        try create.object.put(a, "scope", scope);
        try create.object.put(a, "history", .{ .string = if (std.mem.eql(u8, kind, "pi.agent")) "rewindable" else "latest" });
        try create.object.put(a, "fork", .{ .string = if (std.mem.eql(u8, kind, "pi.agent")) "asOf" else "initial" });
        var initial: json.Value = .{ .object = .empty };
        if (std.mem.eql(u8, kind, "pi.inbox")) try initial.object.put(a, "items", .{ .array = .init(a) });
        if (std.mem.eql(u8, kind, "pi.usage")) {
            try initial.object.put(a, "models", .{ .object = .empty });
            try initial.object.put(a, "tools", .{ .object = .empty });
        }
        if (std.mem.eql(u8, kind, "pi.provider")) try initial.object.put(a, "sessionId", .{ .string = try uuid(self.engine, a) });
        var content: json.Value = .{ .object = .empty };
        try content.object.put(a, "version", .{ .integer = 1 });
        try content.object.put(a, "kind", .{ .string = "base" });
        try content.object.put(a, "value", initial);
        try plan.value.object.put(a, "type", .{ .string = "document.create" });
        try plan.value.object.put(a, "record", create);
        try plan.value.object.put(a, "content", content);
        try tx.plans.append(engine.gpa, plan);
    }
    const hook = try sdk.get(engine, self.options, "conversationCreated");
    defer engine.freeValue(hook);
    if (!c.JS_IsUndefined(hook)) {
        const record_value = try durable.jsValue(engine, record);
        defer engine.freeValue(record_value);
        var args = [_]c.JSValue{ transaction, record_value };
        const pending = try engine.checked(c.JS_Call(engine.context, hook, c.pi_js_undefined(), args.len, &args));
        defer engine.freeValue(pending);
        const result = try engine.awaitValue(pending);
        engine.freeValue(result);
    }
}
fn configurePlan(engine: *Engine, tx: *durable.State, conversation: u64, change: c.JSValue) !void {
    var owned = try agentChange(engine, change);
    defer owned.deinit();
    for (tx.plans.items) |*plan| {
        const record = try json.required(plan.value, "record");
        if (!std.mem.eql(u8, try json.asString(try json.required(record, "kind")), "pi.agent") or try json.asInteger(try json.required(try json.required(record, "scope"), "conversationId")) != conversation) continue;
        const value = plan.value.object.getPtr("content").?.object.getPtr("value").?;
        var iterator = owned.value.object.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.* == .null) {
                _ = value.object.orderedRemove(entry.key_ptr.*);
            } else try value.object.put(plan.arena.allocator(), try plan.arena.allocator().dupe(u8, entry.key_ptr.*), try json.clone(plan.arena.allocator(), entry.value_ptr.*));
        }
        return;
    }
    return error.AgentDocumentPlanUnavailable;
}
pub fn agentChange(engine: *Engine, change: c.JSValue) !json.Owned {
    var result = try json.Owned.empty(engine.gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    for ([_][:0]const u8{ "model", "thinkingLevel", "extensions", "tools", "modelTools", "instructions", "cwd" }) |name| {
        const input = try sdk.get(engine, change, name.ptr);
        defer engine.freeValue(input);
        if (c.JS_IsUndefined(input)) continue;
        if (c.JS_IsNull(input)) {
            try result.value.object.put(a, name, .null);
        } else if (std.mem.eql(u8, name, "extensions") or std.mem.eql(u8, name, "tools") or std.mem.eql(u8, name, "modelTools")) {
            if (c.JS_IsArray(input)) {
                try result.value.object.put(a, name, try names(engine, a, input));
            } else {
                var selection: json.Value = .{ .object = .empty };
                for ([_][:0]const u8{ "add", "remove" }) |field| {
                    if (!std.mem.eql(u8, name, "extensions") and std.mem.eql(u8, field, "add")) continue;
                    const list = try sdk.get(engine, input, field.ptr);
                    defer engine.freeValue(list);
                    if (!c.JS_IsUndefined(list) or !std.mem.eql(u8, name, "extensions")) try selection.object.put(a, field, try names(engine, a, list));
                }
                try result.value.object.put(a, name, selection);
            }
        } else {
            var value = try durable.owned(engine, input);
            defer value.deinit();
            try result.value.object.put(a, name, try json.clone(a, value.value));
        }
    }
    return result;
}
fn names(engine: *Engine, a: std.mem.Allocator, items: c.JSValue) !json.Value {
    if (!c.JS_IsArray(items)) return error.ExpectedAgentSelectionArray;
    var result: json.Value = .{ .array = .init(a) };
    const length = try sdk.length(engine, items);
    for (0..length) |index| {
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index)));
        defer engine.freeValue(item);
        const name = try sdk.get(engine, item, "name");
        defer engine.freeValue(name);
        if (!c.JS_IsString(name)) return error.ExpectedAgentSelectionName;
        const text = try engine.toString(name);
        defer engine.gpa.free(text);
        try result.array.append(.{ .string = try a.dupe(u8, text) });
    }
    return result;
}
fn finish(engine: *Engine, _: c.JSValue, transaction: c.JSValue) !void {
    const tx = try durable.state(engine, transaction);
    for (tx.plans.items) |plan| try tx.transaction.?.documentCommand(plan.value);
    // Source assembles table writes before document plans, even when a fork
    // selected its copies before staging the new conversation record.
    const native = tx.transaction.?;
    const ordered = try native.owned.arena.allocator().alloc(json.Value, native.writes.array.items.len);
    var index: usize = 0;
    for ([_]bool{ false, true }) |documents| for (native.writes.array.items) |write| {
        const tag = try json.asString(try json.required(write, "type"));
        if (std.mem.startsWith(u8, tag, "document.") != documents) continue;
        ordered[index] = write;
        index += 1;
    };
    @memcpy(native.writes.array.items, ordered);
}
pub fn uuid(engine: *Engine, a: std.mem.Allocator) ![]u8 {
    const io = engine.native_io orelse return error.DurableIOUnavailable;
    var bytes: [16]u8 = undefined;
    try io.randomSecure(&bytes);
    const now: u64 = @intCast(@max(0, std.Io.Clock.real.now(io).toMilliseconds()));
    if (now > 0xffffffffffff) return error.UuidTimestampOutOfRange;
    engine.native_durable_uuid_last_ms = @max(now, engine.native_durable_uuid_last_ms);
    const sequence = if (engine.native_durable_uuid_sequence) |previous| blk: {
        if (previous == (1 << 41) - 1) return error.UuidSequenceExhausted;
        break :blk previous + 1;
    } else (@as(u64, bytes[1]) << 32) | (@as(u64, bytes[2]) << 24) | (@as(u64, bytes[3]) << 16) | (@as(u64, bytes[4]) << 8) | bytes[5];
    engine.native_durable_uuid_sequence = sequence;
    for (0..6) |index| bytes[index] = @truncate(engine.native_durable_uuid_last_ms >> @as(u6, @intCast((5 - index) * 8)));
    bytes[6] = 0x70 | @as(u8, @intCast((sequence >> 37) & 0xf));
    bytes[7] = @truncate(sequence >> 29);
    bytes[8] = 0x80 | @as(u8, @intCast((sequence >> 23) & 0x3f));
    bytes[9] = @truncate(sequence >> 15);
    bytes[10] = @truncate(sequence >> 7);
    bytes[11] = @as(u8, @intCast((sequence & 0x7f) << 1)) | (bytes[11] & 1);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return std.fmt.allocPrint(a, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
}

fn constructorAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const options = try engine.eval("({registry:{snapshot(){return{task(){return{}},tasks(){return[]}}}}})", "harness-user-registry-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    const args = [_]c.JSValue{ storage, options, c.pi_js_undefined() };
    const harness = try openOwned(engine, &args);
    defer engine.freeValue(harness);
    const self = try state(engine, harness);
    const conversation = try object(engine, self.session, self.options, 1);
    defer engine.freeValue(conversation);
}
test "native durable VM Harness and conversation constructors clean up every GPA failure and owner cycle" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, constructorAllocationExercise, .{});
}

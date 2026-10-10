//! Atomic nested-call admission: task, index and live slot share one commit.
//! A replay reattaches only when the previous call has the same tool/arguments.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Tokens = struct { task: c.JSValue, index: c.JSValue, live: c.JSValue };
const Stage = enum(c_int) { index, previous, created, live, committed };
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, value: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, value, key));
    }
    fn invoke(self: *Scope, value: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, value, key, args));
    }
};
fn put(engine: *Engine, state: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, state, key, c.JS_DupValue(engine.context, value));
}
fn wait(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
    return awaiting.continueWith(advance, engine, &intrinsics, state, value, @intFromEnum(stage));
}
pub fn admit(engine: *Engine, intrinsics: *awaiting.Intrinsics, tokens: Tokens, runtime: c.JSValue, parent_call_id: c.JSValue, name: c.JSValue, arguments: c.JSValue, key: c.JSValue, progress: c.JSValue, abandon_on_restart: bool, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "runtime", runtime }, .{ "parentCallId", parent_call_id }, .{ "name", name }, .{ "key", key }, .{ "progress", progress }, .{ "taskToken", tokens.task }, .{ "indexToken", tokens.index }, .{ "liveToken", tokens.live }, .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function } }) |field| try put(engine, state, field[0], field[1]);
    try put(engine, state, "abandonOnRestart", c.pi_js_bool(engine.context, @intFromBool(abandon_on_restart)));
    const call = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, call, "type", try engine.checked(c.JS_NewString(engine.context, "toolCall")));
    const separator = try scope.own(try engine.checked(c.JS_NewString(engine.context, "/")));
    const id = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ parent_call_id, separator, key }));
    try put(engine, call, "id", id);
    try put(engine, call, "name", name);
    const options = try scope.own(try vm.object(engine));
    try put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    const copied = try scope.own(try @import("native_chord_json.zig").copyJson(engine, arguments, options));
    try put(engine, call, "arguments", copied);
    try put(engine, state, "call", call);
    var captures = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, transaction, "", 1, 0, captures.len, &captures)));
    const pending = try scope.invoke(runtime, "commit", &.{ callback, context });
    return wait(engine, state, pending, .committed);
}
fn transaction(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return start(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn start(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "tx", tx);
    const runtime = try scope.get(state, "runtime");
    const id = try scope.get(runtime, "taskId");
    const token = try scope.get(state, "indexToken");
    const pending = try scope.invoke(tx, "doc", &.{ token, id });
    return wait(engine, state, pending, .index);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    const stage: Stage = @enumFromInt(raw_stage);
    if (stage == .committed) return vm.get(engine, state, "id");
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const tx = try scope.get(state, "tx");
    const key = try scope.get(state, "key");
    const call = try scope.get(state, "call");
    switch (stage) {
        .index => {
            try put(engine, state, "index", value);
            const object = try scope.own(try js.global(engine, "Object"));
            const calls = try scope.get(value, "calls");
            const own = try scope.invoke(object, "hasOwn", &.{ calls, key });
            const existing = if (c.JS_ToBool(engine.context, own) != 0) try scope.own(try js.getKey(engine, calls, key)) else c.pi_js_undefined();
            if (!c.JS_IsUndefined(existing)) {
                try put(engine, state, "existing", existing);
                const pending = try scope.invoke(tx, "task", &.{existing});
                return wait(engine, state, pending, .previous);
            }
            const input = try scope.own(try vm.object(engine));
            try @import("native_tool_info.zig").putData(engine, input, "kind", try engine.checked(c.JS_NewString(engine.context, "nested")));
            try put(engine, input, "parent", try scope.get(runtime, "taskId"));
            try put(engine, input, "parentCallId", try scope.get(state, "parentCallId"));
            try put(engine, input, "key", key);
            try put(engine, input, "call", call);
            const progress = try scope.get(state, "progress");
            if (c.JS_IsStrictEqual(engine.context, progress, c.pi_js_bool(engine.context, 0))) try put(engine, input, "progress", c.pi_js_bool(engine.context, 0));
            const ownership = try scope.own(try vm.object(engine));
            try @import("native_tool_info.zig").putData(engine, ownership, "kind", try engine.checked(c.JS_NewString(engine.context, "task")));
            try put(engine, ownership, "taskId", try scope.get(runtime, "taskId"));
            const options = try scope.own(try vm.object(engine));
            try put(engine, options, "ownership", ownership);
            try put(engine, options, "abandonOnRestart", try scope.get(state, "abandonOnRestart"));
            const token = try scope.get(state, "taskToken");
            const pending = try scope.invoke(tx, "createTask", &.{ token, input, options });
            return wait(engine, state, pending, .created);
        },
        .previous => {
            const input = if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) c.pi_js_undefined() else try scope.get(value, "input");
            var same = false;
            if (!c.JS_IsUndefined(input) and !c.JS_IsNull(input) and try @import("native_durable_tool_call.zig").equalsString(engine, try scope.get(input, "kind"), "nested")) {
                const parent = try scope.get(input, "parent");
                const owner = try scope.get(runtime, "taskId");
                if (c.JS_IsStrictEqual(engine.context, parent, owner)) {
                    const previous = try scope.get(input, "call");
                    const previous_name = try scope.get(previous, "name");
                    const name = try scope.get(state, "name");
                    if (c.JS_IsStrictEqual(engine.context, previous_name, name)) same = try @import("native_durable_tool_json.zig").equal(engine, try scope.get(previous, "arguments"), try scope.get(call, "arguments"));
                }
            }
            if (!same) {
                const id = try engine.toString(try scope.get(call, "id"));
                defer engine.gpa.free(id);
                const message = try std.fmt.allocPrint(engine.gpa, "Nested call {s} was already made with another tool or other arguments", .{id});
                defer engine.gpa.free(message);
                return @import("native_sdk.zig").sourceError(engine, message);
            }
            try put(engine, state, "id", try scope.get(state, "existing"));
            return c.pi_js_undefined();
        },
        .created => {
            try put(engine, state, "created", value);
            const index = try scope.get(state, "index");
            const calls = try scope.get(index, "calls");
            try js.setKey(engine, calls, key, value);
            const token = try scope.get(state, "liveToken");
            const conversation = try scope.get(runtime, "conversationId");
            const pending = try scope.invoke(tx, "doc", &.{ token, conversation });
            return wait(engine, state, pending, .live);
        },
        .live => {
            const nested = try scope.get(value, "nestedTools");
            if (c.JS_IsUndefined(nested) or c.JS_IsNull(nested)) try vm.put(engine, value, "nestedTools", try vm.array(engine));
            const slot = try scope.own(try vm.object(engine));
            try put(engine, slot, "callId", try scope.get(call, "id"));
            try put(engine, slot, "parentCallId", try scope.get(state, "parentCallId"));
            try put(engine, slot, "parentTaskId", try scope.get(runtime, "taskId"));
            try put(engine, slot, "name", try scope.get(state, "name"));
            const created = try scope.get(state, "created");
            try put(engine, slot, "taskId", created);
            try put(engine, slot, "arguments", try scope.get(call, "arguments"));
            try @import("native_tool_info.zig").putData(engine, slot, "status", try engine.checked(c.JS_NewString(engine.context, "pending")));
            const target = try scope.get(value, "nestedTools");
            _ = try scope.invoke(target, "push", &.{slot});
            try put(engine, state, "id", created);
            return c.pi_js_undefined();
        },
        .committed => unreachable,
    }
}

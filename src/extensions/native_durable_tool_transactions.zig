//! Tool API transactions return the user's result without reporting a task
//! state transition. Each concurrent call has its own retained result cell.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Action = enum(c_int) { commit, createTask };
const Stage = enum(c_int) { changed, created, committed };
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
pub fn commitFunction(engine: *Engine, attempt: c.JSValue) !c.JSValue {
    return function(engine, attempt, .commit);
}
pub fn createTaskFunction(engine: *Engine, attempt: c.JSValue) !c.JSValue {
    return function(engine, attempt, .createTask);
}
fn function(engine: *Engine, attempt: c.JSValue, action: Action) !c.JSValue {
    var captures = [_]c.JSValue{attempt};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, if (action == .commit) "commit" else "createTask", if (action == .commit) 2 else 4, @intFromEnum(action), captures.len, &captures));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw_action: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return invoke(engine, data[0], @enumFromInt(raw_action), argv[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn wait(engine: *Engine, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const attempt = try scope.get(state, "attempt");
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(attempt, "promiseConstructor"), .resolve = try scope.get(attempt, "promiseResolve"), .then_function = try scope.get(attempt, "promiseThen") };
    return awaiting.continueWith(advance, engine, &intrinsics, state, value, @intFromEnum(stage));
}
fn invoke(engine: *Engine, attempt: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    try put(engine, state, "attempt", attempt);
    try put(engine, state, "create", c.pi_js_bool(engine.context, @intFromBool(action == .createTask)));
    const context = if (action == .commit) (if (args.len > 1) args[1] else c.pi_js_undefined()) else (if (args.len > 3) args[3] else c.pi_js_undefined());
    if (action == .commit) {
        try put(engine, state, "change", if (args.len > 0) args[0] else c.pi_js_undefined());
    } else {
        try put(engine, state, "task", if (args.len > 0) args[0] else c.pi_js_undefined());
        try put(engine, state, "input", if (args.len > 1) args[1] else c.pi_js_undefined());
        const options = if (args.len > 2) args[2] else c.pi_js_undefined();
        const ownership = try scope.get(options, "ownership");
        const kind = try scope.get(ownership, "kind");
        const abandon = try @import("native_durable_tool_call.zig").equalsString(engine, kind, "task") and c.JS_ToBool(engine.context, try scope.get(attempt, "resumes")) == 0;
        const child = if (abandon) child: {
            const value = try scope.own(try vm.object(engine));
            try put(engine, value, "abandonOnRestart", c.pi_js_bool(engine.context, 1));
            try js.spreadInto(engine, value, options);
            break :child value;
        } else options;
        try put(engine, state, "options", child);
    }
    var captures = [_]c.JSValue{state};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, transaction, "", 1, 0, captures.len, &captures)));
    const runtime = try scope.get(attempt, "runtime");
    const pending = try scope.invoke(runtime, "commit", &.{ callback, context });
    return wait(engine, state, pending, .committed);
}
fn transaction(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return change(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn change(engine: *Engine, state: c.JSValue, tx: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_ToBool(engine.context, try scope.get(state, "create")) != 0) {
        const pending = try scope.invoke(tx, "createTask", &.{ try scope.get(state, "task"), try scope.get(state, "input"), try scope.get(state, "options") });
        return wait(engine, state, pending, .created);
    }
    const callback = try scope.get(state, "change");
    var args = [_]c.JSValue{tx};
    const pending = try scope.own(try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), args.len, &args)));
    return wait(engine, state, pending, .changed);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    if (@as(Stage, @enumFromInt(raw_stage)) == .committed) return vm.get(engine, state, "value");
    try put(engine, state, "value", value);
    return c.pi_js_undefined();
}

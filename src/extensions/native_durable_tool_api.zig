//! Per-attempt ToolExecutionApi. The execution driver owns the shared ended
//! fence; task/nested operations are genuine native closures supplied by it.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const window = @import("native_durable_output_limits.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Operations = struct { commit: c.JSValue, create_task: c.JSValue, execute_tool: c.JSValue };
const Action = enum(c_int) { output, retainedOutput, diagnostic, details };
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
pub fn create(engine: *Engine, state: c.JSValue, limits: window.Limits, operations: Operations) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(state, "runtime");
    const call = try scope.get(state, "call");
    const api = try vm.object(engine);
    errdefer engine.freeValue(api);
    try put(engine, api, "taskId", try scope.get(runtime, "taskId"));
    try put(engine, api, "conversationId", try scope.get(runtime, "conversationId"));
    try put(engine, api, "callId", try scope.get(call, "id"));
    inline for (.{ "registry", "agent", "models" }) |name| try put(engine, api, name, try scope.get(runtime, name));
    try installAction(engine, api, state, .output);
    const output_window = if (limits.retain == .tail) output_window: {
        const result = try scope.own(try vm.object(engine));
        try put(engine, result, "maxBytes", c.JS_NewFloat64(engine.context, limits.maxBytes));
        try put(engine, result, "maxLines", c.JS_NewFloat64(engine.context, limits.maxLines));
        const settings = try scope.get(runtime, "settings");
        const progress = try scope.get(settings, "progress");
        try put(engine, result, "minIntervalMs", try scope.get(progress, "outputIntervalMs"));
        try put(engine, result, "bytesPerSecond", c.JS_NewInt32(engine.context, 100 * 1024));
        break :output_window result;
    } else c.pi_js_undefined();
    try put(engine, api, "outputWindow", output_window);
    inline for (.{ Action.retainedOutput, Action.diagnostic, Action.details }) |action| try installAction(engine, api, state, action);
    try put(engine, api, "commit", operations.commit);
    try put(engine, api, "memo", try scope.get(runtime, "memo"));
    try put(engine, api, "createTask", operations.create_task);
    inline for (.{ "getTask", "waitForTask", "conversation", "snapshot", "snapshotAsOf", "watchDoc" }) |name| try put(engine, api, name, try scope.get(runtime, name));
    try put(engine, api, "executeTool", operations.execute_tool);
    return api;
}
fn installAction(engine: *Engine, api: c.JSValue, state: c.JSValue, action: Action) !void {
    var captures = [_]c.JSValue{state};
    const arity: c_int = switch (action) {
        .output, .details => 2,
        .diagnostic => 1,
        .retainedOutput => 0,
    };
    const name: [:0]const u8 = switch (action) {
        inline else => |tag| @tagName(tag),
    };
    try @import("native_tool_info.zig").putData(engine, api, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, name, arity, @intFromEnum(action), captures.len, &captures)));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw_action: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const action: Action = @enumFromInt(raw_action);
    return act(engine, data[0], action, argv[0..@intCast(argc)]) catch |err| if (action == .details) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
}
fn assertLive(engine: *Engine, state: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_ToBool(engine.context, try scope.get(state, "ended")) == 0) return;
    const call = try scope.get(state, "call");
    const id = try engine.toString(try scope.get(call, "id"));
    defer engine.gpa.free(id);
    const message = try std.fmt.allocPrint(engine.gpa, "Tool call {s} has settled", .{id});
    defer engine.gpa.free(message);
    _ = try @import("native_sdk.zig").sourceError(engine, message);
}
fn copy(engine: *Engine, value: c.JSValue) !c.JSValue {
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    try put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    return @import("native_chord_json.zig").copyJson(engine, value, options);
}
fn act(engine: *Engine, state: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    try assertLive(engine, state);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const reported = try scope.get(state, "reported");
    const progress = try scope.get(state, "progress");
    switch (action) {
        .output => {
            const buffer = try scope.get(reported, "output");
            const accepted = try scope.invoke(buffer, "push", &.{ if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined() });
            if (c.JS_ToBool(engine.context, accepted) != 0) _ = try scope.invoke(progress, "mark", &.{});
            return c.pi_js_undefined();
        },
        .retainedOutput => {
            const buffer = try scope.get(reported, "output");
            const retained = try scope.invoke(buffer, "snapshot", &.{});
            const result = try vm.object(engine);
            errdefer engine.freeValue(result);
            try put(engine, result, "text", try scope.get(retained, "text"));
            var dropped: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &dropped, try scope.get(retained, "droppedBytes")) < 0) return js.capture(engine);
            try put(engine, result, "truncated", c.pi_js_bool(engine.context, @intFromBool(dropped > 0)));
            return result;
        },
        .diagnostic => {
            const diagnostics = try scope.get(reported, "diagnostics");
            const cloned = try scope.own(try copy(engine, if (args.len > 0) args[0] else c.pi_js_undefined()));
            _ = try scope.invoke(diagnostics, "push", &.{cloned});
            _ = try scope.invoke(progress, "mark", &.{});
            return c.pi_js_undefined();
        },
        .details => {
            const context = if (args.len > 1) args[1] else c.pi_js_undefined();
            const signal = try scope.get(context, "abortSignal");
            if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
            const cloned = try scope.own(try copy(engine, if (args.len > 0) args[0] else c.pi_js_undefined()));
            try put(engine, reported, "details", cloned);
            const committed = try scope.invoke(progress, "markAndWait", &.{});
            const ignored_callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, ignore, "", 0)));
            _ = try scope.invoke(committed, "catch", &.{ignored_callback});
            const awaited = try scope.own(try @import("native_durable_context.zig").awaitWithContext(engine, committed, context));
            const fulfilled = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, identity, "", 1)));
            const constructor = try scope.get(state, "promiseConstructor");
            const resolve = try scope.get(state, "promiseResolve");
            const then_function = try scope.get(state, "promiseThen");
            var intrinsics: @import("native_durable_await.zig").Intrinsics = .{ .constructor = constructor, .resolve = resolve, .then_function = then_function };
            return intrinsics.chain(engine, awaited, fulfilled, c.pi_js_undefined());
        },
    }
}
fn ignore(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn identity(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, if (argc > 0) argv[0] else c.pi_js_undefined());
}

//! The real built-in pi.tool v2 definition and its native phase handlers.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const awaiting = @import("native_durable_await.zig");
const output = @import("native_durable_tool_output.zig");
const preparing = @import("native_durable_tool_task.zig");
const executing = @import("native_durable_tool_execute.zig");
const window = @import("native_durable_output_limits.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Handler = enum(c_int) { call, execute, abort };
const Stage = enum(c_int) { checked, intent, recovered };
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
};
fn put(engine: *Engine, state: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, state, key, c.JS_DupValue(engine.context, value));
}
fn captured(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
}
fn tokens(scope: *Scope, state: c.JSValue) !preparing.Tokens {
    return .{ .assistant = try scope.get(state, "assistantToken"), .terminal = .{ .live = try scope.get(state, "liveToken"), .nested_calls = try scope.get(state, "nestedCallsToken"), .nested_results = try scope.get(state, "nestedResultToken"), .tool_result = try scope.get(state, "toolResultToken"), .usage = try scope.get(state, "usageToken"), .iterator_symbol = try scope.get(state, "iterator") } };
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.own(try vm.object(engine));
    var intrinsics = try awaiting.Intrinsics.init(engine);
    defer intrinsics.deinit(engine);
    var cache = try output.Cache.init(engine);
    defer cache.deinit();
    inline for (.{ .{ "promiseConstructor", intrinsics.constructor }, .{ "promiseResolve", intrinsics.resolve }, .{ "promiseThen", intrinsics.then_function }, .{ "weak", cache.weak }, .{ "iterator", cache.iterator_symbol } }) |field| try put(engine, state, field[0], field[1]);
    inline for (.{ .{ "AssistantEntry", "assistantToken" }, .{ "LiveDoc", "liveToken" }, .{ "NestedCallDoc", "nestedResultToken" }, .{ "ToolResultEntry", "toolResultToken" }, .{ "UsageDoc", "usageToken" } }) |field| try put(engine, state, field[1], try scope.get(exports, field[0]));
    const index = try scope.get(exports, "NestedCallDoc");
    try put(engine, state, "nestedCallsToken", index);
    var pattern_args = [_]c.JSValue{ try scope.own(try engine.checked(c.JS_NewString(engine.context, "[\\x00-\\x08\\x0b-\\x1f\\ufff9-\\ufffb]"))), try scope.own(try engine.checked(c.JS_NewString(engine.context, "g"))) };
    const pattern = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, pattern_args.len, &pattern_args)));
    try put(engine, state, "pattern", pattern);
    const definition = try scope.own(try vm.object(engine));
    try @import("native_tool_info.zig").putData(engine, definition, "name", try engine.checked(c.JS_NewString(engine.context, "pi.tool")));
    try put(engine, definition, "version", c.JS_NewInt32(engine.context, 2));
    try @import("native_tool_info.zig").putData(engine, definition, "initial", try engine.checked(c.JS_NewCFunction(engine.context, initial, "initial", 0)));
    try @import("native_tool_info.zig").putData(engine, definition, "migrate", try engine.checked(c.JS_NewCFunction(engine.context, migrate, "migrate", 2)));
    const phases = try scope.own(try vm.object(engine));
    inline for (.{ Handler.call, Handler.execute }) |handler| {
        var data = [_]c.JSValue{state};
        const name: [:0]const u8 = @tagName(handler);
        try @import("native_tool_info.zig").putData(engine, phases, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, name, 3, @intFromEnum(handler), data.len, &data)));
    }
    try put(engine, definition, "phases", phases);
    var data = [_]c.JSValue{state};
    try @import("native_tool_info.zig").putData(engine, definition, "abort", try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "abort", 3, @intFromEnum(Handler.abort), data.len, &data)));
    const token = try scope.own(try vm.object(engine));
    try put(engine, token, "definition", definition);
    try put(engine, state, "toolTaskToken", token);
    try put(engine, exports, "ToolTask", token);
}
pub fn indexToken(engine: *Engine) !c.JSValue {
    const definition = try vm.object(engine);
    defer engine.freeValue(definition);
    try @import("native_tool_info.zig").putData(engine, definition, "kind", try engine.checked(c.JS_NewString(engine.context, "pi.tool.nested-call")));
    try put(engine, definition, "version", c.JS_NewInt32(engine.context, 1));
    try @import("native_tool_info.zig").putData(engine, definition, "scope", try engine.checked(c.JS_NewString(engine.context, "task")));
    try put(engine, definition, "family", c.pi_js_bool(engine.context, 1));
    try @import("native_tool_info.zig").putData(engine, definition, "initial", try engine.checked(c.JS_NewCFunction(engine.context, indexInitial, "initial", 0)));
    const token = try vm.object(engine);
    errdefer engine.freeValue(token);
    try put(engine, token, "definition", definition);
    return token;
}
fn initial(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const result = vm.object(engine) catch |err| return @import("native_durable.zig").reject(engine, err);
    @import("native_tool_info.zig").putData(engine, result, "phase", engine.checked(c.JS_NewString(engine.context, "call")) catch |err| {
        engine.freeValue(result);
        return @import("native_durable.zig").reject(engine, err);
    }) catch |err| {
        engine.freeValue(result);
        return @import("native_durable.zig").reject(engine, err);
    };
    return result;
}
fn indexInitial(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return indexInitialOwned(engine) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn indexInitialOwned(engine: *Engine) !c.JSValue {
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    return result;
}
fn migrate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return migrateOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn migrateOwned(engine: *Engine, input: c.JSValue, checkpoint: c.JSValue) !c.JSValue {
    const next = try vm.object(engine);
    defer engine.freeValue(next);
    try @import("native_tool_info.zig").putData(engine, next, "kind", try engine.checked(c.JS_NewString(engine.context, "model")));
    try js.spreadInto(engine, next, input);
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "input", next);
    try put(engine, result, "checkpoint", checkpoint);
    return result;
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw_handler: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return begin(engine, data[0], @enumFromInt(raw_handler), argv[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn begin(engine: *Engine, module: c.JSValue, handler: Handler, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var intrinsics = try captured(&scope, module);
    const values = try tokens(&scope, module);
    const task = if (args.len > 0) args[0] else c.pi_js_undefined();
    const runtime = if (args.len > 1) args[1] else c.pi_js_undefined();
    const context = if (args.len > 2) args[2] else c.pi_js_undefined();
    if (handler == .abort) return preparing.abort(engine, &intrinsics, values, task, runtime, context);
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "module", module }, .{ "task", task }, .{ "runtime", runtime }, .{ "context", context } }) |field| try put(engine, state, field[0], field[1]);
    const pending = if (handler == .call) try preparing.prepareCall(engine, &intrinsics, values, task, runtime, context) else try preparing.prepareRecovery(engine, &intrinsics, values, task, runtime, context);
    defer engine.freeValue(pending);
    return awaiting.continueWith(advance, engine, &intrinsics, state, pending, @intFromEnum(if (handler == .call) Stage.checked else Stage.recovered));
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw_stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    const stage: Stage = @enumFromInt(raw_stage);
    if (stage != .intent and c.JS_IsUndefined(value)) return c.pi_js_undefined();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const module = try scope.get(state, "module");
    var intrinsics = try captured(&scope, module);
    const runtime = try scope.get(state, "runtime");
    const task = try scope.get(state, "task");
    const context = try scope.get(state, "context");
    if (stage == .checked) {
        try put(engine, state, "prepared", value);
        const live = try scope.get(module, "liveToken");
        const pending = try @import("native_durable_tool_intent.zig").commit(engine, &intrinsics, live, task, runtime, value, context, false);
        defer engine.freeValue(pending);
        return awaiting.continueWith(advance, engine, &intrinsics, state, pending, @intFromEnum(Stage.intent));
    }
    const prepared = if (stage == .intent) try scope.get(state, "prepared") else value;
    const tool = try scope.get(prepared, "tool");
    const limits = try outputLimits(engine, tool);
    var cache: output.Cache = .{ .engine = engine, .weak = try scope.get(module, "weak"), .iterator_symbol = try scope.get(module, "iterator") };
    const values = try tokens(&scope, module);
    return executing.run(engine, &intrinsics, &cache, .{ .tool_task = try scope.get(module, "toolTaskToken"), .terminal = values.terminal, .sanitize_pattern = try scope.get(module, "pattern") }, limits, runtime, try scope.get(task, "input"), try scope.get(prepared, "call"), tool, try scope.get(prepared, "arguments"), context);
}
fn optionalLimit(engine: *Engine, tool: c.JSValue, name: [:0]const u8, default: f64) !f64 {
    const options = try vm.get(engine, tool, "outputLimits");
    defer engine.freeValue(options);
    if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) return default;
    const value = try vm.get(engine, options, name);
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return default;
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return js.capture(engine);
    return number;
}
fn outputLimits(engine: *Engine, tool: c.JSValue) !window.Limits {
    const max_bytes = try optionalLimit(engine, tool, "maxBytes", 50 * 1024);
    const max_lines = try optionalLimit(engine, tool, "maxLines", 2000);
    const options = try vm.get(engine, tool, "outputLimits");
    defer engine.freeValue(options);
    const retain = if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) c.pi_js_undefined() else try vm.get(engine, options, "retain");
    defer engine.freeValue(retain);
    const retention: window.Retention = if (c.JS_IsUndefined(retain) or c.JS_IsNull(retain) or try @import("native_durable_tool_call.zig").equalsString(engine, retain, "head")) .head else if (try @import("native_durable_tool_call.zig").equalsString(engine, retain, "tail")) .tail else .other;
    return .{ .maxBytes = max_bytes, .maxLines = max_lines, .retain = retention };
}

//! Source timing module with its real PI_TIMING import-time gate and live JS
//! Date, collection, iterator and console callback evaluation.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn create(engine: *em.Engine) !c.JSValue {
    const name = "pi-native:timings";
    if (engine.native_module_values.get(name)) |exports| return c.JS_DupValue(engine.context, exports);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const environment = try scope.get(try scope.global("process"), "env");
    const enabled = c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(environment, "PI_TIMING"), try scope.text("1"))));
    const namespaces = try scope.own(try js.builtin(engine, "Map", &.{}));
    const exports = try scope.object();
    try scope.put(exports, "resetTimings", try scope.own(try @import("native_node_function.zig").create(engine, "resetTimings", 0, reset, &.{ enabled, namespaces })));
    try scope.put(exports, "time", try scope.own(try @import("native_node_function.zig").create(engine, "time", 1, time, &.{ enabled, namespaces })));
    try scope.put(exports, "printTimings", try scope.own(try @import("native_node_function.zig").create(engine, "printTimings", 0, print, &.{ enabled, namespaces })));
    try engine.registerValueModule(name, exports);
    return c.JS_DupValue(engine.context, exports);
}
fn now(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Date"), "now", &.{});
}
fn selected(scope: *Scope, args: []const c.JSValue, index: usize) !c.JSValue {
    const value = if (args.len > index) args[index] else c.pi_js_undefined();
    return if (c.JS_IsUndefined(value)) scope.text("main") else value;
}
fn resetBody(scope: *Scope, namespaces: c.JSValue, namespace: c.JSValue) !void {
    const set = try scope.get(namespaces, "set");
    const timing = try scope.object();
    try scope.put(timing, "timings", try scope.array());
    try scope.put(timing, "lastTime", try now(scope));
    _ = try scope.call(set, namespaces, &.{ namespace, timing });
}
fn reset(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const namespace = try selected(&scope, args, 0);
    if (!scope.truthy(roots[0])) return c.pi_js_undefined();
    try resetBody(&scope, roots[1], namespace);
    return c.pi_js_undefined();
}
fn time(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const label = if (args.len > 0) args[0] else c.pi_js_undefined();
    const namespace = try selected(&scope, args, 1);
    if (!scope.truthy(roots[0])) return c.pi_js_undefined();
    const current = try now(&scope);
    if (!scope.truthy(try scope.invoke(roots[1], "has", &.{namespace}))) try resetBody(&scope, roots[1], namespace);
    const timing = try scope.invoke(roots[1], "get", &.{namespace});
    const rows = try scope.get(timing, "timings");
    const push = try scope.get(rows, "push");
    const row = try scope.object();
    try scope.put(row, "label", label);
    try scope.put(row, "ms", try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, current, try scope.get(timing, "lastTime")))));
    _ = try scope.call(push, rows, &.{row});
    try scope.set(timing, "lastTime", current);
    return c.pi_js_undefined();
}
fn filter(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return printable(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn printable(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 7, try scope.get(input, "ms"), c.JS_NewInt32(engine.context, 0)));
}
fn sum(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return summed(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn summed(engine: *em.Engine, total: c.JSValue, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 0, total, try scope.get(input, "ms")));
}
fn logFunction(scope: *Scope) !struct { console: c.JSValue, function: c.JSValue } {
    const console = try scope.global("console");
    return .{ .console = console, .function = try scope.get(console, "error") };
}
fn group(scope: *Scope, title: c.JSValue, timings: c.JSValue) !void {
    const method = try scope.get(timings, "filter");
    const predicate = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, filter, "", 1)));
    const rows = try scope.call(method, timings, &.{predicate});
    if (scope.equal(try scope.get(rows, "length"), c.JS_NewInt32(scope.engine.context, 0))) return;
    {
        const log = try logFunction(scope);
        const text = try scope.concat(try scope.concat(try scope.text("\n--- "), try scope.stringify(title)), try scope.text(" ---"));
        _ = try scope.call(log.function, log.console, &.{text});
    }
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, rows, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |timing| {
        defer scope.engine.freeValue(timing);
        const log = try logFunction(scope);
        const prefix = try scope.concat(try scope.concat(try scope.text("  "), try scope.stringify(try scope.get(timing, "label"))), try scope.text(": "));
        const text = try scope.concat(try scope.concat(prefix, try scope.stringify(try scope.get(timing, "ms"))), try scope.text("ms"));
        _ = try scope.call(log.function, log.console, &.{text});
    }
    {
        const log = try logFunction(scope);
        const reduce = try scope.get(rows, "reduce");
        const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, sum, "", 2)));
        const total = try scope.call(reduce, rows, &.{ callback, c.JS_NewInt32(scope.engine.context, 0) });
        const text = try scope.concat(try scope.concat(try scope.text("  TOTAL: "), try scope.stringify(total)), try scope.text("ms"));
        _ = try scope.call(log.function, log.console, &.{text});
    }
    {
        const log = try logFunction(scope);
        const dash = try scope.text("-");
        const repeat = try scope.get(dash, "repeat");
        const count = try scope.concat(try scope.get(title, "length"), c.JS_NewInt32(scope.engine.context, 8));
        const text = try scope.concat(try scope.stringify(try scope.call(repeat, dash, &.{count})), try scope.text("\n"));
        _ = try scope.call(log.function, log.console, &.{text});
    }
}
fn print(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(roots[0])) return c.pi_js_undefined();
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, roots[1], symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer engine.freeValue(pair[0]);
        defer engine.freeValue(pair[1]);
        const title = try scope.concat(try scope.text("Startup Timings: "), try scope.stringify(pair[0]));
        try group(&scope, title, try scope.get(pair[1], "timings"));
    }
    return c.pi_js_undefined();
}

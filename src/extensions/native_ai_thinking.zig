//! Original pi-ai thinking helpers, separate from AgentSession selection.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const levels = [_][]const u8{ "off", "minimal", "low", "medium", "high", "xhigh", "max" };
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const ordered = try scope.array();
    for (levels, 0..) |name, i| try scope.index(ordered, @intCast(i), try scope.text(name));
    const exports = try scope.object();
    inline for (.{ "getSupportedThinkingLevels", "clampThinkingLevel" }, 0..) |name, kind| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return if (kind == 0) supported(host, roots[0], arg(args, 0)) else clamp(host, roots[0], arg(args, 0), arg(args, 1));
            }
        };
        try scope.put(exports, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (kind == 0) 1 else 2, Adapter.call, &.{ordered})));
    }
    return c.JS_DupValue(engine.context, exports);
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (args.len > i) args[i] else c.pi_js_undefined();
}
fn at(scope: *Scope, value: c.JSValue, i: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, value, i));
}
fn allowed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const host = em.Engine.fromContext(context.?);
    return allow(host, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(host, err);
}
fn allow(engine: *em.Engine, model: c.JSValue, level: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const map = try scope.get(model, "thinkingLevelMap");
    const mapped = if (temp.nullish(map)) c.pi_js_undefined() else try scope.own(try js.getKey(engine, map, level));
    if (c.JS_IsNull(mapped)) return c.pi_js_bool(engine.context, 0);
    if (scope.equal(level, try scope.text("xhigh")) or scope.equal(level, try scope.text("max"))) return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(mapped)));
    return c.pi_js_bool(engine.context, 1);
}
fn supported(engine: *em.Engine, ordered: c.JSValue, model: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(model, "reasoning"))) {
        const result = try scope.array();
        try scope.index(result, 0, try scope.text("off"));
        return c.JS_DupValue(engine.context, result);
    }
    const function = try scope.get(ordered, "filter");
    var roots = [_]c.JSValue{model};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, allowed, "", 1, 0, roots.len, &roots)));
    return js.call(engine, function, ordered, &.{callback});
}
fn clamp(engine: *em.Engine, ordered: c.JSValue, model: c.JSValue, requested: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const available = try scope.own(try supported(engine, ordered, model));
    if (scope.truthy(try scope.invoke(available, "includes", &.{requested}))) return c.JS_DupValue(engine.context, requested);
    const start = try scope.invoke(ordered, "indexOf", &.{requested});
    if (scope.equal(start, c.JS_NewInt32(engine.context, -1))) {
        const first = try at(&scope, available, c.JS_NewInt32(engine.context, 0));
        return c.JS_DupValue(engine.context, if (temp.nullish(first)) try scope.text("off") else first);
    }
    var index = start;
    var steps: usize = 0;
    while (try arithmetic.compare(engine, .less, index, try scope.get(ordered, "length"))) {
        try @import("native_ai_budget.zig").step(engine, &steps);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        const candidate = try at(&step, ordered, index);
        if (step.truthy(try step.invoke(available, "includes", &.{candidate}))) return c.JS_DupValue(engine.context, candidate);
        index = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, index)));
    }
    index = try scope.own(try arithmetic.binary(engine, .subtract, start, c.JS_NewInt32(engine.context, 1)));
    while (try arithmetic.compare(engine, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) {
        try @import("native_ai_budget.zig").step(engine, &steps);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        const candidate = try at(&step, ordered, index);
        if (step.truthy(try step.invoke(available, "includes", &.{candidate}))) return c.JS_DupValue(engine.context, candidate);
        index = try scope.own(try arithmetic.binary(engine, .subtract, index, c.JS_NewInt32(engine.context, 1)));
    }
    const first = try at(&scope, available, c.JS_NewInt32(engine.context, 0));
    return c.JS_DupValue(engine.context, if (temp.nullish(first)) try scope.text("off") else first);
}

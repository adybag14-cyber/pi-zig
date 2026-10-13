//! Source pi-ai model equality and thinking capability values. VM values,
//! mutable collection methods, getters and coercion order remain observable.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
pub fn extended(scope: *Scope) !c.JSValue {
    const values = try scope.array();
    inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }, 0..) |name, index| try scope.index(values, index, try scope.text(name));
    return values;
}
pub fn bindings(engine: *em.Engine) !c.JSValue {
    if (engine.native_ai_model_values) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const levels = try extended(&scope);
    const exports = try scope.object();
    inline for (.{ "getSupportedThinkingLevels", "clampThinkingLevel", "modelsAreEqual" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                const first = if (args.len > 0) args[0] else c.pi_js_undefined();
                const second = if (args.len > 1) args[1] else c.pi_js_undefined();
                return switch (index) {
                    0 => supported(host, values[0], first),
                    1 => clamp(host, values[0], first, second),
                    else => c.pi_js_bool(host.context, @intFromBool(try equal(host, first, second))),
                };
            }
        };
        try scope.put(exports, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (index == 0) 1 else 2, Adapter.call, &.{levels})));
    }
    engine.native_ai_model_values = c.JS_DupValue(engine.context, exports);
    return c.JS_DupValue(engine.context, exports);
}
pub fn modelType(scope: *Scope, model: c.JSValue) !c.JSValue {
    const value = try scope.get(model, "type");
    return if (temp.nullish(value)) scope.text("chat") else value;
}
pub fn equal(engine: *em.Engine, left: c.JSValue, right: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(left) or !scope.truthy(right)) return false;
    return scope.equal(try modelType(&scope, left), try modelType(&scope, right)) and scope.equal(try scope.get(left, "id"), try scope.get(right, "id")) and scope.equal(try scope.get(left, "provider"), try scope.get(right, "provider"));
}
fn supported(engine: *em.Engine, levels: c.JSValue, model: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(model, "reasoning"))) {
        const result = try scope.array();
        try scope.index(result, 0, try scope.text("off"));
        return c.JS_DupValue(engine.context, result);
    }
    const filter = try scope.get(levels, "filter");
    var roots = [_]c.JSValue{model};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, supportedFilter, "", 1, 0, roots.len, &roots)));
    return js.call(engine, filter, levels, &.{callback});
}
fn supportedFilter(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return filterValue(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn filterValue(engine: *em.Engine, model: c.JSValue, level: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const map = try scope.get(model, "thinkingLevelMap");
    const mapped = if (temp.nullish(map)) c.pi_js_undefined() else try scope.own(try js.getKey(engine, map, level));
    const answer = if (c.JS_IsNull(mapped)) false else if (scope.equal(level, try scope.text("xhigh")) or scope.equal(level, try scope.text("max"))) !c.JS_IsUndefined(mapped) else true;
    return c.pi_js_bool(engine.context, @intFromBool(answer));
}
fn budget(engine: *em.Engine, steps: usize) !void {
    if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and block: {
        engine.interrupts +|= 1;
        break :block engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn included(scope: *Scope, values: c.JSValue, value: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(values, "includes", &.{value}));
}
fn clamp(engine: *em.Engine, levels: c.JSValue, model: c.JSValue, requested: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const available = try scope.own(try supported(engine, levels, model));
    if (try included(&scope, available, requested)) return c.JS_DupValue(engine.context, requested);
    const position = try scope.invoke(levels, "indexOf", &.{requested});
    if (scope.equal(position, c.JS_NewInt32(engine.context, -1))) return firstOrOff(engine, available);
    var index = c.JS_DupValue(engine.context, position);
    defer engine.freeValue(index);
    var steps: usize = 0;
    while (forward: {
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        break :forward try arithmetic.compare(engine, .less, index, try iteration.get(levels, "length"));
    }) {
        steps +|= 1;
        try budget(engine, steps);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        const candidate = try iteration.own(try js.getKey(engine, levels, index));
        if (try included(&iteration, available, candidate)) return c.JS_DupValue(engine.context, candidate);
        const next = try engine.checked(c.JS_PiIncrement(engine.context, index));
        engine.freeValue(index);
        index = next;
    }
    const previous = try arithmetic.binary(engine, .subtract, position, c.JS_NewInt32(engine.context, 1));
    engine.freeValue(index);
    index = previous;
    while (try arithmetic.compare(engine, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) {
        steps +|= 1;
        try budget(engine, steps);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        const candidate = try iteration.own(try js.getKey(engine, levels, index));
        if (try included(&iteration, available, candidate)) return c.JS_DupValue(engine.context, candidate);
        const next = try arithmetic.binary(engine, .subtract, index, c.JS_NewInt32(engine.context, 1));
        engine.freeValue(index);
        index = next;
    }
    return firstOrOff(engine, available);
}
fn firstOrOff(engine: *em.Engine, values: c.JSValue) !c.JSValue {
    const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, 0));
    if (!temp.nullish(value)) return value;
    engine.freeValue(value);
    return sdk.text(engine, "off");
}

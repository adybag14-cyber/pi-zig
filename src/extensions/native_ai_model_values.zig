//! Source pi-ai model equality and thinking capability values. VM values,
//! mutable collection methods, getters and coercion order remain observable.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const live = @import("native_sdk_session_locals.zig");
const pv = live.v;
pub fn extended(scope: *Scope) !c.JSValue {
    const values = try scope.array();
    inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }, 0..) |name, index| try scope.index(values, index, try scope.text(name));
    return values;
}
pub fn bindings(engine: *em.Engine) !c.JSValue {
    if (engine.native_ai_model_values) |cached| return c.JS_DupValue(engine.context, cached);
    const candidate = try live.expression(engine, bindingsBody, .{});
    // Guest-visible function creation may reenter this real module owner.
    if (engine.native_ai_model_values) |cached| {
        var completion = pv.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, cached));
        completion.release(candidate);
        return completion.finishValue();
    }
    engine.native_ai_model_values = candidate;
    return c.JS_DupValue(engine.context, candidate);
}
fn bindingsBody(scope: *pv.Scope) !c.JSValue {
    const levels = try pv.array(scope);
    inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }, 0..) |name, index|
        try pv.index(scope, levels, index, try pv.text(scope, name));
    const exports = try pv.object(scope);
    inline for (.{ "getSupportedThinkingLevels", "clampThinkingLevel", "modelsAreEqual" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                const first = pv.arg(args, 0);
                const second = pv.arg(args, 1);
                return switch (index) {
                    0 => supported(host, captures[0], first),
                    1 => clamp(host, captures[0], first, second),
                    else => c.pi_js_bool(host.context, @intFromBool(try equal(host, first, second))),
                };
            }
        };
        try pv.put(scope, exports, name, try pv.ordinary(scope, name, if (index == 0) 1 else 2, Adapter.call, &.{levels}));
    }
    return pv.duplicate(scope, exports);
}

pub fn modelType(scope: *Scope, model: c.JSValue) !c.JSValue {
    const value = try scope.get(model, "type");
    return if (temp.nullish(value)) scope.text("chat") else value;
}
pub fn equal(engine: *em.Engine, left: c.JSValue, right: c.JSValue) !bool {
    if (!live.truthy(engine, left) or !live.truthy(engine, right)) return false;
    if (!live.truthy(engine, try live.expression(engine, typeEqual, .{ left, right }))) return false;
    if (!live.truthy(engine, try live.expression(engine, fieldEqual, .{ left, right, @as([*:0]const u8, "id") }))) return false;
    return live.truthy(engine, try live.expression(engine, fieldEqual, .{ left, right, @as([*:0]const u8, "provider") }));
}
fn typeValue(scope: *pv.Scope, model: c.JSValue) !c.JSValue {
    const value = try pv.get(scope, model, "type");
    return pv.duplicate(scope, if (pv.nullish(value)) try pv.text(scope, "chat") else value);
}
fn typeEqual(scope: *pv.Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const left_type = try pv.own(scope, try live.expression(scope.engine, typeValue, .{left}));
    const right_type = try pv.own(scope, try live.expression(scope.engine, typeValue, .{right}));
    return pv.boolean(scope, pv.equal(scope, left_type, right_type));
}
fn fieldEqual(scope: *pv.Scope, left: c.JSValue, right: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return pv.boolean(scope, pv.equal(scope, try pv.get(scope, left, name), try pv.get(scope, right, name)));
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

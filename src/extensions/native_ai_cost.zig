//! Original calculateCost over live JavaScript models and Usage objects.
//! Preserve iterable pricing tiers, coercion order and the caller's cost object.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

pub fn create(engine: *em.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "calculateCost", 2, call, &.{});
}
fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return calculate(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
}
fn binary(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, operation, left, right));
}
pub fn calculate(engine: *em.Engine, model: c.JSValue, usage: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input_tokens = try binary(&scope, .add, try binary(&scope, .add, try scope.get(usage, "input"), try scope.get(usage, "cacheRead")), try scope.get(usage, "cacheWrite"));
    var rates = try scope.get(model, "cost");
    var threshold = c.JS_NewInt32(engine.context, -1);
    const raw_tiers = try scope.get(try scope.get(model, "cost"), "tiers");
    const tiers = if (c.JS_IsNull(raw_tiers) or c.JS_IsUndefined(raw_tiers)) try scope.array() else raw_tiers;
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, tiers, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |tier| {
        defer engine.freeValue(tier);
        if (try arithmetic.compare(engine, .greater, input_tokens, try scope.get(tier, "inputTokensAbove")) and
            try arithmetic.compare(engine, .greater, try scope.get(tier, "inputTokensAbove"), threshold))
        {
            rates = try scope.own(c.JS_DupValue(engine.context, tier));
            threshold = try scope.get(tier, "inputTokensAbove");
        }
    }
    const raw_long = try scope.get(usage, "cacheWrite1h");
    const long_write = if (c.JS_IsNull(raw_long) or c.JS_IsUndefined(raw_long)) c.JS_NewInt32(engine.context, 0) else raw_long;
    const short_write = try binary(&scope, .subtract, try scope.get(usage, "cacheWrite"), long_write);
    // Each assignment first evaluates usage.cost, then its original RHS.
    inline for (.{ "input", "output", "cacheRead" }) |name| {
        const destination = try scope.get(usage, "cost");
        const rate = try binary(&scope, .divide, try scope.get(rates, name), c.JS_NewInt32(engine.context, 1000000));
        try scope.set(destination, name, try binary(&scope, .multiply, rate, try scope.get(usage, name)));
    }
    const write_destination = try scope.get(usage, "cost");
    const short_cost = try binary(&scope, .multiply, try scope.get(rates, "cacheWrite"), short_write);
    const doubled_input = try binary(&scope, .multiply, try scope.get(rates, "input"), c.JS_NewInt32(engine.context, 2));
    const long_cost = try binary(&scope, .multiply, doubled_input, long_write);
    try scope.set(write_destination, "cacheWrite", try binary(&scope, .divide, try binary(&scope, .add, short_cost, long_cost), c.JS_NewInt32(engine.context, 1000000)));
    const total_destination = try scope.get(usage, "cost");
    var total = try scope.get(try scope.get(usage, "cost"), "input");
    inline for (.{ "output", "cacheRead", "cacheWrite" }) |name| total = try binary(&scope, .add, total, try scope.get(try scope.get(usage, "cost"), name));
    try scope.set(total_destination, "total", total);
    return c.JS_DupValue(engine.context, try scope.get(usage, "cost"));
}

//! Independent fixture cases share one Engine and one module closure. A case
//! includes its receipt, assertions, and all disposal before its promise settles.
const em = @import("extensions/engine.zig");
const c = em.c;

pub fn run(engine: *em.Engine, source: []const u8, filename: [:0]const u8, case_count: u32) !void {
    const exports = try engine.evalModule(source, filename);
    defer engine.freeValue(exports);
    const count = try engine.checked(c.JS_GetPropertyStr(engine.context, exports, "caseCount"));
    defer engine.freeValue(count);
    var actual_count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &actual_count, count) < 0) return error.JavaScriptException;
    if (actual_count != case_count) return error.WholeCaseFixtureCountChanged;
    const function = try engine.checked(c.JS_GetPropertyStr(engine.context, exports, "runCase"));
    defer engine.freeValue(function);
    if (!c.JS_IsFunction(engine.context, function)) return error.WholeCaseFixtureFunctionMissing;
    for (0..case_count) |index| {
        var arguments = [_]c.JSValue{c.JS_NewUint32(engine.context, @intCast(index))};
        const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), arguments.len, &arguments));
        defer engine.freeValue(pending);
        // Exactly one original host await covers the entire independent case.
        // Never renew the budget inside an in-flight case or replace its Engine.
        const settled = try engine.awaitValue(pending);
        engine.freeValue(settled);
    }
}

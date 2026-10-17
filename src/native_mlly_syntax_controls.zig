//! Prepared exact export controls, no complete mlly namespace/loader claim.
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const actual = @import("extensions/native_mlly_syntax.zig");
fn install(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try v.js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
/// The passed program is the unchanged original-user input body also called
/// with genuine package mlly.hasESMSyntax. It produces observations, not goldens.
pub fn observeActualExport(engine: *v.em.Engine, original_input: []const u8) !c.JSValue {
    const function = try actual.create(engine); defer engine.freeValue(function);
    try install(engine, "ActualMllyHasESMSyntax", function);
    return engine.evalModule(original_input, "actual-mlly-has-esm-syntax-input.mjs");
}
/// Holds only the actual exported function across GC, exercising real capture
/// marking rather than retaining a separately fabricated constants namespace.
pub fn observeAfterGc(engine: *v.em.Engine, original_input: []const u8) !c.JSValue {
    const function = try actual.create(engine); defer engine.freeValue(function);
    c.JS_RunGC(engine.runtime);
    try install(engine, "ActualMllyHasESMSyntax", function);
    return engine.evalModule(original_input, "actual-mlly-has-esm-syntax-after-gc-input.mjs");
}
pub fn verifyAcceptedOriginalObservation(engine: *v.em.Engine, actual_observation: c.JSValue, accepted_observation: c.JSValue) !void {
    const std = @import("std");
    const json = try v.js.global(engine, "JSON"); defer engine.freeValue(json);
    const stringify = try v.js.get(engine, json, "stringify"); defer engine.freeValue(stringify);
    const observed = try v.js.call(engine, stringify, json, &.{actual_observation}); defer engine.freeValue(observed);
    const expected = try v.js.call(engine, stringify, json, &.{accepted_observation}); defer engine.freeValue(expected);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, observed, expected));
}

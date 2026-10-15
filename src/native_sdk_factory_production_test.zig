//! Focused production factory entrypoint. The real application assembler must
//! supply the complete namespaces and platform bootstrap; no positive test
//! silently substitutes a model registry, loader, or SDK session facade.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const factory = @import("extensions/native_sdk_factory_production.zig");
const production = @import("extensions/native_sdk_session_production.zig");
const c = em.c;

pub fn assembleActual(engine: *em.Engine, session_inputs: production.Inputs, imported_bindings: c.JSValue) !c.JSValue {
    return factory.compose(engine, session_inputs, imported_bindings);
}

/// Called only after genuine Source capture has terminal status and fullpost0.
/// api contains actual constructors and the four production factory exports.
/// Reference bytes are passed by the owner; no absent expected file is created.
pub fn compareActualSourceCases(engine: *em.Engine, api: c.JSValue, reference_bytes: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(root, "factoryAPI", api);
    const module = try engine.evalModule(@embedFile("extensions/fixtures/sdk-factory-production-4954.input.txt"), "actual-factory27.mjs");
    engine.freeValue(module);
    const parsed = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, reference_bytes.ptr, reference_bytes.len, "actual-source-factory27.json")));
    if (!scope.equal(try scope.get(parsed, "cases"), c.JS_NewInt32(engine.context, 27))) return error.IncompleteActualFactorySourceReference;
    const stringify = try scope.get(try scope.global("JSON"), "stringify");
    const expected = try scope.call(stringify, c.pi_js_undefined(), &.{try scope.get(parsed, "rows")});
    const actual = try scope.call(stringify, c.pi_js_undefined(), &.{try scope.get(root, "factoryRows")});
    if (!scope.equal(expected, actual)) {
        const expected_text = try engine.toString(expected);
        defer engine.gpa.free(expected_text);
        const actual_text = try engine.toString(actual);
        defer engine.gpa.free(actual_text);
        std.debug.print("factory Source27 mismatch\nexpected={s}\nactual={s}\n", .{ expected_text, actual_text });
        return error.ActualFactorySourceMismatch;
    }
}

/// Source-only pending-graph target. Requires the genuine complete extension
/// initializer/cache/loader, not a replacement reload method or mocked class.
pub fn pendingActualOwnership(engine: *em.Engine, api: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(root, "factoryAPI", api);
    const prepared = try engine.evalModule(@embedFile("extensions/fixtures/sdk-factory-production-ownership.input.txt") ++ "\nawait prepareProductionFactoryOwnership(factoryAPI);export const prepared=true;", "actual-factory-pending-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("productionFactoryOptionsWeak.deref()!==undefined&&productionFactoryRuntimeWeak.deref()!==undefined", "actual-factory-pending-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_ToBool(engine.context, retained) == 1);
    engine.finishJob();
    const completed = try engine.evalModule("await completeProductionFactoryOwnership();export const completed=true;", "actual-factory-pending-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const released = try engine.eval("productionFactoryOptionsWeak.deref()===undefined", "actual-factory-pending-released.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(released);
    try std.testing.expect(c.JS_ToBool(engine.context, released) == 1);
}

test "production factory requires actual imports instead of manufacturing defaults" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const imports = try js.object(engine);
    defer engine.freeValue(imports);
    try std.testing.expectError(error.RequiredActualSdkFactoryBinding, factory.create(engine, imports, c.pi_js_undefined()));
}

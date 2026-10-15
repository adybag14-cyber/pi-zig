//! Focused integration comparison; the assembler supplies actual pi-ai imports.
//! This helper never fabricates Models, a stream implementation or a provider.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const virtual = @import("extensions/native_sdk_virtual_models_production.zig");
const c = em.c;

/// Requires the genuine captured Source36 reference after terminal/fullpost0.
/// Run from an authorized native owner with platform bootstrap already installed.
pub fn compareActualSourceCases(engine: *em.Engine, actual_imports: c.JSValue, reference_bytes: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const api = try scope.own(try virtual.create(engine, actual_imports));
    const root = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(root, "virtualModelsAPI", api);
    const evaluated = try engine.evalModule(@embedFile("extensions/fixtures/sdk-virtual-models-production-4954.input.txt"), "actual-virtual-models36.mjs");
    engine.freeValue(evaluated);
    const parsed = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, reference_bytes.ptr, reference_bytes.len, "actual-source-virtual-models36.json")));
    if (!scope.equal(try scope.get(parsed, "cases"), c.JS_NewInt32(engine.context, 36))) return error.IncompleteActualVirtualModelsSourceReference;
    if (!scope.equal(try scope.get(parsed, "sourceHead"), try scope.text("4954d760504c11df9b2cbdc040346107b6a8153d"))) return error.WrongVirtualModelsSourceReference;
    const stringify = try scope.get(try scope.global("JSON"), "stringify");
    const expected = try scope.call(stringify, c.pi_js_undefined(), &.{try scope.get(parsed, "rows")});
    const actual = try scope.call(stringify, c.pi_js_undefined(), &.{try scope.get(root, "virtualModelsRows")});
    if (!scope.equal(expected, actual)) {
        const expected_text = try engine.toString(expected);
        defer engine.gpa.free(expected_text);
        const actual_text = try engine.toString(actual);
        defer engine.gpa.free(actual_text);
        std.debug.print("virtual-models Source36 mismatch\nexpected={s}\nactual={s}\n", .{ expected_text, actual_text });
        return error.ActualVirtualModelsSourceMismatch;
    }
}

test "virtual-models missing actual imports rejects without synthetic fallback" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const imports = try js.object(engine);
    defer engine.freeValue(imports);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try std.testing.expectError(error.JavaScriptException, virtual.create(engine, imports));
}

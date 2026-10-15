//! Full static-create differential entry for the real composed class. The
//! caller provides actual namespace/IO/timer/bootstrap dependencies and accepted
//! original Source8 bytes; this helper supplies no replacement model registry.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn compareActual(engine: *em.Engine, actual_api: c.JSValue, reference_bytes: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(root, "modelRuntimeCreateAPI", actual_api);
    const module = try engine.evalModule(@embedFile("extensions/fixtures/sdk-model-runtime-create-4954.input.txt"), "actual-model-runtime-create-source8.mjs");
    engine.freeValue(module);
    const reference = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, reference_bytes.ptr, reference_bytes.len, "actual-model-runtime-create-source8.json")));
    if (!scope.equal(try scope.get(reference, "cases"), c.JS_NewInt32(engine.context, 8))) return error.IncompleteActualModelRuntimeCreateReference;
    const expected = try engine.stringify(try scope.get(reference, "rows"));
    defer engine.gpa.free(expected);
    const actual = try engine.stringify(try scope.get(root, "modelCreateRows"));
    defer engine.gpa.free(actual);
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("ModelRuntime.create Source8 mismatch\nexpected={s}\nactual={s}\n", .{ expected, actual });
        return error.ActualModelRuntimeCreateMismatch;
    }
}

const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn stringField(scope: *v.Scope, object: c.JSValue, name: [*:0]const u8, expected: []const u8) !void {
    try std.testing.expect(try v.eq(scope, try scope.get(object, name), expected));
}
fn countField(scope: *v.Scope, object: c.JSValue, name: [*:0]const u8, expected: i32) !void {
    try std.testing.expect(scope.equal(try scope.get(object, name), c.JS_NewInt32(scope.engine.context, expected)));
}
fn compare(scope: *v.Scope, expected: c.JSValue, actual: c.JSValue, count: u32, label: []const u8) !void {
    try std.testing.expectEqual(count, try v.length(scope, expected));
    try std.testing.expectEqual(count, try v.length(scope, actual));
    for (0..count) |index| {
        var row: v.Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const want = try scope.engine.stringify(try v.at(&row, expected, @intCast(index)));
        defer scope.engine.gpa.free(want);
        const got = try scope.engine.stringify(try v.at(&row, actual, @intCast(index)));
        defer scope.engine.gpa.free(got);
        if (!std.mem.eql(u8, want, got)) std.debug.print("ignore7 {s} original case index {d}\n", .{ label, index });
        try std.testing.expectEqualStrings(want, got);
    }
}
fn controls(comptime caller: []const u8, name: [*:0]const u8, field: [*:0]const u8, count: u32, label: []const u8) !void {
    const gpa = std.testing.allocator;
    // A real admitted Source capture must exist first. Never embed invented goldens.
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "verification/native-ignore7-prepared-20261016/source-output.json", gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(source);
    const engine = try v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    // The original inputs intentionally include lone UTF-16 surrogates. Use
    // ECMAScript JSON.parse semantics; std.json rejects these valid JS strings.
    const root = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-ignore7-source-capture.json")));
    try stringField(&scope, root, "version", "7.0.8");
    try stringField(&scope, root, "packageSha256", "643735013bdcf86dfeca4d38fb74d9a4fafa7a640ad2d251077862f18b2556fe");
    try stringField(&scope, root, "sourceHead", "4dd2b149d155d7369de16ea4dc77c84e9f5ffb24");
    try stringField(&scope, root, "callerSha256", "5d8a62805bd3866fd7742f0f6fa6f3e05411961155f95a7de8d9b60cd19d6363");
    try stringField(&scope, root, "liveCallerSha256", "f18ce5b5c25311e054c50b87a487372ba7e0222371a2427545ff0a90a35b1ef6");
    try stringField(&scope, root, "edgeCallerSha256", "88daf67e655f7b04852f33c1e4aa2cb5c57b62babe5440ed01dd5fb56c83edc1");
    const node = try scope.get(root, "actualNode");
    try stringField(&scope, node, "version", "v24.14.0");
    try stringField(&scope, node, "platform", "win32");
    try countField(&scope, root, "matrixSets", 42);
    try countField(&scope, root, "matrixPaths", 54);
    try countField(&scope, root, "cases", 2375);
    try countField(&scope, root, "liveCases", 12);
    try countField(&scope, root, "edgeCases", 12);
    try countField(&scope, root, "totalCases", 2399);
    try @import("extensions/native_ignore7.zig").install(engine);
    const imported = try engine.evalModule("import ignore from 'ignore';globalThis.nativeIgnore7=ignore;", "native-ignore7-binding.mjs");
    engine.freeValue(imported);
    const evaluated = try engine.evalModule(caller, "native-ignore7-original-callers.mjs");
    engine.freeValue(evaluated);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try compare(&scope, try scope.get(root, field), try scope.get(global, name), count, label);
}
test "native ignore7 original callers match genuine pinned package observations" {
    try controls(@embedFile("extensions/fixtures/ignore7-original-caller-controls.input.txt"), "ignore7OriginalObservations", "observations", 2375, "matrix/API");
}
test "native ignore7 live prototypes match genuine pinned package observations" {
    try controls(@embedFile("extensions/fixtures/ignore7-live-prototype-controls.input.txt"), "ignore7LiveObservations", "liveObservations", 12, "live prototype");
}
test "native ignore7 scanner edges match genuine pinned package observations" {
    try controls(@embedFile("extensions/fixtures/ignore7-scanner-edge-controls.input.txt"), "ignore7ScannerEdgeObservations", "edgeObservations", 12, "scanner edges");
}

const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
test "native ignore7 original callers match genuine pinned package observations" {
    const gpa = std.testing.allocator;
    // A real admitted Source capture must exist first. Never embed invented goldens.
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "verification/native-ignore7-prepared-20261016/source-output.json", gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(source);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, source, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try std.testing.expectEqualStrings("7.0.8", root.get("version").?.string);
    try std.testing.expectEqualStrings("643735013bdcf86dfeca4d38fb74d9a4fafa7a640ad2d251077862f18b2556fe", root.get("packageSha256").?.string);
    try std.testing.expectEqualStrings("4dd2b149d155d7369de16ea4dc77c84e9f5ffb24", root.get("sourceHead").?.string);
    try std.testing.expectEqualStrings("5d8a62805bd3866fd7742f0f6fa6f3e05411961155f95a7de8d9b60cd19d6363", root.get("callerSha256").?.string);
    try std.testing.expectEqualStrings("v24.14.0", root.get("actualNode").?.object.get("version").?.string);
    try std.testing.expectEqualStrings("win32", root.get("actualNode").?.object.get("platform").?.string);
    try std.testing.expectEqual(@as(i64, 42), root.get("matrixSets").?.integer);
    try std.testing.expectEqual(@as(i64, 54), root.get("matrixPaths").?.integer);
    try std.testing.expectEqual(@as(i64, 2375), root.get("cases").?.integer);
    const observations = root.get("observations").?;
    try std.testing.expectEqual(root.get("cases").?.integer, @as(i64, @intCast(observations.array.items.len)));
    const engine = try v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("extensions/native_ignore7.zig").install(engine);
    const imported = try engine.evalModule("import ignore from 'ignore';globalThis.nativeIgnore7=ignore;", "native-ignore7-binding.mjs");
    engine.freeValue(imported);
    const evaluated = try engine.evalModule(@embedFile("extensions/fixtures/ignore7-original-caller-controls.input.txt"), "native-ignore7-original-callers.mjs");
    engine.freeValue(evaluated);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const actual = try engine.stringify(try scope.get(try scope.own(c.JS_GetGlobalObject(engine.context)), "ignore7OriginalObservations"));
    defer gpa.free(actual);
    const expected = try std.json.Stringify.valueAlloc(gpa, observations, .{});
    defer gpa.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}

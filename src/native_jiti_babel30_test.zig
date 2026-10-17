const std = @import("std");
const em = @import("extensions/engine.zig");
const controls = @import("native_jiti_babel30_controls.zig");
test "native default Babel30 exact original backend comparison retaining every row" {
    var environment = try std.process.Environ.createMap(std.testing.environ,std.testing.allocator); defer environment.deinit();
    const output = environment.get("PI_JITI_BABEL30_BACKEND_REPORT") orelse return error.RequiredOwnedBabel30ReportPath;
    if (!std.fs.path.isAbsolute(output)) return error.RequiredAbsoluteOwnedBabel30ReportPath;
    const engine = try em.Engine.init(std.testing.allocator,.{}); defer engine.deinit();
    const raw = try controls.collectBackend(engine,std.testing.io); defer engine.gpa.free(raw);
    // Record every observation before a mismatch fails this comparison. External
    // granted owner must place this exact output in its fresh owned run folder.
    const file = try std.Io.Dir.createFileAbsolute(std.testing.io,output,.{.exclusive=true}); defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io,raw);
    const report = try std.json.parseFromSlice(std.json.Value,std.testing.allocator,raw,.{}); defer report.deinit();
    try std.testing.expectEqual(@as(i64,30),report.value.object.get("nativeRows").?.integer);
    try std.testing.expectEqual(@as(i64,0),report.value.object.get("evaluatedRows").?.integer);
    try std.testing.expect(!report.value.object.get("fullComparisonPassed").?.bool);
    // Exact output mismatch is a NEGATIVE result, including PI_UNSUPPORTED
    // frontiers. Merely observing all thirty rows does not satisfy parity.
    try std.testing.expectEqual(@as(usize,0),report.value.object.get("completionMismatches").?.array.items.len);
    try std.testing.expectEqual(@as(usize,0),report.value.object.get("backendMismatches").?.array.items.len);
}

//! Exact standalone artifact supplied by the owning native test build runner.
//! No availability probe, PATH lookup, stale default artifact or runtime fallback.
const std = @import("std");
pub fn executablePath(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    var environment = try std.process.Environ.createMap(gpa, io);
    defer environment.deinit();
    const executable = environment.get("PI_NATIVE_TEST_EXECUTABLE") orelse return error.NativeTestExecutableRequired;
    if (!std.fs.path.isAbsolute(executable)) return error.InvalidNativeTestExecutable;
    return gpa.dupe(u8, executable);
}

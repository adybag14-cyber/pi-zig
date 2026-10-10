const std = @import("std");
const pi = @import("pi_zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var environment = try init.minimal.environ.createMap(init.gpa);
    defer environment.deinit();
    if (args.len == 2 and std.mem.eql(u8, args[1], "--internal-native-extension-group-worker")) return pi.extensions.native_worker.runGroupWithEnvironment(init.gpa, init.io, &environment, args);
    if (args.len == 3 and std.mem.eql(u8, args[1], "--internal-native-extension-worker")) return pi.extensions.native_worker.runWithEnvironment(init.gpa, init.io, args[2], &environment, args);
    if (args.len != 2) return error.ExpectedSDKScriptPath;
    try pi.extensions.native_worker.runSdkFileWithEnvironment(init.gpa, init.io, args[1], &environment, args);
}

const std = @import("std");
const pi = @import("pi_zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedSDKScriptPath;
    var environment = try init.minimal.environ.createMap(init.gpa);
    defer environment.deinit();
    try pi.extensions.native_worker.runSdkFileWithEnvironment(init.gpa, init.io, args[1], &environment, args);
}

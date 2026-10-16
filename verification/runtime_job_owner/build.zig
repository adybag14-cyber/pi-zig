//! Standalone verification target; not integrated into the product build.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const executable = b.addExecutable(.{ .name = "runtime-job-owner",
        .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize }) });
    for ([_][]const u8{ "kernel32", "shell32", "ole32", "oleaut32", "advapi32", "bcrypt" }) |library|
        executable.root_module.linkSystemLibrary(library, .{});
    b.installArtifact(executable);
}

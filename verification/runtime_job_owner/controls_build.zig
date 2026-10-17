//! Native-only control artifacts. Install/build only; never run as a build step.
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const actor = b.addExecutable(.{ .name = "runtime-job-owner-actor",
        .root_module = b.createModule(.{ .root_source_file = b.path("controls_actor.zig"), .target = target, .optimize = optimize }) });
    // Canonical CI607 admits the exact native test.exe role; the actor keeps
    // its separate sealed name and is launched only by the fixture's own job.
    const controls = b.addTest(.{ .name = "test",
        .root_module = b.createModule(.{ .root_source_file = b.path("controls_tests.zig"), .target = target, .optimize = optimize }) });
    inline for (.{ actor, controls }) |artifact| {
        for ([_][]const u8{ "kernel32", "shell32", "ole32", "oleaut32", "advapi32", "bcrypt" }) |library|
            artifact.root_module.linkSystemLibrary(library, .{});
        b.installArtifact(artifact);
    }
}

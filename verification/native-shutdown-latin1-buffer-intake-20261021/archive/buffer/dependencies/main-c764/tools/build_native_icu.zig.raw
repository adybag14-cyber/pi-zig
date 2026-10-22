const std = @import("std");
pub const Package = struct { api: *std.Build.Module, library: *std.Build.Step.Compile };
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Package {
    const common = library(b, target, optimize, "common", "U_COMMON_IMPLEMENTATION");
    const i18n = library(b, target, optimize, "i18n", "U_I18N_IMPLEMENTATION");
    i18n.root_module.linkLibrary(common);
    const stub = b.addLibrary(.{ .name = "pi-icu78-stubdata", .linkage = .static, .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = true }) });
    stub.root_module.addIncludePath(b.path("vendor/icu78/source/common"));
    stub.root_module.addIncludePath(b.path("vendor/icu78/source/stubdata"));
    stub.root_module.addCSourceFile(.{ .file = b.path("vendor/icu78/source/stubdata/stubdata.cpp"), .flags = &.{ "-std=c++17", "-DU_STATIC_IMPLEMENTATION", "-DUCONFIG_ONLY_COLLATION=1", "-DUCONFIG_NO_CONVERSION=1" } });
    common.root_module.linkLibrary(stub);
    if (target.result.os.tag == .windows) i18n.root_module.linkSystemLibrary("advapi32", .{});
    return .{ .api = b.addModule("native_icu_api", .{ .root_source_file = b.path("src/extensions/icu/native_icu_api.zig"), .target = target, .optimize = optimize }), .library = i18n };
}
fn library(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, implementation: []const u8) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{ .name = b.fmt("pi-icu78-{s}", .{name}), .linkage = .static, .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = true }) });
    lib.root_module.addIncludePath(b.path("vendor/icu78/source/common"));
    lib.root_module.addIncludePath(b.path("vendor/icu78/source/i18n"));
    const path = b.pathFromRoot(b.fmt("vendor/icu78/source/{s}/sources.txt", .{name}));
    const bytes = std.Io.Dir.cwd().readFileAlloc(b.graph.io, path, b.allocator, .limited(1024 * 1024)) catch @panic("Pinned ICU sources.txt unavailable");
    var lines = std.mem.tokenizeAny(u8, bytes, "\r\n");
    while (lines.next()) |file| lib.root_module.addCSourceFile(.{ .file = b.path(b.fmt("vendor/icu78/source/{s}/{s}", .{ name, file })), .flags = &.{ "-std=c++17", "-DU_STATIC_IMPLEMENTATION", "-DUCONFIG_ONLY_COLLATION=1", "-DUCONFIG_NO_CONVERSION=1", "-DU_ENABLE_DYLOAD=0", b.fmt("-D{s}", .{implementation}) } });
    return lib;
}

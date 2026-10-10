//! Full libfyaml parser/document subset, statically linked through Zig's C ABI.
//! Each unit is a separate Build step so -j1 bounds C compiler memory.
const std = @import("std");
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const library = b.addLibrary(.{ .name = "pi-native-yaml", .linkage = .static, .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }) });
    const files = [_][]const u8{
        "src/lib/fy-accel.c",         "src/lib/fy-atom.c",       "src/lib/fy-composer.c",        "src/lib/fy-diag.c",
        "src/lib/fy-doc.c",           "src/lib/fy-docbuilder.c", "src/lib/fy-docstate.c",        "src/lib/fy-dump.c",
        "src/lib/fy-emit.c",          "src/lib/fy-event.c",      "src/lib/fy-input.c",           "src/lib/fy-parse.c",
        "src/lib/fy-path.c",          "src/lib/fy-token.c",      "src/lib/fy-types.c",           "src/lib/fy-walk.c",
        "src/lib/fy-composer-diag.c", "src/lib/fy-doc-diag.c",   "src/lib/fy-docbuilder-diag.c", "src/lib/fy-input-diag.c",
        "src/lib/fy-parse-diag.c",    "src/util/fy-blob.c",      "src/util/fy-ctype.c",          "src/util/fy-utf8.c",
        "src/util/fy-utils.c",        "src/xxhash/xxhash.c",     "pi_yaml.c",
    };
    for (files, 0..) |file, index| {
        const object = b.addObject(.{ .name = b.fmt("pi-yaml-{d}", .{index}), .root_module = b.createModule(.{ .target = target, .optimize = .ReleaseSafe, .link_libc = true }) });
        for ([_][]const u8{ "", "include", "src/lib", "src/util", "src/xxhash" }) |directory|
            object.root_module.addIncludePath(b.path(b.fmt("vendor/libfyaml/{s}", .{directory})));
        object.root_module.addCSourceFile(.{ .file = b.path(b.fmt("vendor/libfyaml/{s}", .{file})), .flags = &.{ "-std=gnu11", "-D_GNU_SOURCE", "-DHAVE_CONFIG_H", "-DNDEBUG", "-O1", "-fno-strict-aliasing" } });
        library.root_module.addObject(object);
    }
    return library;
}

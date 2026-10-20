//! One actual Node v24.13 simdjson library for the selected package parser.
//! The original vendor files remain intact; the separately pinned successor
//! changes allocation ownership only. Build/install wiring never executes it.
const std = @import("std");
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
    // The admitted native owner and retained libc++ inline-string proof cover
    // these 64-bit targets. Other targets require their own source admission.
    if (target.result.ptrBitWidth() != 64) return null;
    switch (target.result.os.tag) {
        .windows, .linux => {},
        else => return null,
    }
    const library = b.addLibrary(.{
        .name = "pi-node-package-json",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target, .optimize = optimize,
            .link_libc = true, .link_libcpp = true,
        }),
    });
    library.root_module.addIncludePath(b.path("src/extensions"));
    library.root_module.addIncludePath(b.path("vendor/node-v24.13.0/simdjson-owned"));
    library.root_module.addCSourceFiles(.{
        .files = &.{
            "vendor/node-v24.13.0/simdjson-owned/simdjson.cpp",
            "src/extensions/native_simdjson_memory.cpp",
            "src/extensions/native_node_package_json_parser.cpp",
        },
        .flags = &.{ "-std=gnu++20", "-fno-exceptions", "-fno-rtti", "-fno-strict-aliasing" },
    });
    return library;
}

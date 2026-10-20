//! One native C++ per-allocation owner and one TLS domain for all consumers.
//! Build/install wiring never executes a source generator or target.
const std = @import("std");
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ?*std.Build.Step.Compile {
    if (target.result.ptrBitWidth() != 64) return null;
    switch (target.result.os.tag) {
        .windows, .linux => {},
        else => return null,
    }
    const library = b.addLibrary(.{
        .name = "pi-node-native-memory",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target, .optimize = optimize,
            .link_libc = true, .link_libcpp = true,
        }),
    });
    library.root_module.addIncludePath(b.path("src/extensions"));
    library.root_module.addCSourceFile(.{
        .file = b.path("src/extensions/native_simdjson_memory.cpp"),
        .flags = &.{ "-std=gnu++20", "-fno-exceptions", "-fno-rtti", "-fno-strict-aliasing" },
    });
    return library;
}

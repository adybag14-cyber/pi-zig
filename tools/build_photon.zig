//! Build each C translation unit separately so -j1 bounds compiler memory.
const std = @import("std");
pub fn library(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const result = b.addLibrary(.{ .name = "pi-photon", .linkage = .static, .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }) });
    const flags = [_][]const u8{ "-std=gnu11", "-O1", "-ffp-contract=off", "-fno-fast-math", "-DWASM_RT_USE_MMAP=0", "-DWASM_RT_USE_SEGUE=0", "-DWASM_RT_MEMCHECK_BOUNDS_CHECK=1", "-DWASM_RT_TRAP_HANDLER=pi_image_trap" };
    for (0..16) |index| {
        const name = b.fmt("photon_{d}", .{index});
        addObject(b, result, target, optimize, name, &flags);
        const browser_name = b.fmt("photon_browser_{d}", .{index});
        addObject(b, result, target, optimize, browser_name, &flags);
    }
    for ([_][]const u8{ "codec_imports", "browser_imports", "codec_alloc_guard", "photon_native", "photon_browser_native", "session_api", "session_browser_api" }) |name| addObject(b, result, target, optimize, name, &flags);
    const extra_hooks = [_][]const u8{ "-Dmalloc=pi_image_malloc", "-Dcalloc=pi_image_calloc", "-Drealloc=pi_image_realloc", "-Dfree=pi_image_free", "-Dabort=pi_image_abort", "-include", b.pathFromRoot("vendor/photon-native/codec_alloc_guard.h") };
    const hooks = std.mem.concat(b.allocator, []const u8, &.{ &flags, &extra_hooks }) catch @panic("OOM");
    for ([_][]const u8{ "wasm-rt-impl", "wasm-rt-mem-impl", "wasm-rt-exceptions-impl" }) |name| addObject(b, result, target, optimize, name, hooks);
    return result;
}
fn addObject(b: *std.Build, result: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, name: []const u8, flags: []const []const u8) void {
    const object = b.addObject(.{ .name = b.fmt("pi-photon-{s}", .{name}), .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }) });
    object.root_module.addIncludePath(b.path("vendor/photon-native"));
    object.root_module.addCSourceFile(.{ .file = b.path(b.fmt("vendor/photon-native/{s}.c", .{name})), .flags = flags });
    result.root_module.addObject(object);
}

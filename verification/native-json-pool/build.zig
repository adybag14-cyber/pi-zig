//! Standalone genuine C allocation qualification. Instrument generated copies
//! of current production inputs; preserve the small-block pool and VM behavior.
const std = @import("std");
fn replace(b: *std.Build, source: []const u8, needle: []const u8, value: []const u8) []const u8 {
    if (std.mem.count(u8, source, needle) != 1) std.debug.panic("C allocation qualification anchor drift: {s}", .{needle});
    return std.mem.replaceOwned(u8, b.allocator, source, needle, value) catch @panic("OOM");
}
fn read(b: *std.Build, path: []const u8) []const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(b.graph.io, b.pathFromRoot(path), b.allocator, .limited(32 * 1024 * 1024)) catch @panic("Current production input unavailable");
    return std.mem.replaceOwned(u8, b.allocator, bytes, "\r\n", "\n") catch @panic("OOM");
}
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var allocator = read(b, "../../src/extensions/engine_abi.c");
    allocator = replace(b, allocator, "    size_t limit;", "    size_t limit;\n    size_t allocation_attempts;\n    size_t allocation_fail_at;\n    size_t allocation_failures;");
    const controls =
        \\int pi_js_test_pool_allocation_fails(void *opaque) {
        \\    PiMemoryOwner *owner = opaque;
        \\    if (++owner->allocation_attempts != owner->allocation_fail_at) return 0;
        \\    owner->allocation_failures++;
        \\    return 1;
        \\}
        \\void pi_js_test_allocator_fail_after(void *opaque, size_t index) {
        \\    PiMemoryOwner *owner = opaque;
        \\    owner->allocation_fail_at = owner->allocation_attempts + index + 1;
        \\    owner->allocation_failures = 0;
        \\}
        \\void pi_js_test_allocator_clear_failure(void *opaque) { ((PiMemoryOwner *)opaque)->allocation_fail_at = 0; }
        \\size_t pi_js_test_allocator_attempts(void *opaque) { return ((PiMemoryOwner *)opaque)->allocation_attempts; }
        \\size_t pi_js_test_allocator_failures(void *opaque) { return ((PiMemoryOwner *)opaque)->allocation_failures; }
        \\void pi_js_test_retain_memory_owner(void *opaque) {
        \\    atomic_fetch_add_explicit(&((PiMemoryOwner *)opaque)->references, 1, memory_order_relaxed);
        \\}
        \\static _Atomic size_t pi_memory_owners;
    ;
    allocator = replace(b, allocator, "static _Atomic size_t pi_memory_owners;", controls);
    allocator = replace(b, allocator, "    owner->limit = memory_limit;", "    owner->limit = memory_limit;\n    owner->allocation_attempts = 0;\n    owner->allocation_fail_at = 0;\n    owner->allocation_failures = 0;");
    var vm = read(b, "../../vendor/quickjs/quickjs.c");
    for ([_][]const u8{ "ptr = js_arena_calloc(rt, count, size);", "ptr = js_arena_malloc(rt, size);", "ptr = js_arena_realloc(rt, ptr, size);" }) |call| {
        const anchor = b.fmt("    {s}", .{call});
        vm = replace(b, vm, anchor, b.fmt("    extern int pi_js_test_pool_allocation_fails(void *opaque);\n    if (pi_js_test_pool_allocation_fails(rt->malloc_state.opaque)) return NULL;\n{s}", .{anchor}));
    }
    const generated = b.addWriteFiles();
    const module = b.createModule(.{ .root_source_file = b.path("json_path_cmalloc_test.zig"), .target = target, .optimize = optimize, .link_libc = true });
    module.addIncludePath(b.path("../../src/extensions"));
    module.addIncludePath(b.path("../../vendor/quickjs"));
    const flags = [_][]const u8{ "-std=gnu11", "-D_GNU_SOURCE", "-DQUICKJS_NG_BUILD", "-funsigned-char", "-fno-strict-aliasing" };
    module.addCSourceFiles(.{ .root = b.path("../../vendor/quickjs"), .files = &.{ "dtoa.c", "libregexp.c", "libunicode.c" }, .flags = &flags });
    module.addCSourceFile(.{ .file = generated.add("quickjs-qualified.c", vm), .flags = if (optimize == .Debug) &(flags ++ [_][]const u8{"-Og"}) else &flags });
    module.addCSourceFile(.{ .file = generated.add("engine-allocator-qualified.c", allocator), .flags = &.{"-std=gnu11"} });
    if (target.result.os.tag != .windows) module.linkSystemLibrary("m", .{});
    const tests = b.addTest(.{ .root_module = module });
    b.step("test-json-path-cmalloc", "Exercise every real pool allocation in selected serialization paths with strict exception and zero-live-byte checks").dependOn(&b.addRunArtifact(tests).step);
}

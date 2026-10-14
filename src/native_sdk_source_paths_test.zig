//! Private Source/path algorithm comparator; public export metadata is separate.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const paths = @import("extensions/native_sdk_source_paths.zig");
const c = em.c;

fn arg(argc: c_int, argv: [*c]c.JSValue, position: usize) c.JSValue {
    return if (position < @as(usize, @intCast(argc))) argv[position] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = switch (magic) {
        0 => paths.resolve(engine, arg(argc, argv, 0), arg(argc, argv, 1), arg(argc, argv, 2)),
        1 => paths.cwdRelative(engine, arg(argc, argv, 0), arg(argc, argv, 1)),
        2 => paths.display(engine, arg(argc, argv, 0), arg(argc, argv, 1)),
        else => unreachable,
    };
    return result catch |err| sdk.fail(engine, err);
}
fn setup(engine: *em.Engine) !void {
    var environment = try std.testing.environ.createMap(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-source-path-cwd"});
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const module = engine.native_module_values.get("node:process").?;
    try sdk.put(engine, global, "originalProcess", try sdk.get(engine, module, "default"));
    try sdk.put(engine, global, "nodePathAPI", c.JS_DupValue(engine.context, engine.native_module_values.get("node:path").?));
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    inline for (.{ "resolvePath", "getCwdRelativePath", "formatPathRelativeToCwdOrAbsolute" }, 0..) |name, mode| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, callback, name, if (mode == 0) 1 else 2, @intCast(mode)));
        try sdk.put(engine, api, name, function);
    }
    try sdk.put(engine, global, "sourcePathAPI", c.JS_DupValue(engine.context, api));
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-path-cwd-1692.input.txt"), "path-cwd-original40.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try sdk.get(engine, global, "sdkPathCwdRows");
    defer engine.freeValue(rows);
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    const expected_bytes = switch (builtin.os.tag) {
        .windows => @embedFile("extensions/fixtures/sdk-path-cwd-1692-win32.json"),
        .macos => @embedFile("extensions/fixtures/sdk-path-cwd-1692-darwin.json"),
        else => @embedFile("extensions/fixtures/sdk-path-cwd-1692-linux.json"),
    };
    const expected = try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "path-cwd-original40.json"));
    defer engine.freeValue(expected);
    const expected_raw = try engine.stringify(expected);
    defer gpa.free(expected_raw);
    if (!std.mem.eql(u8, raw, expected_raw)) {
        std.debug.print("Actual Source path cwd40 mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
        return error.SourcePathCwdMismatch;
    }
    const released = try engine.eval("delete globalThis.sdkPathCwdRows;delete globalThis.sourcePathAPI;delete globalThis.nodePathAPI;delete globalThis.originalProcess;", "path-cwd-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native Source path cwd matches genuine40 actual builtin and Source callbacks ordering errors and display" {
    try exercise(std.testing.allocator);
}
test "native Source path cwd releases every actual original40 allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-source-path-cwd", exercise, .{});
}

//! Genuine jsdiff8.0.4 and upstream edit display/renderer comparisons.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

fn arg(argc: c_int, argv: [*c]c.JSValue, index: usize) c.JSValue {
    return if (index < @as(usize, @intCast(argc))) argv[index] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = switch (magic) {
        0 => @import("extensions/native_sdk_jsdiff_default.zig").diffWords(engine, arg(argc, argv, 0), arg(argc, argv, 1)),
        1 => @import("extensions/native_sdk_jsdiff_default.zig").diffLines(engine, arg(argc, argv, 0), arg(argc, argv, 1)),
        2 => @import("extensions/native_sdk_edit_diff_display.zig").generateDefault(engine, arg(argc, argv, 0), arg(argc, argv, 1)),
        3 => @import("extensions/native_sdk_edit_apply.zig").applyNormalized(engine, arg(argc, argv, 0), arg(argc, argv, 1), arg(argc, argv, 2)),
        4 => @import("extensions/native_sdk_render_diff.zig").render(engine, arg(argc, argv, 0), roots[0]),
        else => unreachable,
    };
    return result catch |err| sdk.fail(engine, err);
}
fn setup(engine: *em.Engine) !void {
    var environment = try std.testing.environ.createMap(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-edit-diff-source54"});
    try @import("extensions/native_tui.zig").install(engine);
    const initialized = try engine.evalModule("import{initTheme}from'pi-coding-agent';initTheme('dark',false)", "edit-theme.mjs");
    engine.freeValue(initialized);
    const theme = try sdk.get(engine, engine.native_module_values.get("pi-coding-agent").?, "theme");
    defer engine.freeValue(theme);
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    inline for (.{ "diffWords", "diffLines", "generateDiffString", "applyEditsToNormalizedContent", "renderDiff" }, 0..) |name, mode| {
        var roots = [_]c.JSValue{theme};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, if (mode == 3) 3 else if (mode == 4) 1 else 2, @intCast(mode), 1, &roots));
        try sdk.put(engine, api, name, function);
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "editDiffAPI", c.JS_DupValue(engine.context, api));
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-edit-diff54-b45.input.txt"), "actual-edit-diff54.mjs") catch |err| {
        if (engine.native_allocation_generation == generation) std.debug.print("EditDiff54 execution: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(observed);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const rows = try sdk.get(engine, global, "sdkEditDiffRows");
    defer engine.freeValue(rows);
    const raw = try engine.stringify(rows);
    defer gpa.free(raw);
    const expected_bytes = @embedFile("extensions/fixtures/sdk-edit-diff54-b45-source.json");
    const expected = try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "actual-edit-diff54.json"));
    defer engine.freeValue(expected);
    const expected_rows = try sdk.get(engine, expected, "rows");
    defer engine.freeValue(expected_rows);
    const expected_raw = try engine.stringify(expected_rows);
    defer gpa.free(expected_raw);
    if (!std.mem.eql(u8, raw, expected_raw)) {
        std.debug.print("Actual EditDiff54 mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
        return error.SourceEditDiffMismatch;
    }
    const released = try engine.eval("delete globalThis.sdkEditDiffRows;delete globalThis.editDiffAPI;", "edit-diff-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native edit diff matches genuine Source54 words lines fuzzy edits context display and actual Theme rendering" {
    try exercise(std.testing.allocator);
}
test "native edit diff releases every failed Source54 allocation" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-edit-diff-source54", exercise, .{});
}

//! Actual Source file-tool presentation with real asynchronous filesystem edits.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const presentation = @import("extensions/native_sdk_builtin_file_presentation.zig");
const c = em.c;
fn setup(engine: *em.Engine, root: []const u8) !void {
    var environment = try std.testing.environ.createMap(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-file-renderers-source28"});
    try @import("extensions/native_tui.zig").install(engine);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_url.zig").install(engine);
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    inline for (.{ .{ "read", "readRenderers" }, .{ "write", "writeRenderers" }, .{ "edit", "editRenderers" } }) |entry| {
        const definition = try @import("extensions/native_sdk_builtin_execution.zig").createDefinition(engine, entry[0], root, true);
        defer engine.freeValue(definition);
        try @import("extensions/native_sdk_builtin_presentation.zig").attach(engine, definition, entry[0]);
        try sdk.put(engine, api, entry[1], c.JS_DupValue(engine.context, definition));
    }
    try sdk.put(engine, api, "preview", try @import("extensions/native_sdk_edit_preview.zig").createNative(engine));
    try sdk.put(engine, api, "language", try engine.checked(c.JS_NewCFunction(engine.context, @import("extensions/native_sdk_highlight_paths.zig").callback, "getLanguageFromPath", 1)));
    try sdk.put(engine, api, "theme", try sdk.get(engine, engine.native_module_values.get("pi-coding-agent").?, "theme"));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "fileRenderAPI", c.JS_DupValue(engine.context, api));
    try sdk.put(engine, global, "previewRoot", try sdk.text(engine, root));
    const initialized = try engine.evalModule(
        \\import{initTheme}from'pi-coding-agent';import{pathToFileURL}from'node:url';import{constants}from'node:fs';
        \\initTheme('dark',false);fileRenderAPI.fixtureUri=pathToFileURL(previewRoot+'/').href;
        \\globalThis.fileAccessConstants={prototypeIsNull:Object.getPrototypeOf(constants)===null,flags:Object.fromEntries(['F_OK','R_OK','W_OK','X_OK'].map(name=>[name,Object.getOwnPropertyDescriptor(constants,name)]))};
    , "native-file-renderer-setup.mjs");
    engine.freeValue(initialized);
}
fn compare(engine: *em.Engine) !void {
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-file-renderers28-b45.input.txt"), "actual-file-renderers28.mjs") catch |err| {
        std.debug.print("File renderers28 execution: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(observed);
    const expected_bytes = @embedFile("extensions/fixtures/sdk-file-renderers28-b45-source.json");
    const expected = try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "actual-file-renderers28.json"));
    defer engine.freeValue(expected);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "rows", "fileRenderRows" }, .{ "languages", "fileLanguageRows" }, .{ "previewMetadata", "filePreviewMetadata" }, .{ "accessConstants", "fileAccessConstants" } }) |entry| {
        const actual_value = try sdk.get(engine, global, entry[1]);
        defer engine.freeValue(actual_value);
        const wanted_value = try sdk.get(engine, expected, entry[0]);
        defer engine.freeValue(wanted_value);
        const actual = try engine.stringify(actual_value);
        defer engine.gpa.free(actual);
        const wanted = try engine.stringify(wanted_value);
        defer engine.gpa.free(wanted);
        if (!std.mem.eql(u8, actual, wanted)) {
            std.debug.print("Actual Source file-renderer {s} mismatch:\n{s}\nExpected:\n{s}\n", .{ entry[0], actual, wanted });
            return error.SourceFileRendererMismatch;
        }
    }
    const released = try engine.eval("delete globalThis.fileRenderAPI;delete globalThis.previewRoot;delete globalThis.fileAccessConstants;delete globalThis.fileRenderRows;delete globalThis.fileLanguageRows;delete globalThis.filePreviewMetadata;", "file-renderer-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
fn exercise(gpa: std.mem.Allocator, root: []const u8) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine, root) catch |err| return engine.nativeAllocationError(err, generation);
    compare(engine) catch |err| return engine.nativeAllocationError(err, generation);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
}
fn focusedProbe(failing: *std.testing.FailingAllocator, root: []const u8, offset: ?usize) !usize {
    const engine = try em.Engine.init(failing.allocator(), .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine, root);
    const generation = engine.native_allocation_generation;
    const start = failing.alloc_index;
    if (offset) |index| failing.fail_index = start + index;
    compare(engine) catch |err| return engine.nativeAllocationError(err, generation);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    return failing.alloc_index - start;
}
test "native file renderers retain and release five selected real operation allocation failures" {
    var temporary = try fixture();
    defer temporary.cleanup();
    var root: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &root);
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const total = try focusedProbe(&baseline, root[0..count], null);
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    try std.testing.expect(total >= 5);
    std.debug.print("FILE_RENDERER_OWNER_BASELINE operations={d}\n", .{total});
    for ([_]usize{ 0, total / 4, total / 2, total * 3 / 4, total - 1 }) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        try std.testing.expectError(error.OutOfMemory, focusedProbe(&failing, root[0..count], offset));
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        std.debug.print("FILE_RENDERER_OWNER_FAILURE_COMPLETE offset={d} operations={d}\n", .{ offset, total });
    }
}
fn fixture() !std.testing.TmpDir {
    var temporary = std.testing.tmpDir(.{});
    errdefer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "one.txt", .data = "old\nkeep\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "bom.txt", .data = "\xef\xbb\xbfold\r\nkeep\r\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "duplicate.txt", .data = "repeat repeat\n" });
    return temporary;
}
test "native file renderers match actual Source28 components previews metadata and Source21 language paths" {
    var temporary = try fixture();
    defer temporary.cleanup();
    var root: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &root);
    try exercise(std.testing.allocator, root[0..count]);
}
test "native file renderers release every actual Source28 failed owner allocation" {
    var temporary = try fixture();
    defer temporary.cleanup();
    var root: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &root);
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-file-renderers-source28", exercise, .{root[0..count]});
}

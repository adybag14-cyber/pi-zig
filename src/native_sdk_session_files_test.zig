const std = @import("std");
const sdk = @import("extensions/native_sdk.zig");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;
const Input = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
fn equal(expected: std.json.Value, actual: std.json.Value) anyerror!void {
    try std.testing.expectEqual(@as(std.meta.Tag(std.json.Value), expected), @as(std.meta.Tag(std.json.Value), actual));
    switch (expected) {
        .object => |object| {
            try std.testing.expectEqual(object.count(), actual.object.count());
            var fields = object.iterator();
            while (fields.next()) |field| try equal(field.value_ptr.*, actual.object.get(field.key_ptr.*) orelse return error.MissingSessionField);
        },
        .array => |array| {
            try std.testing.expectEqual(array.items.len, actual.array.items.len);
            for (array.items, actual.array.items) |a, b| try equal(a, b);
        },
        .string => |value| try std.testing.expectEqualStrings(value, actual.string),
        .integer => |value| try std.testing.expectEqual(value, actual.integer),
        .float => |value| try std.testing.expectEqual(value, actual.float),
        .bool => |value| try std.testing.expectEqual(value, actual.bool),
        .null => {},
        else => return error.InvalidSessionValue,
    }
}
fn captureOutput(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    sdk.put(engine, data[0], "output", if (argc > 0) c.JS_DupValue(engine.context, args[0]) else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn induced(gpa: std.mem.Allocator, probe: bool) !void {
    if (!probe) return;
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    // Queued persistence deliberately records errors instead of rejecting the
    // setter. Such injected OOM outcomes still require complete owner cleanup.
    if (failing.has_induced_failure) return error.OutOfMemory;
}
fn exercise(gpa: std.mem.Allocator, directory: []const u8, probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", directory);
    try environment.put("SDK_CONFIG_DIR", directory);
    try environment.put("HOME", directory);
    try environment.put("USERPROFILE", directory);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "pi-sdk-test", "settings.mjs" });
    try @import("extensions/native_stream.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-coding-agent", exports);
    const captured = try sdk.object(engine);
    defer engine.freeValue(captured);
    const console = try sdk.object(engine);
    defer engine.freeValue(console);
    var data = [_]c.JSValue{captured};
    try sdk.put(engine, console, "log", try engine.checked(c.JS_NewCFunctionData2(engine.context, captureOutput, "captureSettingsOutput", 1, 0, 1, &data)));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "console", c.JS_DupValue(engine.context, console));
    inline for (.{
        .{ "extensions/fixtures/sdk-session-files-discovery-6fb2e78.input.json", "extensions/fixtures/sdk-session-files-discovery-6fb2e78.json", "session-files-source.mjs" },
    }) |fixture| {
        const source_input = if (probe) @embedFile("extensions/fixtures/sdk-session-files-discovery-small-6fb2e78.input.json") else @embedFile(fixture[0]);
        var input = try std.json.parseFromSlice(Input, gpa, source_input, .{});
        defer input.deinit();
        try std.testing.expectEqualStrings("6fb2e7815167e6b19006fc526d1a5d0f5f998787", input.value.sourceCommit);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(input.value.input, &digest, .{});
        try std.testing.expectEqualStrings(&std.fmt.bytesToHex(digest, .lower), input.value.inputSha256);
        const evaluation = try engine.evalModule(input.value.input, fixture[2]);
        defer engine.freeValue(evaluation);
        const settled = try engine.awaitValue(evaluation);
        engine.freeValue(settled);
        try induced(gpa, probe);
        const output = try sdk.get(engine, captured, "output");
        defer engine.freeValue(output);
        const raw = try engine.toString(output);
        defer gpa.free(raw);
        var actual = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
        defer actual.deinit();
        const source_expected = if (probe) @embedFile("extensions/fixtures/sdk-session-files-discovery-small-6fb2e78.json") else @embedFile(fixture[1]);
        var expected = try std.json.parseFromSlice(std.json.Value, gpa, source_expected, .{});
        defer expected.deinit();
        equal(expected.value, actual.value) catch |err| {
            std.debug.print("session actual {s}\n", .{raw});
            return err;
        };
        c.JS_RunGC(engine.runtime);
    }
}
test "SDK session files Source references compactions edits branches helpers and migrations" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    try exercise(std.testing.allocator, path[0..count], false);
}
test "SDK session files every failed host allocation releases getters queues errors files and lock lease" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    const Probe = struct {
        fn run(gpa: std.mem.Allocator, directory: []const u8) !void {
            _ = directory;
            var owned = std.testing.tmpDir(.{});
            defer owned.cleanup();
            var probe_path: [std.Io.Dir.max_path_bytes]u8 = undefined;
            const probe_count = try owned.dir.realPath(std.testing.io, &probe_path);
            exercise(gpa, probe_path[0..probe_count], true) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{path[0..count]});
}

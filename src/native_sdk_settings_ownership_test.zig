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
            while (fields.next()) |field| try equal(field.value_ptr.*, actual.object.get(field.key_ptr.*) orelse return error.MissingSettingsField);
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
        else => return error.InvalidSettingsValue,
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
    try environment.put("HOME", directory);
    try environment.put("USERPROFILE", directory);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "pi-sdk-test", "settings.mjs" });
    try @import("extensions/native_stream.zig").install(engine);
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
        .{ "extensions/fixtures/sdk-settings-6fb2e78.input.json", "extensions/fixtures/sdk-settings-6fb2e78.json", "settings-source.mjs" },
        .{ "extensions/fixtures/sdk-settings-edge-6fb2e78.input.json", "extensions/fixtures/sdk-settings-edge-6fb2e78.json", "settings-edge-source.mjs" },
        .{ "extensions/fixtures/sdk-settings-storage-6fb2e78.input.json", "extensions/fixtures/sdk-settings-storage-6fb2e78.json", "settings-storage-source.mjs" },
    }) |fixture| {
        var input = try std.json.parseFromSlice(Input, gpa, @embedFile(fixture[0]), .{});
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
        var expected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile(fixture[1]), .{});
        defer expected.deinit();
        try equal(expected.value, actual.value);
        c.JS_RunGC(engine.runtime);
    }
    try fileProbe(engine, gpa, directory, probe);
}
fn fileProbe(engine: *engine_mod.Engine, gpa: std.mem.Allocator, directory: []const u8, probe: bool) !void {
    const io = std.testing.io;
    const agent = try std.fs.path.join(gpa, &.{ directory, "agent" });
    defer gpa.free(agent);
    try std.Io.Dir.cwd().createDirPath(io, agent);
    const path = try std.fs.path.join(gpa, &.{ agent, "settings.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "{\"outside\":1,\"terminal\":{\"showImages\":true,\"trueColor\":true}}" });
    const exports = engine.native_module_values.get("@earendil-works/pi-coding-agent").?;
    const constructor = try sdk.get(engine, exports, "SettingsManager");
    defer engine.freeValue(constructor);
    const cwd_value = try sdk.text(engine, directory);
    defer engine.freeValue(cwd_value);
    const agent_value = try sdk.text(engine, agent);
    defer engine.freeValue(agent_value);
    const settings = try sdk.invoke(engine, constructor, "create", &.{ cwd_value, agent_value });
    defer engine.freeValue(settings);
    const provider = try sdk.text(engine, "owned");
    defer engine.freeValue(provider);
    const set = try sdk.invoke(engine, settings, "setDefaultProvider", &.{provider});
    engine.freeValue(set);
    const show = try sdk.invoke(engine, settings, "setShowImages", &.{c.pi_js_bool(engine.context, 0)});
    engine.freeValue(show);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "{\"outside\":2,\"terminal\":{\"showImages\":true,\"trueColor\":false}}" });
    const flush = try sdk.invoke(engine, settings, "flush", &.{});
    defer engine.freeValue(flush);
    const finished = try engine.awaitValue(flush);
    engine.freeValue(finished);
    try induced(gpa, probe);
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    defer gpa.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 2), parsed.value.object.get("outside").?.integer);
    try std.testing.expectEqualStrings("owned", parsed.value.object.get("defaultProvider").?.string);
    const terminal = parsed.value.object.get("terminal").?.object;
    try std.testing.expect(!terminal.get("showImages").?.bool and !terminal.get("trueColor").?.bool);
    const lock = try std.fmt.allocPrint(gpa, "{s}.lock", .{path});
    defer gpa.free(lock);
    std.Io.Dir.cwd().access(io, lock, .{}) catch |err| {
        if (err != error.FileNotFound) return err;
        return;
    };
    return error.SettingsFileLeaseLeaked;
}
test "SDK settings Source getter storage queue and real file merge release ownership" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    try exercise(std.testing.allocator, path[0..count], false);
}
test "SDK settings every failed host allocation releases getters queues errors files and lock lease" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    const Probe = struct {
        fn run(gpa: std.mem.Allocator, directory: []const u8) !void {
            exercise(gpa, directory, true) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{path[0..count]});
}

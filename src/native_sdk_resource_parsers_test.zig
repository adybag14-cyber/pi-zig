//! Byte-exact replay of the actual Source33 caller on real native filesystem parsers.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn writeFixtures(gpa: std.mem.Allocator, directory: std.Io.Dir, bytes: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
    defer parsed.deinit();
    for (parsed.value.object.get("files").?.array.items) |file| {
        const path = file.object.get("path").?.string;
        if (std.fs.path.dirname(path)) |parent| try directory.createDirPath(std.testing.io, parent);
        try directory.writeFile(std.testing.io, .{ .sub_path = path, .data = file.object.get("content").?.string });
    }
    for (parsed.value.object.get("themes").?.array.items) |file| {
        const path = file.object.get("path").?.string;
        if (std.fs.path.dirname(path)) |parent| try directory.createDirPath(std.testing.io, parent);
        var asset = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/sdk-resource-paths-dark-5ab.json"), .{});
        defer asset.deinit();
        asset.value.object.getPtr("name").?.* = file.object.get("name").?;
        const text = try std.json.Stringify.valueAlloc(gpa, asset.value, .{ .whitespace = .indent_2 });
        defer gpa.free(text);
        try directory.writeFile(std.testing.io, .{ .sub_path = path, .data = text });
    }
}
fn run(gpa: std.mem.Allocator) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeFixtures(gpa, temporary.dir, @embedFile("extensions/fixtures/sdk-resource-class-5ab.files.json"));
    try writeFixtures(gpa, temporary.dir, @embedFile("extensions/fixtures/sdk-resource-parsers-5ab.files.json"));
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const generation = engine.native_allocation_generation;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    const home = try std.fs.path.join(gpa, &.{ path_buffer[0..length], "home" });
    defer gpa.free(home);
    try temporary.dir.createDirPath(std.testing.io, "home");
    try environment.put("HOME", home);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"sdk-resource-parsers-5ab"});
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    try @import("extensions/native_sdk_resource_class_sources.zig").install(engine, prototype);
    try @import("extensions/native_sdk_resource_class_skill_update.zig").install(engine, prototype);
    try @import("extensions/native_sdk_resource_class_prompt_update.zig").install(engine, prototype);
    const api = try scope.object();
    try scope.put(api, "loadSkills", try scope.own(try @import("extensions/native_sdk_skill_loader.zig").create(engine)));
    try scope.put(api, "loadPromptTemplates", try scope.own(try @import("extensions/native_sdk_prompt_loader.zig").create(engine)));
    try scope.put(api, "parseFrontmatter", try scope.own(try @import("extensions/native_sdk_frontmatter_values.zig").create(engine)));
    try scope.put(api, "prototype", prototype);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "resourceParserAPI", api);
    try scope.put(global, "resourceParserFixtureRoot", try scope.text(path_buffer[0..length]));
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-resource-parsers-5ab.input.txt"), "resource-parsers-original-5ab.mjs") catch |err| {
        const original = engine.nativeAllocationError(err, generation);
        if (original == error.OutOfMemory) return original;
        std.debug.print("Native real resource parser caller failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        const partial = try engine.stringify(try scope.get(global, "resourceParserRows"));
        defer gpa.free(partial);
        std.debug.print("NATIVE_RESOURCE_PARSER_PARTIAL_ROWS={s}\n", .{partial});
        return original;
    };
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    const actual = try engine.stringify(try scope.get(global, "resourceParserRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-resource-parsers-5ab.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "resource-parsers-original-5ab.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual native resource parsers:\n{s}\nExpected genuine Source:\n{s}\n", .{ actual, raw });
        return error.NativeResourceParsersSource33Mismatch;
    }
}
test "native real resource parsers match actual 5ab caller fixture" {
    try run(std.testing.allocator);
}
test "native real resource parsers allocation measurement" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try run(baseline.allocator());
    if (baseline.allocated_bytes != baseline.freed_bytes) return error.MemoryLeakDetected;
    std.debug.print("RESOURCE_PARSER_ALLOCATION_MEASUREMENT total={d} allocated_bytes={d} freed_bytes={d}\n", .{ baseline.alloc_index, baseline.allocated_bytes, baseline.freed_bytes });
}
test "native real resource parsers complete representative allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-resourceparsers5ab", run, .{});
}

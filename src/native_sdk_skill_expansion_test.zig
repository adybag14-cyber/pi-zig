const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const group_mod = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;

// Source482 ran on Windows. Normalize only separators immediately following
// its explicit owned-directory marker, preserving all other string content.
fn portablePaths(value: *json.Value) void {
    switch (value.*) {
        .string => |text| {
            var from: usize = 0;
            while (std.mem.indexOfPos(u8, text, from, "<SDK_SKILL_ROOT>\\")) |position| {
                @constCast(text)[position + "<SDK_SKILL_ROOT>".len] = '/';
                from = position + "<SDK_SKILL_ROOT>/".len;
            }
        },
        .array => |*array| for (array.items) |*item| portablePaths(item),
        .object => |*object| {
            var iterator = object.iterator();
            while (iterator.next()) |entry| portablePaths(entry.value_ptr);
        },
        else => {},
    }
}

test "native SDK skill expansion matches all Source482 queue error getter and raw XML observations" {
    const gpa = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var directory: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &directory);
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-skill482-root");
    try root.installSchemas();
    // Same dependency order as the production native_worker bootstrap.
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    try @import("extensions/node_url.zig").install(engine);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const global = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkSkillRoot", try sdk.text(engine, directory[0..length]));
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/sdk-skill-expansion-source-482.input.txt"), "sdk-skill482.mjs") catch |err| {
        std.debug.print("SDK skill482 driver failed: {s}\n", .{engine.last_error orelse "<no engine diagnostic>"});
        return err;
    };
    defer engine.freeValue(loaded);
    const result = try engine.eval("sdkSkillExpansionResult", "sdk-skill482-result.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer gpa.free(raw);
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/sdk-skill-expansion-source-482.json"));
    defer expected.deinit();
    portablePaths(&actual.value);
    portablePaths(&expected.value);
    const actual_rows = actual.value.object.get("rows") orelse return error.MissingNativeSkillRows;
    const expected_rows = expected.value.object.get("rows") orelse return error.MissingSourceSkillRows;
    try std.testing.expectEqual(@as(usize, 10), actual_rows.array.items.len);
    try std.testing.expectEqual(@as(usize, 10), expected_rows.array.items.len);
    if (!json.equal(expected_rows, actual_rows)) std.debug.print("SDK skill482 actual={s}\n", .{raw});
    try std.testing.expect(json.equal(expected_rows, actual_rows));
    em.c.JS_RunGC(engine.runtime);
}

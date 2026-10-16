//! Actual Source22 input runs unchanged against real native node:fs APIs.
//! The original physical Source files retain their kernel timestamps; no
//! invented Stats, path results, or expected rows are injected.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const c = em.c;
const json = @import("mcp/protocol.zig").json;

test "native filesystem metadata equals all22 actual Node Source callers on retained physical files" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const qualification = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("../verification/node-fs-metadata-source22-20261016/qualification.json"), .{});
    defer qualification.deinit();
    const root = qualification.value.object.get("physical_fixture_root").?.string;
    var controls = try json.Owned.parse(std.testing.allocator, @embedFile("../verification/node-fs-metadata-source22-20261016/node-fs-metadata-24-source-first-0a800f30-20261016-controls-before.json"));
    defer controls.deinit();
    var physical_count: usize = 0;
    for (controls.value.array.items) |row| {
        const path = row.object.get("path").?.string;
        if (!std.mem.startsWith(u8, path, root)) continue;
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(bytes);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .upper);
        try std.testing.expectEqualStrings(row.object.get("sha256").?.string, &hex);
        physical_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 31), physical_count);
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("extensions/node_url.zig").install(engine);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "fsMetadataFixtureRoot", c.JS_NewStringLen(engine.context, root.ptr, root.len)) < 0) return error.JavaScriptException;
    const setup = try engine.evalModule("import fs from 'node:fs';import {pathToFileURL} from 'node:url';globalThis.fsMetadataAPI={fs,pathToFileURL};", "fs-metadata-native-setup.mjs");
    defer engine.freeValue(setup);
    const value = engine.evalModule(@embedFile("extensions/fixtures/node-fs-metadata-24.input.txt"), "actual-node-fs-metadata-24.mjs") catch |err| {
        std.debug.print("Native fs metadata actual Source22: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(value);
    const rows = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "fsMetadataRows"));
    defer engine.freeValue(rows);
    const encoded = try engine.stringify(rows);
    defer std.testing.allocator.free(encoded);
    var actual = try json.Owned.parse(std.testing.allocator, encoded);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/node-fs-metadata-24.json"));
    defer expected.deinit();
    const expected_rows = expected.value.object.get("rows").?;
    try std.testing.expectEqual(@as(usize, 22), actual.value.array.items.len);
    try std.testing.expectEqual(@as(usize, 22), expected_rows.array.items.len);
    if (!json.equal(expected_rows, actual.value)) std.debug.print("Actual native fs metadata rows: {s}\n", .{encoded});
    try std.testing.expect(json.equal(expected_rows, actual.value));
}

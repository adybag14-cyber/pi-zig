//! Real provider privacy, normalized durable images and live skill discovery.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const events = @import("test_support/rpc_events.zig");
const http = @import("test_support/http_fixture.zig");
const Io = std.Io;
const success: http.Response = .{ .headers = "content-type: text/event-stream\r\n", .body = "data: {\"id\":\"chatcmpl-172\",\"choices\":[{\"delta\":{\"content\":\"media-policy-ok-172\"}}]}\n\n" ++
    "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":1,\"total_tokens\":3}}\n\n" ++ "data: [DONE]\n\n" };

fn containsImage(value: std.json.Value) bool {
    switch (value) {
        .string => |v| return std.mem.indexOf(u8, v, "data:image/") != null or (std.mem.startsWith(u8, v, "image/") and v.len > 20),
        .array => |a| for (a.items) |v| {
            if (containsImage(v)) return true;
        },
        .object => |o| {
            var it = o.iterator();
            while (it.next()) |entry| {
                for ([_][]const u8{ "image_url", "input_image", "image", "inline_data", "inlineData" }) |key| if (std.ascii.eqlIgnoreCase(key, entry.key_ptr.*)) return true;
                if (containsImage(entry.value_ptr.*)) return true;
            }
        },
        else => {},
    }
    return false;
}
fn containsText(value: std.json.Value, wanted: []const u8) bool {
    switch (value) {
        .string => |v| return std.mem.indexOf(u8, v, wanted) != null,
        .array => |a| for (a.items) |v| {
            if (containsText(v, wanted)) return true;
        },
        .object => |o| {
            var it = o.iterator();
            while (it.next()) |entry| if (containsText(entry.value_ptr.*, wanted)) return true;
        },
        else => {},
    }
    return false;
}
fn bmp() [58]u8 {
    var data = [_]u8{0} ** 58;
    @memcpy(data[0..2], "BM");
    data[2] = 58;
    data[10] = 54;
    data[14] = 40;
    data[18] = 1;
    data[22] = 1;
    data[26] = 1;
    data[28] = 24;
    data[34] = 4;
    @memcpy(data[54..57], &[_]u8{ 0x33, 0x66, 0xcc });
    return data;
}
// Independently decode the single normalized PNG pixel instead of trusting a
// converter output marker or reusing production image-processing functions.
fn verifyPixel(gpa: std.mem.Allocator, encoded: []const u8) !void {
    const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
    defer gpa.free(bytes);
    try std.base64.standard.Decoder.decode(bytes, encoded);
    try std.testing.expect(bytes.len >= 33 and std.mem.eql(u8, bytes[0..8], "\x89PNG\r\n\x1a\n"));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, bytes[16..20], .big));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, bytes[20..24], .big));
    const depth = bytes[24];
    const color = bytes[25];
    var palette: []const u8 = &.{};
    var compressed: std.ArrayList(u8) = .empty;
    defer compressed.deinit(gpa);
    var cursor: usize = 8;
    while (cursor + 12 <= bytes.len) {
        const length: usize = std.mem.readInt(u32, bytes[cursor..][0..4], .big);
        try std.testing.expect(length <= bytes.len - cursor - 12);
        const kind = bytes[cursor + 4 .. cursor + 8];
        const payload = bytes[cursor + 8 .. cursor + 8 + length];
        const crc = std.mem.readInt(u32, bytes[cursor + 8 + length ..][0..4], .big);
        try std.testing.expectEqual(crc, std.hash.Crc32.hash(bytes[cursor + 4 .. cursor + 8 + length]));
        if (std.mem.eql(u8, kind, "PLTE")) palette = payload;
        if (std.mem.eql(u8, kind, "IDAT")) try compressed.appendSlice(gpa, payload);
        cursor += length + 12;
        if (std.mem.eql(u8, kind, "IEND")) break;
    }
    var input: Io.Reader = .fixed(compressed.items);
    var inflate = std.compress.flate.Decompress.init(&input, .zlib, &.{});
    const scanline = try inflate.reader.allocRemaining(gpa, .limited(8));
    defer gpa.free(scanline);
    try std.testing.expect(scanline.len >= 2 and scanline[0] <= 4);
    const rgb: []const u8 = if (color == 3) indexed: {
        try std.testing.expect(depth == 1 or depth == 2 or depth == 4 or depth == 8);
        const index: usize = scanline[1] >> @as(u3, @intCast(8 - depth));
        try std.testing.expect(index * 3 + 3 <= palette.len);
        break :indexed palette[index * 3 .. index * 3 + 3];
    } else direct: {
        try std.testing.expect((color == 2 or color == 6) and depth == 8 and scanline.len >= 4);
        break :direct scanline[1..4];
    };
    try std.testing.expectEqualSlices(u8, &.{ 0xcc, 0x66, 0x33 }, rgb);
}

fn imageCase(gpa: std.mem.Allocator, io: Io, binary: []const u8, blocked: bool) !void {
    var scratch = try pty.Scratch.init(gpa, io, "media-image");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "workspace", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    const image = bmp();
    try scratch.dir.writeFile(io, .{ .sub_path = "workspace/pixel-renamed.dat", .data = &image });
    const settings = try std.fmt.allocPrint(gpa, "{{\"images\":{{\"blockImages\":{s}}},\"terminal\":{{\"showImages\":false,\"imageWidthCells\":80}},\"enableInstallTelemetry\":false,\"quietStartup\":true}}", .{if (blocked) "true" else "false"});
    defer gpa.free(settings);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = settings });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const work = try std.fs.path.join(gpa, &.{ scratch.path, "workspace" });
    defer gpa.free(work);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const attachment = try std.fmt.allocPrint(gpa, "@{s}/pixel-renamed.dat", .{work});
    defer gpa.free(attachment);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const server = try http.Server.startScripted(gpa, io, &.{success});
    defer server.deinit();
    const base = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/v1", .{server.port});
    defer gpa.free(base);
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &.{ binary, "--provider", "baseten", "--model", "moonshotai/Kimi-K2.5", "--base-url", base, "--api-key", "media-key-172", "--mode", "json", "--session-dir", sessions, "--session-id", "media-172", "--no-tools", "--no-extensions", "--no-context-files", "--no-skills", "--no-prompt-templates", "--print", "describe the attached checkpoint image", attachment }, .cwd = .{ .path = work }, .environ_map = &environment, .stdin = .ignore, .stderr = .{ .file = errors_file } }, 60_000);
    defer child.deinit();
    const term = try child.wait(60_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
    try server.finish();
    const requests = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, requests);
    try std.testing.expectEqual(@as(usize, 1), requests.len);
    try std.testing.expect(std.mem.endsWith(u8, requests[0].path, "/chat/completions"));
    const body = try std.json.parseFromSlice(std.json.Value, gpa, requests[0].body, .{});
    defer body.deinit();
    try std.testing.expectEqual(!blocked, containsImage(body.value));
    try std.testing.expectEqual(blocked, containsText(body.value, "Image reading is disabled."));
    const durable = try scratch.dir.readFileAlloc(io, "sessions/media-172.jsonl", gpa, .limited(1024 * 1024));
    defer gpa.free(durable);
    try std.testing.expect(std.mem.indexOf(u8, durable, "media-policy-ok-172") != null);
    try std.testing.expect(std.mem.indexOf(u8, child.output.items, "media-policy-ok-172") != null);
    var lines = std.mem.splitScalar(u8, durable, '\n');
    var images: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        const message = record.value.object.get("message") orelse continue;
        const role = message.object.get("role") orelse continue;
        if (role != .string or !std.mem.eql(u8, role.string, "user")) continue;
        const content = message.object.get("content").?;
        if (content != .array) continue;
        for (content.array.items) |block| {
            const kind = block.object.get("type") orelse continue;
            if (kind == .string and std.mem.eql(u8, kind.string, "image")) {
                images += 1;
                try std.testing.expectEqualStrings("image/png", block.object.get("mimeType").?.string);
                try verifyPixel(gpa, block.object.get("data").?.string);
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 1), images);
    try std.testing.expect(std.mem.indexOf(u8, durable, "Image converted from image/bmp to image/png.") != null);
}
fn hasSkill(value: std.json.Value) !bool {
    const data = value.object.get("data") orelse return error.SkillCommandDataMissing;
    const commands = data.object.get("commands") orelse return error.SkillCommandsMissing;
    if (commands != .array) return error.SkillCommandsNotArray;
    for (commands.array.items) |command| {
        if (command != .object) continue;
        const name = command.object.get("name") orelse continue;
        if (name == .string and std.mem.eql(u8, name.string, "skill:checkpoint172")) return true;
    }
    return false;
}
fn skillCase(gpa: std.mem.Allocator, io: Io, binary: []const u8) !void {
    var scratch = try pty.Scratch.init(gpa, io, "media-skills");
    defer scratch.deinit();
    try scratch.dir.createDirPath(io, "agent/skills/checkpoint172");
    try scratch.dir.createDir(io, "workspace", .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/skills/checkpoint172/SKILL.md", .data = "---\nname: checkpoint172\ndescription: Checkpoint 172 command-discovery fixture\n---\n\nUse this fixture.\n" });
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"enableSkillCommands\":false,\"enableInstallTelemetry\":false,\"quietStartup\":true}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"unused-172\"}]" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    const work = try std.fs.path.join(gpa, &.{ scratch.path, "workspace" });
    defer gpa.free(work);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &.{ binary, "--offline", "--mock-script", mock, "--mode", "rpc", "--no-session", "--no-tools", "--no-extensions", "--no-context-files" }, .cwd = .{ .path = work }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = errors_file } }, 90_000);
    defer child.deinit();
    try child.send("{\"id\":\"c1\",\"type\":\"get_commands\"}\n");
    const disabled = try events.response(gpa, &child, "c1");
    defer disabled.deinit();
    try std.testing.expect(!try hasSkill(disabled.value));
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json.tmp", .data = "{\"enableSkillCommands\":true,\"enableInstallTelemetry\":false,\"quietStartup\":true}" });
    try scratch.dir.rename("agent/settings.json.tmp", scratch.dir, "agent/settings.json", io);
    try child.send("{\"id\":\"r1\",\"type\":\"reload\"}\n");
    const reload = try events.response(gpa, &child, "r1");
    reload.deinit();
    try child.send("{\"id\":\"c2\",\"type\":\"get_commands\"}\n");
    const enabled = try events.response(gpa, &child, "c2");
    defer enabled.deinit();
    try std.testing.expect(try hasSkill(enabled.value));
    try child.send("{\"id\":\"q1\",\"type\":\"quit\"}\n");
    const quit = try events.response(gpa, &child, "q1");
    quit.deinit();
    child.closeInput();
    const term = try child.wait(20_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
}
test "native media privacy preserves normalized pixels and reloads skill commands" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    try imageCase(gpa, io, binary, true);
    try imageCase(gpa, io, binary, false);
    try skillCase(gpa, io, binary);
    const report = "{\"blockedProviderImage\":true,\"blockedPlaceholder\":true,\"blockedDurableImage\":true,\"allowedProviderImage\":true,\"allowedDurableImage\":true,\"skillDisabledHidden\":true,\"skillEnabledAfterReload\":true,\"rpcReload\":true,\"stderrBytes\":0}\n";
    if (environment.get("PI_MEDIA_SKILLS_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("MEDIA_SKILL_SETTINGS_E2E_172=PASS\n{s}", .{report});
}

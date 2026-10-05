//! Actual image normalization for attachments, read results and post-hook data.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const sessions = @import("test_support/session_fixture.zig");
const json = @import("test_support/json_fixture.zig");
const image = @import("test_support/image_fixture.zig");
const extension = @import("test_support/image_extension_fixture.zig");
const Io = std.Io;
const Dims = std.meta.Tuple(&.{ []const u8, u32, u32 });
const StartupOn = struct { images: usize = 4, large: Dims, bmp: Dims, exif: Dims, byteLimit: Dims, byteLimitBase64Bytes: usize, stderrBytes: usize = 0 };
const StartupOff = struct { exactPreservation: bool = true, bmpConversion: bool = true, images: usize = 2, stderrBytes: usize = 0 };
const ToolResult = struct { dimensions: Dims, persisted: bool = true, stderrBytes: usize = 0 };
const ExtensionResult = struct { dimensions: Dims, postHook: bool = true, persisted: bool = true, stderrBytes: usize = 0 };
const Fixture = struct {
    scratch: pty.Scratch,
    env: std.process.Environ.Map,
    agent: []u8,
    work: []u8,
    sessions: []u8,
    mock: []u8,
    binary: []u8,
    converter: []u8,
    fn init(auto_resize: bool) !Fixture {
        const gpa = std.testing.allocator;
        const io = std.testing.io;
        var scratch = try pty.Scratch.init(gpa, io, "image-processing");
        errdefer scratch.deinit();
        for ([_][]const u8{ "agent", "work", "sessions", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
        const settings = try std.fmt.allocPrint(gpa, "{{\"images\":{{\"autoResize\":{s}}},\"quietStartup\":true,\"enableInstallTelemetry\":false}}", .{if (auto_resize) "true" else "false"});
        defer gpa.free(settings);
        try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = settings });
        var env = try std.process.Environ.createMap(std.testing.environ, gpa);
        errdefer env.deinit();
        const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
        errdefer gpa.free(agent);
        const work = try std.fs.path.join(gpa, &.{ scratch.path, "work" });
        errdefer gpa.free(work);
        const session_dir = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
        errdefer gpa.free(session_dir);
        const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
        errdefer gpa.free(mock);
        const binary = try pty.executablePath(gpa, io, env.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
        errdefer gpa.free(binary);
        const converter = try pty.executablePath(gpa, io, env.get("PI_IMAGE_TEST_CONVERTER") orelse "/usr/bin/convert");
        errdefer gpa.free(converter);
        try env.put("PI_AGENT_DIR", agent);
        try env.put("PI_IMAGE_CONVERTER", converter);
        try env.put("PI_SKIP_VERSION_CHECK", "1");
        try env.put("PI_TELEMETRY", "0");
        try env.put("NO_COLOR", "1");
        return .{ .scratch = scratch, .env = env, .agent = agent, .work = work, .sessions = session_dir, .mock = mock, .binary = binary, .converter = converter };
    }
    fn deinit(self: *Fixture) void {
        const gpa = self.scratch.gpa;
        for ([_][]u8{ self.agent, self.work, self.sessions, self.mock, self.binary, self.converter }) |bytes| gpa.free(bytes);
        self.env.deinit();
        self.scratch.deinit();
    }
    fn path(self: *Fixture, name: []const u8) ![]u8 {
        return std.fs.path.join(self.scratch.gpa, &.{ self.work, name });
    }
    fn render(self: *Fixture, args: []const []const u8) !void {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.scratch.gpa);
        try argv.append(self.scratch.gpa, self.converter);
        try argv.appendSlice(self.scratch.gpa, args);
        const result = try std.process.run(self.scratch.gpa, self.scratch.io, .{ .argv = argv.items, .stdout_limit = .limited(65536), .stderr_limit = .limited(65536), .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .real } } });
        defer self.scratch.gpa.free(result.stdout);
        defer self.scratch.gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            std.debug.print("Image converter failed: {s}\n", .{result.stderr});
            return error.ImageConverterFixtureFailed;
        }
    }
    fn run(self: *Fixture, extra: []const []const u8) ![]u8 {
        const gpa = self.scratch.gpa;
        const io = self.scratch.io;
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.appendSlice(gpa, &.{ self.binary, "--offline", "-p", "--mode", "json", "--mock-script", self.mock, "--session-dir", self.sessions, "--session-id", "image-174", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve" });
        try argv.appendSlice(gpa, extra);
        const errors_file = try self.scratch.dir.createFile(io, "stderr.log", .{});
        defer errors_file.close(io);
        var child = try rpc.Process.spawn(gpa, io, .{ .argv = argv.items, .cwd = .{ .path = self.work }, .environ_map = &self.env, .stdin = .ignore, .stderr = .{ .file = errors_file } }, 150_000);
        defer child.deinit();
        const term = try child.wait(150_000);
        const errors = try self.scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
        defer gpa.free(errors);
        if (term != .exited or term.exited != 0 or errors.len != 0) {
            std.debug.print("Image CLI {any}: {s}\n{s}\n", .{ term, errors, child.output.items });
            return error.ImageProcessFixtureFailed;
        }
        return gpa.dupe(u8, child.output.items);
    }
    fn records(self: *Fixture) !std.json.Parsed(std.json.Value) {
        const session_path = try std.fs.path.join(self.scratch.gpa, &.{ self.sessions, "image-174.jsonl" });
        defer self.scratch.gpa.free(session_path);
        return sessions.load(self.scratch.gpa, self.scratch.io, session_path);
    }
};
fn message(items: []const std.json.Value, role: []const u8, tool: ?[]const u8) !std.json.Value {
    for (items) |record| {
        if (!json.kind(record, "message")) continue;
        const value = try json.field(record, "message");
        const actual = try json.field(value, "role");
        if (actual != .string or !std.mem.eql(u8, actual.string, role)) continue;
        if (tool) |wanted| {
            const name = try json.field(value, "toolName");
            if (name != .string or !std.mem.eql(u8, name.string, wanted)) continue;
        }
        return value;
    }
    return error.ImageMessageMissing;
}
const Blocks = struct {
    images: std.ArrayList(std.json.Value) = .empty,
    text: std.ArrayList(u8) = .empty,
    fn deinit(self: *Blocks, gpa: std.mem.Allocator) void {
        self.images.deinit(gpa);
        self.text.deinit(gpa);
    }
};
fn blocks(gpa: std.mem.Allocator, content: std.json.Value) !Blocks {
    var result: Blocks = .{};
    errdefer result.deinit(gpa);
    if (content == .string) {
        try result.text.appendSlice(gpa, content.string);
        return result;
    }
    try std.testing.expect(content == .array);
    for (content.array.items) |block| {
        if (json.kind(block, "image")) try result.images.append(gpa, block);
        if (json.kind(block, "text")) {
            if (result.text.items.len > 0) try result.text.append(gpa, '\n');
            try result.text.appendSlice(gpa, (try json.field(block, "text")).string);
        }
    }
    return result;
}
fn tuple(d: image.Dimensions) Dims {
    return .{ d.mime, d.width, d.height };
}
fn startup(auto_resize: bool) !StartupOn {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var f = try Fixture.init(auto_resize);
    defer f.deinit();
    const large = try f.path("large.png");
    defer gpa.free(large);
    const noisy = try f.path("byte-limit.png");
    defer gpa.free(noisy);
    const rotated_base = try f.path("rotated-base.jpg");
    defer gpa.free(rotated_base);
    const rotated = try f.path("rotated.jpg");
    defer gpa.free(rotated);
    const bmp = try f.path("compat.bmp");
    defer gpa.free(bmp);
    try f.render(&.{ "-size", "3000x1000", "gradient:#13579b-#fedcba", "-depth", "8", large });
    try f.render(&.{ "-size", "100x100", "xc:#6a2ca0", "-depth", "8", noisy });
    const noisy_bytes = try Io.Dir.cwd().readFileAlloc(io, noisy, gpa, .limited(1024 * 1024));
    defer gpa.free(noisy_bytes);
    const expanded = try image.ancillary(gpa, noisy_bytes);
    defer gpa.free(expanded);
    try f.scratch.dir.writeFile(io, .{ .sub_path = "work/byte-limit.png", .data = expanded });
    try std.testing.expect(std.base64.standard.Encoder.calcSize(expanded.len) >= 4_718_592);
    try f.render(&.{ "-size", "2400x1000", "gradient:#602080-#20a060", "-quality", "92", rotated_base });
    const jpeg = try Io.Dir.cwd().readFileAlloc(io, rotated_base, gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(jpeg);
    const oriented = try image.exif(gpa, jpeg);
    defer gpa.free(oriented);
    try f.scratch.dir.writeFile(io, .{ .sub_path = "work/rotated.jpg", .data = oriented });
    const bmp_bytes = try image.bmp(gpa);
    defer gpa.free(bmp_bytes);
    try f.scratch.dir.writeFile(io, .{ .sub_path = "work/compat.bmp", .data = bmp_bytes });
    try f.scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"startup-complete-174\",\"tool_calls\":[]}]" });
    const refs = try gpa.alloc([]u8, 4);
    defer gpa.free(refs);
    var count: usize = 0;
    defer for (refs[0..count]) |ref| gpa.free(ref);
    for ([_][]const u8{ large, bmp, rotated, noisy }) |path| {
        refs[count] = try std.fmt.allocPrint(gpa, "@{s}", .{path});
        count += 1;
    }
    const output = try f.run(if (auto_resize) &.{ "--no-extensions", "--no-tools", "inspect startup images", refs[0], refs[1], refs[2], refs[3] } else &.{ "--no-extensions", "--no-tools", "inspect startup images", refs[0], refs[1] });
    defer gpa.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "startup-complete-174") != null);
    const records = try f.records();
    defer records.deinit();
    const user = try message(records.value.array.items, "user", null);
    var content = try blocks(gpa, try json.field(user, "content"));
    defer content.deinit(gpa);
    try std.testing.expectEqual(@as(usize, if (auto_resize) 4 else 2), content.images.items.len);
    const images = content.images.items;
    const large_data = (try json.field(images[0], "data")).string;
    const bmp_data = (try json.field(images[1], "data")).string;
    const large_dims = try image.assertDimensions(gpa, large_data, if (auto_resize) 2000 else 3000, if (auto_resize) 667 else 1000);
    const bmp_dims = try image.assertDimensions(gpa, bmp_data, 32, 16);
    try std.testing.expectEqualStrings("image/png", large_dims.mime);
    try std.testing.expectEqualStrings("image/png", bmp_dims.mime);
    try std.testing.expect(std.mem.indexOf(u8, content.text.items, "converted from image/bmp to image/png") != null);
    if (!auto_resize) {
        const original = try Io.Dir.cwd().readFileAlloc(io, large, gpa, .limited(16 * 1024 * 1024));
        defer gpa.free(original);
        const preserved = try image.decode(gpa, large_data);
        defer gpa.free(preserved);
        try std.testing.expectEqualSlices(u8, original, preserved);
        try std.testing.expect(std.mem.indexOf(u8, content.text.items, "displayed at") == null);
        return .{ .images = 2, .large = tuple(large_dims), .bmp = tuple(bmp_dims), .exif = .{ "unused", 0, 0 }, .byteLimit = .{ "unused", 0, 0 }, .byteLimitBase64Bytes = 0 };
    }
    const exif_dims = try image.assertDimensions(gpa, (try json.field(images[2], "data")).string, 833, 2000);
    const byte_data = (try json.field(images[3], "data")).string;
    const byte_dims = try image.assertDimensions(gpa, byte_data, 100, 100);
    try std.testing.expect(byte_data.len < 4_718_592);
    for ([_][]const u8{ "original 3000x1000, displayed at 2000x667", "original 1000x2400, displayed at 833x2000", "original 100x100, displayed at 100x100" }) |hint| try std.testing.expect(std.mem.indexOf(u8, content.text.items, hint) != null);
    return .{ .large = tuple(large_dims), .bmp = tuple(bmp_dims), .exif = tuple(exif_dims), .byteLimit = tuple(byte_dims), .byteLimitBase64Bytes = byte_data.len };
}
fn toolCase(post_hook: bool) !Dims {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var f = try Fixture.init(true);
    defer f.deinit();
    const name = if (post_hook) "large-hook.png" else "large-read.png";
    const path = try f.path(name);
    defer gpa.free(path);
    try f.render(if (post_hook) &.{ "-size", "3600x900", "gradient:#e03050-#103070", "-depth", "8", path } else &.{ "-size", "3200x1600", "gradient:#120030-#30d0f0", "-depth", "8", path });
    const extension_path = try std.fs.path.join(gpa, &.{ f.scratch.path, "extension.ts" });
    defer gpa.free(extension_path);
    try f.scratch.dir.writeFile(io, .{ .sub_path = "extension.ts", .data = extension.source });
    const mock = if (post_hook) "[{\"content\":\"calling image extension\",\"tool_calls\":[{\"id\":\"image-call-174\",\"name\":\"image174\",\"arguments\":\"{}\"}]},{\"content\":\"extension-image-complete-174\",\"tool_calls\":[]}]" else "[{\"content\":\"reading image\",\"tool_calls\":[{\"id\":\"read-image-174\",\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"large-read.png\\\"}\"}]},{\"content\":\"read-image-complete-174\",\"tool_calls\":[]}]";
    try f.scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = mock });
    const output = try f.run(if (post_hook) &.{ "--extension", extension_path, "--no-builtin-tools", "--tools", "image174", "run image hook" } else &.{ "--no-extensions", "--tools", "read", "read the image" });
    defer gpa.free(output);
    const tool_name = if (post_hook) "image174" else "read";
    var lines = std.mem.splitScalar(u8, output, '\n');
    var terminal_events: usize = 0;
    var dims: ?Dims = null;
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        const event = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer event.deinit();
        if (!json.kind(event.value, "tool_execution_end")) continue;
        const tool = (try json.field(event.value, "toolName")).string;
        if (!std.mem.eql(u8, tool, tool_name)) continue;
        terminal_events += 1;
        var content = try blocks(gpa, try json.field(try json.field(event.value, "result"), "content"));
        defer content.deinit(gpa);
        try std.testing.expectEqual(@as(usize, 1), content.images.items.len);
        const value = try image.assertDimensions(gpa, (try json.field(content.images.items[0], "data")).string, 2000, if (post_hook) 500 else 1000);
        try std.testing.expectEqualStrings("image/png", value.mime);
        dims = tuple(value);
        try std.testing.expect(std.mem.indexOf(u8, content.text.items, if (post_hook) "original 3600x900, displayed at 2000x500" else "original 3200x1600, displayed at 2000x1000") != null);
        if (post_hook) try std.testing.expect(std.mem.indexOf(u8, content.text.items, "post-hook-174") != null);
    }
    try std.testing.expectEqual(@as(usize, 1), terminal_events);
    const records = try f.records();
    defer records.deinit();
    const persisted = try message(records.value.array.items, "toolResult", tool_name);
    var content = try blocks(gpa, try json.field(persisted, "content"));
    defer content.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), content.images.items.len);
    _ = try image.assertDimensions(gpa, (try json.field(content.images.items[0], "data")).string, 2000, if (post_hook) 500 else 1000);
    return dims.?;
}
test "native image processing preserves all four executable normalization scenarios" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const on = try startup(true);
    _ = try startup(false);
    const read = try toolCase(false);
    const hook = try toolCase(true);
    const report = try std.json.Stringify.valueAlloc(std.testing.allocator, .{ .checkpoint = 174, .status = "PASS", .startupResizeOn = on, .startupResizeOff = StartupOff{}, .readTool = ToolResult{ .dimensions = read }, .extensionPostHook = ExtensionResult{ .dimensions = hook } }, .{ .whitespace = .indent_2 });
    defer std.testing.allocator.free(report);
    var env = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer env.deinit();
    if (env.get("PI_IMAGE_PROCESSING_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(std.testing.io, path, .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, report);
        try file.writeStreamingAll(std.testing.io, "\n");
    }
    std.debug.print("IMAGE_PROCESSING_E2E_174=PASS\n{s}\n", .{report});
}

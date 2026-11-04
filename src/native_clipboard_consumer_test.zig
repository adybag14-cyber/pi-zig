//! Focused application clipboard controls. Native operations are read-only;
//! every copy path injects a backend/command writer and never changes the OS clipboard.
const std = @import("std");
const builtin = @import("builtin");
const clipboard = @import("coding_agent/clipboard.zig");
const native = clipboard.native_clipboard;
const Io = std.Io;
const gpa = std.testing.allocator;
const io = std.testing.io;

test "native clipboard consumer command order replacement and empty success" {
    const Fake = struct {
        mode: enum { empty, replacement, native_text } = .empty,
        calls: usize = 0,
        native_calls: usize = 0,
        valid: bool = true,
        fn run(raw: *anyopaque, allocator: std.mem.Allocator, _: Io, argv: []const []const u8, timeout_ms: u64, _: ?*const std.process.Environ.Map) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const commands = [_][]const u8{ "termux-clipboard-get", "wl-paste", "xclip", "xsel" };
            const index = self.calls;
            self.calls += 1;
            self.valid = self.valid and index < commands.len and timeout_ms == 5000;
            if (index < commands.len) self.valid = self.valid and std.mem.eql(u8, argv[0], commands[index]);
            if (index == 2) self.valid = self.valid and argv.len == 4 and std.mem.eql(u8, argv[3], "-out");
            if (self.mode == .empty and index == 0) return try allocator.alloc(u8, 0);
            if (self.mode == .replacement and index == 1) return try allocator.dupe(u8, "\xf0\x9f\x92\x00x");
            return null;
        }
        fn get(raw: ?*anyopaque, allocator: std.mem.Allocator, limit: usize) !native.Read {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.native_calls += 1;
            self.valid = self.valid and limit == native.default_memory_limit;
            return .{ .value = try allocator.dupe(u8, "native text") };
        }
    };
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    try env.put("TERMUX_VERSION", "test");
    try env.put("WAYLAND_DISPLAY", "test");
    try env.put("DISPLAY", ":0");
    var fake: Fake = .{};
    const options: clipboard.Options = .{
        .platform = .linux, .environ = &env,
        .runner = .{ .context = &fake, .run_fn = Fake.run },
        .native_backend = .{ .context = &fake, .get_text_fn = Fake.get },
    };
    try std.testing.expect((try clipboard.readClipboardText(gpa, io, options)) == null);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
    try std.testing.expectEqual(@as(usize, 0), fake.native_calls);

    fake.mode = .replacement;
    fake.calls = 0;
    const decoded = (try clipboard.readClipboardText(gpa, io, options)).?;
    defer gpa.free(decoded);
    try std.testing.expectEqualStrings("\xef\xbf\xbd\x00x", decoded);
    try std.testing.expectEqual(@as(usize, 2), fake.calls);
    try std.testing.expectEqual(@as(usize, 0), fake.native_calls);

    fake.mode = .native_text;
    fake.calls = 0;
    const fallback = (try clipboard.readClipboardText(gpa, io, options)).?;
    defer gpa.free(fallback);
    try std.testing.expectEqualStrings("native text", fallback);
    try std.testing.expectEqual(@as(usize, 4), fake.calls);
    try std.testing.expectEqual(@as(usize, 1), fake.native_calls);
    try std.testing.expect(fake.valid);

    const units = try native.utf8ToUtf16Alloc(gpa, "a\x00\xf0\x9f\xa7\xaa\xf0\x9f\x92");
    defer gpa.free(units);
    try std.testing.expectEqualSlices(u16, &.{ 0x61, 0, 0xd83e, 0xddea, 0xfffd }, units);
    const roundtrip = try native.utf16ToUtf8Alloc(gpa, &.{ 0xd800, 0x61, 0xdc00, 0xd83e, 0xddea });
    defer gpa.free(roundtrip);
    try std.testing.expectEqualStrings("\xef\xbf\xbda\xef\xbf\xbd\xf0\x9f\xa7\xaa", roundtrip);
}

test "native clipboard consumer empty Wayland and WSL preserve owner selection" {
    const Fake = struct {
        wayland_available: bool = true,
        x11_available: bool = true,
        wl_calls: usize = 0,
        x11_calls: usize = 0,
        native_calls: usize = 0,
        windows_calls: usize = 0,
        valid: bool = true,
        path: ?[]u8 = null,
        fn run(raw: *anyopaque, allocator: std.mem.Allocator, _: Io, argv: []const []const u8, timeout_ms: u64, _: ?*const std.process.Environ.Map) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (std.mem.eql(u8, argv[0], "wl-paste")) {
                self.wl_calls += 1;
                self.valid = self.valid and argv.len == 2 and std.mem.eql(u8, argv[1], "--list-types") and timeout_ms == 1000;
                return if (self.wayland_available) try allocator.dupe(u8, "text/plain\n") else null;
            }
            if (std.mem.eql(u8, argv[0], "xclip")) {
                self.x11_calls += 1;
                self.valid = self.valid and argv.len == 6 and std.mem.eql(u8, argv[4], "TARGETS") and timeout_ms == 1000;
                return if (self.x11_available) try allocator.dupe(u8, "text/plain\n") else null;
            }
            if (std.mem.eql(u8, argv[0], "wslpath")) {
                self.windows_calls += 1;
                self.valid = self.valid and argv.len == 3 and timeout_ms == 1000;
                if (self.path) |path| allocator.free(path);
                self.path = try allocator.dupe(u8, argv[2]);
                return try allocator.dupe(u8, "C:\\private\\image.png\n");
            }
            if (std.mem.eql(u8, argv[0], "powershell.exe")) {
                self.windows_calls += 1;
                self.valid = self.valid and argv.len == 4 and timeout_ms == 5000 and
                    std.mem.indexOf(u8, argv[3], "GetImage()") != null;
                return try allocator.dupe(u8, "empty\n");
            }
            self.valid = false;
            return null;
        }
        fn image(raw: ?*anyopaque, _: std.mem.Allocator, _: usize) !native.Read {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.native_calls += 1;
            return .empty;
        }
    };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root_length = try tmp.dir.realPath(io, &path_buffer);
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    try env.put("WAYLAND_DISPLAY", "test");
    try env.put("DISPLAY", ":0");
    var fake: Fake = .{};
    defer if (fake.path) |path| gpa.free(path);
    const options: clipboard.Options = .{
        .platform = .linux, .environ = &env, .temp_dir = path_buffer[0..root_length],
        .runner = .{ .context = &fake, .run_fn = Fake.run },
        .native_backend = .{ .context = &fake, .get_image_fn = Fake.image },
    };
    try std.testing.expect((try clipboard.readClipboardImage(gpa, io, options)) == null);
    try std.testing.expectEqual(@as(usize, 0), fake.x11_calls);
    try std.testing.expectEqual(@as(usize, 0), fake.native_calls);

    fake.wayland_available = false;
    try std.testing.expect((try clipboard.readClipboardImage(gpa, io, options)) == null);
    try std.testing.expectEqual(@as(usize, 1), fake.x11_calls);
    try std.testing.expectEqual(@as(usize, 0), fake.native_calls);

    try env.put("WSL_DISTRO_NAME", "test");
    fake.wayland_available = true;
    fake.x11_calls = 0;
    fake.windows_calls = 0;
    try std.testing.expect((try clipboard.readClipboardImage(gpa, io, options)) == null);
    try std.testing.expectEqual(@as(usize, 0), fake.x11_calls);
    try std.testing.expectEqual(@as(usize, 0), fake.native_calls);
    try std.testing.expectEqual(@as(usize, 2), fake.windows_calls);
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().statFile(io, fake.path.?, .{}));

    fake.wayland_available = false;
    fake.x11_available = false;
    try std.testing.expect((try clipboard.readClipboardImage(gpa, io, options)) == null);
    try std.testing.expectEqual(@as(usize, 1), fake.x11_calls);
    try std.testing.expectEqual(@as(usize, 1), fake.native_calls);
    try std.testing.expect(fake.valid);
}

test "native clipboard consumer native failure and OOM precede copy fallback" {
    const Fake = struct {
        mode: enum { success, ordinary, oom } = .success,
        native_calls: usize = 0,
        command_calls: usize = 0,
        output_calls: usize = 0,
        valid: bool = true,
        fn set(raw: ?*anyopaque, _: std.mem.Allocator, text: []const u8, limit: usize) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.native_calls += 1;
            self.valid = self.valid and std.mem.eql(u8, text, "copy") and limit == native.default_memory_limit;
            return switch (self.mode) {
                .success => true,
                .ordinary => error.NativeClipboardUnavailable,
                .oom => error.OutOfMemory,
            };
        }
        fn run(raw: *anyopaque, _: std.mem.Allocator, _: Io, argv: []const []const u8, input: []const u8, timeout_ms: u64, _: ?*const std.process.Environ.Map) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.command_calls += 1;
            self.valid = self.valid and self.native_calls == 1 and argv.len == 1 and
                std.mem.eql(u8, argv[0], "clip") and std.mem.eql(u8, input, "copy") and timeout_ms == 5000;
            return true;
        }
        fn write(raw: *anyopaque, _: Io, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.output_calls += 1;
            self.valid = self.valid and self.native_calls == 1 and std.mem.eql(u8, bytes, "\x1b]52;c;Y29weQ==\x07");
        }
        fn readOom(_: ?*anyopaque, _: std.mem.Allocator, _: usize) !native.Read {
            return error.OutOfMemory;
        }
    };
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    try env.put("SSH_CONNECTION", "test");
    var fake: Fake = .{};
    const options: clipboard.Options = .{
        .platform = .windows, .environ = &env,
        .native_backend = .{ .context = &fake, .set_text_fn = Fake.set, .get_text_fn = Fake.readOom, .get_image_fn = Fake.readOom },
        .write_runner = .{ .context = &fake, .run_fn = Fake.run },
        .output_writer = .{ .context = &fake, .write_fn = Fake.write },
    };
    const direct = try clipboard.copyText(gpa, io, "copy", options);
    try std.testing.expect(direct.native and direct.osc52);
    try std.testing.expectEqual(@as(usize, 0), fake.command_calls);
    fake.mode = .ordinary;
    fake.native_calls = 0;
    fake.output_calls = 0;
    const fallback = try clipboard.copyText(gpa, io, "copy", options);
    try std.testing.expect(fallback.native and fallback.osc52);
    try std.testing.expectEqual(@as(usize, 1), fake.command_calls);
    fake.mode = .oom;
    fake.native_calls = 0;
    fake.command_calls = 0;
    fake.output_calls = 0;
    try std.testing.expectError(error.OutOfMemory, clipboard.copyText(gpa, io, "copy", options));
    try std.testing.expectEqual(@as(usize, 0), fake.command_calls);
    try std.testing.expectEqual(@as(usize, 0), fake.output_calls);
    try std.testing.expectError(error.OutOfMemory, clipboard.readClipboardText(gpa, io, options));
    try std.testing.expectError(error.OutOfMemory, clipboard.readClipboardImage(gpa, io, options));
    try std.testing.expect(fake.valid);
}

test "native clipboard consumer WSL uses UTF8 file quoting and terminal preference" {
    const text = "R\xc3\xa9sum\xc3\xa9 \xf0\x9f\xa7\xaa\n'";
    const Fake = struct {
        captures: usize = 0,
        outputs: usize = 0,
        valid: bool = true,
        path: ?[]u8 = null,
        fn run(raw: *anyopaque, allocator: std.mem.Allocator, task_io: Io, argv: []const []const u8, timeout_ms: u64, _: ?*const std.process.Environ.Map) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.captures += 1;
            if (std.mem.eql(u8, argv[0], "wslpath")) {
                self.valid = self.valid and argv.len == 3 and timeout_ms == 1000;
                const stored = try Io.Dir.cwd().readFileAlloc(task_io, argv[2], allocator, .limited(1024));
                defer allocator.free(stored);
                self.valid = self.valid and std.mem.eql(u8, stored, text);
                self.path = try allocator.dupe(u8, argv[2]);
                return try allocator.dupe(u8, " C:\\O'Brien\\clip.txt\r\n");
            }
            self.valid = self.valid and std.mem.eql(u8, argv[0], "powershell.exe") and argv.len == 4 and timeout_ms == 5000 and
                std.mem.eql(u8, argv[1], "-NoProfile") and std.mem.eql(u8, argv[2], "-Command") and
                std.mem.indexOf(u8, argv[3], "ReadAllText('C:\\O''Brien\\clip.txt', [System.Text.Encoding]::UTF8)") != null;
            return try allocator.alloc(u8, 0);
        }
        fn write(raw: *anyopaque, _: Io, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.outputs += 1;
            self.valid = self.valid and std.mem.startsWith(u8, bytes, "\x1b]52;c;");
        }
    };
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root_length = try tmp.dir.realPath(io, &path_buffer);
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    try env.put("WSL_DISTRO_NAME", "test");
    var fake: Fake = .{};
    defer if (fake.path) |path| gpa.free(path);
    var options: clipboard.Options = .{
        .platform = .linux, .environ = &env, .temp_dir = path_buffer[0..root_length],
        .native_backend = native.unavailable,
        .runner = .{ .context = &fake, .run_fn = Fake.run },
        .output_writer = .{ .context = &fake, .write_fn = Fake.write },
        .osc52_fallback = false,
    };
    const copied = try clipboard.copyText(gpa, io, text, options);
    try std.testing.expect(copied.native and !copied.osc52);
    try std.testing.expectEqual(@as(usize, 2), fake.captures);
    try std.testing.expectEqual(@as(usize, 0), fake.outputs);
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().statFile(io, fake.path.?, .{}));

    try env.put("WT_SESSION", "test");
    options.osc52_fallback = true;
    fake.captures = 0;
    const terminal = try clipboard.copyText(gpa, io, text, options);
    try std.testing.expect(!terminal.native and terminal.osc52);
    try std.testing.expectEqual(@as(usize, 0), fake.captures);
    try std.testing.expectEqual(@as(usize, 1), fake.outputs);
    try std.testing.expect(fake.valid);
}

test "native clipboard consumer advertised MIME and codec errors retain source behavior" {
    const Fake = struct {
        native_bytes: []const u8 = "GIFbroken",
        mode: enum { value, ordinary, oom } = .value,
        native_calls: usize = 0,
        codec_calls: usize = 0,
        valid: bool = true,
        fn image(raw: ?*anyopaque, allocator: std.mem.Allocator, _: usize) !native.Read {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.native_calls += 1;
            return .{ .value = try allocator.dupe(u8, self.native_bytes) };
        }
        fn run(_: *anyopaque, allocator: std.mem.Allocator, _: Io, argv: []const []const u8, _: u64, _: ?*const std.process.Environ.Map) !?[]u8 {
            if (argv.len == 2 and std.mem.eql(u8, argv[1], "--list-types")) return try allocator.dupe(u8, "image/png\n");
            return try allocator.dupe(u8, "advertised PNG bytes without dimensions");
        }
        fn convert(raw: ?*anyopaque, allocator: std.mem.Allocator, bytes: []const u8, limit: usize) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.codec_calls += 1;
            self.valid = self.valid and limit == native.default_memory_limit and std.mem.eql(u8, bytes, self.native_bytes);
            return switch (self.mode) {
                .value => try allocator.dupe(u8, "converted PNG"),
                .ordinary => error.ImageCodecFailure,
                .oom => error.OutOfMemory,
            };
        }
    };
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    try env.put("WAYLAND_DISPLAY", "test");
    var fake: Fake = .{};
    var options: clipboard.Options = .{
        .platform = .linux, .environ = &env,
        .runner = .{ .context = &fake, .run_fn = Fake.run },
        .native_backend = .{ .context = &fake, .get_image_fn = Fake.image },
        .png_converter = .{ .context = &fake, .convert_fn = Fake.convert },
    };
    var advertised = (try clipboard.readClipboardImage(gpa, io, options)).?;
    defer advertised.deinit(gpa);
    try std.testing.expectEqualStrings("image/png", advertised.mime_type);
    try std.testing.expectEqualStrings("advertised PNG bytes without dimensions", advertised.bytes);
    try std.testing.expectEqual(@as(usize, 0), fake.codec_calls);
    try std.testing.expectEqual(@as(usize, 0), fake.native_calls);

    options.platform = .windows;
    var converted = (try clipboard.readClipboardImage(gpa, io, options)).?;
    defer converted.deinit(gpa);
    try std.testing.expectEqualStrings("image/png", converted.mime_type);
    try std.testing.expectEqualStrings("converted PNG", converted.bytes);
    try std.testing.expectEqual(@as(usize, 1), fake.codec_calls);
    fake.native_bytes = "GIF89a";
    var gif = (try clipboard.readClipboardImage(gpa, io, options)).?;
    defer gif.deinit(gpa);
    try std.testing.expectEqualStrings("image/gif", gif.mime_type);
    try std.testing.expectEqual(@as(usize, 1), fake.codec_calls);

    fake.native_bytes = "GIFbroken";
    fake.mode = .ordinary;
    try std.testing.expect((try clipboard.readClipboardImage(gpa, io, options)) == null);
    fake.mode = .oom;
    try std.testing.expectError(error.OutOfMemory, clipboard.readClipboardImage(gpa, io, options));
    const before = fake.codec_calls;
    options.native_memory_limit = 0;
    try std.testing.expectError(error.OutOfMemory, clipboard.readClipboardImage(gpa, io, options));
    try std.testing.expectEqual(before, fake.codec_calls);
    try std.testing.expect(fake.valid);
}

test "native clipboard consumer linked Photon enforces explicit allocation budget" {
    const Fake = struct {
        fn image(_: ?*anyopaque, allocator: std.mem.Allocator, _: usize) !native.Read {
            return .{ .value = try allocator.dupe(u8, "unsupported nonempty image") };
        }
    };
    try std.testing.expectError(error.OutOfMemory, clipboard.readClipboardImage(gpa, io, .{
        .platform = .windows,
        .native_backend = .{ .get_image_fn = Fake.image },
        .native_memory_limit = 1,
    }));
}

extern fn pi_js_native_memory_owners() usize;

fn expectNativeReadOom(outcome: anyerror!native.Read) !void {
    if (outcome) |read| {
        switch (read) {
            .value => |bytes| gpa.free(bytes),
            .unavailable, .empty => {},
        }
        // Never format an unexpected successful real clipboard value.
        return error.TestUnexpectedResult;
    } else |err| {
        if (err != error.OutOfMemory) return error.TestUnexpectedError;
    }
}

test "native clipboard consumer standalone owner retires read-only jobs and budget failures" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const backend: native.Backend = .{};
    const before = pi_js_native_memory_owners();
    try expectNativeReadOom(backend.getText(gpa, 0));
    try std.testing.expectEqual(before, pi_js_native_memory_owners());
    try expectNativeReadOom(backend.getImage(gpa, 0));
    try std.testing.expectEqual(before, pi_js_native_memory_owners());
    inline for (.{ false, true }) |image| {
        const outcome = if (image) backend.getImage(gpa, native.default_memory_limit)
            else backend.getText(gpa, native.default_memory_limit);
        if (outcome) |read| {
            switch (read) {
                .value => |bytes| {
                    defer gpa.free(bytes);
                    try std.testing.expect(bytes.len > 0);
                    if (!image) try std.testing.expect(std.unicode.utf8ValidateSlice(bytes));
                },
                .unavailable, .empty => {},
            }
        } else |err| switch (err) {
            error.OutOfMemory, error.NativeClipboardUnavailable, error.NativeClipboardQueueFailed, error.NativeClipboardFailed => {},
            else => return err,
        }
        try std.testing.expectEqual(before, pi_js_native_memory_owners());
    }
}

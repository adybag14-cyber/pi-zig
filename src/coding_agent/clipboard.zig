//! Clipboard integration for the native interactive editor.
//!
//! Uses the pinned Pi command order, including empty versus unavailable image
//! results and the WSL UTF8-file route. The linked Win32 helper shares the same
//! C worker implementation as TUI, with a standalone per-operation owner.
const std = @import("std");
const builtin = @import("builtin");
const image_mime = @import("../ai/images.zig");
const photon = @import("../ai/photon_native.zig");
pub const native_clipboard = @import("native_clipboard.zig");
const osc52 = @import("../tui/osc52.zig");
const file_permissions = @import("../file_permissions.zig");
const Io = std.Io;

pub const max_clipboard_bytes: usize = 50 * 1024 * 1024;
pub const list_timeout_ms: u64 = 1_000;
pub const read_timeout_ms: u64 = 3_000;
pub const text_read_timeout_ms: u64 = 5_000;
pub const powershell_timeout_ms: u64 = 5_000;
pub const write_timeout_ms: u64 = 5_000;

pub const Platform = enum { linux, macos, windows, other };

pub const Commands = struct {
    wl_paste: []const u8 = "wl-paste",
    xclip: []const u8 = "xclip",
    xsel: []const u8 = "xsel",
    pngpaste: []const u8 = "pngpaste",
    pbpaste: []const u8 = "pbpaste",
    pbcopy: []const u8 = "pbcopy",
    osascript: []const u8 = "osascript",
    powershell: []const u8 = "powershell.exe",
    clip: []const u8 = "clip",
    wslpath: []const u8 = "wslpath",
    termux_clipboard_get: []const u8 = "termux-clipboard-get",
    termux_clipboard_set: []const u8 = "termux-clipboard-set",
    wl_copy: []const u8 = "wl-copy",
};

pub const CommandRunner = struct {
    context: *anyopaque,
    run_fn: *const fn (
        context: *anyopaque,
        gpa: std.mem.Allocator,
        io: Io,
        argv: []const []const u8,
        timeout_ms: u64,
        environ: ?*const std.process.Environ.Map,
    ) anyerror!?[]u8,

    pub fn run(
        self: CommandRunner,
        gpa: std.mem.Allocator,
        io: Io,
        argv: []const []const u8,
        timeout_ms: u64,
        environ: ?*const std.process.Environ.Map,
    ) !?[]u8 {
        return self.run_fn(self.context, gpa, io, argv, timeout_ms, environ);
    }
};

pub const WriteRunner = struct {
    context: *anyopaque,
    run_fn: *const fn (
        context: *anyopaque,
        gpa: std.mem.Allocator,
        io: Io,
        argv: []const []const u8,
        input: []const u8,
        timeout_ms: u64,
        environ: ?*const std.process.Environ.Map,
    ) anyerror!bool,

    pub fn run(
        self: WriteRunner,
        gpa: std.mem.Allocator,
        io: Io,
        argv: []const []const u8,
        input: []const u8,
        timeout_ms: u64,
        environ: ?*const std.process.Environ.Map,
    ) !bool {
        return self.run_fn(self.context, gpa, io, argv, input, timeout_ms, environ);
    }
};

pub const OutputWriter = struct {
    context: *anyopaque,
    write_fn: *const fn (context: *anyopaque, io: Io, bytes: []const u8) anyerror!void,

    pub fn write(self: OutputWriter, io: Io, bytes: []const u8) !void {
        return self.write_fn(self.context, io, bytes);
    }
};

/// Conversion returns a separately owned output, or null for an ordinary
/// codec failure. A genuine allocation failure must remain OutOfMemory.
pub const PngConverter = struct {
    context: ?*anyopaque = null,
    convert_fn: *const fn (?*anyopaque, std.mem.Allocator, []const u8, usize) anyerror!?[]u8,

    pub fn convert(self: PngConverter, gpa: std.mem.Allocator, bytes: []const u8, memory_limit: usize) !?[]u8 {
        return self.convert_fn(self.context, gpa, bytes, memory_limit);
    }
};

pub const Options = struct {
    environ: ?*const std.process.Environ.Map = null,
    platform: ?Platform = null,
    commands: Commands = .{},
    temp_dir: ?[]const u8 = null,
    runner: ?CommandRunner = null,
    write_runner: ?WriteRunner = null,
    output_writer: ?OutputWriter = null,
    osc52_fallback: bool = true,
    native_backend: native_clipboard.Backend = .{},
    png_converter: ?PngConverter = null,
    /// Matches Engine.Options' existing 64 MiB default. Each C worker owner
    /// accounts its job, copied data and stack. After its join/destruction,
    /// Photon uses the same explicit limit for its separate tracked guard.
    /// Host conversion/returned buffers remain owned by gpa; this is neither
    /// a combined concurrent budget nor a process-wide memory limit.
    native_memory_limit: usize = native_clipboard.default_memory_limit,
};

pub const CopyResult = struct {
    native: bool = false,
    osc52: bool = false,
};

pub const ClipboardImage = struct {
    bytes: []u8,
    mime_type: []const u8,

    pub fn deinit(self: *ClipboardImage, gpa: std.mem.Allocator) void {
        gpa.free(self.bytes);
        self.* = undefined;
    }
};

pub const Paste = union(enum) {
    image: ClipboardImage,
    text: []u8,

    pub fn deinit(self: *Paste, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .image => |*image| image.deinit(gpa),
            .text => |text| gpa.free(text),
        }
        self.* = undefined;
    }
};

/// Temporary clipboard attachments are retained until the interactive process
/// exits. This mirrors the original path-based paste behavior while ensuring
/// private files are cleaned deterministically on normal shutdown.
pub const TempStore = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: ?*const std.process.Environ.Map,
    temp_dir: ?[]const u8 = null,
    paths: std.ArrayList([]u8) = .empty,

    pub fn init(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map) TempStore {
        return .{ .gpa = gpa, .io = io, .environ = environ };
    }

    pub fn deinit(self: *TempStore) void {
        for (self.paths.items) |path| {
            std.Io.Dir.cwd().deleteFile(self.io, path) catch {};
            self.gpa.free(path);
        }
        self.paths.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn saveImage(self: *TempStore, image: ClipboardImage) ![]const u8 {
        const path = try temporaryPath(self.gpa, self.io, self.environ, self.temp_dir, extensionForMime(image.mime_type));
        errdefer self.gpa.free(path);
        const file = try std.Io.Dir.cwd().createFile(self.io, path, .{
            .truncate = true,
            .exclusive = true,
            .permissions = file_permissions.privateFile(),
        });
        errdefer std.Io.Dir.cwd().deleteFile(self.io, path) catch {};
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, image.bytes);
        try self.paths.append(self.gpa, path);
        return path;
    }
};

pub fn copyText(gpa: std.mem.Allocator, io: Io, text: []const u8, options: Options) !CopyResult {
    if (text.len > max_clipboard_bytes) return error.ClipboardTooLarge;
    const platform = options.platform orelse nativePlatform();
    const environ = options.environ;
    var result: CopyResult = .{};
    result.native = try copyNative(gpa, io, text, options);
    var copied = result.native;

    if (!copied and platform == .linux and try isWsl(gpa, io, environ)) {
        if (options.osc52_fallback and envHas(environ, "WT_SESSION"))
            result.osc52 = try emitOsc52(gpa, io, text, options);
        if (result.osc52) {
            copied = true;
        } else {
            result.native = copyViaWindowsClipboard(gpa, io, text, options) catch |err| blk: {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                break :blk false;
            };
            copied = result.native;
        }
    }

    const headless = platform == .linux and !envHas(environ, "DISPLAY") and
        !envHas(environ, "WAYLAND_DISPLAY") and !envHas(environ, "TERMUX_VERSION");
    var oversized = false;
    if (options.osc52_fallback and !result.osc52 and (isRemoteSession(environ) or (!copied and headless))) {
        result.osc52 = try emitOsc52(gpa, io, text, options);
        if (result.osc52) copied = true else oversized = true;
    }
    if (copied) return result;
    if (oversized) return error.ClipboardOsc52TooLarge;
    if (envHas(environ, "TERMUX_VERSION")) return error.ClipboardTermuxUnavailable;
    if (platform == .linux) {
        if (envHas(environ, "WAYLAND_DISPLAY")) return error.ClipboardWaylandUnavailable;
        if (envHas(environ, "DISPLAY")) return error.ClipboardX11Unavailable;
    }
    return error.ClipboardUnavailable;
}

pub fn isRemoteSession(environ: ?*const std.process.Environ.Map) bool {
    return envHas(environ, "SSH_CONNECTION") or envHas(environ, "SSH_CLIENT") or envHas(environ, "MOSH_CONNECTION") or
        std.mem.eql(u8, envGet(environ, "PI_CLIPBOARD_OSC52") orelse "", "1");
}

fn copyNative(gpa: std.mem.Allocator, io: Io, text: []const u8, options: Options) !bool {
    const platform = options.platform orelse nativePlatform();
    if (platform != .linux) {
        const copied = options.native_backend.setText(gpa, text, options.native_memory_limit) catch |err| blk: {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            break :blk false;
        };
        if (copied) return true;
    }
    switch (platform) {
        .macos => return tryWrite(gpa, io, &.{options.commands.pbcopy}, text, options),
        .windows => return tryWrite(gpa, io, &.{options.commands.clip}, text, options),
        .linux, .other => {
            if (envHas(options.environ, "TERMUX_VERSION") and
                try tryWrite(gpa, io, &.{options.commands.termux_clipboard_set}, text, options)) return true;
            if (envHas(options.environ, "WAYLAND_DISPLAY") and
                try tryWrite(gpa, io, &.{options.commands.wl_copy}, text, options)) return true;
            if (envHas(options.environ, "DISPLAY")) {
                if (try tryWrite(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard" }, text, options)) return true;
                if (try tryWrite(gpa, io, &.{ options.commands.xsel, "--clipboard", "--input" }, text, options)) return true;
            }
            return false;
        },
    }
}

fn tryWrite(gpa: std.mem.Allocator, io: Io, argv: []const []const u8, input: []const u8, options: Options) !bool {
    return writeCommand(gpa, io, argv, input, write_timeout_ms, options) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
}

fn copyViaWindowsClipboard(gpa: std.mem.Allocator, io: Io, text: []const u8, options: Options) !bool {
    var temporary = try PrivateFile.create(gpa, io, options, "txt");
    defer temporary.deinit();
    try temporary.file.?.writeStreamingAll(io, text);
    temporary.close();
    const target = try windowsPath(gpa, io, temporary.path, options) orelse return false;
    defer gpa.free(target);
    const quoted = try quotePowerShellPath(gpa, target);
    defer gpa.free(quoted);
    const script = try std.fmt.allocPrint(gpa,
        "Set-Clipboard -Value ([System.IO.File]::ReadAllText('{s}', [System.Text.Encoding]::UTF8))", .{quoted});
    defer gpa.free(script);
    const output = try capture(gpa, io, &.{ options.commands.powershell, "-NoProfile", "-Command", script }, powershell_timeout_ms, options) orelse return false;
    defer gpa.free(output);
    return true;
}

fn writeCommand(
    gpa: std.mem.Allocator,
    io: Io,
    argv: []const []const u8,
    input: []const u8,
    timeout_ms: u64,
    options: Options,
) !bool {
    if (options.write_runner) |runner| return runner.run(gpa, io, argv, input, timeout_ms, options.environ);
    return runWrite(gpa, io, argv, input, timeout_ms, options);
}

fn emitOsc52(gpa: std.mem.Allocator, io: Io, text: []const u8, options: Options) !bool {
    const sequence = try osc52.sequenceAlloc(gpa, text) orelse return false;
    defer gpa.free(sequence);
    if (options.output_writer) |writer| {
        try writer.write(io, sequence);
    } else {
        try std.Io.File.stdout().writeStreamingAll(io, sequence);
    }
    return true;
}

fn runWrite(
    gpa: std.mem.Allocator,
    io: Io,
    argv: []const []const u8,
    input: []const u8,
    timeout_ms: u64,
    options: Options,
) !bool {
    var temporary = try PrivateFile.create(gpa, io, options, "txt");
    defer temporary.deinit();
    try temporary.file.?.writeStreamingAll(io, input);
    temporary.close();

    const stdin_file = try std.Io.Dir.cwd().openFile(io, temporary.path, .{});
    defer stdin_file.close(io);
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .environ_map = options.environ,
        .stdin = .{ .file = stdin_file },
        .stdout = .ignore,
        .stderr = .ignore,
        .pgid = if (builtin.os.tag == .windows) null else 0,
        .create_no_window = builtin.os.tag == .windows,
    });
    defer child.kill(io);
    if (comptime builtin.os.tag == .windows) {
        const term = try waitWindowsProcess(&child, io, commandDeadline(io, timeout_ms)) orelse return false;
        return successfulTerm(term);
    }
    return waitLegacyProcess(&child, io, timeout_ms);
}

/// Existing POSIX process mechanics are retained in this Windows port. Their
/// separate process-owner qualification is not inferred from the Win32 path.
fn waitLegacyProcess(child: *std.process.Child, io: Io, timeout_ms: u64) !bool {
    const WaitState = struct {
        child: *std.process.Child,
        io: Io,
        done: std.atomic.Value(bool) = .init(false),
        term: ?std.process.Child.Term = null,
    };
    var state = WaitState{ .child = child, .io = io };
    const waiter = std.Thread.spawn(.{}, struct {
        fn run(s: *WaitState) void {
            defer s.done.store(true, .release);
            s.term = s.child.wait(s.io) catch null;
        }
    }.run, .{&state}) catch |err| {
        child.kill(io);
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };

    var elapsed: u64 = 0;
    var timed_out = false;
    while (!state.done.load(.acquire)) {
        if (elapsed >= timeout_ms) {
            forceKillProcess(child);
            timed_out = true;
            break;
        }
        const step = @min(@as(u64, 25), timeout_ms - elapsed);
        const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(@intCast(step)), .clock = .real } };
        timeout.sleep(io) catch {};
        elapsed += step;
    }
    waiter.join();
    if (timed_out) return false;
    const term = state.term orelse return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn commandDeadline(io: Io, timeout_ms: u64) Io.Clock.Timestamp {
    const duration_ms: i64 = @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    return .fromNow(io, .{ .raw = .fromMilliseconds(duration_ms), .clock = .awake });
}

fn successfulTerm(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

/// Pinned Windows Child.wait preserves its live handles on cancellation.
/// Select cancellation joins both tasks before the caller may kill or retire
/// the child. The POSIX implementation has different cancellation ownership.
fn waitWindowsProcess(child: *std.process.Child, io: Io, deadline: Io.Clock.Timestamp) !?std.process.Child.Term {
    const Event = union(enum) {
        exited: std.process.Child.WaitError!std.process.Child.Term,
        deadline: Io.Cancelable!void,
    };
    const Tasks = struct {
        fn wait(owned: *std.process.Child, task_io: Io) std.process.Child.WaitError!std.process.Child.Term {
            return owned.wait(task_io);
        }
        fn timeout(task_io: Io, end: Io.Clock.Timestamp) Io.Cancelable!void {
            return end.wait(task_io);
        }
    };
    var buffer: [2]Event = undefined;
    var selected: Io.Select(Event) = .init(io, &buffer);
    defer selected.cancelDiscard();
    try selected.concurrent(.exited, Tasks.wait, .{ child, io });
    try selected.concurrent(.deadline, Tasks.timeout, .{ io, deadline });
    const event = try selected.await();
    selected.cancelDiscard();
    return switch (event) {
        .exited => |term| try term,
        .deadline => |elapsed| blk: {
            try elapsed;
            break :blk null;
        },
    };
}

fn forceKillProcess(child: *std.process.Child) void {
    const id = child.id orelse return;
    if (builtin.os.tag == .windows) {
        _ = std.os.windows.ntdll.NtTerminateProcess(id, @enumFromInt(1));
    } else {
        std.posix.kill(-id, std.posix.SIG.KILL) catch {
            std.posix.kill(id, std.posix.SIG.KILL) catch {};
        };
    }
}

pub fn readPaste(gpa: std.mem.Allocator, io: Io, options: Options) !?Paste {
    if (try readClipboardImage(gpa, io, options)) |image| return .{ .image = image };
    if (try readClipboardText(gpa, io, options)) |text| return .{ .text = text };
    return null;
}

const RawImage = struct {
    bytes: []u8,
    /// Static supported MIME, or null when the bytes need Photon conversion.
    mime_type: ?[]const u8,
};
const ImageAttempt = union(enum) { unavailable, empty, image: RawImage };

pub fn readClipboardImage(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    if (envHas(options.environ, "TERMUX_VERSION")) return null;
    var attempt: ImageAttempt = .unavailable;
    if ((options.platform orelse nativePlatform()) == .linux) {
        const wsl = try isWsl(gpa, io, options.environ);
        if (isWaylandSession(options.environ) or wsl)
            attempt = try readWlPasteImage(gpa, io, options);
        if (attempt == .unavailable) attempt = try readXclipImage(gpa, io, options);
        if (attempt != .image and wsl) {
            // A Windows no-image result preserves Linux's empty/unavailable
            // state, so empty Wayland contents never expose stale X11 data.
            if (try readPowerShellImage(gpa, io, options)) |image|
                attempt = .{ .image = .{ .bytes = image.bytes, .mime_type = "image/png" } };
        }
        if (attempt == .unavailable) attempt = try readNativeImage(gpa, options);
    } else {
        attempt = try readNativeImage(gpa, options);
    }
    const image = switch (attempt) {
        .unavailable, .empty => return null,
        .image => |value| value,
    };
    if (image.mime_type) |mime| return .{ .bytes = image.bytes, .mime_type = mime };
    defer gpa.free(image.bytes);
    const converted = try convertToPng(gpa, image.bytes, options) orelse return null;
    if (converted.len == 0) {
        gpa.free(converted);
        return null;
    }
    return .{ .bytes = converted, .mime_type = "image/png" };
}

pub fn readClipboardText(gpa: std.mem.Allocator, io: Io, options: Options) !?[]u8 {
    if (envHas(options.environ, "TERMUX_VERSION")) {
        if (try capture(gpa, io, &.{options.commands.termux_clipboard_get}, text_read_timeout_ms, options)) |bytes|
            return textResult(gpa, bytes);
    }
    if ((options.platform orelse nativePlatform()) == .linux) {
        if (envHas(options.environ, "WAYLAND_DISPLAY")) {
            if (try capture(gpa, io, &.{ options.commands.wl_paste, "--no-newline", "--type", "text" }, text_read_timeout_ms, options)) |bytes|
                return textResult(gpa, bytes);
        }
        if (envHas(options.environ, "DISPLAY")) {
            if (try capture(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard", "-out" }, text_read_timeout_ms, options)) |bytes|
                return textResult(gpa, bytes);
            if (try capture(gpa, io, &.{ options.commands.xsel, "--clipboard", "--output" }, text_read_timeout_ms, options)) |bytes|
                return textResult(gpa, bytes);
        }
    }
    const native = options.native_backend.getText(gpa, options.native_memory_limit) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return switch (native) {
        .unavailable, .empty => null,
        .value => |bytes| try textResult(gpa, bytes),
    };
}

fn textResult(gpa: std.mem.Allocator, bytes: []u8) !?[]u8 {
    if (bytes.len == 0) {
        gpa.free(bytes);
        return null;
    }
    return try decodeOwnedUtf8(gpa, bytes);
}

fn decodeOwnedUtf8(gpa: std.mem.Allocator, bytes: []u8) ![]u8 {
    if (std.unicode.utf8ValidateSlice(bytes)) return bytes;
    defer gpa.free(bytes);
    return native_clipboard.decodeUtf8Alloc(gpa, bytes);
}

fn readWlPasteImage(gpa: std.mem.Allocator, io: Io, options: Options) !ImageAttempt {
    const raw = try capture(gpa, io, &.{ options.commands.wl_paste, "--list-types" }, list_timeout_ms, options) orelse return .unavailable;
    const list = try decodeOwnedUtf8(gpa, raw);
    defer gpa.free(list);
    const selected = selectPreferredImageMimeType(list) orelse return .empty;
    const bytes = try capture(gpa, io, &.{ options.commands.wl_paste, "--type", selected, "--no-newline" }, read_timeout_ms, options) orelse return .unavailable;
    return advertisedImage(gpa, bytes, selected);
}

fn readXclipImage(gpa: std.mem.Allocator, io: Io, options: Options) !ImageAttempt {
    const raw = try capture(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard", "-t", "TARGETS", "-o" }, list_timeout_ms, options) orelse return .unavailable;
    const targets = try decodeOwnedUtf8(gpa, raw);
    defer gpa.free(targets);
    const preferred = selectPreferredImageMimeType(targets) orelse return .empty;
    const bytes = try capture(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard", "-t", preferred, "-o" }, read_timeout_ms, options) orelse return .unavailable;
    return advertisedImage(gpa, bytes, preferred);
}

fn advertisedImage(gpa: std.mem.Allocator, bytes: []u8, mime: []const u8) ImageAttempt {
    if (bytes.len == 0) {
        gpa.free(bytes);
        return .empty;
    }
    // The source trusts a supported advertised MIME without dimensions or a
    // second magic-byte check. Unsupported types share the linked PNG codec.
    return .{ .image = .{ .bytes = bytes, .mime_type = supportedMime(mime) } };
}

fn readNativeImage(gpa: std.mem.Allocator, options: Options) !ImageAttempt {
    // Unlike readClipboardText, the original native image call can reject.
    const native = try options.native_backend.getImage(gpa, options.native_memory_limit);
    return switch (native) {
        .unavailable => .unavailable,
        .empty => .empty,
        .value => |bytes| blk: {
            if (bytes.len == 0) {
                gpa.free(bytes);
                break :blk .empty;
            }
            const detected = detectNativeMime(bytes);
            break :blk .{ .image = .{ .bytes = bytes, .mime_type = if (detected) |mime| supportedMime(mime) else null } };
        },
    };
}

fn detectNativeMime(bytes: []const u8) ?[]const u8 {
    // The shared sniffer accepts a broader GIF prefix; the pinned clipboard
    // target accepts only these two actual signatures.
    if (std.mem.startsWith(u8, bytes, "GIF") and
        !std.mem.startsWith(u8, bytes, "GIF87a") and !std.mem.startsWith(u8, bytes, "GIF89a")) return null;
    return image_mime.detectSupportedMime(bytes);
}

fn supportedMime(mime: []const u8) ?[]const u8 {
    const base = baseMime(mime);
    inline for (.{ "image/png", "image/jpeg", "image/webp", "image/gif" }) |candidate|
        if (std.ascii.eqlIgnoreCase(base, candidate)) return candidate;
    return null;
}

fn convertToPng(gpa: std.mem.Allocator, bytes: []const u8, options: Options) !?[]u8 {
    // Photon uses zero to mean unlimited; never turn an explicit zero owner
    // budget into an unlimited codec operation.
    if (options.native_memory_limit == 0) return error.OutOfMemory;
    if (options.png_converter) |converter| {
        return converter.convert(gpa, bytes, options.native_memory_limit) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
    }
    // A native clipboard read has already destroyed and joined its C job.
    // Photon accounts its own tracked codec graph under a sequential limit;
    // input and escaped output remain separately owned gpa buffers.
    const converted = photon.transform(gpa, .{ .encoded = bytes }, .{
        .format = .png,
        .memory_limit = options.native_memory_limit,
    }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return converted.bytes;
}

fn readPowerShellImage(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    return readPowerShellImageInner(gpa, io, options) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
}

fn readPowerShellImageInner(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    var temporary = try PrivateFile.create(gpa, io, options, "png");
    defer temporary.deinit();
    temporary.close();
    const target = try windowsPath(gpa, io, temporary.path, options) orelse return null;
    defer gpa.free(target);
    const quoted = try quotePowerShellPath(gpa, target);
    defer gpa.free(quoted);
    const script = try std.fmt.allocPrint(gpa,
        "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; " ++
        "$path = '{s}'; $img = [System.Windows.Forms.Clipboard]::GetImage(); " ++
        "if ($img) {{ try {{ $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); Write-Output 'ok' }} " ++
        "finally {{ $img.Dispose() }} }} else {{ Write-Output 'empty' }}", .{quoted});
    defer gpa.free(script);
    const raw = try capture(gpa, io, &.{ options.commands.powershell, "-NoProfile", "-Command", script }, powershell_timeout_ms, options) orelse return null;
    const output = try decodeOwnedUtf8(gpa, raw);
    defer gpa.free(output);
    if (!std.mem.eql(u8, trimText(output), "ok")) return null;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, temporary.path, gpa, .limited(max_clipboard_bytes));
    if (bytes.len == 0) {
        gpa.free(bytes);
        return null;
    }
    return .{ .bytes = bytes, .mime_type = "image/png" };
}

fn windowsPath(gpa: std.mem.Allocator, io: Io, path: []const u8, options: Options) !?[]u8 {
    const raw = try capture(gpa, io, &.{ options.commands.wslpath, "-w", path }, list_timeout_ms, options) orelse return null;
    const decoded = try decodeOwnedUtf8(gpa, raw);
    defer gpa.free(decoded);
    const trimmed = trimText(decoded);
    if (trimmed.len == 0) return null;
    return try gpa.dupe(u8, trimmed);
}

fn quotePowerShellPath(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (path) |byte| {
        try out.append(gpa, byte);
        if (byte == '\'') try out.append(gpa, '\'');
    }
    return out.toOwnedSlice(gpa);
}

/// Input is newline-separated MIME targets. Returned slices borrow raw.
pub fn selectPreferredImageMimeType(raw: []const u8) ?[]const u8 {
    const preferred = [_][]const u8{ "image/png", "image/jpeg", "image/webp", "image/gif" };
    for (preferred) |candidate| {
        var lines = std.mem.splitScalar(u8, raw, '\n');
        while (lines.next()) |line_raw| {
            const line = trimText(line_raw);
            if (std.ascii.eqlIgnoreCase(baseMime(line), candidate)) return line;
        }
    }
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line_raw| {
        const line = trimText(line_raw);
        if (std.ascii.startsWithIgnoreCase(baseMime(line), "image/")) return line;
    }
    return null;
}

fn baseMime(value: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, value, ';') orelse value.len;
    return trimText(value[0..end]);
}

/// ECMAScript trim whitespace, applied after Buffer-compatible UTF8 decoding.
fn trimText(value: []const u8) []const u8 {
    const whitespace = [_][]const u8{
        " ", "\t", "\n", "\r", "\x0b", "\x0c", "\xc2\xa0", "\xe1\x9a\x80",
        "\xe2\x80\x80", "\xe2\x80\x81", "\xe2\x80\x82", "\xe2\x80\x83",
        "\xe2\x80\x84", "\xe2\x80\x85", "\xe2\x80\x86", "\xe2\x80\x87",
        "\xe2\x80\x88", "\xe2\x80\x89", "\xe2\x80\x8a", "\xe2\x80\xa8",
        "\xe2\x80\xa9", "\xe2\x80\xaf", "\xe2\x81\x9f", "\xe3\x80\x80", "\xef\xbb\xbf",
    };
    var trimmed = value;
    leading: while (trimmed.len != 0) {
        for (whitespace) |item| if (std.mem.startsWith(u8, trimmed, item)) {
            trimmed = trimmed[item.len..];
            continue :leading;
        };
        break;
    }
    trailing: while (trimmed.len != 0) {
        for (whitespace) |item| if (std.mem.endsWith(u8, trimmed, item)) {
            trimmed = trimmed[0 .. trimmed.len - item.len];
            continue :trailing;
        };
        break;
    }
    return trimmed;
}

pub fn formatAttachmentReference(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("@\"");
    for (path) |byte| switch (byte) {
        '"' => try out.writer.writeAll("\\\""),
        else => try out.writer.writeByte(byte),
    };
    try out.writer.writeByte('"');
    return out.toOwnedSlice();
}

fn extensionForMime(mime: []const u8) []const u8 {
    if (std.mem.eql(u8, mime, "image/jpeg")) return "jpg";
    if (std.mem.eql(u8, mime, "image/webp")) return "webp";
    if (std.mem.eql(u8, mime, "image/gif")) return "gif";
    if (std.mem.eql(u8, mime, "image/bmp")) return "bmp";
    return "png";
}

fn nativePlatform() Platform {
    return switch (builtin.os.tag) {
        .linux => .linux,
        .macos => .macos,
        .windows => .windows,
        else => .other,
    };
}

pub fn isWaylandSession(environ: ?*const std.process.Environ.Map) bool {
    return envHas(environ, "WAYLAND_DISPLAY") or
        std.mem.eql(u8, envGet(environ, "XDG_SESSION_TYPE") orelse "", "wayland");
}

fn isWsl(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map) !bool {
    if (envHas(environ, "WSL_DISTRO_NAME") or envHas(environ, "WSLENV")) return true;
    const release = std.Io.Dir.cwd().readFileAlloc(io, "/proc/version", gpa, .limited(64 * 1024)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    defer gpa.free(release);
    return std.ascii.indexOfIgnoreCase(release, "microsoft") != null or std.ascii.indexOfIgnoreCase(release, "wsl") != null;
}

fn envGet(environ: ?*const std.process.Environ.Map, key: []const u8) ?[]const u8 {
    return if (environ) |env| env.get(key) else null;
}

fn envHas(environ: ?*const std.process.Environ.Map, key: []const u8) bool {
    return if (envGet(environ, key)) |value| value.len > 0 else false;
}

fn capture(
    gpa: std.mem.Allocator,
    io: Io,
    argv: []const []const u8,
    timeout_ms: u64,
    options: Options,
) !?[]u8 {
    const outcome = if (options.runner) |runner|
        runner.run(gpa, io, argv, timeout_ms, options.environ)
    else if (comptime builtin.os.tag == .windows)
        runCaptureWindows(gpa, io, argv, timeout_ms, options.environ)
    else
        runCaptureLegacy(gpa, io, argv, timeout_ms, options.environ);
    return outcome catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
}

fn runCaptureWindows(
    gpa: std.mem.Allocator,
    io: Io,
    argv: []const []const u8,
    timeout_ms: u64,
    environ: ?*const std.process.Environ.Map,
) !?[]u8 {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .ignore,
        .environ_map = environ,
        .create_no_window = true,
    });
    defer child.kill(io);
    const deadline = commandDeadline(io, timeout_ms);
    // Detach before any wait task: successful Child.wait closes its attached
    // streams, while this owner alone must retire the pending read and pipe.
    const stdout_file = child.stdout.?;
    child.stdout = null;
    defer stdout_file.close(io);
    var storage: Io.File.MultiReader.Buffer(1) = undefined;
    var reader: Io.File.MultiReader = undefined;
    reader.init(gpa, io, storage.toStreams(), &.{stdout_file});
    defer reader.deinit();
    while (reader.fill(4096, .{ .deadline = deadline })) |_| {
        try reader.checkAnyError();
        if (reader.reader(0).buffered().len > max_clipboard_bytes) return null;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
    try reader.checkAnyError();
    // stdout EOF does not imply process exit. The same deadline covers the
    // wait, including a command that closes stdout and remains alive.
    const term = try waitWindowsProcess(&child, io, deadline) orelse return null;
    if (!successfulTerm(term)) return null;
    return try reader.toOwnedSlice(0);
}

fn runCaptureLegacy(
    gpa: std.mem.Allocator,
    io: Io,
    argv: []const []const u8,
    timeout_ms: u64,
    environ: ?*const std.process.Environ.Map,
) !?[]u8 {
    const duration_ms: i64 = @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const result = std.process.run(gpa, io, .{
        .argv = argv,
        .stdout_limit = .limited(max_clipboard_bytes),
        .stderr_limit = .limited(256 * 1024),
        .environ_map = environ,
        .timeout = .{ .duration = .{ .raw = .fromMilliseconds(duration_ms), .clock = .real } },
    }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    defer gpa.free(result.stderr);
    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!ok) {
        gpa.free(result.stdout);
        return null;
    }
    return result.stdout;
}

fn tempRoot(gpa: std.mem.Allocator, environ: ?*const std.process.Environ.Map, explicit: ?[]const u8) ![]u8 {
    if (explicit) |value| return gpa.dupe(u8, value);
    if (environ) |env| {
        if (env.get("TMPDIR") orelse env.get("TEMP") orelse env.get("TMP")) |value| {
            if (value.len > 0) return gpa.dupe(u8, value);
        }
    }
    return gpa.dupe(u8, if (builtin.os.tag == .windows) "." else "/tmp");
}

const PrivateFile = struct {
    gpa: std.mem.Allocator,
    io: Io,
    path: []u8,
    file: ?Io.File,

    fn create(gpa: std.mem.Allocator, io: Io, options: Options, extension: []const u8) !PrivateFile {
        const path = try temporaryPath(gpa, io, options.environ, options.temp_dir, extension);
        errdefer gpa.free(path);
        const file = try Io.Dir.cwd().createFile(io, path, .{
            .truncate = true,
            .exclusive = true,
            .permissions = file_permissions.privateFile(),
        });
        // Cleanup ownership begins only after exclusive creation succeeds.
        return .{ .gpa = gpa, .io = io, .path = path, .file = file };
    }

    fn close(self: *PrivateFile) void {
        if (self.file) |file| file.close(self.io);
        self.file = null;
    }

    fn deinit(self: *PrivateFile) void {
        self.close();
        Io.Dir.cwd().deleteFile(self.io, self.path) catch {};
        self.gpa.free(self.path);
        self.* = undefined;
    }
};

fn temporaryPath(gpa: std.mem.Allocator, io: Io, environ: ?*const std.process.Environ.Map, explicit: ?[]const u8, extension: []const u8) ![]u8 {
    const root = try tempRoot(gpa, environ, explicit);
    defer gpa.free(root);
    var random: [16]u8 = undefined;
    try io.randomSecure(&random);
    var encoded: [32]u8 = undefined;
    const hex = "0123456789abcdef";
    for (random, 0..) |byte, index| {
        encoded[index * 2] = hex[byte >> 4];
        encoded[index * 2 + 1] = hex[byte & 0x0f];
    }
    const name = try std.fmt.allocPrint(gpa, "pi-clipboard-stage-{s}.{s}", .{ encoded, extension });
    defer gpa.free(name);
    return std.fs.path.join(gpa, &.{ root, name });
}

fn fakePng() [24]u8 {
    var png = [_]u8{0} ** 24;
    @memcpy(png[0..8], &[_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a });
    png[11] = 13;
    @memcpy(png[12..16], "IHDR");
    png[19] = 2;
    png[23] = 3;
    return png;
}

test "clipboard MIME preference handles parameters and arbitrary image fallback" {
    try std.testing.expectEqualStrings("image/png; charset=binary", selectPreferredImageMimeType("text/plain\nimage/jpeg\nimage/png; charset=binary\n").?);
    try std.testing.expectEqualStrings("image/tiff", selectPreferredImageMimeType("text/plain\nimage/tiff\n").?);
    try std.testing.expect(selectPreferredImageMimeType("text/plain\n") == null);
}

test "Wayland clipboard image and text use bounded command paths" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const FakeRunner = struct {
        png: [24]u8,
        list_calls: usize = 0,
        image_calls: usize = 0,
        text_calls: usize = 0,

        fn run(
            raw: *anyopaque,
            allocator: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            timeout_ms: u64,
            _: ?*const std.process.Environ.Map,
        ) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expect(timeout_ms <= text_read_timeout_ms);
            if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--list-types")) {
                self.list_calls += 1;
                return @as(?[]u8, try allocator.dupe(u8, "text/plain\nimage/png\n"));
            }
            var type_value: ?[]const u8 = null;
            for (argv[1..], 1..) |arg, index| {
                if (std.mem.eql(u8, arg, "--type") and index + 1 < argv.len) {
                    type_value = argv[index + 1];
                    break;
                }
            }
            if (type_value) |value| {
                if (std.mem.eql(u8, value, "image/png")) {
                    self.image_calls += 1;
                    return @as(?[]u8, try allocator.dupe(u8, &self.png));
                }
                if (std.mem.eql(u8, value, "text") or std.mem.startsWith(u8, value, "text/plain")) {
                    self.text_calls += 1;
                    return @as(?[]u8, try allocator.dupe(u8, "clipboard text"));
                }
            }
            return null;
        }
    };

    var fake = FakeRunner{ .png = fakePng() };
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("WAYLAND_DISPLAY", "wayland-1");
    try env.put("XDG_SESSION_TYPE", "wayland");
    const options = Options{
        .environ = &env,
        .platform = .linux,
        .runner = .{ .context = &fake, .run_fn = FakeRunner.run },
    };
    var image = (try readClipboardImage(gpa, io, options)).?;
    defer image.deinit(gpa);
    try std.testing.expectEqualStrings("image/png", image.mime_type);
    try std.testing.expectEqualSlices(u8, &fake.png, image.bytes);
    const text = (try readClipboardText(gpa, io, options)).?;
    defer gpa.free(text);
    try std.testing.expectEqualStrings("clipboard text", text);
    try std.testing.expectEqual(@as(usize, 1), fake.list_calls);
    try std.testing.expectEqual(@as(usize, 1), fake.image_calls);
    try std.testing.expectEqual(@as(usize, 1), fake.text_calls);
}

test "macOS clipboard text uses the native helper without a command fallback" {
    const Fake = struct {
        native_calls: usize = 0,
        command_calls: usize = 0,
        fn get(raw: ?*anyopaque, gpa: std.mem.Allocator, memory_limit: usize) !native_clipboard.Read {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.native_calls += 1;
            try std.testing.expectEqual(native_clipboard.default_memory_limit, memory_limit);
            return .{ .value = try gpa.dupe(u8, "mac clipboard") };
        }
        fn run(raw: *anyopaque, _: std.mem.Allocator, _: Io, _: []const []const u8, _: u64, _: ?*const std.process.Environ.Map) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.command_calls += 1;
            return null;
        }
    };
    var fake: Fake = .{};
    const text = (try readClipboardText(std.testing.allocator, std.testing.io, .{
        .platform = .macos,
        .native_backend = .{ .context = &fake, .get_text_fn = Fake.get },
        .runner = .{ .context = &fake, .run_fn = Fake.run },
    })).?;
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("mac clipboard", text);
    try std.testing.expectEqual(@as(usize, 1), fake.native_calls);
    try std.testing.expectEqual(@as(usize, 0), fake.command_calls);
}

test "Termux skips image probing and retains text clipboard fallback" {
    const Fake = struct {
        calls: usize = 0,
        fn run(
            raw: *anyopaque,
            allocator: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            _: u64,
            _: ?*const std.process.Environ.Map,
        ) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            try std.testing.expectEqualStrings("termux-clipboard-get", argv[0]);
            return @as(?[]u8, try allocator.dupe(u8, "termux clipboard"));
        }
    };
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("TERMUX_VERSION", "0.119");
    var fake = Fake{};
    var paste = (try readPaste(std.testing.allocator, std.testing.io, .{
        .environ = &env,
        .platform = .linux,
        .runner = .{ .context = &fake, .run_fn = Fake.run },
    })).?;
    defer paste.deinit(std.testing.allocator);
    switch (paste) {
        .text => |text| try std.testing.expectEqualStrings("termux clipboard", text),
        .image => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

test "Termux clipboard also runs on Android-like platform without a Linux platform label" {
    const Fake = struct {
        calls: usize = 0,
        fn run(raw: *anyopaque, gpa: std.mem.Allocator, _: Io, argv: []const []const u8, timeout_ms: u64, _: ?*const std.process.Environ.Map) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            try std.testing.expectEqualStrings("termux-clipboard-get", argv[0]);
            try std.testing.expectEqual(@as(usize, 1), argv.len);
            try std.testing.expectEqual(@as(u64, 5_000), timeout_ms);
            return try gpa.dupe(u8, "android clipboard");
        }
    };
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try env.put("TERMUX_VERSION", "0.119");
    var fake: Fake = .{};
    var paste = (try readPaste(std.testing.allocator, std.testing.io, .{ .environ = &env, .platform = .other, .runner = .{ .context = &fake, .run_fn = Fake.run } })).?;
    defer paste.deinit(std.testing.allocator);
    try std.testing.expect(paste == .text);
    try std.testing.expectEqualStrings("android clipboard", paste.text);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

test "X11 clipboard image uses advertised target before text fallback" {
    const Fake = struct {
        png: [24]u8 = fakePng(),
        target_calls: usize = 0,
        image_calls: usize = 0,
        fn run(
            raw: *anyopaque,
            allocator: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            _: u64,
            _: ?*const std.process.Environ.Map,
        ) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            for (argv) |arg| if (std.mem.eql(u8, arg, "TARGETS")) {
                self.target_calls += 1;
                return @as(?[]u8, try allocator.dupe(u8, "text/plain\nimage/png\n"));
            };
            for (argv, 0..) |arg, index| {
                if (std.mem.eql(u8, arg, "-t") and index + 1 < argv.len and std.mem.eql(u8, argv[index + 1], "image/png")) {
                    self.image_calls += 1;
                    return @as(?[]u8, try allocator.dupe(u8, &self.png));
                }
            }
            return null;
        }
    };
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("DISPLAY", ":0");
    var fake = Fake{};
    var image = (try readClipboardImage(std.testing.allocator, std.testing.io, .{
        .environ = &env,
        .platform = .linux,
        .runner = .{ .context = &fake, .run_fn = Fake.run },
    })).?;
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("image/png", image.mime_type);
    try std.testing.expectEqual(@as(usize, 1), fake.target_calls);
    try std.testing.expectEqual(@as(usize, 1), fake.image_calls);
}

test "clipboard temp store writes private attachment and formats quoted reference" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    var store = TempStore.init(gpa, io, null);
    store.temp_dir = root;
    const png = fakePng();
    const path = try store.saveImage(.{ .bytes = @constCast(&png), .mime_type = "image/png" });
    try std.testing.expect((try std.Io.Dir.cwd().statFile(io, path, .{})).kind == .file);
    const reference = try formatAttachmentReference(gpa, path);
    defer gpa.free(reference);
    try std.testing.expect(std.mem.startsWith(u8, reference, "@\""));
    const owned_path = try gpa.dupe(u8, path);
    defer gpa.free(owned_path);
    store.deinit();
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, owned_path, .{}));
}

test "Wayland copy prefers native wl-copy without OSC 52 locally" {
    const Fake = struct {
        calls: usize = 0,
        fn run(
            raw: *anyopaque,
            _: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            input: []const u8,
            timeout_ms: u64,
            _: ?*const std.process.Environ.Map,
        ) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            try std.testing.expectEqualStrings("wl-copy", argv[0]);
            try std.testing.expectEqualStrings("copy me", input);
            try std.testing.expectEqual(write_timeout_ms, timeout_ms);
            return true;
        }
    };
    const Sink = struct {
        bytes: std.ArrayList(u8) = .empty,
        fn write(raw: *anyopaque, _: Io, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.bytes.appendSlice(std.testing.allocator, bytes);
        }
    };
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("WAYLAND_DISPLAY", "wayland-1");
    try env.put("XDG_SESSION_TYPE", "wayland");
    var fake = Fake{};
    var sink = Sink{};
    defer sink.bytes.deinit(std.testing.allocator);
    const result = try copyText(std.testing.allocator, std.testing.io, "copy me", .{
        .environ = &env,
        .platform = .linux,
        .write_runner = .{ .context = &fake, .run_fn = Fake.run },
        .output_writer = .{ .context = &sink, .write_fn = Sink.write },
    });
    try std.testing.expect(result.native);
    try std.testing.expect(!result.osc52);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
    try std.testing.expectEqual(@as(usize, 0), sink.bytes.items.len);
    // Pi 1.2 also copies to the client terminal when its remote transport has
    // no SSH/Mosh markers. Only the exact opt-in value enables this path.
    for ([_][]const u8{ "", "0", "true", "01", "1" }) |value| {
        try env.put("PI_CLIPBOARD_OSC52", value);
        sink.bytes.clearRetainingCapacity();
        const opted_in = try copyText(std.testing.allocator, std.testing.io, "copy me", .{
            .environ = &env,
            .platform = .linux,
            .write_runner = .{ .context = &fake, .run_fn = Fake.run },
            .output_writer = .{ .context = &sink, .write_fn = Sink.write },
        });
        try std.testing.expect(opted_in.native);
        try std.testing.expectEqual(std.mem.eql(u8, value, "1"), opted_in.osc52);
        try std.testing.expectEqualStrings(if (opted_in.osc52) "\x1b]52;c;Y29weSBtZQ==\x07" else "", sink.bytes.items);
    }
}

test "Wayland copy falls back to X11 and remote sessions also emit bounded OSC 52" {
    const Fake = struct {
        calls: usize = 0,
        fn run(
            raw: *anyopaque,
            _: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            input: []const u8,
            _: u64,
            _: ?*const std.process.Environ.Map,
        ) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            try std.testing.expectEqualStrings("hello", input);
            if (std.mem.eql(u8, argv[0], "wl-copy")) return false;
            if (std.mem.eql(u8, argv[0], "xclip")) return true;
            return false;
        }
    };
    const Sink = struct {
        bytes: std.ArrayList(u8) = .empty,
        fn write(raw: *anyopaque, _: Io, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.bytes.appendSlice(std.testing.allocator, bytes);
        }
    };
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("WAYLAND_DISPLAY", "wayland-1");
    try env.put("XDG_SESSION_TYPE", "wayland");
    try env.put("DISPLAY", ":0");
    try env.put("SSH_CONNECTION", "client server");
    var fake = Fake{};
    var sink = Sink{};
    defer sink.bytes.deinit(std.testing.allocator);
    const result = try copyText(std.testing.allocator, std.testing.io, "hello", .{
        .environ = &env,
        .platform = .linux,
        .write_runner = .{ .context = &fake, .run_fn = Fake.run },
        .output_writer = .{ .context = &sink, .write_fn = Sink.write },
    });
    try std.testing.expect(result.native and result.osc52);
    try std.testing.expectEqual(@as(usize, 2), fake.calls);
    try std.testing.expectEqualStrings("\x1b]52;c;aGVsbG8=\x07", sink.bytes.items);
}

test "headless Linux copy uses OSC 52 and reports its size limit" {
    const Sink = struct {
        bytes: std.ArrayList(u8) = .empty,
        fn write(raw: *anyopaque, _: Io, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.bytes.appendSlice(std.testing.allocator, bytes);
        }
    };
    var sink = Sink{};
    defer sink.bytes.deinit(std.testing.allocator);
    const NoCommand = struct {
        fn run(_: *anyopaque, _: std.mem.Allocator, _: Io, _: []const []const u8, _: u64, _: ?*const std.process.Environ.Map) !?[]u8 {
            return null;
        }
    };
    const result = try copyText(std.testing.allocator, std.testing.io, "fallback", .{
        .platform = .linux,
        .native_backend = native_clipboard.unavailable,
        .runner = .{ .context = &sink, .run_fn = NoCommand.run },
        .output_writer = .{ .context = &sink, .write_fn = Sink.write },
    });
    try std.testing.expect(!result.native and result.osc52);
    try std.testing.expect(std.mem.startsWith(u8, sink.bytes.items, "\x1b]52;c;"));

    sink.bytes.clearRetainingCapacity();
    const too_large = try std.testing.allocator.alloc(u8, (osc52.max_encoded_length / 4) * 3 + 4);
    defer std.testing.allocator.free(too_large);
    @memset(too_large, 'x');
    try std.testing.expectError(error.ClipboardOsc52TooLarge, copyText(std.testing.allocator, std.testing.io, too_large, .{
        .platform = .linux,
        .native_backend = native_clipboard.unavailable,
        .runner = .{ .context = &sink, .run_fn = NoCommand.run },
        .output_writer = .{ .context = &sink, .write_fn = Sink.write },
    }));
    try std.testing.expectEqual(@as(usize, 0), sink.bytes.items.len);
}

test "Termux and Windows copy select their native commands" {
    const Fake = struct {
        expected: []const u8,
        calls: usize = 0,
        fn run(
            raw: *anyopaque,
            _: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            _: []const u8,
            _: u64,
            _: ?*const std.process.Environ.Map,
        ) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            try std.testing.expectEqualStrings(self.expected, argv[0]);
            return true;
        }
    };
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("TERMUX_VERSION", "0.119");
    var termux = Fake{ .expected = "termux-clipboard-set" };
    const termux_result = try copyText(std.testing.allocator, std.testing.io, "termux", .{
        .environ = &env,
        .platform = .linux,
        .write_runner = .{ .context = &termux, .run_fn = Fake.run },
    });
    try std.testing.expect(termux_result.native and !termux_result.osc52);

    var windows = Fake{ .expected = "clip" };
    const windows_result = try copyText(std.testing.allocator, std.testing.io, "windows", .{
        .platform = .windows,
        .native_backend = native_clipboard.unavailable,
        .write_runner = .{ .context = &windows, .run_fn = Fake.run },
    });
    try std.testing.expect(windows_result.native and !windows_result.osc52);
}

test "native clipboard writer force-terminates a hung command" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &root_buf);
    const started = std.Io.Clock.real.now(std.testing.io).toMilliseconds();
    const copied = try runWrite(std.testing.allocator, std.testing.io, &.{ "sh", "-c", "sleep 5" }, "blocked", 50, .{
        .platform = .linux,
        .temp_dir = root_buf[0..root_len],
    });
    const elapsed = std.Io.Clock.real.now(std.testing.io).toMilliseconds() - started;
    try std.testing.expect(!copied);
    try std.testing.expect(elapsed < 2_000);
}

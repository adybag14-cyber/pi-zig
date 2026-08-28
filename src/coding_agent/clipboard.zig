//! Cross-platform clipboard integration for the native interactive editor.
//!
//! Image paste follows the original Pi order: prefer image data, then fall
//! back to plain text. Linux supports Wayland (`wl-paste`) and X11 (`xclip`),
//! WSL can query the Windows clipboard through PowerShell, macOS supports
//! `pngpaste` with an AppleScript fallback, and Windows uses PowerShell's
//! System.Windows.Forms clipboard API. Termux intentionally skips image paste
//! but retains `termux-clipboard-get` text fallback.
const std = @import("std");
const builtin = @import("builtin");
const image_process = @import("../ai/image_process.zig");
const osc52 = @import("../tui/osc52.zig");
const file_permissions = @import("../file_permissions.zig");
const Io = std.Io;

pub const max_clipboard_bytes: usize = 50 * 1024 * 1024;
pub const list_timeout_ms: u64 = 1_000;
pub const read_timeout_ms: u64 = 3_000;
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

pub const Options = struct {
    environ: ?*const std.process.Environ.Map = null,
    platform: ?Platform = null,
    commands: Commands = .{},
    temp_dir: ?[]const u8 = null,
    runner: ?CommandRunner = null,
    write_runner: ?WriteRunner = null,
    output_writer: ?OutputWriter = null,
    osc52_fallback: bool = true,
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
        const extension = extensionForMime(image.mime_type);
        const root = try tempRoot(self.gpa, self.environ, self.temp_dir);
        defer self.gpa.free(root);
        const stamp = std.Io.Clock.real.now(self.io).toMilliseconds();
        const sequence = temp_counter.fetchAdd(1, .monotonic);
        const name = try std.fmt.allocPrint(self.gpa, "pi-clipboard-{d}-{x}.{s}", .{ stamp, sequence, extension });
        defer self.gpa.free(name);
        const path = try std.fs.path.join(self.gpa, &.{ root, name });
        errdefer self.gpa.free(path);

        const permissions = file_permissions.privateFile();
        const file = try std.Io.Dir.cwd().createFile(self.io, path, .{
            .truncate = true,
            .permissions = permissions,
        });
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, image.bytes);
        try self.paths.append(self.gpa, path);
        return path;
    }
};

var temp_counter: std.atomic.Value(u64) = .init(1);

pub fn copyText(gpa: std.mem.Allocator, io: Io, text: []const u8, options: Options) !CopyResult {
    if (text.len > max_clipboard_bytes) return error.ClipboardTooLarge;

    var result = CopyResult{};
    result.native = copyNative(gpa, io, text, options);
    if (options.osc52_fallback and (isRemoteSession(options.environ) or !result.native)) {
        result.osc52 = try emitOsc52(gpa, io, text, options);
    }
    if (!result.native and !result.osc52) return error.ClipboardUnavailable;
    return result;
}

pub fn isRemoteSession(environ: ?*const std.process.Environ.Map) bool {
    return envHas(environ, "SSH_CONNECTION") or envHas(environ, "SSH_CLIENT") or envHas(environ, "MOSH_CONNECTION");
}

fn copyNative(gpa: std.mem.Allocator, io: Io, text: []const u8, options: Options) bool {
    const environ = options.environ;
    const platform = options.platform orelse nativePlatform();

    if (envHas(environ, "TERMUX_VERSION")) {
        if (tryWrite(gpa, io, &.{options.commands.termux_clipboard_set}, text, options)) return true;
    }

    return switch (platform) {
        .macos => tryWrite(gpa, io, &.{options.commands.pbcopy}, text, options),
        .windows => blk: {
            if (tryWrite(gpa, io, &.{options.commands.clip}, text, options)) break :blk true;
            const script = "[Console]::In.ReadToEnd() | Set-Clipboard";
            break :blk tryWrite(gpa, io, &.{ options.commands.powershell, "-NoProfile", "-NonInteractive", "-Command", script }, text, options);
        },
        .linux => blk: {
            const wayland = isWaylandSession(environ) and envHas(environ, "WAYLAND_DISPLAY");
            const x11 = envHas(environ, "DISPLAY");
            if (wayland and tryWrite(gpa, io, &.{options.commands.wl_copy}, text, options)) break :blk true;
            if (x11) {
                if (tryWrite(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard" }, text, options)) break :blk true;
                if (tryWrite(gpa, io, &.{ options.commands.xsel, "--clipboard", "--input" }, text, options)) break :blk true;
            }
            // WSL terminals commonly have neither a Wayland nor X11 display.
            if (isWsl(io, environ)) {
                if (tryWrite(gpa, io, &.{options.commands.clip}, text, options)) break :blk true;
                const script = "[Console]::In.ReadToEnd() | Set-Clipboard";
                if (tryWrite(gpa, io, &.{ options.commands.powershell, "-NoProfile", "-NonInteractive", "-Command", script }, text, options)) break :blk true;
            }
            break :blk false;
        },
        .other => false,
    };
}

fn tryWrite(gpa: std.mem.Allocator, io: Io, argv: []const []const u8, input: []const u8, options: Options) bool {
    return writeCommand(gpa, io, argv, input, write_timeout_ms, options) catch false;
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
    const path = try temporaryPath(gpa, options.environ, options.temp_dir, "txt");
    defer {
        std.Io.Dir.cwd().deleteFile(io, path) catch {};
        gpa.free(path);
    }
    const permissions = file_permissions.privateFile();
    {
        const stage = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true, .permissions = permissions });
        defer stage.close(io);
        try stage.writeStreamingAll(io, input);
    }

    const stdin_file = try std.Io.Dir.cwd().openFile(io, path, .{});
    var child = std.process.spawn(io, .{
        .argv = argv,
        .environ_map = options.environ,
        .stdin = .{ .file = stdin_file },
        .stdout = .ignore,
        .stderr = .ignore,
        .pgid = if (builtin.os.tag == .windows) null else 0,
        .create_no_window = builtin.os.tag == .windows,
    }) catch {
        stdin_file.close(io);
        return false;
    };
    stdin_file.close(io);

    const WaitState = struct {
        child: *std.process.Child,
        io: Io,
        done: std.atomic.Value(bool) = .init(false),
        term: ?std.process.Child.Term = null,
    };
    var state = WaitState{ .child = &child, .io = io };
    const waiter = std.Thread.spawn(.{}, struct {
        fn run(s: *WaitState) void {
            defer s.done.store(true, .release);
            s.term = s.child.wait(s.io) catch null;
        }
    }.run, .{&state}) catch {
        child.kill(io);
        return false;
    };

    var elapsed: u64 = 0;
    var timed_out = false;
    while (!state.done.load(.acquire)) {
        if (elapsed >= timeout_ms) {
            forceKillProcess(&child);
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

pub fn readClipboardImage(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    const environ = options.environ;
    if (envHas(environ, "TERMUX_VERSION")) return null;
    return switch (options.platform orelse nativePlatform()) {
        .linux => readLinuxImage(gpa, io, options),
        .macos => readMacImage(gpa, io, options),
        .windows => readPowerShellImage(gpa, io, options, false),
        .other => null,
    };
}

pub fn readClipboardText(gpa: std.mem.Allocator, io: Io, options: Options) !?[]u8 {
    const environ = options.environ;
    const platform = options.platform orelse nativePlatform();
    var bytes: ?[]u8 = null;

    if (envHas(environ, "TERMUX_VERSION")) {
        bytes = try capture(gpa, io, &.{options.commands.termux_clipboard_get}, read_timeout_ms, options);
    } else switch (platform) {
        .linux => {
            if (isWaylandSession(environ) and envHas(environ, "WAYLAND_DISPLAY")) {
                bytes = try capture(gpa, io, &.{ options.commands.wl_paste, "--no-newline", "--type", "text" }, read_timeout_ms, options);
                if (bytes == null) bytes = try capture(gpa, io, &.{ options.commands.wl_paste, "--no-newline", "--type", "text/plain;charset=utf-8" }, read_timeout_ms, options);
            }
            if (bytes == null and isWsl(io, environ)) {
                bytes = try capture(gpa, io, &.{ options.commands.powershell, "-NoProfile", "-NonInteractive", "-Command", "Get-Clipboard -Raw" }, powershell_timeout_ms, options);
            }
            if (bytes == null) bytes = try capture(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard", "-o" }, read_timeout_ms, options);
            if (bytes == null) bytes = try capture(gpa, io, &.{ options.commands.xsel, "--clipboard", "--output" }, read_timeout_ms, options);
        },
        .macos => bytes = try capture(gpa, io, &.{options.commands.pbpaste}, read_timeout_ms, options),
        .windows => bytes = try capture(gpa, io, &.{ options.commands.powershell, "-NoProfile", "-NonInteractive", "-Command", "Get-Clipboard -Raw" }, powershell_timeout_ms, options),
        .other => {},
    }

    const owned = bytes orelse return null;
    if (owned.len == 0 or !std.unicode.utf8ValidateSlice(owned) or std.mem.indexOfScalar(u8, owned, 0) != null) {
        gpa.free(owned);
        return null;
    }
    return owned;
}

fn readLinuxImage(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    const environ = options.environ;
    const wayland = isWaylandSession(environ);
    const wsl = isWsl(io, environ);

    if (wayland or wsl) {
        if (try readWlPasteImage(gpa, io, options)) |image| return image;
        if (try readXclipImage(gpa, io, options)) |image| return image;
    }
    if (wsl) if (try readPowerShellImage(gpa, io, options, true)) |image| return image;
    if (!wayland) if (try readXclipImage(gpa, io, options)) |image| return image;
    return null;
}

fn readWlPasteImage(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    const list = (try capture(gpa, io, &.{ options.commands.wl_paste, "--list-types" }, list_timeout_ms, options)) orelse return null;
    defer gpa.free(list);
    const selected = selectPreferredImageMimeType(list) orelse return null;
    const bytes = (try capture(gpa, io, &.{ options.commands.wl_paste, "--type", selected, "--no-newline" }, read_timeout_ms, options)) orelse return null;
    return validatedImage(gpa, bytes);
}

fn readXclipImage(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    var preferred: ?[]const u8 = null;
    const targets = try capture(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard", "-t", "TARGETS", "-o" }, list_timeout_ms, options);
    defer if (targets) |value| gpa.free(value);
    if (targets) |value| preferred = selectPreferredImageMimeType(value);

    const candidates = [_][]const u8{ "image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp" };
    if (preferred) |mime| {
        if (try capture(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard", "-t", mime, "-o" }, read_timeout_ms, options)) |bytes| {
            if (validatedImage(gpa, bytes)) |image| return image;
        }
    }
    for (candidates) |mime| {
        if (preferred) |first| if (std.ascii.eqlIgnoreCase(first, mime)) continue;
        if (try capture(gpa, io, &.{ options.commands.xclip, "-selection", "clipboard", "-t", mime, "-o" }, read_timeout_ms, options)) |bytes| {
            if (validatedImage(gpa, bytes)) |image| return image;
        }
    }
    return null;
}

fn readMacImage(gpa: std.mem.Allocator, io: Io, options: Options) !?ClipboardImage {
    if (try capture(gpa, io, &.{ options.commands.pngpaste, "-" }, read_timeout_ms, options)) |bytes| {
        if (validatedImage(gpa, bytes)) |image| return image;
    }

    const path = try temporaryPath(gpa, options.environ, options.temp_dir, "png");
    defer {
        std.Io.Dir.cwd().deleteFile(io, path) catch {};
        gpa.free(path);
    }
    const script =
        \\on run argv
        \\  set outPath to item 1 of argv
        \\  try
        \\    set pngData to the clipboard as «class PNGf»
        \\    set outFile to open for access POSIX file outPath with write permission
        \\    set eof outFile to 0
        \\    write pngData to outFile
        \\    close access outFile
        \\    return "ok"
        \\  on error
        \\    try
        \\      close access POSIX file outPath
        \\    end try
        \\    return "empty"
        \\  end try
        \\end run
    ;
    const result = try capture(gpa, io, &.{ options.commands.osascript, "-e", script, path }, powershell_timeout_ms, options);
    defer if (result) |value| gpa.free(value);
    if (result == null or !std.mem.eql(u8, std.mem.trim(u8, result.?, " \t\r\n"), "ok")) return null;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_clipboard_bytes)) catch return null;
    return validatedImage(gpa, bytes);
}

fn readPowerShellImage(gpa: std.mem.Allocator, io: Io, options: Options, wsl: bool) !?ClipboardImage {
    const path = try temporaryPath(gpa, options.environ, options.temp_dir, "png");
    defer {
        std.Io.Dir.cwd().deleteFile(io, path) catch {};
        gpa.free(path);
    }
    var target_path: []u8 = undefined;
    if (wsl) {
        target_path = (try capture(gpa, io, &.{ options.commands.wslpath, "-w", path }, list_timeout_ms, options)) orelse return null;
    } else {
        target_path = try gpa.dupe(u8, path);
    }
    defer gpa.free(target_path);
    const target = std.mem.trim(u8, target_path, " \t\r\n");
    if (target.len == 0) return null;

    const script =
        \\& { param([string]$path)
        \\  Add-Type -AssemblyName System.Windows.Forms
        \\  Add-Type -AssemblyName System.Drawing
        \\  $img = [System.Windows.Forms.Clipboard]::GetImage()
        \\  if ($null -eq $img) { exit 3 }
        \\  try { $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $img.Dispose() }
        \\}
    ;
    const output = try capture(gpa, io, &.{ options.commands.powershell, "-NoProfile", "-NonInteractive", "-Command", script, target }, powershell_timeout_ms, options);
    defer if (output) |value| gpa.free(value);
    if (output == null) return null;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_clipboard_bytes)) catch return null;
    return validatedImage(gpa, bytes);
}

fn validatedImage(gpa: std.mem.Allocator, bytes: []u8) ?ClipboardImage {
    if (bytes.len == 0) {
        gpa.free(bytes);
        return null;
    }
    const info = image_process.inspect(bytes) orelse {
        gpa.free(bytes);
        return null;
    };
    return .{ .bytes = bytes, .mime_type = info.mime_type };
}

/// Input is newline-separated MIME targets. Returned slices borrow `raw`.
pub fn selectPreferredImageMimeType(raw: []const u8) ?[]const u8 {
    const preferred = [_][]const u8{ "image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp" };
    for (preferred) |candidate| {
        var lines = std.mem.splitAny(u8, raw, "\r\n");
        while (lines.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t");
            if (std.ascii.eqlIgnoreCase(baseMime(line), candidate)) return line;
        }
    }
    var lines = std.mem.splitAny(u8, raw, "\r\n");
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t");
        if (std.ascii.startsWithIgnoreCase(baseMime(line), "image/")) return line;
    }
    return null;
}

fn baseMime(value: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, value, ';') orelse value.len;
    return std.mem.trim(u8, value[0..end], " \t\r\n");
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
    return envHas(environ, "WAYLAND_DISPLAY") or if (envGet(environ, "XDG_SESSION_TYPE")) |value| std.ascii.eqlIgnoreCase(value, "wayland") else false;
}

fn isWsl(io: Io, environ: ?*const std.process.Environ.Map) bool {
    if (envHas(environ, "WSL_DISTRO_NAME") or envHas(environ, "WSLENV")) return true;
    const release = std.Io.Dir.cwd().readFileAlloc(io, "/proc/version", std.heap.page_allocator, .limited(64 * 1024)) catch return false;
    defer std.heap.page_allocator.free(release);
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
    if (options.runner) |runner| return runner.run(gpa, io, argv, timeout_ms, options.environ);
    return runCapture(gpa, io, argv, timeout_ms, options.environ);
}

fn runCapture(
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
    }) catch return null;
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

fn temporaryPath(gpa: std.mem.Allocator, environ: ?*const std.process.Environ.Map, explicit: ?[]const u8, extension: []const u8) ![]u8 {
    const root = try tempRoot(gpa, environ, explicit);
    defer gpa.free(root);
    const sequence = temp_counter.fetchAdd(1, .monotonic);
    const name = try std.fmt.allocPrint(gpa, "pi-clipboard-stage-{x}.{s}", .{ sequence, extension });
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
            try std.testing.expect(timeout_ms <= read_timeout_ms);
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

test "macOS clipboard text uses pbpaste rather than image transport" {
    const Fake = struct {
        command: ?[]const u8 = null,
        fn run(
            raw: *anyopaque,
            allocator: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            _: u64,
            _: ?*const std.process.Environ.Map,
        ) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.command = argv[0];
            if (!std.mem.eql(u8, argv[0], "pbpaste")) return null;
            return @as(?[]u8, try allocator.dupe(u8, "mac clipboard"));
        }
    };
    var fake = Fake{};
    const text = (try readClipboardText(std.testing.allocator, std.testing.io, .{
        .platform = .macos,
        .runner = .{ .context = &fake, .run_fn = Fake.run },
    })).?;
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("pbpaste", fake.command.?);
    try std.testing.expectEqualStrings("mac clipboard", text);
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

test "copy falls back to OSC 52 and rejects oversized terminal payloads" {
    const Sink = struct {
        bytes: std.ArrayList(u8) = .empty,
        fn write(raw: *anyopaque, _: Io, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.bytes.appendSlice(std.testing.allocator, bytes);
        }
    };
    var sink = Sink{};
    defer sink.bytes.deinit(std.testing.allocator);
    const result = try copyText(std.testing.allocator, std.testing.io, "fallback", .{
        .platform = .other,
        .output_writer = .{ .context = &sink, .write_fn = Sink.write },
    });
    try std.testing.expect(!result.native and result.osc52);
    try std.testing.expect(std.mem.startsWith(u8, sink.bytes.items, "\x1b]52;c;"));

    sink.bytes.clearRetainingCapacity();
    const too_large = try std.testing.allocator.alloc(u8, (osc52.max_encoded_length / 4) * 3 + 4);
    defer std.testing.allocator.free(too_large);
    @memset(too_large, 'x');
    try std.testing.expectError(error.ClipboardUnavailable, copyText(std.testing.allocator, std.testing.io, too_large, .{
        .platform = .other,
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

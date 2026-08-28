//! Fullscreen provider-owned authentication dialog.
//!
//! This is the interaction surface used after `/login` selects a provider and
//! authentication method.  OAuth and device-code transports remain in the
//! native auth modules; this dialog owns presentation, manual input, progress,
//! and cooperative cancellation while those transports are waiting.
const std = @import("std");
const Io = std.Io;
const application = @import("../tui/application.zig");
const line_editor = @import("../tui/line_editor.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const tui_render = @import("../tui/render.zig");

const accent = "\x1b[36m";
const success = "\x1b[32m";
const warning = "\x1b[33m";
const failure = "\x1b[31m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reset = "\x1b[0m";

pub const Link = struct {
    url: []const u8,
    label: ?[]const u8 = null,
};

pub const DeviceCode = struct {
    verification_uri: []const u8,
    user_code: []const u8,
    instructions: ?[]const u8 = null,
    interval_seconds: ?u64 = null,
    expires_in_seconds: ?u64 = null,
};

const Stage = enum {
    starting,
    auth_url,
    device_code,
    info,
    waiting,
    prompt,
    complete,
};

const State = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    mutex: Io.Mutex = .init,
    group: Io.Group = .init,
    stop: bool = false,
    abort_flag: bool = false,
    stage: Stage = .starting,
    provider: []u8,
    title: []u8,
    url: ?[]u8 = null,
    instructions: ?[]u8 = null,
    user_code: ?[]u8 = null,
    message: ?[]u8 = null,
    placeholder: ?[]u8 = null,
    links: std.ArrayList([]u8) = .empty,
    progress: std.ArrayList([]u8) = .empty,
    input: std.ArrayList(u8) = .empty,
    prompt_secret: bool = false,
    prompt_submitted: bool = false,
    spinner: usize = 0,
    started_ms: i64,
    terminal_width: usize = 100,
    terminal_rows: usize = 30,
    paint_error: ?anyerror = null,

    fn init(
        gpa: std.mem.Allocator,
        io: Io,
        environ: *const std.process.Environ.Map,
        reader: ?*Io.File.Reader,
        provider: []const u8,
        title: []const u8,
    ) !State {
        return .{
            .gpa = gpa,
            .io = io,
            .environ = environ,
            .reader = reader,
            .provider = try gpa.dupe(u8, provider),
            .title = try gpa.dupe(u8, title),
            .started_ms = std.Io.Clock.awake.now(io).toMilliseconds(),
        };
    }

    fn deinit(self: *State) void {
        self.gpa.free(self.provider);
        self.gpa.free(self.title);
        self.freeOptional(&self.url);
        self.freeOptional(&self.instructions);
        self.freeOptional(&self.user_code);
        self.freeOptional(&self.message);
        self.freeOptional(&self.placeholder);
        for (self.links.items) |line| self.gpa.free(line);
        self.links.deinit(self.gpa);
        for (self.progress.items) |line| self.gpa.free(line);
        self.progress.deinit(self.gpa);
        @memset(self.input.items, 0);
        self.input.deinit(self.gpa);
        self.* = undefined;
    }

    fn freeOptional(self: *State, slot: *?[]u8) void {
        if (slot.*) |value| self.gpa.free(value);
        slot.* = null;
    }

    fn replace(self: *State, slot: *?[]u8, value: ?[]const u8) !void {
        self.freeOptional(slot);
        if (value) |text| slot.* = try self.gpa.dupe(u8, text);
    }

    fn resetContent(self: *State) void {
        self.freeOptional(&self.url);
        self.freeOptional(&self.instructions);
        self.freeOptional(&self.user_code);
        self.freeOptional(&self.message);
        self.freeOptional(&self.placeholder);
        for (self.links.items) |line| self.gpa.free(line);
        self.links.clearRetainingCapacity();
        for (self.progress.items) |line| self.gpa.free(line);
        self.progress.clearRetainingCapacity();
        @memset(self.input.items, 0);
        self.input.clearRetainingCapacity();
        self.prompt_secret = false;
        self.prompt_submitted = false;
    }

    fn setAbort(self: *State) void {
        @atomicStore(bool, &self.abort_flag, true, .release);
        self.stage = .waiting;
        self.replace(&self.message, "Cancelling authentication…") catch {};
        self.prompt_submitted = true;
    }

    fn isAborted(self: *const State) bool {
        return @atomicLoad(bool, &self.abort_flag, .acquire);
    }

    fn sanitizeAlloc(self: *State, input: []const u8) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        for (input) |byte| {
            if (byte == '\n' or byte == '\t' or byte >= 0x20) {
                if (byte == 0x7f or byte == 0x1b) continue;
                try out.append(self.gpa, byte);
            }
        }
        return try out.toOwnedSlice(self.gpa);
    }

    fn appendLine(self: *State, out: *std.ArrayList(u8), text: []const u8) !void {
        try out.appendSlice(self.gpa, text);
        try out.append(self.gpa, '\n');
    }

    fn appendClippedLine(self: *State, out: *std.ArrayList(u8), text: []const u8) !void {
        const clipped = try terminal_text.truncateAlloc(self.gpa, text, self.terminal_width, .{ .ellipsis = "…", .reset_style = true });
        defer self.gpa.free(clipped);
        try self.appendLine(out, clipped);
    }

    fn appendFormattedClipped(self: *State, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
        const line = try std.fmt.allocPrint(self.gpa, fmt, args);
        defer self.gpa.free(line);
        try self.appendClippedLine(out, line);
    }

    fn hyperlinkAlloc(self: *State, url: []const u8, label: ?[]const u8) ![]u8 {
        const safe_url = try self.sanitizeAlloc(url);
        defer self.gpa.free(safe_url);
        const visible = label orelse url;
        const safe_visible = try self.sanitizeAlloc(visible);
        defer self.gpa.free(safe_visible);
        return std.fmt.allocPrint(self.gpa, "\x1b]8;;{s}\x07{s}\x1b]8;;\x07", .{ safe_url, safe_visible });
    }

    fn renderLocked(self: *State) ![]u8 {
        const dimensions = terminal.terminalDimensions(self.environ, .{ .columns = 100, .rows = 30 });
        self.terminal_width = @max(@as(usize, 20), dimensions.columns);
        self.terminal_rows = @max(@as(usize, 8), dimensions.rows);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        try out.appendSlice(self.gpa, terminal.clear_screen);

        const header = try std.fmt.allocPrint(self.gpa, "{s}{s}{s}  {s}{s}{s}", .{ bold, self.title, reset, dim, self.provider, reset });
        defer self.gpa.free(header);
        try self.appendClippedLine(&out, header);
        try self.appendLine(&out, "");

        switch (self.stage) {
            .starting => try self.appendClippedLine(&out, dim ++ "Preparing authentication…" ++ reset),
            .auth_url => {
                try self.appendClippedLine(&out, "Open this link to continue:");
                if (self.url) |url| {
                    const linked = try self.hyperlinkAlloc(url, null);
                    defer self.gpa.free(linked);
                    try self.appendFormattedClipped(&out, "{s}{s}{s}", .{ accent, linked, reset });
                    try self.appendClippedLine(&out, dim ++ "Ctrl+click (Cmd+click on macOS) or copy the URL into a browser." ++ reset);
                }
                if (self.instructions) |instructions| {
                    try self.appendLine(&out, "");
                    const safe = try self.sanitizeAlloc(instructions);
                    defer self.gpa.free(safe);
                    try self.appendFormattedClipped(&out, "{s}{s}{s}", .{ warning, safe, reset });
                }
            },
            .device_code => {
                try self.appendClippedLine(&out, "Authorize this device:");
                if (self.url) |url| {
                    const linked = try self.hyperlinkAlloc(url, null);
                    defer self.gpa.free(linked);
                    try self.appendFormattedClipped(&out, "{s}{s}{s}", .{ accent, linked, reset });
                }
                try self.appendLine(&out, "");
                if (self.user_code) |code| {
                    const safe = try self.sanitizeAlloc(code);
                    defer self.gpa.free(safe);
                    const line = try std.fmt.allocPrint(self.gpa, "{s}Enter code: {s}{s}", .{ warning ++ bold, safe, reset });
                    defer self.gpa.free(line);
                    try self.appendClippedLine(&out, line);
                }
                if (self.instructions) |instructions| {
                    const safe = try self.sanitizeAlloc(instructions);
                    defer self.gpa.free(safe);
                    try self.appendFormattedClipped(&out, "{s}{s}{s}", .{ dim, safe, reset });
                }
            },
            .info => {
                if (self.message) |message| {
                    const safe = try self.sanitizeAlloc(message);
                    defer self.gpa.free(safe);
                    try self.appendClippedLine(&out, safe);
                }
                for (self.links.items) |line| try self.appendFormattedClipped(&out, "{s}{s}{s}", .{ accent, line, reset });
            },
            .waiting => {
                const frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
                const elapsed_ms = @max(@as(i64, 0), std.Io.Clock.awake.now(self.io).toMilliseconds() - self.started_ms);
                const message = self.message orelse "Waiting for authorization…";
                const safe = try self.sanitizeAlloc(message);
                defer self.gpa.free(safe);
                const line = try std.fmt.allocPrint(self.gpa, "{s}{s}{s} {s}  {s}({d}s){s}", .{ accent, frames[self.spinner % frames.len], reset, safe, dim, @divFloor(elapsed_ms, 1000), reset });
                defer self.gpa.free(line);
                try self.appendClippedLine(&out, line);
            },
            .prompt => {
                if (self.message) |message| {
                    const safe = try self.sanitizeAlloc(message);
                    defer self.gpa.free(safe);
                    try self.appendClippedLine(&out, safe);
                }
                if (self.placeholder) |placeholder| {
                    const safe = try self.sanitizeAlloc(placeholder);
                    defer self.gpa.free(safe);
                    try self.appendFormattedClipped(&out, "{s}Example: {s}{s}", .{ dim, safe, reset });
                }
                try self.appendLine(&out, "");
                if (self.prompt_secret) {
                    const count = @min(self.input.items.len, self.terminal_width -| 4);
                    const stars = try self.gpa.alloc(u8, count);
                    defer self.gpa.free(stars);
                    @memset(stars, '*');
                    const line = try std.fmt.allocPrint(self.gpa, "> {s}_", .{stars});
                    defer self.gpa.free(line);
                    try self.appendClippedLine(&out, line);
                } else {
                    const safe = try self.sanitizeAlloc(self.input.items);
                    defer self.gpa.free(safe);
                    const line = try std.fmt.allocPrint(self.gpa, "> {s}_", .{safe});
                    defer self.gpa.free(line);
                    try self.appendClippedLine(&out, line);
                }
                try self.appendClippedLine(&out, dim ++ "Enter submit · Esc cancel" ++ reset);
            },
            .complete => {
                const message = self.message orelse "Authentication complete.";
                const safe = try self.sanitizeAlloc(message);
                defer self.gpa.free(safe);
                const color = if (self.isAborted()) failure else success;
                try self.appendFormattedClipped(&out, "{s}{s}{s}", .{ color, safe, reset });
            },
        }

        if (self.progress.items.len > 0) {
            try self.appendLine(&out, "");
            const max_lines: usize = @min(self.progress.items.len, @max(@as(usize, 1), self.terminal_rows -| 10));
            const start = self.progress.items.len - max_lines;
            for (self.progress.items[start..]) |message| {
                const safe = try self.sanitizeAlloc(message);
                defer self.gpa.free(safe);
                try self.appendFormattedClipped(&out, "{s}• {s}{s}", .{ dim, safe, reset });
            }
        }

        if (self.stage != .complete and self.stage != .prompt) {
            try self.appendLine(&out, "");
            try self.appendClippedLine(&out, dim ++ "Esc or Ctrl+C cancels this login." ++ reset);
        }
        return try out.toOwnedSlice(self.gpa);
    }

    fn paintLocked(self: *State) !void {
        const frame = try self.renderLocked();
        defer self.gpa.free(frame);
        try tui_render.writeAll(self.io, frame);
    }

    fn repaint(self: *State) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.paintLocked() catch |err| {
            self.paint_error = err;
            self.setAbort();
        };
    }

    fn popUtf8(input: *std.ArrayList(u8)) void {
        if (input.items.len == 0) return;
        var index = input.items.len - 1;
        while (index > 0 and (input.items[index] & 0xc0) == 0x80) : (index -= 1) {}
        @memset(input.items[index..], 0);
        input.shrinkRetainingCapacity(index);
    }

    fn handleKeyLocked(self: *State, key: terminal.Key) !void {
        switch (key) {
            .escape, .ctrl_c, .ctrl_d => self.setAbort(),
            .enter => {
                if (self.stage == .prompt) self.prompt_submitted = true;
            },
            .backspace => if (self.stage == .prompt) popUtf8(&self.input),
            .delete => if (self.stage == .prompt) {
                @memset(self.input.items, 0);
                self.input.clearRetainingCapacity();
            },
            .text => |byte| if (self.stage == .prompt and byte >= 0x20 and self.input.items.len < 64 * 1024) try self.input.append(self.gpa, byte),
            else => {},
        }
    }

    fn handleInputLocked(self: *State, data: []const u8) !void {
        if (std.mem.eql(u8, data, "\x1b")) {
            self.setAbort();
            return;
        }
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                const byte = data[offset];
                if (self.stage == .prompt and byte >= 0x20 and byte != 0x7f and self.input.items.len < 64 * 1024)
                    try self.input.append(self.gpa, byte);
                offset += 1;
                continue;
            };
            try self.handleKeyLocked(decoded.key);
            offset += decoded.consumed;
        }
    }

    fn readInputChunk(self: *State, buffer: []u8) !usize {
        if (self.reader) |buffered| {
            const available = buffered.interface.bufferedLen();
            if (available > 0) {
                const count = @min(available, buffer.len);
                const source = try buffered.interface.take(count);
                @memcpy(buffer[0..count], source);
                return count;
            }
        }
        var slices = [_][]u8{buffer};
        return Io.File.stdin().readStreaming(self.io, &slices);
    }

    fn inputTask(self: *State) error{Canceled}!void {
        var buffer: [4096]u8 = undefined;
        while (true) {
            if (@atomicLoad(bool, &self.stop, .acquire)) return;
            const count = self.readInputChunk(buffer[0..]) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                error.EndOfStream => {
                    self.mutex.lockUncancelable(self.io);
                    self.setAbort();
                    self.mutex.unlock(self.io);
                    return;
                },
                else => {
                    self.mutex.lockUncancelable(self.io);
                    self.paint_error = err;
                    self.setAbort();
                    self.mutex.unlock(self.io);
                    return;
                },
            };
            if (count == 0) continue;
            self.mutex.lockUncancelable(self.io);
            self.handleInputLocked(buffer[0..count]) catch |err| {
                self.paint_error = err;
            };
            self.paintLocked() catch |err| {
                self.paint_error = err;
            };
            self.mutex.unlock(self.io);
        }
    }

    fn tickerTask(self: *State) error{Canceled}!void {
        while (true) {
            const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(120), .clock = .real } };
            timeout.sleep(self.io) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                else => return,
            };
            if (@atomicLoad(bool, &self.stop, .acquire)) return;
            self.mutex.lockUncancelable(self.io);
            self.spinner +%= 1;
            if (self.stage == .waiting or self.stage == .auth_url or self.stage == .device_code) {
                self.paintLocked() catch |err| {
                    self.paint_error = err;
                };
            }
            self.mutex.unlock(self.io);
        }
    }
};

pub const Controller = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    already_fullscreen: bool,
    state: ?*State = null,
    raw: ?line_editor.RawMode = null,

    pub fn init(
        gpa: std.mem.Allocator,
        io: Io,
        environ: *const std.process.Environ.Map,
        reader: ?*Io.File.Reader,
        already_fullscreen: bool,
    ) Controller {
        return .{ .gpa = gpa, .io = io, .environ = environ, .reader = reader, .already_fullscreen = already_fullscreen };
    }

    pub fn deinit(self: *Controller) void {
        self.close();
        self.* = undefined;
    }

    pub fn begin(self: *Controller, provider: []const u8, title: []const u8) !void {
        self.close();
        if (!terminal.supportsFullscreen(self.io)) return error.UnsupportedTerminal;
        const state = try self.gpa.create(State);
        errdefer self.gpa.destroy(state);
        state.* = try State.init(self.gpa, self.io, self.environ, self.reader, provider, title);
        errdefer state.deinit();
        self.raw = try line_editor.RawMode.enter();
        errdefer {
            if (self.raw) |*raw| raw.leave();
            self.raw = null;
        }
        if (self.already_fullscreen) {
            try tui_render.writeAll(self.io, terminal.clear_screen ++ terminal.hide_cursor ++ terminal.bracketed_paste_enable ++ application.mouse_enable);
        } else {
            try tui_render.writeAll(self.io, application.enter_sequence);
        }
        self.state = state;
        state.mutex.lockUncancelable(state.io);
        state.paintLocked() catch |err| {
            state.mutex.unlock(state.io);
            return err;
        };
        state.mutex.unlock(state.io);
        state.group.async(self.io, State.inputTask, .{state});
        state.group.async(self.io, State.tickerTask, .{state});
    }

    pub fn close(self: *Controller) void {
        const state = self.state orelse return;
        @atomicStore(bool, &state.stop, true, .release);
        @atomicStore(bool, &state.abort_flag, true, .release);
        state.group.cancel(self.io);
        if (self.already_fullscreen) {
            tui_render.writeAll(self.io, application.mouse_disable ++ terminal.bracketed_paste_disable ++ terminal.show_cursor ++ terminal.clear_screen) catch {};
        } else {
            tui_render.writeAll(self.io, application.leave_sequence) catch {};
        }
        if (self.raw) |*raw| raw.leave();
        self.raw = null;
        state.deinit();
        self.gpa.destroy(state);
        self.state = null;
    }

    pub fn abortFlag(self: *Controller) ?*const bool {
        const state = self.state orelse return null;
        return &state.abort_flag;
    }

    pub fn cancelled(self: *Controller) bool {
        const state = self.state orelse return false;
        return state.isAborted();
    }

    pub fn showAuth(self: *Controller, url: []const u8, instructions: ?[]const u8) !void {
        const state = self.state orelse return error.AuthenticationDialogNotStarted;
        state.mutex.lockUncancelable(state.io);
        defer state.mutex.unlock(state.io);
        state.resetContent();
        state.stage = .auth_url;
        try state.replace(&state.url, url);
        try state.replace(&state.instructions, instructions);
        try state.paintLocked();
    }

    pub fn showDeviceCode(self: *Controller, info: DeviceCode) !void {
        const state = self.state orelse return error.AuthenticationDialogNotStarted;
        state.mutex.lockUncancelable(state.io);
        defer state.mutex.unlock(state.io);
        state.resetContent();
        state.stage = .device_code;
        try state.replace(&state.url, info.verification_uri);
        try state.replace(&state.user_code, info.user_code);
        var detail: ?[]u8 = null;
        defer if (detail) |value| self.gpa.free(value);
        if (info.interval_seconds != null or info.expires_in_seconds != null) {
            detail = if (info.instructions) |instructions|
                try std.fmt.allocPrint(self.gpa, "{s} · polling every {d}s · expires in {d}s", .{ instructions, info.interval_seconds orelse 0, info.expires_in_seconds orelse 0 })
            else
                try std.fmt.allocPrint(self.gpa, "Polling every {d}s · expires in {d}s", .{ info.interval_seconds orelse 0, info.expires_in_seconds orelse 0 });
            try state.replace(&state.instructions, detail);
        } else {
            try state.replace(&state.instructions, info.instructions);
        }
        try state.paintLocked();
    }

    pub fn showInfo(self: *Controller, message: []const u8, links: []const Link) !void {
        const state = self.state orelse return error.AuthenticationDialogNotStarted;
        state.mutex.lockUncancelable(state.io);
        defer state.mutex.unlock(state.io);
        state.resetContent();
        state.stage = .info;
        try state.replace(&state.message, message);
        for (links) |link| {
            const linked = try state.hyperlinkAlloc(link.url, link.label);
            try state.links.append(state.gpa, linked);
        }
        try state.paintLocked();
    }

    pub fn showWaiting(self: *Controller, message: []const u8) !void {
        const state = self.state orelse return error.AuthenticationDialogNotStarted;
        state.mutex.lockUncancelable(state.io);
        defer state.mutex.unlock(state.io);
        state.stage = .waiting;
        try state.replace(&state.message, message);
        try state.paintLocked();
    }

    pub fn showProgress(self: *Controller, message: []const u8) !void {
        const state = self.state orelse return error.AuthenticationDialogNotStarted;
        state.mutex.lockUncancelable(state.io);
        defer state.mutex.unlock(state.io);
        const owned = try state.gpa.dupe(u8, message);
        if (state.progress.items.len >= 16) {
            state.gpa.free(state.progress.items[0]);
            _ = state.progress.orderedRemove(0);
        }
        try state.progress.append(state.gpa, owned);
        try state.paintLocked();
    }

    pub fn prompt(self: *Controller, message: []const u8, placeholder: ?[]const u8, secret: bool) ![]u8 {
        const state = self.state orelse return error.AuthenticationDialogNotStarted;
        state.mutex.lockUncancelable(state.io);
        state.stage = .prompt;
        try state.replace(&state.message, message);
        try state.replace(&state.placeholder, placeholder);
        @memset(state.input.items, 0);
        state.input.clearRetainingCapacity();
        state.prompt_secret = secret;
        state.prompt_submitted = false;
        try state.paintLocked();
        state.mutex.unlock(state.io);

        while (true) {
            if (state.isAborted()) return error.LoginCancelled;
            state.mutex.lockUncancelable(state.io);
            if (state.paint_error) |err| {
                state.mutex.unlock(state.io);
                return err;
            }
            if (state.prompt_submitted) {
                const result = try self.gpa.dupe(u8, std.mem.trim(u8, state.input.items, " \t\r\n"));
                @memset(state.input.items, 0);
                state.input.clearRetainingCapacity();
                state.prompt_submitted = false;
                state.stage = .waiting;
                try state.replace(&state.message, "Continuing authentication…");
                state.paintLocked() catch {};
                state.mutex.unlock(state.io);
                return result;
            }
            state.mutex.unlock(state.io);
            const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .real } };
            timeout.sleep(self.io) catch return error.LoginCancelled;
        }
    }

    pub fn finish(self: *Controller, ok: bool, message: []const u8) void {
        const state = self.state orelse return;
        state.mutex.lockUncancelable(state.io);
        state.stage = .complete;
        if (!ok) @atomicStore(bool, &state.abort_flag, true, .release);
        state.replace(&state.message, message) catch {};
        state.paintLocked() catch {};
        state.mutex.unlock(state.io);
        const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(180), .clock = .real } };
        timeout.sleep(self.io) catch {};
        self.close();
    }
};

test "auth flow dialog accepts manual input and cancellation state" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var state = try State.init(gpa, io, &env, null, "anthropic", "Login to Anthropic");
    defer state.deinit();
    state.stage = .prompt;
    try state.handleInputLocked("code-179");
    try state.handleInputLocked("\r");
    try std.testing.expect(state.prompt_submitted);
    try std.testing.expectEqualStrings("code-179", state.input.items);
    state.prompt_submitted = false;
    try state.handleInputLocked("\x1b");
    try std.testing.expect(state.isAborted());
}

test "auth flow dialog renders OSC 8 links without raw control injection" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var state = try State.init(gpa, io, &env, null, "provider", "Login");
    defer state.deinit();
    state.stage = .auth_url;
    try state.replace(&state.url, "https://example.test/auth\x1b[2J");
    const frame = try state.renderLocked();
    defer gpa.free(frame);
    try std.testing.expect(std.mem.indexOf(u8, frame, "https://example.test/auth") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame, "\x1b[2J\x1b[2J") == null);
}

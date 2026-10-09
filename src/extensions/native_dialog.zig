//! Native state and stdin lease for Source extension selector/input dialogs.
const std = @import("std");
const Io = std.Io;
const keybindings = @import("../tui/keybindings.zig");
const line_editor = @import("../tui/line_editor.zig");
const terminal = @import("../tui/terminal.zig");
const platform = @import("../tui/platform_terminal.zig");
const render = @import("../tui/render.zig");
const widgets = @import("../tui/widgets.zig");
const markers = @import("../tui/cursor_markers.zig");

pub const Kind = enum { select, input };
pub const Model = struct {
    kind: Kind,
    options: []const []const u8,
    input: widgets.Input,
    bindings: ?*const keybindings.Manager = null,
    selected: usize = 0,
    done: bool = false,
    cancelled: bool = false,

    pub fn init(gpa: std.mem.Allocator, kind: Kind, options: []const []const u8, bindings: ?*const keybindings.Manager) Model {
        return .{ .kind = kind, .options = options, .input = widgets.Input.init(gpa), .bindings = bindings };
    }
    pub fn deinit(self: *Model) void {
        self.input.deinit();
    }
    fn matches(self: *const Model, action: []const u8, sequence: []const u8) bool {
        const defaults = keybindings.Manager.init(self.input.gpa);
        return (self.bindings orelse &defaults).matchesActionName(action, sequence);
    }
    pub fn handle(self: *Model, sequence: []const u8, paste: bool) !void {
        if (self.done) return;
        if (paste) {
            if (self.kind == .input) {
                try self.input.insertPaste(sequence);
            }
            return;
        }
        if (self.kind == .select) {
            if (self.matches("tui.select.up", sequence) or std.mem.eql(u8, sequence, "k")) {
                self.selected -|= 1;
            } else if (self.matches("tui.select.down", sequence) or std.mem.eql(u8, sequence, "j")) {
                self.selected = @min(self.options.len -| 1, self.selected +| 1);
            } else if (self.matches("tui.select.confirm", sequence) or std.mem.eql(u8, sequence, "\n")) {
                if (self.selected < self.options.len and self.options[self.selected].len > 0) self.done = true;
            } else if (self.matches("tui.select.cancel", sequence)) {
                self.done = true;
                self.cancelled = true;
            }
        } else if (self.matches("tui.select.confirm", sequence) or std.mem.eql(u8, sequence, "\n")) {
            self.done = true;
        } else if (self.matches("tui.select.cancel", sequence)) {
            self.done = true;
            self.cancelled = true;
        } else try self.input.handleInput(sequence);
    }
};

fn paint(gpa: std.mem.Allocator, io: Io, model: *Model, title: []const u8, previous_rows: *usize) !void {
    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    if (previous_rows.* > 0) try out.writer.print("\x1b[{d}A", .{previous_rows.*});
    try out.writer.writeAll("\r\x1b[J");
    var rows: usize = 0;
    var titles = std.mem.splitScalar(u8, title, '\n');
    while (titles.next()) |line| {
        try out.writer.print(" {s}\r\n", .{line});
        rows += 1;
    }
    try out.writer.writeAll("\r\n");
    rows += 1;
    if (model.kind == .select) {
        for (model.options, 0..) |option, index| {
            try out.writer.print(" {s}{s}\r\n", .{ if (model.selected == index) "→ " else "  ", option });
            rows += 1;
        }
        try out.writer.writeAll(" ↑↓ navigate  enter select  esc cancel\r\n");
    } else {
        var lines = try model.input.component().render(gpa, 80);
        defer lines.deinit(gpa);
        for (lines.items) |line| {
            const resolved = try markers.resolveAlloc(gpa, line, false);
            defer gpa.free(resolved);
            try out.writer.print(" {s}\r\n", .{resolved});
            rows += 1;
        }
        try out.writer.writeAll(" enter submit  esc cancel\r\n");
    }
    rows += 1;
    previous_rows.* = rows;
    try render.writeAll(io, out.written());
}

const Intake = struct {
    decoder: line_editor.InputDecoder,
    last_byte_ms: ?i64 = null,
    fn init(gpa: std.mem.Allocator) Intake {
        return .{ .decoder = .init(gpa) };
    }
    fn deinit(self: *Intake) void {
        self.decoder.deinit();
    }
    fn feed(self: *Intake, byte: u8, now_ms: i64) !?line_editor.InputDecoder.Input {
        const packet = try self.decoder.feed(byte);
        self.last_byte_ms = if (packet == null) now_ms else null;
        return packet;
    }
    fn waitMs(self: *const Intake, now_ms: i64) u32 {
        const timeout = self.decoder.pendingTimeoutMs();
        if (self.decoder.paste) return @intCast(timeout);
        const last = self.last_byte_ms orelse return @intCast(timeout);
        const elapsed = @max(0, now_ms -| last);
        return @intCast(@max(0, timeout -| elapsed));
    }
    fn wake(self: *Intake, now_ms: i64) ?line_editor.InputDecoder.Input {
        // Win32 notification records and interrupted POSIX polls can wake
        // readiness early. Source expires elapsed idle time, not each wake.
        if (self.decoder.paste or self.last_byte_ms == null or self.waitMs(now_ms) != 0) return null;
        self.last_byte_ms = null;
        return self.decoder.flushPending();
    }
};

pub fn run(gpa: std.mem.Allocator, io: Io, reader: *Io.File.Reader, model: *Model, title: []const u8) !void {
    var raw = try line_editor.RawMode.enter();
    defer raw.leave();
    errdefer |err| if (err == error.DeadTerminal) {
        raw.restore = false;
    };
    try render.writeAll(io, terminal.hide_cursor ++ terminal.bracketed_paste_enable);
    defer if (raw.restore) render.writeAll(io, terminal.bracketed_paste_disable ++ terminal.show_cursor) catch {};
    var intake = Intake.init(gpa);
    defer intake.deinit();
    var rows: usize = 0;
    try paint(gpa, io, model, title, &rows);
    while (!model.done) {
        // Native readiness waits have a bounded deadline but are outside Io's
        // task scheduler. Admit the dialog broker's signal/timeout cancellation
        // before every wait so a quiet terminal cannot retain the stdin lease.
        try io.checkCancel();
        const ready = if (platform.inputBuffered(reader)) platform.Ready.input else try platform.waitInput(intake.waitMs(Io.Clock.awake.now(io).toMilliseconds()));
        if (ready == .dead) return error.DeadTerminal;
        if (ready == .input) {
            const byte = try platform.readByte(reader);
            if (try intake.feed(byte, Io.Clock.awake.now(io).toMilliseconds())) |event| {
                try model.handle(switch (event) {
                    .key, .paste => |data| data,
                }, event == .paste);
                if (!model.done) try paint(gpa, io, model, title, &rows);
            }
        } else if (intake.wake(Io.Clock.awake.now(io).toMilliseconds())) |event| {
            try model.handle(switch (event) {
                .key, .paste => |data| data,
            }, event == .paste);
            if (!model.done) try paint(gpa, io, model, title, &rows);
        }
    }
}

test "native dialog selector and input match actual Source1ced callback traces" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/dialog-original-1ced.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const kind: Kind = if (std.mem.eql(u8, item.object.get("kind").?.string, "select")) .select else .input;
        var model = Model.init(std.testing.allocator, kind, &.{ "Yes", "No" }, null);
        defer model.deinit();
        for (item.object.get("keys").?.array.items, item.object.get("states").?.array.items) |key, state| {
            try model.handle(key.string, false);
            if (kind == .select) try std.testing.expectEqual(@as(usize, @intCast(state.object.get("selected").?.integer)), model.selected) else try std.testing.expectEqualStrings(state.object.get("value").?.string, model.input.editor.slice());
            const expected = state.object.get("result").?;
            try std.testing.expectEqual(expected != .null, model.done);
            if (model.done) {
                try std.testing.expectEqual(expected == .bool, model.cancelled);
                if (expected == .string) try std.testing.expectEqualStrings(expected.string, if (kind == .select) model.options[model.selected] else model.input.editor.slice());
            }
        }
    }
}

fn capturePacket(gpa: std.mem.Allocator, model: *Model, events: *std.ArrayList([]u8), packet: line_editor.InputDecoder.Input) !void {
    const data = switch (packet) {
        .key, .paste => |value| value,
    };
    const owned = try gpa.dupe(u8, data);
    events.append(gpa, owned) catch |err| {
        gpa.free(owned);
        return err;
    };
    try model.handle(data, packet == .paste);
}
test "native dialog Source CSI fragmentation ignores early readiness wakes and honors actual escape deadlines" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/dialog-fragment-deadline-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |item| {
        var intake = Intake.init(gpa);
        defer intake.deinit();
        var model = Model.init(gpa, .input, &.{}, null);
        defer model.deinit();
        var events: std.ArrayList([]u8) = .empty;
        defer {
            for (events.items) |value| gpa.free(value);
            events.deinit(gpa);
        }
        const steps = item.object.get("steps").?.array.items;
        const snapshots = item.object.get("snapshots").?.array.items;
        for (steps, snapshots) |step, expected| {
            const now_ms = step.object.get("at").?.integer;
            if (intake.wake(now_ms)) |packet| try capturePacket(gpa, &model, &events, packet);
            if (step.object.get("data")) |data| for (data.string) |byte| {
                if (try intake.feed(byte, now_ms)) |packet| try capturePacket(gpa, &model, &events, packet);
            };
            try std.testing.expectEqualStrings(expected.object.get("value").?.string, model.input.editor.slice());
            const prefix = try std.unicode.utf8ToUtf16LeAlloc(gpa, model.input.editor.slice()[0..model.input.editor.cursor]);
            defer gpa.free(prefix);
            try std.testing.expectEqual(expected.object.get("cursor").?.integer, @as(i64, @intCast(prefix.len)));
            try std.testing.expectEqual(expected.object.get("done").?.bool, model.done);
            try std.testing.expectEqual(expected.object.get("cancelled").?.bool, model.cancelled);
            const wanted_events = expected.object.get("events").?.array.items;
            try std.testing.expectEqual(wanted_events.len, events.items.len);
            for (wanted_events, events.items) |wanted, actual| try std.testing.expectEqualStrings(wanted.string, actual);
        }
    }
}

test "native dialog borrowed registry overrides confirm navigation cancellation and empty disabling" {
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    bindings.parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"tui.select.down\":\"ctrl+n\",\"tui.select.confirm\":\"ctrl+y\",\"tui.select.cancel\":[]}", .{});
    var model = Model.init(std.testing.allocator, .select, &.{ "Yes", "No" }, &bindings);
    defer model.deinit();
    try model.handle("\x1b[B", false);
    try std.testing.expectEqual(@as(usize, 0), model.selected);
    try model.handle("\x1b", false);
    try model.handle("\r", false);
    try std.testing.expect(!model.done);
    try model.handle("\x0e", false);
    try std.testing.expectEqual(@as(usize, 1), model.selected);
    try model.handle("\x19", false);
    try std.testing.expect(model.done and !model.cancelled);
}

fn allocationProbe(gpa: std.mem.Allocator) !void {
    var model = Model.init(gpa, .input, &.{}, null);
    defer model.deinit();
    try model.handle("a", false);
    try model.handle("界", false);
    try model.handle("multi\r\nline", true);
    try model.handle("\x1b[D", false);
    try model.handle("\x7f", false);
    var lines = try model.input.component().render(gpa, 8);
    defer lines.deinit(gpa);
    try markers.resolveLines(gpa, lines.items, false);
}
test "native dialog state paste editor and fake cursor release failed allocation boundaries" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

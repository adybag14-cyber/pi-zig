//! Searchable fullscreen `/thinking` selector with session-only Enter and
//! explicit global-default persistence through Ctrl+S.
const std = @import("std");
const Io = std.Io;
const thinking = @import("../ai/thinking.zig");
const application = @import("../tui/application.zig");
const layout = @import("../tui/layout.zig");
const line_editor = @import("../tui/line_editor.zig");
const mouse = @import("../tui/mouse.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const tui_render = @import("../tui/render.zig");

const accent = "\x1b[36m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reverse = "\x1b[7m";
const reset = "\x1b[0m";

pub const Selection = struct {
    level: ?thinking.ThinkingLevel = null,
    cancelled: bool = true,
    persist_default: bool = false,
};

fn description(level: thinking.ThinkingLevel) []const u8 {
    return switch (level) {
        .off => "No reasoning",
        .minimal => "Very brief reasoning (~1k tokens)",
        .low => "Light reasoning (~2k tokens)",
        .medium => "Moderate reasoning (~8k tokens)",
        .high => "Deep reasoning (~16k tokens)",
        .xhigh => "Extra-high reasoning (~32k tokens)",
        .max => "Maximum reasoning",
    };
}

const Selector = struct {
    gpa: std.mem.Allocator,
    levels: []const thinking.ThinkingLevel,
    current: thinking.ThinkingLevel,
    default_level: ?thinking.ThinkingLevel,
    visible: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    selected: usize = 0,
    done: bool = false,
    result: Selection = .{},

    fn init(
        gpa: std.mem.Allocator,
        levels: []const thinking.ThinkingLevel,
        current: thinking.ThinkingLevel,
        default_level: ?thinking.ThinkingLevel,
        initial_query: ?[]const u8,
    ) !Selector {
        var self = Selector{ .gpa = gpa, .levels = levels, .current = current, .default_level = default_level };
        errdefer self.deinit();
        if (initial_query) |query| try self.query.appendSlice(gpa, query);
        try self.rebuildVisible();
        return self;
    }

    fn deinit(self: *Selector) void {
        self.visible.deinit(self.gpa);
        self.query.deinit(self.gpa);
        self.* = undefined;
    }

    fn component(self: *Selector) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    const vtable: layout.Component.VTable = .{
        .render = renderCallback,
        .handle_input = inputCallback,
        .handle_mouse = mouseCallback,
        .set_focus = focusCallback,
    };

    fn renderCallback(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Selector = @ptrCast(@alignCast(raw));
        return self.render(gpa, width);
    }

    fn inputCallback(raw: *anyopaque, data: []const u8) !void {
        const self: *Selector = @ptrCast(@alignCast(raw));
        try self.handleInput(data);
    }

    fn mouseCallback(raw: *anyopaque, event: mouse.Event) !bool {
        const self: *Selector = @ptrCast(@alignCast(raw));
        return self.handleMouse(event);
    }

    fn focusCallback(_: *anyopaque, _: bool) void {}

    fn matches(self: *const Selector, level: thinking.ThinkingLevel) bool {
        if (self.query.items.len == 0) return true;
        return std.ascii.indexOfIgnoreCase(@tagName(level), self.query.items) != null or
            std.ascii.indexOfIgnoreCase(description(level), self.query.items) != null or
            (self.default_level != null and self.default_level.? == level and std.ascii.indexOfIgnoreCase("default", self.query.items) != null);
    }

    fn rebuildVisible(self: *Selector) !void {
        self.visible.clearRetainingCapacity();
        for (self.levels, 0..) |level, index| if (self.matches(level)) try self.visible.append(self.gpa, index);
        if (self.visible.items.len == 0) {
            self.selected = 0;
            return;
        }
        for (self.visible.items, 0..) |level_index, visible_index| {
            if (self.levels[level_index] == self.current) {
                self.selected = visible_index;
                return;
            }
        }
        self.selected = @min(self.selected, self.visible.items.len - 1);
    }

    fn move(self: *Selector, delta: isize) void {
        if (self.visible.items.len == 0) return;
        if (delta < 0) self.selected = if (self.selected == 0) self.visible.items.len - 1 else self.selected - 1 else if (delta > 0) self.selected = (self.selected + 1) % self.visible.items.len;
    }

    fn select(self: *Selector, persist: bool) void {
        if (self.selected >= self.visible.items.len) return;
        self.result = .{ .level = self.levels[self.visible.items[self.selected]], .cancelled = false, .persist_default = persist };
        self.done = true;
    }

    fn popUtf8(list: *std.ArrayList(u8)) void {
        if (list.items.len == 0) return;
        var index = list.items.len - 1;
        while (index > 0 and (list.items[index] & 0xc0) == 0x80) : (index -= 1) {}
        list.shrinkRetainingCapacity(index);
    }

    fn handleInput(self: *Selector, data: []const u8) !void {
        if (std.mem.eql(u8, data, "\x13")) {
            self.select(true);
            return;
        }
        if (std.mem.eql(u8, data, "\x1b")) {
            if (self.query.items.len > 0) {
                self.query.clearRetainingCapacity();
                try self.rebuildVisible();
            } else {
                self.done = true;
            }
            return;
        }
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                offset += 1;
                continue;
            };
            switch (decoded.key) {
                .up => self.move(-1),
                .down => self.move(1),
                .home => self.selected = 0,
                .end => if (self.visible.items.len > 0) {
                    self.selected = self.visible.items.len - 1;
                },
                .enter => self.select(false),
                .escape => self.done = true,
                .ctrl_c, .ctrl_d => self.done = true,
                .backspace => if (self.query.items.len > 0) {
                    popUtf8(&self.query);
                    try self.rebuildVisible();
                },
                .text => |byte| if (byte >= 0x20) {
                    try self.query.append(self.gpa, byte);
                    try self.rebuildVisible();
                },
                else => {},
            }
            offset += decoded.consumed;
        }
    }

    fn handleMouse(self: *Selector, event: mouse.Event) bool {
        if (event.kind == .scroll) {
            if (event.button == .wheel_up) self.move(-1) else if (event.button == .wheel_down) self.move(1) else return false;
            return true;
        }
        if (event.kind != .press or event.button != .left or event.y < 4) return false;
        const visible_index = event.y - 4;
        if (visible_index >= self.visible.items.len) return false;
        self.selected = visible_index;
        return true;
    }

    fn appendClipped(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), width: usize, owned: []u8) !void {
        defer gpa.free(owned);
        try lines.append(gpa, try terminal_text.truncateAlloc(gpa, owned, width, .{ .ellipsis = "…", .reset_style = true }));
    }

    fn render(self: *Selector, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Thinking Level{s}", .{ bold, reset }));
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Enter selects for this session · Ctrl+S selects and saves default · Esc cancels{s}", .{ dim, reset }));
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Search: {s}{s}_{s}", .{ accent, self.query.items, reset }));
        try lines.append(gpa, try gpa.dupe(u8, ""));
        if (self.visible.items.len == 0) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  No matching thinking levels{s}", .{ dim, reset }));
        } else for (self.visible.items, 0..) |level_index, visible_index| {
            const level = self.levels[level_index];
            const selected = visible_index == self.selected;
            const is_default = self.default_level != null and self.default_level.? == level;
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s} {s:<8}  {s}{s}{s}{s}", .{
                if (selected) reverse else "",
                if (selected) ">" else " ",
                @tagName(level),
                description(level),
                if (is_default) " · default" else "",
                if (level == self.current) " · current" else "",
                reset,
            }));
        }
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }
};

fn readInputChunk(io: Io, reader: ?*Io.File.Reader, buffer: []u8) !usize {
    if (reader) |buffered| {
        const available = buffered.interface.bufferedLen();
        if (available > 0) {
            const count = @min(available, buffer.len);
            const source = try buffered.interface.take(count);
            @memcpy(buffer[0..count], source);
            return count;
        }
    }
    var slices = [_][]u8{buffer};
    return Io.File.stdin().readStreaming(io, &slices);
}

pub fn run(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    levels: []const thinking.ThinkingLevel,
    current: thinking.ThinkingLevel,
    default_level: ?thinking.ThinkingLevel,
    initial_query: ?[]const u8,
    already_fullscreen: bool,
) !Selection {
    if (!terminal.supportsFullscreen(io)) return error.UnsupportedTerminal;
    var selector = try Selector.init(gpa, levels, current, default_level, initial_query);
    defer selector.deinit();
    var app = application.Application.init(gpa, selector.component());
    defer app.deinit();
    app.setFocus(selector.component());
    var raw = try line_editor.RawMode.enter();
    defer raw.leave();
    if (already_fullscreen) {
        try tui_render.writeAll(io, terminal.clear_screen ++ terminal.hide_cursor ++ terminal.bracketed_paste_enable ++ application.mouse_enable);
        defer tui_render.writeAll(io, application.mouse_disable ++ terminal.bracketed_paste_disable ++ terminal.show_cursor ++ terminal.clear_screen) catch {};
    } else {
        try app.start(io);
        defer app.stop(io) catch {};
    }
    var input_buffer: [4096]u8 = undefined;
    while (!selector.done) {
        const dimensions = terminal.terminalDimensions(environ, .{ .columns = 90, .rows = 20 });
        try app.paint(io, dimensions.columns, dimensions.rows);
        const count = readInputChunk(io, reader, &input_buffer) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (count == 0) break;
        try app.handleInput(input_buffer[0..count]);
    }
    return selector.result;
}

test "thinking selector searches and distinguishes session select from Ctrl+S default" {
    const levels = thinking.extended_levels;
    var selector = try Selector.init(std.testing.allocator, &levels, .medium, .high, "extra");
    defer selector.deinit();
    try std.testing.expectEqual(@as(usize, 1), selector.visible.items.len);
    try std.testing.expectEqual(thinking.ThinkingLevel.xhigh, selector.levels[selector.visible.items[0]]);
    try selector.handleInput("\x13");
    try std.testing.expect(selector.result.persist_default);
    try std.testing.expectEqual(thinking.ThinkingLevel.xhigh, selector.result.level.?);
}

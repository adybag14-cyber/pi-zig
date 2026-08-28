//! Alternate-screen application shell with overlays, focus, differential
//! rendering, mouse selection, search, scrolling and IME composition.
const std = @import("std");
const Io = std.Io;
const layout = @import("layout.zig");
const terminal = @import("terminal.zig");
const terminal_text = @import("terminal_text.zig");
const osc52 = @import("osc52.zig");
const mouse = @import("mouse.zig");
const widgets = @import("widgets.zig");

pub const mouse_enable = "\x1b[?1000h\x1b[?1002h\x1b[?1006h";
pub const mouse_disable = "\x1b[?1006l\x1b[?1002l\x1b[?1000l";
pub const synchronized_begin = "\x1b[?2026h";
pub const synchronized_end = "\x1b[?2026l";
pub const enter_sequence = terminal.alternate_screen_enter ++ terminal.hide_cursor ++ terminal.bracketed_paste_enable ++ mouse_enable;
pub const leave_sequence = mouse_disable ++ terminal.bracketed_paste_disable ++ terminal.show_cursor ++ terminal.alternate_screen_leave;

pub const CursorPosition = struct {
    row: usize,
    column: usize,
};

pub const Point = struct {
    row: usize,
    column: usize,
};

pub const Selection = struct {
    anchor: Point,
    focus: Point,
    dragging: bool = false,

    pub fn normalized(self: Selection) struct { start: Point, end: Point } {
        if (self.anchor.row < self.focus.row or
            (self.anchor.row == self.focus.row and self.anchor.column <= self.focus.column))
        {
            return .{ .start = self.anchor, .end = self.focus };
        }
        return .{ .start = self.focus, .end = self.anchor };
    }
};

pub const SearchMatch = struct {
    row: usize,
    start_column: usize,
    end_column: usize,
};

pub const SearchState = struct {
    gpa: std.mem.Allocator,
    query: std.ArrayList(u8) = .empty,
    matches: std.ArrayList(SearchMatch) = .empty,
    active: usize = 0,

    pub fn init(gpa: std.mem.Allocator) SearchState {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *SearchState) void {
        self.query.deinit(self.gpa);
        self.matches.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn setQuery(self: *SearchState, value: []const u8) !void {
        self.query.clearRetainingCapacity();
        try self.query.appendSlice(self.gpa, value);
        self.matches.clearRetainingCapacity();
        self.active = 0;
    }

    pub fn clear(self: *SearchState) void {
        self.query.clearRetainingCapacity();
        self.matches.clearRetainingCapacity();
        self.active = 0;
    }

    pub fn next(self: *SearchState) ?SearchMatch {
        if (self.matches.items.len == 0) return null;
        self.active = (self.active + 1) % self.matches.items.len;
        return self.matches.items[self.active];
    }

    pub fn previous(self: *SearchState) ?SearchMatch {
        if (self.matches.items.len == 0) return null;
        self.active = if (self.active == 0) self.matches.items.len - 1 else self.active - 1;
        return self.matches.items[self.active];
    }

    pub fn current(self: *const SearchState) ?SearchMatch {
        if (self.matches.items.len == 0) return null;
        return self.matches.items[@min(self.active, self.matches.items.len - 1)];
    }
};

pub const CompositionState = struct {
    gpa: std.mem.Allocator,
    active: bool = false,
    preedit: std.ArrayList(u8) = .empty,
    cursor: usize = 0,

    pub fn init(gpa: std.mem.Allocator) CompositionState {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *CompositionState) void {
        self.preedit.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn begin(self: *CompositionState) void {
        self.active = true;
        self.preedit.clearRetainingCapacity();
        self.cursor = 0;
    }

    pub fn update(self: *CompositionState, value: []const u8, cursor: usize) !void {
        if (!self.active) self.begin();
        self.preedit.clearRetainingCapacity();
        try self.preedit.appendSlice(self.gpa, value);
        self.cursor = @min(cursor, value.len);
    }

    pub fn cancel(self: *CompositionState) void {
        self.active = false;
        self.preedit.clearRetainingCapacity();
        self.cursor = 0;
    }
};

pub const Placement = union(enum) {
    center,
    top_left,
    top_right,
    bottom_left,
    bottom_right,
    absolute: struct { x: isize, y: isize },
};

pub const OverlayOptions = struct {
    width: ?usize = null,
    height: ?usize = null,
    placement: Placement = .center,
    modal: bool = true,
    focus: ?layout.Component = null,
    z_index: i32 = 0,
};

const OverlayEntry = struct {
    id: u64,
    component: layout.Component,
    options: OverlayOptions,
    previous_focus: ?layout.Component,
};

const OverlayFrame = struct {
    id: u64,
    x: isize,
    y: isize,
    frame: layout.LayoutFrame,

    fn deinit(self: *OverlayFrame, gpa: std.mem.Allocator) void {
        self.frame.deinit(gpa);
        self.* = undefined;
    }
};

const Hit = struct {
    component: layout.Component,
    rect: layout.Rect,
    scroll: ?*layout.ScrollView = null,
};

pub const View = struct {
    lines: []const []u8,
    cursor: ?CursorPosition,
    width: usize,
    height: usize,
};

pub const Application = struct {
    gpa: std.mem.Allocator,
    root: layout.Component,
    focused: ?layout.Component = null,
    overlays: std.ArrayList(OverlayEntry) = .empty,
    overlay_frames: std.ArrayList(OverlayFrame) = .empty,
    current_frame: ?layout.LayoutFrame = null,
    painted_lines: layout.RenderedLines = .{},
    current_cursor: ?CursorPosition = null,
    painted_width: usize = 0,
    painted_height: usize = 0,
    next_overlay_id: u64 = 1,
    started: bool = false,
    selection: ?Selection = null,
    search: SearchState,
    composition: CompositionState,
    full_redraw_count: usize = 0,
    incremental_redraw_count: usize = 0,

    pub fn init(gpa: std.mem.Allocator, root: layout.Component) Application {
        return .{
            .gpa = gpa,
            .root = root,
            .search = SearchState.init(gpa),
            .composition = CompositionState.init(gpa),
        };
    }

    pub fn deinit(self: *Application) void {
        if (self.focused) |component| component.setFocus(false);
        self.clearCurrentFrames();
        self.overlay_frames.deinit(self.gpa);
        self.painted_lines.deinit(self.gpa);
        self.overlays.deinit(self.gpa);
        self.search.deinit();
        self.composition.deinit();
        self.* = undefined;
    }

    pub fn start(self: *Application, io: Io) !void {
        if (self.started) return;
        try writeAll(io, enter_sequence);
        self.started = true;
    }

    pub fn stop(self: *Application, io: Io) !void {
        if (!self.started) return;
        try writeAll(io, leave_sequence);
        self.started = false;
    }

    pub fn setFocus(self: *Application, component: ?layout.Component) void {
        if (self.focused) |old| {
            if (component) |new| if (old.eql(new)) return;
            old.setFocus(false);
        }
        self.focused = component;
        if (component) |new| new.setFocus(true);
    }

    pub fn pushOverlay(self: *Application, component: layout.Component, options: OverlayOptions) !u64 {
        const id = self.next_overlay_id;
        self.next_overlay_id +%= 1;
        const previous = self.focused;
        try self.overlays.append(self.gpa, .{
            .id = id,
            .component = component,
            .options = options,
            .previous_focus = previous,
        });
        if (options.focus) |focus| {
            self.setFocus(focus);
        } else if (options.modal) {
            self.setFocus(component);
        }
        return id;
    }

    pub fn removeOverlay(self: *Application, id: u64) bool {
        var index: usize = 0;
        while (index < self.overlays.items.len) : (index += 1) {
            if (self.overlays.items[index].id != id) continue;
            const was_top = index + 1 == self.overlays.items.len;
            const entry = self.overlays.orderedRemove(index);
            if (was_top) self.setFocus(entry.previous_focus);
            return true;
        }
        return false;
    }

    pub fn popOverlay(self: *Application) bool {
        const entry = self.overlays.pop() orelse return false;
        self.setFocus(entry.previous_focus);
        return true;
    }

    pub fn clearOverlays(self: *Application) void {
        while (self.popOverlay()) {}
    }

    pub fn setSearch(self: *Application, query: []const u8) !void {
        try self.search.setQuery(query);
    }

    pub fn nextSearchMatch(self: *Application) ?SearchMatch {
        const match = self.search.next() orelse return null;
        if (self.current_frame) |*frame| if (frame.primary_scroll_view) |scroll| {
            if (match.row < scroll.scroll_top) scroll.scrollTo(match.row, true) else if (match.row >= scroll.scroll_top + scroll.viewport_height) {
                scroll.scrollTo(match.row -| (scroll.viewport_height -| 1), true);
            }
        };
        return match;
    }

    pub fn previousSearchMatch(self: *Application) ?SearchMatch {
        const match = self.search.previous() orelse return null;
        if (self.current_frame) |*frame| if (frame.primary_scroll_view) |scroll| scroll.scrollTo(match.row, true);
        return match;
    }

    pub fn beginComposition(self: *Application) void {
        self.composition.begin();
    }

    pub fn updateComposition(self: *Application, preedit: []const u8, cursor: usize) !void {
        try self.composition.update(preedit, cursor);
    }

    pub fn cancelComposition(self: *Application) void {
        self.composition.cancel();
    }

    pub fn commitComposition(self: *Application, committed: []const u8) !void {
        const target = self.inputTarget() orelse {
            self.composition.cancel();
            return;
        };
        try target.handlePaste(committed);
        self.composition.cancel();
    }

    pub fn handlePaste(self: *Application, data: []const u8) !void {
        if (self.inputTarget()) |target| try target.handlePaste(data);
    }

    pub fn handleInput(self: *Application, data: []const u8) !void {
        if (mouse.parse(data)) |event| {
            try self.handleMouse(event);
            return;
        }
        if (self.inputTarget()) |target| try target.handleInput(data);
    }

    fn inputTarget(self: *const Application) ?layout.Component {
        if (self.overlays.items.len > 0) {
            const top = self.overlays.items[self.overlays.items.len - 1];
            if (top.options.modal) return self.focused orelse top.component;
        }
        return self.focused orelse self.root;
    }

    pub fn handleMouse(self: *Application, event: mouse.Event) !void {
        if (event.kind == .scroll) {
            const delta: isize = switch (event.button) {
                .wheel_up => -3,
                .wheel_down => 3,
                .wheel_left => -1,
                .wheel_right => 1,
                else => 0,
            };
            if (self.scrollAt(event.x, event.y)) |scroll| {
                _ = scroll.scrollBy(delta);
            } else if (self.current_frame) |*frame| if (frame.primary_scroll_view) |scroll| {
                _ = scroll.scrollBy(delta);
            } else if (self.hitAt(event.x, event.y)) |hit| {
                var local = event;
                local.x = @intCast(@max(@as(isize, 0), @as(isize, @intCast(event.x)) - hit.rect.x));
                local.y = @intCast(@max(@as(isize, 0), @as(isize, @intCast(event.y)) - hit.rect.y));
                _ = try hit.component.handleMouse(local);
            };
            return;
        }

        switch (event.kind) {
            .press => if (event.button == .left) {
                if (self.hitAt(event.x, event.y)) |hit| {
                    self.setFocus(hit.component);
                    var local = event;
                    local.x = @intCast(@max(@as(isize, 0), @as(isize, @intCast(event.x)) - hit.rect.x));
                    local.y = @intCast(@max(@as(isize, 0), @as(isize, @intCast(event.y)) - hit.rect.y));
                    if (try hit.component.handleMouse(local)) {
                        self.selection = null;
                        return;
                    }
                }
                self.selection = .{
                    .anchor = .{ .row = event.y, .column = event.x },
                    .focus = .{ .row = event.y, .column = event.x },
                    .dragging = true,
                };
            },
            .drag, .move => if (self.selection) |*selection| if (selection.dragging) {
                selection.focus = .{ .row = event.y, .column = event.x };
            },
            .release => if (self.selection) |*selection| {
                selection.focus = .{ .row = event.y, .column = event.x };
                selection.dragging = false;
            },
            .scroll => unreachable,
        }
    }

    pub fn clearSelection(self: *Application) void {
        self.selection = null;
    }

    pub fn selectedTextAlloc(self: *const Application) !?[]u8 {
        const selection = self.selection orelse return null;
        const frame = self.current_frame orelse return null;
        const bounds = selection.normalized();
        if (bounds.start.row >= frame.lines.items.len) return null;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        const last_row = @min(bounds.end.row, frame.lines.items.len - 1);
        var row = bounds.start.row;
        while (row <= last_row) : (row += 1) {
            if (row > bounds.start.row) try out.append(self.gpa, '\n');
            const line = frame.lines.items[row];
            const line_width = terminal_text.visibleWidth(line);
            const start_column = if (row == bounds.start.row) @min(bounds.start.column, line_width) else 0;
            const end_column = if (row == bounds.end.row) @min(bounds.end.column, line_width) else line_width;
            if (end_column <= start_column) continue;
            const segment = try terminal_text.sliceByColumnsAlloc(self.gpa, line, start_column, end_column - start_column);
            defer self.gpa.free(segment);
            const plain = try terminal_text.stripAlloc(self.gpa, segment);
            defer self.gpa.free(plain);
            try out.appendSlice(self.gpa, plain);
        }
        return try out.toOwnedSlice(self.gpa);
    }

    pub fn osc52SelectionAlloc(self: *const Application) !?[]u8 {
        const selected = try self.selectedTextAlloc() orelse return null;
        defer self.gpa.free(selected);
        return osc52.sequenceAlloc(self.gpa, selected);
    }

    fn clearCurrentFrames(self: *Application) void {
        if (self.current_frame) |*frame| frame.deinit(self.gpa);
        self.current_frame = null;
        for (self.overlay_frames.items) |*frame| frame.deinit(self.gpa);
        self.overlay_frames.clearRetainingCapacity();
    }

    pub fn render(self: *Application, width_raw: usize, height_raw: usize) !View {
        const width = @max(@as(usize, 1), width_raw);
        const height = @max(@as(usize, 1), height_raw);
        self.clearCurrentFrames();
        var root_frame = try layout.renderFrame(self.gpa, self.root, width, height);
        errdefer root_frame.deinit(self.gpa);
        self.current_frame = root_frame;

        for (self.overlays.items) |entry| try self.renderOverlay(entry, width, height);
        const frame = &self.current_frame.?;
        try self.rebuildSearch(frame.lines.items);
        try self.applySearchHighlights(frame.lines.items);
        try self.applySelectionHighlights(frame.lines.items);
        self.current_cursor = try extractCursor(self.gpa, frame.lines.items);
        for (frame.lines.items) |*line| {
            const old = line.*;
            line.* = try padLineAlloc(self.gpa, old, width);
            self.gpa.free(old);
        }
        return .{ .lines = frame.lines.items, .cursor = self.current_cursor, .width = width, .height = height };
    }

    fn renderOverlay(self: *Application, entry: OverlayEntry, width: usize, height: usize) !void {
        const overlay_width = @max(@as(usize, 1), @min(entry.options.width orelse @min(width, 60), width));
        var probe = try entry.component.render(self.gpa, overlay_width);
        defer probe.deinit(self.gpa);
        const natural_height = @max(@as(usize, 1), probe.items.len);
        const overlay_height = @max(@as(usize, 1), @min(entry.options.height orelse natural_height, height));
        const position = overlayPosition(entry.options.placement, width, height, overlay_width, overlay_height);
        var overlay_frame = try layout.renderFrame(self.gpa, entry.component, overlay_width, overlay_height);
        errdefer overlay_frame.deinit(self.gpa);
        try self.composite(&overlay_frame, position.x, position.y, width, height);
        try self.overlay_frames.append(self.gpa, .{ .id = entry.id, .x = position.x, .y = position.y, .frame = overlay_frame });
    }

    fn composite(self: *Application, overlay: *const layout.LayoutFrame, x: isize, y: isize, width: usize, height: usize) !void {
        const base = &self.current_frame.?;
        for (overlay.lines.items, 0..) |line, local_row| {
            const target_y = y + @as(isize, @intCast(local_row));
            if (target_y < 0 or target_y >= @as(isize, @intCast(height))) continue;
            const target_row: usize = @intCast(target_y);
            const source_start: usize = @intCast(@max(@as(isize, 0), -x));
            const target_x: usize = @intCast(@max(@as(isize, 0), x));
            if (target_x >= width) continue;
            const clipped = try terminal_text.sliceByColumnsAlloc(self.gpa, line, source_start, width - target_x);
            defer self.gpa.free(clipped);
            const replacement = try composeLineAlloc(self.gpa, base.lines.items[target_row], clipped, target_x, width);
            self.gpa.free(base.lines.items[target_row]);
            base.lines.items[target_row] = replacement;
        }
    }

    pub fn renderAnsi(self: *Application, width: usize, height: usize) ![]u8 {
        const view = try self.render(width, height);
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.writeAll(synchronized_begin);
        const full = self.painted_lines.items.len == 0 or self.painted_width != view.width or self.painted_height != view.height;
        if (full) {
            self.full_redraw_count += 1;
            try out.writer.writeAll("\x1b[2J\x1b[H\x1b[3J");
            for (view.lines, 0..) |line, row| {
                if (row > 0) try out.writer.writeAll("\r\n");
                try out.writer.writeAll(line);
                try out.writer.writeAll("\x1b[0m");
            }
        } else {
            var changes: usize = 0;
            for (view.lines, 0..) |line, row| {
                if (row < self.painted_lines.items.len and std.mem.eql(u8, line, self.painted_lines.items[row])) continue;
                changes += 1;
                try out.writer.print("\x1b[{d};1H\x1b[2K", .{row + 1});
                try out.writer.writeAll(line);
                try out.writer.writeAll("\x1b[0m");
            }
            if (changes > 0) self.incremental_redraw_count += 1;
        }
        if (view.cursor) |cursor| {
            try out.writer.print("\x1b[{d};{d}H{s}", .{ cursor.row + 1, cursor.column + 1, terminal.show_cursor });
        } else {
            try out.writer.writeAll(terminal.hide_cursor);
        }
        try out.writer.writeAll(synchronized_end);
        try self.updatePainted(view.lines, view.width, view.height);
        return try out.toOwnedSlice();
    }

    pub fn paint(self: *Application, io: Io, width: usize, height: usize) !void {
        const bytes = try self.renderAnsi(width, height);
        defer self.gpa.free(bytes);
        try writeAll(io, bytes);
    }

    fn updatePainted(self: *Application, lines: []const []u8, width: usize, height: usize) !void {
        self.painted_lines.deinit(self.gpa);
        self.painted_lines = try layout.RenderedLines.clone(self.gpa, lines);
        self.painted_width = width;
        self.painted_height = height;
    }

    fn hitAt(self: *Application, x: usize, y: usize) ?Hit {
        var index = self.overlay_frames.items.len;
        while (index > 0) {
            index -= 1;
            const overlay = &self.overlay_frames.items[index];
            if (hitBox(&overlay.frame.root, x, y, overlay.x, overlay.y)) |hit| return hit;
        }
        if (self.current_frame) |*frame| return hitBox(&frame.root, x, y, 0, 0);
        return null;
    }

    fn scrollAt(self: *Application, x: usize, y: usize) ?*layout.ScrollView {
        var index = self.overlay_frames.items.len;
        while (index > 0) {
            index -= 1;
            const overlay = &self.overlay_frames.items[index];
            if (scrollBox(&overlay.frame.root, x, y, overlay.x, overlay.y)) |scroll| return scroll;
        }
        if (self.current_frame) |*frame| return scrollBox(&frame.root, x, y, 0, 0);
        return null;
    }

    fn rebuildSearch(self: *Application, lines: []const []u8) !void {
        self.search.matches.clearRetainingCapacity();
        if (self.search.query.items.len == 0) return;
        for (lines, 0..) |line, row| {
            const plain = try terminal_text.stripAlloc(self.gpa, line);
            defer self.gpa.free(plain);
            var offset: usize = 0;
            while (offset + self.search.query.items.len <= plain.len) {
                const relative = indexOfIgnoreCase(plain[offset..], self.search.query.items) orelse break;
                const start_byte = offset + relative;
                const end_byte = start_byte + self.search.query.items.len;
                if (!std.unicode.utf8ValidateSlice(plain[0..start_byte]) or !std.unicode.utf8ValidateSlice(plain[start_byte..end_byte])) {
                    offset = start_byte + 1;
                    continue;
                }
                try self.search.matches.append(self.gpa, .{
                    .row = row,
                    .start_column = terminal_text.visibleWidth(plain[0..start_byte]),
                    .end_column = terminal_text.visibleWidth(plain[0..end_byte]),
                });
                offset = @max(end_byte, start_byte + 1);
            }
        }
        if (self.search.active >= self.search.matches.items.len) self.search.active = 0;
    }

    fn applySearchHighlights(self: *Application, lines: [][]u8) !void {
        var row_index: usize = 0;
        while (row_index < lines.len) : (row_index += 1) {
            var match_index = self.search.matches.items.len;
            while (match_index > 0) {
                match_index -= 1;
                const found = self.search.matches.items[match_index];
                if (found.row != row_index or found.end_column <= found.start_column) continue;
                const replacement = try styleColumnsAlloc(
                    self.gpa,
                    lines[row_index],
                    found.start_column,
                    found.end_column - found.start_column,
                    if (match_index == self.search.active) "7;43" else "43;30",
                );
                self.gpa.free(lines[row_index]);
                lines[row_index] = replacement;
            }
        }
    }

    fn applySelectionHighlights(self: *Application, lines: [][]u8) !void {
        const selection = self.selection orelse return;
        const bounds = selection.normalized();
        if (bounds.start.row >= lines.len) return;
        const last = @min(bounds.end.row, lines.len - 1);
        var row = bounds.start.row;
        while (row <= last) : (row += 1) {
            const width = terminal_text.visibleWidth(lines[row]);
            const start_column = if (row == bounds.start.row) @min(bounds.start.column, width) else 0;
            const end_column = if (row == bounds.end.row) @min(bounds.end.column, width) else width;
            if (end_column <= start_column) continue;
            const replacement = try styleColumnsAlloc(self.gpa, lines[row], start_column, end_column - start_column, "7");
            self.gpa.free(lines[row]);
            lines[row] = replacement;
        }
    }
};

fn writeAll(io: Io, bytes: []const u8) !void {
    std.Io.File.stdout().writeStreamingAll(io, bytes) catch {
        std.debug.print("{s}", .{bytes});
    };
}

fn overlayPosition(placement: Placement, screen_width: usize, screen_height: usize, width: usize, height: usize) struct { x: isize, y: isize } {
    return switch (placement) {
        .center => .{
            .x = @intCast((screen_width -| width) / 2),
            .y = @intCast((screen_height -| height) / 2),
        },
        .top_left => .{ .x = 0, .y = 0 },
        .top_right => .{ .x = @intCast(screen_width -| width), .y = 0 },
        .bottom_left => .{ .x = 0, .y = @intCast(screen_height -| height) },
        .bottom_right => .{ .x = @intCast(screen_width -| width), .y = @intCast(screen_height -| height) },
        .absolute => |position| .{ .x = position.x, .y = position.y },
    };
}

fn rectWithOffset(rect: layout.Rect, x: isize, y: isize) layout.Rect {
    return .{ .x = rect.x + x, .y = rect.y + y, .width = rect.width, .height = rect.height };
}

fn contains(rect: layout.Rect, x: usize, y: usize) bool {
    const sx: isize = @intCast(x);
    const sy: isize = @intCast(y);
    return sx >= rect.x and sy >= rect.y and sx < rect.right() and sy < rect.bottom();
}

fn hitBox(box: *const layout.LayoutBox, x: usize, y: usize, offset_x: isize, offset_y: isize) ?Hit {
    const rect = rectWithOffset(box.rect, offset_x, offset_y);
    const clip = rectWithOffset(box.clip, offset_x, offset_y);
    if (!contains(rect, x, y) or !contains(clip, x, y)) return null;
    var index = box.children.len;
    while (index > 0) {
        index -= 1;
        if (hitBox(&box.children[index], x, y, offset_x, offset_y)) |hit| return hit;
    }
    return .{ .component = box.component, .rect = rect, .scroll = box.scroll_view };
}

fn scrollBox(box: *const layout.LayoutBox, x: usize, y: usize, offset_x: isize, offset_y: isize) ?*layout.ScrollView {
    const rect = rectWithOffset(box.rect, offset_x, offset_y);
    const clip = rectWithOffset(box.clip, offset_x, offset_y);
    if (!contains(rect, x, y) or !contains(clip, x, y)) return null;
    var index = box.children.len;
    while (index > 0) {
        index -= 1;
        if (scrollBox(&box.children[index], x, y, offset_x, offset_y)) |scroll| return scroll;
    }
    return box.scroll_view;
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

fn padLineAlloc(gpa: std.mem.Allocator, line: []const u8, width: usize) ![]u8 {
    const clipped = try terminal_text.truncateAlloc(gpa, line, width, .{ .ellipsis = "", .reset_style = false });
    errdefer gpa.free(clipped);
    const visible = terminal_text.visibleWidth(clipped);
    if (visible >= width) return clipped;
    const old_len = clipped.len;
    const grown = try gpa.realloc(clipped, old_len + width - visible);
    @memset(grown[old_len..], ' ');
    return grown;
}

fn composeLineAlloc(gpa: std.mem.Allocator, base: []const u8, overlay: []const u8, column: usize, width: usize) ![]u8 {
    const before = try terminal_text.sliceByColumnsAlloc(gpa, base, 0, column);
    defer gpa.free(before);
    const clipped = try terminal_text.truncateAlloc(gpa, overlay, width -| column, .{ .ellipsis = "", .reset_style = false });
    defer gpa.free(clipped);
    const overlay_width = terminal_text.visibleWidth(clipped);
    const after = try terminal_text.sliceByColumnsAlloc(gpa, base, column + overlay_width, width -| (column + overlay_width));
    defer gpa.free(after);
    const assembled = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ before, clipped, after });
    defer gpa.free(assembled);
    return padLineAlloc(gpa, assembled, width);
}

fn styleColumnsAlloc(gpa: std.mem.Allocator, line: []const u8, start: usize, width: usize, sgr: []const u8) ![]u8 {
    const total = terminal_text.visibleWidth(line);
    if (start >= total or width == 0) return gpa.dupe(u8, line);
    const bounded = @min(width, total - start);
    const before = try terminal_text.sliceByColumnsAlloc(gpa, line, 0, start);
    defer gpa.free(before);
    const selected = try terminal_text.sliceByColumnsAlloc(gpa, line, start, bounded);
    defer gpa.free(selected);
    const after = try terminal_text.sliceByColumnsAlloc(gpa, line, start + bounded, total -| (start + bounded));
    defer gpa.free(after);
    return std.fmt.allocPrint(gpa, "{s}\x1b[{s}m{s}\x1b[0m{s}", .{ before, sgr, selected, after });
}

fn extractCursor(gpa: std.mem.Allocator, lines: [][]u8) !?CursorPosition {
    var result: ?CursorPosition = null;
    for (lines, 0..) |*line, row| {
        var search_start: usize = 0;
        while (std.mem.indexOfPos(u8, line.*, search_start, widgets.cursor_marker)) |index| {
            if (result == null) result = .{ .row = row, .column = terminal_text.visibleWidth(line.*[0..index]) };
            const replacement = try std.fmt.allocPrint(gpa, "{s}{s}", .{
                line.*[0..index],
                line.*[index + widgets.cursor_marker.len ..],
            });
            gpa.free(line.*);
            line.* = replacement;
            search_start = index;
        }
    }
    return result;
}

test "application overlays compose, focus and restore deterministically" {
    const gpa = std.testing.allocator;
    var root_text = layout.StaticLines{ .lines = &.{ "root one", "root two" } };
    var app = Application.init(gpa, root_text.component());
    defer app.deinit();

    var input = widgets.Input.init(gpa);
    defer input.deinit();
    app.setFocus(input.component());
    try std.testing.expect(input.focused);

    var overlay_text = layout.StaticLines{ .lines = &.{"dialog"} };
    const id = try app.pushOverlay(overlay_text.component(), .{ .width = 10, .placement = .center });
    try std.testing.expect(!input.focused);
    const view = try app.render(20, 5);
    try std.testing.expectEqual(@as(usize, 5), view.lines.len);
    try std.testing.expect(std.mem.indexOf(u8, view.lines[2], "dialog") != null);
    try std.testing.expect(app.removeOverlay(id));
    try std.testing.expect(input.focused);
}

test "application extracts cursor and emits differential synchronized output" {
    const gpa = std.testing.allocator;
    var input = widgets.Input.init(gpa);
    defer input.deinit();
    try input.setValue("hello");
    var app = Application.init(gpa, input.component());
    defer app.deinit();
    app.setFocus(input.component());

    const first = try app.renderAnsi(12, 2);
    defer gpa.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "\x1b[2J") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, widgets.cursor_marker) == null);
    try std.testing.expect(app.current_cursor != null);

    try input.handleInput("!");
    const second = try app.renderAnsi(12, 2);
    defer gpa.free(second);
    try std.testing.expect(std.mem.indexOf(u8, second, "\x1b[1;1H\x1b[2K") != null);
    try std.testing.expectEqual(@as(usize, 1), app.full_redraw_count);
    try std.testing.expectEqual(@as(usize, 1), app.incremental_redraw_count);
}

test "mouse hit testing drives selectors while drag selection extracts cells" {
    const gpa = std.testing.allocator;
    const items = [_]widgets.SelectItem{
        .{ .value = "one", .label = "One" },
        .{ .value = "two", .label = "Two" },
    };
    var list = try widgets.SelectList.init(gpa, &items, 5);
    defer list.deinit();
    var app = Application.init(gpa, list.component());
    defer app.deinit();
    _ = try app.render(20, 4);
    try app.handleInput("\x1b[<0;1;2M");
    try std.testing.expectEqual(@as(usize, 1), list.selectedItemIndex().?);

    var text = layout.StaticLines{ .lines = &.{"abcdef"} };
    var selection_app = Application.init(gpa, text.component());
    defer selection_app.deinit();
    _ = try selection_app.render(10, 2);
    try selection_app.handleMouse(.{ .kind = .press, .button = .left, .x = 1, .y = 0 });
    try selection_app.handleMouse(.{ .kind = .drag, .button = .left, .x = 4, .y = 0 });
    try selection_app.handleMouse(.{ .kind = .release, .button = .left, .x = 4, .y = 0 });
    _ = try selection_app.render(10, 2);
    const selected = (try selection_app.selectedTextAlloc()).?;
    defer gpa.free(selected);
    try std.testing.expectEqualStrings("bcd", selected);
    const osc = (try selection_app.osc52SelectionAlloc()).?;
    defer gpa.free(osc);
    try std.testing.expect(std.mem.startsWith(u8, osc, "\x1b]52;c;"));
}

test "search highlights matches and cycles while IME commits atomically" {
    const gpa = std.testing.allocator;
    var input = widgets.Input.init(gpa);
    defer input.deinit();
    try input.setValue("Alpha alpha beta");
    var app = Application.init(gpa, input.component());
    defer app.deinit();
    app.setFocus(input.component());
    try app.setSearch("alpha");
    const view = try app.render(30, 2);
    try std.testing.expectEqual(@as(usize, 2), app.search.matches.items.len);
    try std.testing.expect(std.mem.indexOf(u8, view.lines[0], "\x1b[7;43m") != null);
    _ = app.nextSearchMatch();
    try std.testing.expectEqual(@as(usize, 1), app.search.active);

    app.beginComposition();
    try app.updateComposition("界", 3);
    try app.commitComposition("界");
    try std.testing.expect(!app.composition.active);
    try std.testing.expect(std.mem.endsWith(u8, input.value(), "界"));
}

test "alternate-screen lifecycle sequences include paste mouse and cursor restoration" {
    try std.testing.expect(std.mem.startsWith(u8, enter_sequence, terminal.alternate_screen_enter));
    try std.testing.expect(std.mem.indexOf(u8, enter_sequence, terminal.bracketed_paste_enable) != null);
    try std.testing.expect(std.mem.indexOf(u8, enter_sequence, "\x1b[?1006h") != null);
    try std.testing.expect(std.mem.endsWith(u8, leave_sequence, terminal.alternate_screen_leave));
}

//! Retained terminal layout tree with stack allocation, clipping, composition,
//! scrolling and common text components.
//!
//! The API is deliberately callback-based rather than tied to concrete widget
//! types: native extensions and the coding-agent UI can expose a `Component`
//! without allocation or inheritance, while a frame owns every rendered line
//! and layout box needed for deterministic diffing and hit testing.
const std = @import("std");
const terminal_text = @import("terminal_text.zig");
const markdown = @import("markdown.zig");
const mouse = @import("mouse.zig");

pub const RenderedLines = struct {
    items: [][]u8 = &.{},

    pub fn deinit(self: *RenderedLines, gpa: std.mem.Allocator) void {
        for (self.items) |line| gpa.free(line);
        if (self.items.len > 0) gpa.free(self.items);
        self.* = .{};
    }

    pub fn clone(gpa: std.mem.Allocator, lines: []const []const u8) !RenderedLines {
        var out: std.ArrayList([]u8) = .empty;
        errdefer {
            for (out.items) |line| gpa.free(line);
            out.deinit(gpa);
        }
        for (lines) |line| try out.append(gpa, try gpa.dupe(u8, line));
        return .{ .items = try out.toOwnedSlice(gpa) };
    }
};

pub const Viewport = struct {
    width: usize,
    height: usize,
};

pub const Rect = struct {
    x: isize,
    y: isize,
    width: usize,
    height: usize,

    pub fn right(self: Rect) isize {
        return self.x + @as(isize, @intCast(self.width));
    }

    pub fn bottom(self: Rect) isize {
        return self.y + @as(isize, @intCast(self.height));
    }
};

pub const Align = enum { stretch, start, center, end };
pub const Axis = enum { vertical, horizontal };
pub const Overscroll = enum { chain, contain };
pub const Scrollbar = enum { hidden, auto, always };

pub const Visibility = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, Viewport) bool,

    pub fn call(self: Visibility, viewport: Viewport) bool {
        return self.callback(self.context, viewport);
    }
};

pub const StackEntry = struct {
    component: Component,
    basis: ?usize = null,
    grow: usize = 0,
    shrink: usize = 1,
    min_size: usize = 0,
    max_size: usize = std.math.maxInt(usize),
    visible: ?Visibility = null,

    fn normalized(self: StackEntry) StackEntry {
        var copy = self;
        copy.max_size = @max(copy.min_size, copy.max_size);
        return copy;
    }
};

pub const StackNode = struct {
    axis: Axis,
    entries: []const StackEntry,
    gap: usize = 0,
    alignment: Align = .stretch,
};

pub const ScrollNode = struct {
    component: Component,
    state: *ScrollView,
};

pub const LayoutNode = union(enum) {
    stack: StackNode,
    scroll: ScrollNode,
};

pub const Component = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        render: *const fn (*anyopaque, std.mem.Allocator, usize) anyerror!RenderedLines,
        layout_node: ?*const fn (*anyopaque) LayoutNode = null,
        handle_input: ?*const fn (*anyopaque, []const u8) anyerror!void = null,
        handle_paste: ?*const fn (*anyopaque, []const u8) anyerror!void = null,
        handle_mouse: ?*const fn (*anyopaque, mouse.Event) anyerror!bool = null,
        set_focus: ?*const fn (*anyopaque, bool) void = null,
        invalidate: ?*const fn (*anyopaque) void = null,
    };

    pub fn render(self: Component, gpa: std.mem.Allocator, width: usize) !RenderedLines {
        return self.vtable.render(self.context, gpa, @max(@as(usize, 1), width));
    }

    pub fn layoutNode(self: Component) ?LayoutNode {
        const callback = self.vtable.layout_node orelse return null;
        return callback(self.context);
    }

    pub fn handleInput(self: Component, data: []const u8) !void {
        if (self.vtable.handle_input) |callback| try callback(self.context, data);
    }

    pub fn handlePaste(self: Component, data: []const u8) !void {
        if (self.vtable.handle_paste) |callback| {
            try callback(self.context, data);
        } else {
            try self.handleInput(data);
        }
    }

    pub fn handleMouse(self: Component, event: mouse.Event) !bool {
        const callback = self.vtable.handle_mouse orelse return false;
        return try callback(self.context, event);
    }

    pub fn setFocus(self: Component, focused: bool) void {
        if (self.vtable.set_focus) |callback| callback(self.context, focused);
    }

    pub fn eql(a: Component, b: Component) bool {
        return a.context == b.context and a.vtable == b.vtable;
    }

    pub fn invalidate(self: Component) void {
        if (self.vtable.invalidate) |callback| callback(self.context);
    }
};

fn clampSize(size: usize, entry_raw: StackEntry) usize {
    const entry = entry_raw.normalized();
    return std.math.clamp(size, entry.min_size, entry.max_size);
}

fn distribute(sizes: []usize, entries: []const StackEntry, amount: usize, grow: bool) void {
    var remaining = amount;
    while (remaining > 0) {
        var total_weight: u128 = 0;
        var candidate_count: usize = 0;
        for (entries, 0..) |entry_raw, index| {
            const entry = entry_raw.normalized();
            const eligible = if (grow)
                entry.grow > 0 and sizes[index] < entry.max_size
            else
                entry.shrink > 0 and sizes[index] > entry.min_size;
            if (!eligible) continue;
            const weight: u128 = if (grow)
                entry.grow
            else
                @as(u128, entry.shrink) * @max(@as(u128, 1), sizes[index]);
            total_weight += weight;
            candidate_count += 1;
        }
        if (candidate_count == 0 or total_weight == 0) return;

        var distributed: usize = 0;
        for (entries, 0..) |entry_raw, index| {
            if (remaining == 0) break;
            const entry = entry_raw.normalized();
            const eligible = if (grow)
                entry.grow > 0 and sizes[index] < entry.max_size
            else
                entry.shrink > 0 and sizes[index] > entry.min_size;
            if (!eligible) continue;
            const weight: u128 = if (grow)
                entry.grow
            else
                @as(u128, entry.shrink) * @max(@as(u128, 1), sizes[index]);
            const proportional_u128 = (@as(u128, remaining) * weight) / total_weight;
            const proportional: usize = @intCast(@min(@as(u128, std.math.maxInt(usize)), @max(@as(u128, 1), proportional_u128)));
            const capacity = if (grow) entry.max_size - sizes[index] else sizes[index] - entry.min_size;
            const delta = @min(remaining, @min(proportional, capacity));
            if (delta == 0) continue;
            if (grow) sizes[index] += delta else sizes[index] -= delta;
            remaining -= delta;
            distributed += delta;
        }
        if (distributed == 0) return;
    }
}

/// Allocate flex-like stack sizes using Pi's basis/grow/shrink/min/max rules.
pub fn allocateStackSizes(
    gpa: std.mem.Allocator,
    entries: []const StackEntry,
    intrinsic_sizes: []const usize,
    available_size: ?usize,
    gap: usize,
) ![]usize {
    if (entries.len != intrinsic_sizes.len) return error.LengthMismatch;
    const sizes = try gpa.alloc(usize, entries.len);
    errdefer gpa.free(sizes);
    for (entries, intrinsic_sizes, 0..) |entry, intrinsic, index| {
        sizes[index] = clampSize(entry.basis orelse intrinsic, entry);
    }
    const available = available_size orelse return sizes;
    const gap_total = if (entries.len > 1) (entries.len - 1) *| gap else 0;
    const content_size = available -| gap_total;
    var total: usize = 0;
    for (sizes) |size| total +|= size;
    if (total < content_size) distribute(sizes, entries, content_size - total, true) else if (total > content_size) distribute(sizes, entries, total - content_size, false);
    return sizes;
}

fn visibleEntries(gpa: std.mem.Allocator, entries: []const StackEntry, viewport: Viewport) ![]StackEntry {
    var out: std.ArrayList(StackEntry) = .empty;
    errdefer out.deinit(gpa);
    for (entries) |entry| {
        if (entry.visible) |condition| if (!condition.call(viewport)) continue;
        try out.append(gpa, entry.normalized());
    }
    return out.toOwnedSlice(gpa);
}

fn repeatSpaces(gpa: std.mem.Allocator, count: usize) ![]u8 {
    const bytes = try gpa.alloc(u8, count);
    @memset(bytes, ' ');
    return bytes;
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

pub const Text = struct {
    gpa: std.mem.Allocator,
    text: []u8,
    padding_x: usize = 1,
    padding_y: usize = 1,
    background_sgr: ?[]const u8 = null,

    pub fn init(gpa: std.mem.Allocator, value: []const u8, padding_x: usize, padding_y: usize) !Text {
        return .{ .gpa = gpa, .text = try gpa.dupe(u8, value), .padding_x = padding_x, .padding_y = padding_y };
    }

    pub fn deinit(self: *Text) void {
        self.gpa.free(self.text);
        self.* = undefined;
    }

    pub fn setText(self: *Text, value: []const u8) !void {
        const replacement = try self.gpa.dupe(u8, value);
        self.gpa.free(self.text);
        self.text = replacement;
    }

    pub fn component(self: *Text) Component {
        return .{ .context = self, .vtable = &vtable };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !RenderedLines {
        const self: *Text = @ptrCast(@alignCast(raw));
        if (std.mem.trim(u8, self.text, " \t\r\n").len == 0) return .{};
        const content_width = @max(@as(usize, 1), width -| (self.padding_x *| 2));
        const wrapped = try markdown.wrapAnsi(gpa, self.text, content_width);
        defer {
            for (wrapped) |line| gpa.free(line);
            gpa.free(wrapped);
        }
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        for (0..self.padding_y) |_| try lines.append(gpa, try backgroundLine(gpa, "", width, self.background_sgr));
        for (wrapped) |line| {
            var content: std.ArrayList(u8) = .empty;
            defer content.deinit(gpa);
            try content.appendNTimes(gpa, ' ', self.padding_x);
            try content.appendSlice(gpa, line);
            try content.appendNTimes(gpa, ' ', self.padding_x);
            try lines.append(gpa, try backgroundLine(gpa, content.items, width, self.background_sgr));
        }
        for (0..self.padding_y) |_| try lines.append(gpa, try backgroundLine(gpa, "", width, self.background_sgr));
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }

    const vtable: Component.VTable = .{ .render = renderOpaque };
};

fn backgroundLine(gpa: std.mem.Allocator, line: []const u8, width: usize, sgr: ?[]const u8) ![]u8 {
    const padded = try padLineAlloc(gpa, line, width);
    if (sgr == null or sgr.?.len == 0) return padded;
    defer gpa.free(padded);
    return std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{ sgr.?, padded });
}

pub const TruncatedText = struct {
    text: []const u8,
    padding_x: usize = 0,
    padding_y: usize = 0,
    ellipsis: []const u8 = "…",

    pub fn component(self: *TruncatedText) Component {
        return .{ .context = self, .vtable = &vtable };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !RenderedLines {
        const self: *TruncatedText = @ptrCast(@alignCast(raw));
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        for (0..self.padding_y) |_| try lines.append(gpa, try repeatSpaces(gpa, width));
        const newline = std.mem.indexOfScalar(u8, self.text, '\n') orelse self.text.len;
        const available = @max(@as(usize, 1), width -| (self.padding_x *| 2));
        const display = try terminal_text.truncateAlloc(gpa, self.text[0..newline], available, .{ .ellipsis = self.ellipsis });
        defer gpa.free(display);
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(gpa);
        try line.appendNTimes(gpa, ' ', self.padding_x);
        try line.appendSlice(gpa, display);
        try line.appendNTimes(gpa, ' ', self.padding_x);
        try lines.append(gpa, try padLineAlloc(gpa, line.items, width));
        for (0..self.padding_y) |_| try lines.append(gpa, try repeatSpaces(gpa, width));
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }

    const vtable: Component.VTable = .{ .render = renderOpaque };
};

pub const Spacer = struct {
    rows: usize = 1,

    pub fn component(self: *Spacer) Component {
        return .{ .context = self, .vtable = &vtable };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !RenderedLines {
        const self: *Spacer = @ptrCast(@alignCast(raw));
        const lines = try gpa.alloc([]u8, self.rows);
        errdefer gpa.free(lines);
        var initialized: usize = 0;
        errdefer for (lines[0..initialized]) |line| gpa.free(line);
        for (lines) |*line| {
            line.* = try repeatSpaces(gpa, width);
            initialized += 1;
        }
        return .{ .items = lines };
    }

    const vtable: Component.VTable = .{ .render = renderOpaque };
};

pub const StaticLines = struct {
    lines: []const []const u8,

    pub fn component(self: *StaticLines) Component {
        return .{ .context = self, .vtable = &vtable };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !RenderedLines {
        const self: *StaticLines = @ptrCast(@alignCast(raw));
        var out: std.ArrayList([]u8) = .empty;
        errdefer {
            for (out.items) |line| gpa.free(line);
            out.deinit(gpa);
        }
        for (self.lines) |line| try out.append(gpa, try padLineAlloc(gpa, line, width));
        return .{ .items = try out.toOwnedSlice(gpa) };
    }

    const vtable: Component.VTable = .{ .render = renderOpaque };
};

pub const Stack = struct {
    axis: Axis,
    entries: []const StackEntry,
    gap: usize = 0,
    alignment: Align = .stretch,

    pub fn component(self: *Stack) Component {
        return .{ .context = self, .vtable = &vtable };
    }

    fn nodeOpaque(raw: *anyopaque) LayoutNode {
        const self: *Stack = @ptrCast(@alignCast(raw));
        return .{ .stack = .{ .axis = self.axis, .entries = self.entries, .gap = self.gap, .alignment = self.alignment } };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !RenderedLines {
        const self: *Stack = @ptrCast(@alignCast(raw));
        var frame = try renderFrame(gpa, self.component(), width, null);
        defer frame.deinitExceptLines(gpa);
        return frame.takeLines();
    }

    const vtable: Component.VTable = .{ .render = renderOpaque, .layout_node = nodeOpaque };
};

pub const ScrollView = struct {
    child: Component,
    follow_end: bool = false,
    primary: bool = false,
    overscroll: Overscroll = .chain,
    scrollbar: Scrollbar = .hidden,
    scrollbar_sgr: []const u8 = "100",
    scroll_top: usize = 0,
    content_height: usize = 0,
    viewport_height: usize = 0,
    following_end: bool = false,
    follow_suppressed_at_end: bool = false,
    transient_scrollbar_visible: bool = false,

    pub fn init(child: Component, follow_end: bool) ScrollView {
        return .{ .child = child, .follow_end = follow_end, .following_end = follow_end };
    }

    pub fn component(self: *ScrollView) Component {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn getContentWidth(self: *const ScrollView, width: usize) usize {
        return if (self.scrollbar == .always and width > 1) width - 1 else width;
    }

    pub fn maxScrollTop(self: *const ScrollView) usize {
        return self.content_height -| self.viewport_height;
    }

    pub fn updateLayout(self: *ScrollView, content_height: usize, viewport_height: usize) void {
        self.content_height = content_height;
        self.viewport_height = viewport_height;
        const max_top = self.maxScrollTop();
        if (self.following_end) self.scroll_top = max_top else self.scroll_top = @min(self.scroll_top, max_top);
        if (self.scroll_top < max_top) self.follow_suppressed_at_end = false;
        if (self.follow_end and self.scroll_top == max_top and !self.follow_suppressed_at_end) self.following_end = true;
        if (content_height <= viewport_height) self.transient_scrollbar_visible = false;
    }

    pub fn scrollTo(self: *ScrollView, position: usize, disable_follow: bool) void {
        const max_top = self.maxScrollTop();
        self.scroll_top = @min(position, max_top);
        self.follow_suppressed_at_end = disable_follow and self.scroll_top == max_top;
        self.following_end = !self.follow_suppressed_at_end and self.follow_end and self.scroll_top == max_top;
        self.transient_scrollbar_visible = self.scrollbar == .auto and self.content_height > self.viewport_height;
    }

    /// Scroll and return the unused delta for overscroll chaining.
    pub fn scrollBy(self: *ScrollView, delta: isize) isize {
        if (delta == 0) return 0;
        const max_top: isize = @intCast(self.maxScrollTop());
        const start: isize = @intCast(if (self.following_end) self.maxScrollTop() else self.scroll_top);
        const requested = start + delta;
        const next = std.math.clamp(requested, @as(isize, 0), max_top);
        self.scroll_top = @intCast(next);
        self.following_end = self.follow_end and next == max_top;
        self.follow_suppressed_at_end = false;
        if (next != start and self.scrollbar == .auto) self.transient_scrollbar_visible = true;
        return delta - (next - start);
    }

    pub fn scrollToStart(self: *ScrollView) void {
        self.scroll_top = 0;
        self.following_end = self.follow_end and self.content_height <= self.viewport_height;
        self.follow_suppressed_at_end = false;
    }

    pub fn scrollToEnd(self: *ScrollView) void {
        self.scroll_top = self.maxScrollTop();
        self.following_end = self.follow_end;
        self.follow_suppressed_at_end = false;
    }

    pub fn scrollbarVisible(self: *const ScrollView) bool {
        return switch (self.scrollbar) {
            .hidden => false,
            .always => self.viewport_height > 0,
            .auto => self.content_height > self.viewport_height and self.transient_scrollbar_visible,
        };
    }

    fn nodeOpaque(raw: *anyopaque) LayoutNode {
        const self: *ScrollView = @ptrCast(@alignCast(raw));
        return .{ .scroll = .{ .component = self.child, .state = self } };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !RenderedLines {
        const self: *ScrollView = @ptrCast(@alignCast(raw));
        const content_width = self.getContentWidth(width);
        const lines = try self.child.render(gpa, content_width);
        if (content_width == width) return lines;
        for (lines.items) |*line| {
            const old = line.*;
            line.* = try padLineAlloc(gpa, old, width);
            gpa.free(old);
        }
        return lines;
    }

    const vtable: Component.VTable = .{ .render = renderOpaque, .layout_node = nodeOpaque };
};

pub const LayoutBox = struct {
    component: Component,
    rect: Rect,
    clip: Rect,
    children: []LayoutBox = &.{},
    lines: ?RenderedLines = null,
    line_offset: usize = 0,
    scroll_view: ?*ScrollView = null,
    layer: i32 = 0,

    pub fn deinit(self: *LayoutBox, gpa: std.mem.Allocator) void {
        for (self.children) |*child| child.deinit(gpa);
        if (self.children.len > 0) gpa.free(self.children);
        if (self.lines) |*lines| lines.deinit(gpa);
        self.* = undefined;
    }
};

pub const ScrollbarGeometry = struct {
    column: usize,
    track_top: usize,
    track_height: usize,
    thumb_top: usize,
    thumb_height: usize,
    max_scroll_top: usize,
};

pub const LayoutFrame = struct {
    root: LayoutBox,
    width: usize,
    height: usize,
    lines: RenderedLines,
    primary_scroll_view: ?*ScrollView = null,

    pub fn deinit(self: *LayoutFrame, gpa: std.mem.Allocator) void {
        self.root.deinit(gpa);
        self.lines.deinit(gpa);
        self.* = undefined;
    }

    fn deinitExceptLines(self: *LayoutFrame, gpa: std.mem.Allocator) void {
        self.root.deinit(gpa);
    }

    fn takeLines(self: *LayoutFrame) RenderedLines {
        const result = self.lines;
        self.lines = .{};
        return result;
    }
};

fn intersect(a: Rect, b: Rect) Rect {
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    const right = @min(a.right(), b.right());
    const bottom = @min(a.bottom(), b.bottom());
    return .{
        .x = x,
        .y = y,
        .width = @intCast(@max(@as(isize, 0), right - x)),
        .height = @intCast(@max(@as(isize, 0), bottom - y)),
    };
}

fn measureHeight(gpa: std.mem.Allocator, component: Component, width: usize, viewport: Viewport) anyerror!usize {
    if (component.layoutNode()) |node| switch (node) {
        .scroll => |scroll| return measureHeight(gpa, scroll.component, scroll.state.getContentWidth(width), viewport),
        .stack => |stack| {
            const entries = try visibleEntries(gpa, stack.entries, viewport);
            defer gpa.free(entries);
            if (entries.len == 0) return 0;
            if (stack.axis == .vertical) {
                var total = (entries.len - 1) *| stack.gap;
                for (entries) |entry| {
                    const intrinsic = if (entry.basis) |basis| basis else try measureHeight(gpa, entry.component, width, viewport);
                    total +|= clampSize(intrinsic, entry);
                }
                return total;
            }
            const widths = try intrinsicWidths(gpa, entries, width, viewport);
            defer gpa.free(widths);
            const allocated = try allocateStackSizes(gpa, entries, widths, width, stack.gap);
            defer gpa.free(allocated);
            var max_height: usize = 0;
            for (entries, allocated) |entry, child_width| {
                if (child_width == 0) continue;
                max_height = @max(max_height, try measureHeight(gpa, entry.component, child_width, viewport));
            }
            return max_height;
        },
    };
    var lines = try component.render(gpa, width);
    defer lines.deinit(gpa);
    return lines.items.len;
}

fn measureWidth(gpa: std.mem.Allocator, component: Component, width: usize, viewport: Viewport) anyerror!usize {
    if (component.layoutNode()) |node| switch (node) {
        .scroll => |scroll| return measureWidth(gpa, scroll.component, scroll.state.getContentWidth(width), viewport),
        .stack => |stack| {
            const entries = try visibleEntries(gpa, stack.entries, viewport);
            defer gpa.free(entries);
            if (entries.len == 0) return 0;
            if (stack.axis == .horizontal) {
                var total = (entries.len - 1) *| stack.gap;
                for (entries) |entry| {
                    const intrinsic = if (entry.basis) |basis| basis else try measureWidth(gpa, entry.component, width, viewport);
                    total +|= clampSize(intrinsic, entry);
                }
                return total;
            }
            var max_width: usize = 0;
            for (entries) |entry| max_width = @max(max_width, try measureWidth(gpa, entry.component, width, viewport));
            return max_width;
        },
    };
    var lines = try component.render(gpa, width);
    defer lines.deinit(gpa);
    var result: usize = 0;
    for (lines.items) |line| result = @max(result, terminal_text.visibleWidth(line));
    return result;
}

fn intrinsicWidths(gpa: std.mem.Allocator, entries: []const StackEntry, width: usize, viewport: Viewport) ![]usize {
    const result = try gpa.alloc(usize, entries.len);
    errdefer gpa.free(result);
    for (entries, 0..) |entry, index| result[index] = if (entry.basis) |basis| basis else try measureWidth(gpa, entry.component, width, viewport);
    return result;
}

fn translateBox(box: *LayoutBox, delta_y: isize) void {
    box.rect.y += delta_y;
    for (box.children) |*child| translateBox(child, delta_y);
}

fn updateClips(box: *LayoutBox, parent_clip: Rect) void {
    box.clip = intersect(parent_clip, box.rect);
    for (box.children) |*child| updateClips(child, box.clip);
}

fn layoutComponent(
    gpa: std.mem.Allocator,
    component: Component,
    x: isize,
    y: isize,
    width_raw: usize,
    height: ?usize,
    clip: Rect,
    viewport: Viewport,
    primary_scroll: *?*ScrollView,
) anyerror!LayoutBox {
    const width = @max(@as(usize, 1), width_raw);
    const node = component.layoutNode() orelse {
        var lines = try component.render(gpa, width);
        errdefer lines.deinit(gpa);
        const allocated_height = height orelse lines.items.len;
        var line_offset: usize = 0;
        if (lines.items.len > allocated_height and allocated_height > 0) line_offset = lines.items.len - allocated_height;
        const rect = Rect{ .x = x, .y = y, .width = width, .height = allocated_height };
        return .{ .component = component, .rect = rect, .clip = intersect(clip, rect), .lines = lines, .line_offset = line_offset };
    };

    switch (node) {
        .scroll => |scroll| {
            const old_top = scroll.state.scroll_top;
            const content_width = scroll.state.getContentWidth(width);
            var child = try layoutComponent(gpa, scroll.component, x, y - @as(isize, @intCast(old_top)), content_width, null, clip, viewport, primary_scroll);
            errdefer child.deinit(gpa);
            const content_height = child.rect.height;
            const viewport_height = height orelse content_height;
            scroll.state.updateLayout(content_height, viewport_height);
            const delta = @as(isize, @intCast(old_top)) - @as(isize, @intCast(scroll.state.scroll_top));
            translateBox(&child, delta);
            if (scroll.state.primary or primary_scroll.* == null) primary_scroll.* = scroll.state;
            const rect = Rect{ .x = x, .y = y, .width = width, .height = viewport_height };
            const child_clip = intersect(clip, rect);
            updateClips(&child, child_clip);
            const children = try gpa.alloc(LayoutBox, 1);
            children[0] = child;
            return .{ .component = component, .rect = rect, .clip = child_clip, .children = children, .scroll_view = scroll.state };
        },
        .stack => |stack| {
            const entries = try visibleEntries(gpa, stack.entries, viewport);
            defer gpa.free(entries);
            const gap_total = if (entries.len > 1) (entries.len - 1) *| stack.gap else 0;
            if (stack.axis == .vertical) {
                const intrinsic = try gpa.alloc(usize, entries.len);
                defer gpa.free(intrinsic);
                for (entries, 0..) |entry, index| intrinsic[index] = entry.basis orelse try measureHeight(gpa, entry.component, width, viewport);
                const sizes = try allocateStackSizes(gpa, entries, intrinsic, height, stack.gap);
                defer gpa.free(sizes);
                var natural_height = gap_total;
                for (sizes) |size| natural_height +|= size;
                const allocated_height = height orelse natural_height;
                const rect = Rect{ .x = x, .y = y, .width = width, .height = allocated_height };
                var children: std.ArrayList(LayoutBox) = .empty;
                errdefer {
                    for (children.items) |*child| child.deinit(gpa);
                    children.deinit(gpa);
                }
                var child_y = y;
                for (entries, sizes) |entry, child_height| {
                    try children.append(gpa, try layoutComponent(gpa, entry.component, x, child_y, width, child_height, intersect(clip, rect), viewport, primary_scroll));
                    child_y += @as(isize, @intCast(child_height +| stack.gap));
                }
                return .{ .component = component, .rect = rect, .clip = intersect(clip, rect), .children = try children.toOwnedSlice(gpa) };
            }

            const intrinsic_widths = try intrinsicWidths(gpa, entries, width, viewport);
            defer gpa.free(intrinsic_widths);
            const widths = try allocateStackSizes(gpa, entries, intrinsic_widths, width, stack.gap);
            defer gpa.free(widths);
            const heights = try gpa.alloc(usize, entries.len);
            defer gpa.free(heights);
            var natural_height: usize = 0;
            for (entries, widths, 0..) |entry, child_width, index| {
                heights[index] = if (child_width == 0) 0 else try measureHeight(gpa, entry.component, @max(@as(usize, 1), child_width), viewport);
                natural_height = @max(natural_height, heights[index]);
            }
            const allocated_height = height orelse natural_height;
            const rect = Rect{ .x = x, .y = y, .width = width, .height = allocated_height };
            var children: std.ArrayList(LayoutBox) = .empty;
            errdefer {
                for (children.items) |*child| child.deinit(gpa);
                children.deinit(gpa);
            }
            var child_x = x;
            for (entries, widths, heights) |entry, child_width, natural_child_height| {
                const child_height = if (stack.alignment == .stretch) allocated_height else @min(allocated_height, natural_child_height);
                var child_y = y;
                if (stack.alignment == .center) child_y += @as(isize, @intCast((allocated_height - child_height) / 2)) else if (stack.alignment == .end) child_y += @as(isize, @intCast(allocated_height - child_height));
                if (child_width == 0) {
                    try children.append(gpa, .{ .component = entry.component, .rect = .{ .x = child_x, .y = child_y, .width = 0, .height = child_height }, .clip = .{ .x = child_x, .y = child_y, .width = 0, .height = 0 } });
                } else {
                    try children.append(gpa, try layoutComponent(gpa, entry.component, child_x, child_y, child_width, child_height, intersect(clip, rect), viewport, primary_scroll));
                }
                child_x += @as(isize, @intCast(child_width +| stack.gap));
            }
            return .{ .component = component, .rect = rect, .clip = intersect(clip, rect), .children = try children.toOwnedSlice(gpa) };
        },
    }
}

fn composeAt(gpa: std.mem.Allocator, base: []const u8, overlay_raw: []const u8, column: usize, width: usize) ![]u8 {
    if (column >= width) return gpa.dupe(u8, base);
    const max_overlay = width - column;
    const overlay = try terminal_text.truncateAlloc(gpa, overlay_raw, max_overlay, .{ .ellipsis = "", .reset_style = false });
    defer gpa.free(overlay);
    const overlay_width = terminal_text.visibleWidth(overlay);
    if (overlay_width == 0) return gpa.dupe(u8, base);
    const before = try terminal_text.sliceByColumnsAlloc(gpa, base, 0, column);
    defer gpa.free(before);
    const after = try terminal_text.sliceByColumnsAlloc(gpa, base, column + overlay_width, width -| (column + overlay_width));
    defer gpa.free(after);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, before);
    try out.appendSlice(gpa, overlay);
    try out.appendSlice(gpa, after);
    const assembled = try out.toOwnedSlice(gpa);
    defer gpa.free(assembled);
    return padLineAlloc(gpa, assembled, width);
}

fn paintBox(gpa: std.mem.Allocator, box: *const LayoutBox, frame_lines: [][]u8, frame_width: usize, frame_height: usize) !void {
    if (box.lines) |lines| {
        if (box.clip.width == 0 or box.clip.height == 0) return;
        for (lines.items, 0..) |line, local_row| {
            if (local_row < box.line_offset) continue;
            const drawn_row = local_row - box.line_offset;
            if (drawn_row >= box.rect.height) break;
            const screen_y = box.rect.y + @as(isize, @intCast(drawn_row));
            if (screen_y < 0 or screen_y >= @as(isize, @intCast(frame_height))) continue;
            if (screen_y < box.clip.y or screen_y >= box.clip.bottom()) continue;
            const source_start: usize = @intCast(@max(@as(isize, 0), box.clip.x - box.rect.x));
            const clipped = try terminal_text.sliceByColumnsAlloc(gpa, line, source_start, box.clip.width);
            defer gpa.free(clipped);
            const column: usize = @intCast(@max(@as(isize, 0), box.clip.x));
            const row: usize = @intCast(screen_y);
            const replacement = try composeAt(gpa, frame_lines[row], clipped, column, frame_width);
            gpa.free(frame_lines[row]);
            frame_lines[row] = replacement;
        }
    }
    for (box.children) |*child| try paintBox(gpa, child, frame_lines, frame_width, frame_height);
}

pub fn scrollbarGeometry(scroll: *const ScrollView, column: usize, track_top: usize) ?ScrollbarGeometry {
    if (!scroll.scrollbarVisible() or scroll.viewport_height == 0) return null;
    const track_height = scroll.viewport_height;
    const max_top = scroll.maxScrollTop();
    const thumb_height = if (scroll.content_height <= track_height)
        track_height
    else
        @min(track_height, @max(@as(usize, 2), (track_height *| track_height + scroll.content_height / 2) / scroll.content_height));
    const travel = track_height -| thumb_height;
    const thumb_top = if (max_top == 0) 0 else (scroll.scroll_top *| travel + max_top / 2) / max_top;
    return .{ .column = column, .track_top = track_top, .track_height = track_height, .thumb_top = thumb_top, .thumb_height = thumb_height, .max_scroll_top = max_top };
}

fn paintScrollbars(gpa: std.mem.Allocator, box: *const LayoutBox, lines: [][]u8, frame_width: usize, frame_height: usize) !void {
    if (box.scroll_view) |scroll| {
        const column_signed = box.rect.x + @as(isize, @intCast(box.rect.width -| 1));
        if (column_signed >= 0 and column_signed < @as(isize, @intCast(frame_width)) and box.rect.y >= 0) {
            if (scrollbarGeometry(scroll, @intCast(column_signed), @intCast(box.rect.y))) |geometry| {
                for (0..geometry.thumb_height) |offset| {
                    const row = geometry.track_top + geometry.thumb_top + offset;
                    if (row >= frame_height) continue;
                    const cell = try std.fmt.allocPrint(gpa, "\x1b[{s}m \x1b[49m", .{scroll.scrollbar_sgr});
                    defer gpa.free(cell);
                    const replacement = try composeAt(gpa, lines[row], cell, geometry.column, frame_width);
                    gpa.free(lines[row]);
                    lines[row] = replacement;
                }
            }
        }
    }
    for (box.children) |*child| try paintScrollbars(gpa, child, lines, frame_width, frame_height);
}

pub fn renderFrame(gpa: std.mem.Allocator, root: Component, width_raw: usize, height: ?usize) !LayoutFrame {
    const width = @max(@as(usize, 1), width_raw);
    const viewport_height = height orelse try measureHeight(gpa, root, width, .{ .width = width, .height = std.math.maxInt(usize) });
    const viewport = Viewport{ .width = width, .height = viewport_height };
    const clip = Rect{ .x = 0, .y = 0, .width = width, .height = viewport_height };
    var primary: ?*ScrollView = null;
    var box = try layoutComponent(gpa, root, 0, 0, width, height, clip, viewport, &primary);
    errdefer box.deinit(gpa);
    const lines = try gpa.alloc([]u8, viewport_height);
    errdefer gpa.free(lines);
    var initialized: usize = 0;
    errdefer for (lines[0..initialized]) |line| gpa.free(line);
    for (lines) |*line| {
        line.* = try repeatSpaces(gpa, width);
        initialized += 1;
    }
    try paintBox(gpa, &box, lines, width, viewport_height);
    try paintScrollbars(gpa, &box, lines, width, viewport_height);
    return .{ .root = box, .width = width, .height = viewport_height, .lines = .{ .items = lines }, .primary_scroll_view = primary };
}

fn strippedLines(gpa: std.mem.Allocator, lines: []const []u8) ![][]u8 {
    const result = try gpa.alloc([]u8, lines.len);
    errdefer gpa.free(result);
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |line| gpa.free(line);
    for (lines, 0..) |line, index| {
        result[index] = try terminal_text.stripAlloc(gpa, line);
        initialized += 1;
    }
    return result;
}

test "stack allocation grows shrinks and obeys bounds" {
    const gpa = std.testing.allocator;
    const dummy = Component{ .context = undefined, .vtable = undefined };
    const entries = [_]StackEntry{
        .{ .component = dummy, .basis = 2, .grow = 1, .min_size = 1, .max_size = 5 },
        .{ .component = dummy, .basis = 4, .grow = 2, .shrink = 0 },
    };
    const intrinsic = [_]usize{ 2, 4 };
    const grown = try allocateStackSizes(gpa, &entries, &intrinsic, 10, 1);
    defer gpa.free(grown);
    try std.testing.expectEqualSlices(usize, &.{ 4, 5 }, grown);
    const shrunk = try allocateStackSizes(gpa, &entries, &intrinsic, 5, 1);
    defer gpa.free(shrunk);
    try std.testing.expectEqualSlices(usize, &.{ 1, 4 }, shrunk);
}

test "vertical stack uses grow gap and clipping" {
    const gpa = std.testing.allocator;
    var top = StaticLines{ .lines = &.{"top"} };
    var body = StaticLines{ .lines = &.{ "one", "two", "three", "four" } };
    var bottom = StaticLines{ .lines = &.{"dock"} };
    const entries = [_]StackEntry{
        .{ .component = top.component(), .basis = 1, .shrink = 0 },
        .{ .component = body.component(), .basis = 0, .grow = 1, .min_size = 1 },
        .{ .component = bottom.component(), .basis = 1, .shrink = 0 },
    };
    var stack = Stack{ .axis = .vertical, .entries = &entries };
    var frame = try renderFrame(gpa, stack.component(), 8, 4);
    defer frame.deinit(gpa);
    const stripped = try strippedLines(gpa, frame.lines.items);
    defer {
        for (stripped) |line| gpa.free(line);
        gpa.free(stripped);
    }
    try std.testing.expectEqualStrings("top     ", stripped[0]);
    try std.testing.expectEqualStrings("three   ", stripped[1]);
    try std.testing.expectEqualStrings("four    ", stripped[2]);
    try std.testing.expectEqualStrings("dock    ", stripped[3]);
}

test "horizontal stack composes allocated columns and wide text" {
    const gpa = std.testing.allocator;
    var left = StaticLines{ .lines = &.{"界"} };
    var right = StaticLines{ .lines = &.{"right"} };
    const entries = [_]StackEntry{
        .{ .component = left.component(), .basis = 4, .shrink = 0 },
        .{ .component = right.component(), .basis = 6, .shrink = 0 },
    };
    var stack = Stack{ .axis = .horizontal, .entries = &entries, .gap = 1 };
    var frame = try renderFrame(gpa, stack.component(), 11, 1);
    defer frame.deinit(gpa);
    const stripped = try terminal_text.stripAlloc(gpa, frame.lines.items[0]);
    defer gpa.free(stripped);
    try std.testing.expectEqualStrings("界   right ", stripped);
    try std.testing.expectEqual(@as(usize, 11), terminal_text.visibleWidth(frame.lines.items[0]));
}

test "scroll view follows end and returns unused overscroll" {
    const gpa = std.testing.allocator;
    var content = StaticLines{ .lines = &.{ "1", "2", "3", "4", "5", "6" } };
    var scroll = ScrollView.init(content.component(), true);
    scroll.primary = true;
    var frame = try renderFrame(gpa, scroll.component(), 4, 3);
    defer frame.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), scroll.scroll_top);
    try std.testing.expect(scroll.following_end);
    try std.testing.expectEqual(@as(isize, 0), scroll.scrollBy(-2));
    try std.testing.expectEqual(@as(usize, 1), scroll.scroll_top);
    try std.testing.expect(!scroll.following_end);
    try std.testing.expectEqual(@as(isize, -2), scroll.scrollBy(-3));
    try std.testing.expectEqual(@as(usize, 0), scroll.scroll_top);
    try std.testing.expectEqual(@as(isize, 7), scroll.scrollBy(10));
    try std.testing.expectEqual(@as(usize, 3), scroll.scroll_top);
}

test "scrollbar geometry is proportional and reserves always column" {
    var dummy = StaticLines{ .lines = &.{"x"} };
    var scroll = ScrollView.init(dummy.component(), false);
    scroll.scrollbar = .always;
    scroll.updateLayout(100, 20);
    scroll.scroll_top = 40;
    const geometry = scrollbarGeometry(&scroll, 5, 0).?;
    try std.testing.expectEqual(@as(usize, 4), geometry.thumb_height);
    try std.testing.expectEqual(@as(usize, 8), geometry.thumb_top);
    try std.testing.expectEqual(@as(usize, 5), scroll.getContentWidth(6));
}

test "text and truncated text honor terminal cells" {
    const gpa = std.testing.allocator;
    var text = try Text.init(gpa, "hello 世界", 1, 0);
    defer text.deinit();
    var rendered = try text.component().render(gpa, 8);
    defer rendered.deinit(gpa);
    for (rendered.items) |line| try std.testing.expectEqual(@as(usize, 8), terminal_text.visibleWidth(line));

    var truncated = TruncatedText{ .text = "a界bcdef", .ellipsis = "…" };
    var one = try truncated.component().render(gpa, 5);
    defer one.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 5), terminal_text.visibleWidth(one.items[0]));
    try std.testing.expect(std.mem.indexOf(u8, one.items[0], "界") != null);
}

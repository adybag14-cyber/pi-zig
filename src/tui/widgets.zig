//! Interactive retained-mode widgets used by the Pi alternate-screen shell.
const std = @import("std");
const layout = @import("layout.zig");
const terminal_text = @import("terminal_text.zig");
const keys = @import("keys.zig");
const fuzzy = @import("fuzzy.zig");
const mouse = @import("mouse.zig");
const Editor = @import("editor.zig").Editor;
const EditorAction = @import("editor.zig").Action;

pub const cursor_marker = "\x1b_pi:c\x07";

pub const VoidCallback = struct {
    context: ?*anyopaque = null,
    call: *const fn (?*anyopaque) void,

    pub fn invoke(self: VoidCallback) void {
        self.call(self.context);
    }
};

pub const TextCallback = struct {
    context: ?*anyopaque = null,
    call: *const fn (?*anyopaque, []const u8) void,

    pub fn invoke(self: TextCallback, value: []const u8) void {
        self.call(self.context, value);
    }
};

pub const IndexCallback = struct {
    context: ?*anyopaque = null,
    call: *const fn (?*anyopaque, usize) void,

    pub fn invoke(self: IndexCallback, index: usize) void {
        self.call(self.context, index);
    }
};

fn styleAlloc(gpa: std.mem.Allocator, sgr: ?[]const u8, text: []const u8) ![]u8 {
    const code = sgr orelse return gpa.dupe(u8, text);
    return std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{ code, text });
}

fn padAlloc(gpa: std.mem.Allocator, text: []const u8, width: usize) ![]u8 {
    const clipped = try terminal_text.truncateAlloc(gpa, text, width, .{ .ellipsis = "", .reset_style = false });
    errdefer gpa.free(clipped);
    const visible = terminal_text.visibleWidth(clipped);
    if (visible >= width) return clipped;
    const old_len = clipped.len;
    const grown = try gpa.realloc(clipped, old_len + width - visible);
    @memset(grown[old_len..], ' ');
    return grown;
}

fn singleLineAlloc(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var previous_space = false;
    for (value) |byte| {
        const whitespace = byte == '\r' or byte == '\n' or byte == '\t';
        if (whitespace) {
            if (!previous_space) try out.append(gpa, ' ');
            previous_space = true;
        } else {
            try out.append(gpa, byte);
            previous_space = byte == ' ';
        }
    }
    const owned = try out.toOwnedSlice(gpa);
    const trimmed = std.mem.trim(u8, owned, " ");
    if (trimmed.ptr == owned.ptr and trimmed.len == owned.len) return owned;
    const result = try gpa.dupe(u8, trimmed);
    gpa.free(owned);
    return result;
}

pub const Box = struct {
    children: []const layout.Component,
    padding_x: usize = 1,
    padding_y: usize = 1,
    background_sgr: ?[]const u8 = null,

    pub fn component(self: *Box) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Box = @ptrCast(@alignCast(raw));
        if (self.children.len == 0) return .{};
        const content_width = @max(@as(usize, 1), width -| self.padding_x *| 2);
        var content: std.ArrayList([]u8) = .empty;
        defer {
            for (content.items) |line| gpa.free(line);
            content.deinit(gpa);
        }
        for (self.children) |child| {
            var rendered = try child.render(gpa, content_width);
            defer rendered.deinit(gpa);
            for (rendered.items) |line| {
                var writer: std.Io.Writer.Allocating = .init(gpa);
                errdefer writer.deinit();
                try writer.writer.splatByteAll(' ', self.padding_x);
                try writer.writer.writeAll(line);
                try writer.writer.splatByteAll(' ', self.padding_x);
                try content.append(gpa, try writer.toOwnedSlice());
            }
        }
        if (content.items.len == 0) return .{};

        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        for (0..self.padding_y) |_| {
            const blank = try padAlloc(gpa, "", width);
            defer gpa.free(blank);
            try lines.append(gpa, try styleAlloc(gpa, self.background_sgr, blank));
        }
        for (content.items) |line| {
            const padded = try padAlloc(gpa, line, width);
            defer gpa.free(padded);
            try lines.append(gpa, try styleAlloc(gpa, self.background_sgr, padded));
        }
        for (0..self.padding_y) |_| {
            const blank = try padAlloc(gpa, "", width);
            defer gpa.free(blank);
            try lines.append(gpa, try styleAlloc(gpa, self.background_sgr, blank));
        }
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }

    fn invalidateOpaque(raw: *anyopaque) void {
        const self: *Box = @ptrCast(@alignCast(raw));
        for (self.children) |child| child.invalidate();
    }

    const vtable: layout.Component.VTable = .{ .render = renderOpaque, .invalidate = invalidateOpaque };
};

pub const Input = struct {
    gpa: std.mem.Allocator,
    editor: Editor,
    prefix: []const u8 = "",
    placeholder: []const u8 = "",
    focused: bool = false,
    password: bool = false,
    normal_sgr: ?[]const u8 = null,
    placeholder_sgr: ?[]const u8 = "2",
    on_submit: ?TextCallback = null,
    on_escape: ?VoidCallback = null,
    on_change: ?TextCallback = null,

    pub fn init(gpa: std.mem.Allocator) Input {
        return .{ .gpa = gpa, .editor = Editor.init(gpa) };
    }

    pub fn deinit(self: *Input) void {
        self.editor.deinit();
        self.* = undefined;
    }

    pub fn component(self: *Input) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn value(self: *const Input) []const u8 {
        return self.editor.slice();
    }

    pub fn setValue(self: *Input, value_: []const u8) !void {
        try self.editor.setText(value_);
        self.notifyChange();
    }

    pub fn setFocused(self: *Input, focused: bool) void {
        self.focused = focused;
    }

    pub fn insertPaste(self: *Input, data: []const u8) !void {
        const normalized = try singleLineAlloc(self.gpa, data);
        defer self.gpa.free(normalized);
        try self.editor.insert(normalized);
        self.notifyChange();
    }

    fn notifyChange(self: *Input) void {
        if (self.on_change) |callback| callback.invoke(self.editor.slice());
    }

    fn apply(self: *Input, action: EditorAction) !void {
        try self.editor.apply(action);
        self.notifyChange();
    }

    fn handleParsed(self: *Input, key: keys.ParsedKey) !bool {
        if (key.event_type == .release) return true;
        const mods = key.effectiveModifiers();
        switch (key.key) {
            .named => |named| switch (named) {
                .escape => {
                    if (self.on_escape) |callback| callback.invoke();
                    return true;
                },
                .enter => {
                    if (self.on_submit) |callback| callback.invoke(self.editor.slice());
                    return true;
                },
                .backspace => {
                    try self.apply(if ((mods & keys.modifier_alt) != 0) .delete_word_backward else .delete_char_backward);
                    return true;
                },
                .delete => {
                    try self.apply(if ((mods & keys.modifier_alt) != 0) .delete_word_forward else .delete_char_forward);
                    return true;
                },
                .left => {
                    try self.apply(if ((mods & (keys.modifier_alt | keys.modifier_ctrl)) != 0) .cursor_word_left else .cursor_left);
                    return true;
                },
                .right => {
                    try self.apply(if ((mods & (keys.modifier_alt | keys.modifier_ctrl)) != 0) .cursor_word_right else .cursor_right);
                    return true;
                },
                .home => {
                    try self.apply(.cursor_line_start);
                    return true;
                },
                .end => {
                    try self.apply(.cursor_line_end);
                    return true;
                },
                .up => {
                    try self.apply(.history_previous);
                    return true;
                },
                .down => {
                    try self.apply(.history_next);
                    return true;
                },
                else => {},
            },
            .codepoint => |cp| {
                if ((mods & keys.modifier_ctrl) != 0 and cp <= 0x7f) {
                    switch (std.ascii.toLower(@intCast(cp))) {
                        'a' => try self.apply(.cursor_line_start),
                        'e' => try self.apply(.cursor_line_end),
                        'b' => try self.apply(.cursor_left),
                        'f' => try self.apply(.cursor_right),
                        'w' => try self.apply(.delete_word_backward),
                        'd' => try self.apply(.delete_char_forward),
                        'k' => try self.apply(.delete_to_line_end),
                        'u' => try self.apply(.delete_to_line_start),
                        'y' => try self.apply(.yank),
                        'z', '_' => try self.apply(.undo),
                        'c' => if (self.on_escape) |callback| callback.invoke(),
                        else => return false,
                    }
                    return true;
                }
                if ((mods & keys.modifier_alt) != 0 and cp <= 0x7f) {
                    switch (std.ascii.toLower(@intCast(cp))) {
                        'b' => try self.apply(.cursor_word_left),
                        'f' => try self.apply(.cursor_word_right),
                        'd' => try self.apply(.delete_word_forward),
                        else => return false,
                    }
                    return true;
                }
            },
        }
        return false;
    }

    pub fn handleInput(self: *Input, data: []const u8) !void {
        if (keys.parseKey(data)) |key| if (try self.handleParsed(key)) return;
        const decoded = try keys.decodePrintableKey(self.gpa, data);
        if (decoded) |printable| {
            defer self.gpa.free(printable);
            if (printable.len > 0) {
                try self.editor.insert(printable);
                self.notifyChange();
            }
            return;
        }
        if (std.unicode.utf8ValidateSlice(data)) {
            for (data) |byte| if (byte < 0x20 or byte == 0x7f) return;
            try self.editor.insert(data);
            self.notifyChange();
        }
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width_raw: usize) !layout.RenderedLines {
        const self: *Input = @ptrCast(@alignCast(raw));
        const width = @max(@as(usize, 1), width_raw);
        const prefix_width = @min(width, terminal_text.visibleWidth(self.prefix));
        const available = @max(@as(usize, 1), width -| prefix_width);
        var content: []u8 = undefined;

        if (self.editor.slice().len == 0 and !self.focused and self.placeholder.len > 0) {
            const placeholder = try terminal_text.truncateAlloc(gpa, self.placeholder, available, .{});
            defer gpa.free(placeholder);
            const styled = try styleAlloc(gpa, self.placeholder_sgr, placeholder);
            defer gpa.free(styled);
            content = try std.fmt.allocPrint(gpa, "{s}{s}", .{ self.prefix, styled });
        } else {
            const source = self.editor.slice();
            const cursor = @min(self.editor.cursor, source.len);
            const before_source = source[0..cursor];
            const after_source = source[cursor..];
            const before_width = terminal_text.visibleWidth(before_source);
            const cursor_reserve: usize = if (self.focused) 1 else 0;
            const visible_capacity = available -| cursor_reserve;
            const start_column = before_width -| visible_capacity;
            var before = try terminal_text.sliceByColumnsAlloc(gpa, before_source, start_column, visible_capacity);
            defer gpa.free(before);
            if (self.password) {
                const cells = terminal_text.visibleWidth(before);
                gpa.free(before);
                before = try gpa.alloc(u8, cells);
                @memset(before, '*');
            }
            const used = terminal_text.visibleWidth(before);
            const after_capacity = available -| used -| cursor_reserve;
            var after = try terminal_text.truncateAlloc(gpa, after_source, after_capacity, .{ .ellipsis = "", .reset_style = false });
            defer gpa.free(after);
            if (self.password) {
                const cells = terminal_text.visibleWidth(after);
                gpa.free(after);
                after = try gpa.alloc(u8, cells);
                @memset(after, '*');
            }
            content = try std.fmt.allocPrint(gpa, "{s}{s}{s}{s}", .{ self.prefix, before, if (self.focused) cursor_marker else "", after });
        }
        defer gpa.free(content);
        const styled = try styleAlloc(gpa, self.normal_sgr, content);
        defer gpa.free(styled);
        const line = try padAlloc(gpa, styled, width);
        const items = try gpa.alloc([]u8, 1);
        items[0] = line;
        return .{ .items = items };
    }

    fn handleOpaque(raw: *anyopaque, data: []const u8) !void {
        const self: *Input = @ptrCast(@alignCast(raw));
        try self.handleInput(data);
    }

    fn pasteOpaque(raw: *anyopaque, data: []const u8) !void {
        const self: *Input = @ptrCast(@alignCast(raw));
        try self.insertPaste(data);
    }

    fn focusOpaque(raw: *anyopaque, focused: bool) void {
        const self: *Input = @ptrCast(@alignCast(raw));
        self.setFocused(focused);
    }

    const vtable: layout.Component.VTable = .{
        .render = renderOpaque,
        .handle_input = handleOpaque,
        .handle_paste = pasteOpaque,
        .set_focus = focusOpaque,
    };
};

pub const SelectItem = struct {
    value: []const u8,
    label: []const u8,
    description: ?[]const u8 = null,
    disabled: bool = false,
};

pub const SelectTheme = struct {
    selected_sgr: ?[]const u8 = "7",
    description_sgr: ?[]const u8 = "2",
    scroll_sgr: ?[]const u8 = "2",
    disabled_sgr: ?[]const u8 = "2",
    no_match_sgr: ?[]const u8 = "2",
};

pub const SelectList = struct {
    gpa: std.mem.Allocator,
    items: []const SelectItem,
    filtered: std.ArrayList(usize) = .empty,
    filter: std.ArrayList(u8) = .empty,
    selected: usize = 0,
    max_visible: usize = 5,
    theme: SelectTheme = .{},
    on_select: ?IndexCallback = null,
    on_cancel: ?VoidCallback = null,
    on_change: ?IndexCallback = null,

    pub fn init(gpa: std.mem.Allocator, items: []const SelectItem, max_visible: usize) !SelectList {
        var self = SelectList{ .gpa = gpa, .items = items, .max_visible = @max(@as(usize, 1), max_visible) };
        errdefer self.deinit();
        try self.rebuildFilter();
        return self;
    }

    pub fn deinit(self: *SelectList) void {
        self.filtered.deinit(self.gpa);
        self.filter.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn component(self: *SelectList) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn setFilter(self: *SelectList, value: []const u8) !void {
        self.filter.clearRetainingCapacity();
        try self.filter.appendSlice(self.gpa, value);
        try self.rebuildFilter();
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;
        var i: usize = 0;
        while (i + needle.len <= haystack.len) : (i += 1) {
            if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
        }
        return false;
    }

    fn rebuildFilter(self: *SelectList) !void {
        self.filtered.clearRetainingCapacity();
        for (self.items, 0..) |item, index| {
            if (containsIgnoreCase(item.value, self.filter.items) or containsIgnoreCase(item.label, self.filter.items)) {
                try self.filtered.append(self.gpa, index);
            }
        }
        self.selected = 0;
        self.seekEnabled(1);
    }

    fn seekEnabled(self: *SelectList, direction: isize) void {
        if (self.filtered.items.len == 0) return;
        self.selected = @min(self.selected, self.filtered.items.len - 1);
        if (!self.items[self.filtered.items[self.selected]].disabled) return;
        var position = self.selected;
        for (0..self.filtered.items.len) |_| {
            position = if (direction < 0)
                (if (position == 0) self.filtered.items.len - 1 else position - 1)
            else
                (position + 1) % self.filtered.items.len;
            if (!self.items[self.filtered.items[position]].disabled) {
                self.selected = position;
                return;
            }
        }
    }

    pub fn selectedItemIndex(self: *const SelectList) ?usize {
        if (self.filtered.items.len == 0) return null;
        return self.filtered.items[self.selected];
    }

    pub fn setSelectedIndex(self: *SelectList, item_index: usize) void {
        for (self.filtered.items, 0..) |index, position| if (index == item_index) {
            self.selected = position;
            self.seekEnabled(1);
            return;
        };
    }

    fn move(self: *SelectList, delta: isize) void {
        if (self.filtered.items.len == 0) return;
        const length: isize = @intCast(self.filtered.items.len);
        var next = @as(isize, @intCast(self.selected)) + delta;
        next = @mod(next, length);
        self.selected = @intCast(next);
        self.seekEnabled(if (delta < 0) -1 else 1);
        if (self.on_change) |callback| if (self.selectedItemIndex()) |index| callback.invoke(index);
    }

    pub fn selectVisibleRow(self: *SelectList, row: usize) void {
        if (self.filtered.items.len == 0) return;
        const range = self.visibleRange();
        const position = range.start + row;
        if (position >= range.end) return;
        self.selected = position;
        self.seekEnabled(1);
        if (self.on_change) |callback| if (self.selectedItemIndex()) |index| callback.invoke(index);
    }

    fn visibleRange(self: *const SelectList) struct { start: usize, end: usize } {
        if (self.filtered.items.len <= self.max_visible) return .{ .start = 0, .end = self.filtered.items.len };
        const half = self.max_visible / 2;
        const max_start = self.filtered.items.len - self.max_visible;
        const start = @min(self.selected -| half, max_start);
        return .{ .start = start, .end = start + self.max_visible };
    }

    pub fn handleInput(self: *SelectList, data: []const u8) void {
        const key = keys.parseKey(data) orelse return;
        if (key.event_type == .release) return;
        switch (key.key) {
            .named => |named| switch (named) {
                .up => self.move(-1),
                .down => self.move(1),
                .page_up => self.move(-@as(isize, @intCast(self.max_visible))),
                .page_down => self.move(@intCast(self.max_visible)),
                .home => {
                    self.selected = 0;
                    self.seekEnabled(1);
                },
                .end => {
                    if (self.filtered.items.len > 0) self.selected = self.filtered.items.len - 1;
                    self.seekEnabled(-1);
                },
                .enter => if (self.on_select) |callback| if (self.selectedItemIndex()) |index| callback.invoke(index),
                .escape => if (self.on_cancel) |callback| callback.invoke(),
                else => {},
            },
            .codepoint => |cp| {
                if (cp == 'j' and (key.effectiveModifiers() & keys.modifier_ctrl) != 0) self.move(1) else if (cp == 'k' and (key.effectiveModifiers() & keys.modifier_ctrl) != 0) self.move(-1);
            },
        }
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *SelectList = @ptrCast(@alignCast(raw));
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        if (self.filtered.items.len == 0) {
            const styled = try styleAlloc(gpa, self.theme.no_match_sgr, "  No matching items");
            defer gpa.free(styled);
            try lines.append(gpa, try padAlloc(gpa, styled, width));
            return .{ .items = try lines.toOwnedSlice(gpa) };
        }

        var primary_width: usize = 1;
        for (self.filtered.items) |index| primary_width = @max(primary_width, terminal_text.visibleWidth(self.items[index].label));
        primary_width = @min(@as(usize, 32), primary_width + 2);
        const range = self.visibleRange();
        for (range.start..range.end) |position| {
            const item = self.items[self.filtered.items[position]];
            const selected = position == self.selected;
            const prefix = if (selected) "→ " else "  ";
            const prefix_width = terminal_text.visibleWidth(prefix);
            const max_label = @max(@as(usize, 1), @min(primary_width, width -| prefix_width));
            const label = try terminal_text.truncateAlloc(gpa, item.label, max_label, .{ .ellipsis = "…" });
            defer gpa.free(label);
            var row: std.Io.Writer.Allocating = .init(gpa);
            defer row.deinit();
            try row.writer.writeAll(prefix);
            try row.writer.writeAll(label);
            if (item.description != null and width > 40) {
                const label_width = terminal_text.visibleWidth(label);
                const spacing = @max(@as(usize, 1), primary_width -| label_width);
                try row.writer.splatByteAll(' ', spacing);
                const used = prefix_width + label_width + spacing;
                const remaining = width -| used;
                if (remaining > 3) {
                    const one_line = try singleLineAlloc(gpa, item.description.?);
                    defer gpa.free(one_line);
                    const desc = try terminal_text.truncateAlloc(gpa, one_line, remaining, .{ .ellipsis = "…" });
                    defer gpa.free(desc);
                    const styled_desc = try styleAlloc(gpa, self.theme.description_sgr, desc);
                    defer gpa.free(styled_desc);
                    try row.writer.writeAll(styled_desc);
                }
            }
            const raw_line = try row.toOwnedSlice();
            defer gpa.free(raw_line);
            const line_sgr = if (item.disabled) self.theme.disabled_sgr else if (selected) self.theme.selected_sgr else null;
            const styled = try styleAlloc(gpa, line_sgr, raw_line);
            defer gpa.free(styled);
            try lines.append(gpa, try padAlloc(gpa, styled, width));
        }
        if (range.start > 0 or range.end < self.filtered.items.len) {
            const info = try std.fmt.allocPrint(gpa, "  ({d}/{d})", .{ self.selected + 1, self.filtered.items.len });
            defer gpa.free(info);
            const styled = try styleAlloc(gpa, self.theme.scroll_sgr, info);
            defer gpa.free(styled);
            try lines.append(gpa, try padAlloc(gpa, styled, width));
        }
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }

    fn handleOpaque(raw: *anyopaque, data: []const u8) !void {
        const self: *SelectList = @ptrCast(@alignCast(raw));
        self.handleInput(data);
    }

    fn mouseOpaque(raw: *anyopaque, event: mouse.Event) !bool {
        const self: *SelectList = @ptrCast(@alignCast(raw));
        if (event.button != .left or event.kind != .press) return false;
        self.selectVisibleRow(event.y);
        if (self.on_select) |callback| if (self.selectedItemIndex()) |index| callback.invoke(index);
        return true;
    }

    const vtable: layout.Component.VTable = .{
        .render = renderOpaque,
        .handle_input = handleOpaque,
        .handle_mouse = mouseOpaque,
    };
};

pub const SettingItem = struct {
    id: []const u8,
    label: []const u8,
    description: ?[]const u8 = null,
    values: []const []const u8,
    current_index: usize = 0,
    disabled: bool = false,
};

pub const SettingCallback = struct {
    context: ?*anyopaque = null,
    call: *const fn (?*anyopaque, []const u8, []const u8) void,

    pub fn invoke(self: SettingCallback, id: []const u8, value: []const u8) void {
        self.call(self.context, id, value);
    }
};

pub const SettingsList = struct {
    gpa: std.mem.Allocator,
    items: []SettingItem,
    filtered: std.ArrayList(usize) = .empty,
    selected: usize = 0,
    max_visible: usize = 8,
    query: std.ArrayList(u8) = .empty,
    cursor_sgr: ?[]const u8 = "7",
    value_sgr: ?[]const u8 = "36",
    description_sgr: ?[]const u8 = "2",
    on_change: ?SettingCallback = null,
    on_cancel: ?VoidCallback = null,

    pub fn init(gpa: std.mem.Allocator, items: []SettingItem, max_visible: usize) !SettingsList {
        var self = SettingsList{ .gpa = gpa, .items = items, .max_visible = @max(@as(usize, 1), max_visible) };
        errdefer self.deinit();
        try self.refilter();
        return self;
    }

    pub fn deinit(self: *SettingsList) void {
        self.filtered.deinit(self.gpa);
        self.query.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn component(self: *SettingsList) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn setQuery(self: *SettingsList, query: []const u8) !void {
        self.query.clearRetainingCapacity();
        try self.query.appendSlice(self.gpa, query);
        try self.refilter();
    }

    fn refilter(self: *SettingsList) !void {
        self.filtered.clearRetainingCapacity();
        for (self.items, 0..) |item, index| {
            const fields = [_][]const u8{ item.id, item.label, item.description orelse "" };
            if (fuzzy.bestScore(&fields, self.query.items) != null) try self.filtered.append(self.gpa, index);
        }
        self.selected = 0;
        self.skipDisabled(1);
    }

    fn skipDisabled(self: *SettingsList, direction: isize) void {
        if (self.filtered.items.len == 0) return;
        self.selected = @min(self.selected, self.filtered.items.len - 1);
        if (!self.items[self.filtered.items[self.selected]].disabled) return;
        for (0..self.filtered.items.len) |_| {
            self.selected = if (direction < 0)
                (if (self.selected == 0) self.filtered.items.len - 1 else self.selected - 1)
            else
                (self.selected + 1) % self.filtered.items.len;
            if (!self.items[self.filtered.items[self.selected]].disabled) return;
        }
    }

    fn move(self: *SettingsList, direction: isize) void {
        if (self.filtered.items.len == 0) return;
        const length: isize = @intCast(self.filtered.items.len);
        self.selected = @intCast(@mod(@as(isize, @intCast(self.selected)) + direction, length));
        self.skipDisabled(direction);
    }

    fn cycle(self: *SettingsList, direction: isize) void {
        if (self.filtered.items.len == 0) return;
        const index = self.filtered.items[self.selected];
        var item = &self.items[index];
        if (item.disabled or item.values.len == 0) return;
        const length: isize = @intCast(item.values.len);
        item.current_index = @intCast(@mod(@as(isize, @intCast(@min(item.current_index, item.values.len - 1))) + direction, length));
        if (self.on_change) |callback| callback.invoke(item.id, item.values[item.current_index]);
    }

    pub fn updateValue(self: *SettingsList, id: []const u8, value: []const u8) bool {
        for (self.items) |*item| {
            if (!std.mem.eql(u8, item.id, id)) continue;
            for (item.values, 0..) |candidate, index| if (std.mem.eql(u8, candidate, value)) {
                item.current_index = index;
                return true;
            };
            return false;
        }
        return false;
    }

    pub fn handleInput(self: *SettingsList, data: []const u8) void {
        const key = keys.parseKey(data) orelse return;
        if (key.event_type == .release) return;
        switch (key.key) {
            .named => |named| switch (named) {
                .up => self.move(-1),
                .down => self.move(1),
                .left => self.cycle(-1),
                .right, .enter, .space => self.cycle(1),
                .page_up => self.move(-@as(isize, @intCast(self.max_visible))),
                .page_down => self.move(@intCast(self.max_visible)),
                .escape => if (self.on_cancel) |callback| callback.invoke(),
                else => {},
            },
            .codepoint => |cp| if (cp == ' ') self.cycle(1),
        }
    }

    fn visibleRange(self: *const SettingsList) struct { start: usize, end: usize } {
        if (self.filtered.items.len <= self.max_visible) return .{ .start = 0, .end = self.filtered.items.len };
        const start = @min(self.selected -| (self.max_visible / 2), self.filtered.items.len - self.max_visible);
        return .{ .start = start, .end = start + self.max_visible };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *SettingsList = @ptrCast(@alignCast(raw));
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        if (self.filtered.items.len == 0) {
            try lines.append(gpa, try padAlloc(gpa, "  No matching settings", width));
            return .{ .items = try lines.toOwnedSlice(gpa) };
        }
        const range = self.visibleRange();
        for (range.start..range.end) |position| {
            const item = self.items[self.filtered.items[position]];
            const selected = position == self.selected;
            const value = if (item.values.len == 0) "" else item.values[@min(item.current_index, item.values.len - 1)];
            const prefix = if (selected) "› " else "  ";
            const value_width = terminal_text.visibleWidth(value);
            const label_capacity = width -| terminal_text.visibleWidth(prefix) -| value_width -| 2;
            const label = try terminal_text.truncateAlloc(gpa, item.label, label_capacity, .{ .ellipsis = "…" });
            defer gpa.free(label);
            const spaces = @max(@as(usize, 1), width -| terminal_text.visibleWidth(prefix) -| terminal_text.visibleWidth(label) -| value_width);
            const styled_value = try styleAlloc(gpa, self.value_sgr, value);
            defer gpa.free(styled_value);
            var writer: std.Io.Writer.Allocating = .init(gpa);
            defer writer.deinit();
            try writer.writer.writeAll(prefix);
            try writer.writer.writeAll(label);
            try writer.writer.splatByteAll(' ', spaces);
            try writer.writer.writeAll(styled_value);
            const raw_line = try writer.toOwnedSlice();
            defer gpa.free(raw_line);
            const styled = try styleAlloc(gpa, if (item.disabled) "2" else if (selected) self.cursor_sgr else null, raw_line);
            defer gpa.free(styled);
            try lines.append(gpa, try padAlloc(gpa, styled, width));
            if (selected and item.description != null and lines.items.len < self.max_visible + 2) {
                const desc_width = width -| 4;
                const desc = try terminal_text.truncateAlloc(gpa, item.description.?, desc_width, .{ .ellipsis = "…" });
                defer gpa.free(desc);
                const desc_row = try std.fmt.allocPrint(gpa, "    {s}", .{desc});
                defer gpa.free(desc_row);
                const styled_desc = try styleAlloc(gpa, self.description_sgr, desc_row);
                defer gpa.free(styled_desc);
                try lines.append(gpa, try padAlloc(gpa, styled_desc, width));
            }
        }
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }

    fn handleOpaque(raw: *anyopaque, data: []const u8) !void {
        const self: *SettingsList = @ptrCast(@alignCast(raw));
        self.handleInput(data);
    }

    fn mouseOpaque(raw: *anyopaque, event: mouse.Event) !bool {
        const self: *SettingsList = @ptrCast(@alignCast(raw));
        if (event.button != .left or event.kind != .press or self.filtered.items.len == 0) return false;
        const range = self.visibleRange();
        var row: usize = 0;
        var position = range.start;
        while (position < range.end) : (position += 1) {
            if (event.y == row) {
                self.selected = position;
                self.skipDisabled(1);
                self.cycle(1);
                return true;
            }
            row += 1;
            const item = self.items[self.filtered.items[position]];
            if (position == self.selected and item.description != null) row += 1;
        }
        return false;
    }

    const vtable: layout.Component.VTable = .{
        .render = renderOpaque,
        .handle_input = handleOpaque,
        .handle_mouse = mouseOpaque,
    };
};

pub const Loader = struct {
    message: []const u8,
    frame: usize = 0,
    cancelled: bool = false,
    cancellable: bool = false,
    spinner_sgr: ?[]const u8 = "36",
    message_sgr: ?[]const u8 = null,
    on_cancel: ?VoidCallback = null,

    const frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

    pub fn tick(self: *Loader) void {
        self.frame +%= 1;
    }

    pub fn component(self: *Loader) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Loader = @ptrCast(@alignCast(raw));
        const spinner = try styleAlloc(gpa, self.spinner_sgr, frames[self.frame % frames.len]);
        defer gpa.free(spinner);
        const message = try styleAlloc(gpa, self.message_sgr, self.message);
        defer gpa.free(message);
        const hint = if (self.cancellable) "  (esc to cancel)" else "";
        const raw_line = try std.fmt.allocPrint(gpa, "{s} {s}{s}", .{ spinner, message, hint });
        defer gpa.free(raw_line);
        const line = try padAlloc(gpa, raw_line, width);
        const items = try gpa.alloc([]u8, 1);
        items[0] = line;
        return .{ .items = items };
    }

    fn handleOpaque(raw: *anyopaque, data: []const u8) !void {
        const self: *Loader = @ptrCast(@alignCast(raw));
        if (!self.cancellable or self.cancelled) return;
        const key = keys.parseKey(data) orelse return;
        if (key.event_type != .release and key.key == .named and key.key.named == .escape) {
            self.cancelled = true;
            if (self.on_cancel) |callback| callback.invoke();
        }
    }

    const vtable: layout.Component.VTable = .{ .render = renderOpaque, .handle_input = handleOpaque };
};

test "box applies padding and background around retained children" {
    const gpa = std.testing.allocator;
    var text = layout.StaticLines{ .lines = &.{"hello"} };
    const children = [_]layout.Component{text.component()};
    var box = Box{ .children = &children, .padding_x = 1, .padding_y = 1, .background_sgr = "44" };
    var rendered = try box.component().render(gpa, 10);
    defer rendered.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), rendered.items.len);
    try std.testing.expectEqual(@as(usize, 10), terminal_text.visibleWidth(rendered.items[1]));
    try std.testing.expect(std.mem.indexOf(u8, rendered.items[1], "hello") != null);
}

test "input is Unicode safe, horizontally scrolls and emits cursor marker" {
    const gpa = std.testing.allocator;
    var input = Input.init(gpa);
    defer input.deinit();
    input.focused = true;
    try input.setValue("ab界cd");
    try input.handleInput("\x1b[D");
    try input.handleInput("X");
    try std.testing.expectEqualStrings("ab界cXd", input.value());
    var rendered = try input.component().render(gpa, 7);
    defer rendered.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items[0], cursor_marker) != null);
    try std.testing.expectEqual(@as(usize, 7), terminal_text.visibleWidth(rendered.items[0]));
}

test "select list filters wraps skips disabled items and renders scrolling" {
    const gpa = std.testing.allocator;
    const items = [_]SelectItem{
        .{ .value = "alpha", .label = "Alpha" },
        .{ .value = "beta", .label = "Beta", .disabled = true },
        .{ .value = "gamma", .label = "Gamma", .description = "third item" },
        .{ .value = "delta", .label = "Delta" },
    };
    var list = try SelectList.init(gpa, &items, 2);
    defer list.deinit();
    list.handleInput("\x1b[B");
    try std.testing.expectEqual(@as(usize, 2), list.selectedItemIndex().?);
    list.handleInput("\x1b[A");
    try std.testing.expectEqual(@as(usize, 0), list.selectedItemIndex().?);
    try list.setFilter("ga");
    try std.testing.expectEqual(@as(usize, 2), list.selectedItemIndex().?);
    var rendered = try list.component().render(gpa, 50);
    defer rendered.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items[0], "Gamma") != null);
}

test "settings list cycles values and fuzzy filters" {
    const gpa = std.testing.allocator;
    const themes = [_][]const u8{ "dark", "light" };
    const modes = [_][]const u8{ "safe", "fast" };
    var settings = [_]SettingItem{
        .{ .id = "theme", .label = "Theme", .values = &themes },
        .{ .id = "mode", .label = "Execution mode", .description = "Controls tool execution", .values = &modes },
    };
    var list = try SettingsList.init(gpa, &settings, 5);
    defer list.deinit();
    list.handleInput("\x1b[C");
    try std.testing.expectEqualStrings("light", settings[0].values[settings[0].current_index]);
    try list.setQuery("exec");
    try std.testing.expectEqual(@as(usize, 1), list.filtered.items.len);
    var rendered = try list.component().render(gpa, 50);
    defer rendered.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items[0], "Execution mode") != null);
}

test "cancellable loader advances and consumes escape" {
    var loader = Loader{ .message = "Working", .cancellable = true };
    loader.tick();
    try loader.component().handleInput("\x1b");
    try std.testing.expect(loader.cancelled);
}

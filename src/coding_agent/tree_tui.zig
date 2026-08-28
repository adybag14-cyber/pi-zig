//! Retained fullscreen session-tree selector used by interactive `/tree`.
//! The selector preserves the append-only session topology while adding the
//! original workflow's search, filtering, branch folding, labels, and active
//! branch/tip indicators.
const std = @import("std");
const Io = std.Io;
const session_mod = @import("../agent/session.zig");
const application = @import("../tui/application.zig");
const layout = @import("../tui/layout.zig");
const line_editor = @import("../tui/line_editor.zig");
const keys = @import("../tui/keys.zig");
const mouse = @import("../tui/mouse.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const tui_render = @import("../tui/render.zig");
const clipboard = @import("clipboard.zig");

const accent = "\x1b[36m";
const success = "\x1b[32m";
const warning = "\x1b[33m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reverse = "\x1b[7m";
const reset = "\x1b[0m";

pub const FilterMode = enum {
    default,
    no_tools,
    user_only,
    labeled_only,
    all,

    fn next(self: FilterMode) FilterMode {
        return switch (self) {
            .default => .no_tools,
            .no_tools => .user_only,
            .user_only => .labeled_only,
            .labeled_only => .all,
            .all => .default,
        };
    }

    fn previous(self: FilterMode) FilterMode {
        return switch (self) {
            .default => .all,
            .no_tools => .default,
            .user_only => .no_tools,
            .labeled_only => .user_only,
            .all => .labeled_only,
        };
    }

    pub fn parse(value: []const u8) ?FilterMode {
        if (std.ascii.eqlIgnoreCase(value, "default")) return .default;
        if (std.ascii.eqlIgnoreCase(value, "no-tools") or std.ascii.eqlIgnoreCase(value, "no_tools")) return .no_tools;
        if (std.ascii.eqlIgnoreCase(value, "user-only") or std.ascii.eqlIgnoreCase(value, "user_only")) return .user_only;
        if (std.ascii.eqlIgnoreCase(value, "labeled-only") or std.ascii.eqlIgnoreCase(value, "labeled_only")) return .labeled_only;
        if (std.ascii.eqlIgnoreCase(value, "all")) return .all;
        return null;
    }

    pub fn wireName(self: FilterMode) []const u8 {
        return switch (self) {
            .default => "default",
            .no_tools => "no-tools",
            .user_only => "user-only",
            .labeled_only => "labeled-only",
            .all => "all",
        };
    }

    fn title(self: FilterMode) []const u8 {
        return switch (self) {
            .default => "default",
            .no_tools => "no tools",
            .user_only => "user only",
            .labeled_only => "labeled",
            .all => "all entries",
        };
    }
};

pub const Selection = struct {
    target_id: ?[]u8 = null,
    cancelled: bool = true,

    pub fn deinit(self: *Selection, gpa: std.mem.Allocator) void {
        if (self.target_id) |value| gpa.free(value);
        self.* = undefined;
    }
};

const Node = struct {
    entry: *const session_mod.SessionEntry,
    depth: usize,
    has_children: bool,
    active_branch: bool,
    active_tip: bool,
};

const Selector = struct {
    gpa: std.mem.Allocator,
    io: Io,
    sess: *session_mod.Session,
    nodes: std.ArrayList(Node) = .empty,
    visible: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    folded: std.StringHashMap(void),
    selected: usize = 0,
    viewport_rows: usize = 30,
    filter_mode: FilterMode = .default,
    done: bool = false,
    cancelled: bool = true,
    result_id: ?[]u8 = null,
    status: ?[]u8 = null,
    editing_label: bool = false,
    label_input: std.ArrayList(u8) = .empty,
    show_label_timestamps: bool = false,
    rendered_start: usize = 0,
    rendered_count: usize = 0,
    clipboard_options: clipboard.Options = .{},

    fn init(gpa: std.mem.Allocator, io: Io, sess: *session_mod.Session) !Selector {
        return initWithFilter(gpa, io, sess, .default);
    }

    fn initWithFilter(gpa: std.mem.Allocator, io: Io, sess: *session_mod.Session, initial_filter: FilterMode) !Selector {
        var self: Selector = .{
            .gpa = gpa,
            .io = io,
            .sess = sess,
            .folded = std.StringHashMap(void).init(gpa),
            .filter_mode = initial_filter,
        };
        errdefer self.deinit();
        try self.rebuildNodes();
        try self.rebuildVisible(true);
        return self;
    }

    fn deinit(self: *Selector) void {
        if (self.result_id) |value| self.gpa.free(value);
        if (self.status) |value| self.gpa.free(value);
        self.folded.deinit();
        self.label_input.deinit(self.gpa);
        self.query.deinit(self.gpa);
        self.visible.deinit(self.gpa);
        self.nodes.deinit(self.gpa);
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

    fn renderCallback(context: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Selector = @ptrCast(@alignCast(context));
        return self.render(gpa, width);
    }

    fn inputCallback(context: *anyopaque, data: []const u8) !void {
        const self: *Selector = @ptrCast(@alignCast(context));
        try self.handleInput(data);
    }

    fn mouseCallback(context: *anyopaque, event: mouse.Event) !bool {
        const self: *Selector = @ptrCast(@alignCast(context));
        return try self.handleMouse(event);
    }

    fn focusCallback(_: *anyopaque, _: bool) void {}

    fn setStatus(self: *Selector, message: []const u8) !void {
        if (self.status) |old| self.gpa.free(old);
        self.status = try self.gpa.dupe(u8, message);
    }

    fn parentMatches(parent_id: ?[]const u8, wanted: ?[]const u8) bool {
        if (parent_id == null or wanted == null) return parent_id == null and wanted == null;
        return std.mem.eql(u8, parent_id.?, wanted.?);
    }

    fn hasChild(self: *const Selector, entry_id: []const u8) bool {
        for (self.sess.entries.items) |entry| {
            if (entry.parent_id) |parent| if (std.mem.eql(u8, parent, entry_id)) return true;
        }
        return false;
    }

    fn appendChildren(
        self: *Selector,
        parent_id: ?[]const u8,
        depth: usize,
        active_ids: *const std.StringHashMap(void),
        visited: *std.StringHashMap(void),
    ) !void {
        for (self.sess.entries.items) |*entry| {
            if (!parentMatches(entry.parent_id, parent_id)) continue;
            if (visited.contains(entry.id)) continue;
            try visited.put(entry.id, {});
            try self.nodes.append(self.gpa, .{
                .entry = entry,
                .depth = depth,
                .has_children = self.hasChild(entry.id),
                .active_branch = active_ids.contains(entry.id),
                .active_tip = if (self.sess.lastEntryId()) |tip| std.mem.eql(u8, tip, entry.id) else false,
            });
            try self.appendChildren(entry.id, depth + 1, active_ids, visited);
        }
    }

    fn rebuildNodes(self: *Selector) !void {
        self.nodes.clearRetainingCapacity();
        const active = try self.sess.branchEntries(self.gpa);
        defer self.gpa.free(active);
        var active_ids = std.StringHashMap(void).init(self.gpa);
        defer active_ids.deinit();
        for (active) |entry| try active_ids.put(entry.id, {});

        var visited = std.StringHashMap(void).init(self.gpa);
        defer visited.deinit();
        try self.appendChildren(null, 0, &active_ids, &visited);

        // Preserve malformed/orphaned records as selectable roots rather than
        // silently dropping durable history from the selector.
        for (self.sess.entries.items) |*entry| {
            if (visited.contains(entry.id)) continue;
            try visited.put(entry.id, {});
            try self.nodes.append(self.gpa, .{
                .entry = entry,
                .depth = 0,
                .has_children = self.hasChild(entry.id),
                .active_branch = active_ids.contains(entry.id),
                .active_tip = if (self.sess.lastEntryId()) |tip| std.mem.eql(u8, tip, entry.id) else false,
            });
            try self.appendChildren(entry.id, 1, &active_ids, &visited);
        }
    }

    fn isDefaultVisible(entry: *const session_mod.SessionEntry) bool {
        return switch (entry.entry_type) {
            .message, .compaction, .branch_summary, .custom_message => true,
            .session_info, .label, .custom, .model_change, .thinking_level_change => false,
        };
    }

    fn assistantOnlyToolCalls(node: Node) bool {
        const entry = node.entry;
        if (node.active_tip or entry.entry_type != .message or !std.mem.eql(u8, entry.role, "assistant")) return false;
        if (std.mem.trim(u8, entry.content, " \t\r\n").len > 0 or entry.meta.error_message.len > 0) return false;
        if (entry.meta.stop_reason.len > 0 and
            !std.ascii.eqlIgnoreCase(entry.meta.stop_reason, "stop") and
            !std.ascii.eqlIgnoreCase(entry.meta.stop_reason, "toolUse") and
            !std.ascii.eqlIgnoreCase(entry.meta.stop_reason, "tool_use")) return false;
        return entry.tool_calls_json != null;
    }

    fn modeMatches(self: *const Selector, node: Node) bool {
        const entry = node.entry;
        if (assistantOnlyToolCalls(node)) return false;
        return switch (self.filter_mode) {
            .default => isDefaultVisible(entry),
            .no_tools => isDefaultVisible(entry) and
                !std.ascii.eqlIgnoreCase(entry.role, "tool") and
                !std.ascii.eqlIgnoreCase(entry.role, "toolResult") and
                entry.tool_call_id == null,
            .user_only => entry.entry_type == .message and std.mem.eql(u8, entry.role, "user"),
            .labeled_only => self.sess.getLabel(entry.id) != null,
            .all => true,
        };
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;
        var index: usize = 0;
        while (index + needle.len <= haystack.len) : (index += 1) {
            if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
        }
        return false;
    }

    fn queryTokenMatches(self: *const Selector, node: Node, token: []const u8) bool {
        const entry = node.entry;
        inline for (.{ entry.id, entry.role, @tagName(entry.entry_type), entry.content, entry.meta.error_message }) |candidate| {
            if (containsIgnoreCase(candidate, token)) return true;
        }
        if (entry.bash_command) |value| if (containsIgnoreCase(value, token)) return true;
        if (entry.tool_name) |value| if (containsIgnoreCase(value, token)) return true;
        if (entry.custom_type) |value| if (containsIgnoreCase(value, token)) return true;
        if (self.sess.getLabel(entry.id)) |value| if (containsIgnoreCase(value, token)) return true;
        return false;
    }

    fn queryMatches(self: *const Selector, node: Node) bool {
        var tokens = std.mem.tokenizeAny(u8, self.query.items, " \t\r\n");
        while (tokens.next()) |token| {
            if (!self.queryTokenMatches(node, token)) return false;
        }
        return true;
    }

    fn hiddenByFold(self: *const Selector, node_index: usize) bool {
        if (self.query.items.len > 0) return false;
        const node = self.nodes.items[node_index];
        var depth = node.depth;
        if (depth == 0) return false;
        var index = node_index;
        while (index > 0 and depth > 0) {
            index -= 1;
            const candidate = self.nodes.items[index];
            if (candidate.depth >= depth) continue;
            depth = candidate.depth;
            if (self.folded.contains(candidate.entry.id)) return true;
        }
        return false;
    }

    fn rebuildVisible(self: *Selector, prefer_tip: bool) !void {
        const previous_id: ?[]const u8 = if (!prefer_tip) blk: {
            if (self.currentNode()) |node| break :blk node.entry.id;
            break :blk null;
        } else null;
        self.visible.clearRetainingCapacity();
        for (self.nodes.items, 0..) |node, index| {
            if (!self.modeMatches(node) or !self.queryMatches(node) or self.hiddenByFold(index)) continue;
            try self.visible.append(self.gpa, index);
        }
        if (self.visible.items.len == 0) {
            self.selected = 0;
            return;
        }
        if (prefer_tip) {
            var last_active: ?usize = null;
            for (self.visible.items, 0..) |node_index, visible_index| {
                const node = self.nodes.items[node_index];
                if (node.active_tip) {
                    self.selected = visible_index;
                    return;
                }
                if (node.active_branch) last_active = visible_index;
            }
            if (last_active) |visible_index| {
                self.selected = visible_index;
                return;
            }
        } else if (previous_id) |id| {
            for (self.visible.items, 0..) |node_index, visible_index| {
                if (std.mem.eql(u8, self.nodes.items[node_index].entry.id, id)) {
                    self.selected = visible_index;
                    return;
                }
            }
        }
        self.selected = @min(self.selected, self.visible.items.len - 1);
    }

    fn currentNode(self: *const Selector) ?Node {
        if (self.visible.items.len == 0 or self.selected >= self.visible.items.len) return null;
        return self.nodes.items[self.visible.items[self.selected]];
    }

    fn selectEntryId(self: *Selector, entry_id: []const u8) void {
        for (self.visible.items, 0..) |node_index, visible_index| {
            if (std.mem.eql(u8, self.nodes.items[node_index].entry.id, entry_id)) {
                self.selected = visible_index;
                return;
            }
        }
    }

    fn latestLabelEntry(self: *const Selector, target_id: []const u8) ?*const session_mod.SessionEntry {
        var resolved: ?*const session_mod.SessionEntry = null;
        for (self.sess.entries.items) |*entry| {
            if (entry.entry_type != .label) continue;
            const target = entry.target_id orelse continue;
            if (!std.mem.eql(u8, target, target_id)) continue;
            resolved = entry;
        }
        return resolved;
    }

    fn selectCurrent(self: *Selector) !void {
        const node = self.currentNode() orelse return;
        if (self.result_id) |old| self.gpa.free(old);
        self.result_id = try self.gpa.dupe(u8, node.entry.id);
        self.cancelled = false;
        self.done = true;
    }

    fn cycleFilter(self: *Selector) !void {
        try self.setFilter(self.filter_mode.next());
    }

    fn cycleFilterBackward(self: *Selector) !void {
        try self.setFilter(self.filter_mode.previous());
    }

    fn setFilter(self: *Selector, mode: FilterMode) !void {
        self.filter_mode = mode;
        self.folded.clearRetainingCapacity();
        self.selected = 0;
        try self.rebuildVisible(true);
    }

    fn startLabelEdit(self: *Selector) !void {
        const node = self.currentNode() orelse return;
        self.label_input.clearRetainingCapacity();
        if (self.sess.getLabel(node.entry.id)) |label| try self.label_input.appendSlice(self.gpa, label);
        self.editing_label = true;
        try self.setStatus("Editing label: Enter saves, Esc cancels");
    }

    fn cancelLabelEdit(self: *Selector) !void {
        self.editing_label = false;
        self.label_input.clearRetainingCapacity();
        try self.setStatus("Label edit cancelled");
    }

    fn commitLabelEdit(self: *Selector) !void {
        const node = self.currentNode() orelse return;
        const target_id = try self.gpa.dupe(u8, node.entry.id);
        defer self.gpa.free(target_id);
        const trimmed = std.mem.trim(u8, self.label_input.items, " \t\r\n");
        _ = try self.sess.appendLabelChange(target_id, if (trimmed.len == 0) null else trimmed);
        self.editing_label = false;
        self.label_input.clearRetainingCapacity();
        try self.rebuildNodes();
        try self.rebuildVisible(false);
        self.selectEntryId(target_id);
        try self.setStatus(if (trimmed.len == 0) "Label cleared" else "Label saved");
    }

    fn copyTextAlloc(self: *const Selector, entry: *const session_mod.SessionEntry) ![]u8 {
        // Match the original selector's user-facing copy projection rather than
        // copying transport wrappers or the rendered tree line.
        if (entry.bash_command) |command| if (std.mem.trim(u8, command, " \t\r\n").len > 0) return try self.gpa.dupe(u8, command);
        if (std.mem.trim(u8, entry.content, " \t\r\n").len > 0) return try self.gpa.dupe(u8, entry.content);
        if (entry.meta.error_message.len > 0) return try self.gpa.dupe(u8, entry.meta.error_message);
        return try std.fmt.allocPrint(self.gpa, "{s} {s}", .{ @tagName(entry.entry_type), entry.id });
    }

    fn copyCurrent(self: *Selector) !void {
        const node = self.currentNode() orelse return;
        const text = try self.copyTextAlloc(node.entry);
        defer self.gpa.free(text);
        _ = clipboard.copyText(self.gpa, self.io, text, self.clipboard_options) catch |err| {
            var buffer: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer, "Copy failed: {s}", .{@errorName(err)}) catch "Copy failed";
            return self.setStatus(message);
        };
        try self.setStatus("Selected entry copied to clipboard");
    }

    fn foldCurrent(self: *Selector) !void {
        const node = self.currentNode() orelse return;
        if (node.has_children and !self.folded.contains(node.entry.id)) {
            try self.folded.put(node.entry.id, {});
            try self.rebuildVisible(false);
            return;
        }
        // Left on an already folded/leaf node moves to its nearest visible parent.
        if (node.entry.parent_id) |parent| {
            for (self.visible.items, 0..) |node_index, visible_index| {
                if (std.mem.eql(u8, self.nodes.items[node_index].entry.id, parent)) {
                    self.selected = visible_index;
                    return;
                }
            }
        }
    }

    fn unfoldCurrent(self: *Selector) !void {
        const node = self.currentNode() orelse return;
        if (self.folded.remove(node.entry.id)) {
            try self.rebuildVisible(false);
            return;
        }
        const current_index = self.visible.items[self.selected];
        if (self.selected + 1 < self.visible.items.len) {
            const child_index = self.visible.items[self.selected + 1];
            if (self.nodes.items[child_index].depth > self.nodes.items[current_index].depth) self.selected += 1;
        }
    }

    fn moveSelection(self: *Selector, delta: isize) void {
        if (self.visible.items.len == 0 or delta == 0) return;
        const count: isize = @intCast(self.visible.items.len);
        const current: isize = @intCast(self.selected);
        var next = @mod(current + delta, count);
        if (next < 0) next += count;
        self.selected = @intCast(next);
    }

    fn popUtf8(list: *std.ArrayList(u8)) void {
        if (list.items.len == 0) return;
        _ = list.pop();
        while (list.items.len > 0 and (list.items[list.items.len - 1] & 0xc0) == 0x80) _ = list.pop();
    }

    fn clearSearchOrCancel(self: *Selector) !void {
        if (self.editing_label) {
            try self.cancelLabelEdit();
            return;
        }
        if (self.query.items.len > 0) {
            self.query.clearRetainingCapacity();
            self.folded.clearRetainingCapacity();
            self.selected = 0;
            try self.rebuildVisible(true);
            try self.setStatus("Search cleared");
            return;
        }
        self.cancelled = true;
        self.done = true;
    }

    fn handleLabelInput(self: *Selector, data: []const u8) !void {
        if (std.mem.eql(u8, data, "\x1b")) return self.cancelLabelEdit();
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                const byte = data[offset];
                if (byte >= 0x20) try self.label_input.append(self.gpa, byte);
                offset += 1;
                continue;
            };
            switch (decoded.key) {
                .enter => try self.commitLabelEdit(),
                .escape, .ctrl_c => try self.cancelLabelEdit(),
                .backspace => popUtf8(&self.label_input),
                .delete => self.label_input.clearRetainingCapacity(),
                .text => |byte| if (byte >= 0x20) try self.label_input.append(self.gpa, byte),
                else => {},
            }
            offset += decoded.consumed;
            if (!self.editing_label) break;
        }
    }

    fn handleMouse(self: *Selector, event: mouse.Event) !bool {
        if (self.editing_label) return false;
        if (event.kind == .scroll) {
            switch (event.button) {
                .wheel_up => self.moveSelection(-3),
                .wheel_down => self.moveSelection(3),
                .wheel_left => try self.foldCurrent(),
                .wheel_right => try self.unfoldCurrent(),
                else => return false,
            }
            return true;
        }
        if (event.kind != .press or (event.button != .left and event.button != .right)) return false;
        if (event.y < 3 or event.y >= 3 + self.rendered_count) return false;
        const visible_index = self.rendered_start + (event.y - 3);
        if (visible_index >= self.visible.items.len) return false;
        self.selected = visible_index;
        if (event.button == .right) {
            const node = self.currentNode() orelse return true;
            if (self.folded.contains(node.entry.id)) try self.unfoldCurrent() else try self.foldCurrent();
            return true;
        }
        const node = self.currentNode() orelse return true;
        const fold_column = 2 + node.depth * 2;
        if (node.has_children and event.x <= fold_column + 2) {
            if (self.folded.contains(node.entry.id)) try self.unfoldCurrent() else try self.foldCurrent();
        }
        return true;
    }

    fn handleDecodedKey(self: *Selector, key: terminal.Key) !void {
        switch (key) {
            .up => self.moveSelection(-1),
            .down => self.moveSelection(1),
            .home => self.selected = 0,
            .end => if (self.visible.items.len > 0) {
                self.selected = self.visible.items.len - 1;
            },
            // Bare cursor-left/right are the original tree page controls.
            // Branch folding uses Ctrl/Alt+Left/Right and is handled before
            // ordinary terminal key decoding.
            .left => self.selected -|= @min(self.selected, self.pageSize()),
            .right => if (self.visible.items.len > 0) {
                self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            },
            .enter => try self.selectCurrent(),
            .tab => try self.cycleFilter(),
            .backspace => if (self.query.items.len > 0) {
                popUtf8(&self.query);
                self.folded.clearRetainingCapacity();
                self.selected = 0;
                try self.rebuildVisible(true);
            },
            .delete => {
                self.query.clearRetainingCapacity();
                self.folded.clearRetainingCapacity();
                self.selected = 0;
                try self.rebuildVisible(true);
            },
            .escape => try self.clearSearchOrCancel(),
            .ctrl_c, .ctrl_d => {
                self.cancelled = true;
                self.done = true;
            },
            .text => |byte| if (byte >= 0x20) {
                try self.query.append(self.gpa, byte);
                self.folded.clearRetainingCapacity();
                self.selected = 0;
                try self.rebuildVisible(true);
            },
            else => {},
        }
    }

    fn handleInput(self: *Selector, data: []const u8) !void {
        if (self.editing_label) return self.handleLabelInput(data);
        if (keys.matchesKey(data, "ctrl+x")) return self.copyCurrent();
        if (keys.matchesKey(data, "shift+l")) return self.startLabelEdit();
        if (keys.matchesKey(data, "shift+t")) {
            self.show_label_timestamps = !self.show_label_timestamps;
            return self.setStatus(if (self.show_label_timestamps) "Label timestamps shown" else "Label timestamps hidden");
        }
        if (keys.matchesKey(data, "ctrl+d")) return self.setFilter(.default);
        if (keys.matchesKey(data, "ctrl+t")) return self.setFilter(if (self.filter_mode == .no_tools) .default else .no_tools);
        if (keys.matchesKey(data, "ctrl+u")) return self.setFilter(if (self.filter_mode == .user_only) .default else .user_only);
        if (keys.matchesKey(data, "ctrl+l")) return self.setFilter(if (self.filter_mode == .labeled_only) .default else .labeled_only);
        if (keys.matchesKey(data, "ctrl+a")) return self.setFilter(if (self.filter_mode == .all) .default else .all);
        if (keys.matchesKey(data, "shift+ctrl+o")) return self.cycleFilterBackward();
        if (keys.matchesKey(data, "ctrl+o")) return self.cycleFilter();
        if (keys.matchesKey(data, "ctrl+left") or keys.matchesKey(data, "alt+left")) return self.foldCurrent();
        if (keys.matchesKey(data, "ctrl+right") or keys.matchesKey(data, "alt+right")) return self.unfoldCurrent();
        if (std.mem.eql(u8, data, "\x1b[5~")) {
            self.selected -|= @min(self.selected, self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b[6~")) {
            if (self.visible.items.len > 0) self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b")) {
            return self.clearSearchOrCancel();
        }
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                const byte = data[offset];
                if (byte >= 0x20) {
                    try self.query.append(self.gpa, byte);
                    self.folded.clearRetainingCapacity();
                    try self.rebuildVisible(true);
                }
                offset += 1;
                continue;
            };
            try self.handleDecodedKey(decoded.key);
            offset += decoded.consumed;
        }
    }

    fn pageSize(self: *const Selector) usize {
        return @max(@as(usize, 1), self.viewport_rows -| 8);
    }

    fn previewAlloc(gpa: std.mem.Allocator, entry: *const session_mod.SessionEntry) ![]u8 {
        const source = if (entry.content.len > 0)
            entry.content
        else if (entry.tool_name) |tool_name|
            tool_name
        else if (entry.custom_type) |custom_type|
            custom_type
        else
            @tagName(entry.entry_type);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        var previous_space = false;
        for (source) |byte| {
            const normalized: u8 = if (byte == '\n' or byte == '\r' or byte == '\t' or byte < 0x20) ' ' else byte;
            if (normalized == ' ') {
                if (previous_space) continue;
                previous_space = true;
            } else {
                previous_space = false;
            }
            try out.append(gpa, normalized);
        }
        return try out.toOwnedSlice(gpa);
    }

    fn render(self: *Selector, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Session Tree{s}  {s}Enter{s} select  {s}Tab{s} filter  {s}Shift+L{s} label  {s}Ctrl+X{s} copy  {s}Esc{s} clear/cancel", .{
            bold, reset, dim, reset, dim, reset, dim, reset, dim, reset, dim, reset,
        }));
        if (self.editing_label) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Filter: {s}{s}{s}  Label: {s}{s}_{s}", .{
                accent, self.filter_mode.title(), reset, warning, self.label_input.items, reset,
            }));
        } else {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Filter: {s}{s}{s}  Search: {s}{s}_{s}", .{
                accent, self.filter_mode.title(), reset, accent, self.query.items, reset,
            }));
        }
        try lines.append(gpa, try gpa.dupe(u8, ""));
        self.rendered_start = 0;
        self.rendered_count = 0;

        if (self.visible.items.len == 0) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  No matching session entries{s}", .{ dim, reset }));
        } else {
            const visible_count = self.pageSize();
            const half = visible_count / 2;
            var start = self.selected -| half;
            if (start + visible_count > self.visible.items.len) start = self.visible.items.len -| visible_count;
            const end = @min(self.visible.items.len, start + visible_count);
            self.rendered_start = start;
            self.rendered_count = end - start;
            for (self.visible.items[start..end], start..) |node_index, visible_index| {
                const node = self.nodes.items[node_index];
                const entry = node.entry;
                const selected = visible_index == self.selected;
                const fold_mark = if (!node.has_children) " " else if (self.folded.contains(entry.id)) "▸" else "▾";
                const branch_mark = if (node.active_tip) "◆" else if (node.active_branch) "●" else "○";
                const branch_color = if (node.active_tip) success else if (node.active_branch) accent else dim;
                const label = self.sess.getLabel(entry.id);
                const preview = try previewAlloc(gpa, entry);
                defer gpa.free(preview);
                var line: std.Io.Writer.Allocating = .init(gpa);
                defer line.deinit();
                if (selected) try line.writer.writeAll(reverse);
                try line.writer.writeAll(if (selected) "> " else "  ");
                var depth: usize = 0;
                while (depth < node.depth) : (depth += 1) try line.writer.writeAll("  ");
                try line.writer.print("{s} {s}{s}{s} {s}[{s}]{s} {s}", .{
                    fold_mark,
                    branch_color,
                    branch_mark,
                    reset,
                    dim,
                    entry.role,
                    reset,
                    preview,
                });
                if (label) |value| {
                    try line.writer.print(" {s}#{s}{s}", .{ warning, value, reset });
                    if (self.show_label_timestamps) if (self.latestLabelEntry(entry.id)) |label_entry| {
                        if (label_entry.timestamp.len > 0) try line.writer.print(" {s}@{s}{s}", .{ dim, label_entry.timestamp, reset });
                    };
                }
                try line.writer.print(" {s}{s}{s}", .{ dim, entry.id, reset });
                if (selected) try line.writer.writeAll(reset);
                try appendClipped(gpa, &lines, width, try line.toOwnedSlice());
            }
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {d}/{d} entries · ◆ tip · ● active · mouse selects/folds · Shift+T timestamps{s}", .{
                dim,
                self.selected + 1,
                self.visible.items.len,
                reset,
            }));
        }
        if (self.status) |status| try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ warning, status, reset }));
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }
};

fn appendClipped(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), width: usize, owned: []u8) !void {
    defer gpa.free(owned);
    try lines.append(gpa, try terminal_text.truncateAlloc(gpa, owned, width, .{ .ellipsis = "…", .reset_style = true }));
}

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
    sess: *session_mod.Session,
    already_fullscreen: bool,
) !Selection {
    return runWithFilter(gpa, io, environ, reader, sess, .default, already_fullscreen);
}

pub fn runWithFilter(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    sess: *session_mod.Session,
    initial_filter: FilterMode,
    already_fullscreen: bool,
) !Selection {
    if (!terminal.supportsFullscreen(io)) return error.UnsupportedTerminal;
    var selector = try Selector.initWithFilter(gpa, io, sess, initial_filter);
    defer selector.deinit();
    selector.clipboard_options.environ = environ;
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
        const dimensions = terminal.terminalDimensions(environ, .{ .columns = 100, .rows = 30 });
        selector.viewport_rows = dimensions.rows;
        try app.paint(io, dimensions.columns, dimensions.rows);
        const count = readInputChunk(io, reader, input_buffer[0..]) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (count == 0) break;
        try app.handleInput(input_buffer[0..count]);
    }

    return .{
        .target_id = if (selector.result_id) |value| try gpa.dupe(u8, value) else null,
        .cancelled = selector.cancelled,
    };
}

fn buildTestSession(gpa: std.mem.Allocator) !session_mod.Session {
    var sess = try session_mod.Session.init(gpa, "tree-tui-test", "/tmp");
    const root = try sess.appendMessage(null, "user", "root question", null, null);
    const first = try sess.appendMessage(root, "assistant", "first answer", null, null);
    try sess.setTip(root);
    const branch = try sess.appendMessage(root, "user", "alternate question", null, null);
    const alternate = try sess.appendMessage(branch, "assistant", "alternate answer", null, null);
    _ = try sess.appendLabelChange(first, "bookmark");
    try sess.setTip(alternate);
    return sess;
}

test "tree selector builds branches and selects active tip" {
    const gpa = std.testing.allocator;
    var sess = try buildTestSession(gpa);
    defer sess.deinit();
    var selector = try Selector.init(gpa, std.testing.io, &sess);
    defer selector.deinit();
    try std.testing.expect(selector.nodes.items.len >= 4);
    const node = selector.currentNode().?;
    try std.testing.expect(node.active_tip);
    try std.testing.expectEqualStrings(sess.lastEntryId().?, node.entry.id);
}

test "tree selector search filters labels and content" {
    const gpa = std.testing.allocator;
    var sess = try buildTestSession(gpa);
    defer sess.deinit();
    var selector = try Selector.init(gpa, std.testing.io, &sess);
    defer selector.deinit();
    try selector.query.appendSlice(gpa, "bookmark");
    try selector.rebuildVisible(true);
    try std.testing.expectEqual(@as(usize, 1), selector.visible.items.len);
    try std.testing.expectEqualStrings("first answer", selector.currentNode().?.entry.content);
}

test "tree selector fold hides descendants and tab cycles filters" {
    const gpa = std.testing.allocator;
    var sess = try buildTestSession(gpa);
    defer sess.deinit();
    var selector = try Selector.init(gpa, std.testing.io, &sess);
    defer selector.deinit();
    selector.selected = 0;
    const before = selector.visible.items.len;
    try selector.foldCurrent();
    try std.testing.expect(selector.visible.items.len < before);
    const prior = selector.filter_mode;
    try selector.cycleFilter();
    try std.testing.expect(selector.filter_mode != prior);
}

test "tree selector escape clears search before cancelling and movement wraps" {
    const gpa = std.testing.allocator;
    var sess = try buildTestSession(gpa);
    defer sess.deinit();
    var selector = try Selector.init(gpa, std.testing.io, &sess);
    defer selector.deinit();

    try selector.query.appendSlice(gpa, "alternate");
    try selector.rebuildVisible(true);
    try selector.handleInput("\x1b");
    try std.testing.expectEqual(@as(usize, 0), selector.query.items.len);
    try std.testing.expect(!selector.done);

    selector.selected = 0;
    selector.moveSelection(-1);
    try std.testing.expectEqual(selector.visible.items.len - 1, selector.selected);
    selector.moveSelection(1);
    try std.testing.expectEqual(@as(usize, 0), selector.selected);
}

test "tree selector direct filters and editable labels match original controls" {
    const gpa = std.testing.allocator;
    var sess = try buildTestSession(gpa);
    defer sess.deinit();
    var selector = try Selector.init(gpa, std.testing.io, &sess);
    defer selector.deinit();

    try selector.handleInput("\x01"); // ctrl+a: all entries
    try std.testing.expectEqual(FilterMode.all, selector.filter_mode);
    try selector.handleInput("\x14"); // ctrl+t: no tools
    try std.testing.expectEqual(FilterMode.no_tools, selector.filter_mode);
    try selector.handleInput("\x14");
    try std.testing.expectEqual(FilterMode.default, selector.filter_mode);

    try selector.query.appendSlice(gpa, "answer first");
    try selector.rebuildVisible(true);
    try std.testing.expectEqual(@as(usize, 1), selector.visible.items.len);
    try selector.startLabelEdit();
    selector.label_input.clearRetainingCapacity();
    try selector.label_input.appendSlice(gpa, "renamed");
    try selector.commitLabelEdit();
    try std.testing.expectEqualStrings("renamed", sess.getLabel(selector.currentNode().?.entry.id).?);
    try std.testing.expect(selector.latestLabelEntry(selector.currentNode().?.entry.id).?.timestamp.len > 0);
}

test "tree selector mouse selects rows and scrolls wrapped selection" {
    const gpa = std.testing.allocator;
    var sess = try buildTestSession(gpa);
    defer sess.deinit();
    var selector = try Selector.init(gpa, std.testing.io, &sess);
    defer selector.deinit();
    selector.rendered_start = 0;
    selector.rendered_count = selector.visible.items.len;
    selector.selected = 0;

    try std.testing.expect(try selector.handleMouse(.{ .kind = .press, .button = .left, .x = 20, .y = 4 }));
    try std.testing.expectEqual(@as(usize, 1), selector.selected);
    try std.testing.expect(try selector.handleMouse(.{ .kind = .scroll, .button = .wheel_up, .x = 0, .y = 0 }));
    try std.testing.expectEqual(@mod(@as(usize, 1) + selector.visible.items.len - 3, selector.visible.items.len), selector.selected);
}

test "tree selector copy uses the native clipboard projection" {
    const Fake = struct {
        copied: std.ArrayList(u8) = .empty,
        fn run(
            raw: *anyopaque,
            _: std.mem.Allocator,
            _: Io,
            _: []const []const u8,
            input: []const u8,
            _: u64,
            _: ?*const std.process.Environ.Map,
        ) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.copied.appendSlice(std.testing.allocator, input);
            return true;
        }
    };
    const gpa = std.testing.allocator;
    var sess = try buildTestSession(gpa);
    defer sess.deinit();
    var selector = try Selector.init(gpa, std.testing.io, &sess);
    defer selector.deinit();
    var fake = Fake{};
    defer fake.copied.deinit(gpa);
    selector.clipboard_options = .{
        .platform = .macos,
        .write_runner = .{ .context = &fake, .run_fn = Fake.run },
    };
    const expected = try selector.copyTextAlloc(selector.currentNode().?.entry);
    defer gpa.free(expected);
    try selector.copyCurrent();
    try std.testing.expectEqualStrings(expected, fake.copied.items);
    try std.testing.expectEqualStrings("Selected entry copied to clipboard", selector.status.?);
}

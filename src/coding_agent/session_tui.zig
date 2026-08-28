//! Retained fullscreen session picker used by startup `--resume` and live
//! `/resume`. It keeps corrupt sessions visible, supports project/all scopes,
//! fuzzy and quoted search, recent/thread/relevance ordering, names-only
//! filtering, rename/delete administration, and deterministic terminal restore.
const std = @import("std");
const Io = std.Io;
const session_mod = @import("../agent/session.zig");
const application = @import("../tui/application.zig");
const fuzzy = @import("../tui/fuzzy.zig");
const layout = @import("../tui/layout.zig");
const line_editor = @import("../tui/line_editor.zig");
const mouse = @import("../tui/mouse.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const tui_render = @import("../tui/render.zig");

const accent = "\x1b[36m";
const success = "\x1b[32m";
const warning = "\x1b[33m";
const danger = "\x1b[31m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reverse = "\x1b[7m";
const reset = "\x1b[0m";

pub const Scope = enum {
    current,
    all,

    fn title(self: Scope) []const u8 {
        return switch (self) {
            .current => "project",
            .all => "all",
        };
    }
};

pub const SortMode = enum {
    threaded,
    recent,
    relevance,

    fn title(self: SortMode) []const u8 {
        return switch (self) {
            .threaded => "threaded",
            .recent => "recent",
            .relevance => "relevance",
        };
    }

    fn next(self: SortMode) SortMode {
        return switch (self) {
            .threaded => .recent,
            .recent => .relevance,
            .relevance => .threaded,
        };
    }
};

pub const Options = struct {
    session_dir: []const u8,
    all_sessions_root: ?[]const u8 = null,
    current_session_path: ?[]const u8 = null,
    required_cwd: ?[]const u8 = null,
    initial_query: ?[]const u8 = null,
    allow_rename: bool = true,
    allow_delete: bool = true,
    already_fullscreen: bool = false,
};

pub const Selection = struct {
    path: ?[]u8 = null,
    cancelled: bool = true,
    renamed: usize = 0,
    deleted: usize = 0,

    pub fn deinit(self: *Selection, gpa: std.mem.Allocator) void {
        if (self.path) |value| gpa.free(value);
        self.* = undefined;
    }
};

const Ranked = struct {
    item_index: usize,
    score: i32,
    root_mtime: i96,
    depth: usize,
};

const EditMode = enum { search, rename, confirm_delete };

const Selector = struct {
    gpa: std.mem.Allocator,
    io: Io,
    current_sessions: []session_mod.SessionInfo,
    all_sessions: []session_mod.SessionInfo,
    current_session_path: ?[]const u8,
    required_cwd: ?[]const u8,
    allow_rename: bool,
    allow_delete: bool,
    visible: std.ArrayList(Ranked) = .empty,
    query: std.ArrayList(u8) = .empty,
    edit: std.ArrayList(u8) = .empty,
    selected: usize = 0,
    viewport_rows: usize = 30,
    scope: Scope = .current,
    sort_mode: SortMode = .threaded,
    names_only: bool = false,
    show_paths: bool = false,
    edit_mode: EditMode = .search,
    done: bool = false,
    cancelled: bool = true,
    result: ?[]u8 = null,
    status: ?[]u8 = null,
    rendered_start: usize = 0,
    rendered_count: usize = 0,
    last_click_ms: i64 = 0,
    last_click_index: ?usize = null,
    renamed: usize = 0,
    deleted: usize = 0,

    fn init(gpa: std.mem.Allocator, io: Io, options: Options) !Selector {
        const current_sessions = try session_mod.listSessions(gpa, io, options.session_dir);
        errdefer deinitInfos(gpa, current_sessions);
        const all_sessions = if (options.all_sessions_root) |root|
            try session_mod.listSessionsRecursive(gpa, io, root)
        else
            try cloneInfos(gpa, current_sessions);
        errdefer deinitInfos(gpa, all_sessions);

        var self: Selector = .{
            .gpa = gpa,
            .io = io,
            .current_sessions = current_sessions,
            .all_sessions = all_sessions,
            .current_session_path = options.current_session_path,
            .required_cwd = options.required_cwd,
            .allow_rename = options.allow_rename,
            .allow_delete = options.allow_delete,
        };
        errdefer self.deinit();
        if (options.initial_query) |query| try self.query.appendSlice(gpa, query);
        try self.rebuildVisible(true);
        return self;
    }

    fn deinitInfos(gpa: std.mem.Allocator, infos: []session_mod.SessionInfo) void {
        for (infos) |*info| info.deinit(gpa);
        gpa.free(infos);
    }

    fn cloneInfo(gpa: std.mem.Allocator, info: session_mod.SessionInfo) !session_mod.SessionInfo {
        return .{
            .path = try gpa.dupe(u8, info.path),
            .id = try gpa.dupe(u8, info.id),
            .cwd = try gpa.dupe(u8, info.cwd),
            .name = try gpa.dupe(u8, info.name),
            .parent_session_path = if (info.parent_session_path) |value| try gpa.dupe(u8, value) else null,
            .created_at = try gpa.dupe(u8, info.created_at),
            .message_count = info.message_count,
            .first_message = try gpa.dupe(u8, info.first_message),
            .all_messages_text = try gpa.dupe(u8, info.all_messages_text),
            .valid = info.valid,
            .mtime_hint = if (info.mtime_hint.len > 0) try gpa.dupe(u8, info.mtime_hint) else "",
            .mtime_ns = info.mtime_ns,
        };
    }

    fn cloneInfos(gpa: std.mem.Allocator, infos: []const session_mod.SessionInfo) ![]session_mod.SessionInfo {
        const out = try gpa.alloc(session_mod.SessionInfo, infos.len);
        var initialized: usize = 0;
        errdefer {
            for (out[0..initialized]) |*info| info.deinit(gpa);
            gpa.free(out);
        }
        for (infos, 0..) |info, index| {
            out[index] = try cloneInfo(gpa, info);
            initialized += 1;
        }
        return out;
    }

    fn deinit(self: *Selector) void {
        if (self.result) |value| self.gpa.free(value);
        if (self.status) |value| self.gpa.free(value);
        self.query.deinit(self.gpa);
        self.edit.deinit(self.gpa);
        self.visible.deinit(self.gpa);
        deinitInfos(self.gpa, self.current_sessions);
        deinitInfos(self.gpa, self.all_sessions);
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

    fn activeSessions(self: *Selector) []session_mod.SessionInfo {
        return switch (self.scope) {
            .current => self.current_sessions,
            .all => self.all_sessions,
        };
    }

    fn activeSessionsConst(self: *const Selector) []const session_mod.SessionInfo {
        return switch (self.scope) {
            .current => self.current_sessions,
            .all => self.all_sessions,
        };
    }

    fn samePath(lhs: []const u8, rhs: []const u8) bool {
        return if (@import("builtin").os.tag == .windows)
            std.ascii.eqlIgnoreCase(lhs, rhs)
        else
            std.mem.eql(u8, lhs, rhs);
    }

    fn activeIndexForPath(self: *const Selector, path: []const u8) ?usize {
        for (self.activeSessionsConst(), 0..) |info, index| if (samePath(info.path, path)) return index;
        return null;
    }

    fn threadRoot(self: *const Selector, index: usize) struct { mtime: i96, depth: usize } {
        const infos = self.activeSessionsConst();
        var current = index;
        var depth: usize = 0;
        while (depth < infos.len) : (depth += 1) {
            const parent = infos[current].parent_session_path orelse break;
            var found: ?usize = null;
            for (infos, 0..) |candidate, candidate_index| {
                if (samePath(candidate.path, parent)) {
                    found = candidate_index;
                    break;
                }
            }
            current = found orelse break;
        }
        return .{ .mtime = infos[current].mtime_ns, .depth = depth };
    }

    fn queryScore(self: *const Selector, info: session_mod.SessionInfo) ?i32 {
        const query = std.mem.trim(u8, self.query.items, " \t\r\n");
        if (query.len == 0) return 0;
        const fields = [_][]const u8{ info.id, info.name, info.cwd, info.first_message, info.all_messages_text, info.path };
        var total: i32 = 0;
        var index: usize = 0;
        while (index < query.len) {
            while (index < query.len and std.ascii.isWhitespace(query[index])) : (index += 1) {}
            if (index >= query.len) break;
            const quoted = query[index] == '"';
            if (quoted) index += 1;
            const start = index;
            if (quoted) {
                while (index < query.len and query[index] != '"') : (index += 1) {}
            } else {
                while (index < query.len and !std.ascii.isWhitespace(query[index])) : (index += 1) {}
            }
            const token = query[start..index];
            if (quoted and index < query.len and query[index] == '"') index += 1;
            if (token.len == 0) continue;
            if (quoted) {
                var matched = false;
                for (fields) |field| {
                    if (std.ascii.indexOfIgnoreCase(field, token)) |position| {
                        total +|= @intCast(@max(@as(isize, 1), 2000 - @as(isize, @intCast(@min(position, 1999)))));
                        matched = true;
                        break;
                    }
                }
                if (!matched) return null;
            } else {
                total +|= fuzzy.bestScore(&fields, token) orelse return null;
            }
        }
        return total;
    }

    fn rankedLessThan(self: *const Selector, lhs: Ranked, rhs: Ranked) bool {
        const infos = self.activeSessionsConst();
        const l = infos[lhs.item_index];
        const r = infos[rhs.item_index];
        switch (self.sort_mode) {
            .relevance => {
                if (lhs.score != rhs.score) return lhs.score > rhs.score;
                if (l.mtime_ns != r.mtime_ns) return l.mtime_ns > r.mtime_ns;
            },
            .recent => {
                if (l.mtime_ns != r.mtime_ns) return l.mtime_ns > r.mtime_ns;
            },
            .threaded => {
                if (lhs.root_mtime != rhs.root_mtime) return lhs.root_mtime > rhs.root_mtime;
                if (lhs.depth != rhs.depth) return lhs.depth < rhs.depth;
                if (l.mtime_ns != r.mtime_ns) return l.mtime_ns < r.mtime_ns;
            },
        }
        return std.mem.lessThan(u8, l.path, r.path);
    }

    fn rebuildVisible(self: *Selector, prefer_current: bool) !void {
        var preferred_path: ?[]u8 = null;
        defer if (preferred_path) |value| self.gpa.free(value);
        if (!prefer_current) {
            if (self.currentInfo()) |info| preferred_path = try self.gpa.dupe(u8, info.path);
        }

        self.visible.clearRetainingCapacity();
        const infos = self.activeSessionsConst();
        for (infos, 0..) |info, index| {
            if (self.names_only and std.mem.trim(u8, info.name, " \t\r\n").len == 0) continue;
            const score = self.queryScore(info) orelse continue;
            const root = self.threadRoot(index);
            try self.visible.append(self.gpa, .{ .item_index = index, .score = score, .root_mtime = root.mtime, .depth = root.depth });
        }
        std.mem.sort(Ranked, self.visible.items, self, struct {
            fn lessThan(ctx: *Selector, lhs: Ranked, rhs: Ranked) bool {
                return ctx.rankedLessThan(lhs, rhs);
            }
        }.lessThan);

        if (self.visible.items.len == 0) {
            self.selected = 0;
            return;
        }
        if (prefer_current) {
            if (self.current_session_path) |path| {
                for (self.visible.items, 0..) |ranked, visible_index| {
                    if (samePath(infos[ranked.item_index].path, path)) {
                        self.selected = visible_index;
                        return;
                    }
                }
            }
        } else if (preferred_path) |path| {
            for (self.visible.items, 0..) |ranked, visible_index| {
                if (samePath(infos[ranked.item_index].path, path)) {
                    self.selected = visible_index;
                    return;
                }
            }
        }
        self.selected = @min(self.selected, self.visible.items.len - 1);
    }

    fn currentInfo(self: *const Selector) ?session_mod.SessionInfo {
        if (self.selected >= self.visible.items.len) return null;
        return self.activeSessionsConst()[self.visible.items[self.selected].item_index];
    }

    fn setStatus(self: *Selector, value: []const u8) !void {
        if (self.status) |old| self.gpa.free(old);
        self.status = try self.gpa.dupe(u8, value);
    }

    fn clearStatus(self: *Selector) void {
        if (self.status) |old| self.gpa.free(old);
        self.status = null;
    }

    fn pageSize(self: *const Selector) usize {
        return @max(@as(usize, 1), self.viewport_rows -| 12);
    }

    fn moveSelection(self: *Selector, delta: isize) void {
        const count = self.visible.items.len;
        if (count == 0) return;
        if (delta < 0) self.selected = if (self.selected == 0) count - 1 else self.selected - 1 else if (delta > 0) self.selected = if (self.selected + 1 >= count) 0 else self.selected + 1;
    }

    fn selectCurrent(self: *Selector) !void {
        const info = self.currentInfo() orelse return;
        if (!info.valid) return self.setStatus("The selected JSONL session is malformed and cannot be resumed.");
        if (self.required_cwd) |cwd| {
            if (info.cwd.len > 0 and !samePath(info.cwd, cwd)) return self.setStatus("This live process can resume only a session from its current working directory.");
        }
        if (self.result) |old| self.gpa.free(old);
        self.result = try self.gpa.dupe(u8, info.path);
        self.cancelled = false;
        self.done = true;
    }

    fn cycleScope(self: *Selector) !void {
        if (self.all_sessions.len == 0) return;
        self.scope = if (self.scope == .current) .all else .current;
        try self.rebuildVisible(true);
    }

    fn cycleSort(self: *Selector) !void {
        self.sort_mode = self.sort_mode.next();
        try self.rebuildVisible(false);
    }

    fn beginRename(self: *Selector) !void {
        if (!self.allow_rename) return;
        const info = self.currentInfo() orelse return;
        if (!info.valid) return self.setStatus("Malformed sessions cannot be renamed.");
        self.edit.clearRetainingCapacity();
        try self.edit.appendSlice(self.gpa, info.name);
        self.edit_mode = .rename;
        self.clearStatus();
    }

    fn replaceNameInInfos(self: *Selector, path: []const u8, value: []const u8) !void {
        for ([_][]session_mod.SessionInfo{ self.current_sessions, self.all_sessions }) |infos| {
            for (infos) |*info| {
                if (!samePath(info.path, path)) continue;
                self.gpa.free(info.name);
                info.name = try self.gpa.dupe(u8, value);
            }
        }
    }

    fn commitRename(self: *Selector) !void {
        const info = self.currentInfo() orelse {
            self.edit_mode = .search;
            return;
        };
        var loaded = session_mod.Session.load(self.gpa, self.io, info.path) catch {
            self.edit_mode = .search;
            return self.setStatus("Could not load the selected session for rename.");
        };
        defer loaded.deinit();
        const value = std.mem.trim(u8, self.edit.items, " \t\r\n");
        _ = try loaded.appendSessionInfo(value);
        try loaded.save(self.io, info.path);
        try self.replaceNameInInfos(info.path, loaded.name);
        self.renamed += 1;
        self.edit_mode = .search;
        self.edit.clearRetainingCapacity();
        try self.setStatus("Session name saved.");
        try self.rebuildVisible(false);
    }

    fn beginDelete(self: *Selector) !void {
        if (!self.allow_delete) return;
        const info = self.currentInfo() orelse return;
        if (self.current_session_path) |current| if (samePath(info.path, current)) return self.setStatus("The active session cannot be deleted.");
        self.edit_mode = .confirm_delete;
        try self.setStatus("Delete this session permanently? Press y to confirm; any other key cancels.");
    }

    fn removePathFromInfos(self: *Selector, path: []const u8) !void {
        // Re-listing is safer than moving owned SessionInfo values inside two
        // independently owned inventories after a deletion.
        const session_dir = if (self.current_sessions.len > 0)
            std.fs.path.dirname(self.current_sessions[0].path) orelse "."
        else
            null;
        if (session_dir) |dir_path| {
            const replacement = try session_mod.listSessions(self.gpa, self.io, dir_path);
            deinitInfos(self.gpa, self.current_sessions);
            self.current_sessions = replacement;
        }
        // Remove directly from all inventory by rebuilding an owned slice.
        var kept: std.ArrayList(session_mod.SessionInfo) = .empty;
        errdefer {
            for (kept.items) |*item| item.deinit(self.gpa);
            kept.deinit(self.gpa);
        }
        for (self.all_sessions) |*info| {
            if (samePath(info.path, path)) {
                info.deinit(self.gpa);
            } else {
                try kept.append(self.gpa, info.*);
                info.* = undefined;
            }
        }
        self.gpa.free(self.all_sessions);
        self.all_sessions = try kept.toOwnedSlice(self.gpa);
    }

    fn confirmDelete(self: *Selector, yes: bool) !void {
        defer {
            self.edit_mode = .search;
        }
        if (!yes) {
            try self.setStatus("Deletion cancelled.");
            return;
        }
        const info = self.currentInfo() orelse return;
        const path = try self.gpa.dupe(u8, info.path);
        defer self.gpa.free(path);
        std.Io.Dir.cwd().deleteFile(self.io, path) catch return self.setStatus("Could not delete the selected session.");
        try self.removePathFromInfos(path);
        self.deleted += 1;
        try self.setStatus("Session deleted.");
        try self.rebuildVisible(false);
    }

    fn clearSearchOrCancel(self: *Selector) !void {
        if (self.edit_mode == .rename) {
            self.edit_mode = .search;
            self.edit.clearRetainingCapacity();
            return;
        }
        if (self.edit_mode == .confirm_delete) return self.confirmDelete(false);
        if (self.query.items.len > 0) {
            self.query.clearRetainingCapacity();
            try self.rebuildVisible(true);
            return;
        }
        self.cancelled = true;
        self.done = true;
    }

    fn popUtf8(list: *std.ArrayList(u8)) void {
        if (list.items.len == 0) return;
        var index = list.items.len - 1;
        while (index > 0 and (list.items[index] & 0xc0) == 0x80) : (index -= 1) {}
        list.shrinkRetainingCapacity(index);
    }

    fn handleDecodedKey(self: *Selector, key: terminal.Key) !void {
        if (self.edit_mode == .rename) {
            switch (key) {
                .enter => try self.commitRename(),
                .escape, .ctrl_c => try self.clearSearchOrCancel(),
                .backspace => popUtf8(&self.edit),
                .text => |byte| if (byte >= 0x20) try self.edit.append(self.gpa, byte),
                else => {},
            }
            return;
        }
        if (self.edit_mode == .confirm_delete) {
            switch (key) {
                .text => |byte| try self.confirmDelete(byte == 'y' or byte == 'Y'),
                .escape, .ctrl_c => try self.confirmDelete(false),
                else => try self.confirmDelete(false),
            }
            return;
        }
        switch (key) {
            .up => self.moveSelection(-1),
            .down => self.moveSelection(1),
            .home => self.selected = 0,
            .end => {
                if (self.visible.items.len > 0) self.selected = self.visible.items.len - 1;
            },
            .left => self.selected -|= @min(self.selected, self.pageSize()),
            .right => {
                if (self.visible.items.len > 0) self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            },
            .enter => try self.selectCurrent(),
            .tab => try self.cycleScope(),
            .backspace => {
                if (self.query.items.len > 0) {
                    popUtf8(&self.query);
                    try self.rebuildVisible(false);
                }
            },
            .delete => {
                if (self.query.items.len > 0) {
                    self.query.clearRetainingCapacity();
                    try self.rebuildVisible(true);
                }
            },
            .escape => try self.clearSearchOrCancel(),
            .ctrl_c => {
                self.cancelled = true;
                self.done = true;
            },
            .ctrl_d => try self.beginDelete(),
            .text => |byte| if (byte >= 0x20) {
                try self.query.append(self.gpa, byte);
                try self.rebuildVisible(false);
            },
            else => {},
        }
    }

    fn handleInput(self: *Selector, data: []const u8) !void {
        if (self.edit_mode == .search and data.len == 1) {
            switch (data[0]) {
                0x12 => return self.beginRename(), // Ctrl-R
                0x14 => return self.cycleSort(), // Ctrl-T
                0x0e => { // Ctrl-N
                    self.names_only = !self.names_only;
                    return self.rebuildVisible(false);
                },
                0x10 => { // Ctrl-P
                    self.show_paths = !self.show_paths;
                    return;
                },
                else => {},
            }
        }
        if (std.mem.eql(u8, data, "\x1b[5~")) {
            self.selected -|= @min(self.selected, self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b[6~")) {
            if (self.visible.items.len > 0) self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b")) return self.clearSearchOrCancel();
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                const byte = data[offset];
                if (byte >= 0x20) {
                    if (self.edit_mode == .rename) try self.edit.append(self.gpa, byte) else try self.query.append(self.gpa, byte);
                    if (self.edit_mode == .search) try self.rebuildVisible(false);
                }
                offset += 1;
                continue;
            };
            try self.handleDecodedKey(decoded.key);
            offset += decoded.consumed;
        }
    }

    fn handleMouse(self: *Selector, event: mouse.Event) !bool {
        if (event.kind == .scroll) {
            switch (event.button) {
                .wheel_up => self.moveSelection(-3),
                .wheel_down => self.moveSelection(3),
                else => return false,
            }
            return true;
        }
        if (event.kind != .press or event.button != .left) return false;
        if (event.y < 3 or event.y >= 3 + self.rendered_count) return false;
        const visible_index = self.rendered_start + (event.y - 3);
        if (visible_index >= self.visible.items.len) return false;
        self.selected = visible_index;
        const now_ms = std.Io.Clock.awake.now(self.io).toMilliseconds();
        if (self.last_click_index != null and self.last_click_index.? == visible_index and now_ms >= self.last_click_ms and now_ms - self.last_click_ms <= 500) {
            self.last_click_index = null;
            self.last_click_ms = 0;
            try self.selectCurrent();
        } else {
            self.last_click_index = visible_index;
            self.last_click_ms = now_ms;
        }
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
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Resume Session{s}  {s}Enter{s} select  {s}Tab{s} scope  {s}Esc{s} clear/cancel", .{ bold, reset, dim, reset, dim, reset, dim, reset }));
        const input = if (self.edit_mode == .rename) self.edit.items else self.query.items;
        const mode_label = if (self.edit_mode == .rename) "Rename" else "Search";
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Scope {s}{s}{s} · sort {s}{s}{s} · {s}{s}{s}: {s}{s}_{s}", .{
            accent,                                self.scope.title(),                            reset,
            accent,                                self.sort_mode.title(),                        reset,
            if (self.names_only) warning else dim, if (self.names_only) "named" else "all names", reset,
            mode_label,                            input,                                         reset,
        }));
        try lines.append(gpa, try gpa.dupe(u8, ""));

        self.rendered_start = 0;
        self.rendered_count = 0;
        if (self.visible.items.len == 0) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  No matching sessions{s}", .{ dim, reset }));
        } else {
            const infos = self.activeSessionsConst();
            const count = self.pageSize();
            const half = count / 2;
            var start = self.selected -| half;
            if (start + count > self.visible.items.len) start = self.visible.items.len -| count;
            const end = @min(self.visible.items.len, start + count);
            self.rendered_start = start;
            self.rendered_count = end - start;
            for (self.visible.items[start..end], start..) |ranked, visible_index| {
                const info = infos[ranked.item_index];
                const selected = visible_index == self.selected;
                const current = if (self.current_session_path) |path| samePath(path, info.path) else false;
                var line: std.Io.Writer.Allocating = .init(gpa);
                defer line.deinit();
                if (selected) try line.writer.writeAll(reverse);
                try line.writer.writeAll(if (selected) "> " else "  ");
                if (self.sort_mode == .threaded and ranked.depth > 0) {
                    var depth: usize = 0;
                    while (depth < @min(ranked.depth, 5)) : (depth += 1) try line.writer.writeAll("  ");
                    try line.writer.writeAll("↳ ");
                }
                const title = if (info.name.len > 0) info.name else info.first_message;
                try line.writer.print("{s}{s}{s} {s}[{s}]{s}", .{ if (selected) accent else "", title, if (selected) reset else "", dim, info.id, reset });
                if (current) try line.writer.print(" {s}●{s}", .{ success, reset });
                if (!info.valid) try line.writer.print(" {s}invalid{s}", .{ danger, reset });
                if (selected) try line.writer.writeAll(reset);
                try appendClipped(gpa, &lines, width, try line.toOwnedSlice());
            }

            const info = self.currentInfo().?;
            try lines.append(gpa, try gpa.dupe(u8, ""));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {d} messages · created {s} · {s}{s}", .{ dim, info.message_count, info.created_at, info.cwd, reset }));
            if (self.show_paths) try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {s}{s}", .{ dim, info.path, reset }));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {d}/{d} · Ctrl-T sort · Ctrl-N names · Ctrl-P paths · Ctrl-R rename · Ctrl-D delete{s}", .{ dim, self.selected + 1, self.visible.items.len, reset }));
        }
        if (self.status) |status| try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ warning, status, reset }));
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
    options: Options,
) !Selection {
    if (!terminal.supportsFullscreen(io)) return error.UnsupportedTerminal;
    var selector = try Selector.init(gpa, io, options);
    defer selector.deinit();
    var app = application.Application.init(gpa, selector.component());
    defer app.deinit();
    app.setFocus(selector.component());

    var raw = try line_editor.RawMode.enter();
    defer raw.leave();
    if (options.already_fullscreen) {
        try tui_render.writeAll(io, terminal.clear_screen ++ terminal.hide_cursor ++ terminal.bracketed_paste_enable ++ application.mouse_enable);
        defer tui_render.writeAll(io, application.mouse_disable ++ terminal.bracketed_paste_disable ++ terminal.show_cursor ++ terminal.clear_screen) catch {};
    } else {
        try app.start(io);
        defer app.stop(io) catch {};
    }

    var input_buffer: [4096]u8 = undefined;
    while (!selector.done) {
        const dimensions = terminal.terminalDimensions(environ, .{ .columns = 110, .rows = 34 });
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
        .path = if (selector.result) |value| try gpa.dupe(u8, value) else null,
        .cancelled = selector.cancelled,
        .renamed = selector.renamed,
        .deleted = selector.deleted,
    };
}

fn fakeInfo(gpa: std.mem.Allocator, id: []const u8, name: []const u8, cwd: []const u8, text: []const u8, mtime: i96) !session_mod.SessionInfo {
    return .{
        .path = try std.fmt.allocPrint(gpa, "/tmp/{s}.jsonl", .{id}),
        .id = try gpa.dupe(u8, id),
        .cwd = try gpa.dupe(u8, cwd),
        .name = try gpa.dupe(u8, name),
        .created_at = try gpa.dupe(u8, "2026-08-19T20:00:00.000Z"),
        .message_count = 2,
        .first_message = try gpa.dupe(u8, text),
        .all_messages_text = try gpa.dupe(u8, text),
        .valid = true,
        .mtime_ns = mtime,
    };
}

test "session search supports fuzzy tokens and quoted phrases" {
    const gpa = std.testing.allocator;
    var info = try fakeInfo(gpa, "s1", "Alpha work", "/repo", "repair node cve safely", 2);
    defer info.deinit(gpa);
    var selector: Selector = undefined;
    selector.gpa = gpa;
    selector.query = .empty;
    defer selector.query.deinit(gpa);
    try selector.query.appendSlice(gpa, "alpha \"node cve\"");
    try std.testing.expect(selector.queryScore(info) != null);
    selector.query.clearRetainingCapacity();
    try selector.query.appendSlice(gpa, "alpha \"missing phrase\"");
    try std.testing.expect(selector.queryScore(info) == null);
}

test "session selector sort mode cycles through all original modes" {
    try std.testing.expectEqual(SortMode.recent, SortMode.threaded.next());
    try std.testing.expectEqual(SortMode.relevance, SortMode.recent.next());
    try std.testing.expectEqual(SortMode.threaded, SortMode.relevance.next());
}

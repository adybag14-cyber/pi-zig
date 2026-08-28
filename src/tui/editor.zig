//! Stateful native text editor core for the interactive TUI.
//!
//! This ports the non-rendering behavior of Pi's editor: UTF-8-safe scalar
//! movement, line/word navigation, destructive kills, yank/yank-pop, undo and
//! command history. Visual grapheme segmentation/wrapping remains in the TUI
//! parity backlog and is deliberately not claimed here.
const std = @import("std");
const nav = @import("word_navigation.zig");
const KillRing = @import("kill_ring.zig").KillRing;

pub const Action = enum {
    cursor_left,
    cursor_right,
    cursor_word_left,
    cursor_word_right,
    cursor_line_start,
    cursor_line_end,
    cursor_up,
    cursor_down,
    delete_char_backward,
    delete_char_forward,
    delete_word_backward,
    delete_word_forward,
    delete_to_line_start,
    delete_to_line_end,
    yank,
    yank_pop,
    undo,
    history_previous,
    history_next,
};

const Snapshot = struct {
    text: []u8,
    cursor: usize,
};

pub const Editor = struct {
    gpa: std.mem.Allocator,
    text: std.ArrayList(u8) = .empty,
    cursor: usize = 0,
    undo_stack: std.ArrayList(Snapshot) = .empty,
    kill_ring: KillRing,
    history: std.ArrayList([]u8) = .empty,
    history_index: ?usize = null,
    history_draft: ?[]u8 = null,
    last_was_kill: bool = false,
    last_yank_start: ?usize = null,
    last_yank_len: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Editor {
        return .{ .gpa = gpa, .kill_ring = KillRing.init(gpa) };
    }

    pub fn deinit(self: *Editor) void {
        self.text.deinit(self.gpa);
        for (self.undo_stack.items) |snap| self.gpa.free(snap.text);
        self.undo_stack.deinit(self.gpa);
        self.kill_ring.deinit();
        for (self.history.items) |item| self.gpa.free(item);
        self.history.deinit(self.gpa);
        if (self.history_draft) |draft| self.gpa.free(draft);
        self.* = undefined;
    }

    pub fn slice(self: *const Editor) []const u8 {
        return self.text.items;
    }

    pub fn setText(self: *Editor, value: []const u8) !void {
        return self.setTextAt(value, value.len);
    }

    pub fn setTextAt(self: *Editor, value: []const u8, cursor: usize) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(self.gpa, value);
        self.cursor = @min(cursor, value.len);
        self.resetTransient();
    }

    pub fn insert(self: *Editor, value: []const u8) !void {
        if (value.len == 0) return;
        try self.pushUndo();
        try self.insertNoUndo(value);
        self.last_was_kill = false;
        self.clearYankSpan();
        self.leaveHistory();
    }

    pub fn apply(self: *Editor, action: Action) !void {
        switch (action) {
            .cursor_left => self.cursor = nav.previousScalar(self.text.items, self.cursor),
            .cursor_right => self.cursor = nav.nextScalar(self.text.items, self.cursor),
            .cursor_word_left => self.cursor = nav.findWordBackward(self.text.items, self.cursor),
            .cursor_word_right => self.cursor = nav.findWordForward(self.text.items, self.cursor),
            .cursor_line_start => self.cursor = self.lineStart(self.cursor),
            .cursor_line_end => self.cursor = self.lineEnd(self.cursor),
            .cursor_up => self.moveVertical(false),
            .cursor_down => self.moveVertical(true),
            .delete_char_backward => try self.deleteBackward(),
            .delete_char_forward => try self.deleteForward(),
            .delete_word_backward => try self.killRange(nav.findWordBackward(self.text.items, self.cursor), self.cursor, true),
            .delete_word_forward => try self.killRange(self.cursor, nav.findWordForward(self.text.items, self.cursor), false),
            .delete_to_line_start => try self.killRange(self.lineStart(self.cursor), self.cursor, true),
            .delete_to_line_end => try self.killRange(self.cursor, self.lineEndIncludingNewline(self.cursor), false),
            .yank => try self.yank(),
            .yank_pop => try self.yankPop(),
            .undo => self.undo(),
            .history_previous => try self.historyPrevious(),
            .history_next => try self.historyNext(),
        }
        if (action != .delete_word_backward and action != .delete_word_forward and action != .delete_to_line_start and action != .delete_to_line_end) {
            self.last_was_kill = false;
        }
        if (action != .yank and action != .yank_pop) self.clearYankSpan();
    }

    pub fn addHistory(self: *Editor, value: []const u8) !void {
        if (value.len == 0) return;
        if (self.history.items.len > 0 and std.mem.eql(u8, self.history.items[self.history.items.len - 1], value)) return;
        try self.history.append(self.gpa, try self.gpa.dupe(u8, value));
        self.leaveHistory();
    }

    fn pushUndo(self: *Editor) !void {
        try self.undo_stack.append(self.gpa, .{ .text = try self.gpa.dupe(u8, self.text.items), .cursor = self.cursor });
    }

    fn undo(self: *Editor) void {
        const snap = self.undo_stack.pop() orelse return;
        self.text.clearRetainingCapacity();
        self.text.appendSlice(self.gpa, snap.text) catch {
            self.gpa.free(snap.text);
            return;
        };
        self.cursor = @min(snap.cursor, self.text.items.len);
        self.gpa.free(snap.text);
        self.resetTransient();
    }

    fn insertNoUndo(self: *Editor, value: []const u8) !void {
        const old_len = self.text.items.len;
        try self.text.resize(self.gpa, old_len + value.len);
        std.mem.copyBackwards(u8, self.text.items[self.cursor + value.len .. old_len + value.len], self.text.items[self.cursor..old_len]);
        @memcpy(self.text.items[self.cursor .. self.cursor + value.len], value);
        self.cursor += value.len;
    }

    fn removeRangeNoUndo(self: *Editor, start: usize, end: usize) void {
        if (end <= start or start >= self.text.items.len) return;
        const bounded_end = @min(end, self.text.items.len);
        const tail_len = self.text.items.len - bounded_end;
        std.mem.copyForwards(u8, self.text.items[start .. start + tail_len], self.text.items[bounded_end..]);
        self.text.items.len -= bounded_end - start;
        self.cursor = @min(start, self.text.items.len);
    }

    fn deleteBackward(self: *Editor) !void {
        if (self.cursor == 0) return;
        const start = nav.previousScalar(self.text.items, self.cursor);
        try self.pushUndo();
        self.removeRangeNoUndo(start, self.cursor);
        self.last_was_kill = false;
        self.leaveHistory();
    }

    fn deleteForward(self: *Editor) !void {
        if (self.cursor >= self.text.items.len) return;
        const end = nav.nextScalar(self.text.items, self.cursor);
        try self.pushUndo();
        self.removeRangeNoUndo(self.cursor, end);
        self.last_was_kill = false;
        self.leaveHistory();
    }

    fn killRange(self: *Editor, start: usize, end: usize, prepend: bool) !void {
        if (end <= start) return;
        try self.pushUndo();
        try self.kill_ring.push(self.text.items[start..end], prepend, self.last_was_kill);
        self.removeRangeNoUndo(start, end);
        self.last_was_kill = true;
        self.clearYankSpan();
        self.leaveHistory();
    }

    fn yank(self: *Editor) !void {
        const value = self.kill_ring.peek() orelse return;
        try self.pushUndo();
        const start = self.cursor;
        try self.insertNoUndo(value);
        self.last_yank_start = start;
        self.last_yank_len = value.len;
        self.last_was_kill = false;
        self.leaveHistory();
    }

    fn yankPop(self: *Editor) !void {
        const start = self.last_yank_start orelse return;
        if (start + self.last_yank_len > self.text.items.len) return;
        if (self.kill_ring.entries.items.len <= 1) return;
        try self.pushUndo();
        self.removeRangeNoUndo(start, start + self.last_yank_len);
        self.kill_ring.rotate();
        const value = self.kill_ring.peek() orelse return;
        self.cursor = start;
        try self.insertNoUndo(value);
        self.last_yank_start = start;
        self.last_yank_len = value.len;
        self.last_was_kill = false;
    }

    fn lineStart(self: *const Editor, pos: usize) usize {
        var i = @min(pos, self.text.items.len);
        while (i > 0 and self.text.items[i - 1] != '\n') : (i -= 1) {}
        return i;
    }

    fn lineEnd(self: *const Editor, pos: usize) usize {
        var i = @min(pos, self.text.items.len);
        while (i < self.text.items.len and self.text.items[i] != '\n') : (i += 1) {}
        return i;
    }

    fn lineEndIncludingNewline(self: *const Editor, pos: usize) usize {
        const end = self.lineEnd(pos);
        return if (end < self.text.items.len) end + 1 else end;
    }

    fn scalarColumn(text: []const u8, start: usize, pos: usize) usize {
        var col: usize = 0;
        var i = start;
        while (i < pos) : (col += 1) i = nav.nextScalar(text, i);
        return col;
    }

    fn positionAtColumn(text: []const u8, start: usize, end: usize, col: usize) usize {
        var i = start;
        var n: usize = 0;
        while (i < end and n < col) : (n += 1) i = nav.nextScalar(text, i);
        return i;
    }

    fn moveVertical(self: *Editor, down: bool) void {
        const start = self.lineStart(self.cursor);
        const col = scalarColumn(self.text.items, start, self.cursor);
        if (down) {
            const end = self.lineEnd(self.cursor);
            if (end >= self.text.items.len) return;
            const next_start = end + 1;
            const next_end = self.lineEnd(next_start);
            self.cursor = positionAtColumn(self.text.items, next_start, next_end, col);
        } else {
            if (start == 0) return;
            const prev_end = start - 1;
            const prev_start = self.lineStart(prev_end);
            self.cursor = positionAtColumn(self.text.items, prev_start, prev_end, col);
        }
    }

    fn historyPrevious(self: *Editor) !void {
        if (self.history.items.len == 0) return;
        if (self.history_index == null) {
            if (self.history_draft) |draft| self.gpa.free(draft);
            self.history_draft = try self.gpa.dupe(u8, self.text.items);
            self.history_index = self.history.items.len - 1;
        } else if (self.history_index.? > 0) {
            self.history_index.? -= 1;
        }
        try self.replaceFromHistory(self.history.items[self.history_index.?]);
    }

    fn historyNext(self: *Editor) !void {
        const idx = self.history_index orelse return;
        if (idx + 1 < self.history.items.len) {
            self.history_index = idx + 1;
            try self.replaceFromHistory(self.history.items[idx + 1]);
        } else {
            const draft = self.history_draft orelse "";
            try self.replaceFromHistory(draft);
            self.leaveHistory();
        }
    }

    fn replaceFromHistory(self: *Editor, value: []const u8) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(self.gpa, value);
        self.cursor = value.len;
    }

    fn leaveHistory(self: *Editor) void {
        self.history_index = null;
        if (self.history_draft) |draft| {
            self.gpa.free(draft);
            self.history_draft = null;
        }
    }

    fn clearYankSpan(self: *Editor) void {
        self.last_yank_start = null;
        self.last_yank_len = 0;
    }

    fn resetTransient(self: *Editor) void {
        self.last_was_kill = false;
        self.clearYankSpan();
        self.leaveHistory();
    }
};

test "editor is UTF-8 safe and undo restores text plus cursor" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("a你好b");
    try ed.apply(.cursor_left);
    try ed.apply(.delete_char_backward);
    try std.testing.expectEqualStrings("a你b", ed.slice());
    try ed.apply(.undo);
    try std.testing.expectEqualStrings("a你好b", ed.slice());
    try std.testing.expectEqual(@as(usize, "a你好".len), ed.cursor);
}

test "editor kill accumulation yank and yank-pop follow upstream semantics" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("alpha beta gamma");
    try ed.apply(.delete_word_backward); // gamma
    try ed.apply(.delete_word_backward); // space + beta, prepended into same kill
    try std.testing.expectEqualStrings("alpha ", ed.slice());
    try std.testing.expectEqualStrings("beta gamma", ed.kill_ring.peek().?);
    try ed.kill_ring.push("older", false, false);
    try ed.apply(.yank);
    try std.testing.expectEqualStrings("alpha older", ed.slice());
    try ed.apply(.yank_pop);
    try std.testing.expectEqualStrings("alpha beta gamma", ed.slice());
}

test "editor vertical movement preserves scalar column" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.setText("abc\n你x\n12345");
    ed.cursor = 2;
    try ed.apply(.cursor_down);
    try std.testing.expectEqual(@as(usize, "abc\n你x".len), ed.cursor);
    try ed.apply(.cursor_down);
    try std.testing.expectEqual(@as(usize, "abc\n你x\n12".len), ed.cursor);
}

test "editor history restores draft after newest entry" {
    var ed = Editor.init(std.testing.allocator);
    defer ed.deinit();
    try ed.addHistory("first");
    try ed.addHistory("second");
    try ed.setText("draft");
    try ed.apply(.history_previous);
    try std.testing.expectEqualStrings("second", ed.slice());
    try ed.apply(.history_previous);
    try std.testing.expectEqualStrings("first", ed.slice());
    try ed.apply(.history_next);
    try std.testing.expectEqualStrings("second", ed.slice());
    try ed.apply(.history_next);
    try std.testing.expectEqualStrings("draft", ed.slice());
}

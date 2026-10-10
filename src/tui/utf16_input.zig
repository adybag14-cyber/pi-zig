//! Owned UTF16 single-line editing state, following Source Input transitions.
//! Word boundaries are injected; this module does not substitute scalar runs
//! for the locale/dictionary-aware Source segmenter.
const std = @import("std");
const graphemes = @import("utf16_graphemes.zig");
pub const Action = enum { left, right, start, end, backspace, delete, kill_start, kill_end, word_left, word_right, kill_word_left, kill_word_right, yank, yank_pop, undo };
pub const WordBoundary = *const fn ([]const u16, i64) i64;
pub const Snapshot = struct { value: []u16, cursor: i64 };
pub const State = struct {
    gpa: std.mem.Allocator,
    value: []u16 = &.{},
    cursor: i64 = 0,
    paste: std.ArrayList(u16) = .empty,
    in_paste: bool = false,
    last: enum { none, kill, yank, type_word } = .none,
    undo_stack: std.ArrayList(Snapshot) = .empty,
    kill_ring: std.ArrayList([]u16) = .empty,
    pub fn init(gpa: std.mem.Allocator) State {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *State) void {
        self.gpa.free(self.value);
        self.paste.deinit(self.gpa);
        for (self.undo_stack.items) |snapshot| self.gpa.free(snapshot.value);
        self.undo_stack.deinit(self.gpa);
        for (self.kill_ring.items) |text| self.gpa.free(text);
        self.kill_ring.deinit(self.gpa);
    }
    pub fn setValue(self: *State, value: []const u16) !void {
        const owned = try self.gpa.dupe(u16, value);
        self.gpa.free(self.value);
        self.value = owned;
        self.cursor = @min(self.cursor, @as(i64, @intCast(value.len)));
    }
    pub fn pushUndo(self: *State) !void {
        const text = try self.gpa.dupe(u16, self.value);
        errdefer self.gpa.free(text);
        try self.undo_stack.append(self.gpa, .{ .value = text, .cursor = self.cursor });
    }
    fn replace(self: *State, start: usize, end: usize, text: []const u16) !void {
        const result = try self.gpa.alloc(u16, start + text.len + self.value.len - end);
        @memcpy(result[0..start], self.value[0..start]);
        @memcpy(result[start..][0..text.len], text);
        @memcpy(result[start + text.len ..], self.value[end..]);
        self.gpa.free(self.value);
        self.value = result;
    }
    pub fn sliceIndex(self: *const State, offset: i64) usize {
        const length: i64 = @intCast(self.value.len);
        return @intCast(if (offset < 0) @max(0, length + offset) else @min(offset, length));
    }
    fn kill(self: *State, start: usize, end: usize, prepend: bool, accumulate: bool) !void {
        const text = self.value[start..end];
        if (text.len != 0) {
            if (accumulate and self.kill_ring.items.len != 0) {
                const index = self.kill_ring.items.len - 1;
                const old = self.kill_ring.items[index];
                const combined = try self.gpa.alloc(u16, old.len + text.len);
                @memcpy(combined[0..if (prepend) text.len else old.len], if (prepend) text else old);
                @memcpy(combined[if (prepend) text.len else old.len..], if (prepend) old else text);
                self.gpa.free(old);
                self.kill_ring.items[index] = combined;
            } else {
                const owned = try self.gpa.dupe(u16, text);
                errdefer self.gpa.free(owned);
                try self.kill_ring.append(self.gpa, owned);
            }
        }
        self.last = .kill;
        try self.replace(start, end, &.{});
    }
    pub fn whitespace(unit: u16) bool {
        return switch (unit) {
            9...13, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
            else => false,
        };
    }
    pub fn insert(self: *State, text: []const u16) !void {
        var has_whitespace = false;
        for (text) |unit| if (whitespace(unit)) {
            has_whitespace = true;
            break;
        };
        if (has_whitespace or self.last != .type_word) try self.pushUndo();
        self.last = .type_word;
        const at = self.sliceIndex(self.cursor);
        try self.replace(at, at, text);
        self.cursor += @intCast(text.len);
    }
    pub fn pasteText(self: *State, text: []const u16) !void {
        self.last = .none;
        try self.pushUndo();
        var clean: std.ArrayList(u16) = .empty;
        defer clean.deinit(self.gpa);
        for (text) |unit| switch (unit) {
            '\r', '\n' => {},
            '\t' => try clean.appendSlice(self.gpa, &.{ ' ', ' ', ' ', ' ' }),
            else => try clean.append(self.gpa, unit),
        };
        const at = self.sliceIndex(self.cursor);
        try self.replace(at, at, clean.items);
        self.cursor += @intCast(clean.items.len);
    }
    pub fn apply(self: *State, action: Action, backward: ?WordBoundary, forward: ?WordBoundary) !void {
        switch (action) {
            .left => {
                self.last = .none;
                if (self.cursor > 0) self.cursor = @intCast(graphemes.previous(self.value, self.sliceIndex(self.cursor)));
            },
            .right => {
                self.last = .none;
                if (self.cursor < self.value.len) {
                    const at = self.sliceIndex(self.cursor);
                    self.cursor += @intCast(graphemes.next(self.value, at) - at);
                }
            },
            .start => {
                self.last = .none;
                self.cursor = 0;
            },
            .end => {
                self.last = .none;
                self.cursor = @intCast(self.value.len);
            },
            .backspace, .delete => {
                self.last = .none;
                if ((action == .backspace and self.cursor <= 0) or (action == .delete and self.cursor >= self.value.len)) return;
                const at = self.sliceIndex(self.cursor);
                const length = if (action == .backspace) at - graphemes.previous(self.value, at) else graphemes.next(self.value, at) - at;
                try self.pushUndo();
                if (action == .backspace) {
                    try self.replace(at - length, at, &.{});
                    self.cursor -= @intCast(length);
                } else try self.replace(at, self.sliceIndex(self.cursor + @as(i64, @intCast(length))), &.{});
            },
            .kill_start, .kill_end => {
                if ((action == .kill_start and self.cursor == 0) or (action == .kill_end and self.cursor >= self.value.len)) return;
                const start = if (action == .kill_start) 0 else self.sliceIndex(self.cursor);
                const end = if (action == .kill_end) self.value.len else self.sliceIndex(self.cursor);
                try self.pushUndo();
                try self.kill(start, end, action == .kill_start, self.last == .kill);
                if (action == .kill_start) self.cursor = 0;
            },
            .word_left, .word_right, .kill_word_left, .kill_word_right => {
                const left = action == .word_left or action == .kill_word_left;
                if ((left and self.cursor == 0) or (!left and self.cursor >= self.value.len)) return;
                const boundary = if (left) backward orelse return error.WordSegmentationUnavailable else forward orelse return error.WordSegmentationUnavailable;
                const target = boundary(self.value, self.cursor);
                if (action == .word_left or action == .word_right) {
                    self.last = .none;
                    self.cursor = target;
                    return;
                }
                const was_kill = self.last == .kill;
                try self.pushUndo();
                try self.kill(self.sliceIndex(if (left) target else self.cursor), self.sliceIndex(if (left) self.cursor else target), left, was_kill);
                if (left) self.cursor = target;
            },
            .yank => {
                if (self.kill_ring.items.len == 0) return;
                const text = self.kill_ring.items[self.kill_ring.items.len - 1];
                if (text.len == 0) return;
                try self.pushUndo();
                const at = self.sliceIndex(self.cursor);
                try self.replace(at, at, text);
                self.cursor += @intCast(text.len);
                self.last = .yank;
            },
            .yank_pop => {
                if (self.last != .yank or self.kill_ring.items.len <= 1) return;
                try self.pushUndo();
                const old = self.kill_ring.items[self.kill_ring.items.len - 1];
                // Source slices at cursor - length, with JS negative-index
                // semantics if a caller changed value between yank operations.
                const signed = self.cursor - @as(i64, @intCast(old.len));
                try self.replace(self.sliceIndex(signed), self.sliceIndex(self.cursor), &.{});
                self.cursor = signed;
                const last = self.kill_ring.pop().?;
                self.kill_ring.insertAssumeCapacity(0, last);
                const text = self.kill_ring.items[self.kill_ring.items.len - 1];
                const at = self.sliceIndex(self.cursor);
                try self.replace(at, at, text);
                self.cursor += @intCast(text.len);
                self.last = .yank;
            },
            .undo => {
                if (self.undo_stack.pop()) |snapshot| {
                    self.gpa.free(self.value);
                    self.value = snapshot.value;
                    self.cursor = snapshot.cursor;
                    self.last = .none;
                }
            },
        }
    }
};
test "UTF16 Input preserves split surrogate insertion coalesced undo and setter cursor" {
    var input = State.init(std.testing.allocator);
    defer input.deinit();
    try input.setValue(&.{ 0xd83d, 0xde00, 'x' });
    try std.testing.expectEqual(@as(i64, 0), input.cursor);
    input.cursor = 1;
    try input.insert(&.{'a'});
    try input.insert(&.{'b'});
    try std.testing.expectEqualSlices(u16, &.{ 0xd83d, 'a', 'b', 0xde00, 'x' }, input.value);
    try input.apply(.undo, null, null);
    try std.testing.expectEqualSlices(u16, &.{ 0xd83d, 0xde00, 'x' }, input.value);
    try std.testing.expectEqual(@as(i64, 1), input.cursor);
    try input.setValue(&.{});
    try std.testing.expectEqual(@as(i64, 0), input.cursor);
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    var input = State.init(gpa);
    defer input.deinit();
    try input.insert(&.{ 'a', 'b' });
    try input.insert(&.{ ' ', 'c' });
    try input.apply(.kill_start, null, null);
    try input.apply(.yank, null, null);
    try input.pasteText(&.{ '\r', '\n', '\t', 0xd800 });
    try input.apply(.backspace, null, null);
    try input.apply(.undo, null, null);
    try input.setValue(&.{ 0xd800, 'z' });
}
test "UTF16 Input every allocation failure frees undo kill paste and value buffers" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn fixtureUnits(value: std.json.Value) ![]u16 {
    const units = try std.testing.allocator.alloc(u16, value.array.items.len);
    for (value.array.items, units) |item, *unit| unit.* = @intCast(item.integer);
    return units;
}
fn expectUnits(expected: std.json.Value, actual: []const u16) !void {
    const units = try fixtureUnits(expected);
    defer std.testing.allocator.free(units);
    try std.testing.expectEqualSlices(u16, units, actual);
}
test "actual Source6fb Input UTF16 transitions undo coalescing kill yank setters and paste" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/input-state-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |trace| {
        var input = State.init(std.testing.allocator);
        defer input.deinit();
        for (trace.array.items) |step| {
            const operation = step.object.get("operation").?.object;
            if (operation.get("cursor")) |value| input.cursor = @intCast(value.integer) else if (operation.get("action")) |value| try input.apply(std.meta.stringToEnum(Action, value.string).?, null, null) else {
                var items = operation.iterator();
                const field = items.next().?;
                const units = try fixtureUnits(field.value_ptr.*);
                defer std.testing.allocator.free(units);
                if (std.mem.eql(u8, field.key_ptr.*, "value")) try input.setValue(units) else if (std.mem.eql(u8, field.key_ptr.*, "text")) try input.insert(units) else try input.pasteText(units);
            }
            const expected = step.object.get("expected").?.object;
            try expectUnits(expected.get("value").?, input.value);
            try std.testing.expectEqual(expected.get("cursor").?.integer, input.cursor);
            const last = expected.get("last").?;
            const wanted = if (last == .null) .none else if (std.mem.eql(u8, last.string, "type-word")) .type_word else std.meta.stringToEnum(@TypeOf(input.last), last.string).?;
            try std.testing.expectEqual(wanted, input.last);
            const undo = expected.get("undo").?.array.items;
            try std.testing.expectEqual(undo.len, input.undo_stack.items.len);
            for (undo, input.undo_stack.items) |want, actual| {
                try expectUnits(want.object.get("value").?, actual.value);
                try std.testing.expectEqual(want.object.get("cursor").?.integer, actual.cursor);
            }
            const kill = expected.get("kill").?.array.items;
            try std.testing.expectEqual(kill.len, input.kill_ring.items.len);
            for (kill, input.kill_ring.items) |want, actual| try expectUnits(want, actual);
        }
    }
    for (fixture.value.object.get("graphemeCases").?.array.items) |item| {
        const text = try fixtureUnits(item.object.get("units").?);
        defer std.testing.allocator.free(text);
        var iterator: graphemes.Iterator = .{ .text = text };
        for (item.object.get("segments").?.array.items) |want| {
            const actual = iterator.next().?;
            try std.testing.expectEqual(@as(usize, @intCast(want.object.get("start").?.integer)), actual.start);
            try std.testing.expectEqual(@as(usize, @intCast(want.object.get("end").?.integer)), actual.end);
        }
        try std.testing.expect(iterator.next() == null);
        for (item.object.get("cursors").?.array.items) |want| {
            const cursor: usize = @intCast(want.object.get("cursor").?.integer);
            try std.testing.expectEqual(@as(usize, @intCast(want.object.get("previous").?.integer)), graphemes.previous(text, cursor));
            try std.testing.expectEqual(@as(usize, @intCast(want.object.get("next").?.integer)), graphemes.next(text, cursor));
        }
    }
}

//! Minimal differential terminal buffer (pi-tui subset).
//! Tracks last painted lines and emits only changed rows (line-oriented).
const std = @import("std");
const Io = std.Io;
const ansi = @import("ansi.zig");

pub const DiffBuffer = struct {
    gpa: std.mem.Allocator,
    io: Io,
    rows: std.ArrayList([]u8) = .empty,
    width: usize = 80,
    height: usize = 24,

    pub fn deinit(self: *DiffBuffer) void {
        for (self.rows.items) |r| self.gpa.free(r);
        self.rows.deinit(self.gpa);
        self.* = undefined;
    }

    /// Replace logical row content; returns true if paint needed.
    pub fn setRow(self: *DiffBuffer, row: usize, text: []const u8) !bool {
        while (self.rows.items.len <= row) {
            try self.rows.append(self.gpa, try self.gpa.dupe(u8, ""));
        }
        if (std.mem.eql(u8, self.rows.items[row], text)) return false;
        self.gpa.free(self.rows.items[row]);
        self.rows.items[row] = try self.gpa.dupe(u8, text);
        return true;
    }

    /// Paint a single row at 1-based terminal line using ANSI cursor addressing.
    pub fn paintRow(self: *DiffBuffer, row: usize) !void {
        if (row >= self.rows.items.len) return;
        var buf: [64]u8 = undefined;
        // CUP: ESC [ row ; col H  (1-based)
        const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};1H\x1b[2K", .{row + 1});
        try writeAll(self.io, seq);
        try writeAll(self.io, self.rows.items[row]);
    }

    pub fn paintDirty(self: *DiffBuffer, dirty: []const bool) !void {
        for (dirty, 0..) |d, i| {
            if (d) try self.paintRow(i);
        }
    }

    /// Full refresh of all rows.
    pub fn repaintAll(self: *DiffBuffer) !void {
        try writeAll(self.io, "\x1b[H\x1b[J"); // home + clear
        for (self.rows.items, 0..) |_, i| {
            try self.paintRow(i);
        }
    }
};

fn writeAll(io: Io, bytes: []const u8) !void {
    _ = ansi;
    const render = @import("render.zig");
    try render.writeAll(io, bytes);
}

test "diff buffer detects changes" {
    const gpa = std.testing.allocator;
    var db = DiffBuffer{ .gpa = gpa, .io = std.testing.io };
    defer db.deinit();
    try std.testing.expect(try db.setRow(0, "hello"));
    try std.testing.expect(!try db.setRow(0, "hello"));
    try std.testing.expect(try db.setRow(0, "world"));
}

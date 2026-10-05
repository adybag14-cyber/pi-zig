//! Native VT cell model for inspecting bytes emitted by a real PTY child.
const std = @import("std");

pub const Cell = struct { scalar: u21 = ' ', continuation: bool = false };
pub const Screen = struct {
    gpa: std.mem.Allocator,
    columns: usize,
    rows: usize,
    primary: []Cell,
    alternate: []Cell,
    in_alternate: bool = false,
    row: usize = 0,
    column: usize = 0,
    saved_row: usize = 0,
    saved_column: usize = 0,
    wrap_pending: bool = false,
    cursor_visible: bool = true,
    frames: usize = 0,
    synchronized_update: bool = false,
    enters: usize = 0,
    leaves: usize = 0,
    mode: enum { ground, escape, csi, string, string_escape } = .ground,
    sequence: std.ArrayList(u8) = .empty,
    utf8: [4]u8 = undefined,
    utf8_length: usize = 0,
    utf8_expected: usize = 0,

    pub fn init(gpa: std.mem.Allocator, columns: usize, rows: usize) !Screen {
        if (columns == 0 or rows == 0 or columns > 10000 or rows > 10000) return error.InvalidScreenSize;
        const primary = try gpa.alloc(Cell, columns * rows);
        errdefer gpa.free(primary);
        const alternate = try gpa.alloc(Cell, columns * rows);
        @memset(primary, .{});
        @memset(alternate, .{});
        return .{ .gpa = gpa, .columns = columns, .rows = rows, .primary = primary, .alternate = alternate };
    }
    pub fn deinit(self: *Screen) void {
        self.gpa.free(self.primary);
        self.gpa.free(self.alternate);
        self.sequence.deinit(self.gpa);
    }
    pub fn cells(self: *Screen) []Cell {
        return if (self.in_alternate) self.alternate else self.primary;
    }
    pub fn resize(self: *Screen, columns: usize, rows: usize) !void {
        var replacement = try Screen.init(self.gpa, columns, rows);
        errdefer replacement.deinit();
        for (0..@min(rows, self.rows)) |row| {
            const width = @min(columns, self.columns);
            @memcpy(replacement.primary[row * columns ..][0..width], self.primary[row * self.columns ..][0..width]);
            @memcpy(replacement.alternate[row * columns ..][0..width], self.alternate[row * self.columns ..][0..width]);
        }
        self.gpa.free(self.primary);
        self.gpa.free(self.alternate);
        self.primary = replacement.primary;
        self.alternate = replacement.alternate;
        self.columns = columns;
        self.rows = rows;
        self.row = @min(self.row, rows - 1);
        self.column = @min(self.column, columns - 1);
        self.saved_row = @min(self.saved_row, rows - 1);
        self.saved_column = @min(self.saved_column, columns - 1);
        self.wrap_pending = false;
    }
    pub fn feed(self: *Screen, bytes: []const u8) !void {
        for (bytes) |byte| switch (self.mode) {
            .escape => switch (byte) {
                '[' => {
                    self.sequence.clearRetainingCapacity();
                    self.mode = .csi;
                },
                ']', 'P', '_', '^' => self.mode = .string,
                '7' => {
                    self.saved_row = self.row;
                    self.saved_column = self.column;
                    self.mode = .ground;
                },
                '8' => {
                    self.row = self.saved_row;
                    self.column = self.saved_column;
                    self.mode = .ground;
                },
                'D' => {
                    self.lineFeed();
                    self.mode = .ground;
                },
                'E' => {
                    self.column = 0;
                    self.lineFeed();
                    self.mode = .ground;
                },
                else => self.mode = .ground,
            },
            .csi => {
                if (byte >= 0x40 and byte <= 0x7e) {
                    self.csi(byte);
                    self.mode = .ground;
                } else {
                    if (self.sequence.items.len >= 4096) return error.TerminalSequenceLimit;
                    try self.sequence.append(self.gpa, byte);
                }
            },
            .string => {
                if (byte == 7) self.mode = .ground else if (byte == 0x1b) self.mode = .string_escape;
            },
            .string_escape => {
                self.mode = if (byte == '\\') .ground else .string;
            },
            .ground => {
                if (self.utf8_length > 0) {
                    if (byte & 0xc0 != 0x80) return error.InvalidTerminalUtf8;
                    self.utf8[self.utf8_length] = byte;
                    self.utf8_length += 1;
                    if (self.utf8_length == self.utf8_expected) {
                        self.put(try std.unicode.utf8Decode(self.utf8[0..self.utf8_length]));
                        self.utf8_length = 0;
                    }
                } else switch (byte) {
                    0x1b => self.mode = .escape,
                    '\r' => {
                        self.column = 0;
                        self.wrap_pending = false;
                    },
                    '\n', 0x0b, 0x0c => self.lineFeed(),
                    8 => {
                        self.column -|= 1;
                        self.wrap_pending = false;
                    },
                    '\t' => {
                        self.column = @min(self.columns - 1, (self.column / 8 + 1) * 8);
                        self.wrap_pending = false;
                    },
                    0...7, 14...26, 28...31, 127 => {},
                    else => if (byte < 128) self.put(byte) else {
                        self.utf8_expected = try std.unicode.utf8ByteSequenceLength(byte);
                        self.utf8[0] = byte;
                        self.utf8_length = 1;
                    },
                }
            },
        };
    }
    fn lineFeed(self: *Screen) void {
        self.wrap_pending = false;
        if (self.row + 1 < self.rows) self.row += 1 else {
            const active = self.cells();
            std.mem.copyForwards(Cell, active[0 .. active.len - self.columns], active[self.columns..]);
            @memset(active[active.len - self.columns ..], .{});
        }
    }
    fn put(self: *Screen, scalar: u21) void {
        const width: usize = if (scalar >= 0x300 and scalar <= 0x36f) 0 else if ((scalar >= 0x1100 and scalar <= 0x115f) or (scalar >= 0x2e80 and scalar <= 0xa4cf) or (scalar >= 0x1f300 and scalar <= 0x1faff)) 2 else 1;
        if (width == 0) return;
        if (self.wrap_pending or self.column + width > self.columns) {
            self.column = 0;
            self.lineFeed();
        }
        self.cells()[self.row * self.columns + self.column] = .{ .scalar = scalar };
        if (width == 2 and self.column + 1 < self.columns) self.cells()[self.row * self.columns + self.column + 1] = .{ .continuation = true };
        self.column += width;
        if (self.column >= self.columns) {
            self.column = self.columns - 1;
            self.wrap_pending = true;
        }
    }
    fn parameter(sequence: []const u8, index: usize, fallback: usize) usize {
        var fields = std.mem.splitScalar(u8, sequence, ';');
        for (0..index) |_| _ = fields.next() orelse return fallback;
        const field = fields.next() orelse return fallback;
        return std.fmt.parseUnsigned(usize, field, 10) catch fallback;
    }
    fn csi(self: *Screen, final: u8) void {
        const sequence = self.sequence.items;
        if ((final == 'h' or final == 'l') and sequence.len > 0 and sequence[0] == '?') {
            var modes = std.mem.splitScalar(u8, sequence[1..], ';');
            while (modes.next()) |value| {
                const flag = std.fmt.parseUnsigned(usize, value, 10) catch continue;
                if (flag == 1049) {
                    if (final == 'h' and !self.in_alternate) {
                        self.saved_row = self.row;
                        self.saved_column = self.column;
                        self.in_alternate = true;
                        @memset(self.alternate, .{});
                        self.row = 0;
                        self.column = 0;
                        self.enters += 1;
                    }
                    if (final == 'l' and self.in_alternate) {
                        self.in_alternate = false;
                        self.row = self.saved_row;
                        self.column = self.saved_column;
                        self.leaves += 1;
                    }
                    self.wrap_pending = false;
                } else if (flag == 25) self.cursor_visible = final == 'h' else if (flag == 2026) {
                    self.synchronized_update = final == 'h';
                    if (final == 'l') self.frames += 1;
                }
            }
            return;
        }
        const n = @max(@as(usize, 1), parameter(sequence, 0, 1));
        switch (final) {
            'H', 'f' => {
                self.row = @min(self.rows - 1, n - 1);
                self.column = @min(self.columns - 1, @max(@as(usize, 1), parameter(sequence, 1, 1)) - 1);
            },
            'A' => self.row -|= n,
            'B' => self.row = @min(self.rows - 1, self.row +| n),
            'C' => self.column = @min(self.columns - 1, self.column +| n),
            'D' => self.column -|= n,
            'G' => self.column = @min(self.columns - 1, n - 1),
            'd' => self.row = @min(self.rows - 1, n - 1),
            'J' => switch (parameter(sequence, 0, 0)) {
                0 => @memset(self.cells()[self.row * self.columns + self.column ..], .{}),
                1 => @memset(self.cells()[0 .. self.row * self.columns + self.column + 1], .{}),
                2 => @memset(self.cells(), .{}),
                else => {},
            },
            'K' => switch (parameter(sequence, 0, 0)) {
                0 => @memset(self.cells()[self.row * self.columns + self.column .. (self.row + 1) * self.columns], .{}),
                1 => @memset(self.cells()[self.row * self.columns .. self.row * self.columns + self.column + 1], .{}),
                2 => @memset(self.cells()[self.row * self.columns .. (self.row + 1) * self.columns], .{}),
                else => {},
            },
            's' => {
                self.saved_row = self.row;
                self.saved_column = self.column;
            },
            'u' => {
                self.row = self.saved_row;
                self.column = self.saved_column;
            },
            else => {},
        }
        if (final != 'm') self.wrap_pending = false;
    }
    pub fn textAlloc(self: *Screen, gpa: std.mem.Allocator) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(gpa);
        for (0..self.rows) |row| {
            const line = self.cells()[row * self.columns .. (row + 1) * self.columns];
            var end = line.len;
            while (end > 0 and line[end - 1].scalar == ' ' and !line[end - 1].continuation) end -= 1;
            for (line[0..end]) |cell| if (!cell.continuation) {
                var buffer: [4]u8 = undefined;
                const length = try std.unicode.utf8Encode(cell.scalar, &buffer);
                try output.appendSlice(gpa, buffer[0..length]);
            };
            try output.append(gpa, '\n');
        }
        return output.toOwnedSlice(gpa);
    }
    pub fn contains(self: *Screen, marker: []const u8) !bool {
        const text = try self.textAlloc(self.gpa);
        defer self.gpa.free(text);
        return std.mem.indexOf(u8, text, marker) != null;
    }
};

test "VT cells interpret fragmented cursor redraws alternate restoration Unicode and synchronized frames" {
    var screen = try Screen.init(std.testing.allocator, 12, 4);
    defer screen.deinit();
    try screen.feed("shell\x1b[?1049h\x1b[?2026h\x1b[2J\x1b[Hhello\r\nworld\x1b[2;");
    try std.testing.expect(screen.synchronized_update);
    try screen.feed("1H\x1b[2K\x1b[1mΩ🙂\x1b[0m\x1b[?2026l");
    try std.testing.expect(try screen.contains("hello\nΩ🙂"));
    try std.testing.expectEqual(@as(usize, 1), screen.frames);
    try std.testing.expect(!screen.synchronized_update);
    // A preceding completed frame cannot make cells of the next, fragmented
    // synchronized update ready for a process assertion.
    try screen.feed("\x1b[?2026h\x1b[2J");
    try std.testing.expect(screen.synchronized_update);
    try std.testing.expectEqual(@as(usize, 1), screen.frames);
    try screen.feed("\x1b[?2026l");
    try std.testing.expect(!screen.synchronized_update);
    try std.testing.expectEqual(@as(usize, 2), screen.frames);
    try screen.feed("\x1b]0;ignored title\x07\x1b[?1049l");
    try std.testing.expect(try screen.contains("shell"));
    try std.testing.expectEqual(@as(usize, 1), screen.enters);
    try std.testing.expectEqual(@as(usize, 1), screen.leaves);
}

fn allocationCase(gpa: std.mem.Allocator) !void {
    var screen = try Screen.init(gpa, 12, 4);
    defer screen.deinit();
    try screen.feed("\x1b[?1049hhello\x1b[2;1Hworld");
    try screen.resize(16, 6);
    const text = try screen.textAlloc(gpa);
    defer gpa.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "hello\nworld") != null);
}
test "VT screen resize and capture release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

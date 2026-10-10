//! One-pass bounded-memory line offsets and decoded UTF-8 byte counts.
const std = @import("std");
const decode = @import("decode.zig");

pub const LineScan = struct {
    newlines: u64,
    start: u64,
    end: u64,
    firstLineEnd: u64,
    lastLineStart: u64,
    selectedBytes: u64,
    firstLineBytes: u64,
};
pub const Options = struct { startLine: u64, endLine: ?u64 = null };
pub const max_safe_integer = 9007199254740991;

pub const LineScanner = struct {
    options: Options,
    position: u64 = 0,
    newlines: u64 = 0,
    line_start: u64 = 0,
    start: ?u64 = null,
    end: ?u64 = null,
    first_line_end: ?u64 = null,
    last_line_start: ?u64 = null,
    selected_bytes: u64 = 0,
    first_line_bytes: u64 = 0,
    selection: ?decode.Decoder = null,
    first_line: ?decode.Decoder = null,
    head: [3]u8 = undefined,
    head_length: u2 = 0,
    head_pending: bool = true,
    bom: bool = false,

    pub fn init(options: Options) !LineScanner {
        if (options.startLine > max_safe_integer or (options.endLine != null and (options.endLine.? <= options.startLine or options.endLine.? > max_safe_integer))) return error.InvalidLineRange;
        var self: LineScanner = .{ .options = options };
        if (options.startLine == 0) self.begin(0);
        return self;
    }
    fn begin(self: *LineScanner, start: u64) void {
        self.start = start;
        if (self.options.endLine != null and self.options.startLine == self.options.endLine.? - 1) self.last_line_start = start;
        self.selection = decode.rangeDecoder();
        self.first_line = decode.rangeDecoder();
    }
    pub fn push(self: *LineScanner, chunk: []const u8) !void {
        var remaining = chunk;
        if (self.head_pending) {
            const take = @min(3 - @as(usize, self.head_length), remaining.len);
            @memcpy(self.head[self.head_length..][0..take], remaining[0..take]);
            self.head_length += @intCast(take);
            if (self.head_length < 3) return;
            try self.releaseHead();
            remaining = remaining[take..];
        }
        try self.process(remaining);
    }
    fn releaseHead(self: *LineScanner) !void {
        self.head_pending = false;
        const head = self.head[0..self.head_length];
        self.bom = decode.startsWithBom(head);
        try self.process(head);
    }
    fn feed(self: *LineScanner, chunk: []const u8, base: u64, from_input: usize, to: usize) !void {
        var from = from_input;
        if (self.bom and base < 3 and base + from < 3) from = @min(to, @as(usize, @intCast(3 - base)));
        if (from >= to) return;
        if (self.selection) |*decoder| try decoder.push(chunk[from..to], decode.Count{ .bytes = &self.selected_bytes });
        if (self.first_line) |*decoder| try decoder.push(chunk[from..to], decode.Count{ .bytes = &self.first_line_bytes });
    }
    fn endFirstLine(self: *LineScanner, position: u64) !void {
        self.first_line_end = position;
        if (self.first_line) |*decoder| try decoder.finish(decode.Count{ .bytes = &self.first_line_bytes });
        self.first_line = null;
    }
    fn endSelection(self: *LineScanner, position: u64) !void {
        self.end = position;
        if (self.selection) |*decoder| try decoder.finish(decode.Count{ .bytes = &self.selected_bytes });
        self.selection = null;
    }
    fn process(self: *LineScanner, chunk: []const u8) !void {
        const base = self.position;
        const next_position = std.math.add(u64, base, chunk.len) catch return error.LineScanSizeOverflow;
        var from: usize = 0;
        for (chunk, 0..) |byte, index| {
            if (byte != '\n') continue;
            try self.feed(chunk, base, from, index);
            const position = base + index;
            if (self.newlines == self.options.startLine) try self.endFirstLine(position);
            if (self.options.endLine != null and self.newlines == self.options.endLine.? - 1) try self.endSelection(position);
            try self.feed(chunk, base, index, index + 1);
            from = index + 1;
            self.newlines += 1;
            self.line_start = position + 1;
            if (self.newlines == self.options.startLine) self.begin(self.line_start);
            if (self.options.endLine != null and self.newlines == self.options.endLine.? - 1) self.last_line_start = self.line_start;
        }
        try self.feed(chunk, base, from, chunk.len);
        self.position = next_position;
    }
    pub fn finish(self: *LineScanner) !LineScan {
        if (self.head_pending) try self.releaseHead();
        const size = self.position;
        if (self.start == null) return .{ .newlines = self.newlines, .start = size, .end = size, .firstLineEnd = size, .lastLineStart = size, .selectedBytes = 0, .firstLineBytes = 0 };
        if (self.first_line_end == null) try self.endFirstLine(size);
        if (self.end == null) try self.endSelection(size);
        return .{ .newlines = self.newlines, .start = self.start.?, .end = self.end.?, .firstLineEnd = self.first_line_end.?, .lastLineStart = self.last_line_start orelse self.line_start, .selectedBytes = self.selected_bytes, .firstLineBytes = self.first_line_bytes };
    }
};

test "durable line scan offsets retain CR and strip only a file leading BOM" {
    const file = "\xef\xbb\xbfA\r\n\xe2\x82\n\xef\xbb\xbfB\n";
    var scanner = try LineScanner.init(.{ .startLine = 1, .endLine = 3 });
    for (file) |byte| try scanner.push(&.{byte});
    try std.testing.expectEqualDeep(LineScan{ .newlines = 3, .start = 6, .end = 13, .firstLineEnd = 8, .lastLineStart = 9, .selectedBytes = 8, .firstLineBytes = 3 }, try scanner.finish());
    try std.testing.expectError(error.InvalidLineRange, LineScanner.init(.{ .startLine = 2, .endLine = 2 }));
    var empty = try LineScanner.init(.{ .startLine = 9 });
    try empty.push(file);
    try std.testing.expectEqual(@as(u64, file.len), (try empty.finish()).start);
}

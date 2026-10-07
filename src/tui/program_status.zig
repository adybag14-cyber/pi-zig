//! Pi 1.1 program status protocol, with owned UTF-8 and OSC-safe messages.
const std = @import("std");
pub const query = "\x1b]7501;?\x1b\\";
pub const State = enum { idle, working, blocked, done, @"error", clear };
pub const Kind = enum { permission, question, auth };
pub const Status = struct { state: State, app: ?[]const u8 = null, kind: ?Kind = null, message: ?[]const u8 = null };

/// Terminal-owned negotiation and cached encoded report. Every returned byte
/// slice is caller-owned, so terminal restart and input threads share no views.
pub const Protocol = struct {
    gpa: std.mem.Allocator,
    latest: ?[]u8 = null,
    supported: bool = false,
    query_pending: bool = false,
    owed_attributes: usize = 0,
    pub fn init(gpa: std.mem.Allocator) Protocol {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *Protocol) void {
        if (self.latest) |bytes| self.gpa.free(bytes);
    }
    pub fn start(self: *Protocol, override: ?[]const u8) ![]u8 {
        if (self.owed_attributes == std.math.maxInt(usize)) return error.ProgramStatusQueryOverflow;
        const forced = if (override) |value| std.mem.eql(u8, value, "1") else false;
        const disabled = if (override) |value| std.mem.eql(u8, value, "0") else false;
        const output = try std.fmt.allocPrint(self.gpa, "\x1b[>7u\x1b[?u{s}\x1b[c{s}", .{
            if (!forced and !disabled) query else "",
            if (forced) self.latest orelse "" else "",
        });
        self.supported = forced;
        self.query_pending = !forced and !disabled;
        self.owed_attributes += 1;
        return output;
    }
    pub fn stop(self: *Protocol) !?[]u8 {
        const result = if (self.supported and self.latest != null) try format(self.gpa, .{ .state = .clear }) else null;
        self.supported = false;
        self.query_pending = false;
        return result;
    }
    pub fn set(self: *Protocol, status: Status) !?[]u8 {
        const encoded = try format(self.gpa, status);
        errdefer self.gpa.free(encoded);
        const report = if (self.supported) try self.gpa.dupe(u8, encoded) else null;
        if (self.latest) |old| self.gpa.free(old);
        self.latest = if (status.state == .clear) null else encoded;
        if (status.state == .clear) self.gpa.free(encoded);
        return report;
    }
    pub fn response(self: *Protocol, sequence: []const u8) !struct { consumed: bool, report: ?[]u8 = null } {
        if (isReply(sequence)) {
            const report = if (self.query_pending and self.latest != null) try self.gpa.dupe(u8, self.latest.?) else null;
            if (self.query_pending) self.supported = true;
            self.query_pending = false;
            return .{ .consumed = true, .report = report };
        }
        if (@import("terminal.zig").parseKeyboardProtocolNegotiationSequence(sequence)) |value| {
            if (value == .device_attributes and self.owed_attributes > 0) {
                self.owed_attributes -= 1;
                if (self.owed_attributes == 0) self.query_pending = false;
            }
        }
        return .{ .consumed = false };
    }
};

pub fn isReply(sequence: []const u8) bool {
    if (!std.mem.startsWith(u8, sequence, "\x1b]7501;?")) return false;
    const end = if (std.mem.endsWith(u8, sequence, "\x07")) sequence.len - 1 else if (std.mem.endsWith(u8, sequence, "\x1b\\")) sequence.len - 2 else return false;
    for (sequence[8..end]) |byte| if (byte == 7 or byte == 27) return false;
    return true;
}
fn validApp(app: []const u8) bool {
    if (app.len == 0 or app.len > 32) return false;
    for (app) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.' and byte != '+' and byte != '-') return false;
    return true;
}
fn whitespace(point: u21) bool {
    return switch (point) {
        9...13, 32, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
pub fn format(gpa: std.mem.Allocator, status: Status) ![]u8 {
    var clean: std.ArrayList(u8) = .empty;
    defer clean.deinit(gpa);
    const message = status.message orelse "";
    var offset: usize = 0;
    var controls = false;
    while (offset < message.len) {
        const width = std.unicode.utf8ByteSequenceLength(message[offset]) catch return error.InvalidStatusUtf8;
        if (width > message.len - offset) return error.InvalidStatusUtf8;
        const point = try std.unicode.utf8Decode(message[offset..][0..width]);
        const control = point <= 31 or (point >= 127 and point <= 159);
        if (control) {
            if (!controls) try clean.append(gpa, ' ');
        } else try clean.appendSlice(gpa, message[offset..][0..width]);
        controls = control;
        offset += width;
    }
    var begin: usize = 0;
    while (begin < clean.items.len) {
        const width = try std.unicode.utf8ByteSequenceLength(clean.items[begin]);
        if (!whitespace(try std.unicode.utf8Decode(clean.items[begin..][0..width]))) break;
        begin += width;
    }
    var end = clean.items.len;
    while (end > begin) {
        var previous = end - 1;
        while (previous > begin and clean.items[previous] & 0xc0 == 0x80) previous -= 1;
        if (!whitespace(try std.unicode.utf8Decode(clean.items[previous..end]))) break;
        end = previous;
    }
    if (end - begin > 2048) {
        end = begin + 2048;
        while (end > begin and clean.items[end] & 0xc0 == 0x80) end -= 1;
    }
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    output.writer.print("\x1b]7501;state={s}", .{@tagName(status.state)}) catch return error.OutOfMemory;
    if (status.app) |app| if (validApp(app)) output.writer.print(":app={s}", .{app}) catch return error.OutOfMemory;
    if (status.state == .blocked) if (status.kind) |kind| output.writer.print(":kind={s}", .{@tagName(kind)}) catch return error.OutOfMemory;
    if (end > begin) {
        const encoder = std.base64.standard.Encoder;
        const encoded = try gpa.alloc(u8, encoder.calcSize(end - begin));
        defer gpa.free(encoded);
        _ = encoder.encode(encoded, clean.items[begin..end]);
        output.writer.print(":msg={s}", .{encoded}) catch return error.OutOfMemory;
    }
    output.writer.writeAll("\x1b\\") catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

test "program status encoding matches Pi states controls app validation and reply boundaries" {
    const gpa = std.testing.allocator;
    const blocked = try format(gpa, .{ .state = .blocked, .app = "pi", .kind = .permission, .message = "Allow bash?" });
    defer gpa.free(blocked);
    try std.testing.expectEqualStrings("\x1b]7501;state=blocked:app=pi:kind=permission:msg=QWxsb3cgYmFzaD8=\x1b\\", blocked);
    const sanitized = try format(gpa, .{ .state = .@"error", .app = "my app", .kind = .auth, .message = "first\nsecond\x1b[31m\u{009b}third\t" });
    defer gpa.free(sanitized);
    try std.testing.expectEqualStrings("\x1b]7501;state=error:msg=Zmlyc3Qgc2Vjb25kIFszMW0gdGhpcmQ=\x1b\\", sanitized);
    try std.testing.expect(isReply(query));
    try std.testing.expect(isReply("\x1b]7501;?version=2\x07"));
    try std.testing.expect(!isReply("\x1b]7501;state=idle\x1b\\"));
    try std.testing.expect(!isReply("\x1b]7501;?\x07extra\x07"));
}
test "program status truncates at UTF-8 boundary after Unicode trim and coalesces control runs" {
    const gpa = std.testing.allocator;
    const input = try gpa.alloc(u8, 4006);
    defer gpa.free(input);
    @memcpy(input[0..3], "\u{3000}");
    for (0..2000) |index| @memcpy(input[3 + index * 2 ..][0..2], "é");
    @memcpy(input[4003..], "\u{3000}");
    const encoded = try format(gpa, .{ .state = .working, .message = input });
    defer gpa.free(encoded);
    const start = std.mem.indexOf(u8, encoded, ":msg=").? + 5;
    const payload = encoded[start .. encoded.len - 2];
    const decoded = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(payload));
    defer gpa.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, payload);
    try std.testing.expectEqual(@as(usize, 2048), decoded.len);
    for (0..1024) |index| try std.testing.expectEqualStrings("é", decoded[index * 2 ..][0..2]);
}

test "program status support handshake caches reports fences DA restarts and clears on stop" {
    const gpa = std.testing.allocator;
    var protocol = Protocol.init(gpa);
    defer protocol.deinit();
    try std.testing.expect(try protocol.set(.{ .state = .working, .app = "pi" }) == null);
    const first = try protocol.start(null);
    defer gpa.free(first);
    try std.testing.expectEqualStrings("\x1b[>7u\x1b[?u\x1b]7501;?\x1b\\\x1b[c", first);
    const reply = try protocol.response("\x1b]7501;?version=2\x07");
    defer gpa.free(reply.report.?);
    try std.testing.expect(reply.consumed and protocol.supported);
    try std.testing.expectEqualStrings("\x1b]7501;state=working:app=pi\x1b\\", reply.report.?);
    const stopped = (try protocol.stop()).?;
    defer gpa.free(stopped);
    try std.testing.expectEqualStrings("\x1b]7501;state=clear\x1b\\", stopped);
    const second = try protocol.start(null);
    defer gpa.free(second);
    _ = try protocol.response("\x1b[?1;2c");
    try std.testing.expect(protocol.query_pending);
    _ = try protocol.response("\x1b[?1;2c");
    try std.testing.expect(!protocol.query_pending);
    try std.testing.expect((try protocol.response(query)).report == null);
    try std.testing.expect(!protocol.supported);
    const forced = try protocol.start("1");
    defer gpa.free(forced);
    try std.testing.expect(std.mem.indexOf(u8, forced, "state=working") != null);
    try std.testing.expect(std.mem.indexOf(u8, forced, query) == null);
    const clear = (try protocol.set(.{ .state = .clear })).?;
    defer gpa.free(clear);
    try std.testing.expect(protocol.latest == null);
    try std.testing.expect(try protocol.stop() == null);
}

test "program status owned report transitions reclaim every failed allocation" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var protocol = Protocol.init(gpa);
            defer protocol.deinit();
            _ = try protocol.set(.{ .state = .working, .app = "pi", .message = "owned Ω message" });
            const start = try protocol.start(null);
            defer gpa.free(start);
            const reply = try protocol.response(query);
            if (reply.report) |bytes| gpa.free(bytes);
            const next = try protocol.set(.{ .state = .blocked, .kind = .question, .message = "Question?" });
            if (next) |bytes| gpa.free(bytes);
            const stopped = try protocol.stop();
            if (stopped) |bytes| gpa.free(bytes);
            const forced = try protocol.start("1");
            defer gpa.free(forced);
            const clear = try protocol.set(.{ .state = .clear });
            if (clear) |bytes| gpa.free(bytes);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

//! Owned portable RFC6455 peer for genuine Source-frame wire gates.
const std = @import("std");
const socket = @import("../ai/codex_websocket.zig");
pub const Turn = struct { request: []const u8, replies: []const []const u8 };
pub const Action = union(enum) { read_text: []const u8, write_raw: []const u8, read_close: []const u8, signal: *std.Io.Event };
pub const Peer = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    listener: std.Io.net.Server,
    path: []const u8,
    headers: []const std.http.Header,
    turns: []const Turn,
    wait_for_disconnect: bool = false,
    actions: []const Action = &.{},
    future: ?std.Io.Future(anyerror!void) = null,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, path: []const u8, headers: []const std.http.Header, turns: []const Turn) !*Peer {
        return initMode(gpa, io, path, headers, turns, false, &.{});
    }
    pub fn initDisconnect(gpa: std.mem.Allocator, io: std.Io, path: []const u8, headers: []const std.http.Header) !*Peer {
        return initMode(gpa, io, path, headers, &.{}, true, &.{});
    }
    pub fn initActions(gpa: std.mem.Allocator, io: std.Io, path: []const u8, actions: []const Action) !*Peer {
        return initMode(gpa, io, path, &.{}, &.{}, false, actions);
    }
    fn initMode(gpa: std.mem.Allocator, io: std.Io, path: []const u8, headers: []const std.http.Header, turns: []const Turn, wait_for_disconnect: bool, actions: []const Action) !*Peer {
        const self = try gpa.create(Peer);
        errdefer gpa.destroy(self);
        const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
        self.* = .{ .gpa = gpa, .io = io, .listener = try address.listen(io, .{ .reuse_address = true }), .path = path, .headers = headers, .turns = turns, .wait_for_disconnect = wait_for_disconnect, .actions = actions };
        errdefer self.listener.deinit(io);
        self.future = try io.concurrent(serve, .{self});
        return self;
    }
    pub fn url(self: *Peer, gpa: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(gpa, "ws://127.0.0.1:{d}{s}", .{ self.listener.socket.address.getPort(), self.path });
    }
    pub fn finish(self: *Peer) !void {
        if (self.future) |*future| {
            const value = future.await(self.io);
            self.future = null;
            try value;
        }
    }
    pub fn deinit(self: *Peer) void {
        if (self.future) |*future| future.cancel(self.io) catch {};
        self.listener.deinit(self.io);
        self.gpa.destroy(self);
    }
    fn serve(self: *Peer) anyerror!void {
        const peer = try self.listener.accept(self.io);
        defer peer.close(self.io);
        var read_buffer: [16 * 1024]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;
        var reader = peer.reader(self.io, &read_buffer);
        var writer = peer.writer(self.io, &write_buffer);
        var http = std.http.Server.init(&reader.interface, &writer.interface);
        const request = try http.receiveHead();
        if (request.head.method != .GET) return error.SourceWebSocketMethodMismatch;
        if (!std.mem.eql(u8, request.head.target, self.path)) return error.SourceWebSocketPathMismatch;
        var key: ?[]const u8 = null;
        for (self.headers) |expected| {
            var iterator = request.iterateHeaders();
            var found = false;
            while (iterator.next()) |header| if (std.ascii.eqlIgnoreCase(header.name, expected.name)) {
                if (!std.mem.eql(u8, header.value, expected.value)) return error.SourceWebSocketHeaderMismatch;
                found = true;
            };
            if (!found) return error.SourceWebSocketHeaderMissing;
        }
        var iterator = request.iterateHeaders();
        while (iterator.next()) |header| if (std.ascii.eqlIgnoreCase(header.name, "sec-websocket-key")) {
            key = header.value;
        };
        var accept: [28]u8 = undefined;
        socket.expectedAccept(key orelse return error.MissingWebSocketKey, &accept);
        try writer.interface.print("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept});
        try writer.interface.flush();
        for (self.actions) |action| switch (action) {
            .read_text => |expected| {
                const payload = try readClientText(self.gpa, &reader.interface);
                defer self.gpa.free(payload);
                if (!std.mem.eql(u8, payload, expected)) return error.FixtureTextMismatch;
            },
            .write_raw => |bytes| {
                try writer.interface.writeAll(bytes);
                try writer.interface.flush();
            },
            .read_close => |expected| {
                const payload = try readClientFrame(self.gpa, &reader.interface, 0x88);
                defer self.gpa.free(payload);
                if (!std.mem.eql(u8, payload, expected)) return error.FixtureCloseMismatch;
            },
            .signal => |event| event.set(self.io),
        };
        for (self.turns) |turn| {
            const payload = try readClientText(self.gpa, &reader.interface);
            defer self.gpa.free(payload);
            if (!std.mem.eql(u8, payload, turn.request)) return error.SourceWebSocketFrameMismatch;
            for (turn.replies) |reply| {
                try writeServerText(&writer.interface, reply);
                try writer.interface.flush();
            }
        }
        if (self.wait_for_disconnect) {
            _ = reader.interface.takeByte() catch |err| switch (err) {
                error.EndOfStream => return,
                else => return err,
            };
            return error.ExpectedOwnedSocketDisconnect;
        }
    }
};
fn readClientText(gpa: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    return readClientFrame(gpa, reader, 0x81);
}
fn readClientFrame(gpa: std.mem.Allocator, reader: *std.Io.Reader, expected_opcode: u8) ![]u8 {
    const prefix = try reader.takeArray(2);
    if (prefix[0] != expected_opcode or (prefix[1] & 0x80) == 0) return error.ExpectedMaskedClientFrame;
    const length: u64 = switch (prefix[1] & 0x7f) {
        126 => try reader.takeInt(u16, .big),
        127 => try reader.takeInt(u64, .big),
        else => prefix[1] & 0x7f,
    };
    if (length > 4 * 1024 * 1024) return error.FixtureFrameTooLarge;
    const mask = try reader.takeArray(4);
    const payload = try gpa.alloc(u8, @intCast(length));
    errdefer gpa.free(payload);
    try reader.readSliceAll(payload);
    for (payload, 0..) |*byte, index| byte.* ^= mask[index & 3];
    return payload;
}
fn writeServerText(writer: *std.Io.Writer, payload: []const u8) !void {
    try writer.writeByte(0x81);
    if (payload.len < 126) try writer.writeByte(@intCast(payload.len)) else if (payload.len <= std.math.maxInt(u16)) {
        try writer.writeByte(126);
        try writer.writeInt(u16, @intCast(payload.len), .big);
    } else {
        try writer.writeByte(127);
        try writer.writeInt(u64, payload.len, .big);
    }
    try writer.writeAll(payload);
}

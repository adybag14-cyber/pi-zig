//! Incremental protocol-v1 client connection state machine.
//! Transport ownership stays with the caller, allowing memory, Unix-socket,
//! embedded and test transports to share identical framing/handshake behavior.
const std = @import("std");
const protocol = @import("../protocol/root.zig");
const server_json = protocol.server_json;

pub const ConnectionState = enum { disconnected, connecting, connected };

pub const Error = error{
    AlreadyConnecting,
    AlreadyConnected,
    NotConnecting,
    NotConnected,
    DataBeforeHelloSent,
    ExpectedServerHello,
    UnexpectedHandshake,
    ServerRejectedHello,
    InvalidMaxFrameLength,
};

/// Message ownership is transferred to the callback. A callback must either
/// retain the arena-backed value or call `deinit` before returning.
pub const Handlers = struct {
    context: ?*anyopaque = null,
    on_handshake: *const fn (?*anyopaque, server_json.ParsedServerMessage) anyerror!void,
    on_handshake_error: *const fn (?*anyopaque, server_json.ParsedServerMessage) anyerror!void = discardMessage,
    on_message: *const fn (?*anyopaque, server_json.ParsedServerMessage) anyerror!void,
    on_state_change: ?*const fn (?*anyopaque, ConnectionState) void = null,
};

fn discardMessage(_: ?*anyopaque, value: server_json.ParsedServerMessage) anyerror!void {
    var owned = value;
    owned.deinit();
}

pub const Connection = struct {
    gpa: std.mem.Allocator,
    max_frame_length: usize,
    state: ConnectionState = .disconnected,
    transport_ready: bool = false,
    decoder: protocol.framing.Decoder,
    generation: u64 = 0,

    pub fn init(gpa: std.mem.Allocator, max_frame_length: usize) !Connection {
        if (max_frame_length == 0 or max_frame_length > std.math.maxInt(u32)) return Error.InvalidMaxFrameLength;
        return .{
            .gpa = gpa,
            .max_frame_length = max_frame_length,
            .decoder = .{ .gpa = gpa, .max_frame_length = max_frame_length },
        };
    }

    pub fn deinit(self: *Connection) void {
        self.decoder.deinit();
        self.* = undefined;
    }

    /// Starts one fresh lifecycle and returns the framed protocol hello. The
    /// caller should acquire its transport, call `markTransportReady`, and send
    /// this frame. Data delivered before that mark is rejected.
    pub fn start(self: *Connection, handlers: Handlers) ![]u8 {
        switch (self.state) {
            .connecting => return Error.AlreadyConnecting,
            .connected => return Error.AlreadyConnected,
            .disconnected => {},
        }
        self.resetDecoder();
        self.generation +%= 1;
        self.transport_ready = false;
        self.transition(.connecting, handlers);
        const frame = protocol.codec.encodeClientJsonFrame(self.gpa, "{\"type\":\"hello\",\"version\":1}") catch |err| {
            self.transition(.disconnected, handlers);
            return err;
        };
        if (frame.len - 4 > self.max_frame_length) {
            self.gpa.free(frame);
            self.transition(.disconnected, handlers);
            return protocol.framing.Error.FrameTooLarge;
        }
        return frame;
    }

    pub fn markTransportReady(self: *Connection) !void {
        if (self.state != .connecting) return Error.NotConnecting;
        self.transport_ready = true;
    }

    pub fn push(self: *Connection, chunk: []const u8, handlers: Handlers) !void {
        if (self.state == .disconnected) return Error.NotConnected;
        if (self.state == .connecting and !self.transport_ready) {
            self.fail(handlers);
            return Error.DataBeforeHelloSent;
        }
        const payloads = self.decoder.push(chunk) catch |err| {
            self.fail(handlers);
            return err;
        };
        defer {
            for (payloads) |payload| self.gpa.free(payload);
            self.gpa.free(payloads);
        }
        for (payloads) |payload| {
            var parsed = protocol.codec.decodeServerPayload(self.gpa, payload) catch |err| {
                self.fail(handlers);
                return err;
            };
            self.deliver(&parsed, handlers) catch |err| {
                self.fail(handlers);
                return err;
            };
        }
    }

    /// Validates that the terminal byte stream ended on a frame boundary.
    pub fn end(self: *Connection, handlers: Handlers) !void {
        if (self.state == .disconnected) return;
        self.decoder.end() catch |err| {
            self.fail(handlers);
            return err;
        };
        self.fail(handlers);
    }

    pub fn disconnect(self: *Connection, handlers: Handlers) void {
        if (self.state == .disconnected) return;
        self.fail(handlers);
    }

    fn deliver(self: *Connection, parsed: *server_json.ParsedServerMessage, handlers: Handlers) !void {
        switch (self.state) {
            .connecting => switch (parsed.message) {
                .hello => {
                    const transferred = parsed.*;
                    parsed.* = undefined;
                    handlers.on_handshake(handlers.context, transferred) catch |err| return err;
                    self.transition(.connected, handlers);
                },
                .hello_error => {
                    const transferred = parsed.*;
                    parsed.* = undefined;
                    handlers.on_handshake_error(handlers.context, transferred) catch |err| return err;
                    return Error.ServerRejectedHello;
                },
                else => {
                    parsed.deinit();
                    parsed.* = undefined;
                    return Error.ExpectedServerHello;
                },
            },
            .connected => switch (parsed.message) {
                .hello, .hello_error => {
                    parsed.deinit();
                    parsed.* = undefined;
                    return Error.UnexpectedHandshake;
                },
                else => {
                    const transferred = parsed.*;
                    parsed.* = undefined;
                    try handlers.on_message(handlers.context, transferred);
                },
            },
            .disconnected => return Error.NotConnected,
        }
    }

    fn fail(self: *Connection, handlers: Handlers) void {
        self.transport_ready = false;
        self.transition(.disconnected, handlers);
    }

    fn transition(self: *Connection, next: ConnectionState, handlers: Handlers) void {
        if (self.state == next) return;
        self.state = next;
        if (handlers.on_state_change) |callback| callback(handlers.context, next);
    }

    fn resetDecoder(self: *Connection) void {
        self.decoder.deinit();
        self.decoder = .{ .gpa = self.gpa, .max_frame_length = self.max_frame_length };
    }
};

const empty_snapshot =
    "{\"serverId\":\"server-1\",\"protocolVersion\":1,\"revision\":0,\"sessions\":[],\"models\":[]}";

const TestHandler = struct {
    handshakes: usize = 0,
    messages: usize = 0,
    rejected: usize = 0,
    states: std.ArrayList(ConnectionState) = .empty,

    fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.states.deinit(gpa);
    }
    fn handlers(self: *@This()) Handlers {
        return .{
            .context = self,
            .on_handshake = onHandshake,
            .on_handshake_error = onHandshakeError,
            .on_message = onMessage,
            .on_state_change = onState,
        };
    }
    fn onHandshake(raw: ?*anyopaque, value: server_json.ParsedServerMessage) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var owned = value;
        defer owned.deinit();
        self.handshakes += 1;
    }
    fn onHandshakeError(raw: ?*anyopaque, value: server_json.ParsedServerMessage) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var owned = value;
        defer owned.deinit();
        self.rejected += 1;
    }
    fn onMessage(raw: ?*anyopaque, value: server_json.ParsedServerMessage) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var owned = value;
        defer owned.deinit();
        self.messages += 1;
    }
    fn onState(raw: ?*anyopaque, value: ConnectionState) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.states.append(std.testing.allocator, value) catch unreachable;
    }
};

test "connection sends hello then accepts fragmented server hello" {
    const gpa = std.testing.allocator;
    var connection = try Connection.init(gpa, protocol.framing.DEFAULT_MAX_FRAME_LENGTH);
    defer connection.deinit();
    var observer: TestHandler = .{};
    defer observer.deinit(gpa);
    const handlers = observer.handlers();
    const client_hello = try connection.start(handlers);
    defer gpa.free(client_hello);
    var decoded = try protocol.codec.decodeClientFrame(gpa, client_hello);
    defer protocol.json.deinitClientMessage(gpa, &decoded);
    try std.testing.expect(decoded == .hello);
    try connection.markTransportReady();

    const json = "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_snapshot ++ "}";
    const frame = try protocol.codec.encodeJsonFrame(gpa, json);
    defer gpa.free(frame);
    try connection.push(frame[0..3], handlers);
    try connection.push(frame[3..9], handlers);
    try connection.push(frame[9..], handlers);
    try std.testing.expectEqual(ConnectionState.connected, connection.state);
    try std.testing.expectEqual(@as(usize, 1), observer.handshakes);
    try std.testing.expectEqualSlices(ConnectionState, &.{ .connecting, .connected }, observer.states.items);
}

test "connection rejects data before transport readiness and non-hello first messages" {
    const gpa = std.testing.allocator;
    var observer: TestHandler = .{};
    defer observer.deinit(gpa);
    const handlers = observer.handlers();
    var connection = try Connection.init(gpa, protocol.framing.DEFAULT_MAX_FRAME_LENGTH);
    defer connection.deinit();
    const hello = try connection.start(handlers);
    defer gpa.free(hello);
    const server = try protocol.codec.encodeJsonFrame(gpa, "{\"type\":\"event\",\"event\":{\"type\":\"server_snapshot\",\"snapshot\":" ++ empty_snapshot ++ "}}");
    defer gpa.free(server);
    try std.testing.expectError(Error.DataBeforeHelloSent, connection.push(server, handlers));
    try std.testing.expectEqual(ConnectionState.disconnected, connection.state);

    const hello2 = try connection.start(handlers);
    defer gpa.free(hello2);
    try connection.markTransportReady();
    try std.testing.expectError(Error.ExpectedServerHello, connection.push(server, handlers));
    try std.testing.expectEqual(ConnectionState.disconnected, connection.state);
}

test "connection rejects duplicate handshake and detects truncated terminal frame" {
    const gpa = std.testing.allocator;
    var observer: TestHandler = .{};
    defer observer.deinit(gpa);
    const handlers = observer.handlers();
    var connection = try Connection.init(gpa, protocol.framing.DEFAULT_MAX_FRAME_LENGTH);
    defer connection.deinit();
    const client = try connection.start(handlers);
    defer gpa.free(client);
    try connection.markTransportReady();
    const json = "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_snapshot ++ "}";
    const frame = try protocol.codec.encodeJsonFrame(gpa, json);
    defer gpa.free(frame);
    try connection.push(frame, handlers);
    try std.testing.expectError(Error.UnexpectedHandshake, connection.push(frame, handlers));

    const retry = try connection.start(handlers);
    defer gpa.free(retry);
    try connection.markTransportReady();
    try connection.push(frame[0..2], handlers);
    try std.testing.expectError(protocol.framing.Error.TruncatedFrame, connection.end(handlers));
}

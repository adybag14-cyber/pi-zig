//! Offline loopback HTTP plans for native provider process/transport gates.
const std = @import("std");
pub const Reply = struct {
    path: []const u8,
    body: []const u8,
    status: std.http.Status = .ok,
    headers: []const std.http.Header = &.{},
    delay_ms: u32 = 0,
    payload_contains: ?[]const u8 = null,
    expected_request_headers: []const std.http.Header = &.{},
    request_observed: ?*std.Io.Event = null,
    response_release: ?*std.Io.Event = null,
};
pub const Captured = struct { path: []u8, payload: []u8 };
pub const PlanServer = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    listener: std.Io.net.Server,
    replies: []const Reply,
    captured: std.ArrayList(Captured) = .empty,
    future: ?std.Io.Future(anyerror!void) = null,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, replies: []const Reply) !*PlanServer {
        const self = try gpa.create(PlanServer);
        errdefer gpa.destroy(self);
        const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
        self.* = .{ .gpa = gpa, .io = io, .listener = try address.listen(io, .{ .reuse_address = true }), .replies = replies };
        errdefer self.listener.deinit(io);
        self.future = try io.concurrent(serve, .{self});
        return self;
    }

    pub fn url(self: *const PlanServer, gpa: std.mem.Allocator, suffix: []const u8) ![]u8 {
        return std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}{s}", .{ self.listener.socket.address.getPort(), suffix });
    }

    pub fn finish(self: *PlanServer) !void {
        if (self.future) |*future| {
            const result = future.await(self.io);
            self.future = null;
            try result;
        }
    }

    pub fn deinit(self: *PlanServer) void {
        if (self.future) |*future| future.cancel(self.io) catch {};
        self.listener.deinit(self.io);
        for (self.captured.items) |record| {
            self.gpa.free(record.path);
            self.gpa.free(record.payload);
        }
        self.captured.deinit(self.gpa);
        const allocator = self.gpa;
        allocator.destroy(self);
    }

    fn serve(self: *PlanServer) anyerror!void {
        for (self.replies) |reply| {
            const connection = try self.listener.accept(self.io);
            defer connection.close(self.io);
            var read_buffer: [16 * 1024]u8 = undefined;
            var write_buffer: [4096]u8 = undefined;
            var reader = connection.reader(self.io, &read_buffer);
            var writer = connection.writer(self.io, &write_buffer);
            var server = std.http.Server.init(&reader.interface, &writer.interface);
            var request = try server.receiveHead();
            for (reply.expected_request_headers) |expected| {
                var iterator = request.iterateHeaders();
                var found = false;
                while (iterator.next()) |header| {
                    if (!std.ascii.eqlIgnoreCase(header.name, expected.name)) continue;
                    if (!std.mem.eql(u8, header.value, expected.value)) return error.UnexpectedFixtureHeader;
                    found = true;
                }
                if (!found) return error.MissingFixtureHeader;
            }
            const path = try self.gpa.dupe(u8, request.head.target);
            var captured = false;
            errdefer if (!captured) self.gpa.free(path);
            const body_reader = request.readerExpectNone(&.{});
            const payload = try body_reader.allocRemaining(self.gpa, .limited(4 * 1024 * 1024));
            errdefer if (!captured) self.gpa.free(payload);
            try self.captured.append(self.gpa, .{ .path = path, .payload = payload });
            captured = true;
            if (!std.mem.eql(u8, path, reply.path)) return error.UnexpectedFixturePath;
            if (reply.payload_contains) |marker| if (std.mem.indexOf(u8, payload, marker) == null) return error.UnexpectedFixturePayload;
            if (reply.request_observed) |event| event.set(self.io);
            if (reply.response_release) |event| try event.waitTimeout(self.io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
            if (reply.delay_ms > 0) try self.io.sleep(.fromMilliseconds(reply.delay_ms), .awake);
            var headers: std.ArrayList(std.http.Header) = .empty;
            defer headers.deinit(self.gpa);
            try headers.append(self.gpa, .{ .name = "content-type", .value = "application/json" });
            try headers.appendSlice(self.gpa, reply.headers);
            try request.respond(reply.body, .{ .status = reply.status, .keep_alive = false, .extra_headers = headers.items });
        }
    }
};

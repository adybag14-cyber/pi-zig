//! One-request owned peer retaining the actual wire method, target and headers.
const std = @import("std");
pub const Capture = struct { method: std.http.Method, target: []const u8, body: []const u8, headers: []const std.http.Header };
pub const Server = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    listener: std.Io.net.Server,
    response: []const u8,
    response_chunks: ?[]const []const u8 = null,
    captured: ?Capture = null,
    future: ?std.Io.Future(anyerror!void) = null,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, response: []const u8) !*Server {
        return initPlan(gpa, io, response, null);
    }
    fn initPlan(gpa: std.mem.Allocator, io: std.Io, response: []const u8, chunks: ?[]const []const u8) !*Server {
        const self = try gpa.create(Server);
        errdefer gpa.destroy(self);
        const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
        self.* = .{ .gpa = gpa, .arena = .init(gpa), .io = io, .listener = try address.listen(io, .{ .reuse_address = true }), .response = response, .response_chunks = chunks };
        errdefer self.listener.deinit(io);
        self.future = try io.concurrent(serve, .{self});
        return self;
    }
    pub fn url(self: *const Server, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}{s}", .{ self.listener.socket.address.getPort(), path });
    }
    pub fn initChunks(gpa: std.mem.Allocator, io: std.Io, chunks: []const []const u8) !*Server {
        return initPlan(gpa, io, "", chunks);
    }
    pub fn finish(self: *Server) !Capture {
        if (self.future) |*future| {
            const result = future.await(self.io);
            self.future = null;
            try result;
        }
        return self.captured orelse error.MissingActualWireRequest;
    }
    pub fn deinit(self: *Server) void {
        if (self.future) |*future| future.cancel(self.io) catch {};
        self.listener.deinit(self.io);
        self.arena.deinit();
        self.gpa.destroy(self);
    }
    fn serve(self: *Server) anyerror!void {
        const connection = try self.listener.accept(self.io);
        defer connection.close(self.io);
        var read_buffer: [16 * 1024]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;
        var reader = connection.reader(self.io, &read_buffer);
        var writer = connection.writer(self.io, &write_buffer);
        var protocol = std.http.Server.init(&reader.interface, &writer.interface);
        var request = try protocol.receiveHead();
        const a = self.arena.allocator();
        const target = try a.dupe(u8, request.head.target);
        var headers: std.ArrayList(std.http.Header) = .empty;
        var fields = request.iterateHeaders();
        while (fields.next()) |field| try headers.append(a, .{ .name = try a.dupe(u8, field.name), .value = try a.dupe(u8, field.value) });
        const body_reader = request.readerExpectNone(&.{});
        const body = try body_reader.allocRemaining(a, .limited(4 * 1024 * 1024));
        self.captured = .{ .method = request.head.method, .target = target, .body = body, .headers = headers.items };
        const options: std.http.Server.Request.RespondOptions = .{ .extra_headers = &.{ .{ .name = "content-type", .value = "text/event-stream" }, .{ .name = "x-fixture", .value = "source-only" } } };
        if (self.response_chunks) |chunks| {
            var response = try request.respondStreaming(&.{}, .{ .respond_options = options });
            for (chunks) |chunk| {
                try response.writer.writeAll(chunk);
                try response.writer.flush();
                try response.flush();
            }
            try response.end();
        } else try request.respond(self.response, options);
    }
};

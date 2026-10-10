//! Owned loopback fixture routes HTTP methods independently of GET/POST scheduling.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
pub const Record = struct { method: std.http.Method, body: []u8, authorization: []u8 };
pub const Server = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    listener: std.Io.net.Server,
    future: ?std.Io.Future(anyerror!void) = null,
    records: std.ArrayList(Record) = .empty,
    get_seen: std.Io.Event = .unset,
    pub fn init(gpa: std.mem.Allocator, io: std.Io) !*Server {
        const self = try gpa.create(Server);
        errdefer gpa.destroy(self);
        const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
        self.* = .{ .gpa = gpa, .io = io, .listener = try address.listen(io, .{ .reuse_address = true }) };
        errdefer self.listener.deinit(io);
        self.future = try io.concurrent(serve, .{self});
        return self;
    }
    pub fn url(self: *Server, gpa: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/mcp", .{self.listener.socket.address.getPort()});
    }
    pub fn finish(self: *Server) !void {
        if (self.future) |*future| {
            const result = future.await(self.io);
            self.future = null;
            try result;
        }
    }
    pub fn deinit(self: *Server) void {
        if (self.future) |*future| future.cancel(self.io) catch {};
        self.listener.deinit(self.io);
        for (self.records.items) |record| {
            self.gpa.free(record.body);
            self.gpa.free(record.authorization);
        }
        self.records.deinit(self.gpa);
        self.gpa.destroy(self);
    }
    fn serve(self: *Server) anyerror!void {
        while (true) {
            const stream = try self.listener.accept(self.io);
            defer stream.close(self.io);
            var input_buffer: [16384]u8 = undefined;
            var output_buffer: [4096]u8 = undefined;
            var reader = stream.reader(self.io, &input_buffer);
            var writer = stream.writer(self.io, &output_buffer);
            var http = std.http.Server.init(&reader.interface, &writer.interface);
            var request = try http.receiveHead();
            if (!std.mem.eql(u8, request.head.target, "/mcp")) return error.InvalidFixturePath;
            var recorded = false;
            var authorization: []const u8 = "";
            var headers = request.iterateHeaders();
            while (headers.next()) |header| if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
                authorization = header.value;
            };
            const owned_auth = try self.gpa.dupe(u8, authorization);
            errdefer if (!recorded) self.gpa.free(owned_auth);
            const body = try request.readerExpectNone(&.{}).allocRemaining(self.gpa, .limited(1024 * 1024));
            errdefer if (!recorded) self.gpa.free(body);
            try self.records.append(self.gpa, .{ .method = request.head.method, .body = body, .authorization = owned_auth });
            recorded = true;
            if (!std.mem.eql(u8, owned_auth, "Bearer owned-token")) return error.InvalidFixtureAuthorization;
            if (request.head.method == .GET) {
                self.get_seen.set(self.io);
                try request.respond("", .{ .status = .method_not_allowed, .keep_alive = false });
                continue;
            }
            if (request.head.method == .DELETE) {
                try request.respond("", .{ .status = .no_content, .keep_alive = false });
                return;
            }
            if (request.head.method != .POST) return error.InvalidFixtureMethod;
            var message = try json.Owned.parse(self.gpa, body);
            defer message.deinit();
            if (try protocol.kind(message.value) == .notification) {
                try request.respond("", .{ .status = .accepted, .keep_alive = false });
                continue;
            }
            const id = try protocol.field(message.value, "id");
            const method = try protocol.text(message.value, "method");
            var result: json.Owned = undefined;
            if (std.mem.eql(u8, method, "initialize")) result = try json.Owned.parse(self.gpa, "{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"http-configured\",\"version\":\"1\"}}") else if (std.mem.eql(u8, method, "tools/list")) result = try json.Owned.parse(self.gpa, "{\"tools\":[{\"name\":\"echo\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"message\":{\"type\":\"string\"}},\"required\":[\"message\"]}}]}") else if (std.mem.eql(u8, method, "tools/call")) {
                result = try json.Owned.empty(self.gpa);
                const a = result.arena.allocator();
                const params = try protocol.field(message.value, "params");
                const arguments = try protocol.field(params, "arguments");
                var block: Value = .{ .object = .empty };
                try block.object.put(a, "type", .{ .string = "text" });
                try block.object.put(a, "text", try json.clone(a, try protocol.field(arguments, "message")));
                var content: Value = .{ .array = .init(a) };
                try content.array.append(block);
                result.value = .{ .object = .empty };
                try result.value.object.put(a, "content", content);
            } else return error.InvalidFixtureRpc;
            defer result.deinit();
            var response = try protocol.response(self.gpa, id, result.value, false);
            defer response.deinit();
            const output = try json.stringify(self.gpa, response.value);
            defer self.gpa.free(output);
            try request.respond(output, .{ .keep_alive = false, .extra_headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "mcp-session-id", .value = "configured-session" } } });
        }
    }
};

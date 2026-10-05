//! Bounded native loopback HTTP fixture and native browser-opener executable.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const Io = std.Io;
pub const Request = struct {
    method: []const u8,
    path: []const u8,
    headers: []const u8,
    body: []const u8,
    arrival_ms: i64,
    pub fn header(self: Request, name: []const u8) ?[]const u8 {
        var lines = std.mem.splitSequence(u8, self.headers, "\r\n");
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (std.ascii.eqlIgnoreCase(line[0..colon], name)) return std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
        return null;
    }
};
pub const Response = struct { status: u16 = 200, headers: []const u8 = "", body: []const u8, delay_ms: u32 = 0 };
pub const CapturedRequest = Request;
pub const Handler = *const fn (?*anyopaque, Request, []u8) anyerror!Response;

fn now(io: Io) i64 {
    return Io.Clock.awake.now(io).toMilliseconds();
}

fn address(port: u16) linux.sockaddr.in {
    return .{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, 0x7f000001) };
}

fn ready(io: Io, fd: linux.fd_t, events: i16, end: i64) !void {
    const remaining = end - now(io);
    if (remaining <= 0) return error.HttpFixtureTimeout;
    var descriptor: linux.pollfd = .{ .fd = fd, .events = events, .revents = 0 };
    switch (linux.errno(linux.poll(@ptrCast(&descriptor), 1, @intCast(@min(remaining, 50))))) {
        .SUCCESS, .INTR => {},
        else => return error.HttpFixturePollFailed,
    }
    if (descriptor.revents & linux.POLL.NVAL != 0) return error.HttpFixtureInvalidSocket;
}

fn send(io: Io, fd: linux.fd_t, bytes: []const u8, end: i64) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        if (now(io) >= end) return error.HttpFixtureTimeout;
        const written = linux.sendto(fd, bytes[offset..].ptr, bytes.len - offset, linux.MSG.NOSIGNAL, null, 0);
        switch (linux.errno(written)) {
            .SUCCESS => {
                if (written == 0) return error.HttpFixtureDisconnected;
                offset += written;
            },
            .INTR => continue,
            .AGAIN => try ready(io, fd, linux.POLL.OUT, end),
            else => return error.HttpFixtureDisconnected,
        }
    }
}

fn contentLength(header: []const u8) !usize {
    var lines = std.mem.splitSequence(u8, header, "\r\n");
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(line[0..colon], "content-length")) return std.fmt.parseInt(usize, std.mem.trim(u8, line[colon + 1 ..], " \t"), 10);
    }
    return 0;
}

fn receive(io: Io, fd: linux.fd_t, buffer: []u8, end: i64, stop: ?*std.atomic.Value(bool)) ![]const u8 {
    var used: usize = 0;
    while (true) {
        if (stop) |flag| if (flag.load(.acquire)) return error.HttpFixtureStopped;
        if (now(io) >= end) return error.HttpFixtureTimeout;
        if (used == buffer.len) return error.HttpFixtureRequestLimit;
        const count = linux.read(fd, buffer[used..].ptr, buffer.len - used);
        switch (linux.errno(count)) {
            .SUCCESS => {
                if (count == 0) return error.HttpFixtureDisconnected;
                used += count;
                if (std.mem.indexOf(u8, buffer[0..used], "\r\n\r\n")) |header_end| {
                    const length = try contentLength(buffer[0..header_end]);
                    if (length > buffer.len - header_end - 4) return error.HttpFixtureRequestLimit;
                    if (used >= header_end + 4 + length) return buffer[0 .. header_end + 4 + length];
                }
            },
            .INTR => continue,
            .AGAIN => try ready(io, fd, linux.POLL.IN, end),
            else => return error.HttpFixtureDisconnected,
        }
    }
}

pub const Server = struct {
    gpa: std.mem.Allocator,
    io: Io,
    fd: linux.fd_t,
    port: u16,
    context: ?*anyopaque,
    handler: Handler,
    stopped: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    failure: ?anyerror = null,
    request_timeout_ms: u32 = 3000,
    mutex: Io.Mutex = .init,
    captured: std.ArrayList(CapturedRequest) = .empty,
    scripted: ?[]const Response = null,
    response_index: usize = 0,

    pub fn start(gpa: std.mem.Allocator, io: Io, context: ?*anyopaque, handler: Handler) !*Server {
        if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
        const result = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, 0);
        if (linux.errno(result) != .SUCCESS) return error.HttpFixtureSocketFailed;
        const fd: linux.fd_t = @intCast(result);
        errdefer _ = linux.close(fd);
        var local = address(0);
        if (linux.errno(linux.bind(fd, @ptrCast(&local), @sizeOf(@TypeOf(local)))) != .SUCCESS) return error.HttpFixtureBindFailed;
        if (linux.errno(linux.listen(fd, 16)) != .SUCCESS) return error.HttpFixtureListenFailed;
        var length: linux.socklen_t = @sizeOf(@TypeOf(local));
        if (linux.errno(linux.getsockname(fd, @ptrCast(&local), &length)) != .SUCCESS) return error.HttpFixtureAddressFailed;
        const self = try gpa.create(Server);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .fd = fd, .port = std.mem.bigToNative(u16, local.port), .context = context, .handler = handler };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }

    fn handle(self: *Server, fd: linux.fd_t) !void {
        var input: [65536]u8 = undefined;
        const arrival_ms = now(self.io);
        const end = arrival_ms + self.request_timeout_ms;
        const message = try receive(self.io, fd, &input, end, &self.stopped);
        const first_line = std.mem.indexOf(u8, message, "\r\n") orelse return error.HttpFixtureMalformedRequest;
        var parts = std.mem.splitScalar(u8, message[0..first_line], ' ');
        const method = parts.next() orelse return error.HttpFixtureMalformedRequest;
        const path = parts.next() orelse return error.HttpFixtureMalformedRequest;
        const body_start = (std.mem.indexOf(u8, message, "\r\n\r\n") orelse return error.HttpFixtureMalformedRequest) + 4;
        var output: [4096]u8 = undefined;
        const request: Request = .{ .method = method, .path = path, .headers = message[first_line + 2 .. body_start - 4], .body = message[body_start..], .arrival_ms = arrival_ms };
        try self.capture(request);
        const response = if (self.scripted) |responses| blk: {
            if (self.response_index >= responses.len) return error.HttpFixtureScriptExhausted;
            defer self.response_index += 1;
            break :blk responses[self.response_index];
        } else try self.handler(self.context, request, &output);
        const delayed_until = now(self.io) + response.delay_ms;
        while (now(self.io) < delayed_until) {
            if (self.stopped.load(.acquire)) return error.HttpFixtureStopped;
            if (now(self.io) >= end) return error.HttpFixtureTimeout;
            try self.io.sleep(.fromMilliseconds(@min(10, @max(1, delayed_until - now(self.io)))), .awake);
        }
        var header: [4096]u8 = undefined;
        var writer = Io.Writer.fixed(&header);
        try writer.print("HTTP/1.1 {d} {s}\r\ncontent-length: {d}\r\nconnection: close\r\n", .{ response.status, if (response.status == 200) "OK" else "Error", response.body.len });
        const response_request: Request = .{ .method = "", .path = "", .headers = response.headers, .body = "", .arrival_ms = 0 };
        if (response_request.header("content-type") == null) try writer.writeAll("content-type: application/json\r\n");
        if (response.headers.len != 0) {
            try writer.writeAll(response.headers);
            if (!std.mem.endsWith(u8, response.headers, "\r\n")) try writer.writeAll("\r\n");
        }
        try writer.writeAll("\r\n");
        try send(self.io, fd, writer.buffered(), end);
        try send(self.io, fd, response.body, end);
    }

    fn run(self: *Server) void {
        while (!self.stopped.load(.acquire)) {
            ready(self.io, self.fd, linux.POLL.IN, now(self.io) + 1000) catch |err| {
                self.failure = err;
                return;
            };
            const accepted = linux.accept4(self.fd, null, null, linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK);
            switch (linux.errno(accepted)) {
                .SUCCESS => {
                    const fd: linux.fd_t = @intCast(accepted);
                    self.handle(fd) catch |err| switch (err) {
                        error.HttpFixtureDisconnected, error.HttpFixtureStopped => {},
                        else => self.failure = err,
                    };
                    _ = linux.close(fd);
                },
                .AGAIN, .INTR => {},
                else => {
                    self.failure = error.HttpFixtureAcceptFailed;
                    return;
                },
            }
        }
    }

    pub fn finish(self: *Server) !void {
        self.stopped.store(true, .release);
        if (self.thread) |thread| thread.join();
        self.thread = null;
        if (self.failure) |err| return err;
    }

    pub fn deinit(self: *Server) void {
        self.finish() catch |err| std.debug.print("Owned HTTP fixture failed: {s}\n", .{@errorName(err)});
        _ = linux.close(self.fd);
        for (self.captured.items) |request| freeRequest(self.gpa, request);
        self.captured.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    fn capture(self: *Server, request: Request) !void {
        const owned = try cloneRequest(self.gpa, request);
        errdefer freeRequest(self.gpa, owned);
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        try self.captured.append(self.gpa, owned);
    }

    pub fn snapshotRequests(self: *Server, gpa: std.mem.Allocator) ![]CapturedRequest {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const result = try gpa.alloc(CapturedRequest, self.captured.items.len);
        var initialized: usize = 0;
        errdefer {
            for (result[0..initialized]) |request| freeRequest(gpa, request);
            gpa.free(result);
        }
        for (result, self.captured.items) |*owned, request| {
            owned.* = try cloneRequest(gpa, request);
            initialized += 1;
        }
        return result;
    }

    pub fn startScripted(gpa: std.mem.Allocator, io: Io, responses: []const Response) !*Server {
        const self = try start(gpa, io, null, unreachableHandler);
        // No client exists yet; the caller connects only after this returns.
        self.scripted = responses;
        return self;
    }
};

fn unreachableHandler(_: ?*anyopaque, _: Request, _: []u8) !Response {
    return error.HttpFixtureScriptMissing;
}

fn cloneRequest(gpa: std.mem.Allocator, request: Request) !CapturedRequest {
    const method = try gpa.dupe(u8, request.method);
    errdefer gpa.free(method);
    const path = try gpa.dupe(u8, request.path);
    errdefer gpa.free(path);
    const headers = try gpa.dupe(u8, request.headers);
    errdefer gpa.free(headers);
    const body = try gpa.dupe(u8, request.body);
    return .{ .method = method, .path = path, .headers = headers, .body = body, .arrival_ms = request.arrival_ms };
}

fn freeRequest(gpa: std.mem.Allocator, request: CapturedRequest) void {
    gpa.free(request.method);
    gpa.free(request.path);
    gpa.free(request.headers);
    gpa.free(request.body);
}

pub fn freeRequests(gpa: std.mem.Allocator, requests: []CapturedRequest) void {
    for (requests) |request| freeRequest(gpa, request);
    gpa.free(requests);
}

fn getMessage(io: Io, port: u16, path: []const u8, response: []u8) ![]const u8 {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const result = linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, 0);
    if (linux.errno(result) != .SUCCESS) return error.HttpFixtureSocketFailed;
    const fd: linux.fd_t = @intCast(result);
    defer _ = linux.close(fd);
    const local = address(port);
    const end = now(io) + 10_000;
    switch (linux.errno(linux.connect(fd, &local, @sizeOf(@TypeOf(local))))) {
        .SUCCESS => {},
        .INPROGRESS => {
            try ready(io, fd, linux.POLL.OUT, end);
            var socket_error: c_int = 0;
            var size: linux.socklen_t = @sizeOf(c_int);
            if (linux.errno(linux.getsockopt(fd, linux.SOL.SOCKET, linux.SO.ERROR, @ptrCast(&socket_error), &size)) != .SUCCESS or socket_error != 0) return error.HttpFixtureConnectFailed;
        },
        else => return error.HttpFixtureConnectFailed,
    }
    var request: [4096]u8 = undefined;
    try send(io, fd, try std.fmt.bufPrint(&request, "GET {s} HTTP/1.1\r\nhost: 127.0.0.1:{d}\r\nconnection: close\r\n\r\n", .{ path, port }), end);
    return receive(io, fd, response, end, null);
}

pub fn get(io: Io, port: u16, path: []const u8) !u16 {
    var response: [65536]u8 = undefined;
    const message = try getMessage(io, port, path, &response);
    var parts = std.mem.splitScalar(u8, message, ' ');
    _ = parts.next();
    return std.fmt.parseInt(u16, parts.next() orelse return error.HttpFixtureMalformedResponse, 10);
}

/// Build this source as pi-auth-opener; the dialog test symlinks it to xdg-open.
pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const url = args.next() orelse return error.MissingBrowserUrl;
    const output = init.environ_map.get("PI_AUTH_OPENED_URL") orelse return error.MissingBrowserCapturePath;
    const file = try Io.Dir.createFileAbsolute(init.io, output, .{});
    defer file.close(init.io);
    try file.writeStreamingAll(init.io, url);
}

test "native HTTP scripted responses retain status headers bodies delays and captured requests" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const responses = [_]Response{
        .{ .status = 503, .headers = "Retry-After-Ms: 5\r\nX-Should-Retry: true\r\n", .body = "{\"error\":\"retry\"}", .delay_ms = 5 },
        .{ .body = "{\"ok\":true}" },
    };
    const server = try Server.startScripted(std.testing.allocator, std.testing.io, &responses);
    defer server.deinit();
    var output: [65536]u8 = undefined;
    const first_response = try getMessage(std.testing.io, server.port, "/first", &output);
    try std.testing.expect(std.mem.startsWith(u8, first_response, "HTTP/1.1 503 "));
    try std.testing.expect(std.mem.indexOf(u8, first_response, "Retry-After-Ms: 5\r\nX-Should-Retry: true\r\n") != null);
    try std.testing.expect(std.mem.endsWith(u8, first_response, "{\"error\":\"retry\"}"));
    try std.testing.expectEqual(@as(u16, 200), try get(std.testing.io, server.port, "/second"));
    try server.finish();
    const requests = try server.snapshotRequests(std.testing.allocator);
    defer freeRequests(std.testing.allocator, requests);
    try std.testing.expectEqual(@as(usize, 2), requests.len);
    try std.testing.expectEqualStrings("GET", requests[0].method);
    try std.testing.expectEqualStrings("/first", requests[0].path);
    try std.testing.expectEqualStrings("/second", requests[1].path);
    try std.testing.expect(requests[0].header("HOST") != null);
    try std.testing.expectEqualStrings("", requests[0].body);
    try std.testing.expect(requests[1].arrival_ms >= requests[0].arrival_ms + 5);
}

fn capturedRequestAllocationProbe(gpa: std.mem.Allocator) !void {
    const owned = try cloneRequest(gpa, .{ .method = "POST", .path = "/native", .headers = "content-type: application/json", .body = "{\"owned\":true}", .arrival_ms = 17 });
    defer freeRequest(gpa, owned);
    try std.testing.expectEqualStrings("{\"owned\":true}", owned.body);
    try std.testing.expectEqualStrings("application/json", owned.header("Content-Type").?);
}

test "native HTTP captured request ownership releases every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, capturedRequestAllocationProbe, .{});
}

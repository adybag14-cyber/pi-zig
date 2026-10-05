//! Native Streamable HTTP using Pi's existing proxy and joined cancellation path.
const std = @import("std");
const protocol = @import("protocol.zig");
const transport_mod = @import("transport.zig");
const fetch = @import("../ai/http_fetch.zig");
const proxy = @import("../ai/http_proxy.zig");
const sse = @import("sse.zig");
pub const Options = struct {
    url: []const u8,
    headers: []const std.http.Header = &.{},
    proxy: proxy.Config = .{},
    open_get_stream: bool = true,
    max_message_bytes: usize = 16 * 1024 * 1024,
    initial_delay_ms: u32 = 1000,
    max_delay_ms: u32 = 30_000,
    max_retries: usize = 5,
    error_context: ?*anyopaque = null,
    on_http_error: ?*const fn (?*anyopaque, u16, []const u8) anyerror!void = null,
};
pub const Http = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    arena: std.heap.ArenaAllocator,
    options: Options,
    mutex: std.Io.Mutex = .init,
    closing_mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    receiver: ?transport_mod.Receiver = null,
    started: bool = false,
    closing: bool = false,
    active: usize = 0,
    session_id: ?[]u8 = null,
    version: ?[]u8 = null,
    get_started: bool = false,
    get_future: ?std.Io.Future(anyerror!void) = null,
    closed_emitted: bool = false,
    pub fn create(gpa: std.mem.Allocator, io: std.Io, options: Options) !*Http {
        const uri = try std.Uri.parse(options.url);
        if (!std.mem.eql(u8, uri.scheme, "http") and !std.mem.eql(u8, uri.scheme, "https")) return error.UnsupportedMcpUrl;
        const self = try gpa.create(Http);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .arena = .init(gpa), .options = options };
        errdefer self.arena.deinit();
        const a = self.arena.allocator();
        self.options.url = try a.dupe(u8, options.url);
        const headers = try a.alloc(std.http.Header, options.headers.len);
        for (headers, options.headers) |*to, source| to.* = .{ .name = try a.dupe(u8, source.name), .value = try a.dupe(u8, source.value) };
        self.options.headers = headers;
        if (options.proxy.setting) |setting| self.options.proxy.setting = try a.dupe(u8, setting);
        return self;
    }
    pub fn deinit(self: *Http) void {
        self.close() catch {};
        if (self.session_id) |value| self.gpa.free(value);
        if (self.version) |value| self.gpa.free(value);
        self.arena.deinit();
        const gpa = self.gpa;
        gpa.destroy(self);
    }
    pub fn transport(self: *Http) transport_mod.Transport {
        return .{ .context = self, .vtable = &vtable };
    }
    const vtable: transport_mod.Transport.VTable = .{ .start = startRaw, .send = sendRaw, .close = closeRaw, .protocol_version = versionRaw };
    fn from(raw: *anyopaque) *Http {
        return @ptrCast(@alignCast(raw));
    }
    fn startRaw(raw: *anyopaque, receiver: transport_mod.Receiver) !void {
        const self = from(raw);
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.started) return error.McpTransportAlreadyStarted;
        if (@atomicLoad(bool, &self.closing, .acquire)) return error.McpConnectionClosed;
        self.receiver = receiver;
        self.started = true;
    }
    fn sendRaw(raw: *anyopaque, value: protocol.Value, flag: ?*bool) !void {
        return from(raw).send(value, flag);
    }
    fn closeRaw(raw: *anyopaque) !void {
        return from(raw).close();
    }
    fn versionRaw(raw: *anyopaque, value: []const u8) !void {
        const self = from(raw);
        const copied = try self.gpa.dupe(u8, value);
        errdefer self.gpa.free(copied);
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.version) |old| self.gpa.free(old);
        self.version = copied;
    }
    fn putHeader(a: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
        for (headers.items) |*header| if (std.ascii.eqlIgnoreCase(header.name, name)) {
            header.value = try a.dupe(u8, value);
            return;
        };
        try headers.append(a, .{ .name = try a.dupe(u8, name), .value = try a.dupe(u8, value) });
    }
    fn makeHeaders(self: *Http, a: std.mem.Allocator, method: std.http.Method, last_id: ?[]const u8) ![]const std.http.Header {
        var result: std.ArrayList(std.http.Header) = .empty;
        for (self.options.headers) |header| try putHeader(a, &result, header.name, header.value);
        if (method == .POST) {
            try putHeader(a, &result, "accept", "application/json, text/event-stream");
            try putHeader(a, &result, "content-type", "application/json");
        } else if (method == .GET) try putHeader(a, &result, "accept", "text/event-stream");
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.session_id) |value| try putHeader(a, &result, "Mcp-Session-Id", value);
        if (self.version) |value| try putHeader(a, &result, "MCP-Protocol-Version", value);
        if (last_id) |value| try putHeader(a, &result, "last-event-id", value);
        return result.items;
    }
    fn begin(self: *Http) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (!self.started or @atomicLoad(bool, &self.closing, .acquire)) return error.McpConnectionClosed;
        self.active += 1;
    }
    fn endOperation(self: *Http) void {
        self.mutex.lockUncancelable(self.io);
        self.active -= 1;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
    }
    fn send(self: *Http, value: protocol.Value, flag: ?*bool) !void {
        if (flag) |aborted| if (@atomicLoad(bool, aborted, .acquire)) return error.McpRequestAborted;
        try self.begin();
        defer self.endOperation();
        const bytes = try protocol.json.stringify(self.gpa, value);
        defer self.gpa.free(bytes);
        var body = Body.init(self, jsonRequestId(value));
        defer body.deinit();
        _ = self.perform(.POST, bytes, &body, null, null) catch |cause| {
            if (body.answered) {
                try body.finish();
                return;
            }
            return cause;
        };
        try body.finish();
        if (jsonRequestId(value) != null and (body.status == 202 or body.status == 204)) return error.McpAcceptedWithoutResponse;
        if (jsonRequestId(value) == null and jsonMethod(value, "notifications/initialized")) try self.startGet();
    }
    fn jsonRequestId(value: protocol.Value) ?protocol.Value {
        const kind = protocol.kind(value) catch return null;
        return if (kind == .request) protocol.json.get(value, "id") else null;
    }
    fn jsonMethod(value: protocol.Value, method: []const u8) bool {
        const actual = protocol.text(value, "method") catch return false;
        return std.mem.eql(u8, actual, method);
    }
    fn perform(self: *Http, method: std.http.Method, payload: ?[]const u8, body: *Body, last_id: ?[]const u8, timeout: ?u64) !fetch.Result {
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        var client: std.http.Client = .{ .allocator = self.gpa, .io = self.io };
        defer client.deinit();
        _ = try proxy.configureClient(&client, arena.allocator(), self.options.url, self.options.proxy);
        return fetch.fetchControlledObserved(&client, .{ .location = .{ .url = self.options.url }, .method = method, .payload = payload, .keep_alive = false, .extra_headers = try self.makeHeaders(arena.allocator(), method, last_id), .response_writer = &body.writer }, timeout, if (method == .DELETE) null else &self.closing, .{ .context = body, .callback = Body.head });
    }
    fn startGet(self: *Http) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (!self.options.open_get_stream or self.get_started or @atomicLoad(bool, &self.closing, .acquire)) return;
        self.get_started = true;
        self.get_future = try self.io.concurrent(getLoop, .{self});
    }
    fn getLoop(self: *Http) anyerror!void {
        var last_id: ?[]u8 = null;
        defer if (last_id) |value| self.gpa.free(value);
        var retry_ms: ?f64 = null;
        var attempt: usize = 0;
        while (!@atomicLoad(bool, &self.closing, .acquire)) {
            var body = Body.init(self, null);
            defer body.deinit();
            body.is_get = true;
            const result = self.perform(.GET, null, &body, last_id, null);
            if (@atomicLoad(bool, &self.closing, .acquire)) return;
            if (result) |response| {
                if (response.status == 405) return;
                body.finish() catch |cause| self.receiver.?.failure(self.receiver.?.context, cause);
            } else |cause| {
                self.receiver.?.failure(self.receiver.?.context, cause);
                if (body.status == 401 or body.status == 403 or body.status == 404 or (body.status >= 400 and body.status < 500 and body.status != 408 and body.status != 429)) return;
            }
            if (body.last_id) |id| {
                const copied = try self.gpa.dupe(u8, id);
                if (last_id) |old| self.gpa.free(old);
                last_id = copied;
            }
            if (body.retry_ms) |millis| retry_ms = millis;
            if (body.received) attempt = 0;
            if (attempt >= self.options.max_retries) {
                self.receiver.?.failure(self.receiver.?.context, error.McpGetStreamDropped);
                return;
            }
            const multiplier: usize = @as(usize, 1) << @intCast(@min(attempt, 20));
            const delay = if (retry_ms) |value| @min(value, @as(f64, @floatFromInt(self.options.max_delay_ms))) else @as(f64, @floatFromInt(@min(@as(usize, self.options.initial_delay_ms) * multiplier, self.options.max_delay_ms)));
            attempt += 1;
            const deadline = std.Io.Clock.awake.now(self.io).toMilliseconds() + @as(i64, @intFromFloat(@max(0, delay)));
            while (!@atomicLoad(bool, &self.closing, .acquire) and std.Io.Clock.awake.now(self.io).toMilliseconds() < deadline) try self.io.sleep(.fromMilliseconds(5), .awake);
        }
    }
    pub fn sessionIdCopy(self: *Http, gpa: std.mem.Allocator) !?[]u8 {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        return if (self.session_id) |value| try gpa.dupe(u8, value) else null;
    }
    pub fn close(self: *Http) !void {
        @atomicStore(bool, &self.closing, true, .release);
        self.closing_mutex.lockUncancelable(self.io);
        defer self.closing_mutex.unlock(self.io);
        if (self.get_future) |*future| {
            future.cancel(self.io) catch {};
            self.get_future = null;
        }
        self.mutex.lockUncancelable(self.io);
        while (self.active > 0) self.changed.waitUncancelable(self.io, &self.mutex);
        const remove = self.started and self.session_id != null and !self.closed_emitted;
        self.mutex.unlock(self.io);
        if (remove) {
            var body = Body.init(self, null);
            defer body.deinit();
            _ = self.perform(.DELETE, null, &body, null, 1000) catch {};
        }
        if (!self.closed_emitted) {
            self.closed_emitted = true;
            if (self.receiver) |receiver| receiver.closed(receiver.context);
        }
    }
    const Mode = enum { discard, json, sse, failure };
    const Body = struct {
        transport: *Http,
        request_id: ?protocol.Value,
        writer: std.Io.Writer = .{ .buffer = &.{}, .vtable = &.{ .drain = drain } },
        mode: Mode = .discard,
        status: u16 = 0,
        json_bytes: std.ArrayList(u8) = .empty,
        parser: sse.Parser,
        cause: ?anyerror = null,
        answered: bool = false,
        is_get: bool = false,
        received: bool = false,
        last_id: ?[]u8 = null,
        retry_ms: ?f64 = null,
        fn init(self: *Http, id: ?protocol.Value) Body {
            return .{ .transport = self, .request_id = id, .parser = sse.Parser.init(self.gpa, .{ .on_event = event, .on_id = eventId, .on_retry = eventRetry, .max_event_bytes = self.options.max_message_bytes }) };
        }
        fn deinit(self: *Body) void {
            self.parser.deinit();
            self.json_bytes.deinit(self.transport.gpa);
            if (self.last_id) |value| self.transport.gpa.free(value);
        }
        fn head(raw: ?*anyopaque, value: std.http.Client.Response.Head) !void {
            const self: *Body = @ptrCast(@alignCast(raw.?));
            self.status = @intCast(@intFromEnum(value.status));
            self.parser.options.context = self;
            var content_type: ?[]const u8 = null;
            var session_id: ?[]const u8 = null;
            var iterator = value.iterateHeaders();
            while (iterator.next()) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, "content-type")) content_type = header.value;
                if (std.ascii.eqlIgnoreCase(header.name, "mcp-session-id")) session_id = header.value;
            }
            if (self.status < 200 or self.status >= 300) {
                if (self.status == 405 and self.is_get) {
                    self.mode = .discard;
                    return;
                }
                self.mode = .failure;
                return;
            }
            if (session_id) |id| if (id.len > 0) {
                const copied = try self.transport.gpa.dupe(u8, id);
                self.transport.mutex.lockUncancelable(self.transport.io);
                if (self.transport.session_id) |old| self.transport.gpa.free(old);
                self.transport.session_id = copied;
                self.transport.mutex.unlock(self.transport.io);
            };
            if (self.request_id == null and !self.is_get) {
                self.mode = .discard;
                return;
            }
            const raw_type = content_type orelse return error.UnsupportedMcpContentType;
            const end = std.mem.indexOfScalar(u8, raw_type, ';') orelse raw_type.len;
            const kind = std.mem.trim(u8, raw_type[0..end], " \t");
            if (std.ascii.eqlIgnoreCase(kind, "application/json") and !self.is_get) self.mode = .json else if (std.ascii.eqlIgnoreCase(kind, "text/event-stream")) self.mode = .sse else return error.UnsupportedMcpContentType;
        }
        fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            const self: *Body = @fieldParentPtr("writer", writer);
            self.feed(writer.buffer[0..writer.end]) catch |cause| {
                self.cause = cause;
                return error.WriteFailed;
            };
            writer.end = 0;
            var consumed: usize = 0;
            for (data[0 .. data.len - 1]) |slice| {
                self.feed(slice) catch |cause| {
                    self.cause = cause;
                    return error.WriteFailed;
                };
                consumed += slice.len;
            }
            for (0..splat) |_| {
                self.feed(data[data.len - 1]) catch |cause| {
                    self.cause = cause;
                    return error.WriteFailed;
                };
                consumed += data[data.len - 1].len;
            }
            return consumed;
        }
        fn feed(self: *Body, bytes: []const u8) !void {
            switch (self.mode) {
                .discard => {},
                .sse => {
                    try self.parser.push(bytes);
                    if (self.answered) return error.McpResponseComplete;
                },
                .json, .failure => {
                    const max = if (self.mode == .failure) @min(self.transport.options.max_message_bytes, 8192) else self.transport.options.max_message_bytes;
                    if (bytes.len > max -| self.json_bytes.items.len) return error.McpMessageTooLarge;
                    try self.json_bytes.appendSlice(self.transport.gpa, bytes);
                },
            }
        }
        fn event(raw: ?*anyopaque, value: sse.Event) !void {
            const self: *Body = @ptrCast(@alignCast(raw.?));
            self.received = true;
            if (std.mem.trim(u8, value.data, " \t\r\n").len == 0) return;
            if (value.event) |name| if (!std.mem.eql(u8, name, "message")) return;
            var owned = protocol.json.Owned.parse(self.transport.gpa, value.data) catch |cause| {
                self.transport.receiver.?.failure(self.transport.receiver.?.context, cause);
                return;
            };
            defer owned.deinit();
            const kind = protocol.kind(owned.value) catch |cause| {
                self.transport.receiver.?.failure(self.transport.receiver.?.context, cause);
                return;
            };
            try self.transport.receiver.?.message(self.transport.receiver.?.context, owned.value);
            if (kind == .response and self.request_id != null and protocol.json.equal(try protocol.field(owned.value, "id"), self.request_id.?)) self.answered = true;
        }
        fn eventId(raw: ?*anyopaque, value: []const u8) !void {
            const self: *Body = @ptrCast(@alignCast(raw.?));
            const copied = try self.transport.gpa.dupe(u8, value);
            if (self.last_id) |old| self.transport.gpa.free(old);
            self.last_id = copied;
        }
        fn eventRetry(raw: ?*anyopaque, value: f64) !void {
            const self: *Body = @ptrCast(@alignCast(raw.?));
            self.retry_ms = value;
        }
        fn finish(self: *Body) !void {
            if (self.cause) |cause| if (cause != error.McpResponseComplete) return cause;
            switch (self.mode) {
                .discard => {},
                .sse => {
                    try self.parser.finish();
                    if (self.request_id != null and !self.answered) return error.McpResponseStreamIncomplete;
                },
                .failure => {
                    if (self.transport.options.on_http_error) |callback| try callback(self.transport.options.error_context, self.status, self.json_bytes.items);
                    if (self.status == 401) return error.McpAuthRequired;
                    if (self.status == 404 and self.transport.session_id != null) return error.McpSessionExpired;
                    return error.McpHttpError;
                },
                .json => {
                    var owned = try protocol.json.Owned.parse(self.transport.gpa, self.json_bytes.items);
                    defer owned.deinit();
                    if (owned.value == .array) {
                        for (owned.value.array.items) |value| {
                            _ = try protocol.kind(value);
                            try self.transport.receiver.?.message(self.transport.receiver.?.context, value);
                        }
                    } else {
                        _ = try protocol.kind(owned.value);
                        try self.transport.receiver.?.message(self.transport.receiver.?.context, owned.value);
                    }
                },
            }
        }
    };
};

//! Raw native HTTP/SSE worker. No JS values or provider interpretation cross
//! this thread boundary. The owner consumes exact SSE fields and owns all VM
//! callbacks, JSON decoding, retry decisions and assistant-message state.
const std = @import("std");
const fetch = @import("../ai/http_fetch.zig");
const proxy = @import("../ai/http_proxy.zig");
const a = std.heap.page_allocator;
pub const maximum_frame_bytes = 512 * 1024;
pub const maximum_queue_bytes = 1024 * 1024;
pub const maximum_queue_items = 64;
pub const Framing = enum { sse, bytes, body };
pub const Header = struct { name: []u8, value: []u8 };
pub const Head = struct {
    status: u16,
    status_text: []u8,
    headers: []Header,
    fn deinit(self: Head) void {
        a.free(self.status_text);
        for (self.headers) |header| {
            a.free(header.name);
            a.free(header.value);
        }
        a.free(self.headers);
    }
};
pub const Frame = struct {
    event: ?[]u8,
    data: []u8,
    fn deinit(self: Frame) void {
        if (self.event) |value| a.free(value);
        a.free(self.data);
    }
};
pub const Event = union(enum) {
    head: Head,
    frame: Frame,
    bytes: []u8,
    body: []u8,
    error_body: []u8,
    pub fn deinit(self: Event) void {
        switch (self) {
            .head => |value| value.deinit(),
            .frame => |value| value.deinit(),
            .bytes, .body, .error_body => |value| a.free(value),
        }
    }
    fn storageBytes(self: Event) usize {
        return switch (self) {
            .head => |value| count: {
                var n: usize = value.status_text.len;
                for (value.headers) |header| n += header.name.len + header.value.len;
                break :count n;
            },
            .frame => |value| value.data.len + if (value.event) |name| name.len else 0,
            .bytes, .body, .error_body => |value| value.len,
        };
    }
};
pub const Input = struct {
    url: []const u8,
    payload: []const u8,
    headers: []const std.http.Header,
    proxy_url: ?[]const u8 = null,
    timeout_ms: ?u64 = null,
    method: std.http.Method = .POST,
    framing: Framing = .sse,
    /// Central e3b8a89 opt-in, backported without unrelated preparation hooks.
    stream_error_bytes: bool = false,
};
const OwnedInput = struct {
    url: []u8,
    payload: []u8,
    headers: []std.http.Header,
    proxy_url: ?[]u8,
    timeout_ms: ?u64,
    method: std.http.Method,
    framing: Framing,
    stream_error_bytes: bool,
    fn copy(input: Input) !OwnedInput {
        const url = try a.dupe(u8, input.url);
        errdefer a.free(url);
        const payload = try a.dupe(u8, input.payload);
        errdefer a.free(payload);
        const proxy_url = if (input.proxy_url) |value| try a.dupe(u8, value) else null;
        errdefer if (proxy_url) |value| a.free(value);
        const headers = try a.alloc(std.http.Header, input.headers.len);
        errdefer a.free(headers);
        var count: usize = 0;
        errdefer for (headers[0..count]) |header| {
            a.free(header.name);
            a.free(header.value);
        };
        for (input.headers, headers) |source, *destination| {
            const name = try a.dupe(u8, source.name);
            errdefer a.free(name);
            destination.* = .{ .name = name, .value = try a.dupe(u8, source.value) };
            count += 1;
        }
        return .{ .url = url, .payload = payload, .headers = headers, .proxy_url = proxy_url, .timeout_ms = input.timeout_ms, .method = input.method, .framing = input.framing, .stream_error_bytes = input.stream_error_bytes and input.framing == .bytes };
    }
    fn deinit(self: OwnedInput) void {
        a.free(self.url);
        a.free(self.payload);
        for (self.headers) |header| {
            a.free(header.name);
            a.free(header.value);
        }
        a.free(self.headers);
        if (self.proxy_url) |value| a.free(value);
    }
};
pub const Worker = struct {
    io: std.Io,
    input: OwnedInput,
    notify_context: ?*anyopaque,
    notify: ?*const fn (?*anyopaque) void,
    abort_flag: bool = false,
    finished: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    failure: ?anyerror = null,
    writer_failure: ?anyerror = null,
    mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    queue: [maximum_queue_items]?Event = @splat(null),
    queue_head: usize = 0,
    queue_count: usize = 0,
    queued_bytes: usize = 0,
    status: u16 = 0,
    writer: std.Io.Writer = .{ .vtable = &vtable, .buffer = &.{}, .end = 0 },
    transfer_buffer: [4096]u8 = undefined,
    line: std.ArrayList(u8) = .empty,
    data: std.ArrayList(u8) = .empty,
    event: ?[]u8 = null,
    has_data: bool = false,
    previous_cr: bool = false,
    first_line: bool = true,
    error_body: std.ArrayList(u8) = .empty,
    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = std.Io.Writer.noopFlush };
    pub fn create(io: std.Io, input: Input, notify_context: ?*anyopaque, notify: ?*const fn (?*anyopaque) void) !*Worker {
        const owned = try OwnedInput.copy(input);
        errdefer owned.deinit();
        const worker = try a.create(Worker);
        errdefer a.destroy(worker);
        worker.* = .{ .io = io, .input = owned, .notify_context = notify_context, .notify = notify };
        worker.writer.buffer = &worker.transfer_buffer;
        worker.thread = try std.Thread.spawn(.{}, run, .{worker});
        return worker;
    }
    pub fn cancel(self: *Worker) void {
        @atomicStore(bool, &self.abort_flag, true, .release);
        self.mutex.lockUncancelable(self.io);
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
    }
    pub fn destroy(self: *Worker) void {
        self.cancel();
        if (self.thread) |thread| thread.join();
        while (self.pop()) |value| value.deinit();
        self.line.deinit(a);
        self.data.deinit(a);
        self.error_body.deinit(a);
        if (self.event) |value| a.free(value);
        self.input.deinit();
        a.destroy(self);
    }
    pub fn pop(self: *Worker) ?Event {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.queue_count == 0) return null;
        const value = self.queue[self.queue_head].?;
        self.queue[self.queue_head] = null;
        self.queue_head = (self.queue_head + 1) % maximum_queue_items;
        self.queue_count -= 1;
        self.queued_bytes -= value.storageBytes();
        self.changed.broadcast(self.io);
        return value;
    }
    pub fn peek(self: *Worker) ?std.meta.Tag(Event) {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return if (self.queue_count == 0) null else std.meta.activeTag(self.queue[self.queue_head].?);
    }
    fn push(self: *Worker, value: Event) !void {
        errdefer value.deinit();
        const bytes = value.storageBytes();
        if (bytes > maximum_queue_bytes) return error.NativeHttpEventLimit;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.queue_count == maximum_queue_items or bytes > maximum_queue_bytes - self.queued_bytes) {
            if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.NativeHttpAborted;
            // The controlled fetch's timeout cancels its request task. This
            // wait must remain a cancellation point even without an owner
            // consumer to drain a full queue.
            try self.changed.wait(self.io, &self.mutex);
        }
        if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.NativeHttpAborted;
        const index = (self.queue_head + self.queue_count) % maximum_queue_items;
        self.queue[index] = value;
        self.queue_count += 1;
        self.queued_bytes += bytes;
        if (self.notify) |notify| notify(self.notify_context);
    }
    fn run(self: *Worker) void {
        self.request() catch |err| {
            self.failure = if (err == error.ProviderRequestTimeout or err == error.ProviderRequestAborted) err else self.writer_failure orelse err;
        };
        self.finished.store(true, .release);
        if (self.notify) |notify| notify(self.notify_context);
    }
    fn request(self: *Worker) !void {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        var client: std.http.Client = .{ .allocator = a, .io = self.io };
        defer client.deinit();
        _ = try proxy.configureClient(&client, arena.allocator(), self.input.url, .{ .setting = self.input.proxy_url });
        const payload: ?[]const u8 = if ((self.input.method == .GET or self.input.method == .HEAD) and self.input.payload.len == 0) null else self.input.payload;
        _ = try fetch.fetchControlledObserved(&client, .{ .location = .{ .url = self.input.url }, .method = self.input.method, .payload = payload, .extra_headers = self.input.headers, .keep_alive = false, .response_writer = &self.writer }, self.input.timeout_ms, &self.abort_flag, .{ .context = self, .callback = observeHead });
        if (self.writer.end != 0) {
            try self.feed(self.writer.buffer[0..self.writer.end]);
            self.writer.end = 0;
        }
        if ((self.status < 200 or self.status >= 300) and !self.input.stream_error_bytes) {
            const body = try self.error_body.toOwnedSlice(a);
            try self.push(.{ .error_body = body });
        } else if (self.input.framing == .body) {
            const body = try self.error_body.toOwnedSlice(a);
            try self.push(.{ .body = body });
        }
        // SSE dispatches only complete events separated by an empty line.
        // A trailing incomplete line/event is retained solely for teardown.
    }
    fn observeHead(context: ?*anyopaque, head: std.http.Client.Response.Head) !void {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        self.status = @intCast(@intFromEnum(head.status));
        var headers: std.ArrayList(Header) = .empty;
        errdefer {
            for (headers.items) |header| {
                a.free(header.name);
                a.free(header.value);
            }
            headers.deinit(a);
        }
        var iterator = head.iterateHeaders();
        while (iterator.next()) |header| {
            const name = try a.dupe(u8, header.name);
            errdefer a.free(name);
            const value = try a.dupe(u8, header.value);
            errdefer a.free(value);
            try headers.append(a, .{ .name = name, .value = value });
        }
        const status_text = try a.dupe(u8, head.reason);
        var transferred = false;
        errdefer if (!transferred) a.free(status_text);
        const owned = try headers.toOwnedSlice(a);
        // push takes complete ownership even when cancellation/backpressure
        // fails; do not run a second cleanup for its status/header buffers.
        transferred = true;
        try self.push(.{ .head = .{ .status = self.status, .status_text = status_text, .headers = owned } });
    }
    fn drain(writer: *std.Io.Writer, input: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Worker = @fieldParentPtr("writer", writer);
        var count: usize = 0;
        self.feed(writer.buffer[0..writer.end]) catch |err| {
            self.writer_failure = err;
            return error.WriteFailed;
        };
        writer.end = 0;
        if (input.len == 0) return 0;
        for (input[0 .. input.len - 1]) |bytes| {
            self.feed(bytes) catch |err| {
                self.writer_failure = err;
                return error.WriteFailed;
            };
            count += bytes.len;
        }
        const repeated = input[input.len - 1];
        for (0..splat) |_| {
            self.feed(repeated) catch |err| {
                self.writer_failure = err;
                return error.WriteFailed;
            };
            count += repeated.len;
        }
        return count;
    }
    fn feed(self: *Worker, bytes: []const u8) !void {
        if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.NativeHttpAborted;
        if (((self.status < 200 or self.status >= 300) and !self.input.stream_error_bytes) or self.input.framing == .body) {
            if (bytes.len > maximum_frame_bytes - self.error_body.items.len) return error.NativeHttpErrorBodyLimit;
            return self.error_body.appendSlice(a, bytes);
        }
        if (self.input.framing == .bytes) {
            if (bytes.len == 0) return;
            return self.push(.{ .bytes = try a.dupe(u8, bytes) });
        }
        for (bytes) |byte| {
            if (byte == '\n' and self.previous_cr) {
                self.previous_cr = false;
                continue;
            }
            self.previous_cr = byte == '\r';
            if (byte == '\r' or byte == '\n') {
                try self.handleLine();
                self.line.clearRetainingCapacity();
            } else {
                if (self.line.items.len == maximum_frame_bytes) return error.NativeHttpFrameLimit;
                try self.line.append(a, byte);
            }
        }
    }
    fn handleLine(self: *Worker) !void {
        var line = self.line.items;
        if (self.first_line) {
            self.first_line = false;
            if (std.mem.startsWith(u8, line, "\xef\xbb\xbf")) line = line[3..];
        }
        if (line.len == 0) {
            if (self.has_data) {
                try self.push(.{ .frame = try self.copyFrame() });
            }
            self.data.clearRetainingCapacity();
            self.has_data = false;
            if (self.event) |value| a.free(value);
            self.event = null;
            return;
        }
        if (line[0] == ':') return;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse line.len;
        const field = line[0..colon];
        var value: []const u8 = if (colon < line.len) line[colon + 1 ..] else &.{};
        if (value.len > 0 and value[0] == ' ') value = value[1..];
        if (std.mem.eql(u8, field, "data")) {
            const extra: usize = if (self.has_data) 1 else 0;
            if (value.len + extra > maximum_frame_bytes - self.data.items.len) return error.NativeHttpFrameLimit;
            if (self.has_data) try self.data.append(a, '\n');
            try self.data.appendSlice(a, value);
            self.has_data = true;
        } else if (std.mem.eql(u8, field, "event")) {
            const copied = try a.dupe(u8, value);
            if (self.event) |old| a.free(old);
            self.event = copied;
        }
    }
    fn copyFrame(self: *Worker) !Frame {
        const data = try a.dupe(u8, self.data.items);
        errdefer a.free(data);
        const event = if (self.event) |value| try a.dupe(u8, value) else null;
        return .{ .data = data, .event = event };
    }
};

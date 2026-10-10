//! std.http one-shot request helper that retains the selected provider retry
//! headers before the response/request backing storage is released.
const std = @import("std");
const retry = @import("retry.zig");

pub const Result = struct {
    status: u16,
    provider: retry.ProviderResponseMeta,
};

pub const HeadObserver = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, std.http.Client.Response.Head) anyerror!void,
};

/// Equivalent to `std.http.Client.fetch` for the options used by Pi's native
/// transports, with retry metadata captured from the response head.
pub fn fetchObserved(client: *std.http.Client, options: std.http.Client.FetchOptions, observer: ?HeadObserver) !Result {
    const uri = switch (options.location) {
        .url => |value| try std.Uri.parse(value),
        .uri => |value| value,
    };
    const method: std.http.Method = options.method orelse if (options.payload != null) .POST else .GET;
    const redirect_behavior: std.http.Client.Request.RedirectBehavior = options.redirect_behavior orelse
        if (options.payload == null) @enumFromInt(3) else .unhandled;

    var req = try client.request(method, uri, .{
        .redirect_behavior = redirect_behavior,
        .headers = options.headers,
        .extra_headers = options.extra_headers,
        .privileged_headers = options.privileged_headers,
        .keep_alive = options.keep_alive,
    });
    defer req.deinit();

    if (options.payload) |payload| {
        req.transfer_encoding = .{ .content_length = payload.len };
        var body = try req.sendBodyUnflushed(&.{});
        try body.writer.writeAll(payload);
        try body.end();
        try req.connection.?.flush();
    } else {
        try req.sendBodiless();
    }

    const redirect_buffer: []u8 = if (redirect_behavior == .unhandled)
        &.{}
    else
        options.redirect_buffer orelse try client.allocator.alloc(u8, 8 * 1024);
    defer if (options.redirect_buffer == null) client.allocator.free(redirect_buffer);

    var response = try req.receiveHead(redirect_buffer);
    const provider = retry.providerMetaFromHead(response.head, std.Io.Clock.real.now(client.io).toMilliseconds());
    const status: u16 = @intCast(@intFromEnum(response.head.status));
    if (observer) |value| try value.callback(value.context, response.head);

    const response_writer = options.response_writer orelse {
        const reader = response.reader(&.{});
        _ = reader.discardRemaining() catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr() orelse error.ReadFailed,
        };
        return .{ .status = status, .provider = provider };
    };

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => options.decompress_buffer orelse try client.allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => options.decompress_buffer orelse try client.allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (options.decompress_buffer == null) client.allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
    _ = reader.streamRemaining(response_writer) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr() orelse error.ReadFailed,
        else => |other| return other,
    };

    return .{ .status = status, .provider = provider };
}

pub fn fetch(client: *std.http.Client, options: std.http.Client.FetchOptions) !Result {
    return fetchObserved(client, options, null);
}

fn fetchTask(client: *std.http.Client, options: std.http.Client.FetchOptions, observer: ?HeadObserver) anyerror!Result {
    return fetchObserved(client, options, observer);
}

fn timeoutTask(io: std.Io, timeout_ms: u64) bool {
    const duration_ms: i64 = @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(duration_ms), .clock = .real } };
    timeout.sleep(io) catch return false;
    return true;
}

fn abortTask(io: std.Io, flag: *bool) bool {
    while (!@atomicLoad(bool, flag, .acquire)) {
        if (!timeoutTask(io, 25)) return false;
    }
    return true;
}

/// Run a one-shot request under the provider-level timeout and cooperative
/// abort signal. Select cancellation waits for the underlying request task to
/// release its request/connection state before the caller can destroy either
/// the client or response writer.
pub fn fetchControlledObserved(
    client: *std.http.Client,
    options: std.http.Client.FetchOptions,
    timeout_ms: ?u64,
    abort_flag: ?*bool,
    observer: ?HeadObserver,
) !Result {
    return fetchControlledScoped(client, options, timeout_ms, abort_flag, observer, false);
}

/// Mistral's request deadline ends at response headers. Caller cancellation
/// continues to cover the body, and every branch is joined before return.
pub fn fetchHeadersControlled(client: *std.http.Client, options: std.http.Client.FetchOptions, timeout_ms: ?u64, abort_flag: ?*bool) !Result {
    return fetchControlledScoped(client, options, timeout_ms, abort_flag, null, true);
}
const HeaderState = struct {
    ready: std.atomic.Value(bool) = .init(false),
    observer: ?HeadObserver,
    fn observe(raw: ?*anyopaque, head: std.http.Client.Response.Head) !void {
        const self: *HeaderState = @ptrCast(@alignCast(raw.?));
        self.ready.store(true, .release);
        if (self.observer) |observer| try observer.callback(observer.context, head);
    }
};
fn fetchControlledScoped(client: *std.http.Client, options: std.http.Client.FetchOptions, timeout_ms: ?u64, abort_flag: ?*bool, observer: ?HeadObserver, headers_only: bool) !Result {
    if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.ProviderRequestAborted;
    if (timeout_ms == null and abort_flag == null) return fetchObserved(client, options, observer);
    if (timeout_ms == 0) return error.ProviderRequestTimeout;

    const Race = union(enum) {
        request: anyerror!Result,
        timeout: bool,
        aborted: bool,
    };
    var queue: [3]Race = undefined;
    var select = std.Io.Select(Race).init(client.io, &queue);
    var header_state: HeaderState = .{ .observer = observer };
    // Cancellation joins request teardown before the caller can reuse its
    // client/writer, including if a later branch cannot obtain concurrency.
    defer while (select.cancel()) |_| {};
    const effective_observer: ?HeadObserver = if (headers_only) .{ .context = &header_state, .callback = HeaderState.observe } else observer;
    try select.concurrent(.request, fetchTask, .{ client, options, effective_observer });
    if (timeout_ms) |millis| try select.concurrent(.timeout, timeoutTask, .{ client.io, millis });
    if (abort_flag) |flag| try select.concurrent(.aborted, abortTask, .{ client.io, flag });

    while (true) {
        const winner = try select.await();
        switch (winner) {
            .request => |result| {
                return result;
            },
            .timeout => |expired| {
                if (headers_only and header_state.ready.load(.acquire)) continue;
                if (expired) return error.ProviderRequestTimeout;
                return error.Canceled;
            },
            .aborted => |aborted| {
                if (aborted) return error.ProviderRequestAborted;
                return error.Canceled;
            },
        }
    }
}

pub fn fetchControlled(
    client: *std.http.Client,
    options: std.http.Client.FetchOptions,
    timeout_ms: ?u64,
    abort_flag: ?*bool,
) !Result {
    return fetchControlledObserved(client, options, timeout_ms, abort_flag, null);
}

test "fetch captures standard provider retry headers" {
    const head = try std.http.Client.Response.Head.parse(
        "HTTP/1.1 429 Too Many Requests\r\n" ++
            "x-should-retry: true\r\n" ++
            "retry-after-ms: 1250\r\n" ++
            "content-length: 0\r\n\r\n",
    );
    const meta = retry.providerMetaFromHead(head, 0);
    try std.testing.expectEqual(@as(?u16, 429), meta.status);
    try std.testing.expectEqual(@as(?bool, true), meta.should_retry);
    try std.testing.expectEqual(@as(?u64, 1250), meta.retry_after_ms);
}

test "controlled fetch rejects immediate timeout and pre-abort before I/O" {
    var client: std.http.Client = .{ .allocator = std.testing.allocator, .io = std.testing.io };
    defer client.deinit();
    const options: std.http.Client.FetchOptions = .{ .location = .{ .url = "http://127.0.0.1:1/" } };
    try std.testing.expectError(error.ProviderRequestTimeout, fetchControlled(&client, options, 0, null));
    var aborted = true;
    try std.testing.expectError(error.ProviderRequestAborted, fetchControlled(&client, options, null, &aborted));
}

test "Mistral header deadline permits a long response body and still rejects late headers" {
    const fixture = @import("http_fixture.zig");
    const gpa = std.testing.allocator;
    var client: std.http.Client = .{ .allocator = gpa, .io = std.testing.io };
    defer client.deinit();
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{ .{ .path = "/body", .body = "long-body", .body_delay_ms = 200 }, .{ .path = "/headers", .body = "late", .delay_ms = 200 } });
    defer server.deinit();
    const url = try server.url(gpa, "/body");
    defer gpa.free(url);
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    const result = try fetchHeadersControlled(&client, .{ .location = .{ .url = url }, .response_writer = &output.writer }, 100, null);
    try std.testing.expectEqual(@as(u16, 200), result.status);
    try std.testing.expectEqualStrings("long-body", output.written());
    const late = try server.url(gpa, "/headers");
    defer gpa.free(late);
    try std.testing.expectError(error.ProviderRequestTimeout, fetchHeadersControlled(&client, .{ .location = .{ .url = late } }, 30, null));
}

test "Mistral header deadline keeps caller cancellation active while body is pending" {
    const fixture = @import("http_fixture.zig");
    const gpa = std.testing.allocator;
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{.{ .path = "/body", .body = "late-body", .body_delay_ms = 500 }});
    defer server.deinit();
    const url = try server.url(gpa, "/body");
    defer gpa.free(url);
    var client: std.http.Client = .{ .allocator = gpa, .io = std.testing.io };
    defer client.deinit();
    const Task = struct {
        client: *std.http.Client,
        url: []const u8,
        aborted: bool = false,
        result: ?anyerror = null,
        fn run(self: *@This()) std.Io.Cancelable!void {
            _ = fetchHeadersControlled(self.client, .{ .location = .{ .url = self.url } }, 100, &self.aborted) catch |cause| {
                self.result = cause;
                return;
            };
        }
    };
    var task: Task = .{ .client = &client, .url = url };
    var group: std.Io.Group = .init;
    defer group.cancel(std.testing.io);
    try group.concurrent(std.testing.io, Task.run, .{&task});
    try std.testing.io.sleep(.fromMilliseconds(200), .awake);
    @atomicStore(bool, &task.aborted, true, .release);
    try group.await(std.testing.io);
    try std.testing.expectEqual(@as(?anyerror, error.ProviderRequestAborted), task.result);
}

test "controlled fetch races real response timeout and live abort with zero eager async capacity" {
    const fixture = @import("http_fixture.zig");
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing });
    defer threaded.deinit();
    const io = threaded.io();
    var client: std.http.Client = .{ .allocator = std.testing.allocator, .io = io };
    defer client.deinit();
    const server = try fixture.PlanServer.init(std.heap.page_allocator, std.testing.io, &.{.{ .path = "/complete", .body = "response-owned", .delay_ms = 20 }});
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/complete");
    defer std.testing.allocator.free(url);
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var aborted = false;
    const result = try fetchControlled(&client, .{ .location = .{ .url = url }, .response_writer = &output.writer }, 500, &aborted);
    try std.testing.expectEqual(@as(u16, 200), result.status);
    try std.testing.expectEqualStrings("response-owned", output.written());
    try server.finish();
}

test "controlled fetch timeout cancels its real request and the client remains reusable without eager async" {
    const fixture = @import("http_fixture.zig");
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing });
    defer threaded.deinit();
    var client: std.http.Client = .{ .allocator = std.testing.allocator, .io = threaded.io() };
    defer client.deinit();
    {
        const server = try fixture.PlanServer.init(std.heap.page_allocator, std.testing.io, &.{.{ .path = "/slow", .body = "late", .delay_ms = 200 }});
        defer server.deinit();
        const url = try server.url(std.testing.allocator, "/slow");
        defer std.testing.allocator.free(url);
        try std.testing.expectError(error.ProviderRequestTimeout, fetchControlled(&client, .{ .location = .{ .url = url } }, 30, null));
    }
    const server = try fixture.PlanServer.init(std.heap.page_allocator, std.testing.io, &.{.{ .path = "/reuse", .body = "reused" }});
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/reuse");
    defer std.testing.allocator.free(url);
    try std.testing.expectEqual(@as(u16, 200), (try fetchControlled(&client, .{ .location = .{ .url = url } }, 500, null)).status);
    try server.finish();
}

test "controlled fetch resource unavailable cancels every partially started branch and releases request state" {
    const fixture = @import("http_fixture.zig");
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing, .concurrent_limit = .nothing });
    defer threaded.deinit();
    var client: std.http.Client = .{ .allocator = std.testing.allocator, .io = threaded.io() };
    defer client.deinit();
    const server = try fixture.PlanServer.init(std.heap.page_allocator, std.testing.io, &.{.{ .path = "/slow", .body = "late", .delay_ms = 200 }});
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/slow");
    defer std.testing.allocator.free(url);
    const options: std.http.Client.FetchOptions = .{ .location = .{ .url = url } };
    try std.testing.expectError(error.ConcurrencyUnavailable, fetchControlled(&client, options, 500, null));
    threaded.concurrent_limit = .limited(1);
    try std.testing.expectError(error.ConcurrencyUnavailable, fetchControlled(&client, options, 500, null));
}

test "controlled fetch live abort joins its request with zero eager async capacity" {
    const fixture = @import("http_fixture.zig");
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing });
    defer threaded.deinit();
    var client: std.http.Client = .{ .allocator = std.testing.allocator, .io = threaded.io() };
    defer client.deinit();
    var observed: std.Io.Event = .unset;
    var release: std.Io.Event = .unset;
    const server = try fixture.PlanServer.init(std.heap.page_allocator, std.testing.io, &.{.{ .path = "/slow", .body = "late", .request_observed = &observed, .response_release = &release }});
    defer server.deinit();
    const url = try server.url(std.testing.allocator, "/slow");
    defer std.testing.allocator.free(url);
    const Task = struct {
        client: *std.http.Client,
        url: []const u8,
        aborted: bool = false,
        done: std.Io.Event = .unset,
        failure: ?anyerror = null,
        fn run(self: *@This()) std.Io.Cancelable!void {
            defer self.done.set(std.testing.io);
            _ = fetchControlled(self.client, .{ .location = .{ .url = self.url } }, null, &self.aborted) catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var task: Task = .{ .client = &client, .url = url };
    var group: std.Io.Group = .init;
    defer {
        release.set(std.testing.io);
        group.cancel(std.testing.io);
    }
    try group.concurrent(std.testing.io, Task.run, .{&task});
    try observed.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(1000), .clock = .awake } });
    @atomicStore(bool, &task.aborted, true, .release);
    try task.done.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(1000), .clock = .awake } });
    try std.testing.expectEqual(@as(?anyerror, error.ProviderRequestAborted), task.failure);
}

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
            error.ReadFailed => return response.bodyErr().?,
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
        error.ReadFailed => return response.bodyErr().?,
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
    select.async(.request, fetchTask, .{ client, options, observer });
    if (timeout_ms) |millis| select.async(.timeout, timeoutTask, .{ client.io, millis });
    if (abort_flag) |flag| select.async(.aborted, abortTask, .{ client.io, flag });

    const winner = try select.await();
    switch (winner) {
        .request => |result| {
            while (select.cancel()) |_| {}
            return result;
        },
        .timeout => |expired| {
            while (select.cancel()) |_| {}
            if (expired) return error.ProviderRequestTimeout;
            return error.Canceled;
        },
        .aborted => |aborted| {
            while (select.cancel()) |_| {}
            if (aborted) return error.ProviderRequestAborted;
            return error.Canceled;
        },
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

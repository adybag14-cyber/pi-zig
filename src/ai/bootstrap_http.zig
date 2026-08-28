//! Shared bounded HTTP request path for OAuth, cloud-credential, catalog, and
//! update/bootstrap traffic.
//!
//! Model transports already consume `retry.ProviderPolicy`, response retry
//! headers, proxy selection, deadlines, and cooperative cancellation. Bootstrap
//! clients historically bypassed that policy. This module gives them the same
//! transport contract while returning an owned response body suitable for the
//! small JSON/form payloads used by authentication and discovery endpoints.
const std = @import("std");
const retry = @import("retry.zig");
const http_fetch = @import("http_fetch.zig");
const http_proxy = @import("http_proxy.zig");

pub const max_default_response_bytes: usize = 4 * 1024 * 1024;

pub const Options = struct {
    policy: retry.ProviderPolicy = .{ .max_retries = 2 },
    abort_flag: ?*bool = null,
    proxy: http_proxy.Config = .{},
    max_response_bytes: usize = max_default_response_bytes,
};

/// Preserve an explicit provider timeout while supplying an endpoint-specific
/// default for legacy OAuth/bootstrap paths that already had a deadline.
pub fn withDefaultTimeout(options: Options, timeout_ms: u64) Options {
    var out = options;
    if (out.policy.timeout_ms == null) out.policy.timeout_ms = timeout_ms;
    return out;
}

pub const Request = struct {
    url: []const u8,
    method: std.http.Method = .GET,
    payload: ?[]const u8 = null,
    headers: []const std.http.Header = &.{},
    options: Options = .{},
};

pub const Response = struct {
    status: u16,
    body: []u8,
    provider: retry.ProviderResponseMeta,
    /// Total HTTP attempts, including the successful or terminal attempt.
    attempts: usize,

    pub fn deinit(self: *Response, gpa: std.mem.Allocator) void {
        gpa.free(self.body);
        self.* = undefined;
    }
};

fn nonRetryableTransportError(err: anyerror) bool {
    return switch (err) {
        error.OutOfMemory,
        error.ProviderRequestAborted,
        error.ProviderRetryDelayExceeded,
        error.InvalidUri,
        error.UriMissingHost,
        error.UnsupportedUriScheme,
        error.UnsupportedCompressionMethod,
        error.InvalidTargetUrl,
        error.UnsupportedTargetProtocol,
        error.InvalidProxyUrl,
        error.UnsupportedProxyProtocol,
        error.ProxyHostMissing,
        error.BootstrapResponseTooLarge,
        => true,
        else => false,
    };
}

/// Transport errors without a response status are retryable by the original
/// provider policy unless they are deterministic configuration/allocation or
/// explicit cancellation failures. Known transient names continue to use the
/// shared classifier; unknown I/O failures are treated as transient because no
/// HTTP response was produced and the retry budget is strictly bounded.
pub fn isRetryableTransportError(err: anyerror) bool {
    if (nonRetryableTransportError(err)) return false;
    if (err == error.ProviderRequestTimeout) return true;
    if (retry.isRetryableError(@errorName(err))) return true;
    return true;
}

fn waitBeforeRetry(io: std.Io, policy: retry.ProviderPolicy, retry_index: usize, server_delay_ms: ?u64, abort_flag: ?*bool) !void {
    const delay_ms = try retry.providerDelayMs(io, policy, retry_index, server_delay_ms);
    if (!retry.waitProvider(io, delay_ms, abort_flag)) return error.ProviderRequestAborted;
}

/// Execute one small bootstrap request with provider retry headers, bounded
/// retry delays, per-request timeout, cooperative abort, and target-aware proxy
/// selection. The response body is owned by the caller.
pub fn request(gpa: std.mem.Allocator, io: std.Io, options: Request) !Response {
    var retry_index: usize = 0;
    while (true) {
        if (options.options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.ProviderRequestAborted;

        const response_capacity = std.math.add(usize, options.options.max_response_bytes, 1) catch return error.BootstrapResponseTooLarge;
        const response_buffer = try gpa.alloc(u8, response_capacity);
        defer gpa.free(response_buffer);
        var response_writer = std.Io.Writer.fixed(response_buffer);

        var proxy_arena_state = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena_state.deinit();
        var client: std.http.Client = .{ .allocator = gpa, .io = io };
        defer client.deinit();
        _ = try http_proxy.configureClient(&client, proxy_arena_state.allocator(), options.url, options.options.proxy);

        const result = http_fetch.fetchControlled(&client, .{
            .location = .{ .url = options.url },
            .method = options.method,
            .payload = options.payload,
            .keep_alive = false,
            .extra_headers = options.headers,
            .response_writer = &response_writer,
        }, options.options.policy.timeout_ms, options.options.abort_flag) catch |err| {
            if (err == error.WriteFailed) return error.BootstrapResponseTooLarge;
            if (retry_index >= options.options.policy.max_retries or !isRetryableTransportError(err)) return err;
            try waitBeforeRetry(io, options.options.policy, retry_index, null, options.options.abort_flag);
            retry_index += 1;
            continue;
        };

        const written = response_writer.buffered();
        if (written.len > options.options.max_response_bytes) {
            return error.BootstrapResponseTooLarge;
        }
        const body = try gpa.dupe(u8, written);

        if (retry_index < options.options.policy.max_retries and retry.isRetryableProviderResponse(result.provider)) {
            gpa.free(body);
            try waitBeforeRetry(io, options.options.policy, retry_index, result.provider.retry_after_ms, options.options.abort_flag);
            retry_index += 1;
            continue;
        }

        return .{
            .status = result.status,
            .body = body,
            .provider = result.provider,
            .attempts = retry_index + 1,
        };
    }
}

test "bootstrap transport errors preserve cancellation and retry timeouts" {
    try std.testing.expect(!isRetryableTransportError(error.ProviderRequestAborted));
    try std.testing.expect(!isRetryableTransportError(error.OutOfMemory));
    try std.testing.expect(isRetryableTransportError(error.ProviderRequestTimeout));
    try std.testing.expect(isRetryableTransportError(error.ConnectionResetByPeer));
    try std.testing.expect(isRetryableTransportError(error.ConnectionRefused));
}

test "bootstrap response policy obeys explicit provider overrides" {
    try std.testing.expect(retry.isRetryableProviderResponse(.{ .status = 400, .should_retry = true }));
    try std.testing.expect(!retry.isRetryableProviderResponse(.{ .status = 503, .should_retry = false }));
    try std.testing.expect(retry.isRetryableProviderResponse(.{ .status = 429, .retry_after_ms = 0 }));
}

test "bootstrap request rejects pre-abort without opening a socket" {
    var flag = true;
    try std.testing.expectError(error.ProviderRequestAborted, request(std.testing.allocator, std.testing.io, .{
        .url = "http://127.0.0.1:1/token",
        .options = .{ .abort_flag = &flag },
    }));
}

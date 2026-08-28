//! Shared retry classification and bounded exponential backoff.
//!
//! Mirrors Pi's TypeScript retry policy: quota/billing failures fail fast,
//! transient provider/transport failures retry with `base * 2^(attempt-1)`,
//! and either the whole agent run or only the pending retry sleep can abort.
const std = @import("std");
const Io = std.Io;

pub const Policy = struct {
    enabled: bool = true,
    /// Number of retries after the initial request.
    max_retries: usize = 3,
    base_delay_ms: u64 = 2_000,
};

/// Provider-internal request retry policy. This is deliberately separate from
/// the outer assistant-turn policy above: a provider retry repeats the same
/// HTTP request before an assistant attempt is published to durable history.
pub const ProviderPolicy = struct {
    /// Request timeout is retained here so every transport consumes one
    /// settings contract. Individual transports apply it where their I/O path
    /// supports a deadline.
    timeout_ms: ?u64 = null,
    /// Number of provider request retries after the initial request.
    max_retries: usize = 0,
    /// Maximum server-requested delay. Zero disables the cap.
    max_retry_delay_ms: u64 = 60_000,
};

/// Selected response metadata used by the shared provider retry policy.
pub const ProviderResponseMeta = struct {
    status: ?u16 = null,
    retry_after_ms: ?u64 = null,
    /// `x-should-retry` overrides status-based classification when present.
    should_retry: ?bool = null,
};

fn monthNumber(mon: []const u8) ?u8 {
    const names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    for (names, 1..) |name, index| {
        if (std.ascii.eqlIgnoreCase(mon, name)) return @intCast(index);
    }
    return null;
}

fn daysFromCivil(year_in: i64, month: u8, day: u8) i64 {
    var year = year_in;
    if (month <= 2) year -= 1;
    const era = @divFloor(year, 400);
    const yoe = year - era * 400;
    const mp: i64 = @as(i64, month) + (if (month > 2) @as(i64, -3) else @as(i64, 9));
    const doy = @divFloor(153 * mp + 2, 5) + @as(i64, day) - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

fn parseHttpDateMs(value: []const u8) ?i64 {
    // IMF-fixdate: Sun, 06 Nov 1994 08:49:37 GMT
    const text = std.mem.trim(u8, value, " \t\r\n");
    if (text.len != 29 or text[3] != ',' or text[4] != ' ' or text[7] != ' ' or text[11] != ' ' or
        text[16] != ' ' or text[19] != ':' or text[22] != ':' or text[25] != ' ' or
        !std.ascii.eqlIgnoreCase(text[26..29], "GMT")) return null;
    const day = std.fmt.parseInt(u8, text[5..7], 10) catch return null;
    const month = monthNumber(text[8..11]) orelse return null;
    const year = std.fmt.parseInt(i64, text[12..16], 10) catch return null;
    const hour = std.fmt.parseInt(u8, text[17..19], 10) catch return null;
    const minute = std.fmt.parseInt(u8, text[20..22], 10) catch return null;
    const second = std.fmt.parseInt(u8, text[23..25], 10) catch return null;
    if (day == 0 or day > 31 or hour > 23 or minute > 59 or second > 60) return null;
    const days = daysFromCivil(year, month, day);
    return (days * 86_400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second)) * 1000;
}

fn nonNegativeFloatToU64(value: f64) ?u64 {
    if (!std.math.isFinite(value)) return null;
    if (value <= 0) return 0;
    const max_value: f64 = @floatFromInt(std.math.maxInt(u64));
    if (value >= max_value) return std.math.maxInt(u64);
    return @intFromFloat(value);
}

/// Extract the response headers used by the provider retry contract. Header
/// parsing happens while the std.http response owns the backing bytes.
pub fn providerMetaFromHead(head: std.http.Client.Response.Head, now_ms: i64) ProviderResponseMeta {
    var meta: ProviderResponseMeta = .{ .status = @intCast(@intFromEnum(head.status)) };
    var retry_after_ms: ?[]const u8 = null;
    var retry_after: ?[]const u8 = null;
    var it = head.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "x-should-retry")) {
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, header.value, " \t"), "true")) meta.should_retry = true else if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, header.value, " \t"), "false")) meta.should_retry = false;
        } else if (std.ascii.eqlIgnoreCase(header.name, "retry-after-ms")) {
            retry_after_ms = header.value;
        } else if (std.ascii.eqlIgnoreCase(header.name, "retry-after")) {
            retry_after = header.value;
        }
    }
    if (retry_after_ms) |raw| {
        if (std.fmt.parseFloat(f64, std.mem.trim(u8, raw, " \t"))) |millis| {
            if (nonNegativeFloatToU64(millis)) |value| {
                meta.retry_after_ms = value;
                return meta;
            }
        } else |_| {}
        // A malformed retry-after-ms does not mask a valid retry-after value.
    }
    if (retry_after) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t");
        if (std.fmt.parseFloat(f64, trimmed)) |seconds| {
            if (nonNegativeFloatToU64(seconds * 1000.0)) |value| meta.retry_after_ms = value;
        } else |_| {
            if (parseHttpDateMs(trimmed)) |at_ms| meta.retry_after_ms = @intCast(@max(0, at_ms - now_ms));
        }
    }
    return meta;
}

/// Mirrors the pinned OpenAI/Anthropic SDK policy. An explicit provider header
/// wins; transport errors have no status and are retryable; otherwise 408,
/// 409, 429 and 5xx responses are retryable.
pub fn isRetryableProviderResponse(meta: ProviderResponseMeta) bool {
    if (meta.should_retry) |value| return value;
    const status = meta.status orelse return true;
    return status == 408 or status == 409 or status == 429 or status >= 500;
}

/// Deterministic core used by tests. `jitter_permille` is clamped to the
/// upstream 75%-100% backoff range.
pub fn providerDelayMsWithJitter(policy: ProviderPolicy, retry_index: usize, server_delay_ms: ?u64, jitter_permille_in: u16) !u64 {
    if (server_delay_ms) |delay| {
        if (policy.max_retry_delay_ms > 0 and delay > policy.max_retry_delay_ms) return error.ProviderRetryDelayExceeded;
        return delay;
    }
    var capped: u64 = 500;
    var remaining = retry_index;
    while (remaining > 0 and capped < 8_000) : (remaining -= 1) {
        capped = @min(capped * 2, 8_000);
    }
    const jitter_permille: u64 = @max(@as(u16, 750), @min(@as(u16, 1000), jitter_permille_in));
    const multiplied = std.math.mul(u64, capped, jitter_permille) catch std.math.maxInt(u64);
    return multiplied / 1000;
}

pub fn providerDelayMs(io: Io, policy: ProviderPolicy, retry_index: usize, server_delay_ms: ?u64) !u64 {
    const seed: u64 = @bitCast(Io.Clock.real.now(io).toMilliseconds());
    var prng = std.Random.DefaultPrng.init(seed ^ @as(u64, @intCast(retry_index)) *% 0x9e3779b97f4a7c15);
    const jitter = prng.random().intRangeAtMost(u16, 750, 1000);
    return providerDelayMsWithJitter(policy, retry_index, server_delay_ms, jitter);
}

pub fn waitProvider(io: Io, delay_ms: u64, abort_flag: ?*bool) bool {
    return wait(io, delay_ms, abort_flag, null);
}

const non_retryable_patterns = [_][]const u8{
    "gousagelimiterror",
    "freeusagelimiterror",
    "monthly usage limit reached",
    "available balance",
    "insufficient_quota",
    "out of budget",
    "quota exceeded",
    "free-models-per-day",
    "free model daily limit",
    "billing",
};

const retryable_patterns = [_][]const u8{
    "overloaded",
    "rate limit",
    "rate-limit",
    "ratelimit",
    "too many requests",
    "429",
    "500",
    "502",
    "503",
    "504",
    "524",
    "service unavailable",
    "service-unavailable",
    "server error",
    "server-error",
    "internal error",
    "internal-error",
    "provider returned error",
    "provider-returned-error",
    "exceeded request buffer limit while retrying upstream",
    "network error",
    "network-error",
    "connection error",
    "connection-error",
    "connection refused",
    "connection reset by peer",
    "connection lost",
    "network unreachable",
    "temporary name server failure",
    "tls connection truncated",
    "broken pipe",
    "other side closed",
    "fetch failed",
    "getaddrinfo",
    "enotfound",
    "eai_again",
    "upstream connect",
    "reset before headers",
    "socket hang up",
    "socket connection was closed",
    "timed out",
    "timeout",
    "terminated",
    "websocket closed",
    "websocket error",
    "ended without",
    "stream ended before message_stop",
    "stream ended before a terminal response event",
    "http2 request did not get a response",
    "retry delay",
    "you can retry your request",
    "try your request again",
    "please retry your request",
    "resourceexhausted",
};

fn isWordByte(value: u8) bool {
    return std.ascii.isAlphanumeric(value) or value == '_';
}

/// Case-insensitive containment that ignores punctuation and whitespace. This
/// lets human provider text (`connection refused`) and Zig error names
/// (`ConnectionRefused`) share one classifier without allocating a normalized
/// copy on every failure.
fn containsAsciiFold(haystack: []const u8, needle: []const u8) bool {
    var needle_words: usize = 0;
    for (needle) |value| needle_words += @intFromBool(isWordByte(value));
    if (needle_words == 0) return true;

    var start: usize = 0;
    while (start < haystack.len) : (start += 1) {
        if (!isWordByte(haystack[start])) continue;
        var hay_index = start;
        var needle_index: usize = 0;
        var matched: usize = 0;
        while (needle_index < needle.len) {
            while (needle_index < needle.len and !isWordByte(needle[needle_index])) needle_index += 1;
            if (needle_index == needle.len) break;
            while (hay_index < haystack.len and !isWordByte(haystack[hay_index])) hay_index += 1;
            if (hay_index == haystack.len or std.ascii.toLower(haystack[hay_index]) != std.ascii.toLower(needle[needle_index])) break;
            hay_index += 1;
            needle_index += 1;
            matched += 1;
        }
        while (needle_index < needle.len and !isWordByte(needle[needle_index])) needle_index += 1;
        if (needle_index == needle.len and matched == needle_words) return true;
    }
    return false;
}

pub fn isRetryableError(error_message: []const u8) bool {
    if (error_message.len == 0) return false;
    for (non_retryable_patterns) |pattern| {
        if (containsAsciiFold(error_message, pattern)) return false;
    }
    for (retryable_patterns) |pattern| {
        if (containsAsciiFold(error_message, pattern)) return true;
    }
    return false;
}

/// One-indexed retry delay. Attempt 1 returns `base_delay_ms`.
pub fn delayMs(base_delay_ms: u64, attempt: usize) u64 {
    if (attempt <= 1 or base_delay_ms == 0) return base_delay_ms;
    var result = base_delay_ms;
    var index: usize = 1;
    while (index < attempt) : (index += 1) {
        result = std.math.mul(u64, result, 2) catch return std.math.maxInt(u64);
    }
    return result;
}

pub fn isAbortRequested(abort_flag: ?*bool, retry_abort_flag: ?*bool) bool {
    if (abort_flag) |flag| {
        if (@atomicLoad(bool, flag, .acquire)) return true;
    }
    if (retry_abort_flag) |flag| {
        if (@atomicLoad(bool, flag, .acquire)) return true;
    }
    return false;
}

/// Sleep in short bounded slices so RPC `abort_retry` and whole-run aborts are
/// observed promptly. Returns false when cancellation wins.
pub fn wait(io: Io, delay_ms: u64, abort_flag: ?*bool, retry_abort_flag: ?*bool) bool {
    if (isAbortRequested(abort_flag, retry_abort_flag)) return false;
    var remaining = delay_ms;
    while (remaining > 0) {
        const slice_ms = @min(remaining, 25);
        const timeout: Io.Timeout = .{ .duration = .{
            .raw = .fromMilliseconds(@intCast(slice_ms)),
            .clock = .real,
        } };
        timeout.sleep(io) catch return false;
        if (isAbortRequested(abort_flag, retry_abort_flag)) return false;
        remaining -= slice_ms;
    }
    return !isAbortRequested(abort_flag, retry_abort_flag);
}

test "provider retry metadata honors headers status and date forms" {
    const overridden = try std.http.Client.Response.Head.parse(
        "HTTP/1.1 400 Bad Request\r\n" ++
            "x-should-retry: true\r\n" ++
            "retry-after-ms: malformed\r\n" ++
            "retry-after: 2.5\r\n" ++
            "content-length: 0\r\n\r\n",
    );
    const meta = providerMetaFromHead(overridden, 0);
    try std.testing.expectEqual(@as(?u16, 400), meta.status);
    try std.testing.expectEqual(@as(?bool, true), meta.should_retry);
    try std.testing.expectEqual(@as(?u64, 2_500), meta.retry_after_ms);
    try std.testing.expect(isRetryableProviderResponse(meta));

    const denied = try std.http.Client.Response.Head.parse(
        "HTTP/1.1 503 Service Unavailable\r\n" ++
            "x-should-retry: false\r\n" ++
            "content-length: 0\r\n\r\n",
    );
    try std.testing.expect(!isRetryableProviderResponse(providerMetaFromHead(denied, 0)));

    const date = try std.http.Client.Response.Head.parse(
        "HTTP/1.1 429 Too Many Requests\r\n" ++
            "retry-after: Wed, 13 May 2026 00:00:45 GMT\r\n" ++
            "content-length: 0\r\n\r\n",
    );
    const now = parseHttpDateMs("Wed, 13 May 2026 00:00:00 GMT").?;
    try std.testing.expectEqual(@as(?u64, 45_000), providerMetaFromHead(date, now).retry_after_ms);

    const huge = try std.http.Client.Response.Head.parse(
        "HTTP/1.1 429 Too Many Requests\r\n" ++
            "retry-after-ms: 999999999999999999999999999999\r\n" ++
            "content-length: 0\r\n\r\n",
    );
    try std.testing.expectEqual(@as(?u64, std.math.maxInt(u64)), providerMetaFromHead(huge, now).retry_after_ms);
}

test "provider retry delay caps server requests and bounds exponential jitter" {
    const policy: ProviderPolicy = .{ .max_retries = 2, .max_retry_delay_ms = 1_000 };
    try std.testing.expectEqual(@as(u64, 999), try providerDelayMsWithJitter(policy, 0, 999, 1000));
    try std.testing.expectError(error.ProviderRetryDelayExceeded, providerDelayMsWithJitter(policy, 0, 1_001, 1000));
    try std.testing.expectEqual(@as(u64, 375), try providerDelayMsWithJitter(policy, 0, null, 750));
    try std.testing.expectEqual(@as(u64, 500), try providerDelayMsWithJitter(policy, 0, null, 1000));
    try std.testing.expectEqual(@as(u64, 6_000), try providerDelayMsWithJitter(policy, 20, null, 750));
    try std.testing.expectEqual(@as(u64, 8_000), try providerDelayMsWithJitter(policy, 20, null, 1000));
    try std.testing.expectEqual(@as(u64, 90_000), try providerDelayMsWithJitter(.{ .max_retry_delay_ms = 0 }, 0, 90_000, 1000));
}

test "provider retry defaults match upstream request policy" {
    const transient = ProviderResponseMeta{ .status = 408 };
    try std.testing.expect(isRetryableProviderResponse(transient));
    try std.testing.expect(isRetryableProviderResponse(.{ .status = 409 }));
    try std.testing.expect(isRetryableProviderResponse(.{ .status = 429 }));
    try std.testing.expect(isRetryableProviderResponse(.{ .status = 500 }));
    try std.testing.expect(isRetryableProviderResponse(.{}));
    try std.testing.expect(!isRetryableProviderResponse(.{ .status = 400 }));
    _ = try providerDelayMs(std.testing.io, .{}, 0, null);
}

test "retry classifier accepts transient provider and transport failures" {
    inline for (.{
        "529 overloaded_error: Overloaded",
        "HTTP 429 too many requests",
        "Provider returned error",
        "fetch failed: getaddrinfo ENOTFOUND api.example.test",
        "WebSocket closed before a terminal response event",
        "ResourceExhausted",
        "You can retry your request",
        "ConnectionResetByPeer",
        "TemporaryNameServerFailure",
    }) |message| {
        try std.testing.expect(isRetryableError(message));
    }
}

test "retry classifier rejects quota billing and deterministic failures" {
    inline for (.{
        "insufficient_quota",
        "Monthly usage limit reached; enable available balance",
        "quota exceeded",
        "HTTP 429: Rate limit exceeded: free-models-per-day. Wait for the daily reset or purchase credits to raise your free model daily limit.",
        "billing account disabled",
        "invalid request body",
        "authentication failed",
        "",
    }) |message| {
        try std.testing.expect(!isRetryableError(message));
    }
}

test "retry delay uses saturating exponential backoff" {
    try std.testing.expectEqual(@as(u64, 2_000), delayMs(2_000, 1));
    try std.testing.expectEqual(@as(u64, 4_000), delayMs(2_000, 2));
    try std.testing.expectEqual(@as(u64, 8_000), delayMs(2_000, 3));
    try std.testing.expectEqual(std.math.maxInt(u64), delayMs(std.math.maxInt(u64), 2));
}

test "retry wait observes a retry-only cancellation" {
    var abort_retry = true;
    try std.testing.expect(!wait(std.testing.io, 0, null, &abort_retry));
    @atomicStore(bool, &abort_retry, false, .release);
    try std.testing.expect(wait(std.testing.io, 0, null, &abort_retry));
}

//! OpenAI Responses API transport.
//! Native implementation of the core upstream semantics used by coding-agent:
//! Responses-style input replay, function calls/results, tools, reasoning,
//! streaming output events, usage accounting, cancellation, and custom headers.
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");
const retry_mod = @import("retry.zig");
const ai = @import("root.zig");
const context_estimate = @import("context_estimate.zig");
const transcript_repair = @import("transcript_repair.zig");
const metadata = @import("request_metadata.zig");
const providers = @import("providers.zig");
const cost_mod = @import("cost.zig");
const cloudflare = @import("cloudflare.zig");
const copilot = @import("github_copilot.zig");
const constrained = @import("constrained_sampling.zig");
const thinking_mod = @import("thinking.zig");
const codex_ws = @import("codex_websocket.zig");

const MIN_OUTPUT_TOKENS: u64 = 16;
const CODEX_BASE_RETRY_DELAY_MS: i64 = 1000;
const CODEX_MAX_RETRY_DELAY_MS: i64 = 60_000;
pub const DEFAULT_HTTP_IDLE_TIMEOUT_MS: u64 = 300_000;
pub const DEFAULT_WEBSOCKET_CONNECT_TIMEOUT_MS: u64 = codex_ws.DEFAULT_CONNECT_TIMEOUT_MS;

const HttpPostResult = struct {
    status: u16,
    provider: retry_mod.ProviderResponseMeta,
};

/// Encode a standards-valid Zstandard frame without depending on libzstd.
/// Raw blocks are used generally; uniform blocks use Zstd's RLE block form.
/// This is deliberately tiny/portable: the Codex backend only requires a
/// decodable `Content-Encoding: zstd` request body, while a future encoder can
/// replace the block strategy without changing the HTTP path.
fn encodeZstdRequestBody(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    // Zstandard frame magic, little endian: 0xFD2FB528.
    try out.appendSlice(gpa, &.{ 0x28, 0xB5, 0x2F, 0xFD });

    // Single-segment frames carry the uncompressed content size directly.
    if (input.len <= 0xff) {
        try out.append(gpa, 0x20); // single segment, 1-byte content size
        try out.append(gpa, @intCast(input.len));
    } else if (input.len <= 0xffff + 256) {
        try out.append(gpa, 0x60); // single segment, 2-byte content size (+256)
        const encoded: u16 = @intCast(input.len - 256);
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, encoded, .little);
        try out.appendSlice(gpa, &buf);
    } else if (input.len <= std.math.maxInt(u32)) {
        try out.append(gpa, 0xA0); // single segment, 4-byte content size
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, @intCast(input.len), .little);
        try out.appendSlice(gpa, &buf);
    } else {
        try out.append(gpa, 0xE0); // single segment, 8-byte content size
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, @intCast(input.len), .little);
        try out.appendSlice(gpa, &buf);
    }

    if (input.len == 0) {
        // Last raw block, zero bytes.
        try out.appendSlice(gpa, &.{ 0x01, 0x00, 0x00 });
        return out.toOwnedSlice(gpa);
    }

    var pos: usize = 0;
    while (pos < input.len) {
        const block_len = @min(input.len - pos, std.compress.zstd.block_size_max);
        const block = input[pos .. pos + block_len];
        const last = pos + block_len == input.len;

        var rle = block.len > 1;
        if (rle) {
            const first = block[0];
            for (block[1..]) |byte| {
                if (byte != first) {
                    rle = false;
                    break;
                }
            }
        }

        // Zstd block header: last:1, type:2, size:21, little endian u24.
        const block_type: u32 = if (rle) 1 else 0;
        const header: u32 = (@as(u32, @intCast(block_len)) << 3) | (block_type << 1) | @as(u32, @intFromBool(last));
        try out.append(gpa, @truncate(header));
        try out.append(gpa, @truncate(header >> 8));
        try out.append(gpa, @truncate(header >> 16));
        if (rle) {
            try out.append(gpa, block[0]);
        } else {
            try out.appendSlice(gpa, block);
        }
        pos += block_len;
    }

    return out.toOwnedSlice(gpa);
}

fn monthNumber(mon: []const u8) ?u8 {
    const names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    for (names, 1..) |name, idx| if (std.ascii.eqlIgnoreCase(mon, name)) return @intCast(idx);
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

fn retryAfterMsFromHead(head: std.http.Client.Response.Head, now_ms: i64) ?i64 {
    var retry_after_ms: ?[]const u8 = null;
    var retry_after: ?[]const u8 = null;
    var it = head.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "retry-after-ms")) retry_after_ms = header.value else if (std.ascii.eqlIgnoreCase(header.name, "retry-after")) retry_after = header.value;
    }
    if (retry_after_ms) |raw| {
        const millis = std.fmt.parseFloat(f64, std.mem.trim(u8, raw, " \t")) catch return null;
        if (!std.math.isFinite(millis)) return null;
        return @intFromFloat(@max(0.0, millis));
    }
    if (retry_after) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t");
        if (std.fmt.parseFloat(f64, trimmed)) |seconds| {
            if (!std.math.isFinite(seconds)) return null;
            return @intFromFloat(@max(0.0, seconds * 1000.0));
        } else |_| {}
        if (parseHttpDateMs(trimmed)) |at_ms| return @max(0, at_ms - now_ms);
    }
    return null;
}

fn isTerminalCodexRateLimit(body: []const u8) bool {
    const needles = [_][]const u8{ "GoUsageLimitError", "FreeUsageLimitError", "Monthly usage limit reached", "available balance", "insufficient_quota", "out of budget", "quota exceeded", "billing" };
    for (needles) |needle| if (std.ascii.indexOfIgnoreCase(body, needle) != null) return true;
    return false;
}

fn isRetryableHttp(meta: retry_mod.ProviderResponseMeta, body: []const u8, codex: bool) bool {
    if (meta.should_retry != null) return retry_mod.isRetryableProviderResponse(meta);
    if (codex and meta.status == 429 and isTerminalCodexRateLimit(body)) return false;
    if (retry_mod.isRetryableProviderResponse(meta)) return true;
    return std.ascii.indexOfIgnoreCase(body, "rate limit") != null or
        std.ascii.indexOfIgnoreCase(body, "rate-limit") != null or
        std.ascii.indexOfIgnoreCase(body, "overloaded") != null or
        std.ascii.indexOfIgnoreCase(body, "service unavailable") != null or
        std.ascii.indexOfIgnoreCase(body, "upstream connect") != null or
        std.ascii.indexOfIgnoreCase(body, "connection refused") != null;
}

fn sleepMs(io: Io, timeout_ms: u64) bool {
    const duration_ms: i64 = @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const timeout: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(duration_ms), .clock = .real } };
    timeout.sleep(io) catch return false;
    return true;
}

fn watchAbort(io: Io, flag: *bool) bool {
    while (!@atomicLoad(bool, flag, .acquire)) {
        if (!sleepMs(io, 25)) return false;
    }
    return true;
}

fn receiveHeadTask(req: *std.http.Client.Request) anyerror!std.http.Client.Response {
    return req.receiveHead(&.{});
}

fn receiveHeadWithControl(
    req: *std.http.Client.Request,
    io: Io,
    timeout_ms: u64,
    abort_flag: ?*bool,
) !std.http.Client.Response {
    if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.CodexHttpAborted;
    if (timeout_ms == 0 and abort_flag == null) return req.receiveHead(&.{});

    const Race = union(enum) { head: anyerror!std.http.Client.Response, timeout: bool, aborted: bool };
    var queue: [3]Race = undefined;
    var select = Io.Select(Race).init(io, &queue);
    select.async(.head, receiveHeadTask, .{req});
    if (timeout_ms > 0) select.async(.timeout, sleepMs, .{ io, timeout_ms });
    if (abort_flag) |flag| select.async(.aborted, watchAbort, .{ io, flag });

    const winner = try select.await();
    switch (winner) {
        .head => |result| {
            while (select.cancel()) |_| {}
            return result;
        },
        .timeout => |expired| {
            while (select.cancel()) |_| {}
            if (expired) return error.CodexResponseHeaderIdleTimeout;
            return error.Canceled;
        },
        .aborted => |aborted| {
            while (select.cancel()) |_| {}
            if (aborted) return error.CodexHttpAborted;
            return error.Canceled;
        },
    }
}

fn readSomeTask(reader: *std.Io.Reader, buffer: []u8) anyerror!usize {
    return readAvailable(reader, buffer);
}

/// Read at least one byte from an open stream and then return all bytes that
/// are currently buffered. `readSliceShort` waits to fill the destination and
/// can therefore deadlock low-volume SSE/WebSocket upgrade traffic.
fn readAvailable(reader: *std.Io.Reader, buffer: []u8) !usize {
    if (buffer.len == 0) return 0;
    const available = reader.peekGreedy(1) catch |err| switch (err) {
        error.EndOfStream => return 0,
        else => return err,
    };
    const count = @min(buffer.len, available.len);
    @memcpy(buffer[0..count], available[0..count]);
    reader.toss(count);
    return count;
}

fn readSomeWithControl(
    reader: *std.Io.Reader,
    io: Io,
    buffer: []u8,
    timeout_ms: u64,
    abort_flag: ?*bool,
) !usize {
    if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.CodexHttpAborted;
    if (timeout_ms == 0 and abort_flag == null) return readAvailable(reader, buffer);

    const Race = union(enum) { read: anyerror!usize, timeout: bool, aborted: bool };
    var queue: [3]Race = undefined;
    var select = Io.Select(Race).init(io, &queue);
    select.async(.read, readSomeTask, .{ reader, buffer });
    if (timeout_ms > 0) select.async(.timeout, sleepMs, .{ io, timeout_ms });
    if (abort_flag) |flag| select.async(.aborted, watchAbort, .{ io, flag });

    const winner = try select.await();
    switch (winner) {
        .read => |result| {
            while (select.cancel()) |_| {}
            return result;
        },
        .timeout => |expired| {
            while (select.cancel()) |_| {}
            if (expired) return error.CodexResponseBodyIdleTimeout;
            return error.Canceled;
        },
        .aborted => |aborted| {
            while (select.cancel()) |_| {}
            if (aborted) return error.CodexHttpAborted;
            return error.Canceled;
        },
    }
}

fn streamResponseWithControl(
    response: *std.http.Client.Response,
    gpa: std.mem.Allocator,
    io: Io,
    response_writer: *std.Io.Writer,
    timeout_ms: u64,
    abort_flag: ?*bool,
    terminal_live: ?*ResponsesLive,
) !void {
    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try gpa.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try gpa.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (decompress_buffer.len > 0) gpa.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
    var chunk: [8192]u8 = undefined;
    while (true) {
        if (terminal_live) |live| if (live.terminal) return;
        const n = readSomeWithControl(reader, io, &chunk, timeout_ms, abort_flag) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr() orelse error.ReadFailed,
            else => |e| return e,
        };
        if (n == 0) return;
        try response_writer.writeAll(chunk[0..n]);
        // Force the ResponsesLive writer's backing buffer through the parser so
        // a terminal event smaller than the 4KiB writer buffer is visible now,
        // rather than only after another network read or EOF.
        if (terminal_live) |live| {
            try live.flushWriterBuffer();
            // The parser owns terminal recognition; only stop after it has parsed
            // a complete terminal JSON event, never from raw substring matching.
            if (live.terminal) return;
        }
    }
}

fn postHttpCaptureRetry(
    client: *std.http.Client,
    gpa: std.mem.Allocator,
    io: Io,
    url: []const u8,
    payload: []const u8,
    headers: []const std.http.Header,
    response_writer: *std.Io.Writer,
    idle_timeout_ms: u64,
    abort_flag: ?*bool,
    terminal_live: ?*ResponsesLive,
) !HttpPostResult {
    const uri = try std.Uri.parse(url);
    var req = try client.request(.POST, uri, .{
        .redirect_behavior = .unhandled,
        .keep_alive = false,
        .extra_headers = headers,
    });
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = payload.len };
    var body = try req.sendBodyUnflushed(&.{});
    try body.writer.writeAll(payload);
    try body.end();
    try req.connection.?.flush();

    var response = try receiveHeadWithControl(&req, io, idle_timeout_ms, abort_flag);
    const provider = retry_mod.providerMetaFromHead(response.head, Io.Clock.real.now(io).toMilliseconds());
    const status = provider.status.?;
    try streamResponseWithControl(&response, gpa, io, response_writer, idle_timeout_ms, abort_flag, terminal_live);
    return .{ .status = status, .provider = provider };
}

fn retryDelayMs(policy: retry_mod.ProviderPolicy, attempt: usize, server_delay: ?u64) !u64 {
    if (server_delay) |delay| {
        if (policy.max_retry_delay_ms > 0 and delay > policy.max_retry_delay_ms) return error.ProviderRetryDelayExceeded;
        return delay;
    }
    var delay: u64 = @intCast(CODEX_BASE_RETRY_DELAY_MS);
    var remaining = attempt;
    while (remaining > 0 and delay < 8_000) : (remaining -= 1) delay = @min(delay * 2, 8_000);
    return delay;
}

pub const AuthMode = enum { bearer, azure_api_key };
pub const ProtocolMode = enum { standard, azure, codex };

const ServiceTier = enum { unknown, default, flex, priority };

fn serviceTierFromString(value: []const u8) ServiceTier {
    if (std.ascii.eqlIgnoreCase(value, "default")) return .default;
    if (std.ascii.eqlIgnoreCase(value, "flex")) return .flex;
    if (std.ascii.eqlIgnoreCase(value, "priority")) return .priority;
    return .unknown;
}

fn requestedServiceTier(params: []const metadata.SamplingParam) ServiceTier {
    for (params) |param| {
        if (!std.mem.eql(u8, param.name, "service_tier")) continue;
        const raw = std.mem.trim(u8, param.value_json, " \t\r\n");
        if (raw.len >= 2 and raw[0] == '\"' and raw[raw.len - 1] == '\"') return serviceTierFromString(raw[1 .. raw.len - 1]);
        return .unknown;
    }
    return .unknown;
}

fn effectiveServiceTier(mode: ProtocolMode, response_tier: ServiceTier, request_tier: ServiceTier) ServiceTier {
    if (mode == .codex and response_tier == .default and (request_tier == .flex or request_tier == .priority)) return request_tier;
    return if (response_tier != .unknown) response_tier else request_tier;
}

fn applyServiceTierCost(model: []const u8, tier: ServiceTier, usage: *ai.Usage) void {
    const multiplier: f64 = switch (tier) {
        .flex => 0.5,
        .priority => if (std.mem.eql(u8, model, "gpt-5.5")) 2.5 else 2.0,
        else => 1.0,
    };
    if (multiplier == 1.0) return;
    usage.cost.input *= multiplier;
    usage.cost.output *= multiplier;
    usage.cost.cache_read *= multiplier;
    usage.cost.cache_write *= multiplier;
    usage.cost.total = usage.cost.input + usage.cost.output + usage.cost.cache_read + usage.cost.cache_write;
}

fn codexCacheSessionId(session_id: ?[]const u8, retention: metadata.CacheRetention) ?[]const u8 {
    if (retention == .none) return null;
    const sid = session_id orelse return null;
    return sid[0..@min(sid.len, 64)];
}

fn codexTransportName(transport: codex_ws.Transport) []const u8 {
    return switch (transport) {
        .sse => "sse",
        .websocket => "websocket",
        .websocket_cached => "websocket-cached",
        .auto => "auto",
    };
}

fn transportDiagnosticJson(
    gpa: std.mem.Allocator,
    io: Io,
    code: []const u8,
    transport: codex_ws.Transport,
    fallback_transport: ?[]const u8,
    events_emitted: bool,
    request_bytes: usize,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("[{\"type\":\"provider_transport_failure\",\"timestamp\":");
    try out.writer.print("{d}", .{Io.Clock.real.now(io).toMilliseconds()});
    try out.writer.writeAll(",\"error\":{\"name\":\"ZigError\",\"message\":");
    try std.json.Stringify.value(code, .{}, &out.writer);
    try out.writer.writeAll(",\"code\":");
    try std.json.Stringify.value(code, .{}, &out.writer);
    try out.writer.writeAll("},\"details\":{\"configuredTransport\":");
    try std.json.Stringify.value(codexTransportName(transport), .{}, &out.writer);
    if (fallback_transport) |fallback| {
        try out.writer.writeAll(",\"fallbackTransport\":");
        try std.json.Stringify.value(fallback, .{}, &out.writer);
    }
    try out.writer.print(",\"eventsEmitted\":{s},\"phase\":", .{if (events_emitted) "true" else "false"});
    try std.json.Stringify.value(if (events_emitted) "after_message_stream_start" else "before_message_stream_start", .{}, &out.writer);
    try out.writer.print(",\"requestBytes\":{d}}}}}]", .{request_bytes});
    return out.toOwnedSlice();
}

pub const TokenRefreshFn = *const fn (*anyopaque, *ResponsesClient, i64) anyerror!void;

pub const ResponsesClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    /// Process/provider proxy environment.
    environ: ?*const std.process.Environ.Map = null,
    /// Global settings.json `httpProxy` fallback.
    proxy_url: ?[]const u8 = null,
    /// Provider-internal request retry settings.
    provider_retry: retry_mod.ProviderPolicy = .{ .max_retries = 2 },
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    provider_id: []const u8 = "openai",
    thinking: ai.ThinkingLevel = .off,
    reasoning: bool = true,
    input_image: bool = false,
    thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
    custom_headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    model_cost: providers.ModelCost = .{},
    abort_flag: ?*bool = null,
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
    auth_mode: AuthMode = .bearer,
    api_version: ?[]const u8 = null,
    protocol_mode: ProtocolMode = .standard,
    transport: codex_ws.Transport = .sse,
    /// Maximum idle time for Codex HTTP response headers and each body read.
    /// Zero disables the deadline.
    http_idle_timeout_ms: u64 = DEFAULT_HTTP_IDLE_TIMEOUT_MS,
    /// Maximum time to establish a Codex WebSocket; zero disables the deadline.
    websocket_connect_timeout_ms: u64 = DEFAULT_WEBSOCKET_CONNECT_TIMEOUT_MS,
    /// OAuth token expiry/refresh hook used by the OpenAI Codex identity.
    token_expiration_ms: ?i64 = null,
    token_refresh_ctx: ?*anyopaque = null,
    token_refresh_fn: ?TokenRefreshFn = null,
    ws_client: ?codex_ws.Client = null,
    continuation: ?CodexContinuation = null,
    /// Optional pool-owned session flag. Direct clients use the local fallback bit.
    ws_fallback_flag: ?*bool = null,
    ws_fallback_local: bool = false,

    pub fn deinit(self: *ResponsesClient) void {
        if (self.ws_client) |*socket| socket.deinit();
        self.ws_client = null;
        self.clearContinuation();
    }

    pub fn client(self: *ResponsesClient) ai.ModelClient {
        return .{ .ptr = self, .completeFn = completeImpl, .completeOptionsFn = completeOptionsImpl, .streamFn = streamImpl };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        return completeOptionsImpl(ptr, gpa, messages, tools_json, .{});
    }

    fn completeOptionsImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, options: ai.CompletionOptions) anyerror!ai.ModelResponse {
        const self: *ResponsesClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages, tools_json, options, false, null, null);
    }

    fn streamImpl(
        ptr: *anyopaque,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) anyerror!ai.ModelResponse {
        const self: *ResponsesClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages, tools_json, .{}, true, on_delta, delta_ctx);
    }

    fn ensureTokenFresh(self: *ResponsesClient) !void {
        const expires = self.token_expiration_ms orelse return;
        const refresh_fn = self.token_refresh_fn orelse return;
        const ctx = self.token_refresh_ctx orelse return;
        const now_ms = std.Io.Clock.real.now(self.io).toMilliseconds();
        if (now_ms < expires) return;
        try refresh_fn(ctx, self, now_ms);
    }

    fn request(
        self: *ResponsesClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        request_options: ai.CompletionOptions,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        try self.ensureTokenFresh();
        const effective_max_tokens = context_estimate.clampMaxTokens(self.context_window, ai.resolveMaxTokens(self.max_tokens, request_options.max_tokens), messages, tools_json);
        const effective_cache_retention: metadata.CacheRetention = ai.resolveCacheRetention(self.cache_retention, request_options);
        const effective_session_id: ?[]const u8 = ai.resolveSessionAffinity(self.session_id, request_options);
        const payload = if (self.protocol_mode == .codex)
            try buildCodexRequestBody(gpa, self.model, messages, tools_json, .{
                .stream = streaming,
                .thinking = self.thinking,
                .reasoning = self.reasoning,
                .input_image = self.input_image,
                .thinking_level_map = self.thinking_level_map,
                .max_tokens = effective_max_tokens,
                .sampling_params = self.sampling_params,
                .compat = self.compat,
                .session_id = codexCacheSessionId(effective_session_id, effective_cache_retention),
                .cache_retention = effective_cache_retention,
                .provider_id = self.provider_id,
                .api_id = protocolApiName(self.protocol_mode),
            })
        else
            try buildRequestBody(gpa, self.model, messages, tools_json, .{
                .stream = streaming,
                .thinking = self.thinking,
                .reasoning = self.reasoning,
                .input_image = self.input_image,
                .thinking_level_map = self.thinking_level_map,
                .max_tokens = effective_max_tokens,
                .sampling_params = self.sampling_params,
                .compat = self.compat,
                .session_id = codexCacheSessionId(effective_session_id, effective_cache_retention),
                .cache_retention = effective_cache_retention,
                .provider_id = self.provider_id,
                .api_id = protocolApiName(self.protocol_mode),
            });
        defer gpa.free(payload);
        const url = if (self.protocol_mode == .codex)
            try resolveCodexUrl(gpa, self.base_url)
        else if (self.api_version) |version|
            try std.fmt.allocPrint(gpa, "{s}/responses?api-version={s}", .{ self.base_url, version })
        else
            try std.fmt.allocPrint(gpa, "{s}/responses", .{self.base_url});
        defer gpa.free(url);

        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena.deinit();
        var http_client: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http_client.deinit();
        _ = try http_proxy.configureClient(&http_client, proxy_arena.allocator(), url, .{
            .environ = self.environ,
            .setting = self.proxy_url,
        });
        const authorization = if (self.auth_mode == .bearer) try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key}) else null;
        defer if (authorization) |value| gpa.free(value);
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        var codex_account_id: ?[]u8 = null;
        defer if (codex_account_id) |value| gpa.free(value);
        try putHeader(gpa, &headers, "content-type", "application/json");
        if (self.protocol_mode == .codex) {
            // Codex applies custom headers first, then mandatory identity/auth headers.
            for (self.custom_headers) |header| try putHeader(gpa, &headers, header.name, header.value);
            try putHeader(gpa, &headers, "authorization", authorization.?);
            codex_account_id = try extractCodexAccountId(gpa, self.api_key);
            try putHeader(gpa, &headers, "chatgpt-account-id", codex_account_id.?);
            try putHeader(gpa, &headers, "originator", "pi");
            try putHeader(gpa, &headers, "user-agent", "pi-zig/0.3.0");
            try putHeader(gpa, &headers, "openai-beta", "responses=experimental");
            try putHeader(gpa, &headers, "content-type", "application/json");
            if (codexCacheSessionId(effective_session_id, effective_cache_retention)) |sid| {
                try putHeader(gpa, &headers, "session-id", sid);
                try putHeader(gpa, &headers, "x-client-request-id", sid);
            }
        } else {
            if (self.auth_mode == .azure_api_key) {
                try putHeader(gpa, &headers, "api-key", self.api_key);
            } else if (cloudflare.isAIGateway(self.provider_id)) {
                try putHeader(gpa, &headers, "cf-aig-authorization", authorization.?);
            } else {
                try putHeader(gpa, &headers, "authorization", authorization.?);
            }
            if (effective_session_id) |sid| if (effective_cache_retention != .none) {
                const format = self.compat.session_affinity_format orelse if (std.ascii.eqlIgnoreCase(self.provider_id, "openrouter")) metadata.SessionAffinityFormat.openrouter else metadata.SessionAffinityFormat.openai;
                switch (format) {
                    .openrouter => try putHeader(gpa, &headers, "x-session-id", sid),
                    .openai => {
                        try putHeader(gpa, &headers, "session_id", sid);
                        try putHeader(gpa, &headers, "x-client-request-id", sid);
                    },
                    .openai_nosession => try putHeader(gpa, &headers, "x-client-request-id", sid),
                }
            };
            if (copilot.isCopilot(self.provider_id)) {
                try putHeader(gpa, &headers, "User-Agent", copilot.USER_AGENT);
                try putHeader(gpa, &headers, "Editor-Version", copilot.EDITOR_VERSION);
                try putHeader(gpa, &headers, "Editor-Plugin-Version", copilot.EDITOR_PLUGIN_VERSION);
                try putHeader(gpa, &headers, "Copilot-Integration-Id", copilot.INTEGRATION_ID);
                const dynamic = copilot.infer(messages);
                try putHeader(gpa, &headers, "X-Initiator", dynamic.initiator);
                try putHeader(gpa, &headers, "Openai-Intent", "conversation-edits");
                if (dynamic.has_vision) try putHeader(gpa, &headers, "Copilot-Vision-Request", "true");
            }
            for (self.custom_headers) |header| try putHeader(gpa, &headers, header.name, header.value);
        }
        try putHeader(gpa, &headers, "accept", if (streaming) "text/event-stream" else "application/json");

        var live = ResponsesLive.init(gpa, on_delta, delta_ctx, streaming, self.abort_flag);
        live.grammar_tools_json = tools_json;
        live.supports_grammar = self.compat.supports_openai_grammar_tools == true;
        live.strict_codex_json = self.protocol_mode == .codex;
        live.attachBuffer();
        defer live.deinit();

        if (self.protocol_mode == .codex and streaming and self.transport.usesWebSocket() and !self.websocketFallbackActive()) {
            if (try self.requestCodexWebSocket(gpa, url, payload, headers.items, messages, tools_json, &live)) |response| return response;
            // Transport failure before the first model event: reset the shared
            // accumulator and fall back to the established SSE transport.
            live.resetForRetry();
        }

        // The official Codex SSE path sends Zstandard-encoded request bytes.
        // Keep WebSocket frames uncompressed; only prepare this after WS has
        // either been skipped or fallen back to SSE.
        var encoded_payload: ?[]u8 = null;
        defer if (encoded_payload) |bytes| gpa.free(bytes);
        var http_payload: []const u8 = payload;
        if (self.protocol_mode == .codex and streaming) {
            encoded_payload = encodeZstdRequestBody(gpa, payload) catch null;
            if (encoded_payload) |bytes| {
                http_payload = bytes;
                try putHeader(gpa, &headers, "content-encoding", "zstd");
            }
        }

        const provider_timeout_is_zero = if (self.provider_retry.timeout_ms) |value| value == 0 else false;
        const effective_idle_timeout_ms = self.provider_retry.timeout_ms orelse if (self.protocol_mode == .codex) self.http_idle_timeout_ms else 0;
        var retry_index: usize = 0;
        var status: u16 = 0;
        var provider_meta: retry_mod.ProviderResponseMeta = .{};
        while (true) {
            if (retry_index > 0) live.resetForRetry();
            const result = (if (provider_timeout_is_zero)
                error.ProviderRequestTimeout
            else
                postHttpCaptureRetry(
                    &http_client,
                    gpa,
                    self.io,
                    url,
                    http_payload,
                    headers.items,
                    &live.writer,
                    effective_idle_timeout_ms,
                    self.abort_flag,
                    if (self.protocol_mode == .codex and streaming) &live else null,
                )) catch |err| {
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                // A Codex parser error is a provider protocol failure, not a
                // transport outage. Preserve any partial assistant output and do
                // not retry/fall back, matching the WebSocket behavior.
                if (self.protocol_mode == .codex and live.error_message.len > 0 and std.mem.eql(u8, live.stop_reason, "error")) {
                    var response = try live.finish(self.provider_id, self.model);
                    errdefer response.deinit(gpa);
                    try response.normalizeToolArguments(gpa);
                    try response.setApi(gpa, protocolApiName(self.protocol_mode));
                    _ = cost_mod.calculate(self.model_cost, &response.usage);
                    try response.ensureStopReason(gpa);
                    return response;
                }
                // Never replay a request after model output has started: doing so
                // can duplicate already-emitted deltas/tool calls.
                if (live.started()) return err;
                if (retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = if (self.protocol_mode == .codex)
                    try retryDelayMs(self.provider_retry, retry_index, null)
                else
                    try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            status = result.status;
            provider_meta = result.provider;
            try live.flushTrailing();
            if (live.aborted) return abortedResponse(gpa, self.provider_id, self.model);
            if (retry_index < self.provider_retry.max_retries and isRetryableHttp(result.provider, live.body.items, self.protocol_mode == .codex)) {
                const delay_ms = if (self.protocol_mode == .codex)
                    try retryDelayMs(self.provider_retry, retry_index, result.provider.retry_after_ms)
                else
                    try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, result.provider.retry_after_ms);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            }
            break;
        }

        if (status < 200 or status >= 300) {
            const snippet = if (live.body.items.len > 800) live.body.items[0..800] else live.body.items;
            const content = try std.fmt.allocPrint(gpa, "HTTP {d} from {s}: {s}", .{ status, self.provider_id, snippet });
            return .{
                .content = content,
                .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                .provider = try gpa.dupe(u8, self.provider_id),
                .model = try gpa.dupe(u8, self.model),
                .stop_reason = try gpa.dupe(u8, "error"),
                .provider_status = provider_meta.status,
                .provider_retry_after_ms = provider_meta.retry_after_ms,
                .provider_should_retry = provider_meta.should_retry,
            };
        }

        var response = if (streaming)
            try live.finish(self.provider_id, self.model)
        else
            try parseResponseConfigured(gpa, live.body.items, self.provider_id, self.model, tools_json, self.compat);
        try response.normalizeToolArguments(gpa);
        if (response.api.len > 0) gpa.free(response.api);
        response.api = try gpa.dupe(u8, protocolApiName(self.protocol_mode));
        _ = cost_mod.calculate(self.model_cost, &response.usage);
        const request_tier = requestedServiceTier(self.sampling_params);
        const response_tier = if (streaming) live.service_tier else parseResponseServiceTier(gpa, live.body.items);
        applyServiceTierCost(self.model, effectiveServiceTier(self.protocol_mode, response_tier, request_tier), &response.usage);
        try response.ensureStopReason(gpa);
        return response;
    }

    fn finishCodexLiveResponse(
        self: *ResponsesClient,
        gpa: std.mem.Allocator,
        live: *ResponsesLive,
        messages: []const ai.ChatMessage,
        payload: []const u8,
        allow_continuation: bool,
    ) !ai.ModelResponse {
        var response = try live.finish(self.provider_id, self.model);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        if (response.api.len > 0) gpa.free(response.api);
        response.api = try gpa.dupe(u8, protocolApiName(self.protocol_mode));
        _ = cost_mod.calculate(self.model_cost, &response.usage);
        const request_tier = requestedServiceTier(self.sampling_params);
        applyServiceTierCost(self.model, effectiveServiceTier(self.protocol_mode, live.service_tier, request_tier), &response.usage);
        try response.ensureStopReason(gpa);

        if (allow_continuation and self.transport.usesCachedContext() and response.response_id.len > 0 and self.session_id != null and self.cache_retention != .none)
            try self.rememberContinuation(gpa, messages, payload, response.response_id)
        else
            self.clearContinuation();
        if (!allow_continuation or self.session_id == null or self.cache_retention == .none) self.closeCodexSocket();
        return response;
    }

    /// Attempt one Codex Responses request over RFC6455. Returns null only
    /// when transport failed before any provider event, allowing safe SSE
    /// fallback without duplicating partially emitted model output.
    fn requestCodexWebSocket(
        self: *ResponsesClient,
        gpa: std.mem.Allocator,
        url: []const u8,
        payload: []const u8,
        base_headers: []const std.http.Header,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        live: *ResponsesLive,
    ) !?ai.ModelResponse {
        if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire))
            return try abortedResponse(gpa, self.provider_id, self.model);

        const cache_sid = codexCacheSessionId(self.session_id, self.cache_retention);
        const request_id_owned = if (cache_sid == null) try uuidV7(gpa, self.io) else null;
        defer if (request_id_owned) |value| gpa.free(value);
        const request_id = cache_sid orelse request_id_owned.?;

        self.ensureCodexSocket(gpa, url, base_headers, request_id) catch |err| {
            if (err == error.WebSocketAborted or (self.abort_flag != null and @atomicLoad(bool, self.abort_flag.?, .acquire)))
                return try abortedResponse(gpa, self.provider_id, self.model);
            try live.setTransportDiagnostic(self.io, @errorName(err), self.transport, "sse", false, payload.len);
            self.markWebSocketFallback();
            return null;
        };

        var cached_payload: ?[]u8 = null;
        defer if (cached_payload) |value| gpa.free(value);
        var used_continuation = false;
        if (self.transport.usesCachedContext()) {
            cached_payload = try self.buildCachedCodexPayload(gpa, payload, messages, tools_json);
            used_continuation = cached_payload != null;
        }

        var retried_full_context = false;
        var retried_connection_limit = false;
        while (true) {
            const wire_payload = cached_payload orelse payload;
            const frame_payload = try codexResponseCreateFrame(gpa, wire_payload);
            defer gpa.free(frame_payload);
            self.ws_client.?.sendText(frame_payload) catch |err| {
                self.closeCodexSocket();
                self.clearContinuation();
                try live.setTransportDiagnostic(self.io, @errorName(err), self.transport, "sse", false, wire_payload.len);
                self.markWebSocketFallback();
                return null;
            };

            var saw_event = false;
            var retry_full = false;
            while (true) {
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) {
                    self.closeCodexSocket();
                    return try abortedResponse(gpa, self.provider_id, self.model);
                };
                var frame = self.ws_client.?.readMessageWithControl(gpa, self.http_idle_timeout_ms, self.abort_flag) catch |err| {
                    self.closeCodexSocket();
                    if (err == error.WebSocketAborted or (self.abort_flag != null and @atomicLoad(bool, self.abort_flag.?, .acquire))) {
                        return try abortedResponse(gpa, self.provider_id, self.model);
                    }
                    self.clearContinuation();
                    if (!saw_event) {
                        try live.setTransportDiagnostic(self.io, @errorName(err), self.transport, "sse", false, wire_payload.len);
                        self.markWebSocketFallback();
                        return null;
                    }
                    // Once the provider has started emitting a response, never fall
                    // back to SSE: replaying the request could duplicate already
                    // delivered text/tool deltas. Preserve the partial assistant
                    // message as an error response with a transport diagnostic.
                    try live.setTransportDiagnostic(self.io, @errorName(err), self.transport, null, true, wire_payload.len);
                    if (live.raw_stop_reason.len > 0) self.gpa.free(live.raw_stop_reason);
                    live.raw_stop_reason = try gpa.dupe(u8, @errorName(err));
                    live.stop_reason = "error";
                    if (live.on_delta) |handler| handler(live.delta_ctx, .{ .kind = .err, .text = @errorName(err) });
                    return try self.finishCodexLiveResponse(gpa, live, messages, payload, false);
                };
                defer frame.deinit(gpa);
                if (frame.opcode != .text) continue;

                const kind = codexEventKind(frame.data);
                if (kind == .diagnostic) continue;
                if (kind == .previous_response_not_found and used_continuation and !retried_full_context) {
                    self.clearContinuation();
                    retried_full_context = true;
                    retry_full = true;
                    break;
                }
                if (kind == .connection_limit and !saw_event) {
                    self.closeCodexSocket();
                    self.clearContinuation();
                    if (!retried_connection_limit) {
                        retried_connection_limit = true;
                        live.resetForRetry();
                        self.ensureCodexSocket(gpa, url, base_headers, request_id) catch |err| {
                            if (err == error.WebSocketAborted or (self.abort_flag != null and @atomicLoad(bool, self.abort_flag.?, .acquire)))
                                return try abortedResponse(gpa, self.provider_id, self.model);
                            self.markWebSocketFallback();
                            return null;
                        };
                        retry_full = true;
                        used_continuation = false;
                        if (cached_payload) |value| {
                            gpa.free(value);
                            cached_payload = null;
                        }
                        break;
                    }
                    try live.setTransportDiagnostic(self.io, "websocket_connection_limit_reached", self.transport, "sse", false, wire_payload.len);
                    self.markWebSocketFallback();
                    return null;
                }
                if (kind == .api_error or kind == .previous_response_not_found or kind == .connection_limit) {
                    self.closeCodexSocket();
                    self.clearContinuation();
                    try live.handleEventJson(frame.data);
                    return try self.finishCodexLiveResponse(gpa, live, messages, payload, false);
                }
                saw_event = true;
                live.handleEventJson(frame.data) catch |err| {
                    self.closeCodexSocket();
                    self.clearContinuation();
                    if (live.error_message.len == 0) try live.setErrorMessage(@errorName(err));
                    live.stop_reason = "error";
                    return try self.finishCodexLiveResponse(gpa, live, messages, payload, false);
                };
                if (kind == .terminal) break;
            }
            if (retry_full) {
                live.resetForRetry();
                used_continuation = false;
                if (cached_payload) |value| {
                    gpa.free(value);
                    cached_payload = null;
                }
                continue;
            }
            break;
        }

        return try self.finishCodexLiveResponse(gpa, live, messages, payload, true);
    }

    fn buildCachedCodexPayload(self: *ResponsesClient, gpa: std.mem.Allocator, payload: []const u8, messages: []const ai.ChatMessage, tools_json: []const u8) !?[]u8 {
        const continuation = if (self.continuation) |*value| value else return null;
        if (continuation.prefix_count >= messages.len) {
            self.clearContinuation();
            return null;
        }
        if (!std.mem.eql(u8, &continuation.prefix_hash, &hashChatMessages(messages[0..continuation.prefix_count]))) {
            self.clearContinuation();
            return null;
        }
        if (!std.mem.eql(u8, &continuation.shape_hash, &requestShapeHash(payload))) {
            self.clearContinuation();
            return null;
        }
        const previous = messages[continuation.prefix_count];
        if (!std.mem.eql(u8, previous.role, "assistant") or previous.response_id == null or
            !std.mem.eql(u8, previous.response_id.?, continuation.response_id) or
            previous.provider == null or previous.api == null or previous.model == null or
            !std.mem.eql(u8, previous.provider.?, self.provider_id) or
            !std.mem.eql(u8, previous.api.?, protocolApiName(self.protocol_mode)) or
            !std.mem.eql(u8, previous.model.?, self.model))
        {
            self.clearContinuation();
            return null;
        }

        var delta: std.Io.Writer.Allocating = .init(gpa);
        defer delta.deinit();
        try writeResponseInputMessages(gpa, &delta.writer, messages[continuation.prefix_count + 1 ..], tools_json, self.compat, self.provider_id, protocolApiName(self.protocol_mode), self.model, self.input_image);
        return try buildPreviousResponsePayload(gpa, payload, continuation.response_id, delta.written());
    }

    fn rememberContinuation(self: *ResponsesClient, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, payload: []const u8, response_id: []const u8) !void {
        self.clearContinuation();
        self.continuation = .{
            .response_id = try gpa.dupe(u8, response_id),
            .prefix_count = messages.len,
            .prefix_hash = hashChatMessages(messages),
            .shape_hash = requestShapeHash(payload),
        };
    }

    fn clearContinuation(self: *ResponsesClient) void {
        if (self.continuation) |*value| value.deinit(self.gpa);
        self.continuation = null;
    }

    fn ensureCodexSocket(self: *ResponsesClient, gpa: std.mem.Allocator, url: []const u8, base_headers: []const std.http.Header, request_id: []const u8) !void {
        if (self.ws_client) |*socket| {
            if (!socket.reusable()) self.closeCodexSocket();
        }
        if (self.ws_client != null) return;
        var ws_headers: std.ArrayList(std.http.Header) = .empty;
        defer ws_headers.deinit(gpa);
        try ws_headers.appendSlice(gpa, base_headers);
        removeHeader(&ws_headers, "accept");
        removeHeader(&ws_headers, "content-type");
        removeHeader(&ws_headers, "openai-beta");
        try putHeader(gpa, &ws_headers, "openai-beta", codex_ws.OPENAI_BETA);
        try putHeader(gpa, &ws_headers, "x-client-request-id", request_id);
        try putHeader(gpa, &ws_headers, "session-id", request_id);
        self.ws_client = try codex_ws.Client.connectWithTimeoutAndAbortProxy(
            gpa,
            self.io,
            url,
            ws_headers.items,
            self.websocket_connect_timeout_ms,
            self.abort_flag,
            .{ .environ = self.environ, .setting = self.proxy_url },
        );
    }

    fn websocketFallbackActive(self: *const ResponsesClient) bool {
        if (self.ws_fallback_flag) |flag| return flag.*;
        return self.ws_fallback_local;
    }

    fn markWebSocketFallback(self: *ResponsesClient) void {
        if (self.ws_fallback_flag) |flag| flag.* = true else self.ws_fallback_local = true;
    }

    fn closeCodexSocket(self: *ResponsesClient) void {
        if (self.ws_client) |*socket| socket.deinit();
        self.ws_client = null;
        // `previous_response_id` continuation is scoped to the physical
        // Codex WebSocket connection. Never carry it across reconnects.
        self.clearContinuation();
    }
};

const CodexContinuation = struct {
    response_id: []u8,
    prefix_count: usize,
    prefix_hash: [32]u8,
    shape_hash: [32]u8,

    fn deinit(self: *CodexContinuation, gpa: std.mem.Allocator) void {
        gpa.free(self.response_id);
        self.* = undefined;
    }
};

fn hashField(hasher: anytype, value: ?[]const u8) void {
    var len_buf: [8]u8 = undefined;
    const slice = value orelse "";
    std.mem.writeInt(u64, &len_buf, @intCast(slice.len), .little);
    hasher.update(&len_buf);
    hasher.update(slice);
    hasher.update(&[_]u8{if (value == null) 0 else 1});
}

fn hashChatMessages(messages: []const ai.ChatMessage) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (messages) |message| {
        hashField(&hasher, message.role);
        hashField(&hasher, message.content);
        hashField(&hasher, message.provider);
        hashField(&hasher, message.api);
        hashField(&hasher, message.model);
        hashField(&hasher, message.response_id);
        hashField(&hasher, message.thinking);
        hashField(&hasher, message.thinking_signature);
        hashField(&hasher, message.tool_call_id);
        hashField(&hasher, message.tool_calls_json);
        hashField(&hasher, message.tool_name);
        hashField(&hasher, message.image_b64);
        hashField(&hasher, message.image_mime);
        for (message.images) |image| {
            hashField(&hasher, image.data_b64);
            hashField(&hasher, image.mime_type);
        }
        for (message.added_tool_names) |name| hashField(&hasher, name);
        hasher.update(&[_]u8{0xff});
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn requestShapeHash(payload: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, payload, .{}) catch {
        hasher.update(payload);
        var fallback: [32]u8 = undefined;
        hasher.final(&fallback);
        return fallback;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        hasher.update(payload);
    } else {
        var it = parsed.value.object.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, "input") or std.mem.eql(u8, entry.key_ptr.*, "previous_response_id")) continue;
            hashField(&hasher, entry.key_ptr.*);
            var encoded: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
            defer encoded.deinit();
            std.json.Stringify.value(entry.value_ptr.*, .{}, &encoded.writer) catch continue;
            hasher.update(encoded.written());
        }
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn buildPreviousResponsePayload(gpa: std.mem.Allocator, payload: []const u8, previous_response_id: []const u8, delta_input_json: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponsesPayload;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeByte('{');
    var first = true;
    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, "input") or std.mem.eql(u8, entry.key_ptr.*, "previous_response_id")) continue;
        if (!first) try out.writer.writeByte(',');
        first = false;
        try std.json.Stringify.value(entry.key_ptr.*, .{}, &out.writer);
        try out.writer.writeByte(':');
        try std.json.Stringify.value(entry.value_ptr.*, .{}, &out.writer);
    }
    if (!first) try out.writer.writeByte(',');
    try out.writer.writeAll("\"previous_response_id\":");
    try std.json.Stringify.value(previous_response_id, .{}, &out.writer);
    try out.writer.writeAll(",\"input\":");
    try out.writer.writeAll(delta_input_json);
    try out.writer.writeByte('}');
    return out.toOwnedSlice();
}

const CodexEventKind = enum { other, diagnostic, terminal, api_error, connection_limit, previous_response_not_found };

fn codexEventKind(data: []const u8) CodexEventKind {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, data, .{}) catch return .other;
    defer parsed.deinit();
    if (parsed.value != .object) return .other;
    const typ = parsed.value.object.get("type") orelse return .other;
    if (typ != .string) return .other;
    if (std.mem.eql(u8, typ.string, "codex.rate_limits")) return .diagnostic;
    if (std.mem.eql(u8, typ.string, "error")) {
        var code: ?[]const u8 = null;
        if (parsed.value.object.get("code")) |value| {
            if (value == .string) code = value.string;
        }
        if (code == null) {
            if (parsed.value.object.get("error")) |err_value| {
                if (err_value == .object) {
                    if (err_value.object.get("code")) |value| {
                        if (value == .string) code = value.string;
                    }
                }
            }
        }
        if (code) |value| {
            if (std.mem.eql(u8, value, "previous_response_not_found")) return .previous_response_not_found;
            if (std.mem.eql(u8, value, "websocket_connection_limit_reached")) return .connection_limit;
        }
        return .api_error;
    }
    if (std.mem.eql(u8, typ.string, "response.completed") or
        std.mem.eql(u8, typ.string, "response.done") or
        std.mem.eql(u8, typ.string, "response.incomplete") or
        std.mem.eql(u8, typ.string, "response.failed")) return .terminal;
    return .other;
}

fn codexResponseCreateFrame(gpa: std.mem.Allocator, payload: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, payload, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{' or trimmed[trimmed.len - 1] != '}') return error.InvalidResponsesPayload;
    return std.fmt.allocPrint(gpa, "{{\"type\":\"response.create\",{s}", .{trimmed[1..]});
}

fn removeHeader(headers: *std.ArrayList(std.http.Header), name: []const u8) void {
    var i: usize = 0;
    while (i < headers.items.len) {
        if (std.ascii.eqlIgnoreCase(headers.items[i].name, name)) {
            _ = headers.orderedRemove(i);
        } else i += 1;
    }
}

fn uuidV7(gpa: std.mem.Allocator, io: Io) ![]u8 {
    var bytes: [16]u8 = undefined;
    io.random(&bytes);
    const now_ms: u64 = @intCast(@max(@as(i64, 0), Io.Clock.real.now(io).toMilliseconds()));
    bytes[0] = @truncate(now_ms >> 40);
    bytes[1] = @truncate(now_ms >> 32);
    bytes[2] = @truncate(now_ms >> 24);
    bytes[3] = @truncate(now_ms >> 16);
    bytes[4] = @truncate(now_ms >> 8);
    bytes[5] = @truncate(now_ms);
    bytes[6] = (bytes[6] & 0x0f) | 0x70;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const out = try gpa.alloc(u8, 36);
    errdefer gpa.free(out);
    const hex = "0123456789abcdef";
    var j: usize = 0;
    for (bytes, 0..) |byte, i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            out[j] = '-';
            j += 1;
        }
        out[j] = hex[byte >> 4];
        out[j + 1] = hex[byte & 0x0f];
        j += 2;
    }
    return out;
}

fn protocolApiName(mode: ProtocolMode) []const u8 {
    return switch (mode) {
        .standard => "openai-responses",
        .azure => "azure-openai-responses",
        .codex => "openai-codex-responses",
    };
}

fn resolveCodexUrl(gpa: std.mem.Allocator, base_url: []const u8) ![]u8 {
    const trimmed = std.mem.trimEnd(u8, base_url, "/");
    if (std.mem.endsWith(u8, trimmed, "/codex/responses")) return gpa.dupe(u8, trimmed);
    if (std.mem.endsWith(u8, trimmed, "/codex")) return std.fmt.allocPrint(gpa, "{s}/responses", .{trimmed});
    return std.fmt.allocPrint(gpa, "{s}/codex/responses", .{trimmed});
}

fn decodeBase64Url(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoder = std.base64.url_safe_no_pad.Decoder;
    const size = decoder.calcSizeForSlice(input) catch return error.InvalidCodexToken;
    const out = try gpa.alloc(u8, size);
    errdefer gpa.free(out);
    decoder.decode(out, input) catch return error.InvalidCodexToken;
    return out;
}

fn extractCodexAccountId(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    const first = std.mem.indexOfScalar(u8, token, '.') orelse return error.InvalidCodexToken;
    const rest = token[first + 1 ..];
    const second_rel = std.mem.indexOfScalar(u8, rest, '.') orelse return error.InvalidCodexToken;
    const payload = try decodeBase64Url(gpa, rest[0..second_rel]);
    defer gpa.free(payload);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, payload, .{}) catch return error.InvalidCodexToken;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCodexToken;
    const auth = parsed.value.object.get("https://api.openai.com/auth") orelse return error.InvalidCodexToken;
    if (auth != .object) return error.InvalidCodexToken;
    const id = auth.object.get("chatgpt_account_id") orelse return error.InvalidCodexToken;
    if (id != .string or id.string.len == 0) return error.InvalidCodexToken;
    return gpa.dupe(u8, id.string);
}

fn abortedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !ai.ModelResponse {
    return .{
        .content = try gpa.dupe(u8, "aborted"),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "aborted"),
    };
}

fn putHeader(gpa: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
    for (headers.items) |*header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            header.* = .{ .name = name, .value = value };
            return;
        }
    }
    try headers.append(gpa, .{ .name = name, .value = value });
}

pub const RequestOptions = struct {
    stream: bool = false,
    thinking: ai.ThinkingLevel = .off,
    reasoning: bool = true,
    /// Whether the selected model accepts image inputs. Direct serializer use
    /// defaults true for backward compatibility; runtime clients pass model metadata.
    input_image: bool = true,
    thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
    max_tokens: u64 = 0,
    sampling_params: []const metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
    provider_id: []const u8 = "openai",
    api_id: []const u8 = "openai-responses",
};

fn mappedThinkingLevel(map: ?thinking_mod.ThinkingLevelMap, level: ai.ThinkingLevel, fallback: []const u8) ?[]const u8 {
    const resolved = map orelse return fallback;
    return switch (resolved.entry(level)) {
        .absent => fallback,
        .unsupported => null,
        .mapped => |value| value,
    };
}

fn requestedThinkingEffort(options: RequestOptions) ?[]const u8 {
    if (!options.reasoning or options.thinking == .off) return null;
    const fallback = options.thinking.openaiEffort() orelse return null;
    return mappedThinkingLevel(options.thinking_level_map, options.thinking, fallback);
}

fn disabledThinkingEffort(options: RequestOptions) ?[]const u8 {
    if (!options.reasoning or options.thinking != .off) return null;
    if (std.ascii.eqlIgnoreCase(options.provider_id, "github-copilot")) return null;
    return mappedThinkingLevel(options.thinking_level_map, .off, "none");
}

fn hasSampling(params: []const metadata.SamplingParam, name: []const u8) bool {
    for (params) |param| if (std.mem.eql(u8, param.name, name)) return true;
    return false;
}

fn callIdOnly(id: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, id, '|')) |i| id[0..i] else id;
}

fn writeResponseInput(
    gpa: std.mem.Allocator,
    w: anytype,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    compat: metadata.Compat,
    current_provider: []const u8,
    current_api: []const u8,
    current_model: []const u8,
    supports_image_input: bool,
) !void {
    var repaired = try transcript_repair.repair(gpa, messages);
    defer repaired.deinit();
    try writeResponseInputMessages(gpa, w, repaired.messages.items, tools_json, compat, current_provider, current_api, current_model, supports_image_input);
}

fn writeResponseInputMessages(
    gpa: std.mem.Allocator,
    w: anytype,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    compat: metadata.Compat,
    current_provider: []const u8,
    current_api: []const u8,
    current_model: []const u8,
    supports_image_input: bool,
) !void {
    try w.writeAll("[");
    var first = true;
    var loaded_deferred: std.StringHashMap(void) = .init(gpa);
    defer loaded_deferred.deinit();
    for (messages, 0..) |msg, msg_index| {
        if (std.mem.eql(u8, msg.role, "tool")) {
            if (!first) try w.writeAll(",");
            first = false;
            const grammar_result = if (msg.tool_name) |name|
                (try constrained.findGrammarInputProperty(gpa, tools_json, name, compat.supports_openai_grammar_tools == true))
            else
                null;
            defer if (grammar_result) |property| gpa.free(property);
            try w.writeAll(if (grammar_result != null)
                "{\"type\":\"custom_tool_call_output\",\"call_id\":"
            else
                "{\"type\":\"function_call_output\",\"call_id\":");
            try std.json.Stringify.value(callIdOnly(msg.tool_call_id orelse ""), .{}, w);
            try w.writeAll(",\"output\":");
            try writeToolResultOutput(gpa, w, msg, supports_image_input);
            try w.writeAll("}");
            const deferred_mode = compat.supports_additional_tools == true or compat.supports_tool_search == true;
            if (deferred_mode and msg.added_tool_names.len > 0) {
                var names: std.ArrayList([]const u8) = .empty;
                defer names.deinit(gpa);
                for (msg.added_tool_names) |name| {
                    if (!isDeferredTool(gpa, messages, name) or loaded_deferred.contains(name)) continue;
                    try loaded_deferred.put(name, {});
                    try names.append(gpa, name);
                }
                if (names.items.len > 0) {
                    if (compat.supports_additional_tools == true) {
                        if (try convertToolsSelected(gpa, tools_json, compat, messages, names.items, false, false)) |loaded_tools| {
                            defer gpa.free(loaded_tools);
                            try w.writeAll(",{\"type\":\"additional_tools\",\"role\":\"developer\",\"tools\":");
                            try w.writeAll(loaded_tools);
                            try w.writeAll("}");
                        }
                    } else {
                        const search_id = try std.fmt.allocPrint(gpa, "pi_tool_load_{d}", .{msg_index});
                        defer gpa.free(search_id);
                        try w.writeAll(",{");
                        try w.writeAll("\"type\":\"tool_search_call\",\"call_id\":");
                        try std.json.Stringify.value(search_id, .{}, w);
                        try w.writeAll(",\"execution\":\"client\",\"status\":\"completed\",\"arguments\":{\"query\":");
                        var query: std.Io.Writer.Allocating = .init(gpa);
                        defer query.deinit();
                        for (names.items, 0..) |name, i| {
                            if (i > 0) try query.writer.writeByte(' ');
                            try query.writer.writeAll(name);
                        }
                        try std.json.Stringify.value(query.written(), .{}, w);
                        try w.print(",\"limit\":{d}}}}}", .{names.items.len});
                        if (try convertToolsSelected(gpa, tools_json, compat, messages, names.items, false, true)) |loaded_tools| {
                            defer gpa.free(loaded_tools);
                            try w.writeAll(",{");
                            try w.writeAll("\"type\":\"tool_search_output\",\"call_id\":");
                            try std.json.Stringify.value(search_id, .{}, w);
                            try w.writeAll(",\"execution\":\"client\",\"status\":\"completed\",\"tools\":");
                            try w.writeAll(loaded_tools);
                            try w.writeAll("}");
                        }
                    }
                }
            }
            continue;
        }

        if (std.mem.eql(u8, msg.role, "assistant")) {
            const same_identity = msg.provider != null and msg.api != null and msg.model != null and
                std.mem.eql(u8, msg.provider.?, current_provider) and
                std.mem.eql(u8, msg.api.?, current_api) and
                std.mem.eql(u8, msg.model.?, current_model);
            if (same_identity) if (msg.thinking_signature) |signature| {
                _ = try writeReasoningSignature(gpa, w, signature, &first);
            };
            if (!same_identity and msg.thinking != null and msg.thinking.?.len > 0) {
                if (!first) try w.writeAll(",");
                first = false;
                try w.writeAll("{\"type\":\"message\",\"role\":\"assistant\",\"status\":\"completed\",\"id\":");
                const thinking_id = try std.fmt.allocPrint(gpa, "msg_pi_{d}_thinking", .{msg_index});
                defer gpa.free(thinking_id);
                try std.json.Stringify.value(thinking_id, .{}, w);
                try w.writeAll(",\"content\":[{\"type\":\"output_text\",\"text\":");
                try std.json.Stringify.value(msg.thinking.?, .{}, w);
                try w.writeAll(",\"annotations\":[]}]}");
            }
            if (msg.content.len > 0) {
                if (!first) try w.writeAll(",");
                first = false;
                try w.writeAll("{\"type\":\"message\",\"role\":\"assistant\",\"status\":\"completed\",\"id\":");
                const message_id = try std.fmt.allocPrint(gpa, "msg_pi_{d}", .{msg_index});
                defer gpa.free(message_id);
                try std.json.Stringify.value(message_id, .{}, w);
                try w.writeAll(",\"content\":[{\"type\":\"output_text\",\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeAll(",\"annotations\":[]}]}");
            }
            if (msg.tool_calls_json) |tool_json| try writeResponseToolCalls(gpa, w, tool_json, tools_json, compat.supports_openai_grammar_tools == true, &first);
            continue;
        }

        if (!first) try w.writeAll(",");
        first = false;
        const role = if (std.mem.eql(u8, msg.role, "system") and compat.supports_developer_role != false) "developer" else msg.role;
        try w.writeAll("{\"role\":");
        try std.json.Stringify.value(role, .{}, w);
        if (msg.hasImages()) {
            try w.writeAll(",\"content\":[{\"type\":\"input_text\",\"text\":");
            try std.json.Stringify.value(msg.content, .{}, w);
            try w.writeByte('}');
            var image_index: usize = 0;
            while (image_index < msg.imageCount()) : (image_index += 1) {
                const image = msg.imageAt(image_index).?;
                try w.writeAll(",{\"type\":\"input_image\",\"detail\":\"auto\",\"image_url\":");
                const data_url = try std.fmt.allocPrint(gpa, "data:{s};base64,{s}", .{ image.mime_type, image.data_b64 });
                defer gpa.free(data_url);
                try std.json.Stringify.value(data_url, .{}, w);
                try w.writeByte('}');
            }
            try w.writeByte(']');
        } else if (std.mem.eql(u8, role, "user")) {
            try w.writeAll(",\"content\":[{\"type\":\"input_text\",\"text\":");
            try std.json.Stringify.value(msg.content, .{}, w);
            try w.writeAll("}]");
        } else {
            try w.writeAll(",\"content\":");
            try std.json.Stringify.value(msg.content, .{}, w);
        }
        try w.writeAll("}");
    }
    try w.writeAll("]");
}

fn writeToolResultOutput(gpa: std.mem.Allocator, w: anytype, msg: ai.ChatMessage, supports_image_input: bool) !void {
    if (msg.hasImages()) {
        if (supports_image_input) {
            try w.writeByte('[');
            var first = true;
            if (msg.content.len > 0) {
                try w.writeAll("{\"type\":\"input_text\",\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeByte('}');
                first = false;
            }
            var image_index: usize = 0;
            while (image_index < msg.imageCount()) : (image_index += 1) {
                const image = msg.imageAt(image_index).?;
                if (!first) try w.writeByte(',');
                try w.writeAll("{\"type\":\"input_image\",\"detail\":\"auto\",\"image_url\":");
                const data_url = try std.fmt.allocPrint(gpa, "data:{s};base64,{s}", .{ image.mime_type, image.data_b64 });
                defer gpa.free(data_url);
                try std.json.Stringify.value(data_url, .{}, w);
                try w.writeByte('}');
                first = false;
            }
            try w.writeByte(']');
            return;
        }
        if (msg.content.len > 0) {
            try std.json.Stringify.value(msg.content, .{}, w);
        } else {
            try std.json.Stringify.value("(see attached image)", .{}, w);
        }
        return;
    }
    try std.json.Stringify.value(if (msg.content.len > 0) msg.content else "(no tool output)", .{}, w);
}

fn writeReasoningSignature(gpa: std.mem.Allocator, w: anytype, signature: []const u8, first: *bool) !bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, signature, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const typ = parsed.value.object.get("type") orelse return false;
    if (typ != .string or !std.mem.eql(u8, typ.string, "reasoning")) return false;
    if (!first.*) try w.writeAll(",");
    first.* = false;
    try std.json.Stringify.value(parsed.value, .{}, w);
    return true;
}

fn writeResponseToolCalls(
    gpa: std.mem.Allocator,
    w: anytype,
    raw: []const u8,
    tools_json: []const u8,
    supports_grammar: bool,
    first: *bool,
) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .array) return;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const id = item.object.get("id") orelse continue;
        const fn_obj = item.object.get("function") orelse continue;
        if (id != .string or fn_obj != .object) continue;
        const name = fn_obj.object.get("name") orelse continue;
        const args = fn_obj.object.get("arguments") orelse continue;
        if (name != .string or args != .string) continue;
        if (!first.*) try w.writeAll(",");
        first.* = false;
        const grammar_input = try constrained.extractGrammarInput(gpa, tools_json, supports_grammar, name.string, args.string);
        defer if (grammar_input) |input| gpa.free(input);
        try w.writeAll(if (grammar_input != null)
            "{\"type\":\"custom_tool_call\",\"call_id\":"
        else
            "{\"type\":\"function_call\",\"call_id\":");
        try std.json.Stringify.value(callIdOnly(id.string), .{}, w);
        try w.writeAll(",\"name\":");
        try std.json.Stringify.value(name.string, .{}, w);
        if (grammar_input) |input| {
            try w.writeAll(",\"input\":");
            try std.json.Stringify.value(input, .{}, w);
        } else {
            try w.writeAll(",\"arguments\":");
            try std.json.Stringify.value(args.string, .{}, w);
        }
        if (std.mem.indexOfScalar(u8, id.string, '|')) |sep| {
            const item_id = id.string[sep + 1 ..];
            if (item_id.len > 0 and (grammar_input != null or std.mem.startsWith(u8, item_id, "fc_"))) {
                try w.writeAll(",\"id\":");
                try std.json.Stringify.value(item_id, .{}, w);
            }
        }
        try w.writeAll("}");
    }
}

fn toolCallsContainName(gpa: std.mem.Allocator, raw: []const u8, wanted: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .array) return false;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_value = item.object.get("function") orelse continue;
        if (fn_value != .object) continue;
        const name = fn_value.object.get("name") orelse continue;
        if (name == .string and std.mem.eql(u8, name.string, wanted)) return true;
    }
    return false;
}

fn isDeferredTool(gpa: std.mem.Allocator, messages: []const ai.ChatMessage, name: []const u8) bool {
    var used = false;
    for (messages) |message| {
        if (std.mem.eql(u8, message.role, "assistant")) {
            if (message.tool_calls_json) |calls| {
                if (toolCallsContainName(gpa, calls, name)) used = true;
            }
        } else if (std.mem.eql(u8, message.role, "tool")) {
            for (message.added_tool_names) |added| {
                if (std.mem.eql(u8, added, name) and !used) return true;
            }
        }
    }
    return false;
}

fn nameInList(name: []const u8, names: []const []const u8) bool {
    for (names) |candidate| if (std.mem.eql(u8, candidate, name)) return true;
    return false;
}

fn convertToolsSelected(
    gpa: std.mem.Allocator,
    raw: []const u8,
    compat: metadata.Compat,
    messages: []const ai.ChatMessage,
    include_names: ?[]const []const u8,
    exclude_deferred: bool,
    defer_loading: bool,
) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .array) return null;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("[");
    var first = true;
    for (parsed.value.array.items) |item| {
        const fn_obj = constrained.functionSpec(item) orelse continue;
        const name = constrained.toolName(item) orelse continue;
        if (include_names) |names| {
            if (!nameInList(name, names)) continue;
        } else if (exclude_deferred and isDeferredTool(gpa, messages, name)) {
            continue;
        }
        if (!first) try out.writer.writeAll(",");
        first = false;
        if (try constrained.resolveGrammar(item, compat.supports_openai_grammar_tools == true)) |grammar| {
            try out.writer.writeAll("{\"type\":\"custom\",\"name\":");
            try std.json.Stringify.value(name, .{}, &out.writer);
            if (fn_obj.get("description")) |description| if (description == .string) {
                try out.writer.writeAll(",\"description\":");
                try std.json.Stringify.value(description.string, .{}, &out.writer);
            };
            try out.writer.writeAll(",\"format\":{\"type\":\"grammar\",\"syntax\":");
            try std.json.Stringify.value(grammar.syntax, .{}, &out.writer);
            try out.writer.writeAll(",\"definition\":");
            try std.json.Stringify.value(grammar.definition, .{}, &out.writer);
            try out.writer.writeAll("}");
            if (defer_loading) try out.writer.writeAll(",\"defer_loading\":true");
            try out.writer.writeAll("}");
        } else {
            const supports_strict = compat.supports_strict_mode == true;
            const strict = try constrained.resolveJsonSchemaStrict(item, supports_strict);
            try out.writer.writeAll("{\"type\":\"function\",\"name\":");
            try std.json.Stringify.value(name, .{}, &out.writer);
            if (fn_obj.get("description")) |description| if (description == .string) {
                try out.writer.writeAll(",\"description\":");
                try std.json.Stringify.value(description.string, .{}, &out.writer);
            };
            try out.writer.writeAll(",\"parameters\":");
            if (fn_obj.get("parameters")) |parameters| try std.json.Stringify.value(parameters, .{}, &out.writer) else try out.writer.writeAll("{\"type\":\"object\"}");
            if (supports_strict) {
                const strict_value = strict orelse if (fn_obj.get("strict")) |value| value == .bool and value.bool else false;
                try out.writer.print(",\"strict\":{s}", .{if (strict_value) "true" else "false"});
            }
            if (defer_loading) try out.writer.writeAll(",\"defer_loading\":true");
            try out.writer.writeAll("}");
        }
    }
    try out.writer.writeAll("]");
    if (first) {
        out.deinit();
        return null;
    }
    return try out.toOwnedSlice();
}

fn convertTools(gpa: std.mem.Allocator, raw: []const u8, compat: metadata.Compat) !?[]u8 {
    return convertToolsSelected(gpa, raw, compat, &.{}, null, false, false);
}

pub fn buildRequestBody(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    options: RequestOptions,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.writeAll(",\"input\":");
    try writeResponseInput(gpa, w, messages, tools_json, options.compat, options.provider_id, options.api_id, model, options.input_image);
    if (!hasSampling(options.sampling_params, "stream")) try w.print(",\"stream\":{s}", .{if (options.stream) "true" else "false"});
    if (!hasSampling(options.sampling_params, "store")) try w.writeAll(",\"store\":false");
    if (options.session_id) |sid| {
        if (!hasSampling(options.sampling_params, "prompt_cache_key")) {
            try w.writeAll(",\"prompt_cache_key\":");
            try std.json.Stringify.value(sid[0..@min(sid.len, 64)], .{}, w);
        }
        if (options.cache_retention == .long and options.compat.supports_long_cache_retention != false and !hasSampling(options.sampling_params, "prompt_cache_retention"))
            try w.writeAll(",\"prompt_cache_retention\":\"24h\"");
    } else if (options.cache_retention == .none and options.compat.supports_explicit_prompt_cache_mode == true and !hasSampling(options.sampling_params, "prompt_cache_options")) {
        try w.writeAll(",\"prompt_cache_options\":{\"mode\":\"explicit\"}");
    }
    if (options.max_tokens > 0 and !hasSampling(options.sampling_params, "max_output_tokens")) {
        try w.print(",\"max_output_tokens\":{d}", .{@max(options.max_tokens, MIN_OUTPUT_TOKENS)});
    }
    var emitted_reasoning_include = false;
    if (!hasSampling(options.sampling_params, "reasoning")) {
        if (requestedThinkingEffort(options)) |effort| {
            try w.writeAll(",\"reasoning\":{\"effort\":");
            try std.json.Stringify.value(effort, .{}, w);
            try w.writeAll(",\"summary\":\"auto\"},\"include\":[\"reasoning.encrypted_content\"]");
            emitted_reasoning_include = true;
        } else if (disabledThinkingEffort(options)) |effort| {
            try w.writeAll(",\"reasoning\":{\"effort\":");
            try std.json.Stringify.value(effort, .{}, w);
            try w.writeAll("}");
        }
    }
    if (options.reasoning and !emitted_reasoning_include and std.ascii.eqlIgnoreCase(options.provider_id, "xai") and !hasSampling(options.sampling_params, "include"))
        try w.writeAll(",\"include\":[\"reasoning.encrypted_content\"]");
    if (tools_json.len > 2) {
        const defer_tools = options.compat.supports_additional_tools == true or options.compat.supports_tool_search == true;
        if (try convertToolsSelected(gpa, tools_json, options.compat, messages, null, defer_tools, false)) |tools| {
            defer gpa.free(tools);
            try w.writeAll(",\"tools\":");
            try w.writeAll(tools);
        }
    }
    // Deliberately last: matches upstream samplingParams override semantics.
    for (options.sampling_params) |param| {
        try w.writeAll(",");
        try std.json.Stringify.value(param.name, .{}, w);
        try w.writeAll(":");
        try w.writeAll(param.value_json);
    }
    try w.writeAll("}");
    return try out.toOwnedSlice();
}

pub fn buildCodexRequestBody(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    options: RequestOptions,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    var instructions: []const u8 = "You are a helpful assistant.";
    var filtered: std.ArrayList(ai.ChatMessage) = .empty;
    defer filtered.deinit(gpa);
    for (messages) |msg| {
        if (std.mem.eql(u8, msg.role, "system") or std.mem.eql(u8, msg.role, "developer")) {
            if (msg.content.len > 0) instructions = msg.content;
            continue;
        }
        try filtered.append(gpa, msg);
    }
    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.writeAll(",\"store\":false");
    try w.print(",\"stream\":{s}", .{if (options.stream) "true" else "false"});
    try w.writeAll(",\"instructions\":");
    try std.json.Stringify.value(instructions, .{}, w);
    try w.writeAll(",\"input\":");
    try writeResponseInput(gpa, w, filtered.items, tools_json, options.compat, options.provider_id, options.api_id, model, options.input_image);
    try w.writeAll(",\"text\":{\"verbosity\":\"low\"}");
    try w.writeAll(",\"include\":[\"reasoning.encrypted_content\"]");
    if (options.session_id) |sid| {
        try w.writeAll(",\"prompt_cache_key\":");
        try std.json.Stringify.value(sid[0..@min(sid.len, 64)], .{}, w);
    }
    if (!hasSampling(options.sampling_params, "tool_choice")) try w.writeAll(",\"tool_choice\":\"auto\"");
    if (!hasSampling(options.sampling_params, "parallel_tool_calls")) try w.writeAll(",\"parallel_tool_calls\":true");
    if (!hasSampling(options.sampling_params, "reasoning")) if (requestedThinkingEffort(options)) |effort| {
        try w.writeAll(",\"reasoning\":{\"effort\":");
        try std.json.Stringify.value(effort, .{}, w);
        try w.writeAll(",\"summary\":\"auto\"}");
    };
    if (tools_json.len > 2) {
        const defer_tools = options.compat.supports_additional_tools == true or options.compat.supports_tool_search == true;
        if (try convertToolsSelected(gpa, tools_json, options.compat, filtered.items, null, defer_tools, false)) |tools| {
            defer gpa.free(tools);
            try w.writeAll(",\"tools\":");
            try w.writeAll(tools);
        }
    }
    for (options.sampling_params) |param| {
        try w.writeAll(",");
        try std.json.Stringify.value(param.name, .{}, w);
        try w.writeAll(":");
        try w.writeAll(param.value_json);
    }
    try w.writeAll("}");
    return out.toOwnedSlice();
}

fn jsonValueOwned(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn valueU64(value: ?std.json.Value) u64 {
    const v = value orelse return 0;
    if (v != .integer or v.integer < 0) return 0;
    return @intCast(v.integer);
}

fn responseServiceTier(value: std.json.Value) ServiceTier {
    if (value != .object) return .unknown;
    const tier = value.object.get("service_tier") orelse return .unknown;
    return if (tier == .string) serviceTierFromString(tier.string) else .unknown;
}

fn parseResponseServiceTier(gpa: std.mem.Allocator, raw: []const u8) ServiceTier {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return .unknown;
    defer parsed.deinit();
    return responseServiceTier(parsed.value);
}

pub fn parseUsage(value: std.json.Value) ai.Usage {
    if (value != .object) return .{};
    const prompt = valueU64(value.object.get("input_tokens"));
    const output = valueU64(value.object.get("output_tokens"));
    var cached: u64 = 0;
    var cache_write: u64 = 0;
    if (value.object.get("input_tokens_details")) |details| if (details == .object) {
        cached = valueU64(details.object.get("cached_tokens"));
        cache_write = valueU64(details.object.get("cache_write_tokens"));
    };
    const cache_read = if (cache_write > 0) cached -| @min(cached, cache_write) else cached;
    var reasoning: ?u64 = 0;
    if (value.object.get("output_tokens_details")) |details| if (details == .object) {
        reasoning = valueU64(details.object.get("reasoning_tokens"));
    };
    var usage: ai.Usage = .{
        .input = prompt -| @min(prompt, cache_read + cache_write),
        .output = output,
        .cache_read = cache_read,
        .cache_write = cache_write,
        .reasoning = reasoning,
    };
    usage.normalizeTotal();
    return usage;
}

fn combinedToolId(gpa: std.mem.Allocator, call_id: []const u8, item_id: ?[]const u8) ![]u8 {
    if (item_id) |iid| if (iid.len > 0) return try std.fmt.allocPrint(gpa, "{s}|{s}", .{ call_id, iid });
    return try gpa.dupe(u8, call_id);
}

pub fn parseResponse(gpa: std.mem.Allocator, raw: []const u8, provider_id: []const u8, fallback_model: []const u8) !ai.ModelResponse {
    return parseResponseConfigured(gpa, raw, provider_id, fallback_model, "[]", .{});
}

fn parseResponseConfigured(gpa: std.mem.Allocator, raw: []const u8, provider_id: []const u8, fallback_model: []const u8, tools_json: []const u8, compat: metadata.Compat) !ai.ModelResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(gpa);
    var thinking: std.ArrayList(u8) = .empty;
    errdefer thinking.deinit(gpa);
    var thinking_signature: []const u8 = "";
    errdefer if (thinking_signature.len > 0) gpa.free(thinking_signature);
    var calls: std.ArrayList(ai.ToolCall) = .empty;
    errdefer {
        for (calls.items) |*call| call.deinit(gpa);
        calls.deinit(gpa);
    }
    if (parsed.value.object.get("output")) |output| if (output == .array) {
        for (output.array.items) |item| {
            if (item != .object) continue;
            const typ = item.object.get("type") orelse continue;
            if (typ != .string) continue;
            if (std.mem.eql(u8, typ.string, "message")) {
                if (item.object.get("content")) |content| if (content == .array) {
                    for (content.array.items) |part| if (part == .object) {
                        const pt = part.object.get("type") orelse continue;
                        if (pt == .string and (std.mem.eql(u8, pt.string, "output_text") or std.mem.eql(u8, pt.string, "refusal"))) {
                            const value = part.object.get(if (std.mem.eql(u8, pt.string, "refusal")) "refusal" else "text") orelse continue;
                            if (value == .string) try text.appendSlice(gpa, value.string);
                        }
                    };
                };
            } else if (std.mem.eql(u8, typ.string, "reasoning")) {
                if (thinking_signature.len == 0) thinking_signature = try jsonValueOwned(gpa, item);
                if (item.object.get("summary")) |summary| {
                    if (summary == .array) {
                        for (summary.array.items) |part| {
                            if (part != .object) continue;
                            const tx = part.object.get("text") orelse continue;
                            if (tx != .string) continue;
                            if (thinking.items.len > 0) try thinking.appendSlice(gpa, "\n\n");
                            try thinking.appendSlice(gpa, tx.string);
                        }
                    }
                }
            } else if (std.mem.eql(u8, typ.string, "function_call")) {
                const call_id = item.object.get("call_id") orelse continue;
                const name = item.object.get("name") orelse continue;
                const args = item.object.get("arguments") orelse continue;
                if (call_id != .string or name != .string or args != .string) continue;
                const item_id: ?[]const u8 = if (item.object.get("id")) |id| if (id == .string) id.string else null else null;
                try calls.append(gpa, .{
                    .id = try combinedToolId(gpa, call_id.string, item_id),
                    .name = try gpa.dupe(u8, name.string),
                    .arguments = try gpa.dupe(u8, args.string),
                });
            } else if (std.mem.eql(u8, typ.string, "custom_tool_call")) {
                const call_id = item.object.get("call_id") orelse continue;
                const name = item.object.get("name") orelse continue;
                const input = item.object.get("input") orelse continue;
                if (call_id != .string or name != .string or input != .string) continue;
                const item_id: ?[]const u8 = if (item.object.get("id")) |id| if (id == .string) id.string else null else null;
                const args = (try constrained.normalizeGrammarArguments(gpa, tools_json, compat.supports_openai_grammar_tools == true, name.string, input.string)) orelse try constrained.wrapGrammarInput(gpa, "input", input.string);
                defer gpa.free(args);
                try calls.append(gpa, .{
                    .id = try combinedToolId(gpa, call_id.string, item_id),
                    .name = try gpa.dupe(u8, name.string),
                    .arguments = try gpa.dupe(u8, args),
                });
            }
        }
    };
    var usage: ai.Usage = .{};
    if (parsed.value.object.get("usage")) |u| usage = parseUsage(u);
    var response_id: []const u8 = "";
    if (parsed.value.object.get("id")) |id| {
        if (id == .string and id.string.len > 0) response_id = try gpa.dupe(u8, id.string);
    }
    var response_model: []const u8 = "";
    if (parsed.value.object.get("model")) |m| {
        if (m == .string and m.string.len > 0 and !std.mem.eql(u8, m.string, fallback_model)) response_model = try gpa.dupe(u8, m.string);
    }
    var stop: []const u8 = if (calls.items.len > 0) "toolUse" else "stop";
    var raw_stop_reason: []const u8 = "";
    if (parsed.value.object.get("status")) |status| if (status == .string) {
        var incomplete_reason: []const u8 = "";
        if (std.mem.eql(u8, status.string, "incomplete")) {
            stop = "error";
            if (parsed.value.object.get("incomplete_details")) |details| {
                if (details == .object) {
                    if (details.object.get("reason")) |reason| {
                        if (reason == .string) {
                            incomplete_reason = reason.string;
                            if (std.mem.eql(u8, reason.string, "max_output_tokens")) stop = "length";
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, status.string, "failed")) stop = "error";
        raw_stop_reason = if (incomplete_reason.len > 0)
            try std.fmt.allocPrint(gpa, "{s}.{s}", .{ status.string, incomplete_reason })
        else
            try gpa.dupe(u8, status.string);
    };
    return .{
        .content = try text.toOwnedSlice(gpa),
        .thinking = if (thinking.items.len > 0) try thinking.toOwnedSlice(gpa) else "",
        .thinking_signature = thinking_signature,
        .tool_calls = try calls.toOwnedSlice(gpa),
        .provider = try gpa.dupe(u8, provider_id),
        .model = try gpa.dupe(u8, fallback_model),
        .response_id = response_id,
        .response_model = response_model,
        .raw_stop_reason = raw_stop_reason,
        .stop_reason = try gpa.dupe(u8, stop),
        .usage = usage,
    };
}

const ToolSlot = struct {
    output_index: u64,
    id: []u8,
};

const ResponsesLive = struct {
    gpa: std.mem.Allocator,
    writer: std.Io.Writer,
    buf: [4096]u8 = undefined,
    line: std.ArrayList(u8) = .empty,
    body: std.ArrayList(u8) = .empty,
    text: std.ArrayList(u8) = .empty,
    thinking: std.ArrayList(u8) = .empty,
    tool_ids: std.ArrayList([]u8) = .empty,
    tool_names: std.ArrayList([]u8) = .empty,
    tool_args: std.ArrayList(std.ArrayList(u8)) = .empty,
    slots: std.ArrayList(ToolSlot) = .empty,
    usage: ai.Usage = .{},
    service_tier: ServiceTier = .unknown,
    stop_reason: []const u8 = "",
    response_id: []u8 = &.{},
    response_model: []u8 = &.{},
    diagnostics_json: []u8 = &.{},
    error_message: []u8 = &.{},
    raw_stop_reason: []u8 = &.{},
    reasoning_signature: []u8 = &.{},
    reasoning_id: []u8 = &.{},
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    streaming: bool,
    abort_flag: ?*bool,
    aborted: bool = false,
    /// Parsed terminal SSE event; used by Codex HTTP to stop before TCP EOF.
    terminal: bool = false,
    grammar_tools_json: []const u8 = "[]",
    supports_grammar: bool = false,
    /// Codex transport treats malformed event JSON as a protocol error.
    strict_codex_json: bool = false,

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = std.Io.Writer.noopFlush };

    fn init(gpa: std.mem.Allocator, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque, streaming: bool, abort_flag: ?*bool) ResponsesLive {
        return .{
            .gpa = gpa,
            .writer = .{ .vtable = &vtable, .buffer = &.{}, .end = 0 },
            .on_delta = on_delta,
            .delta_ctx = delta_ctx,
            .streaming = streaming,
            .abort_flag = abort_flag,
        };
    }

    fn attachBuffer(self: *ResponsesLive) void {
        self.writer.buffer = &self.buf;
        self.writer.end = 0;
    }

    fn clearTools(self: *ResponsesLive) void {
        for (self.tool_ids.items) |id| self.gpa.free(id);
        self.tool_ids.clearRetainingCapacity();
        for (self.tool_names.items) |name| self.gpa.free(name);
        self.tool_names.clearRetainingCapacity();
        for (self.tool_args.items) |*args| args.deinit(self.gpa);
        self.tool_args.clearRetainingCapacity();
        for (self.slots.items) |slot| self.gpa.free(slot.id);
        self.slots.clearRetainingCapacity();
    }

    fn resetForRetry(self: *ResponsesLive) void {
        self.line.clearRetainingCapacity();
        self.body.clearRetainingCapacity();
        self.text.clearRetainingCapacity();
        self.thinking.clearRetainingCapacity();
        self.clearTools();
        self.usage = .{};
        self.service_tier = .unknown;
        self.stop_reason = "";
        if (self.response_id.len > 0) self.gpa.free(self.response_id);
        if (self.response_model.len > 0) self.gpa.free(self.response_model);
        // Preserve transport diagnostics across WebSocket -> SSE retry.
        if (self.error_message.len > 0) self.gpa.free(self.error_message);
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        if (self.reasoning_signature.len > 0) self.gpa.free(self.reasoning_signature);
        if (self.reasoning_id.len > 0) self.gpa.free(self.reasoning_id);
        self.response_id = &.{};
        self.response_model = &.{};
        self.error_message = &.{};
        self.raw_stop_reason = &.{};
        self.reasoning_signature = &.{};
        self.reasoning_id = &.{};
        self.aborted = false;
        self.terminal = false;
        self.writer.end = 0;
    }

    fn deinit(self: *ResponsesLive) void {
        self.line.deinit(self.gpa);
        self.body.deinit(self.gpa);
        self.text.deinit(self.gpa);
        self.thinking.deinit(self.gpa);
        if (self.response_id.len > 0) self.gpa.free(self.response_id);
        if (self.response_model.len > 0) self.gpa.free(self.response_model);
        if (self.diagnostics_json.len > 0) self.gpa.free(self.diagnostics_json);
        if (self.error_message.len > 0) self.gpa.free(self.error_message);
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        if (self.reasoning_signature.len > 0) self.gpa.free(self.reasoning_signature);
        if (self.reasoning_id.len > 0) self.gpa.free(self.reasoning_id);
        self.clearTools();
        self.tool_ids.deinit(self.gpa);
        self.tool_names.deinit(self.gpa);
        self.tool_args.deinit(self.gpa);
        self.slots.deinit(self.gpa);
        self.* = undefined;
    }

    fn setTransportDiagnostic(self: *ResponsesLive, io: Io, code: []const u8, transport: codex_ws.Transport, fallback_transport: ?[]const u8, events_emitted: bool, request_bytes: usize) !void {
        const encoded = try transportDiagnosticJson(self.gpa, io, code, transport, fallback_transport, events_emitted, request_bytes);
        if (self.diagnostics_json.len > 0) self.gpa.free(self.diagnostics_json);
        self.diagnostics_json = encoded;
    }

    fn setErrorMessage(self: *ResponsesLive, message: []const u8) !void {
        if (self.error_message.len > 0) self.gpa.free(self.error_message);
        self.error_message = try self.gpa.dupe(u8, message);
    }

    fn captureApiError(self: *ResponsesLive, event: std.json.Value) !void {
        if (event != .object) return;
        const typ = event.object.get("type") orelse return;
        if (typ != .string) return;
        var code: ?[]const u8 = null;
        var message: ?[]const u8 = null;
        if (event.object.get("code")) |v| {
            if (v == .string) code = v.string;
        }
        if (event.object.get("message")) |v| {
            if (v == .string) message = v.string;
        }
        if (event.object.get("error")) |err_v| {
            if (err_v == .object) {
                if (code == null) {
                    if (err_v.object.get("code")) |v| if (v == .string) {
                        code = v.string;
                    };
                }
                if (message == null) {
                    if (err_v.object.get("message")) |v| if (v == .string) {
                        message = v.string;
                    };
                }
            }
        }
        if (std.mem.eql(u8, typ.string, "response.failed")) {
            if (event.object.get("response")) |response| {
                if (response == .object) {
                    if (response.object.get("error")) |err_v| {
                        if (err_v == .object) {
                            if (code == null) {
                                if (err_v.object.get("code")) |v| if (v == .string) {
                                    code = v.string;
                                };
                            }
                            if (message == null) {
                                if (err_v.object.get("message")) |v| if (v == .string) {
                                    message = v.string;
                                };
                            }
                        }
                    }
                }
            }
            try self.setErrorMessage(message orelse code orelse "Codex response failed");
        } else {
            const detail = message orelse code orelse "Codex API error";
            const formatted = try std.fmt.allocPrint(self.gpa, "Codex error: {s}", .{detail});
            defer self.gpa.free(formatted);
            try self.setErrorMessage(formatted);
        }
        self.stop_reason = "error";
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        self.raw_stop_reason = try self.gpa.dupe(u8, code orelse typ.string);
        self.terminal = true;
    }

    fn started(self: *const ResponsesLive) bool {
        return self.text.items.len > 0 or self.thinking.items.len > 0 or self.tool_ids.items.len > 0 or self.response_id.len > 0;
    }

    fn flushWriterBuffer(self: *ResponsesLive) !void {
        if (self.writer.end > 0) {
            try self.feed(self.writer.buffer[0..self.writer.end]);
            self.writer.end = 0;
        }
    }

    fn flushTrailing(self: *ResponsesLive) !void {
        try self.flushWriterBuffer();
        if (self.streaming and self.line.items.len > 0) {
            try self.handleLine(self.line.items);
            self.line.clearRetainingCapacity();
        }
    }

    fn feed(self: *ResponsesLive, chunk: []const u8) !void {
        if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) {
            self.aborted = true;
            return error.WriteFailed;
        };
        try self.body.appendSlice(self.gpa, chunk);
        if (!self.streaming) return;
        for (chunk) |byte| {
            if (byte == '\n') {
                try self.handleLine(self.line.items);
                self.line.clearRetainingCapacity();
            } else if (byte != '\r') try self.line.append(self.gpa, byte);
        }
    }

    fn toolIndexById(self: *ResponsesLive, id: []const u8) ?usize {
        for (self.tool_ids.items, 0..) |existing, i| if (std.mem.eql(u8, existing, id)) return i;
        return null;
    }

    fn slotId(self: *ResponsesLive, output_index: u64) ?[]const u8 {
        for (self.slots.items) |slot| if (slot.output_index == output_index) return slot.id;
        return null;
    }

    fn addTool(self: *ResponsesLive, output_index: u64, item: std.json.Value) !void {
        if (item != .object) return;
        const call = item.object.get("call_id") orelse return;
        const name = item.object.get("name") orelse return;
        if (call != .string or name != .string) return;
        const item_id: ?[]const u8 = if (item.object.get("id")) |id| if (id == .string) id.string else null else null;
        const id = try combinedToolId(self.gpa, call.string, item_id);
        errdefer self.gpa.free(id);
        try self.tool_ids.append(self.gpa, id);
        try self.tool_names.append(self.gpa, try self.gpa.dupe(u8, name.string));
        try self.tool_args.append(self.gpa, .empty);
        try self.slots.append(self.gpa, .{ .output_index = output_index, .id = try self.gpa.dupe(u8, id) });
        var delta = ai.StreamDelta{ .kind = .tool_call_delta, .tool_call_id = id, .tool_name = name.string };
        const initial = item.object.get("arguments") orelse item.object.get("input");
        if (initial) |args| if (args == .string and args.string.len > 0) {
            try self.tool_args.items[self.tool_args.items.len - 1].appendSlice(self.gpa, args.string);
            delta.tool_arguments = args.string;
        };
        if (self.on_delta) |handler| handler(self.delta_ctx, delta);
    }

    fn appendToolArgs(self: *ResponsesLive, output_index: u64, fragment: []const u8) !void {
        const id = self.slotId(output_index) orelse return;
        const idx = self.toolIndexById(id) orelse return;
        try self.tool_args.items[idx].appendSlice(self.gpa, fragment);
        if (self.on_delta) |handler| handler(self.delta_ctx, .{ .kind = .tool_call_delta, .tool_call_id = id, .tool_arguments = fragment });
    }

    fn captureReasoningItem(self: *ResponsesLive, item: std.json.Value) !void {
        if (item != .object) return;
        const typ = item.object.get("type") orelse return;
        if (typ != .string or !std.mem.eql(u8, typ.string, "reasoning")) return;
        if (item.object.get("id")) |id| if (id == .string and id.string.len > 0) {
            if (self.reasoning_id.len == 0) {
                self.reasoning_id = try self.gpa.dupe(u8, id.string);
            } else if (!std.mem.eql(u8, self.reasoning_id, id.string)) {
                return;
            }
        };
        const serialized = try jsonValueOwned(self.gpa, item);
        if (self.reasoning_signature.len > 0) self.gpa.free(self.reasoning_signature);
        self.reasoning_signature = serialized;
    }

    fn backfillReasoning(self: *ResponsesLive, response: std.json.Value) !void {
        if (response != .object) return;
        const output = response.object.get("output") orelse return;
        if (output != .array) return;
        for (output.array.items) |item| {
            if (item != .object) continue;
            const typ = item.object.get("type") orelse continue;
            if (typ != .string or !std.mem.eql(u8, typ.string, "reasoning")) continue;
            const encrypted = item.object.get("encrypted_content") orelse continue;
            if (encrypted != .string or encrypted.string.len == 0) continue;
            if (self.reasoning_id.len > 0) {
                const id = item.object.get("id") orelse continue;
                if (id != .string or !std.mem.eql(u8, id.string, self.reasoning_id)) continue;
            }
            try self.captureReasoningItem(item);
            return;
        }
    }

    fn finalizeIdentity(self: *ResponsesLive, response: std.json.Value) !void {
        if (response != .object) return;
        if (response.object.get("id")) |id| if (id == .string and id.string.len > 0 and self.response_id.len == 0) {
            self.response_id = try self.gpa.dupe(u8, id.string);
        };
        if (response.object.get("model")) |model| if (model == .string and model.string.len > 0 and self.response_model.len == 0) {
            self.response_model = try self.gpa.dupe(u8, model.string);
        };
        const tier = responseServiceTier(response);
        if (tier != .unknown) self.service_tier = tier;
    }

    fn finalizeStatus(self: *ResponsesLive, response: std.json.Value) !void {
        if (response != .object) return;
        try self.backfillReasoning(response);
        if (response.object.get("id")) |id| if (id == .string and id.string.len > 0) {
            if (self.response_id.len > 0) self.gpa.free(self.response_id);
            self.response_id = try self.gpa.dupe(u8, id.string);
        };
        if (response.object.get("model")) |model| if (model == .string and model.string.len > 0) {
            if (self.response_model.len > 0) self.gpa.free(self.response_model);
            self.response_model = try self.gpa.dupe(u8, model.string);
        };
        const tier = responseServiceTier(response);
        if (tier != .unknown) self.service_tier = tier;
        if (response.object.get("usage")) |u| self.usage = parseUsage(u);
        const status = response.object.get("status") orelse return;
        if (status != .string) return;
        var incomplete_reason: []const u8 = "";
        if (std.mem.eql(u8, status.string, "completed")) {
            self.stop_reason = if (self.tool_ids.items.len > 0) "toolUse" else "stop";
        } else if (std.mem.eql(u8, status.string, "incomplete")) {
            self.stop_reason = "error";
            if (response.object.get("incomplete_details")) |details| {
                if (details == .object) {
                    if (details.object.get("reason")) |reason| {
                        if (reason == .string) {
                            incomplete_reason = reason.string;
                            if (std.mem.eql(u8, reason.string, "max_output_tokens")) self.stop_reason = "length";
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, status.string, "failed")) self.stop_reason = "error";
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        self.raw_stop_reason = if (incomplete_reason.len > 0)
            try std.fmt.allocPrint(self.gpa, "{s}.{s}", .{ status.string, incomplete_reason })
        else
            try self.gpa.dupe(u8, status.string);
    }

    fn handleLine(self: *ResponsesLive, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \\t");
        if (!std.mem.startsWith(u8, trimmed, "data:")) return;
        const data = std.mem.trim(u8, trimmed["data:".len..], " \\t");
        return self.handleEventJson(data);
    }

    fn handleEventJson(self: *ResponsesLive, data: []const u8) !void {
        if (data.len == 0 or std.mem.eql(u8, data, "[DONE]")) return;
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, data, .{}) catch {
            if (!self.strict_codex_json) return;
            try self.setErrorMessage("Invalid Codex response event JSON");
            self.stop_reason = "error";
            if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
            self.raw_stop_reason = try self.gpa.dupe(u8, "CodexProtocolError");
            self.terminal = true;
            return error.CodexProtocolError;
        };
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const type_v = parsed.value.object.get("type") orelse return;
        if (type_v != .string) return;
        const typ = type_v.string;
        if (std.mem.eql(u8, typ, "response.created")) {
            if (parsed.value.object.get("response")) |response| try self.finalizeIdentity(response);
        } else if (std.mem.eql(u8, typ, "response.reasoning_summary_text.delta") or std.mem.eql(u8, typ, "response.reasoning_text.delta")) {
            const delta = parsed.value.object.get("delta") orelse return;
            if (delta != .string) return;
            try self.thinking.appendSlice(self.gpa, delta.string);
            if (self.on_delta) |handler| handler(self.delta_ctx, .{ .kind = .thinking_delta, .thinking = delta.string });
        } else if (std.mem.eql(u8, typ, "response.reasoning_summary_part.done")) {
            try self.thinking.appendSlice(self.gpa, "\n\n");
            if (self.on_delta) |handler| handler(self.delta_ctx, .{ .kind = .thinking_delta, .thinking = "\n\n" });
        } else if (std.mem.eql(u8, typ, "response.output_text.delta") or std.mem.eql(u8, typ, "response.refusal.delta")) {
            const delta = parsed.value.object.get("delta") orelse return;
            if (delta != .string) return;
            try self.text.appendSlice(self.gpa, delta.string);
            if (self.on_delta) |handler| handler(self.delta_ctx, .{ .kind = .text_delta, .text = delta.string });
        } else if (std.mem.eql(u8, typ, "response.output_item.added")) {
            const index = valueU64(parsed.value.object.get("output_index"));
            const item = parsed.value.object.get("item") orelse return;
            try self.captureReasoningItem(item);
            if (item == .object) {
                const item_type = item.object.get("type") orelse return;
                if (item_type == .string and (std.mem.eql(u8, item_type.string, "function_call") or std.mem.eql(u8, item_type.string, "custom_tool_call"))) try self.addTool(index, item);
            }
        } else if (std.mem.eql(u8, typ, "response.output_item.done")) {
            const item = parsed.value.object.get("item") orelse return;
            try self.captureReasoningItem(item);
        } else if (std.mem.eql(u8, typ, "response.function_call_arguments.delta")) {
            const index = valueU64(parsed.value.object.get("output_index"));
            const delta = parsed.value.object.get("delta") orelse return;
            if (delta == .string) try self.appendToolArgs(index, delta.string);
        } else if (std.mem.eql(u8, typ, "response.function_call_arguments.done")) {
            const index = valueU64(parsed.value.object.get("output_index"));
            const args = parsed.value.object.get("arguments") orelse return;
            if (args == .string) {
                const id = self.slotId(index) orelse return;
                const idx = self.toolIndexById(id) orelse return;
                if (!std.mem.eql(u8, self.tool_args.items[idx].items, args.string)) {
                    self.tool_args.items[idx].clearRetainingCapacity();
                    try self.tool_args.items[idx].appendSlice(self.gpa, args.string);
                }
            }
        } else if (std.mem.eql(u8, typ, "response.custom_tool_call_input.delta")) {
            const index = valueU64(parsed.value.object.get("output_index"));
            const delta = parsed.value.object.get("delta") orelse return;
            if (delta == .string) try self.appendToolArgs(index, delta.string);
        } else if (std.mem.eql(u8, typ, "response.custom_tool_call_input.done")) {
            const index = valueU64(parsed.value.object.get("output_index"));
            const input = parsed.value.object.get("input") orelse return;
            if (input == .string) {
                const id = self.slotId(index) orelse return;
                const idx = self.toolIndexById(id) orelse return;
                self.tool_args.items[idx].clearRetainingCapacity();
                try self.tool_args.items[idx].appendSlice(self.gpa, input.string);
            }
        } else if (std.mem.eql(u8, typ, "response.completed") or std.mem.eql(u8, typ, "response.done") or std.mem.eql(u8, typ, "response.incomplete")) {
            if (parsed.value.object.get("response")) |response| try self.finalizeStatus(response);
            self.terminal = true;
        } else if (std.mem.eql(u8, typ, "response.failed")) {
            if (parsed.value.object.get("response")) |response| try self.finalizeStatus(response);
            try self.captureApiError(parsed.value);
        } else if (std.mem.eql(u8, typ, "error")) {
            try self.captureApiError(parsed.value);
        }
    }

    fn finish(self: *ResponsesLive, provider: []const u8, model: []const u8) !ai.ModelResponse {
        var calls = try self.gpa.alloc(ai.ToolCall, self.tool_ids.items.len);
        errdefer self.gpa.free(calls);
        for (self.tool_ids.items, 0..) |id, i| {
            const name = self.tool_names.items[i];
            const raw_args = self.tool_args.items[i].items;
            const normalized = try constrained.normalizeGrammarArguments(self.gpa, self.grammar_tools_json, self.supports_grammar, name, raw_args);
            calls[i] = .{
                .id = try self.gpa.dupe(u8, id),
                .name = try self.gpa.dupe(u8, name),
                .arguments = if (normalized) |value| value else try self.gpa.dupe(u8, raw_args),
            };
        }
        return .{
            .content = try self.gpa.dupe(u8, self.text.items),
            .thinking = if (self.thinking.items.len > 0) try self.gpa.dupe(u8, self.thinking.items) else "",
            .thinking_signature = if (self.reasoning_signature.len > 0) try self.gpa.dupe(u8, self.reasoning_signature) else "",
            .tool_calls = calls,
            .provider = try self.gpa.dupe(u8, provider),
            .model = try self.gpa.dupe(u8, model),
            .response_id = if (self.response_id.len > 0) try self.gpa.dupe(u8, self.response_id) else "",
            .response_model = if (self.response_model.len > 0 and !std.mem.eql(u8, self.response_model, model)) try self.gpa.dupe(u8, self.response_model) else "",
            .diagnostics_json = if (self.diagnostics_json.len > 0) try self.gpa.dupe(u8, self.diagnostics_json) else "",
            .error_message = if (self.error_message.len > 0) try self.gpa.dupe(u8, self.error_message) else "",
            .raw_stop_reason = if (self.raw_stop_reason.len > 0) try self.gpa.dupe(u8, self.raw_stop_reason) else "",
            .stop_reason = try self.gpa.dupe(u8, if (self.stop_reason.len > 0) self.stop_reason else if (calls.len > 0) "toolUse" else "stop"),
            .usage = self.usage,
        };
    }

    fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *ResponsesLive = @fieldParentPtr("writer", writer);
        if (writer.end > 0) {
            self.feed(writer.buffer[0..writer.end]) catch return error.WriteFailed;
            writer.end = 0;
        }
        if (data.len == 0) return 0;
        var total: usize = 0;
        for (data[0 .. data.len - 1]) |part| {
            self.feed(part) catch return error.WriteFailed;
            total += part.len;
        }
        const pattern = data[data.len - 1];
        var count = splat;
        while (count > 0) : (count -= 1) {
            self.feed(pattern) catch return error.WriteFailed;
            total += pattern.len;
        }
        return total;
    }
};

test "Responses omitted compat defaults developer strict off and long cache on" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "instructions" },
        .{ .role = "user", .content = "hi" },
    };
    const tools =
        \\[{"type":"function","function":{"name":"read","parameters":{"type":"object","properties":{}},"strict":true}}]
    ;
    const body = try buildRequestBody(gpa, "m", &messages, tools, .{
        .session_id = "session",
        .cache_retention = .long,
    });
    defer gpa.free(body);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    const input = parsed.value.object.get("input").?.array.items;
    try std.testing.expectEqualStrings("developer", input[0].object.get("role").?.string);
    try std.testing.expect(parsed.value.object.get("prompt_cache_retention") != null);
    const tool = parsed.value.object.get("tools").?.array.items[0].object;
    try std.testing.expect(tool.get("strict") == null);
}

test "Responses request uses input replay, tools, minimum tokens and reasoning" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "hello" },
        .{ .role = "assistant", .content = "", .tool_calls_json = "[{\"id\":\"call_1|fc_1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"a\\\"}\"}}]" },
        .{ .role = "tool", .content = "ok", .tool_call_id = "call_1|fc_1", .tool_name = "read" },
    };
    const tools = "[{\"type\":\"function\",\"function\":{\"name\":\"read\",\"description\":\"read\",\"parameters\":{\"type\":\"object\"}}}]";
    const body = try buildRequestBody(gpa, "gpt-x", &messages, tools, .{
        .stream = true,
        .thinking = .high,
        .max_tokens = 8,
        .compat = .{ .supports_developer_role = true },
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"max_output_tokens\":16") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"developer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"function_call_output\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"call_id\":\"call_1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning\":{\"effort\":\"high\"") != null);
}

test "Responses nonstream parser extracts function call and accounting" {
    const gpa = std.testing.allocator;
    const raw =
        \\{"id":"resp_1","model":"gpt-r","status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello"}]},{"type":"function_call","id":"fc_abc","call_id":"call_abc","name":"read","arguments":"{\"path\":\"a\"}"}],"usage":{"input_tokens":100,"input_tokens_details":{"cached_tokens":20},"output_tokens":30,"output_tokens_details":{"reasoning_tokens":7}}}
    ;
    var response = try parseResponse(gpa, raw, "corp", "fallback");
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("hello", response.content);
    try std.testing.expectEqual(@as(usize, 1), response.tool_calls.len);
    try std.testing.expectEqualStrings("call_abc|fc_abc", response.tool_calls[0].id);
    try std.testing.expectEqual(@as(u64, 80), response.usage.input);
    try std.testing.expectEqual(@as(u64, 20), response.usage.cache_read);
    try std.testing.expectEqual(@as(?u64, 7), response.usage.reasoning);
    try std.testing.expectEqualStrings("fallback", response.model);
    try std.testing.expectEqualStrings("gpt-r", response.response_model);
    try std.testing.expectEqualStrings("resp_1", response.response_id);
    try std.testing.expectEqualStrings("completed", response.raw_stop_reason);
}

test "Responses incomplete max output maps to length" {
    const gpa = std.testing.allocator;
    const raw =
        \\{"model":"m","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[],"usage":{"input_tokens":1,"output_tokens":16}}
    ;
    var response = try parseResponse(gpa, raw, "openai", "m");
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("length", response.stop_reason);
    try std.testing.expectEqualStrings("incomplete.max_output_tokens", response.raw_stop_reason);
}

test "Responses parser and stream retain reasoning summary text" {
    const gpa = std.testing.allocator;
    const raw =
        \\{"model":"r","status":"completed","output":[{"type":"reasoning","summary":[{"type":"summary_text","text":"first"},{"type":"summary_text","text":"second"}]},{"type":"message","content":[{"type":"output_text","text":"answer"}]}]}
    ;
    var response = try parseResponse(gpa, raw, "openai", "r");
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("first\n\nsecond", response.thinking);
    try std.testing.expect(std.mem.indexOf(u8, response.thinking_signature, "\"type\":\"reasoning\"") != null);

    var live = ResponsesLive.init(gpa, null, null, true, null);
    live.attachBuffer();
    defer live.deinit();
    try live.writer.writeAll(
        "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_stream\",\"summary\":[]}}\n\n" ++
            "data: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":0,\"delta\":\"plan \"}\n\n" ++
            "data: {\"type\":\"response.reasoning_text.delta\",\"output_index\":0,\"delta\":\"step\"}\n\n" ++
            "data: {\"type\":\"response.output_text.delta\",\"output_index\":1,\"delta\":\"done\"}\n\n" ++
            "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_stream\",\"model\":\"routed-r\",\"status\":\"completed\",\"output\":[{\"type\":\"reasoning\",\"id\":\"rs_stream\",\"encrypted_content\":\"enc-final\",\"summary\":[]}]}}\n\n",
    );
    try live.flushTrailing();
    var streamed = try live.finish("openai", "r");
    defer streamed.deinit(gpa);
    try std.testing.expectEqualStrings("plan step", streamed.thinking);
    try std.testing.expectEqualStrings("done", streamed.content);
    try std.testing.expectEqualStrings("resp_stream", streamed.response_id);
    try std.testing.expectEqualStrings("routed-r", streamed.response_model);
    try std.testing.expectEqualStrings("completed", streamed.raw_stop_reason);
    try std.testing.expect(std.mem.indexOf(u8, streamed.thinking_signature, "enc-final") != null);
}

test "Responses reasoning replay is identity gated and cross-model degrades to text" {
    const gpa = std.testing.allocator;
    const signature = "{\"type\":\"reasoning\",\"id\":\"rs_1\",\"encrypted_content\":\"cipher\",\"summary\":[]}";
    const same = [_]ai.ChatMessage{.{
        .role = "assistant",
        .content = "answer",
        .thinking = "private summary",
        .thinking_signature = signature,
        .provider = "openai",
        .api = "openai-responses",
        .model = "gpt-r",
    }};
    const same_body = try buildRequestBody(gpa, "gpt-r", &same, "[]", .{});
    defer gpa.free(same_body);
    try std.testing.expect(std.mem.indexOf(u8, same_body, "\"type\":\"reasoning\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, same_body, "cipher") != null);
    try std.testing.expect(std.mem.indexOf(u8, same_body, "private summary") == null);
    try std.testing.expect(std.mem.indexOf(u8, same_body, "msg_pi_0") != null);

    var cross = same;
    cross[0].model = "old-model";
    const cross_body = try buildRequestBody(gpa, "gpt-r", &cross, "[]", .{});
    defer gpa.free(cross_body);
    try std.testing.expect(std.mem.indexOf(u8, cross_body, "cipher") == null);
    try std.testing.expect(std.mem.indexOf(u8, cross_body, "private summary") != null);
    try std.testing.expect(std.mem.indexOf(u8, cross_body, "msg_pi_0_thinking") != null);
}

test "responses cache modes and codex request shape" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system instructions" },
        .{ .role = "user", .content = "hello" },
    };
    const none_body = try buildRequestBody(gpa, "m", &msgs, "[]", .{
        .cache_retention = .none,
        .compat = .{ .supports_explicit_prompt_cache_mode = true },
    });
    defer gpa.free(none_body);
    try std.testing.expect(std.mem.indexOf(u8, none_body, "\"prompt_cache_options\":{\"mode\":\"explicit\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, none_body, "prompt_cache_key") == null);

    const codex = try buildCodexRequestBody(gpa, "gpt-5", &msgs, "[]", .{
        .stream = true,
        .thinking = .high,
        .session_id = "session-123",
    });
    defer gpa.free(codex);
    try std.testing.expect(std.mem.indexOf(u8, codex, "\"instructions\":\"system instructions\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, codex, "\"prompt_cache_key\":\"session-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, codex, "\"tool_choice\":\"auto\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, codex, "\"parallel_tool_calls\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, codex, "\"include\":[\"reasoning.encrypted_content\"]") != null);
    // System prompt is instructions, not duplicated in Codex input.
    try std.testing.expect(std.mem.indexOf(u8, codex, "\"role\":\"system\"") == null);
}

test "codex URL and JWT account extraction" {
    const gpa = std.testing.allocator;
    const a = try resolveCodexUrl(gpa, "https://chatgpt.com/backend-api");
    defer gpa.free(a);
    try std.testing.expectEqualStrings("https://chatgpt.com/backend-api/codex/responses", a);
    const b = try resolveCodexUrl(gpa, "https://example.test/codex/");
    defer gpa.free(b);
    try std.testing.expectEqualStrings("https://example.test/codex/responses", b);
    // payload: {"https://api.openai.com/auth":{"chatgpt_account_id":"acct-42"}}
    const token = "e30.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdC00MiJ9fQ.sig";
    const account = try extractCodexAccountId(gpa, token);
    defer gpa.free(account);
    try std.testing.expectEqualStrings("acct-42", account);
}

test "Responses deferred tools load at addedToolNames boundary" {
    const gpa = std.testing.allocator;
    const tools =
        \\[{"type":"function","function":{"name":"immediate","description":"now","parameters":{"type":"object"}}},{"type":"function","function":{"name":"late_tool","description":"later","parameters":{"type":"object"}}}]
    ;
    const added = [_][]const u8{"late_tool"};
    const messages = [_]ai.ChatMessage{
        .{ .role = "user", .content = "go" },
        .{ .role = "assistant", .content = "", .tool_calls_json = "[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"immediate\",\"arguments\":\"{}\"}}]" },
        .{ .role = "tool", .content = "ok", .tool_call_id = "c1", .tool_name = "immediate", .added_tool_names = &added },
    };
    const body = try buildRequestBody(gpa, "m", &messages, tools, .{ .compat = .{ .supports_tool_search = true } });
    defer gpa.free(body);
    // Root tool list contains only the immediate definition.
    const root_tools = std.mem.indexOf(u8, body, "\"tools\":[") orelse return error.TestUnexpectedResult;
    const search = std.mem.indexOf(u8, body, "\"type\":\"tool_search_call\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(root_tools > search); // request root tools occur after input replay
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"tool_search_output\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"late_tool\",\"description\":\"later\",\"parameters\":{\"type\":\"object\"},\"defer_loading\":true") != null);
    // Late tool appears exactly once: only inside the load output, not root tools.
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, body, pos, "\"name\":\"late_tool\"")) |found| {
        count += 1;
        pos = found + 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "Responses additional_tools loads deferred definitions at message boundary" {
    const gpa = std.testing.allocator;
    const tools =
        \\[{"type":"function","function":{"name":"immediate","description":"now","parameters":{"type":"object"}}},{"type":"function","function":{"name":"late_tool","description":"later","parameters":{"type":"object"}}}]
    ;
    const added = [_][]const u8{"late_tool"};
    const messages = [_]ai.ChatMessage{
        .{ .role = "user", .content = "go" },
        .{ .role = "assistant", .content = "", .tool_calls_json = "[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"immediate\",\"arguments\":\"{}\"}}]" },
        .{ .role = "tool", .content = "ok", .tool_call_id = "c1", .tool_name = "immediate", .added_tool_names = &added },
    };
    const body = try buildRequestBody(gpa, "m", &messages, tools, .{ .compat = .{ .supports_additional_tools = true } });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"additional_tools\",\"role\":\"developer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "tool_search_call") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"late_tool\",\"description\":\"later\",\"parameters\":{\"type\":\"object\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "defer_loading") == null);
}

test "Responses reasoning maps levels and off independently from Codex" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    var map = thinking_mod.ThinkingLevelMap{};
    map.high = .{ .mapped = "very_high" };
    map.off = .{ .mapped = "none_custom" };

    const high = try buildRequestBody(gpa, "gpt-r", &msgs, "[]", .{
        .thinking = .high,
        .reasoning = true,
        .thinking_level_map = map,
    });
    defer gpa.free(high);
    try std.testing.expect(std.mem.indexOf(u8, high, "\"reasoning\":{\"effort\":\"very_high\",\"summary\":\"auto\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, high, "reasoning.encrypted_content") != null);

    const off = try buildRequestBody(gpa, "gpt-r", &msgs, "[]", .{
        .thinking = .off,
        .reasoning = true,
        .thinking_level_map = map,
    });
    defer gpa.free(off);
    try std.testing.expect(std.mem.indexOf(u8, off, "\"reasoning\":{\"effort\":\"none_custom\"}") != null);

    const codex_off = try buildCodexRequestBody(gpa, "gpt-r", &msgs, "[]", .{
        .thinking = .off,
        .reasoning = true,
        .thinking_level_map = map,
    });
    defer gpa.free(codex_off);
    try std.testing.expect(std.mem.indexOf(u8, codex_off, "\"reasoning\":") == null);
}

test "Responses reasoning respects unsupported holes and model capability" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    var map = thinking_mod.ThinkingLevelMap{};
    map.high = .unsupported;
    map.off = .unsupported;

    const unsupported_high = try buildRequestBody(gpa, "gpt-r", &msgs, "[]", .{
        .thinking = .high,
        .reasoning = true,
        .thinking_level_map = map,
    });
    defer gpa.free(unsupported_high);
    try std.testing.expect(std.mem.indexOf(u8, unsupported_high, "\"reasoning\":") == null);

    const unsupported_off = try buildRequestBody(gpa, "gpt-r", &msgs, "[]", .{
        .thinking = .off,
        .reasoning = true,
        .thinking_level_map = map,
    });
    defer gpa.free(unsupported_off);
    try std.testing.expect(std.mem.indexOf(u8, unsupported_off, "\"reasoning\":") == null);

    const non_reasoning = try buildRequestBody(gpa, "plain", &msgs, "[]", .{
        .thinking = .high,
        .reasoning = false,
    });
    defer gpa.free(non_reasoning);
    try std.testing.expect(std.mem.indexOf(u8, non_reasoning, "\"reasoning\":") == null);

    const copilot_off = try buildRequestBody(gpa, "gpt-r", &msgs, "[]", .{
        .thinking = .off,
        .reasoning = true,
        .provider_id = "github-copilot",
    });
    defer gpa.free(copilot_off);
    try std.testing.expect(std.mem.indexOf(u8, copilot_off, "\"reasoning\":") == null);
}

test "Responses service tier pricing matches upstream multipliers" {
    var usage: ai.Usage = .{ .cost = .{ .input = 1.0, .output = 2.0, .cache_read = 0.5, .cache_write = 0.25, .total = 3.75 } };
    applyServiceTierCost("gpt-5.4", .priority, &usage);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), usage.cost.input, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 7.5), usage.cost.total, 1e-12);

    var g55: ai.Usage = .{ .cost = .{ .input = 1.0, .output = 1.0, .total = 2.0 } };
    applyServiceTierCost("gpt-5.5", .priority, &g55);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), g55.cost.input, 1e-12);
}

test "Responses service tier resolution handles Codex default and request fallback" {
    const params = [_]metadata.SamplingParam{.{ .name = "service_tier", .value_json = "\"flex\"" }};
    try std.testing.expectEqual(ServiceTier.flex, requestedServiceTier(&params));
    try std.testing.expectEqual(ServiceTier.flex, effectiveServiceTier(.standard, .unknown, .flex));
    try std.testing.expectEqual(ServiceTier.default, effectiveServiceTier(.standard, .default, .flex));
    try std.testing.expectEqual(ServiceTier.flex, effectiveServiceTier(.codex, .default, .flex));
}

test "xAI Responses requests encrypted reasoning include even when off" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBody(gpa, "grok", &msgs, "[]", .{ .reasoning = true, .thinking = .off, .provider_id = "xai" });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning\":{\"effort\":\"none\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"include\":[\"reasoning.encrypted_content\"]") != null);
}

test "Responses tool results preserve images for vision models without user-message conversion" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .tool_calls_json = "[{\"id\":\"call_img\",\"type\":\"function\",\"function\":{\"name\":\"screenshot\",\"arguments\":\"{}\"}}]" },
        .{ .role = "tool", .content = "screen captured", .tool_call_id = "call_img", .tool_name = "screenshot", .image_b64 = "AQIDBA==", .image_mime = "image/png", .images = &.{.{ .data_b64 = "BQYH", .mime_type = "image/jpeg" }} },
    };
    const body = try buildRequestBody(gpa, "gpt-test", &messages, "[]", .{ .input_image = true });
    defer gpa.free(body);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    const input = parsed.value.object.get("input").?.array;
    try std.testing.expectEqual(@as(usize, 2), input.items.len);
    const output = input.items[1].object.get("output").?.array;
    try std.testing.expectEqual(@as(usize, 3), output.items.len);
    try std.testing.expectEqualStrings("input_text", output.items[0].object.get("type").?.string);
    try std.testing.expectEqualStrings("screen captured", output.items[0].object.get("text").?.string);
    try std.testing.expectEqualStrings("input_image", output.items[1].object.get("type").?.string);
    try std.testing.expectEqualStrings("data:image/png;base64,AQIDBA==", output.items[1].object.get("image_url").?.string);
    try std.testing.expectEqualStrings("input_image", output.items[2].object.get("type").?.string);
    try std.testing.expectEqualStrings("data:image/jpeg;base64,BQYH", output.items[2].object.get("image_url").?.string);
    for (input.items) |item| {
        if (item == .object) {
            if (item.object.get("role")) |role| try std.testing.expect(!std.mem.eql(u8, role.string, "user"));
        }
    }
}

test "Responses tool image fallback never drops the tool output" {
    const gpa = std.testing.allocator;
    const with_text = [_]ai.ChatMessage{
        .{ .role = "tool", .content = "text survives", .tool_call_id = "c1", .tool_name = "shot", .image_b64 = "AA==", .image_mime = "image/jpeg" },
    };
    const body1 = try buildRequestBody(gpa, "text-only", &with_text, "[]", .{ .input_image = false });
    defer gpa.free(body1);
    var p1 = try std.json.parseFromSlice(std.json.Value, gpa, body1, .{});
    defer p1.deinit();
    try std.testing.expectEqualStrings("text survives", p1.value.object.get("input").?.array.items[0].object.get("output").?.string);
    try std.testing.expect(std.mem.indexOf(u8, body1, "data:image") == null);

    const image_only = [_]ai.ChatMessage{
        .{ .role = "tool", .content = "", .tool_call_id = "c2", .tool_name = "shot", .image_b64 = "AA==", .image_mime = "image/png" },
    };
    const body2 = try buildRequestBody(gpa, "text-only", &image_only, "[]", .{ .input_image = false });
    defer gpa.free(body2);
    var p2 = try std.json.parseFromSlice(std.json.Value, gpa, body2, .{});
    defer p2.deinit();
    try std.testing.expectEqualStrings("(see attached image)", p2.value.object.get("input").?.array.items[0].object.get("output").?.string);
}

test "Codex websocket response.create frame wraps request body" {
    const gpa = std.testing.allocator;
    const body = try codexResponseCreateFrame(gpa, "{\"model\":\"gpt-5\",\"input\":[]}");
    defer gpa.free(body);
    try std.testing.expectEqualStrings("{\"type\":\"response.create\",\"model\":\"gpt-5\",\"input\":[]}", body);
}

test "Codex websocket event classifier distinguishes terminal and transport error" {
    try std.testing.expectEqual(CodexEventKind.terminal, codexEventKind("{\"type\":\"response.completed\"}"));
    try std.testing.expectEqual(CodexEventKind.api_error, codexEventKind("{\"type\":\"error\"}"));
    try std.testing.expectEqual(CodexEventKind.previous_response_not_found, codexEventKind("{\"type\":\"error\",\"error\":{\"code\":\"previous_response_not_found\"}}"));
    try std.testing.expectEqual(CodexEventKind.connection_limit, codexEventKind("{\"type\":\"error\",\"error\":{\"code\":\"websocket_connection_limit_reached\"}}"));
    try std.testing.expectEqual(CodexEventKind.diagnostic, codexEventKind("{\"type\":\"codex.rate_limits\"}"));
    try std.testing.expectEqual(CodexEventKind.other, codexEventKind("{\"type\":\"response.output_text.delta\"}"));
}

test "Codex cached continuation sends only input after prior response" {
    const gpa = std.testing.allocator;
    var client = ResponsesClient{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "k",
        .base_url = "https://example.test/backend-api",
        .model = "gpt-5",
        .provider_id = "openai-codex",
        .protocol_mode = .codex,
        .transport = .websocket_cached,
    };
    defer client.deinit();
    const first = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    const first_body = try buildCodexRequestBody(gpa, client.model, &first, "[]", .{ .stream = true, .provider_id = client.provider_id, .api_id = "openai-codex-responses" });
    defer gpa.free(first_body);
    try client.rememberContinuation(gpa, &first, first_body, "resp_1");

    const second = [_]ai.ChatMessage{
        .{ .role = "user", .content = "hello" },
        .{ .role = "assistant", .content = "answer", .provider = "openai-codex", .api = "openai-codex-responses", .model = "gpt-5", .response_id = "resp_1" },
        .{ .role = "user", .content = "finish" },
    };
    const second_body = try buildCodexRequestBody(gpa, client.model, &second, "[]", .{ .stream = true, .provider_id = client.provider_id, .api_id = "openai-codex-responses" });
    defer gpa.free(second_body);
    const cached = (try client.buildCachedCodexPayload(gpa, second_body, &second, "[]")).?;
    defer gpa.free(cached);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, cached, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("resp_1", parsed.value.object.get("previous_response_id").?.string);
    const input = parsed.value.object.get("input").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), input.len);
    try std.testing.expectEqualStrings("user", input[0].object.get("role").?.string);
}

test "Codex cached continuation invalidates when request shape changes" {
    const gpa = std.testing.allocator;
    var client = ResponsesClient{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "k",
        .base_url = "https://example.test/backend-api",
        .model = "gpt-5",
        .provider_id = "openai-codex",
        .protocol_mode = .codex,
        .transport = .websocket_cached,
    };
    defer client.deinit();
    const first = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    const body = try buildCodexRequestBody(gpa, client.model, &first, "[]", .{ .stream = true, .provider_id = client.provider_id, .api_id = "openai-codex-responses" });
    defer gpa.free(body);
    try client.rememberContinuation(gpa, &first, body, "resp_1");
    const second = [_]ai.ChatMessage{
        .{ .role = "user", .content = "hello" },
        .{ .role = "assistant", .content = "answer", .provider = "openai-codex", .api = "openai-codex-responses", .model = "gpt-5", .response_id = "resp_1" },
        .{ .role = "user", .content = "finish" },
    };
    const second_body = try buildCodexRequestBody(gpa, client.model, &second, "[]", .{ .stream = true, .provider_id = client.provider_id, .api_id = "openai-codex-responses" });
    defer gpa.free(second_body);
    const changed = try std.fmt.allocPrint(gpa, "{s},\"service_tier\":\"priority\"}}", .{second_body[0 .. second_body.len - 1]});
    defer gpa.free(changed);
    try std.testing.expect((try client.buildCachedCodexPayload(gpa, changed, &second, "[]")) == null);
}

test "Codex websocket close invalidates connection-scoped continuation" {
    const gpa = std.testing.allocator;
    var client = ResponsesClient{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "k",
        .base_url = "https://example.test/backend-api",
        .model = "gpt-5",
        .provider_id = "openai-codex",
        .protocol_mode = .codex,
        .transport = .websocket_cached,
    };
    defer client.deinit();
    const first = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    const body = try buildCodexRequestBody(gpa, client.model, &first, "[]", .{ .stream = true, .provider_id = client.provider_id, .api_id = "openai-codex-responses" });
    defer gpa.free(body);
    try client.rememberContinuation(gpa, &first, body, "resp_old_socket");
    try std.testing.expect(client.continuation != null);

    // A reconnect is a new backend continuation scope even when the Pi
    // session itself remains unchanged.
    client.closeCodexSocket();
    try std.testing.expect(client.continuation == null);
}

test "Codex websocket request id is RFC9562 UUIDv7" {
    const gpa = std.testing.allocator;
    const id = try uuidV7(gpa, std.testing.io);
    defer gpa.free(id);
    try std.testing.expectEqual(@as(usize, 36), id.len);
    try std.testing.expectEqual(@as(u8, '7'), id[14]);
    try std.testing.expect(id[19] == '8' or id[19] == '9' or id[19] == 'a' or id[19] == 'b');
    try std.testing.expectEqual(@as(u8, '-'), id[8]);
    try std.testing.expectEqual(@as(u8, '-'), id[13]);
    try std.testing.expectEqual(@as(u8, '-'), id[18]);
    try std.testing.expectEqual(@as(u8, '-'), id[23]);
}

test "Codex pure Zig Zstandard request framing round-trips raw and RLE blocks" {
    const gpa = std.testing.allocator;
    const samples = [_][]const u8{
        "",
        "hi",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "compress me compress me compress me",
    };
    for (samples) |sample| {
        const encoded = try encodeZstdRequestBody(gpa, sample);
        defer gpa.free(encoded);
        try std.testing.expect(encoded.len >= 9);
        try std.testing.expectEqualSlices(u8, &.{ 0x28, 0xB5, 0x2F, 0xFD }, encoded[0..4]);
        var in: std.Io.Reader = .fixed(encoded);
        var zstd_stream: std.compress.zstd.Decompress = .init(&in, &.{}, .{});
        var out: std.Io.Writer.Allocating = .init(gpa);
        defer out.deinit();
        _ = try zstd_stream.reader.streamRemaining(&out.writer);
        try std.testing.expectEqualSlices(u8, sample, out.written());
    }

    const large = try gpa.alloc(u8, std.compress.zstd.block_size_max + 17);
    defer gpa.free(large);
    @memset(large, 'x');
    const encoded = try encodeZstdRequestBody(gpa, large);
    defer gpa.free(encoded);
    var in: std.Io.Reader = .fixed(encoded);
    var zstd_stream: std.compress.zstd.Decompress = .init(&in, &.{}, .{});
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    _ = try zstd_stream.reader.streamRemaining(&out.writer);
    try std.testing.expectEqualSlices(u8, large, out.written());
}

test "Codex Retry-After parser honors ms seconds and IMF-fixdate" {
    const now_ms: i64 = 1_778_630_400_000; // 2026-05-13T00:00:00Z
    const h1 = try std.http.Client.Response.Head.parse("HTTP/1.1 429 Too Many Requests\r\nretry-after-ms: 1500\r\ncontent-length: 0\r\n\r\n");
    try std.testing.expectEqual(@as(?i64, 1500), retryAfterMsFromHead(h1, now_ms));
    const h2 = try std.http.Client.Response.Head.parse("HTTP/1.1 429 Too Many Requests\r\nretry-after: 60\r\ncontent-length: 0\r\n\r\n");
    try std.testing.expectEqual(@as(?i64, 60_000), retryAfterMsFromHead(h2, now_ms));
    const h3 = try std.http.Client.Response.Head.parse("HTTP/1.1 429 Too Many Requests\r\nretry-after: Wed, 13 May 2026 00:00:45 GMT\r\ncontent-length: 0\r\n\r\n");
    try std.testing.expectEqual(@as(?i64, 45_000), retryAfterMsFromHead(h3, now_ms));
}

test "Codex retry policy bounds server delays and treats quota exhaustion as terminal" {
    try std.testing.expectEqual(@as(u64, 1000), try retryDelayMs(.{}, 0, null));
    try std.testing.expectEqual(@as(u64, 2000), try retryDelayMs(.{}, 1, null));
    try std.testing.expectEqual(@as(u64, 1500), try retryDelayMs(.{}, 0, 1500));
    try std.testing.expectError(error.ProviderRetryDelayExceeded, retryDelayMs(.{}, 0, 60_001));
    try std.testing.expect(isRetryableHttp(.{ .status = 429 }, "rate_limit_exceeded", true));
    try std.testing.expect(!isRetryableHttp(.{ .status = 429 }, "insufficient_quota: billing required", true));
    try std.testing.expect(isRetryableHttp(.{ .status = 503 }, "upstream unavailable", true));
}

test "Codex cache session affinity clamps to 64 and disables with retention none" {
    const long = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
    try std.testing.expectEqual(@as(usize, 64), codexCacheSessionId(long, .short).?.len);
    try std.testing.expectEqualStrings(long[0..64], codexCacheSessionId(long, .long).?);
    try std.testing.expect(codexCacheSessionId(long, .none) == null);
    try std.testing.expect(codexCacheSessionId(null, .short) == null);
}

test "Codex sampling tool choice overrides default without duplicate keys" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "use tool" }};
    const params = [_]metadata.SamplingParam{.{ .name = "tool_choice", .value_json = "\"required\"" }};
    const body = try buildCodexRequestBody(gpa, "gpt-5", &msgs, "[]", .{ .sampling_params = &params });
    defer gpa.free(body);
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, body, pos, "\"tool_choice\"")) |found| {
        count += 1;
        pos = found + 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"tool_choice\":\"required\"") != null);
}

test "Codex SSE terminal event becomes visible before EOF" {
    const gpa = std.testing.allocator;
    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    live.attachBuffer();
    try live.writer.writeAll("data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_terminal\",\"status\":\"completed\",\"output\":[]}}\n\n");
    // The event fits in the writer buffer, so explicitly exercising the helper
    // used by the HTTP pump proves no second network read/EOF is required.
    try live.flushWriterBuffer();
    try std.testing.expect(live.terminal);
    try std.testing.expectEqualStrings("resp_terminal", live.response_id);
}

test "Codex SSE nonterminal delta does not stop body pump" {
    const gpa = std.testing.allocator;
    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    live.attachBuffer();
    try live.writer.writeAll("data: {\"type\":\"response.output_text.delta\",\"delta\":\"hi\"}\n\n");
    try live.flushWriterBuffer();
    try std.testing.expect(!live.terminal);
    try std.testing.expectEqualStrings("hi", live.text.items);
}

test "Codex transport diagnostic is redacted JSON and survives live retry reset" {
    const gpa = std.testing.allocator;
    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    live.attachBuffer();
    try live.setTransportDiagnostic(std.testing.io, "WebSocketConnectTimeout", .auto, "sse", false, 321);
    try std.testing.expect(std.mem.indexOf(u8, live.diagnostics_json, "provider_transport_failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, live.diagnostics_json, "WebSocketConnectTimeout") != null);
    try std.testing.expect(std.mem.indexOf(u8, live.diagnostics_json, "\\\"api_key\\\"") == null);
    live.resetForRetry();
    try std.testing.expect(std.mem.indexOf(u8, live.diagnostics_json, "fallbackTransport") != null);

    var response = try live.finish("openai-codex", "gpt-5");
    defer response.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, response.diagnostics_json, "requestBytes") != null);
}

test "Codex post-start transport failure preserves partial assistant response" {
    const gpa = std.testing.allocator;
    var client = ResponsesClient{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "token",
        .base_url = "https://chatgpt.com/backend-api",
        .model = "gpt-5.1-codex",
        .provider_id = "openai-codex",
        .protocol_mode = .codex,
        .transport = .auto,
    };
    defer client.deinit();

    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    live.attachBuffer();
    try live.handleEventJson("{\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}");
    try live.setTransportDiagnostic(std.testing.io, "WebSocketIdleTimeout", .auto, null, true, 456);
    live.stop_reason = "error";
    live.raw_stop_reason = try gpa.dupe(u8, "WebSocketIdleTimeout");

    var response = try client.finishCodexLiveResponse(gpa, &live, &.{}, "{}", false);
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("partial", response.content);
    try std.testing.expectEqualStrings("error", response.stop_reason);
    try std.testing.expectEqualStrings("WebSocketIdleTimeout", response.raw_stop_reason);
    try std.testing.expect(std.mem.indexOf(u8, response.diagnostics_json, "after_message_stream_start") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.diagnostics_json, "fallbackTransport") == null);
}

test "Codex API error preserves partial text and stays distinct from transport diagnostics" {
    const gpa = std.testing.allocator;
    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    live.attachBuffer();
    try live.handleEventJson("{\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}");
    try live.handleEventJson("{\"type\":\"error\",\"error\":{\"code\":\"bad_request\",\"message\":\"invalid tool\"}}");
    var response = try live.finish("openai-codex", "gpt-5.1-codex");
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("partial", response.content);
    try std.testing.expectEqualStrings("Codex error: invalid tool", response.error_message);
    try std.testing.expectEqualStrings("bad_request", response.raw_stop_reason);
    try std.testing.expectEqualStrings("error", response.stop_reason);
    try std.testing.expectEqual(@as(usize, 0), response.diagnostics_json.len);
}

test "Codex response.failed captures nested provider message" {
    const gpa = std.testing.allocator;
    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    try live.handleEventJson("{\"type\":\"response.failed\",\"response\":{\"status\":\"failed\",\"error\":{\"code\":\"server_error\",\"message\":\"backend failed\"}}}");
    var response = try live.finish("openai-codex", "gpt-5.1-codex");
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("backend failed", response.error_message);
    try std.testing.expectEqualStrings("server_error", response.raw_stop_reason);
    try std.testing.expectEqualStrings("error", response.stop_reason);
}

test "Codex malformed event JSON becomes protocol error response metadata" {
    const gpa = std.testing.allocator;
    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    live.strict_codex_json = true;
    try live.handleEventJson("{\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}");
    try std.testing.expectError(error.CodexProtocolError, live.handleEventJson("{not-json"));
    var response = try live.finish("openai-codex", "gpt-5.1-codex");
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("partial", response.content);
    try std.testing.expectEqualStrings("Invalid Codex response event JSON", response.error_message);
    try std.testing.expectEqualStrings("CodexProtocolError", response.raw_stop_reason);
    try std.testing.expectEqualStrings("error", response.stop_reason);
    try std.testing.expectEqual(@as(usize, 0), response.diagnostics_json.len);
}

test "ordinary Responses parser remains tolerant of malformed provider event" {
    const gpa = std.testing.allocator;
    var live = ResponsesLive.init(gpa, null, null, true, null);
    defer live.deinit();
    try live.handleEventJson("{not-json");
    try std.testing.expectEqual(@as(usize, 0), live.error_message.len);
}

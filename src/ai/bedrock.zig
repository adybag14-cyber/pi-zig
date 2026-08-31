//! Native Amazon Bedrock Converse Stream transport.
//!
//! This implements the raw HTTP bearer-token path supported by Bedrock rather
//! than depending on the AWS SDK. Converse Stream responses use AWS EventStream
//! framing, so the transport includes an incremental binary frame decoder and
//! maps Bedrock message/content/metadata events onto Pi's ModelResponse stream.
//!
//! Authentication is SDK-free: bearer tokens, SigV4 static credentials, and
//! refresh hooks supplied by the native AWS credential-chain modules.
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");
const http_fetch = @import("http_fetch.zig");
const retry_mod = @import("retry.zig");
const ai = @import("root.zig");
const context_estimate = @import("context_estimate.zig");
const transcript_repair = @import("transcript_repair.zig");
const metadata = @import("request_metadata.zig");
const stream_mod = @import("stream.zig");
const cost_mod = @import("cost.zig");

pub const AwsCredentials = struct {
    access_key_id: []const u8,
    secret_access_key: []const u8,
    session_token: ?[]const u8 = null,
};

pub const SigV4Result = struct {
    authorization: []u8,
    amz_date: [16]u8,
    payload_hash: [64]u8,

    pub fn deinit(self: *SigV4Result, gpa: std.mem.Allocator) void {
        gpa.free(self.authorization);
        self.* = undefined;
    }
};

/// Deterministic AWS Signature V4 signer for Bedrock runtime requests.
/// Exposed for unit tests; production calls pass the real clock timestamp.
pub fn signAwsRequest(
    gpa: std.mem.Allocator,
    method: []const u8,
    url: []const u8,
    payload: []const u8,
    credentials: AwsCredentials,
    region: []const u8,
    unix_seconds: i64,
) !SigV4Result {
    return signAwsRequestForService(gpa, method, url, payload, credentials, region, "bedrock", "application/json", unix_seconds);
}

pub fn signAwsRequestForService(
    gpa: std.mem.Allocator,
    method: []const u8,
    url: []const u8,
    payload: []const u8,
    credentials: AwsCredentials,
    region: []const u8,
    service: []const u8,
    content_type: []const u8,
    unix_seconds: i64,
) !SigV4Result {
    if (unix_seconds < 0) return error.InvalidAwsTimestamp;
    const parts = try splitAwsUrl(url);
    if (parts.query.len != 0) return error.UnsupportedAwsQueryString;

    var amz_date: [16]u8 = undefined;
    var short_date: [8]u8 = undefined;
    try formatAwsDate(unix_seconds, &amz_date, &short_date);

    var payload_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &payload_digest, .{});
    const payload_hash = std.fmt.bytesToHex(payload_digest, .lower);

    const signed_headers = if (credentials.session_token != null)
        "content-type;host;x-amz-date;x-amz-security-token"
    else
        "content-type;host;x-amz-date";

    const canonical_headers = if (credentials.session_token) |token|
        try std.fmt.allocPrint(gpa, "content-type:{s}\nhost:{s}\nx-amz-date:{s}\nx-amz-security-token:{s}\n", .{ content_type, parts.authority, amz_date[0..], token })
    else
        try std.fmt.allocPrint(gpa, "content-type:{s}\nhost:{s}\nx-amz-date:{s}\n", .{ content_type, parts.authority, amz_date[0..] });
    defer gpa.free(canonical_headers);

    const canonical_request = try std.fmt.allocPrint(gpa, "{s}\n{s}\n\n{s}\n{s}\n{s}", .{
        method,
        parts.path,
        canonical_headers,
        signed_headers,
        payload_hash[0..],
    });
    defer gpa.free(canonical_request);

    var canonical_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical_request, &canonical_digest, .{});
    const canonical_hash = std.fmt.bytesToHex(canonical_digest, .lower);
    const scope = try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/aws4_request", .{ short_date[0..], region, service });
    defer gpa.free(scope);
    const string_to_sign = try std.fmt.allocPrint(gpa, "AWS4-HMAC-SHA256\n{s}\n{s}\n{s}", .{ amz_date[0..], scope, canonical_hash[0..] });
    defer gpa.free(string_to_sign);

    const secret_key = try std.fmt.allocPrint(gpa, "AWS4{s}", .{credentials.secret_access_key});
    defer gpa.free(secret_key);
    const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
    var k_date: [Hmac.mac_length]u8 = undefined;
    var k_region: [Hmac.mac_length]u8 = undefined;
    var k_service: [Hmac.mac_length]u8 = undefined;
    var k_signing: [Hmac.mac_length]u8 = undefined;
    var signature: [Hmac.mac_length]u8 = undefined;
    Hmac.create(&k_date, short_date[0..], secret_key);
    Hmac.create(&k_region, region, &k_date);
    Hmac.create(&k_service, service, &k_region);
    Hmac.create(&k_signing, "aws4_request", &k_service);
    Hmac.create(&signature, string_to_sign, &k_signing);
    const signature_hex = std.fmt.bytesToHex(signature, .lower);

    const authorization = try std.fmt.allocPrint(
        gpa,
        "AWS4-HMAC-SHA256 Credential={s}/{s}, SignedHeaders={s}, Signature={s}",
        .{ credentials.access_key_id, scope, signed_headers, signature_hex[0..] },
    );
    return .{ .authorization = authorization, .amz_date = amz_date, .payload_hash = payload_hash };
}

const AwsUrlParts = struct {
    authority: []const u8,
    path: []const u8,
    query: []const u8,
};

fn splitAwsUrl(url: []const u8) !AwsUrlParts {
    const scheme = std.mem.indexOf(u8, url, "://") orelse return error.InvalidBedrockUrl;
    const authority_start = scheme + 3;
    if (authority_start >= url.len) return error.InvalidBedrockUrl;
    const path_start = std.mem.indexOfScalarPos(u8, url, authority_start, '/') orelse url.len;
    const authority = url[authority_start..path_start];
    if (authority.len == 0 or std.mem.indexOfScalar(u8, authority, '@') != null) return error.InvalidBedrockUrl;
    const path_and_query = if (path_start < url.len) url[path_start..] else "/";
    if (std.mem.indexOfScalar(u8, path_and_query, '#') != null) return error.InvalidBedrockUrl;
    if (std.mem.indexOfScalar(u8, path_and_query, '?')) |q| {
        return .{ .authority = authority, .path = if (q == 0) "/" else path_and_query[0..q], .query = path_and_query[q + 1 ..] };
    }
    return .{ .authority = authority, .path = path_and_query, .query = "" };
}

fn formatAwsDate(unix_seconds: i64, amz_date: *[16]u8, short_date: *[8]u8) !void {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_seconds) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const full = try std.fmt.bufPrint(amz_date, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
    if (full.len != amz_date.len) return error.InvalidAwsTimestamp;
    @memcpy(short_date, amz_date[0..8]);
}

pub const CredentialRefreshFn = *const fn (ctx: *anyopaque, client: *BedrockClient, now_unix: i64) anyerror!void;

const ResponseObserverContext = struct {
    gpa: std.mem.Allocator,
    callback: ai.ProviderResponseHandler,
    callback_ctx: ?*anyopaque,

    fn observe(raw: ?*anyopaque, head: std.http.Client.Response.Head) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var headers: std.ArrayList(metadata.Header) = .empty;
        defer headers.deinit(self.gpa);
        var iterator = head.iterateHeaders();
        while (iterator.next()) |header| try headers.append(self.gpa, .{ .name = header.name, .value = header.value });
        try self.callback(self.callback_ctx, .{
            .status = @intCast(@intFromEnum(head.status)),
            .headers = headers.items,
        });
    }
};

pub const BedrockClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    /// Process/provider proxy environment.
    environ: ?*const std.process.Environ.Map = null,
    /// Global settings.json `httpProxy` fallback.
    proxy_url: ?[]const u8 = null,
    /// Provider-internal request retry settings.
    provider_retry: retry_mod.ProviderPolicy = .{ .max_retries = 2 },
    /// Bedrock bearer token (`AWS_BEARER_TOKEN_BEDROCK`). Empty selects SigV4/skip-auth.
    api_key: []const u8 = "",
    /// Ambient/static AWS credentials used for native SigV4 when bearer auth is absent.
    aws_credentials: ?AwsCredentials = null,
    /// Optional lazy/refreshable credential source (web identity/process/container/IMDS).
    credential_refresh_ctx: ?*anyopaque = null,
    credential_refresh_fn: ?CredentialRefreshFn = null,
    credential_expiration_unix: ?i64 = null,
    /// Explicit AWS region (`AWS_REGION`/`AWS_DEFAULT_REGION`). ARN region wins.
    region: ?[]const u8 = null,
    /// Custom proxy compatibility for AWS_BEDROCK_SKIP_AUTH=1.
    skip_auth: bool = false,
    /// Bedrock runtime endpoint, e.g. https://bedrock-runtime.us-east-1.amazonaws.com
    base_url: []const u8,
    model: []const u8,
    provider_id: []const u8 = "amazon-bedrock",
    api_id: []const u8 = "bedrock-converse-stream",
    thinking: ai.ThinkingLevel = .off,
    custom_headers: []const metadata.Header = &.{},
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    input_image: bool = false,
    model_cost: @import("providers.zig").ModelCost = .{},
    abort_flag: ?*bool = null,
    cache_retention: metadata.CacheRetention = .short,

    pub fn client(self: *BedrockClient) ai.ModelClient {
        return .{ .ptr = self, .completeFn = completeImpl, .completeOptionsFn = completeOptionsImpl, .streamFn = streamImpl };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        return completeOptionsImpl(ptr, gpa, messages, tools_json, .{});
    }

    fn completeOptionsImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, options: ai.CompletionOptions) anyerror!ai.ModelResponse {
        const self: *BedrockClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, options, null, null);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn streamImpl(
        ptr: *anyopaque,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) anyerror!ai.ModelResponse {
        const self: *BedrockClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, .{}, on_delta, delta_ctx);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn request(
        self: *BedrockClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        request_options: ai.CompletionOptions,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        const now_unix = Io.Clock.real.now(self.io).toSeconds();
        if (self.credential_refresh_fn) |refresh| {
            const should_refresh = if (self.api_key.len > 0)
                (if (self.credential_expiration_unix) |expires| expires <= now_unix + 60 else true)
            else
                self.aws_credentials == null or (if (self.credential_expiration_unix) |expires| expires <= now_unix + 60 else false);
            if (should_refresh) try refresh(self.credential_refresh_ctx orelse return error.InvalidCredentialRefreshContext, self, now_unix);
        }
        if (self.api_key.len == 0 and self.aws_credentials == null and !self.skip_auth) return error.MissingBedrockCredentials;
        var prepared = try transcript_repair.prepare(gpa, messages, .{ .supports_images = self.input_image, .target_provider = self.provider_id, .target_api = self.api_id, .target_model = self.model });
        defer prepared.deinit();
        const effective_messages = prepared.messages.items;
        const effective_max_tokens = context_estimate.clampMaxTokens(self.context_window, ai.resolveMaxTokens(self.max_tokens, request_options.max_tokens), effective_messages, tools_json);
        const payload = try buildRequestBody(gpa, self.model, effective_messages, tools_json, .{
            .thinking = self.thinking,
            .max_tokens = effective_max_tokens,
            .cache_retention = ai.resolveCacheRetention(self.cache_retention, request_options),
            .tool_choice = request_options.tool_choice,
        });
        defer gpa.free(payload);
        const effective_region = inferBedrockRegion(self.model, self.base_url, self.region);
        const effective_base = try effectiveBedrockBaseUrl(gpa, self.base_url, effective_region);
        defer gpa.free(effective_base);
        const url = try buildConverseStreamUrl(gpa, effective_base, self.model);
        defer gpa.free(url);

        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena.deinit();
        var http_client: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http_client.deinit();
        _ = try http_proxy.configureClient(&http_client, proxy_arena.allocator(), url, .{
            .environ = self.environ,
            .setting = self.proxy_url,
        });
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try putHeader(gpa, &headers, "content-type", "application/json");
        try putHeader(gpa, &headers, "accept", "application/vnd.amazon.eventstream");

        var bearer_authorization: ?[]u8 = null;
        defer if (bearer_authorization) |value| gpa.free(value);
        var signature: ?SigV4Result = null;
        defer if (signature) |*value| value.deinit(gpa);
        if (!self.skip_auth) {
            if (self.api_key.len > 0) {
                bearer_authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
                try putHeader(gpa, &headers, "authorization", bearer_authorization.?);
            } else if (self.aws_credentials) |credentials| {
                signature = try signAwsRequest(
                    gpa,
                    "POST",
                    url,
                    payload,
                    credentials,
                    effective_region,
                    now_unix,
                );
                try putHeader(gpa, &headers, "authorization", signature.?.authorization);
                try putHeader(gpa, &headers, "x-amz-date", signature.?.amz_date[0..]);
                if (credentials.session_token) |token| try putHeader(gpa, &headers, "x-amz-security-token", token);
            }
        }
        for (self.custom_headers) |header| {
            if (isReservedHeader(header.name)) continue;
            try putHeader(gpa, &headers, header.name, header.value);
        }

        var retry_index: usize = 0;
        var response_observer: ?ResponseObserverContext = if (request_options.on_response) |callback| .{
            .gpa = gpa,
            .callback = callback,
            .callback_ctx = request_options.on_response_ctx,
        } else null;
        while (true) {
            var live = BedrockLive.init(gpa, self.provider_id, self.model, self.model_cost, on_delta, delta_ctx, self.abort_flag);
            live.attachBuffer();
            defer live.deinit();

            const fetch_result = http_fetch.fetchControlledObserved(&http_client, .{
                .location = .{ .url = url },
                .method = .POST,
                .payload = payload,
                .keep_alive = false,
                .extra_headers = headers.items,
                .response_writer = &live.writer,
            }, self.provider_retry.timeout_ms, self.abort_flag, if (response_observer) |*observer| .{
                .context = observer,
                .callback = ResponseObserverContext.observe,
            } else null) catch |err| {
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                if (live.body.items.len > 0 or retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            try live.flushTrailing();
            if (live.aborted) return abortedResponse(gpa, self.provider_id, self.model);

            const status = fetch_result.status;
            if (status < 200 or status >= 300) {
                if (retry_index < self.provider_retry.max_retries and retry_mod.isRetryableProviderResponse(fetch_result.provider)) {
                    const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, fetch_result.provider.retry_after_ms);
                    retry_index += 1;
                    if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                    continue;
                }
                const snippet = if (live.body.items.len > 1200) live.body.items[0..1200] else live.body.items;
                var response = try httpErrorResponse(gpa, self.provider_id, self.model, status, snippet);
                response.provider_status = fetch_result.provider.status;
                response.provider_retry_after_ms = fetch_result.provider.retry_after_ms;
                response.provider_should_retry = fetch_result.provider.should_retry;
                return response;
            }
            if (!live.terminal) return streamEndedResponse(gpa, self.provider_id, self.model);
            return try live.finish();
        }
    }
};

pub const BuildOptions = struct {
    thinking: ai.ThinkingLevel = .off,
    max_tokens: u64 = 0,
    cache_retention: metadata.CacheRetention = .short,
    tool_choice: ?ai.ToolChoice = null,
};

pub fn inferBedrockRegion(model: []const u8, base_url: []const u8, configured_region: ?[]const u8) []const u8 {
    if (bedrockArnRegion(model)) |region| return region;
    if (configured_region) |region| if (std.mem.trim(u8, region, " \t\r\n").len > 0) return region;
    if (standardBedrockEndpointRegion(base_url)) |region| return region;
    return "us-east-1";
}

fn bedrockArnRegion(model: []const u8) ?[]const u8 {
    if (!std.ascii.startsWithIgnoreCase(model, "arn:")) return null;
    var it = std.mem.splitScalar(u8, model, ':');
    _ = it.next() orelse return null; // arn
    _ = it.next() orelse return null; // partition
    const service = it.next() orelse return null;
    const region = it.next() orelse return null;
    if (!std.ascii.eqlIgnoreCase(service, "bedrock") or region.len == 0) return null;
    return region;
}

fn standardBedrockEndpointRegion(base_url: []const u8) ?[]const u8 {
    const parts = splitAwsUrl(base_url) catch return null;
    const normal = "bedrock-runtime.";
    const fips = "bedrock-runtime-fips.";
    const prefix_len: usize = if (std.ascii.startsWithIgnoreCase(parts.authority, normal))
        normal.len
    else if (std.ascii.startsWithIgnoreCase(parts.authority, fips))
        fips.len
    else
        return null;
    const tail = parts.authority[prefix_len..];
    const suffix = std.ascii.indexOfIgnoreCase(tail, ".amazonaws.com") orelse return null;
    if (suffix == 0) return null;
    return tail[0..suffix];
}

fn effectiveBedrockBaseUrl(gpa: std.mem.Allocator, base_url: []const u8, region: []const u8) ![]u8 {
    const parts = splitAwsUrl(base_url) catch return gpa.dupe(u8, base_url);
    const current = standardBedrockEndpointRegion(base_url) orelse return gpa.dupe(u8, base_url);
    if (std.ascii.eqlIgnoreCase(current, region)) return gpa.dupe(u8, base_url);
    const region_start = std.ascii.indexOfIgnoreCase(parts.authority, current) orelse return gpa.dupe(u8, base_url);
    const authority_prefix = parts.authority[0..region_start];
    const suffix = parts.authority[region_start + current.len ..];
    const scheme_end = std.mem.indexOf(u8, base_url, "://") orelse return gpa.dupe(u8, base_url);
    const scheme = base_url[0..scheme_end];
    return std.fmt.allocPrint(gpa, "{s}://{s}{s}{s}", .{ scheme, authority_prefix, region, suffix });
}

pub fn buildConverseStreamUrl(gpa: std.mem.Allocator, base_url: []const u8, model: []const u8) ![]u8 {
    var encoded: std.Io.Writer.Allocating = .init(gpa);
    defer encoded.deinit();
    // AWS path labels use percent encoding; do not leave '/' or ':' raw in ARNs.
    for (model) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try encoded.writer.writeByte(c);
        } else {
            try encoded.writer.print("%{X:0>2}", .{c});
        }
    }
    const root = std.mem.trimEnd(u8, base_url, "/");
    return std.fmt.allocPrint(gpa, "{s}/model/{s}/converse-stream", .{ root, encoded.written() });
}

pub fn buildRequestBody(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    options: BuildOptions,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    var repaired = try transcript_repair.repair(gpa, messages);
    defer repaired.deinit();
    const replay_messages = repaired.messages.items;
    try w.writeByte('{');

    var wrote = false;
    // Bedrock accepts system as content blocks separate from messages.
    var system_count: usize = 0;
    for (replay_messages) |message| {
        if (std.mem.eql(u8, message.role, "system")) system_count += 1;
    }
    const cache_enabled = options.cache_retention != .none and supportsPromptCaching(model);
    const claude_thinking_signature = isClaudeModel(model);

    if (system_count > 0) {
        try w.writeAll("\"system\":[{\"text\":");
        var merged: std.ArrayList(u8) = .empty;
        defer merged.deinit(gpa);
        var first = true;
        for (replay_messages) |message| {
            if (!std.mem.eql(u8, message.role, "system")) continue;
            if (!first) try merged.appendSlice(gpa, "\n\n");
            first = false;
            try merged.appendSlice(gpa, message.content);
        }
        try std.json.Stringify.value(merged.items, .{}, w);
        try w.writeByte('}');
        if (cache_enabled) try writeCachePoint(w, options.cache_retention);
        try w.writeByte(']');
        wrote = true;
    }

    if (wrote) try w.writeByte(',');
    try w.writeAll("\"messages\":[");
    try writeMessages(gpa, w, replay_messages, options.cache_retention, cache_enabled, claude_thinking_signature);
    try w.writeByte(']');
    wrote = true;

    if (options.max_tokens > 0) {
        try w.print(",\"inferenceConfig\":{{\"maxTokens\":{d}}}", .{options.max_tokens});
    }
    if (options.thinking != .off and isClaudeModel(model)) {
        const govcloud = isGovCloudModel(model);
        if (supportsAdaptiveThinking(model)) {
            try w.writeAll(",\"additionalModelRequestFields\":{\"thinking\":{\"type\":\"adaptive\"");
            if (!govcloud) try w.writeAll(",\"display\":\"summarized\"");
            try w.writeAll("},\"output_config\":{\"effort\":");
            try std.json.Stringify.value(mapAdaptiveEffort(model, options.thinking), .{}, w);
            try w.writeAll("}}");
        } else {
            const budget: u64 = switch (options.thinking) {
                .minimal => 1024,
                .low => 2048,
                .medium => 8192,
                .high, .xhigh, .max => 16384,
                .off => 0,
            };
            try w.print(",\"additionalModelRequestFields\":{{\"thinking\":{{\"type\":\"enabled\",\"budget_tokens\":{d}", .{budget});
            if (!govcloud) try w.writeAll(",\"display\":\"summarized\"");
            try w.writeAll("},\"anthropic_beta\":[\"interleaved-thinking-2025-05-14\"]}");
        }
    }
    if (try writeTools(gpa, w, tools_json, options.tool_choice)) {}
    try w.writeByte('}');
    return out.toOwnedSlice();
}

fn writeMessages(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    messages: []const ai.ChatMessage,
    cache_retention: metadata.CacheRetention,
    cache_enabled: bool,
    claude_thinking_signature: bool,
) !void {
    // Determine the last non-system message so the explicit cache point matches
    // upstream's last-user-message behavior when possible.
    var last_non_system: ?usize = null;
    for (messages, 0..) |message, i| {
        if (!std.mem.eql(u8, message.role, "system")) last_non_system = i;
    }

    var first_message = true;
    var i: usize = 0;
    while (i < messages.len) : (i += 1) {
        const msg = messages[i];
        if (std.mem.eql(u8, msg.role, "system")) continue;

        if (std.mem.eql(u8, msg.role, "tool") or std.mem.eql(u8, msg.role, "toolResult")) {
            if (!first_message) try w.writeByte(',');
            first_message = false;
            try w.writeAll("{\"role\":\"user\",\"content\":[");
            var first_tool = true;
            var j = i;
            while (j < messages.len) : (j += 1) {
                const tool = messages[j];
                if (!std.mem.eql(u8, tool.role, "tool") and !std.mem.eql(u8, tool.role, "toolResult")) break;
                if (!first_tool) try w.writeByte(',');
                first_tool = false;
                try w.writeAll("{\"toolResult\":{\"toolUseId\":");
                const normalized = try normalizeToolId(gpa, tool.tool_call_id orelse "");
                defer gpa.free(normalized);
                try std.json.Stringify.value(normalized, .{}, w);
                try w.writeAll(",\"content\":[{\"text\":");
                const text = if (std.mem.trim(u8, tool.content, " \t\r\n").len == 0) "<empty>" else tool.content;
                try std.json.Stringify.value(text, .{}, w);
                try w.writeAll("}],\"status\":");
                try std.json.Stringify.value(if (tool.tool_is_error) "error" else "success", .{}, w);
                try w.writeAll("}}");
            }
            i = j - 1;
            if (cache_enabled and last_non_system != null and last_non_system.? == i) try writeCachePoint(w, cache_retention);
            try w.writeAll("]}");
            continue;
        }

        if (!first_message) try w.writeByte(',');
        first_message = false;
        if (std.mem.eql(u8, msg.role, "assistant")) {
            try w.writeAll("{\"role\":\"assistant\",\"content\":[");
            var first_block = true;
            if (msg.thinking) |thinking| if (std.mem.trim(u8, thinking, " \t\r\n").len > 0) {
                if (!first_block) try w.writeByte(',');
                first_block = false;
                if (msg.thinking_redacted and msg.thinking_signature != null and msg.thinking_signature.?.len > 0) {
                    try w.writeAll("{\"reasoningContent\":{\"redactedContent\":");
                    try std.json.Stringify.value(msg.thinking_signature.?, .{}, w);
                    try w.writeAll("}}");
                } else if (claude_thinking_signature) {
                    if (msg.thinking_signature != null and std.mem.trim(u8, msg.thinking_signature.?, " \t\r\n").len > 0) {
                        try w.writeAll("{\"reasoningContent\":{\"reasoningText\":{\"text\":");
                        try std.json.Stringify.value(thinking, .{}, w);
                        try w.writeAll(",\"signature\":");
                        try std.json.Stringify.value(msg.thinking_signature.?, .{}, w);
                        try w.writeAll("}}}");
                    } else {
                        // Claude rejects replayed reasoningContent without a signature.
                        // Match upstream by falling back to an ordinary text block.
                        try w.writeAll("{\"text\":");
                        try std.json.Stringify.value(thinking, .{}, w);
                        try w.writeByte('}');
                    }
                } else {
                    try w.writeAll("{\"reasoningContent\":{\"reasoningText\":{\"text\":");
                    try std.json.Stringify.value(thinking, .{}, w);
                    try w.writeAll("}}}");
                }
            };
            if (std.mem.trim(u8, msg.content, " \t\r\n").len > 0) {
                if (!first_block) try w.writeByte(',');
                first_block = false;
                try w.writeAll("{\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeByte('}');
            }
            if (msg.tool_calls_json) |raw| try appendToolUses(gpa, w, raw, &first_block);
            // Bedrock rejects empty assistant content arrays. Preserve the turn as text.
            if (first_block) try w.writeAll("{\"text\":\"<empty>\"}");
            try w.writeAll("]}");
        } else {
            try w.writeAll("{\"role\":\"user\",\"content\":[");
            var first_block = true;
            if (std.mem.trim(u8, msg.content, " \t\r\n").len > 0) {
                try w.writeAll("{\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeByte('}');
                first_block = false;
            }
            var image_index: usize = 0;
            while (image_index < msg.imageCount()) : (image_index += 1) {
                const image = msg.imageAt(image_index).?;
                if (!first_block) try w.writeByte(',');
                first_block = false;
                try w.writeAll("{\"image\":{\"format\":");
                try std.json.Stringify.value(imageFormat(image.mime_type), .{}, w);
                try w.writeAll(",\"source\":{\"bytes\":");
                try std.json.Stringify.value(image.data_b64, .{}, w);
                try w.writeAll("}}}");
            }
            if (first_block) try w.writeAll("{\"text\":\"<empty>\"}");
            if (cache_enabled and last_non_system != null and last_non_system.? == i) try writeCachePoint(w, cache_retention);
            try w.writeAll("]}");
        }
    }
}

fn writeCachePoint(w: *std.Io.Writer, retention: metadata.CacheRetention) !void {
    try w.writeAll(",{\"cachePoint\":{\"type\":\"default\"");
    if (retention == .long) try w.writeAll(",\"ttl\":\"1h\"");
    try w.writeAll("}}");
}

fn appendToolUses(gpa: std.mem.Allocator, w: *std.Io.Writer, raw: []const u8, first_block: *bool) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .array) return;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const idv = item.object.get("id") orelse continue;
        const fnv = item.object.get("function") orelse continue;
        if (idv != .string or fnv != .object) continue;
        const namev = fnv.object.get("name") orelse continue;
        if (namev != .string) continue;
        if (!first_block.*) try w.writeByte(',');
        first_block.* = false;
        const normalized = try normalizeToolId(gpa, idv.string);
        defer gpa.free(normalized);
        try w.writeAll("{\"toolUse\":{\"toolUseId\":");
        try std.json.Stringify.value(normalized, .{}, w);
        try w.writeAll(",\"name\":");
        try std.json.Stringify.value(namev.string, .{}, w);
        try w.writeAll(",\"input\":");
        if (fnv.object.get("arguments")) |args| {
            if (args == .string) {
                var args_doc = std.json.parseFromSlice(std.json.Value, gpa, args.string, .{}) catch null;
                if (args_doc) |*doc| {
                    defer doc.deinit();
                    try std.json.Stringify.value(doc.value, .{}, w);
                } else try w.writeAll("{}");
            } else try std.json.Stringify.value(args, .{}, w);
        } else try w.writeAll("{}");
        try w.writeAll("}}");
    }
}

fn writeTools(gpa: std.mem.Allocator, w: *std.Io.Writer, tools_json: []const u8, tool_choice: ?ai.ToolChoice) !bool {
    if (tool_choice == .none) return false;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .array) return false;
    var valid: usize = 0;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fnv = item.object.get("function") orelse continue;
        if (fnv != .object) continue;
        if (fnv.object.get("name")) |name| {
            if (name == .string) valid += 1;
        }
    }
    if (valid == 0) return false;
    try w.writeAll(",\"toolConfig\":{\"tools\":[");
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fnv = item.object.get("function") orelse continue;
        if (fnv != .object) continue;
        const name = fnv.object.get("name") orelse continue;
        if (name != .string) continue;
        if (!first) try w.writeByte(',');
        first = false;
        try w.writeAll("{\"toolSpec\":{\"name\":");
        try std.json.Stringify.value(name.string, .{}, w);
        if (fnv.object.get("description")) |desc| if (desc == .string) {
            try w.writeAll(",\"description\":");
            try std.json.Stringify.value(desc.string, .{}, w);
        };
        try w.writeAll(",\"inputSchema\":{\"json\":");
        if (fnv.object.get("parameters")) |params| try std.json.Stringify.value(params, .{}, w) else try w.writeAll("{\"type\":\"object\",\"properties\":{}}");
        try w.writeAll("}}}");
    }
    try w.writeAll("],\"toolChoice\":{\"auto\":{}}}");
    return true;
}

fn normalizeToolId(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const n = @min(input.len, 64);
    var out = try gpa.alloc(u8, n);
    for (input[0..n], 0..) |c, i| out[i] = if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') c else '_';
    return out;
}

fn imageFormat(mime: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(mime, "image/jpeg") or std.ascii.eqlIgnoreCase(mime, "image/jpg")) return "jpeg";
    if (std.ascii.eqlIgnoreCase(mime, "image/gif")) return "gif";
    if (std.ascii.eqlIgnoreCase(mime, "image/webp")) return "webp";
    return "png";
}

fn isClaudeModel(model: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(model, "claude") != null;
}

fn normalizeModelRef(model: []const u8, out: []u8) []const u8 {
    const n = @min(model.len, out.len);
    for (model[0..n], 0..) |c, i| {
        const lower = std.ascii.toLower(c);
        out[i] = switch (lower) {
            ' ', '_', '.', ':' => '-',
            else => lower,
        };
    }
    return out[0..n];
}

fn supportsAdaptiveThinking(model: []const u8) bool {
    var buf: [512]u8 = undefined;
    const value = normalizeModelRef(model, &buf);
    return std.mem.indexOf(u8, value, "opus-4-6") != null or
        std.mem.indexOf(u8, value, "opus-4-7") != null or
        std.mem.indexOf(u8, value, "opus-4-8") != null or
        std.mem.indexOf(u8, value, "opus-5") != null or
        std.mem.indexOf(u8, value, "sonnet-4-6") != null or
        std.mem.indexOf(u8, value, "sonnet-5") != null or
        std.mem.indexOf(u8, value, "fable-5") != null;
}

fn supportsNativeXhighEffort(model: []const u8) bool {
    var buf: [512]u8 = undefined;
    const value = normalizeModelRef(model, &buf);
    return std.mem.indexOf(u8, value, "opus-4-7") != null or
        std.mem.indexOf(u8, value, "opus-4-8") != null or
        std.mem.indexOf(u8, value, "opus-5") != null or
        std.mem.indexOf(u8, value, "sonnet-5") != null or
        std.mem.indexOf(u8, value, "fable-5") != null;
}

fn mapAdaptiveEffort(model: []const u8, level: ai.ThinkingLevel) []const u8 {
    if (level == .xhigh and supportsNativeXhighEffort(model)) return "xhigh";
    return switch (level) {
        .minimal, .low => "low",
        .medium => "medium",
        .high, .xhigh, .max => "high",
        .off => "low",
    };
}

fn isGovCloudModel(model: []const u8) bool {
    return std.ascii.startsWithIgnoreCase(model, "us-gov.") or std.ascii.startsWithIgnoreCase(model, "arn:aws-us-gov:");
}

fn supportsPromptCaching(model: []const u8) bool {
    // Pi enables explicit Bedrock cache points only for Claude families that
    // advertise prompt caching. Nova uses automatic caching and other models
    // may reject explicit cachePoint blocks. Normalize common ARN/model ID
    // separators so IDs such as anthropic.claude-sonnet-4-... match reliably.
    var normalized_buf: [512]u8 = undefined;
    const value = normalizeModelRef(model, &normalized_buf);
    if (std.mem.indexOf(u8, value, "claude") == null) return false;
    return std.mem.indexOf(u8, value, "fable-5") != null or
        std.mem.indexOf(u8, value, "opus-5") != null or
        std.mem.indexOf(u8, value, "sonnet-5") != null or
        std.mem.indexOf(u8, value, "-4-") != null or
        std.mem.indexOf(u8, value, "claude-3-7-sonnet") != null or
        std.mem.indexOf(u8, value, "claude-3-5-haiku") != null;
}

fn isReservedHeader(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "authorization") or std.ascii.eqlIgnoreCase(name, "host") or std.ascii.startsWithIgnoreCase(name, "x-amz-");
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

const BedrockLive = struct {
    gpa: std.mem.Allocator,
    provider: []const u8,
    model: []const u8,
    model_cost: @import("providers.zig").ModelCost,
    writer: std.Io.Writer,
    buf: [4096]u8 = undefined,
    body: std.ArrayList(u8) = .empty,
    pending: std.ArrayList(u8) = .empty,
    acc: stream_mod.Accumulator,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    abort_flag: ?*bool,
    aborted: bool = false,
    terminal: bool = false,
    terminal_error: bool = false,
    stop_reason: []u8 = &.{},
    raw_stop_reason: []u8 = &.{},
    error_message: []u8 = &.{},
    thinking_signature: std.ArrayList(u8) = .empty,
    redacted_bytes: std.ArrayList(u8) = .empty,
    redacted_announced: bool = false,
    usage: ai.Usage = .{},
    active_tool_id: []u8 = &.{},
    active_tool_name: []u8 = &.{},

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = std.Io.Writer.noopFlush };

    fn init(gpa: std.mem.Allocator, provider: []const u8, model: []const u8, model_cost: @import("providers.zig").ModelCost, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque, abort_flag: ?*bool) BedrockLive {
        return .{
            .gpa = gpa,
            .provider = provider,
            .model = model,
            .model_cost = model_cost,
            .writer = .{ .vtable = &vtable, .buffer = &.{}, .end = 0 },
            .acc = stream_mod.Accumulator.init(gpa),
            .on_delta = on_delta,
            .delta_ctx = delta_ctx,
            .abort_flag = abort_flag,
        };
    }

    fn attachBuffer(self: *BedrockLive) void {
        self.writer.buffer = &self.buf;
        self.writer.end = 0;
    }

    fn deinit(self: *BedrockLive) void {
        self.body.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.acc.deinit();
        self.thinking_signature.deinit(self.gpa);
        self.redacted_bytes.deinit(self.gpa);
        if (self.stop_reason.len > 0) self.gpa.free(self.stop_reason);
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        if (self.error_message.len > 0) self.gpa.free(self.error_message);
        if (self.active_tool_id.len > 0) self.gpa.free(self.active_tool_id);
        if (self.active_tool_name.len > 0) self.gpa.free(self.active_tool_name);
        self.* = undefined;
    }

    fn flushTrailing(self: *BedrockLive) !void {
        if (self.writer.end > 0) {
            try self.feed(self.writer.buffer[0..self.writer.end]);
            self.writer.end = 0;
        }
        if (self.pending.items.len != 0) return error.TruncatedBedrockEventStream;
    }

    fn feed(self: *BedrockLive, chunk: []const u8) !void {
        if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) {
            self.aborted = true;
            return error.WriteFailed;
        };
        try self.body.appendSlice(self.gpa, chunk);
        try self.pending.appendSlice(self.gpa, chunk);
        while (self.pending.items.len >= 12) {
            const total_len = readU32Be(self.pending.items[0..4]);
            if (total_len < 16 or total_len > 16 * 1024 * 1024) return error.InvalidBedrockEventFrame;
            if (self.pending.items.len < total_len) break;
            try self.handleFrame(self.pending.items[0..total_len]);
            const remain = self.pending.items.len - total_len;
            std.mem.copyForwards(u8, self.pending.items[0..remain], self.pending.items[total_len..]);
            self.pending.items.len = remain;
        }
    }

    fn handleFrame(self: *BedrockLive, frame: []const u8) !void {
        const total_len = readU32Be(frame[0..4]);
        const headers_len = readU32Be(frame[4..8]);
        if (total_len != frame.len or headers_len > total_len - 16) return error.InvalidBedrockEventFrame;
        const expected_prelude_crc = readU32Be(frame[8..12]);
        if (std.hash.Crc32.hash(frame[0..8]) != expected_prelude_crc) return error.BedrockPreludeCrcMismatch;
        const expected_message_crc = readU32Be(frame[frame.len - 4 ..]);
        if (std.hash.Crc32.hash(frame[0 .. frame.len - 4]) != expected_message_crc) return error.BedrockMessageCrcMismatch;

        const headers = frame[12 .. 12 + headers_len];
        const payload = frame[12 + headers_len .. frame.len - 4];
        const event_type = try headerString(headers, ":event-type");
        const message_type = try headerString(headers, ":message-type");
        if (message_type) |mt| {
            if (std.mem.eql(u8, mt, "exception") or std.mem.eql(u8, mt, "error")) {
                const exception_type = (try headerString(headers, ":exception-type")) orelse event_type orelse "BedrockException";
                try self.setError(exception_type, payload);
                return;
            }
        }
        const typ = event_type orelse return;
        try self.handleEvent(typ, payload);
    }

    fn handleEvent(self: *BedrockLive, typ: []const u8, payload: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, payload, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const obj = parsed.value.object;

        if (std.mem.eql(u8, typ, "messageStart")) return;
        if (std.mem.eql(u8, typ, "contentBlockStart")) {
            const start = obj.get("start") orelse return;
            if (start != .object) return;
            const tool_use = start.object.get("toolUse") orelse return;
            if (tool_use != .object) return;
            const id = stringField(tool_use.object, "toolUseId") orelse "";
            const name = stringField(tool_use.object, "name") orelse "";
            if (self.active_tool_id.len > 0) self.gpa.free(self.active_tool_id);
            if (self.active_tool_name.len > 0) self.gpa.free(self.active_tool_name);
            self.active_tool_id = try self.gpa.dupe(u8, id);
            self.active_tool_name = try self.gpa.dupe(u8, name);
            try self.push(.{ .kind = .tool_call_delta, .tool_call_id = id, .tool_name = name });
            return;
        }
        if (std.mem.eql(u8, typ, "contentBlockDelta")) {
            const delta = obj.get("delta") orelse return;
            if (delta != .object) return;
            if (stringField(delta.object, "text")) |text| {
                if (text.len > 0) try self.push(.{ .kind = .text_delta, .text = text });
                return;
            }
            if (delta.object.get("toolUse")) |tool| if (tool == .object) {
                const input = stringField(tool.object, "input") orelse "";
                if (input.len > 0) try self.push(.{ .kind = .tool_call_delta, .tool_call_id = self.active_tool_id, .tool_name = self.active_tool_name, .tool_arguments = input });
                return;
            };
            if (delta.object.get("reasoningContent")) |reasoning| if (reasoning == .object) {
                if (stringField(reasoning.object, "text")) |text| if (text.len > 0) try self.push(.{ .kind = .thinking_delta, .thinking = text });
                if (stringField(reasoning.object, "signature")) |sig| if (sig.len > 0) try self.thinking_signature.appendSlice(self.gpa, sig);
                if (reasoning.object.get("redactedContent")) |redacted| try self.appendRedacted(redacted);
                return;
            };
            return;
        }
        if (std.mem.eql(u8, typ, "contentBlockStop")) {
            if (self.active_tool_id.len > 0) {
                self.gpa.free(self.active_tool_id);
                self.active_tool_id = &.{};
            }
            if (self.active_tool_name.len > 0) {
                self.gpa.free(self.active_tool_name);
                self.active_tool_name = &.{};
            }
            return;
        }
        if (std.mem.eql(u8, typ, "messageStop")) {
            const reason = stringField(obj, "stopReason") orelse "";
            if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
            self.raw_stop_reason = try self.gpa.dupe(u8, reason);
            try self.setStopReason(mapStopReason(reason));
            self.terminal = true;
            if (self.on_delta) |handler| handler(self.delta_ctx, .{ .kind = .done });
            return;
        }
        if (std.mem.eql(u8, typ, "metadata")) {
            if (obj.get("usage")) |usage| if (usage == .object) {
                self.usage.input = numberU64(usage.object.get("inputTokens"));
                self.usage.output = numberU64(usage.object.get("outputTokens"));
                self.usage.cache_read = numberU64(usage.object.get("cacheReadInputTokens"));
                self.usage.cache_write = numberU64(usage.object.get("cacheWriteInputTokens"));
                self.usage.total_tokens = numberU64(usage.object.get("totalTokens"));
                if (self.usage.total_tokens == 0) self.usage.normalizeTotal();
                _ = cost_mod.calculate(self.model_cost, &self.usage);
            };
            return;
        }
        // Service exceptions are sometimes represented as ordinary event types.
        if (std.mem.endsWith(u8, typ, "Exception")) try self.setError(typ, payload);
    }

    fn setStopReason(self: *BedrockLive, reason: []const u8) !void {
        if (self.stop_reason.len > 0) self.gpa.free(self.stop_reason);
        self.stop_reason = try self.gpa.dupe(u8, reason);
    }

    fn appendRedacted(self: *BedrockLive, value: std.json.Value) !void {
        switch (value) {
            .string => |encoded| {
                const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidBedrockRedactedReasoning;
                const decoded = try self.gpa.alloc(u8, decoded_len);
                defer self.gpa.free(decoded);
                std.base64.standard.Decoder.decode(decoded, encoded) catch return error.InvalidBedrockRedactedReasoning;
                try self.redacted_bytes.appendSlice(self.gpa, decoded);
            },
            .array => |array| for (array.items) |item| {
                if (item != .integer or item.integer < 0 or item.integer > 255) return error.InvalidBedrockRedactedReasoning;
                try self.redacted_bytes.append(self.gpa, @intCast(item.integer));
            },
            else => return error.InvalidBedrockRedactedReasoning,
        }
        if (!self.redacted_announced) {
            self.redacted_announced = true;
            try self.push(.{ .kind = .thinking_delta, .thinking = "[Reasoning redacted]" });
        }
    }

    fn setError(self: *BedrockLive, typ: []const u8, payload: []const u8) !void {
        self.terminal = true;
        self.terminal_error = true;
        try self.setStopReason("error");
        if (self.error_message.len > 0) self.gpa.free(self.error_message);
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, payload, .{}) catch null;
        if (parsed) |*doc| {
            defer doc.deinit();
            const message = if (doc.value == .object)
                stringField(doc.value.object, "message") orelse stringField(doc.value.object, "Message") orelse payload
            else
                payload;
            self.error_message = try std.fmt.allocPrint(self.gpa, "{s}: {s}", .{ humanExceptionPrefix(typ), message });
        } else {
            self.error_message = try std.fmt.allocPrint(self.gpa, "{s}: {s}", .{ humanExceptionPrefix(typ), payload });
        }
        if (self.on_delta) |handler| handler(self.delta_ctx, .{ .kind = .err, .text = self.error_message });
    }

    fn push(self: *BedrockLive, delta: stream_mod.StreamDelta) !void {
        try self.acc.onDelta(delta);
        if (self.on_delta) |handler| handler(self.delta_ctx, delta);
    }

    fn finish(self: *BedrockLive) !ai.ModelResponse {
        var response = try self.acc.finish();
        response.provider = try self.gpa.dupe(u8, self.provider);
        response.model = try self.gpa.dupe(u8, self.model);
        response.usage = self.usage;
        if (self.redacted_bytes.items.len > 0) {
            const encoded_len = std.base64.standard.Encoder.calcSize(self.redacted_bytes.items.len);
            const encoded = try self.gpa.alloc(u8, encoded_len);
            _ = std.base64.standard.Encoder.encode(encoded, self.redacted_bytes.items);
            response.thinking_signature = encoded;
            response.thinking_redacted = true;
        } else if (self.thinking_signature.items.len > 0) {
            response.thinking_signature = try self.gpa.dupe(u8, self.thinking_signature.items);
        }
        const reason = if (self.stop_reason.len > 0) self.stop_reason else if (response.tool_calls.len > 0) "toolUse" else "stop";
        response.stop_reason = try self.gpa.dupe(u8, reason);
        if (self.raw_stop_reason.len > 0) response.raw_stop_reason = try self.gpa.dupe(u8, self.raw_stop_reason);
        if (self.terminal_error and self.error_message.len > 0) {
            if (response.content.len > 0) self.gpa.free(response.content);
            response.content = try self.gpa.dupe(u8, self.error_message);
        }
        return response;
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *BedrockLive = @fieldParentPtr("writer", w);
        if (w.end > 0) {
            self.feed(w.buffer[0..w.end]) catch return error.WriteFailed;
            w.end = 0;
        }
        if (data.len == 0) return 0;
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |part| {
            self.feed(part) catch return error.WriteFailed;
            n += part.len;
        }
        const pattern = data[data.len - 1];
        var s = splat;
        while (s > 0) : (s -= 1) {
            self.feed(pattern) catch return error.WriteFailed;
            n += pattern.len;
        }
        return n;
    }
};

fn readU32Be(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) | (@as(u32, bytes[2]) << 8) | @as(u32, bytes[3]);
}

fn writeU32Be(out: []u8, value: u32) void {
    out[0] = @intCast((value >> 24) & 0xff);
    out[1] = @intCast((value >> 16) & 0xff);
    out[2] = @intCast((value >> 8) & 0xff);
    out[3] = @intCast(value & 0xff);
}

fn headerString(headers: []const u8, wanted: []const u8) !?[]const u8 {
    var i: usize = 0;
    while (i < headers.len) {
        if (i + 2 > headers.len) return error.InvalidBedrockEventHeaders;
        const name_len: usize = headers[i];
        i += 1;
        if (i + name_len + 1 > headers.len) return error.InvalidBedrockEventHeaders;
        const name = headers[i .. i + name_len];
        i += name_len;
        const value_type = headers[i];
        i += 1;
        switch (value_type) {
            0, 1 => {
                if (std.mem.eql(u8, name, wanted)) return null;
            },
            2 => {
                if (i + 1 > headers.len) return error.InvalidBedrockEventHeaders;
                i += 1;
            },
            3 => {
                if (i + 2 > headers.len) return error.InvalidBedrockEventHeaders;
                i += 2;
            },
            4 => {
                if (i + 4 > headers.len) return error.InvalidBedrockEventHeaders;
                i += 4;
            },
            5, 8 => {
                if (i + 8 > headers.len) return error.InvalidBedrockEventHeaders;
                i += 8;
            },
            6, 7 => {
                if (i + 2 > headers.len) return error.InvalidBedrockEventHeaders;
                const len: usize = (@as(usize, headers[i]) << 8) | headers[i + 1];
                i += 2;
                if (i + len > headers.len) return error.InvalidBedrockEventHeaders;
                const value = headers[i .. i + len];
                i += len;
                if (value_type == 7 and std.mem.eql(u8, name, wanted)) return value;
            },
            9 => {
                if (i + 16 > headers.len) return error.InvalidBedrockEventHeaders;
                i += 16;
            },
            else => return error.InvalidBedrockEventHeaders,
        }
    }
    return null;
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn numberU64(value: ?std.json.Value) u64 {
    const v = value orelse return 0;
    return switch (v) {
        .integer => |n| if (n > 0) @intCast(n) else 0,
        .float => |n| if (n > 0) @intFromFloat(n) else 0,
        else => 0,
    };
}

fn mapStopReason(reason: []const u8) []const u8 {
    if (std.mem.eql(u8, reason, "end_turn") or std.mem.eql(u8, reason, "stop_sequence")) return "stop";
    if (std.mem.eql(u8, reason, "max_tokens") or std.mem.eql(u8, reason, "model_context_window_exceeded")) return "length";
    if (std.mem.eql(u8, reason, "tool_use")) return "toolUse";
    return "error";
}

fn humanExceptionPrefix(typ: []const u8) []const u8 {
    if (std.mem.eql(u8, typ, "InternalServerException")) return "Internal server error";
    if (std.mem.eql(u8, typ, "ModelStreamErrorException")) return "Model stream error";
    if (std.mem.eql(u8, typ, "ValidationException")) return "Validation error";
    if (std.mem.eql(u8, typ, "ThrottlingException")) return "Throttling error";
    if (std.mem.eql(u8, typ, "ServiceUnavailableException")) return "Service unavailable";
    return typ;
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

fn httpErrorResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8, status: u16, body: []const u8) !ai.ModelResponse {
    return .{
        .content = try std.fmt.allocPrint(gpa, "HTTP {d} from Bedrock: {s}", .{ status, body }),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "error"),
    };
}

fn streamEndedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !ai.ModelResponse {
    return .{
        .content = try gpa.dupe(u8, "Bedrock stream ended without a stop reason"),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "error"),
    };
}

// Test helper: build one valid AWS EventStream frame with string pseudo-headers.
fn testFrame(gpa: std.mem.Allocator, message_type: []const u8, event_type: []const u8, payload: []const u8) ![]u8 {
    var headers: std.ArrayList(u8) = .empty;
    defer headers.deinit(gpa);
    try appendStringHeader(gpa, &headers, ":message-type", message_type);
    try appendStringHeader(gpa, &headers, ":event-type", event_type);
    try appendStringHeader(gpa, &headers, ":content-type", "application/json");
    const total_len: usize = 12 + headers.items.len + payload.len + 4;
    var frame = try gpa.alloc(u8, total_len);
    writeU32Be(frame[0..4], @intCast(total_len));
    writeU32Be(frame[4..8], @intCast(headers.items.len));
    writeU32Be(frame[8..12], std.hash.Crc32.hash(frame[0..8]));
    @memcpy(frame[12 .. 12 + headers.items.len], headers.items);
    @memcpy(frame[12 + headers.items.len .. total_len - 4], payload);
    writeU32Be(frame[total_len - 4 ..], std.hash.Crc32.hash(frame[0 .. total_len - 4]));
    return frame;
}

fn appendStringHeader(gpa: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
    try out.append(gpa, @intCast(name.len));
    try out.appendSlice(gpa, name);
    try out.append(gpa, 7); // string
    try out.append(gpa, @intCast(value.len >> 8));
    try out.append(gpa, @intCast(value.len));
    try out.appendSlice(gpa, value);
}

test "Bedrock SigV4 signing matches deterministic vector" {
    const gpa = std.testing.allocator;
    var sig = try signAwsRequest(
        gpa,
        "POST",
        "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-test/converse-stream",
        "{\"messages\":[]}",
        .{
            .access_key_id = "AKIDEXAMPLE",
            .secret_access_key = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        },
        "us-east-1",
        1704164645,
    );
    defer sig.deinit(gpa);
    try std.testing.expectEqualStrings("20240102T030405Z", sig.amz_date[0..]);
    try std.testing.expectEqualStrings("5e4ce7b36ba37b78a5d5f9fd08e6b7b54ba6879d651aa46ec9e1d6fa24ebe30a", sig.payload_hash[0..]);
    try std.testing.expectEqualStrings(
        "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20240102/us-east-1/bedrock/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=4bd4f4809acc40548d4d9be1fb5d1d91eb48e8e4916b19fb6239c28219d08825",
        sig.authorization,
    );
}

test "Bedrock region resolution prefers ARN then configured region then endpoint" {
    try std.testing.expectEqualStrings(
        "us-gov-west-1",
        inferBedrockRegion(
            "arn:aws-us-gov:bedrock:us-gov-west-1:123456789012:application-inference-profile/abc",
            "https://bedrock-runtime.eu-central-1.amazonaws.com",
            "us-east-2",
        ),
    );
    try std.testing.expectEqualStrings("us-east-2", inferBedrockRegion("model", "https://bedrock-runtime.eu-central-1.amazonaws.com", "us-east-2"));
    try std.testing.expectEqualStrings("eu-central-1", inferBedrockRegion("model", "https://bedrock-runtime.eu-central-1.amazonaws.com", null));
    try std.testing.expectEqualStrings("us-east-1", inferBedrockRegion("model", "https://bedrock-vpc.example", null));

    const retargeted = try effectiveBedrockBaseUrl(std.testing.allocator, "https://bedrock-runtime.us-east-1.amazonaws.com", "eu-west-2");
    defer std.testing.allocator.free(retargeted);
    try std.testing.expectEqualStrings("https://bedrock-runtime.eu-west-2.amazonaws.com", retargeted);

    const custom = try effectiveBedrockBaseUrl(std.testing.allocator, "https://bedrock-vpc.example", "eu-west-2");
    defer std.testing.allocator.free(custom);
    try std.testing.expectEqualStrings("https://bedrock-vpc.example", custom);
}

test "Bedrock request serializes system user assistant tools results and cache" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "hello", .image_b64 = "aGVsbG8=", .image_mime = "image/png", .images = &.{.{ .data_b64 = "d29ybGQ=", .mime_type = "image/jpeg" }} },
        .{ .role = "assistant", .provider = "amazon-bedrock", .model = "anthropic.claude-sonnet-4-20250514-v1:0", .thinking = "plan", .thinking_signature = "sig", .content = "using tool", .tool_calls_json = "[{\"id\":\"call:1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"a\\\"}\"}}]" },
        .{ .role = "tool", .tool_call_id = "call:1", .tool_name = "read", .content = "ok", .tool_is_error = false },
    };
    const tools = "[{\"type\":\"function\",\"function\":{\"name\":\"read\",\"description\":\"Read\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}}}]";
    const body = try buildRequestBody(gpa, "anthropic.claude-sonnet-4-20250514-v1:0", &messages, tools, .{ .thinking = .high, .max_tokens = 4096, .cache_retention = .long });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"system\":[{\"text\":\"system\"},{\"cachePoint\":{\"type\":\"default\",\"ttl\":\"1h\"}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"toolUseId\":\"call_1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"toolResult\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoningText\":{\"text\":\"plan\",\"signature\":\"sig\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"toolConfig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"maxTokens\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"budget_tokens\":16384") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"bytes\":\"aGVsbG8=\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"bytes\":\"d29ybGQ=\"") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body, "\"image\":{"));
}

test "Bedrock cache points are gated to supported Claude models" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system" },
        .{ .role = "user", .content = "hello" },
    };
    const nova = try buildRequestBody(gpa, "amazon.nova-pro-v1:0", &messages, "[]", .{ .cache_retention = .long });
    defer gpa.free(nova);
    try std.testing.expect(std.mem.indexOf(u8, nova, "cachePoint") == null);

    const haiku = try buildRequestBody(gpa, "anthropic.claude-3-5-haiku-20241022-v1:0", &messages, "[]", .{ .cache_retention = .short });
    defer gpa.free(haiku);
    try std.testing.expect(std.mem.indexOf(u8, haiku, "cachePoint") != null);
}

test "Bedrock Claude replay without thinking signature falls back to text" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "assistant", .thinking = "unsigned prior thought", .content = "answer" },
    };
    const body = try buildRequestBody(gpa, "anthropic.claude-sonnet-4-20250514-v1:0", &messages, "[]", .{});
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "reasoningContent") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "{\"text\":\"unsigned prior thought\"}") != null);
}

test "Bedrock adaptive Claude thinking maps effort and omits legacy beta" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    const body = try buildRequestBody(gpa, "global.anthropic.claude-opus-4-8-v1", &messages, "[]", .{ .thinking = .xhigh });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"thinking\":{\"type\":\"adaptive\",\"display\":\"summarized\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"output_config\":{\"effort\":\"xhigh\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "anthropic_beta") == null);
}

test "Bedrock GovCloud Claude thinking omits display" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    const body = try buildRequestBody(gpa, "us-gov.anthropic.claude-sonnet-4-5-20250929-v1:0", &messages, "[]", .{ .thinking = .high });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"enabled\",\"budget_tokens\":16384") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"display\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "anthropic_beta") != null);
}

test "Bedrock URL percent encodes model path label" {
    const gpa = std.testing.allocator;
    const url = try buildConverseStreamUrl(gpa, "https://bedrock-runtime.us-east-1.amazonaws.com/", "arn:aws:bedrock:us-east-1:123:inference-profile/a");
    defer gpa.free(url);
    try std.testing.expectEqualStrings("https://bedrock-runtime.us-east-1.amazonaws.com/model/arn%3Aaws%3Abedrock%3Aus-east-1%3A123%3Ainference-profile%2Fa/converse-stream", url);
}

test "Bedrock response observer forwards raw gateway headers before streaming" {
    const head = try std.http.Client.Response.Head.parse(
        "HTTP/1.1 200 OK\r\n" ++
            "content-type: application/vnd.amazon.eventstream\r\n" ++
            "x-amzn-requestid: req-123\r\n" ++
            "x-bifrost-provider: bedrock\r\n" ++
            "x-bifrost-resolved-model: model-raw\r\n\r\n",
    );
    const Probe = struct {
        calls: usize = 0,
        status: u16 = 0,
        request_id: bool = false,
        provider: bool = false,
        model: bool = false,
        fn callback(raw: ?*anyopaque, response: ai.ProviderResponse) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            self.status = response.status;
            for (response.headers) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, "x-amzn-requestid") and std.mem.eql(u8, header.value, "req-123")) self.request_id = true;
                if (std.ascii.eqlIgnoreCase(header.name, "x-bifrost-provider") and std.mem.eql(u8, header.value, "bedrock")) self.provider = true;
                if (std.ascii.eqlIgnoreCase(header.name, "x-bifrost-resolved-model") and std.mem.eql(u8, header.value, "model-raw")) self.model = true;
            }
        }
    };
    var probe = Probe{};
    var observer = ResponseObserverContext{ .gpa = std.testing.allocator, .callback = Probe.callback, .callback_ctx = &probe };
    try ResponseObserverContext.observe(&observer, head);
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(@as(u16, 200), probe.status);
    try std.testing.expect(probe.request_id and probe.provider and probe.model);
}

test "Bedrock AWS EventStream accumulates text thinking tools usage and stop reason" {
    const gpa = std.testing.allocator;
    var live = BedrockLive.init(gpa, "amazon-bedrock", "anthropic.claude-test", .{ .input = 1, .output = 2, .cache_read = 0.1, .cache_write = 1.25 }, null, null, null);
    defer live.deinit();
    const fixtures = [_]struct { typ: []const u8, payload: []const u8 }{
        .{ .typ = "messageStart", .payload = "{\"role\":\"assistant\"}" },
        .{ .typ = "contentBlockDelta", .payload = "{\"contentBlockIndex\":0,\"delta\":{\"reasoningContent\":{\"text\":\"think\",\"signature\":\"sig\"}}}" },
        .{ .typ = "contentBlockDelta", .payload = "{\"contentBlockIndex\":1,\"delta\":{\"text\":\"hello \"}}" },
        .{ .typ = "contentBlockStart", .payload = "{\"contentBlockIndex\":2,\"start\":{\"toolUse\":{\"toolUseId\":\"t1\",\"name\":\"read\"}}}" },
        .{ .typ = "contentBlockDelta", .payload = "{\"contentBlockIndex\":2,\"delta\":{\"toolUse\":{\"input\":\"{\\\"path\\\":\"}}}" },
        .{ .typ = "contentBlockDelta", .payload = "{\"contentBlockIndex\":2,\"delta\":{\"toolUse\":{\"input\":\"\\\"a\\\"}\"}}}" },
        .{ .typ = "contentBlockStop", .payload = "{\"contentBlockIndex\":2}" },
        .{ .typ = "metadata", .payload = "{\"usage\":{\"inputTokens\":100,\"outputTokens\":20,\"cacheReadInputTokens\":10,\"cacheWriteInputTokens\":5,\"totalTokens\":135}}" },
        .{ .typ = "messageStop", .payload = "{\"stopReason\":\"tool_use\"}" },
    };
    for (fixtures, 0..) |fixture, i| {
        const frame = try testFrame(gpa, "event", fixture.typ, fixture.payload);
        defer gpa.free(frame);
        // Deliberately split a frame to exercise incremental binary buffering.
        if (i == 2) {
            try live.feed(frame[0..7]);
            try live.feed(frame[7..]);
        } else try live.feed(frame);
    }
    try std.testing.expect(live.terminal);
    var response = try live.finish();
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("hello ", response.content);
    try std.testing.expectEqualStrings("think", response.thinking);
    try std.testing.expectEqualStrings("sig", response.thinking_signature);
    try std.testing.expectEqualStrings("toolUse", response.stop_reason);
    try std.testing.expectEqualStrings("tool_use", response.raw_stop_reason);
    try std.testing.expectEqual(@as(usize, 1), response.tool_calls.len);
    try std.testing.expectEqualStrings("read", response.tool_calls[0].name);
    try std.testing.expectEqualStrings("{\"path\":\"a\"}", response.tool_calls[0].arguments);
    try std.testing.expectEqual(@as(u64, 100), response.usage.input);
    try std.testing.expectEqual(@as(u64, 10), response.usage.cache_read);
    try std.testing.expect(response.usage.cost.total > 0);
}

test "Bedrock preserves and replays split redacted reasoning" {
    const gpa = std.testing.allocator;
    var live = BedrockLive.init(gpa, "amazon-bedrock", "global.openai.gpt-5.6-terra", .{}, null, null, null);
    defer live.deinit();
    try live.handleEvent("contentBlockDelta", "{\"delta\":{\"reasoningContent\":{\"redactedContent\":\"aGU=\"}}}");
    try live.handleEvent("contentBlockDelta", "{\"delta\":{\"reasoningContent\":{\"redactedContent\":\"bGxv\"}}}");
    try live.handleEvent("messageStop", "{\"stopReason\":\"end_turn\"}");
    var response = try live.finish();
    defer response.deinit(gpa);
    try std.testing.expect(response.thinking_redacted);
    try std.testing.expectEqualStrings("[Reasoning redacted]", response.thinking);
    try std.testing.expectEqualStrings("aGVsbG8=", response.thinking_signature);

    const messages = [_]ai.ChatMessage{.{
        .role = "assistant",
        .content = "done",
        .thinking = "[Reasoning redacted]",
        .thinking_signature = "aGVsbG8=",
        .thinking_redacted = true,
    }};
    const body = try buildRequestBody(gpa, "global.openai.gpt-5.6-terra", &messages, "[]", .{});
    defer gpa.free(body);
    const redacted_at = std.mem.indexOf(u8, body, "\"redactedContent\":\"aGVsbG8=\"") orelse return error.TestUnexpectedResult;
    const text_at = std.mem.indexOf(u8, body, "\"text\":\"done\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(redacted_at < text_at);
}

test "Bedrock tool choice none suppresses the tool configuration" {
    const gpa = std.testing.allocator;
    const tools = "[{\"type\":\"function\",\"function\":{\"name\":\"read\",\"parameters\":{\"type\":\"object\"}}}]";
    const body = try buildRequestBody(gpa, "amazon.nova-pro-v1:0", &.{.{ .role = "user", .content = "hi" }}, tools, .{ .tool_choice = .none });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "toolConfig") == null);
}

test "Bedrock event stream validates CRC and surfaces exceptions" {
    const gpa = std.testing.allocator;
    var live = BedrockLive.init(gpa, "amazon-bedrock", "m", .{}, null, null, null);
    defer live.deinit();
    const frame = try testFrame(gpa, "exception", "ThrottlingException", "{\"message\":\"slow down\"}");
    defer gpa.free(frame);
    try live.feed(frame);
    try std.testing.expect(live.terminal_error);
    try std.testing.expect(std.mem.indexOf(u8, live.error_message, "Throttling error: slow down") != null);

    var bad = try gpa.dupe(u8, frame);
    defer gpa.free(bad);
    bad[bad.len - 5] ^= 1;
    var broken = BedrockLive.init(gpa, "amazon-bedrock", "m", .{}, null, null, null);
    defer broken.deinit();
    try std.testing.expectError(error.BedrockMessageCrcMismatch, broken.feed(bad));
}

test "Bedrock standard endpoint parsing supports FIPS and China partitions" {
    try std.testing.expectEqualStrings("us-gov-west-1", standardBedrockEndpointRegion("https://bedrock-runtime-fips.us-gov-west-1.amazonaws.com").?);
    try std.testing.expectEqualStrings("cn-north-1", standardBedrockEndpointRegion("https://bedrock-runtime.cn-north-1.amazonaws.com.cn").?);
    const fips = try effectiveBedrockBaseUrl(std.testing.allocator, "https://bedrock-runtime-fips.us-gov-west-1.amazonaws.com", "us-gov-east-1");
    defer std.testing.allocator.free(fips);
    try std.testing.expectEqualStrings("https://bedrock-runtime-fips.us-gov-east-1.amazonaws.com", fips);
}

test "generic SigV4 signer supports STS service and form content type" {
    const gpa = std.testing.allocator;
    var signed = try signAwsRequestForService(
        gpa,
        "POST",
        "https://sts.us-east-1.amazonaws.com/",
        "Action=GetCallerIdentity&Version=2011-06-15",
        .{ .access_key_id = "AKIDEXAMPLE", .secret_access_key = "secret" },
        "us-east-1",
        "sts",
        "application/x-www-form-urlencoded; charset=utf-8",
        1704153600,
    );
    defer signed.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, signed.authorization, "/us-east-1/sts/aws4_request") != null);
}

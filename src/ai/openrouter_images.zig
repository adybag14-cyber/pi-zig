//! Native OpenRouter image generation (`openrouter-images`).
//! Upstream exposes image generation separately from chat ModelClient APIs.
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");
const http_fetch = @import("http_fetch.zig");
const retry_mod = @import("retry.zig");
const metadata = @import("request_metadata.zig");
const providers = @import("providers.zig");
const cost_mod = @import("cost.zig");

pub const ImageInput = struct {
    mime_type: []const u8,
    data: []const u8,
};

pub const Input = union(enum) {
    text: []const u8,
    image: ImageInput,
};

pub const ImageOutput = struct {
    mime_type: []u8,
    data: []u8,
};

pub const Output = union(enum) {
    text: []u8,
    image: ImageOutput,

    fn deinit(self: *Output, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .text => |text| gpa.free(text),
            .image => |image| {
                gpa.free(image.mime_type);
                gpa.free(image.data);
            },
        }
        self.* = undefined;
    }
};

pub const Response = struct {
    api: []u8,
    provider: []u8,
    model: []u8,
    response_id: []u8 = &.{},
    output: []Output,
    stop_reason: []u8,
    error_message: []u8 = &.{},
    usage: cost_mod.Usage = .{},
    provider_status: ?u16 = null,
    provider_retry_after_ms: ?u64 = null,
    provider_should_retry: ?bool = null,

    fn providerRetryMeta(self: Response) retry_mod.ProviderResponseMeta {
        return .{ .status = self.provider_status, .retry_after_ms = self.provider_retry_after_ms, .should_retry = self.provider_should_retry };
    }

    pub fn deinit(self: *Response, gpa: std.mem.Allocator) void {
        gpa.free(self.api);
        gpa.free(self.provider);
        gpa.free(self.model);
        if (self.response_id.len > 0) gpa.free(self.response_id);
        for (self.output) |*item| item.deinit(gpa);
        gpa.free(self.output);
        gpa.free(self.stop_reason);
        if (self.error_message.len > 0) gpa.free(self.error_message);
        self.* = undefined;
    }
};

pub const Client = struct {
    gpa: std.mem.Allocator,
    io: Io,
    /// Process/provider proxy environment.
    environ: ?*const std.process.Environ.Map = null,
    /// Global settings.json `httpProxy` fallback.
    proxy_url: ?[]const u8 = null,
    /// Provider-internal request retry settings.
    provider_retry: retry_mod.ProviderPolicy = .{ .max_retries = 2 },
    api_key: []const u8,
    base_url: []const u8 = "https://openrouter.ai/api/v1",
    provider_id: []const u8 = "openrouter",
    model: []const u8,
    output_text: bool = false,
    custom_headers: []const metadata.Header = &.{},
    model_cost: providers.ModelCost = .{},
    abort_flag: ?*bool = null,

    pub fn generate(self: *Client, gpa: std.mem.Allocator, input: []const Input) !Response {
        if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
        const payload = try buildRequestBody(gpa, self.model, input, self.output_text);
        defer gpa.free(payload);
        const trimmed = std.mem.trimEnd(u8, self.base_url, "/");
        const url = try std.fmt.allocPrint(gpa, "{s}/chat/completions", .{trimmed});
        defer gpa.free(url);

        var retry_index: usize = 0;
        while (true) {
            const response = self.requestOnce(gpa, url, payload) catch |err| {
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                if (retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            if (std.mem.eql(u8, response.stop_reason, "error") and retry_index < self.provider_retry.max_retries and retry_mod.isRetryableProviderResponse(response.providerRetryMeta())) {
                var retry_response = response;
                const delay_ms = retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, retry_response.provider_retry_after_ms) catch |err| {
                    retry_response.deinit(gpa);
                    return err;
                };
                retry_response.deinit(gpa);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            }
            return response;
        }
    }

    fn requestOnce(self: *Client, gpa: std.mem.Allocator, url: []const u8, payload: []const u8) !Response {
        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena.deinit();
        var http: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http.deinit();
        _ = try http_proxy.configureClient(&http, proxy_arena.allocator(), url, .{
            .environ = self.environ,
            .setting = self.proxy_url,
        });
        var body: std.Io.Writer.Allocating = .init(gpa);
        defer body.deinit();
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
        defer gpa.free(authorization);
        try putHeader(gpa, &headers, "content-type", "application/json");
        try putHeader(gpa, &headers, "accept", "application/json");
        try putHeader(gpa, &headers, "authorization", authorization);
        for (self.custom_headers) |header| try putHeader(gpa, &headers, header.name, header.value);

        const result = try http_fetch.fetchControlled(&http, .{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .keep_alive = false,
            .extra_headers = headers.items,
            .response_writer = &body.writer,
        }, self.provider_retry.timeout_ms, self.abort_flag);
        const status = result.status;
        const raw = try body.toOwnedSlice();
        defer gpa.free(raw);
        if (status < 200 or status >= 300) {
            var response = try errorResponse(gpa, self.provider_id, self.model, status, raw);
            response.provider_status = result.provider.status;
            response.provider_retry_after_ms = result.provider.retry_after_ms;
            response.provider_should_retry = result.provider.should_retry;
            return response;
        }
        return try parseResponse(gpa, raw, self.provider_id, self.model, self.model_cost);
    }
};

fn putHeader(gpa: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
    for (headers.items) |*header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            header.* = .{ .name = name, .value = value };
            return;
        }
    }
    try headers.append(gpa, .{ .name = name, .value = value });
}

pub fn buildRequestBody(gpa: std.mem.Allocator, model: []const u8, input: []const Input, output_text: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.writeAll(",\"messages\":[{\"role\":\"user\",\"content\":[");
    for (input, 0..) |item, index| {
        if (index > 0) try w.writeByte(',');
        switch (item) {
            .text => |text| {
                try w.writeAll("{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(text, .{}, w);
                try w.writeByte('}');
            },
            .image => |image| {
                try w.writeAll("{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:");
                try w.writeAll(image.mime_type);
                try w.writeAll(";base64,");
                try w.writeAll(image.data);
                try w.writeAll("\"}}");
            },
        }
    }
    try w.writeAll("]}],\"stream\":false,\"modalities\":[\"image\"");
    if (output_text) try w.writeAll(",\"text\"");
    try w.writeAll("]}");
    return out.toOwnedSlice();
}

fn valueU64(obj: std.json.ObjectMap, key: []const u8) u64 {
    const value = obj.get(key) orelse return 0;
    return switch (value) {
        .integer => |n| if (n > 0) @intCast(n) else 0,
        .float => |n| if (n > 0) @intFromFloat(n) else 0,
        else => 0,
    };
}

fn imageDataUrl(value: std.json.Value) ?[]const u8 {
    if (value == .string) return value.string;
    if (value == .object) {
        const url = value.object.get("url") orelse return null;
        if (url == .string) return url.string;
    }
    return null;
}

fn appendDataImage(gpa: std.mem.Allocator, items: *std.ArrayList(Output), url: []const u8) !void {
    if (!std.mem.startsWith(u8, url, "data:")) return;
    const semi = std.mem.indexOfScalarPos(u8, url, 5, ';') orelse return;
    const marker = ";base64,";
    if (!std.mem.startsWith(u8, url[semi..], marker)) return;
    const data_start = semi + marker.len;
    if (data_start > url.len) return;
    try items.append(gpa, .{ .image = .{
        .mime_type = try gpa.dupe(u8, url[5..semi]),
        .data = try gpa.dupe(u8, url[data_start..]),
    } });
}

pub fn parseResponse(gpa: std.mem.Allocator, raw: []const u8, provider: []const u8, model: []const u8, model_cost: providers.ModelCost) !Response {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;
    const root = parsed.value.object;
    var items: std.ArrayList(Output) = .empty;
    errdefer {
        for (items.items) |*item| item.deinit(gpa);
        items.deinit(gpa);
    }
    var response_id: []u8 = &.{};
    errdefer if (response_id.len > 0) gpa.free(response_id);
    if (root.get("id")) |id| {
        if (id == .string) response_id = try gpa.dupe(u8, id.string);
    }

    if (root.get("choices")) |choices| if (choices == .array and choices.array.items.len > 0) {
        const choice = choices.array.items[0];
        if (choice == .object) if (choice.object.get("message")) |message| if (message == .object) {
            if (message.object.get("content")) |content| if (content == .string and content.string.len > 0)
                try items.append(gpa, .{ .text = try gpa.dupe(u8, content.string) });
            if (message.object.get("images")) |images| if (images == .array) {
                for (images.array.items) |image| {
                    if (image != .object) continue;
                    const raw_url = image.object.get("image_url") orelse continue;
                    const url = imageDataUrl(raw_url) orelse continue;
                    try appendDataImage(gpa, &items, url);
                }
            };
        };
    };

    var usage: cost_mod.Usage = .{};
    if (root.get("usage")) |raw_usage| if (raw_usage == .object) {
        const prompt = valueU64(raw_usage.object, "prompt_tokens");
        usage.output = valueU64(raw_usage.object, "completion_tokens");
        var cached: u64 = 0;
        var cache_write: u64 = 0;
        if (raw_usage.object.get("prompt_tokens_details")) |details| if (details == .object) {
            cached = valueU64(details.object, "cached_tokens");
            cache_write = valueU64(details.object, "cache_write_tokens");
        };
        usage.cache_write = cache_write;
        usage.cache_read = if (cache_write > 0) cached -| cache_write else cached;
        usage.input = prompt -| usage.cache_read -| usage.cache_write;
        usage.normalizeTotal();
        _ = cost_mod.calculate(model_cost, &usage);
    };

    return .{
        .api = try gpa.dupe(u8, "openrouter-images"),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .response_id = response_id,
        .output = try items.toOwnedSlice(gpa),
        .stop_reason = try gpa.dupe(u8, "stop"),
        .usage = usage,
    };
}

fn abortedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !Response {
    return .{
        .api = try gpa.dupe(u8, "openrouter-images"),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .output = try gpa.alloc(Output, 0),
        .stop_reason = try gpa.dupe(u8, "aborted"),
        .error_message = try gpa.dupe(u8, "Request aborted"),
    };
}

fn errorResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8, status: u16, raw: []const u8) !Response {
    const capped = if (raw.len > 4096) raw[0..4096] else raw;
    return .{
        .api = try gpa.dupe(u8, "openrouter-images"),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .output = try gpa.alloc(Output, 0),
        .stop_reason = try gpa.dupe(u8, "error"),
        .error_message = try std.fmt.allocPrint(gpa, "OpenRouter image API error ({d}): {s}", .{ status, capped }),
    };
}

test "OpenRouter images request serializes multimodal input and modalities" {
    const gpa = std.testing.allocator;
    const input = [_]Input{
        .{ .text = "Generate a dog" },
        .{ .image = .{ .mime_type = "image/png", .data = "ZmFrZQ==" } },
    };
    const body = try buildRequestBody(gpa, "google/gemini-image", &input, true);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"modalities\":[\"image\",\"text\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "data:image/png;base64,ZmFrZQ==") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "Generate a dog") != null);
}

test "OpenRouter images parser returns text data image id and cost" {
    const gpa = std.testing.allocator;
    const raw =
        \\{"id":"img-1","usage":{"prompt_tokens":12,"completion_tokens":34,"prompt_tokens_details":{"cached_tokens":4,"cache_write_tokens":1}},"choices":[{"message":{"content":"Here is your image.","images":[{"image_url":"data:image/png;base64,ZmFrZS1wbmc="},{"image_url":{"url":"https://example.invalid/x.png"}}]}}]}
    ;
    var response = try parseResponse(gpa, raw, "openrouter", "image-model", .{ .input = 1.0, .output = 2.0, .cache_read = 0.1, .cache_write = 1.25 });
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("img-1", response.response_id);
    try std.testing.expectEqual(@as(usize, 2), response.output.len);
    try std.testing.expectEqualStrings("Here is your image.", response.output[0].text);
    try std.testing.expectEqualStrings("image/png", response.output[1].image.mime_type);
    try std.testing.expectEqualStrings("ZmFrZS1wbmc=", response.output[1].image.data);
    try std.testing.expectEqual(@as(u64, 8), response.usage.input);
    try std.testing.expectEqual(@as(u64, 3), response.usage.cache_read);
    try std.testing.expectEqual(@as(u64, 1), response.usage.cache_write);
    try std.testing.expectEqual(@as(u64, 34), response.usage.output);
    try std.testing.expect(response.usage.cost.total > 0);
}

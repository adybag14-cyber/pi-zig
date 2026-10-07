//! Direct native classifier/image transport adapters used by SDK providers.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const classifier = @import("../ai/classifier.zig");
const images = @import("../ai/openrouter_images.zig");
const metadata = @import("../ai/request_metadata.zig");
const providers = @import("../ai/providers.zig");
const c = engine_mod.c;

fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (argc < 2) return sdk.fail(engine, error.NativeSDKMissingArgument);
    return execute(engine, args[0], args[1], if (argc > 2) args[2] else c.pi_js_undefined(), magic == 1) catch |err| sdk.fail(engine, err);
}
pub fn install(engine: *engine_mod.Engine, provider: c.JSValue) !void {
    try sdk.put(engine, provider, "classify", try engine.checked(c.pi_js_function_magic(engine.context, callback, "classify", 3, 0)));
    try sdk.put(engine, provider, "generateImages", try engine.checked(c.pi_js_function_magic(engine.context, callback, "generateImages", 3, 1)));
}
fn usage(engine: *engine_mod.Engine, value: anytype) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "input", c.JS_NewInt64(engine.context, @intCast(value.input)));
    try sdk.put(engine, result, "output", c.JS_NewInt64(engine.context, @intCast(value.output)));
    try sdk.put(engine, result, "cacheRead", c.JS_NewInt64(engine.context, @intCast(value.cache_read)));
    try sdk.put(engine, result, "cacheWrite", c.JS_NewInt64(engine.context, @intCast(value.cache_write)));
    try sdk.put(engine, result, "totalTokens", c.JS_NewInt64(engine.context, @intCast(value.input + value.output + value.cache_read + value.cache_write)));
    const price = try sdk.object(engine);
    defer engine.freeValue(price);
    inline for (.{ .{ "input", value.cost.input }, .{ "output", value.cost.output }, .{ "cacheRead", value.cost.cache_read }, .{ "cacheWrite", value.cost.cache_write }, .{ "total", value.cost.total } }) |item| try sdk.put(engine, price, item[0], c.JS_NewFloat64(engine.context, item[1]));
    try sdk.put(engine, result, "cost", c.JS_DupValue(engine.context, price));
    return result;
}
fn execute(engine: *engine_mod.Engine, model: c.JSValue, context: c.JSValue, options: c.JSValue, image_operation: bool) !c.JSValue {
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const raw_model = try engine.stringify(model);
    defer engine.gpa.free(raw_model);
    const info = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_model, .{ .allocate = .alloc_always });
    const raw_context = try engine.stringify(context);
    defer engine.gpa.free(raw_context);
    const input = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_context, .{ .allocate = .alloc_always });
    const raw_options = try engine.stringify(options);
    defer engine.gpa.free(raw_options);
    const configured = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw_options, .{ .allocate = .alloc_always });
    if (info != .object or configured != .object or input != .object) return error.NativeSDKInvalidModelRequest;
    const id = string(info.object, "id") orelse return error.NativeSDKInvalidModelRequest;
    const provider = string(info.object, "provider") orelse return error.NativeSDKInvalidModelRequest;
    const api = string(info.object, "api") orelse return error.NativeSDKInvalidModelRequest;
    const base = string(info.object, "baseUrl") orelse return error.NativeSDKMissingBaseUrl;
    const key = string(configured.object, "apiKey") orelse "";
    var headers: std.ArrayList(metadata.Header) = .empty;
    var classifier_headers: std.ArrayList(classifier.Header) = .empty;
    if (configured.object.get("headers")) |fields| if (fields == .object) {
        var iterator = fields.object.iterator();
        while (iterator.next()) |field| {
            try classifier_headers.append(allocator, .{ .name = field.key_ptr.*, .value = if (field.value_ptr.* == .string) field.value_ptr.string else null });
            if (field.value_ptr.* == .string) try headers.append(allocator, .{ .name = field.key_ptr.*, .value = field.value_ptr.string });
        }
    };
    const result = if (!image_operation) classified: {
        const kind = classifier.Api.parse(api) orelse return error.UnsupportedClassifierApi;
        var client: classifier.Client = .{ .io = io, .model = .{ .api = kind, .provider = provider, .id = id, .base_url = base, .input_image = hasInput(info.object, "image"), .cost = prices(info.object) }, .api_key = key, .headers = classifier_headers.items };
        if (configured.object.get("temperature")) |temperature| client.temperature = number(temperature) orelse 1;
        if (configured.object.get("maxRetries")) |retries| client.provider_retry.max_retries = @intFromFloat(number(retries) orelse 2);
        var response = try awaitTransport(engine, &client, raw_context, options);
        defer response.deinit(engine.gpa);
        const value = try sdk.object(engine);
        errdefer engine.freeValue(value);
        try sdk.put(engine, value, "api", try sdk.text(engine, response.api.name()));
        try sdk.put(engine, value, "provider", try sdk.text(engine, response.provider));
        try sdk.put(engine, value, "model", try sdk.text(engine, response.model));
        try sdk.put(engine, value, "answers", try engine.fromJsonValue(.{ .object = response.answers }));
        try sdk.put(engine, value, "stopReason", try sdk.text(engine, switch (response.stop_reason) {
            .stop => "stop",
            .aborted => "aborted",
            .err => "error",
        }));
        try sdk.put(engine, value, "timestamp", c.JS_NewInt64(engine.context, response.timestamp_ms));
        if (response.error_message) |message| try sdk.put(engine, value, "errorMessage", try sdk.text(engine, message));
        if (response.usage) |accounting| try sdk.put(engine, value, "usage", try usage(engine, accounting));
        break :classified value;
    } else generated: {
        if (!std.mem.eql(u8, api, "openrouter-images")) return error.UnsupportedImageApi;
        const parts = input.object.get("input") orelse return error.NativeSDKInvalidImageContext;
        if (parts != .array) return error.NativeSDKInvalidImageContext;
        var content: std.ArrayList(images.Input) = .empty;
        for (parts.array.items) |part| {
            if (part != .object) return error.NativeSDKInvalidImageContext;
            const typ = string(part.object, "type") orelse return error.NativeSDKInvalidImageContext;
            if (std.mem.eql(u8, typ, "text")) try content.append(allocator, .{ .text = string(part.object, "text") orelse return error.NativeSDKInvalidImageContext }) else if (std.mem.eql(u8, typ, "image")) try content.append(allocator, .{ .image = .{ .mime_type = string(part.object, "mimeType") orelse return error.NativeSDKInvalidImageContext, .data = string(part.object, "data") orelse return error.NativeSDKInvalidImageContext } });
        }
        var client: images.Client = .{ .gpa = engine.gpa, .io = io, .api_key = key, .base_url = base, .provider_id = provider, .model = id, .custom_headers = headers.items, .model_cost = prices(info.object) };
        if (configured.object.get("maxRetries")) |retries| client.provider_retry.max_retries = @intFromFloat(number(retries) orelse 2);
        var response = try awaitTransport(engine, &client, content.items, options);
        defer response.deinit(engine.gpa);
        const value = try sdk.object(engine);
        errdefer engine.freeValue(value);
        try sdk.put(engine, value, "api", try sdk.text(engine, response.api));
        try sdk.put(engine, value, "provider", try sdk.text(engine, response.provider));
        try sdk.put(engine, value, "model", try sdk.text(engine, response.model));
        const output = try sdk.array(engine);
        defer engine.freeValue(output);
        for (response.output) |part| {
            const item = try sdk.object(engine);
            defer engine.freeValue(item);
            switch (part) {
                .text => |text| {
                    try sdk.put(engine, item, "type", try sdk.text(engine, "text"));
                    try sdk.put(engine, item, "text", try sdk.text(engine, text));
                },
                .image => |image| {
                    try sdk.put(engine, item, "type", try sdk.text(engine, "image"));
                    try sdk.put(engine, item, "data", try sdk.text(engine, image.data));
                    try sdk.put(engine, item, "mimeType", try sdk.text(engine, image.mime_type));
                },
            }
            try sdk.append(engine, output, c.JS_DupValue(engine.context, item));
        }
        try sdk.put(engine, value, "output", c.JS_DupValue(engine.context, output));
        try sdk.put(engine, value, "stopReason", try sdk.text(engine, response.stop_reason));
        try sdk.put(engine, value, "timestamp", c.JS_NewInt64(engine.context, std.Io.Clock.real.now(io).toMilliseconds()));
        if (response.response_id.len > 0) try sdk.put(engine, value, "responseId", try sdk.text(engine, response.response_id));
        if (response.error_message.len > 0) try sdk.put(engine, value, "errorMessage", try sdk.text(engine, response.error_message));
        if (!std.mem.eql(u8, response.stop_reason, "error") and !std.mem.eql(u8, response.stop_reason, "aborted")) try sdk.put(engine, value, "usage", try usage(engine, response.usage));
        break :generated value;
    };
    defer engine.freeValue(result);
    return sdk.promise(engine, result);
}
fn string(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return if (value == .string) value.string else null;
}
fn hasInput(object: std.json.ObjectMap, name: []const u8) bool {
    const inputs = object.get("input") orelse return false;
    if (inputs != .array) return false;
    for (inputs.array.items) |item| if (item == .string and std.mem.eql(u8, item.string, name)) return true;
    return false;
}
fn number(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => @floatFromInt(value.integer),
        .float => value.float,
        else => null,
    };
}
fn prices(object: std.json.ObjectMap) providers.ModelCost {
    const price = object.get("cost") orelse return .{};
    if (price != .object) return .{};
    return .{ .input = number(price.object.get("input") orelse .null) orelse 0, .output = number(price.object.get("output") orelse .null) orelse 0, .cache_read = number(price.object.get("cacheRead") orelse .null) orelse 0, .cache_write = number(price.object.get("cacheWrite") orelse .null) orelse 0 };
}

fn awaitTransport(engine: *engine_mod.Engine, client: anytype, input: anytype, options: c.JSValue) !if (@TypeOf(client.*) == classifier.Client) classifier.Result else images.Response {
    const Client = @TypeOf(client.*);
    const Result = if (Client == classifier.Client) classifier.Result else images.Response;
    const Input = @TypeOf(input);
    const Work = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        input: Input,
        done: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This()) anyerror!Result {
            defer self.done.store(true, .release);
            return if (Client == classifier.Client) self.client.classify(self.allocator, self.input) else self.client.generate(self.allocator, self.input);
        }
    };
    var aborted = false;
    client.abort_flag = &aborted;
    const signal = try sdk.get(engine, options, "signal");
    defer engine.freeValue(signal);
    var work: Work = .{ .client = client, .allocator = engine.gpa, .input = input };
    const io = engine.native_io orelse return error.NativeSDKRequiresIO;
    var future = try io.concurrent(Work.run, .{&work});
    var consumed = false;
    errdefer if (!consumed) {
        @atomicStore(bool, &aborted, true, .release);
        if (future.cancel(io)) |result| {
            var owned = result;
            owned.deinit(engine.gpa);
        } else |_| {}
    };
    while (!work.done.load(.acquire)) {
        if (c.JS_IsObject(signal)) {
            const state = try sdk.get(engine, signal, "aborted");
            defer engine.freeValue(state);
            if (c.JS_ToBool(engine.context, state) == 1) {
                @atomicStore(bool, &aborted, true, .release);
                consumed = true;
                return future.cancel(io);
            }
        }
        if (engine.host_await_deadline_ms) |deadline| if (std.Io.Clock.awake.now(io).toMilliseconds() >= deadline) return error.NativeHostPromiseTimeout;
        _ = try @import("timers.zig").pumpReady(engine);
        _ = try engine.drainReadyJobs();
        if (!work.done.load(.acquire)) try io.sleep(.fromMilliseconds(1), .awake);
    }
    consumed = true;
    return future.await(io);
}

//! Native System One classifier wire contract from Pi 1.0.1.
const std = @import("std");
const costs = @import("cost.zig");
const providers = @import("providers.zig");
const metadata = @import("request_metadata.zig");
const http_fetch = @import("http_fetch.zig");
const http_proxy = @import("http_proxy.zig");
const retry = @import("retry.zig");
const llama = @import("llama_classifier.zig");

pub const Api = enum {
    typesafe_system_one,
    cloudflare_workers_ai_system_one,
    llama_cpp_classify,

    pub fn parse(value: []const u8) ?Api {
        if (std.mem.eql(u8, value, "typesafe-system-one")) return .typesafe_system_one;
        if (std.mem.eql(u8, value, "cloudflare-workers-ai-system-one")) return .cloudflare_workers_ai_system_one;
        if (std.mem.eql(u8, value, "llama-cpp-classify")) return .llama_cpp_classify;
        return null;
    }

    pub fn name(self: Api) []const u8 {
        return switch (self) {
            .typesafe_system_one => "typesafe-system-one",
            .cloudflare_workers_ai_system_one => "cloudflare-workers-ai-system-one",
            .llama_cpp_classify => "llama-cpp-classify",
        };
    }
};

pub const Model = struct {
    api: Api,
    provider: []const u8,
    id: []const u8,
    base_url: []const u8,
    cost: providers.ModelCost = .{},
    headers: []const metadata.Header = &.{},

    pub fn fromInfo(info: providers.ModelInfo) !Model {
        if (info.kind != .classifier) return error.NotClassifierModel;
        const api = Api.parse(info.operation_api orelse return error.MissingClassifierApi) orelse return error.UnsupportedClassifierApi;
        return .{ .api = api, .provider = info.providerName(), .id = info.id, .base_url = info.base_url orelse return error.MissingClassifierBaseUrl, .cost = info.cost, .headers = info.headers };
    }
};

pub const Header = struct { name: []const u8, value: ?[]const u8 };
pub const HttpResult = struct {
    status: u16,
    body: []u8,
    retry_meta: retry.ProviderResponseMeta = .{},
};
pub const FetchOverride = struct {
    context: ?*anyopaque = null,
    call: *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const std.http.Header, []const u8) anyerror!HttpResult,
};

pub const Client = struct {
    io: std.Io,
    model: Model,
    api_key: []const u8,
    environ: ?*const std.process.Environ.Map = null,
    proxy_url: ?[]const u8 = null,
    headers: []const Header = &.{},
    timeout_ms: ?u64 = null,
    abort_flag: ?*bool = null,
    provider_retry: retry.ProviderPolicy = .{ .max_retries = 2 },
    fetch_override: ?FetchOverride = null,
    response_observer: ?http_fetch.HeadObserver = null,
    temperature: f64 = 1,

    pub fn classify(self: *Client, gpa: std.mem.Allocator, context_json: []const u8) !Result {
        const timestamp = std.Io.Clock.real.now(self.io).toMilliseconds();
        if (self.aborted()) return errorResult(gpa, self.model, timestamp, "Request aborted", true);
        if (self.model.api == .llama_cpp_classify) return self.classifyLocal(gpa, context_json, timestamp) catch |err| errorResult(gpa, self.model, timestamp, @errorName(err), self.aborted());
        if (self.api_key.len == 0) return errorResult(gpa, self.model, timestamp, "No API key for classifier provider", false);
        const payload = buildPayload(gpa, self.model, context_json) catch |err| return errorResult(gpa, self.model, timestamp, @errorName(err), false);
        defer gpa.free(payload);
        const endpoint = if (self.model.api == .cloudflare_workers_ai_system_one) "run" else "systemone";
        const url = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ std.mem.trimEnd(u8, self.model.base_url, "/"), endpoint });
        defer gpa.free(url);
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
        defer gpa.free(authorization);
        try putHeader(gpa, &headers, "authorization", authorization);
        try putHeader(gpa, &headers, "content-type", "application/json");
        for (self.model.headers) |header| try putHeader(gpa, &headers, header.name, header.value);
        for (self.headers) |header| try putHeader(gpa, &headers, header.name, header.value);
        var retries: usize = 0;
        while (true) {
            if (self.aborted()) return errorResult(gpa, self.model, timestamp, "Request aborted", true);
            var response = self.requestOnce(gpa, url, headers.items, payload) catch |err| {
                if (self.aborted()) return errorResult(gpa, self.model, timestamp, "Request aborted", true);
                // Upstream retries structured provider errors, including its
                // explicit timeout, but not arbitrary errors from custom fetch.
                if (err != error.ProviderRequestTimeout or retries >= self.provider_retry.max_retries) return errorResult(gpa, self.model, timestamp, @errorName(err), false);
                const delay = retry.providerDelayMs(self.io, self.provider_retry, retries, null) catch |delay_error| return errorResult(gpa, self.model, timestamp, @errorName(delay_error), false);
                retries += 1;
                if (!retry.waitProvider(self.io, delay, self.abort_flag)) return errorResult(gpa, self.model, timestamp, "Request aborted", true);
                continue;
            };
            defer gpa.free(response.body);
            if (response.status >= 200 and response.status < 300) {
                return parseResponse(gpa, self.model, context_json, response.body, timestamp) catch |err| errorResult(gpa, self.model, timestamp, @errorName(err), false);
            }
            response.retry_meta.status = response.status;
            if (retries < self.provider_retry.max_retries and retry.isRetryableProviderResponse(response.retry_meta)) {
                const delay = retry.providerDelayMs(self.io, self.provider_retry, retries, response.retry_meta.retry_after_ms) catch |delay_error| return errorResult(gpa, self.model, timestamp, @errorName(delay_error), false);
                retries += 1;
                if (!retry.waitProvider(self.io, delay, self.abort_flag)) return errorResult(gpa, self.model, timestamp, "Request aborted", true);
                continue;
            }
            const message = try std.fmt.allocPrint(gpa, "Classifier provider returned HTTP {d}: {s}", .{ response.status, response.body });
            defer gpa.free(message);
            return errorResult(gpa, self.model, timestamp, message, false);
        }
    }

    fn requestOnce(self: *Client, gpa: std.mem.Allocator, url: []const u8, headers: []const std.http.Header, payload: []const u8) !HttpResult {
        if (self.fetch_override) |fetch| return fetch.call(fetch.context, gpa, url, headers, payload);
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        var http: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http.deinit();
        _ = try http_proxy.configureClient(&http, arena.allocator(), url, .{ .environ = self.environ, .setting = self.proxy_url });
        var body: std.Io.Writer.Allocating = .init(gpa);
        defer body.deinit();
        const result = try http_fetch.fetchControlledObserved(&http, .{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .extra_headers = headers,
            .response_writer = &body.writer,
        }, self.timeout_ms, self.abort_flag, self.response_observer);
        return .{ .status = result.status, .body = try body.toOwnedSlice(), .retry_meta = result.provider };
    }

    fn classifyLocal(self: *Client, gpa: std.mem.Allocator, context_json: []const u8, timestamp: i64) !Result {
        const backing = try gpa.create(std.heap.ArenaAllocator);
        backing.* = .init(gpa);
        errdefer {
            backing.deinit();
            gpa.destroy(backing);
        }
        const allocator = backing.allocator();
        const answers = try llama.run(allocator, .{ .context = self, .call = localPost }, self.model.id, context_json, self.temperature);
        return .{ .backing = backing, .api = self.model.api, .provider = try allocator.dupe(u8, self.model.provider), .model = try allocator.dupe(u8, self.model.id), .answers = answers, .timestamp_ms = timestamp };
    }

    fn localPost(context: ?*anyopaque, gpa: std.mem.Allocator, path: []const u8, value: std.json.Value, observe: bool) anyerror!std.json.Value {
        const self: *Client = @ptrCast(@alignCast(context.?));
        const url = try std.fmt.allocPrint(gpa, "{s}{s}", .{ llama.serverRoot(self.model.base_url), path });
        defer gpa.free(url);
        var payload: std.Io.Writer.Allocating = .init(gpa);
        defer payload.deinit();
        try std.json.Stringify.value(value, .{}, &payload.writer);
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try putHeader(gpa, &headers, "content-type", "application/json");
        const authorization = if (self.api_key.len > 0) try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key}) else null;
        defer if (authorization) |owned| gpa.free(owned);
        if (authorization) |text_value| try putHeader(gpa, &headers, "authorization", text_value);
        for (self.model.headers) |header| try putHeader(gpa, &headers, header.name, header.value);
        for (self.headers) |header| try putHeader(gpa, &headers, header.name, header.value);
        var transport = self.*;
        if (!observe) transport.response_observer = null;
        var retries: u32 = 0;
        while (true) {
            if (self.aborted()) return error.RequestAborted;
            var response = transport.requestOnce(gpa, url, headers.items, payload.written()) catch |err| {
                if (err != error.ProviderRequestTimeout or retries >= self.provider_retry.max_retries) return err;
                const delay = try retry.providerDelayMs(self.io, self.provider_retry, retries, null);
                retries += 1;
                if (!retry.waitProvider(self.io, delay, self.abort_flag)) return error.RequestAborted;
                continue;
            };
            defer gpa.free(response.body);
            if (response.status >= 200 and response.status < 300) return std.json.parseFromSliceLeaky(std.json.Value, gpa, response.body, .{ .allocate = .alloc_always });
            response.retry_meta.status = response.status;
            if (retries >= self.provider_retry.max_retries or !retry.isRetryableProviderResponse(response.retry_meta)) return error.ClassifierHttpFailure;
            const delay = try retry.providerDelayMs(self.io, self.provider_retry, retries, response.retry_meta.retry_after_ms);
            retries += 1;
            if (!retry.waitProvider(self.io, delay, self.abort_flag)) return error.RequestAborted;
        }
    }

    fn aborted(self: *const Client) bool {
        return if (self.abort_flag) |flag| @atomicLoad(bool, flag, .acquire) else false;
    }
};

fn putHeader(gpa: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: ?[]const u8) !void {
    for (headers.items, 0..) |header, index| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            if (value) |text_value| headers.items[index] = .{ .name = name, .value = text_value } else _ = headers.orderedRemove(index);
            return;
        }
    }
    if (value) |text_value| try headers.append(gpa, .{ .name = name, .value = text_value });
}

fn errorResult(gpa: std.mem.Allocator, model: Model, timestamp: i64, message: []const u8, aborted: bool) !Result {
    const backing = try gpa.create(std.heap.ArenaAllocator);
    backing.* = .init(gpa);
    errdefer {
        backing.deinit();
        gpa.destroy(backing);
    }
    const allocator = backing.allocator();
    return .{
        .backing = backing,
        .api = model.api,
        .provider = try allocator.dupe(u8, model.provider),
        .model = try allocator.dupe(u8, model.id),
        .timestamp_ms = timestamp,
        .stop_reason = if (aborted) .aborted else .err,
        .error_message = try allocator.dupe(u8, message),
    };
}

pub const Result = struct {
    backing: *std.heap.ArenaAllocator,
    api: Api,
    provider: []const u8,
    model: []const u8,
    answers: std.json.ObjectMap = .empty,
    usage: ?costs.Usage = null,
    stop_reason: enum { stop, aborted, err } = .stop,
    error_message: ?[]const u8 = null,
    timestamp_ms: i64,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        self.backing.deinit();
        gpa.destroy(self.backing);
        self.* = undefined;
    }
};

fn object(value: std.json.Value) !std.json.ObjectMap {
    if (value != .object) return error.InvalidClassifierObject;
    return value.object;
}

fn required(map: std.json.ObjectMap, key: []const u8) !std.json.Value {
    return map.get(key) orelse error.MissingClassifierField;
}

fn text(value: std.json.Value) ![]const u8 {
    if (value != .string) return error.InvalidClassifierString;
    return value.string;
}

fn number(value: std.json.Value) !f64 {
    const result: f64 = switch (value) {
        .integer => |value_int| @floatFromInt(value_int),
        .float => |value_float| value_float,
        else => return error.InvalidClassifierNumber,
    };
    if (!std.math.isFinite(result)) return error.InvalidClassifierNumber;
    return result;
}

pub fn buildPayload(gpa: std.mem.Allocator, model: Model, context_json: []const u8) ![]u8 {
    if (model.api == .llama_cpp_classify) return error.NotSystemOneApi;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const context = try object(try std.json.parseFromSliceLeaky(std.json.Value, allocator, context_json, .{}));
    const state = try required(context, "state");
    _ = try object(state);
    const questions = try object(try required(context, "questions"));
    var entries = questions.iterator();
    while (entries.next()) |entry| {
        var question = try object(entry.value_ptr.*);
        const kind = try text(try required(question, "type"));
        if (std.mem.eql(u8, kind, "bool")) {
            try question.put(allocator, "type", .{ .string = "noul" });
            entry.value_ptr.* = .{ .object = question };
        } else if (!std.mem.eql(u8, kind, "choice") and !std.mem.eql(u8, kind, "score")) return error.InvalidClassifierQuestion;
    }
    var request: std.json.ObjectMap = .empty;
    try request.put(allocator, "state", state);
    try request.put(allocator, "questions", .{ .object = questions });
    var payload: std.json.ObjectMap = .empty;
    try payload.put(allocator, "model", .{ .string = model.id });
    if (model.api == .cloudflare_workers_ai_system_one) {
        try payload.put(allocator, "input", .{ .object = request });
    } else {
        try payload.put(allocator, "state", state);
        try payload.put(allocator, "questions", .{ .object = questions });
    }
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try std.json.Stringify.value(std.json.Value{ .object = payload }, .{}, &output.writer);
    return output.toOwnedSlice();
}

fn unwrap(api: Api, root: std.json.ObjectMap) !std.json.ObjectMap {
    if (api == .typesafe_system_one) return root;
    if (api != .cloudflare_workers_ai_system_one) return error.NotSystemOneApi;
    if (root.get("success")) |success| if (success == .bool and !success.bool) return error.CloudflareClassifierFailure;
    const result = try object(try required(root, "result"));
    if (result.contains("answers")) return result;
    if (!std.mem.eql(u8, try text(try required(result, "state")), "Completed")) return error.CloudflareClassifierNotCompleted;
    return object(try required(result, "result"));
}

fn tokens(value: ?std.json.Value) u64 {
    const raw = value orelse return 0;
    const count = number(raw) catch return 0;
    if (count <= 0 or count >= @as(f64, @floatFromInt(std.math.maxInt(u64)))) return 0;
    return @intFromFloat(count);
}

fn parseUsage(raw: ?std.json.Value, model: Model) ?costs.Usage {
    const value = raw orelse return null;
    if (value != .object or (!value.object.contains("input_tokens") and !value.object.contains("output_tokens"))) return null;
    var usage: costs.Usage = .{ .input = tokens(value.object.get("input_tokens")), .output = tokens(value.object.get("output_tokens")) };
    usage.normalizeTotal();
    _ = costs.calculate(model.cost, &usage);
    return usage;
}

fn parseAnswers(allocator: std.mem.Allocator, answers: std.json.ObjectMap, questions: std.json.ObjectMap) !std.json.ObjectMap {
    var output: std.json.ObjectMap = .empty;
    var entries = questions.iterator();
    while (entries.next()) |entry| {
        const question = try object(entry.value_ptr.*);
        const kind = try text(try required(question, "type"));
        const answer = try object(try required(answers, entry.key_ptr.*));
        const wire_kind = try text(try required(answer, "type"));
        var projected: std.json.ObjectMap = .empty;
        try projected.put(allocator, "type", .{ .string = kind });
        if (std.mem.eql(u8, kind, "choice")) {
            if (!std.mem.eql(u8, wire_kind, "choice")) return error.InvalidClassifierAnswer;
            const choice = try text(try required(answer, "choice"));
            const probabilities = try object(try required(answer, "probabilities"));
            var probabilities_iterator = probabilities.iterator();
            while (probabilities_iterator.next()) |probability| _ = try number(probability.value_ptr.*);
            const confidence = try number(try required(answer, "confidence"));
            try projected.put(allocator, "choice", .{ .string = choice });
            try projected.put(allocator, "probabilities", .{ .object = probabilities });
            try projected.put(allocator, "confidence", .{ .float = confidence });
        } else if (std.mem.eql(u8, kind, "score")) {
            if (!std.mem.eql(u8, wire_kind, "score")) return error.InvalidClassifierAnswer;
            try projected.put(allocator, "score", .{ .float = try number(try required(answer, "score")) });
            try projected.put(allocator, "confidence", .{ .float = try number(try required(answer, "confidence")) });
        } else if (std.mem.eql(u8, kind, "bool")) {
            if (!std.mem.eql(u8, wire_kind, "noul")) return error.InvalidClassifierAnswer;
            try projected.put(allocator, "probability", .{ .float = try number(try required(answer, "noul")) });
        } else return error.InvalidClassifierQuestion;
        try output.put(allocator, entry.key_ptr.*, .{ .object = projected });
    }
    return output;
}

pub fn parseResponse(gpa: std.mem.Allocator, model: Model, context_json: []const u8, response_json: []const u8, timestamp_ms: i64) !Result {
    const backing = try gpa.create(std.heap.ArenaAllocator);
    backing.* = .init(gpa);
    errdefer {
        backing.deinit();
        gpa.destroy(backing);
    }
    const allocator = backing.allocator();
    var result: Result = .{
        .backing = backing,
        .api = model.api,
        .provider = try allocator.dupe(u8, model.provider),
        .model = try allocator.dupe(u8, model.id),
        .answers = .empty,
        .timestamp_ms = timestamp_ms,
    };
    const context = try object(try std.json.parseFromSliceLeaky(std.json.Value, allocator, context_json, .{ .allocate = .alloc_always }));
    const root = try object(try std.json.parseFromSliceLeaky(std.json.Value, allocator, response_json, .{ .allocate = .alloc_always }));
    const output = unwrap(model.api, root) catch |err| {
        result.stop_reason = .err;
        result.error_message = @errorName(err);
        return result;
    };
    // Parse billable usage first, even if malformed answers subsequently fail.
    result.usage = parseUsage(output.get("usage"), model);
    const answers = projectAnswers(allocator, output, context) catch |err| {
        result.stop_reason = .err;
        result.error_message = @errorName(err);
        return result;
    };
    result.answers = answers;
    return result;
}

fn projectAnswers(allocator: std.mem.Allocator, output: std.json.ObjectMap, context: std.json.ObjectMap) !std.json.ObjectMap {
    return parseAnswers(allocator, try object(try required(output, "answers")), try object(try required(context, "questions")));
}

const fixture_model: Model = .{ .api = .typesafe_system_one, .provider = "typesafe", .id = "jev-latest", .base_url = "https://api.typesafe.ai/v1", .cost = .{ .input = 0.042 } };
const fixture_context = "{\"state\":{\"text\":\"deployment succeeded\"},\"questions\":{\"approved\":{\"type\":\"bool\",\"criteria\":{\"true\":\"Yes\",\"false\":\"No\"}},\"category\":{\"type\":\"choice\"},\"satisfaction\":{\"type\":\"score\"}}}";
const fixture_output = "{\"answers\":{\"approved\":{\"type\":\"noul\",\"noul\":0.95},\"category\":{\"type\":\"choice\",\"choice\":\"success\",\"probabilities\":{\"success\":0.9,\"failure\":0.1},\"confidence\":0.8},\"satisfaction\":{\"type\":\"score\",\"score\":2,\"confidence\":0.7}},\"usage\":{\"input_tokens\":308,\"output_tokens\":23}}";

test "System One payload maps bool questions without mutating caller input" {
    const payload = try buildPayload(std.testing.allocator, fixture_model, fixture_context);
    defer std.testing.allocator.free(payload);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"type\":\"noul\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fixture_context, "\"type\":\"bool\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"model\":\"jev-latest\"") != null);
}

test "System One result parses choice score bool and token pricing" {
    var result = try parseResponse(std.testing.allocator, fixture_model, fixture_context, fixture_output, 42);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(.stop, result.stop_reason);
    try std.testing.expectEqualStrings("success", result.answers.get("category").?.object.get("choice").?.string);
    try std.testing.expectEqual(@as(u64, 331), result.usage.?.total_tokens);
    try std.testing.expectApproxEqAbs(@as(f64, 0.000012936), result.usage.?.cost.total, 0.000000000001);
    const approved = result.answers.get("approved").?.object;
    try std.testing.expectEqualStrings("bool", approved.get("type").?.string);
    try std.testing.expectApproxEqAbs(@as(f64, 0.95), approved.get("probability").?.float, 0.00001);
}

test "Cloudflare classifier accepts direct and Completed envelopes" {
    var model = fixture_model;
    model.api = .cloudflare_workers_ai_system_one;
    const envelopes = [_][]const u8{
        "{\"success\":true,\"result\":" ++ fixture_output ++ "}",
        "{\"success\":true,\"result\":{\"state\":\"Completed\",\"result\":" ++ fixture_output ++ "}}",
    };
    for (envelopes) |envelope| {
        var result = try parseResponse(std.testing.allocator, model, fixture_context, envelope, 42);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(.stop, result.stop_reason);
        try std.testing.expectEqual(@as(usize, 3), result.answers.count());
    }
}

test "classifier malformed answers preserve billable usage and prototype sensitive IDs" {
    const context = "{\"state\":{},\"questions\":{\"__proto__\":{\"type\":\"bool\"}}}";
    var valid = try parseResponse(std.testing.allocator, fixture_model, context, "{\"answers\":{\"__proto__\":{\"type\":\"noul\",\"noul\":0.75}}}", 42);
    defer valid.deinit(std.testing.allocator);
    try std.testing.expectEqual(.stop, valid.stop_reason);
    try std.testing.expect(valid.answers.contains("__proto__"));
    var billed = try parseResponse(std.testing.allocator, fixture_model, context, "{\"answers\":{},\"usage\":{\"input_tokens\":308}}", 42);
    defer billed.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, billed.stop_reason);
    try std.testing.expectEqual(@as(u64, 308), billed.usage.?.input);
    var missing = try parseResponse(std.testing.allocator, fixture_model, context, "{\"usage\":{\"input_tokens\":308}}", 42);
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, missing.stop_reason);
    try std.testing.expectEqual(@as(u64, 308), missing.usage.?.input);
}

test "classifier client uses native fetch headers and rejects absent credentials before requests" {
    const Fixture = struct {
        calls: usize = 0,
        suppress_authorization: bool = false,
        fn fetch(context: ?*anyopaque, gpa: std.mem.Allocator, url: []const u8, headers: []const std.http.Header, payload: []const u8) anyerror!HttpResult {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            try std.testing.expectEqualStrings("https://api.typesafe.ai/v1/systemone", url);
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"type\":\"noul\"") != null);
            var authorizations: usize = 0;
            for (headers) |header| if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
                authorizations += 1;
                try std.testing.expectEqualStrings("Bearer request", header.value);
            };
            try std.testing.expectEqual(@as(usize, if (self.suppress_authorization) 0 else 1), authorizations);
            return .{ .status = 200, .body = try gpa.dupe(u8, fixture_output) };
        }
    };
    var fixture: Fixture = .{};
    var client: Client = .{
        .io = std.testing.io,
        .model = fixture_model,
        .api_key = "secret",
        .headers = &.{.{ .name = "Authorization", .value = "Bearer request" }},
        .fetch_override = .{ .context = &fixture, .call = Fixture.fetch },
    };
    var result = try client.classify(std.testing.allocator, fixture_context);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(.stop, result.stop_reason);
    try std.testing.expectEqualStrings("success", result.answers.get("category").?.object.get("choice").?.string);
    client.headers = &.{.{ .name = "AUTHORIZATION", .value = null }};
    fixture.suppress_authorization = true;
    var suppressed = try client.classify(std.testing.allocator, fixture_context);
    defer suppressed.deinit(std.testing.allocator);
    try std.testing.expectEqual(.stop, suppressed.stop_reason);
    client.api_key = "";
    var missing = try client.classify(std.testing.allocator, fixture_context);
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, missing.stop_reason);
    try std.testing.expectEqual(@as(usize, 2), fixture.calls);
}

test "classifier provider retry honors status overrides and arbitrary fetch failures" {
    const Fixture = struct {
        calls: usize = 0,
        arbitrary_failure: bool = false,
        no_retry_header: bool = false,
        fn fetch(context: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, _: []const std.http.Header, _: []const u8) anyerror!HttpResult {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            if (self.arbitrary_failure) return error.CustomFetchFailure;
            if (self.calls == 1) return .{
                .status = 429,
                .body = try gpa.dupe(u8, "rate limited"),
                .retry_meta = .{ .retry_after_ms = 0, .should_retry = !self.no_retry_header },
            };
            return .{ .status = 200, .body = try gpa.dupe(u8, fixture_output) };
        }
    };
    var fixture: Fixture = .{};
    var client: Client = .{ .io = std.testing.io, .model = fixture_model, .api_key = "fixture", .fetch_override = .{ .context = &fixture, .call = Fixture.fetch } };
    var retried = try client.classify(std.testing.allocator, fixture_context);
    defer retried.deinit(std.testing.allocator);
    try std.testing.expectEqual(.stop, retried.stop_reason);
    try std.testing.expectEqual(@as(usize, 2), fixture.calls);
    fixture = .{ .no_retry_header = true };
    var refused = try client.classify(std.testing.allocator, fixture_context);
    defer refused.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, refused.stop_reason);
    try std.testing.expectEqual(@as(usize, 1), fixture.calls);
    fixture = .{ .arbitrary_failure = true };
    var failed = try client.classify(std.testing.allocator, fixture_context);
    defer failed.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, failed.stop_reason);
    try std.testing.expectEqual(@as(usize, 1), fixture.calls);
}

test "generated typed classifier models route separately from chat models" {
    var count: usize = 0;
    for (providers.all_models) |info| {
        if (info.kind != .classifier) continue;
        count += 1;
        const model = try Model.fromInfo(info);
        try std.testing.expectEqualStrings(info.apiName(), model.api.name());
        try std.testing.expectEqualStrings(info.providerName(), model.provider);
    }
    const source = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("catalog_source.json"), .{});
    defer source.deinit();
    var source_count: usize = 0;
    for (source.value.object.get("models").?.array.items) |model| {
        if (std.mem.eql(u8, model.object.get("type").?.string, "classifier")) source_count += 1;
    }
    try std.testing.expectEqual(source_count, count);
    try std.testing.expectError(error.NotClassifierModel, Model.fromInfo(providers.known_models[0]));
}

test "llama classifier routes local endpoints without credentials and escalates missing labels" {
    const Fixture = struct {
        calls: usize = 0,
        completions: usize = 0,
        missing_all: bool = false,
        duplicate_labels: bool = false,
        fn fetch(context: ?*anyopaque, gpa: std.mem.Allocator, url: []const u8, headers: []const std.http.Header, payload: []const u8) anyerror!HttpResult {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            for (headers) |header| try std.testing.expect(!std.ascii.eqlIgnoreCase(header.name, "authorization"));
            const parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{});
            defer parsed.deinit();
            const fields = parsed.value.object;
            try std.testing.expectEqualStrings("local-model", fields.get("model").?.string);
            if (std.mem.endsWith(u8, url, "/tokenize")) {
                try std.testing.expectEqualStrings("http://fixture/tokenize", url);
                try std.testing.expect(!fields.get("add_special").?.bool and !fields.get("parse_special").?.bool);
                const content = fields.get("content").?.string;
                const body = if (std.mem.eql(u8, content, "\n")) "{\"tokens\":[1]}" else if (std.mem.eql(u8, content, "\nYes") or self.duplicate_labels) "{\"tokens\":[{\"id\":1},{\"id\":7}]}" else "{\"tokens\":[1,8]}";
                return .{ .status = 200, .body = try gpa.dupe(u8, body) };
            }
            if (std.mem.endsWith(u8, url, "/apply-template")) {
                try std.testing.expect(!fields.get("chat_template_kwargs").?.object.get("enable_thinking").?.bool);
                try std.testing.expect(std.mem.indexOf(u8, fields.get("messages").?.array.items[1].object.get("content").?.string, "Answer Yes or No.") != null);
                return .{ .status = 200, .body = try gpa.dupe(u8, "{\"prompt\":\"model-template<think>\"}") };
            }
            try std.testing.expectEqualStrings("http://fixture/completion", url);
            self.completions += 1;
            try std.testing.expectEqualStrings("model-template<think></think>", fields.get("prompt").?.string);
            try std.testing.expectEqual(@as(i64, 1), fields.get("n_predict").?.integer);
            try std.testing.expect(fields.get("cache_prompt").?.bool and !fields.get("post_sampling_probs").?.bool);
            const depth = fields.get("n_probs").?.integer;
            try std.testing.expectEqual(([_]i64{ 256, 4096, 32768 })[self.completions - 1], depth);
            const body = if (self.missing_all) "{\"completion_probabilities\":[{\"top_logprobs\":[]}]}" else if (depth == 256) "{\"completion_probabilities\":[{\"top_logprobs\":[{\"id\":7,\"logprob\":-0.2}]}]}" else "{\"completion_probabilities\":[{\"top_logprobs\":[{\"id\":7,\"logprob\":-0.2},{\"id\":8,\"logprob\":-2.0}]}]}";
            return .{ .status = 200, .body = try gpa.dupe(u8, body) };
        }
    };
    const context_json = "{\"state\":{\"value\":42},\"questions\":{\"decision\":{\"type\":\"bool\",\"instructions\":\"Accept?\",\"criteria\":{\"true\":\"accepted\",\"false\":\"rejected\"}}}}";
    var fixture: Fixture = .{};
    var client: Client = .{ .io = std.testing.io, .model = .{ .api = .llama_cpp_classify, .provider = "llama-cpp", .id = "local-model", .base_url = "http://fixture/v1/" }, .api_key = "", .fetch_override = .{ .context = &fixture, .call = Fixture.fetch } };
    var result = try client.classify(std.testing.allocator, context_json);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(.stop, result.stop_reason);
    try std.testing.expect(result.usage == null);
    try std.testing.expectEqual(@as(usize, 2), fixture.completions);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8581489351), result.answers.get("decision").?.object.get("probability").?.float, 1e-9);
    fixture = .{ .missing_all = true };
    var missing = try client.classify(std.testing.allocator, context_json);
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, missing.stop_reason);
    try std.testing.expectEqual(@as(usize, 0), missing.answers.count());
    try std.testing.expectEqual(@as(usize, 3), fixture.completions);
    fixture = .{ .duplicate_labels = true };
    var duplicate = try client.classify(std.testing.allocator, context_json);
    defer duplicate.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, duplicate.stop_reason);
    try std.testing.expectEqual(@as(usize, 0), fixture.completions);
    fixture = .{};
    client.temperature = 0;
    var invalid = try client.classify(std.testing.allocator, context_json);
    defer invalid.deinit(std.testing.allocator);
    try std.testing.expectEqual(.err, invalid.stop_reason);
    try std.testing.expectEqual(@as(usize, 0), fixture.calls);
}

test "llama classifier native HTTP exchanges all endpoint records and observes only completions" {
    const fixture = @import("http_fixture.zig");
    const gpa = std.testing.allocator;
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/tokenize", .body = "{\"tokens\":[1]}" },
        .{ .path = "/tokenize", .body = "{\"tokens\":[1,7]}" },
        .{ .path = "/tokenize", .body = "{\"tokens\":[1]}" },
        .{ .path = "/tokenize", .body = "{\"tokens\":[1,8]}" },
        .{ .path = "/apply-template", .body = "{\"prompt\":\"actual-template<think>\"}", .payload_contains = "\"enable_thinking\":false" },
        .{ .path = "/completion", .body = "{\"completion_probabilities\":[{\"top_logprobs\":[{\"id\":7,\"logprob\":-0.2}]}]}", .payload_contains = "\"n_probs\":256" },
        .{ .path = "/completion", .body = "{\"completion_probabilities\":[{\"top_logprobs\":[{\"id\":7,\"logprob\":-0.2},{\"id\":8,\"logprob\":-2.0}]}]}", .payload_contains = "\"n_probs\":4096" },
    });
    defer server.deinit();
    const base_url = try server.url(gpa, "/v1/");
    defer gpa.free(base_url);
    const Observer = struct {
        count: usize = 0,
        fn observe(context: ?*anyopaque, head: std.http.Client.Response.Head) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            try std.testing.expectEqual(std.http.Status.ok, head.status);
            self.count += 1;
        }
    };
    var observer: Observer = .{};
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    var client: Client = .{ .io = std.testing.io, .model = .{ .api = .llama_cpp_classify, .provider = "llama.cpp", .id = "local", .base_url = base_url }, .api_key = "", .environ = &environment, .timeout_ms = 3000, .response_observer = .{ .context = &observer, .callback = Observer.observe } };
    var result = try client.classify(gpa, "{\"state\":{\"value\":42},\"questions\":{\"answer\":{\"type\":\"bool\",\"instructions\":\"Accept?\",\"criteria\":{\"true\":\"yes\",\"false\":\"no\"}}}}");
    defer result.deinit(gpa);
    if (result.stop_reason != .stop) std.debug.print("Native llama HTTP fixture: {s}\n", .{result.error_message orelse "unknown"});
    try std.testing.expectEqual(.stop, result.stop_reason);
    try server.finish();
    try std.testing.expectEqual(@as(usize, 7), server.captured.items.len);
    try std.testing.expectEqual(@as(usize, 2), observer.count);
    try std.testing.expect(result.usage == null);
}

test "classifier native HTTP retry headers and local timeout preserve empty error answers" {
    const fixture = @import("http_fixture.zig");
    const gpa = std.testing.allocator;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    const retried_server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/systemone", .body = "temporarily unavailable", .status = .service_unavailable, .headers = &.{.{ .name = "retry-after", .value = "0" }} },
        .{ .path = "/systemone", .body = fixture_output },
    });
    defer retried_server.deinit();
    const retry_url = try retried_server.url(gpa, "");
    defer gpa.free(retry_url);
    var retry_model = fixture_model;
    retry_model.base_url = retry_url;
    var client: Client = .{ .io = std.testing.io, .model = retry_model, .api_key = "offline-fixture", .environ = &environment, .timeout_ms = 3000 };
    var retried = try client.classify(gpa, fixture_context);
    defer retried.deinit(gpa);
    try std.testing.expectEqual(.stop, retried.stop_reason);
    try retried_server.finish();
    try std.testing.expectEqual(@as(usize, 2), retried_server.captured.items.len);
    const refused_server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/systemone", .body = "do not retry", .status = .service_unavailable, .headers = &.{.{ .name = "x-should-retry", .value = "false" }} },
    });
    defer refused_server.deinit();
    const refused_url = try refused_server.url(gpa, "");
    defer gpa.free(refused_url);
    client.model.base_url = refused_url;
    var refused = try client.classify(gpa, fixture_context);
    defer refused.deinit(gpa);
    try std.testing.expectEqual(.err, refused.stop_reason);
    try refused_server.finish();
    try std.testing.expectEqual(@as(usize, 1), refused_server.captured.items.len);
    const stalled_server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/tokenize", .body = "{\"tokens\":[1]}", .delay_ms = 1000 },
    });
    defer stalled_server.deinit();
    const local_url = try stalled_server.url(gpa, "/v1");
    defer gpa.free(local_url);
    client.model.api = .llama_cpp_classify;
    client.model.base_url = local_url;
    client.api_key = "";
    client.timeout_ms = 25;
    client.provider_retry.max_retries = 0;
    var timed_out = try client.classify(gpa, "{\"state\":{},\"questions\":{\"decision\":{\"type\":\"bool\",\"instructions\":\"Accept?\",\"criteria\":{\"true\":\"yes\",\"false\":\"no\"}}}}");
    defer timed_out.deinit(gpa);
    try std.testing.expectEqual(.err, timed_out.stop_reason);
    try std.testing.expectEqualStrings("ProviderRequestTimeout", timed_out.error_message.?);
    try std.testing.expectEqual(@as(usize, 0), timed_out.answers.count());
    try std.testing.expect(timed_out.usage == null);
}

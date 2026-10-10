//! Actual Main typed transports use immutable, explicitly owned configuration.
//! A program cannot choose a different Registry/SDK runtime through JSON.
const std = @import("std");
const json = @import("../mcp/protocol.zig").json;
const Value = json.Value;
const registry = @import("typed_model_registry.zig");
const models = @import("../mcp/codemode_models.zig");
const classifier = @import("../ai/classifier.zig");
const images = @import("../ai/openrouter_images.zig");
const auth = @import("typed_model_auth.zig");
const metadata = @import("../ai/request_metadata.zig");
pub const State = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    references: std.atomic.Value(usize) = .init(1),
    environ: std.process.Environ.Map,
    provider_configs: Value,
    agent_dir: ?[]const u8,
    explicit_provider: ?[]const u8,
    explicit_key: ?[]const u8,
    proxy_url: ?[]const u8,
    classifier_fetch: ?classifier.FetchOverride = null,
    actions_context: ?*anyopaque = null,
    actions: ?*const fn (?*anyopaque, std.mem.Allocator, *const registry.Snapshot, []const u8, []const u8) anyerror!void = null,
    pub fn create(gpa: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, file: *const @import("models_file.zig").ModelsFile, agent_dir: ?[]const u8, explicit_provider: ?[]const u8, explicit_key: ?[]const u8, proxy_url: ?[]const u8) !*State {
        const self = try gpa.create(State);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .arena = .init(gpa), .io = io, .environ = .init(gpa), .provider_configs = .null, .agent_dir = null, .explicit_provider = null, .explicit_key = null, .proxy_url = null };
        errdefer {
            self.environ.deinit();
            self.arena.deinit();
        }
        const a = self.arena.allocator();
        var fields = environ.iterator();
        while (fields.next()) |field| try self.environ.put(field.key_ptr.*, field.value_ptr.*);
        if (file.parsed) |parsed| self.provider_configs = try json.clone(a, parsed.value.object.get("providers") orelse .null);
        self.agent_dir = if (agent_dir) |value| try a.dupe(u8, value) else null;
        self.explicit_provider = if (explicit_provider) |value| try a.dupe(u8, value) else null;
        self.explicit_key = if (explicit_key) |value| try a.dupe(u8, value) else null;
        self.proxy_url = if (proxy_url) |value| try a.dupe(u8, value) else null;
        return self;
    }
    pub fn backend(self: *State) registry.Backend {
        return .{ .context = self, .operate = operate, .available = available, .retain = retain, .release = release };
    }
    fn retain(raw: ?*anyopaque) void {
        const self: *State = @ptrCast(@alignCast(raw.?));
        _ = self.references.fetchAdd(1, .monotonic);
    }
    pub fn release(raw: ?*anyopaque) void {
        const self: *State = @ptrCast(@alignCast(raw.?));
        if (self.references.fetchSub(1, .acq_rel) != 1) return;
        self.environ.deinit();
        self.arena.deinit();
        self.gpa.destroy(self);
    }
    fn providerConfig(self: *State, name: []const u8) Value {
        return if (self.provider_configs == .object) self.provider_configs.object.get(name) orelse .null else .null;
    }
    fn credentials(self: *State, gpa: std.mem.Allocator, name: []const u8) !?json.Owned {
        const directory = self.agent_dir orelse return null;
        var storage = try @import("../auth/root.zig").AuthStorage.init(gpa, self.io, directory);
        defer storage.deinit();
        const bytes = (try storage.readCredentialJson(name)) orelse return null;
        defer gpa.free(bytes);
        var result = try json.Owned.parse(gpa, bytes);
        errdefer result.deinit();
        // AuthStorage.read resolves stored key templates using credential.env.
        if (result.value == .object) if (result.value.object.get("type")) |typ| if (typ == .string and std.mem.eql(u8, typ.string, "api_key")) {
            if (result.value.object.get("key")) |key| if (key == .string) {
                var env: std.process.Environ.Map = .init(gpa);
                defer env.deinit();
                var fields = self.environ.iterator();
                while (fields.next()) |field| try env.put(field.key_ptr.*, field.value_ptr.*);
                if (result.value.object.get("env")) |overlay| if (overlay == .object) {
                    var entries = overlay.object.iterator();
                    while (entries.next()) |entry| if (entry.value_ptr.* == .string) try env.put(entry.key_ptr.*, entry.value_ptr.string);
                };
                var resolver = @import("config_value.zig").Resolver.init(result.arena.allocator(), self.io, &env);
                defer resolver.deinit();
                const resolved = try resolver.resolve(key.string);
                try result.value.object.put(result.arena.allocator(), "key", if (resolved) |value| .{ .string = value } else .null);
            };
        };
        return result;
    }
    fn prepare(self: *State, gpa: std.mem.Allocator, row: *const registry.Snapshot, aborted: ?*bool) !json.Owned {
        var stored = try self.credentials(gpa, row.info.providerName());
        defer if (stored) |*value| value.deinit();
        const explicit = if (self.explicit_provider != null and std.mem.eql(u8, self.explicit_provider.?, row.info.providerName())) self.explicit_key else null;
        if (row.auth_resolve) |callback| {
            var credential = try json.Owned.empty(gpa);
            defer credential.deinit();
            const a = credential.arena.allocator();
            credential.value = if (stored) |value| try json.clone(a, value.value) else .null;
            if (explicit) |key| {
                credential.value = .{ .object = .empty };
                try credential.value.object.put(a, "type", .{ .string = "api_key" });
                try credential.value.object.put(a, "key", .{ .string = try a.dupe(u8, key) });
            }
            const bytes = try json.stringify(gpa, credential.value);
            defer gpa.free(bytes);
            const envelope = try callback.runtime.invokeProviderAuthOperation(callback.callback_id, callback.provider, callback.generation, .resolve, bytes, "{}", aborted);
            defer gpa.free(envelope);
            if (self.actions) |accept| try accept(self.actions_context, gpa, row, callback.runtime.source_path, envelope);
            var response = try json.Owned.parse(gpa, envelope);
            defer response.deinit();
            return auth.decorate(gpa, self.io, &self.environ, row.info, self.providerConfig(row.info.providerName()), if (row.native_mode) .null else row.configuration, if (credential.value == .null) null else credential.value, json.get(response.value, "value") orelse .null);
        }
        return auth.resolve(gpa, self.io, &self.environ, row.info, self.providerConfig(row.info.providerName()), row.configuration, if (stored) |value| value.value else null, explicit);
    }
    fn available(raw: ?*anyopaque, gpa: std.mem.Allocator, rows: []const registry.Snapshot, aborted: ?*bool) !json.Owned {
        const self: *State = @ptrCast(@alignCast(raw.?));
        var result = try json.Owned.empty(gpa);
        errdefer result.deinit();
        const a = result.arena.allocator();
        result.value = .{ .array = .init(a) };
        var checks: std.StringHashMapUnmanaged(bool) = .empty;
        defer checks.deinit(gpa);
        for (rows) |row| {
            if (abortRequested(aborted)) return error.Canceled;
            const configured = if (checks.get(row.info.providerName())) |value| value else blk: {
                if (row.auth_check) |callback| {
                    var credential = try self.credentials(gpa, row.info.providerName());
                    defer if (credential) |*value| value.deinit();
                    const bytes = if (credential) |value| try json.stringify(gpa, value.value) else try gpa.dupe(u8, "null");
                    defer gpa.free(bytes);
                    const envelope = try callback.runtime.invokeProviderAuthOperation(callback.callback_id, callback.provider, callback.generation, .check, bytes, "{}", aborted);
                    defer gpa.free(envelope);
                    if (self.actions) |accept| try accept(self.actions_context, gpa, &row, callback.runtime.source_path, envelope);
                    var response = try json.Owned.parse(gpa, envelope);
                    defer response.deinit();
                    const configured = auth.truthy(json.get(response.value, "value") orelse .null);
                    try checks.put(gpa, row.info.providerName(), configured);
                    break :blk configured;
                }
                var credential = try self.credentials(gpa, row.info.providerName());
                defer if (credential) |*value| value.deinit();
                const explicit = if (self.explicit_provider != null and std.mem.eql(u8, self.explicit_provider.?, row.info.providerName())) self.explicit_key else null;
                const value = if (row.auth_resolve) |callback| resolve: {
                    const bytes = if (credential) |stored| try json.stringify(gpa, stored.value) else try gpa.dupe(u8, "null");
                    defer gpa.free(bytes);
                    const envelope = try callback.runtime.invokeProviderAuthOperation(callback.callback_id, callback.provider, callback.generation, .resolve, bytes, "{}", aborted);
                    defer gpa.free(envelope);
                    if (self.actions) |accept| try accept(self.actions_context, gpa, &row, callback.runtime.source_path, envelope);
                    var response = try json.Owned.parse(gpa, envelope);
                    defer response.deinit();
                    break :resolve auth.truthy(json.get(response.value, "value") orelse .null);
                } else try auth.checkConfigured(gpa, self.io, &self.environ, row.info, self.providerConfig(row.info.providerName()), if (row.native_mode) .null else row.configuration, if (credential) |stored| stored.value else null, explicit);
                try checks.put(gpa, row.info.providerName(), value);
                break :blk value;
            };
            if (configured) try result.value.array.append(try json.clone(a, row.value));
        }
        return result;
    }
    fn operate(raw: ?*anyopaque, gpa: std.mem.Allocator, row: *const registry.Snapshot, operation: models.Operation, context: Value, aborted: ?*bool) !json.Owned {
        const self: *State = @ptrCast(@alignCast(raw.?));
        if (abortRequested(aborted)) return failure(gpa, self.io, row, operation, "Operation aborted", true);
        if (operation == .classify and !row.info.input_image) if (json.get(context, "images")) |blocks| if (blocks == .array and blocks.array.items.len > 0) {
            const message = try std.fmt.allocPrint(gpa, "Model {s}/{s} does not accept image input", .{ row.info.providerName(), row.info.id });
            defer gpa.free(message);
            return failure(gpa, self.io, row, operation, message, false);
        };
        var prepared = self.prepare(gpa, row, aborted) catch |err| {
            if (err == error.OutOfMemory) return err;
            const message = try std.fmt.allocPrint(gpa, "API key auth failed for provider {s}", .{row.info.providerName()});
            defer gpa.free(message);
            return failure(gpa, self.io, row, operation, message, abortRequested(aborted));
        };
        defer prepared.deinit();
        if (prepared.value == .null) {
            const message = try std.fmt.allocPrint(gpa, "Provider is not configured: {s}", .{row.info.providerName()});
            defer gpa.free(message);
            return failure(gpa, self.io, row, operation, message, false);
        }
        const authentication = try json.required(prepared.value, "auth");
        const auth_base_url = json.get(authentication, "baseUrl");
        const rewrites_model = if (auth_base_url) |value| auth.truthy(value) else false;
        const key = if (json.get(authentication, "apiKey")) |value| if (value == .string) value.string else "" else "";
        var request_options = try json.Owned.empty(gpa);
        defer request_options.deinit();
        const options_allocator = request_options.arena.allocator();
        request_options.value = .{ .object = .empty };
        for ([_][]const u8{ "apiKey", "headers" }) |field| if (json.get(authentication, field)) |value| try request_options.value.object.put(options_allocator, field, try json.clone(options_allocator, value));
        if (json.get(prepared.value, "env")) |value| try request_options.value.object.put(options_allocator, "env", try json.clone(options_allocator, value));
        const options = try json.stringify(gpa, request_options.value);
        defer gpa.free(options);
        const body = try json.stringify(gpa, context);
        defer gpa.free(body);
        if (row.callback) |callback| {
            const request_model = if (rewrites_model) rewritten: {
                var value = try json.clone(options_allocator, row.value);
                try value.object.put(options_allocator, "baseUrl", try json.clone(options_allocator, auth_base_url.?));
                break :rewritten value;
            } else row.value;
            const model = try json.stringify(gpa, request_model);
            defer gpa.free(model);
            const envelope = try callback.runtime.invokeProviderTypedOperation(callback.callback_id, callback.provider, callback.generation, if (operation == .classify) .classify else .generate_images, model, body, options, rewrites_model, aborted);
            defer gpa.free(envelope);
            if (self.actions) |accept| try accept(self.actions_context, gpa, row, callback.runtime.source_path, envelope);
            var response = try json.Owned.parse(gpa, envelope);
            defer response.deinit();
            var result = try json.Owned.empty(gpa);
            errdefer result.deinit();
            result.value = try json.clone(result.arena.allocator(), json.get(response.value, "value") orelse .null);
            return result;
        }
        if (row.native_mode) return failure(gpa, self.io, row, operation, if (operation == .classify) try std.fmt.allocPrint(request_options.arena.allocator(), "Provider {s} does not support classification", .{row.info.providerName()}) else try std.fmt.allocPrint(request_options.arena.allocator(), "Provider {s} does not support image generation", .{row.info.providerName()}), false);
        var request_info = row.info;
        if (rewrites_model) request_info.base_url = try json.asString(auth_base_url.?);
        var headers: std.ArrayList(metadata.Header) = .empty;
        defer headers.deinit(gpa);
        if (json.get(authentication, "headers")) |value| if (value == .object) {
            var entries = value.object.iterator();
            while (entries.next()) |entry| if (entry.value_ptr.* == .string) try headers.append(gpa, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
        };
        if (operation == .classify) {
            var converted: std.ArrayList(classifier.Header) = .empty;
            defer converted.deinit(gpa);
            for (headers.items) |header| try converted.append(gpa, .{ .name = header.name, .value = header.value });
            var client: classifier.Client = .{ .io = self.io, .model = try classifier.Model.fromInfo(request_info), .api_key = key, .environ = &self.environ, .proxy_url = self.proxy_url, .headers = converted.items, .abort_flag = aborted, .fetch_override = self.classifier_fetch };
            var response = try client.classify(gpa, body);
            defer response.deinit(gpa);
            return classifierValue(gpa, response);
        }
        var input: std.ArrayList(images.Input) = .empty;
        defer input.deinit(gpa);
        for ((try json.required(context, "input")).array.items) |block| {
            const kind = try json.asString(try json.required(block, "type"));
            if (std.mem.eql(u8, kind, "text")) try input.append(gpa, .{ .text = try json.asString(try json.required(block, "text")) }) else try input.append(gpa, .{ .image = .{ .mime_type = try json.asString(try json.required(block, "mimeType")), .data = try json.asString(try json.required(block, "data")) } });
        }
        var client = try images.Client.fromModel(self.io, request_info, key);
        client.gpa = gpa;
        client.environ = &self.environ;
        client.proxy_url = self.proxy_url;
        client.custom_headers = headers.items;
        client.abort_flag = aborted;
        if (json.get(row.value, "output")) |output| if (output == .array) for (output.array.items) |kind| {
            if (kind == .string and std.mem.eql(u8, kind.string, "text")) client.output_text = true;
        };
        var response = try client.generate(gpa, input.items);
        defer response.deinit(gpa);
        return imageValue(gpa, self.io, response);
    }
};
fn abortRequested(flag: ?*bool) bool {
    return if (flag) |value| @atomicLoad(bool, value, .acquire) else false;
}
fn put(a: std.mem.Allocator, row: *Value, name: []const u8, value: Value) !void {
    try row.object.put(a, name, try json.clone(a, value));
}
fn usage(a: std.mem.Allocator, value: @import("../ai/cost.zig").Usage) !Value {
    var result: Value = .{ .object = .empty };
    inline for (.{ .{ "input", value.input }, .{ "output", value.output }, .{ "cacheRead", value.cache_read }, .{ "cacheWrite", value.cache_write }, .{ "totalTokens", value.total() } }) |field| try result.object.put(a, field[0], .{ .integer = @intCast(field[1]) });
    if (value.cache_write_1h) |count| try result.object.put(a, "cacheWrite1h", .{ .integer = @intCast(count) });
    if (value.reasoning) |count| try result.object.put(a, "reasoning", .{ .integer = @intCast(count) });
    var cost: Value = .{ .object = .empty };
    inline for (.{ .{ "input", value.cost.input }, .{ "output", value.cost.output }, .{ "cacheRead", value.cost.cache_read }, .{ "cacheWrite", value.cost.cache_write }, .{ "total", value.cost.total } }) |field| try cost.object.put(a, field[0], .{ .float = field[1] });
    try result.object.put(a, "cost", cost);
    return result;
}
fn classifierValue(gpa: std.mem.Allocator, response: classifier.Result) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    try put(a, &result.value, "api", .{ .string = response.api.name() });
    try put(a, &result.value, "provider", .{ .string = response.provider });
    try put(a, &result.value, "model", .{ .string = response.model });
    try put(a, &result.value, "answers", .{ .object = response.answers });
    try put(a, &result.value, "stopReason", .{ .string = if (response.stop_reason == .err) "error" else @tagName(response.stop_reason) });
    try put(a, &result.value, "timestamp", .{ .integer = response.timestamp_ms });
    if (response.error_message) |message| try put(a, &result.value, "errorMessage", .{ .string = message });
    if (response.usage) |accounting| try result.value.object.put(a, "usage", try usage(a, accounting));
    return result;
}
fn imageValue(gpa: std.mem.Allocator, io: std.Io, response: images.Response) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    try put(a, &result.value, "api", .{ .string = response.api });
    try put(a, &result.value, "provider", .{ .string = response.provider });
    try put(a, &result.value, "model", .{ .string = response.model });
    try put(a, &result.value, "stopReason", .{ .string = response.stop_reason });
    try put(a, &result.value, "timestamp", .{ .integer = std.Io.Clock.real.now(io).toMilliseconds() });
    var output: Value = .{ .array = .init(a) };
    for (response.output) |block| {
        var value: Value = .{ .object = .empty };
        switch (block) {
            .text => |text| {
                try put(a, &value, "type", .{ .string = "text" });
                try put(a, &value, "text", .{ .string = text });
            },
            .image => |image| {
                try put(a, &value, "type", .{ .string = "image" });
                try put(a, &value, "mimeType", .{ .string = image.mime_type });
                try put(a, &value, "data", .{ .string = image.data });
            },
        }
        try output.array.append(value);
    }
    try result.value.object.put(a, "output", output);
    if (response.response_id.len > 0) try put(a, &result.value, "responseId", .{ .string = response.response_id });
    if (response.error_message.len > 0) try put(a, &result.value, "errorMessage", .{ .string = response.error_message });
    if (!std.mem.eql(u8, response.stop_reason, "error") and !std.mem.eql(u8, response.stop_reason, "aborted")) try result.value.object.put(a, "usage", try usage(a, response.usage));
    return result;
}
fn failure(gpa: std.mem.Allocator, io: std.Io, row: *const registry.Snapshot, operation: models.Operation, message: []const u8, aborted: bool) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    try put(a, &result.value, "api", .{ .string = row.info.apiName() });
    try put(a, &result.value, "provider", .{ .string = row.info.providerName() });
    try put(a, &result.value, "model", .{ .string = row.info.id });
    try put(a, &result.value, if (operation == .classify) "answers" else "output", if (operation == .classify) .{ .object = .empty } else .{ .array = .init(a) });
    try put(a, &result.value, "stopReason", .{ .string = if (aborted) "aborted" else "error" });
    try put(a, &result.value, "errorMessage", .{ .string = message });
    try put(a, &result.value, "timestamp", .{ .integer = std.Io.Clock.real.now(io).toMilliseconds() });
    return result;
}

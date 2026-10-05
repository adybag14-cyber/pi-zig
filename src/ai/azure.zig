//! Azure endpoint and deployment resolution shared by both native protocols.
const std = @import("std");
pub const Options = struct {
    base_url: ?[]const u8 = null,
    resource_name: ?[]const u8 = null,
    api_version: ?[]const u8 = null,
    deployment_name: ?[]const u8 = null,
    /// Request-scoped values take precedence over the client's process map.
    env: ?*const std.process.Environ.Map = null,

    pub fn merge(base: Options, request: Options) Options {
        var result = base;
        inline for (std.meta.fields(Options)) |field| {
            if (@field(request, field.name)) |value| @field(result, field.name) = value;
        }
        return result;
    }
};
pub const Config = struct {
    base_url: []u8,
    api_version: []u8,
    pub fn deinit(self: Config, gpa: std.mem.Allocator) void {
        gpa.free(self.base_url);
        gpa.free(self.api_version);
    }
};

pub fn isProvider(provider: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider, "azure") or std.ascii.eqlIgnoreCase(provider, "azure-openai-responses") or std.ascii.eqlIgnoreCase(provider, "azure_openai_responses");
}

fn nonempty(value: ?[]const u8) ?[]const u8 {
    return if (value) |text| if (text.len > 0) text else null else null;
}
fn envValue(environ: ?*const std.process.Environ.Map, scoped: ?*const std.process.Environ.Map, name: []const u8) ?[]const u8 {
    if (scoped) |map| if (nonempty(map.get(name))) |value| return value;
    return if (environ) |map| nonempty(map.get(name)) else null;
}
fn trimmed(value: ?[]const u8) ?[]const u8 {
    const text = value orelse return null;
    return nonempty(std.mem.trim(u8, text, " \t\r\n"));
}

pub fn normalizeBaseUrl(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const value = std.mem.trimEnd(u8, std.mem.trim(u8, input, " \t\r\n"), "/");
    var uri = std.Uri.parse(value) catch return error.InvalidAzureBaseUrl;
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "https") and !std.ascii.eqlIgnoreCase(uri.scheme, "http")) return error.InvalidAzureBaseUrl;
    const host = uri.host orelse return error.InvalidAzureBaseUrl;
    const raw_host = switch (host) {
        .raw, .percent_encoded => |bytes| bytes,
    };
    if (raw_host.len == 0 or std.mem.indexOfAny(u8, raw_host, " \t\r\n\x00") != null) return error.InvalidAzureBaseUrl;
    const lower_host = try std.ascii.allocLowerString(gpa, raw_host);
    defer gpa.free(lower_host);
    uri.host = .{ .percent_encoded = lower_host };
    uri.scheme = if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) "https" else "http";
    if (uri.port == (if (std.mem.eql(u8, uri.scheme, "https")) @as(u16, 443) else @as(u16, 80))) uri.port = null;
    const path = std.mem.trimEnd(u8, switch (uri.path) {
        .raw, .percent_encoded => |bytes| bytes,
    }, "/");
    const azure_host = std.mem.endsWith(u8, lower_host, ".openai.azure.com") or std.mem.endsWith(u8, lower_host, ".cognitiveservices.azure.com") or std.mem.endsWith(u8, lower_host, ".ai.azure.com");
    if (azure_host and (path.len == 0 or std.mem.eql(u8, path, "/openai") or std.mem.eql(u8, path, "/openai/v1/responses"))) {
        uri.path = .{ .raw = "/openai/v1" };
        uri.query = null;
    }
    const encoded = try std.fmt.allocPrint(gpa, "{f}", .{uri});
    errdefer gpa.free(encoded);
    return gpa.realloc(encoded, std.mem.trimEnd(u8, encoded, "/").len);
}

pub fn resolveConfig(gpa: std.mem.Allocator, model_base_url: []const u8, environ: ?*const std.process.Environ.Map, options: Options) !Config {
    const explicit = trimmed(options.base_url) orelse trimmed(envValue(environ, options.env, "AZURE_OPENAI_BASE_URL"));
    var resource_url: ?[]u8 = null;
    defer if (resource_url) |url| gpa.free(url);
    const source = if (explicit) |url| url else resource: {
        if (nonempty(options.resource_name) orelse envValue(environ, options.env, "AZURE_OPENAI_RESOURCE_NAME")) |name| {
            resource_url = try std.fmt.allocPrint(gpa, "https://{s}.openai.azure.com/openai/v1", .{name});
            break :resource resource_url.?;
        }
        break :resource nonempty(model_base_url) orelse return error.MissingAzureBaseUrl;
    };
    const base_url = try normalizeBaseUrl(gpa, source);
    errdefer gpa.free(base_url);
    const version = nonempty(options.api_version) orelse envValue(environ, options.env, "AZURE_OPENAI_API_VERSION") orelse "v1";
    return .{ .base_url = base_url, .api_version = try gpa.dupe(u8, version) };
}

pub fn resolveDeploymentName(gpa: std.mem.Allocator, model: []const u8, environ: ?*const std.process.Environ.Map, options: Options) ![]u8 {
    if (nonempty(options.deployment_name)) |name| return gpa.dupe(u8, name);
    var deployment = model;
    if (envValue(environ, options.env, "AZURE_OPENAI_DEPLOYMENT_NAME_MAP")) |mapping| {
        var entries = std.mem.splitScalar(u8, mapping, ',');
        while (entries.next()) |entry| {
            const item = std.mem.trim(u8, entry, " \t\r\n");
            const equals = std.mem.indexOfScalar(u8, item, '=') orelse continue;
            const tail = item[equals + 1 ..];
            const value = tail[0 .. std.mem.indexOfScalar(u8, tail, '=') orelse tail.len];
            if (equals == 0 or value.len == 0) continue;
            const key = std.mem.trim(u8, item[0..equals], " \t\r\n");
            if (std.mem.eql(u8, key, model)) deployment = std.mem.trim(u8, value, " \t\r\n");
        }
    }
    return gpa.dupe(u8, if (deployment.len == 0) model else deployment);
}

pub fn endpoint(gpa: std.mem.Allocator, base: []const u8, suffix: []const u8, version: ?[]const u8) ![]u8 {
    var uri = std.Uri.parse(base) catch return error.InvalidAzureBaseUrl;
    const current = switch (uri.path) {
        .raw, .percent_encoded => |bytes| bytes,
    };
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ std.mem.trimEnd(u8, current, "/"), std.mem.trimStart(u8, suffix, "/") });
    defer gpa.free(path);
    uri.path = .{ .percent_encoded = path };
    uri.fragment = null;
    var query: std.Io.Writer.Allocating = .init(gpa);
    defer query.deinit();
    if (version) |api_version| {
        if (uri.query) |existing| {
            var parts = std.mem.splitScalar(u8, switch (existing) {
                .raw, .percent_encoded => |bytes| bytes,
            }, '&');
            while (parts.next()) |part| {
                const end = std.mem.indexOfScalar(u8, part, '=') orelse part.len;
                if (part.len == 0 or std.mem.eql(u8, part[0..end], "api-version")) continue;
                query.writer.writeAll(part) catch return error.OutOfMemory;
                query.writer.writeByte('&') catch return error.OutOfMemory;
            }
        }
        query.writer.writeAll("api-version=") catch return error.OutOfMemory;
        for (api_version) |byte| {
            if (std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "-._~", byte) != null)
                query.writer.writeByte(byte) catch return error.OutOfMemory
            else
                query.writer.print("%{X:0>2}", .{byte}) catch return error.OutOfMemory;
        }
        uri.query = .{ .percent_encoded = query.written() };
    }
    return std.fmt.allocPrint(gpa, "{f}", .{uri});
}

/// Azure's completions wrapper changes only the outbound deployment, retaining
/// the catalog identity passed to caller callbacks and response metadata.
pub fn deploymentPayload(gpa: std.mem.Allocator, payload: []const u8, deployment: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{ .duplicate_field_behavior = .use_last });
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidAzurePayload;
    try parsed.value.object.put(parsed.arena.allocator(), "model", .{ .string = deployment });
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    std.json.Stringify.value(parsed.value, .{}, &output.writer) catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

pub fn configurationErrorMessage(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.MissingAzureBaseUrl => "Azure OpenAI base URL is required. Set AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME, or pass azureBaseUrl, azureResourceName, or model.baseUrl.",
        error.InvalidAzureBaseUrl => "Invalid Azure OpenAI base URL",
        else => null,
    };
}

pub fn configurationErrorResponse(comptime ModelResponse: type, gpa: std.mem.Allocator, provider: []const u8, model: []const u8, err: anyerror) !ModelResponse {
    const message = configurationErrorMessage(err) orelse return err;
    const content = try gpa.dupe(u8, "");
    errdefer gpa.free(content);
    const calls = try gpa.alloc(@typeInfo(@FieldType(ModelResponse, "tool_calls")).pointer.child, 0);
    errdefer gpa.free(calls);
    const owned_provider = try gpa.dupe(u8, provider);
    errdefer gpa.free(owned_provider);
    const owned_model = try gpa.dupe(u8, model);
    errdefer gpa.free(owned_model);
    const reason = try gpa.dupe(u8, "error");
    errdefer gpa.free(reason);
    return .{ .content = content, .tool_calls = calls, .provider = owned_provider, .model = owned_model, .stop_reason = reason, .error_message = try gpa.dupe(u8, message) };
}

test "Azure config normalizes reviewed upstream endpoint cases and retains proxy queries" {
    const gpa = std.testing.allocator;
    inline for (.{
        .{ "https://my-resource.openai.azure.com", "https://my-resource.openai.azure.com/openai/v1" },
        .{ "https://my-resource.cognitiveservices.azure.com/openai/", "https://my-resource.cognitiveservices.azure.com/openai/v1" },
        .{ "https://my-resource.ai.azure.com", "https://my-resource.ai.azure.com/openai/v1" },
        .{ "https://my-resource.services.ai.azure.com/openai/v1/responses?api-version=old", "https://my-resource.services.ai.azure.com/openai/v1" },
        .{ " https://MY-RESOURCE.openai.azure.com:443/openai?api-version=old ", "https://my-resource.openai.azure.com/openai/v1" },
        .{ "https://my-proxy.example.com/v1?custom=true", "https://my-proxy.example.com/v1?custom=true" },
    }) |pair| {
        const actual = try normalizeBaseUrl(gpa, pair[0]);
        defer gpa.free(actual);
        try std.testing.expectEqualStrings(pair[1], actual);
    }
    try std.testing.expectError(error.InvalidAzureBaseUrl, normalizeBaseUrl(gpa, "not-a-url"));
    const url = try endpoint(gpa, "https://proxy.example.com/azure/v1?custom=true&api-version=old#fragment", "responses", "v1+preview");
    defer gpa.free(url);
    try std.testing.expectEqualStrings("https://proxy.example.com/azure/v1/responses?custom=true&api-version=v1%2Bpreview", url);
}

test "Azure endpoint deployment and API version precedence match scoped provider environment" {
    const gpa = std.testing.allocator;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    try environ.put("AZURE_OPENAI_BASE_URL", "https://env.ai.azure.com");
    try environ.put("AZURE_OPENAI_RESOURCE_NAME", "resource");
    try environ.put("AZURE_OPENAI_API_VERSION", "env-version");
    try environ.put("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", "bad, m=first,m=second=ignored, empty=   , =missing");
    var scoped: std.process.Environ.Map = .init(gpa);
    defer scoped.deinit();
    try scoped.put("AZURE_OPENAI_BASE_URL", "https://scoped.ai.azure.com");
    const resolved = try resolveConfig(gpa, "https://model.example/v1", &environ, .{ .env = &scoped });
    defer resolved.deinit(gpa);
    try std.testing.expectEqualStrings("https://scoped.ai.azure.com/openai/v1", resolved.base_url);
    try std.testing.expectEqualStrings("env-version", resolved.api_version);
    const deployment = try resolveDeploymentName(gpa, "m", &environ, .{});
    defer gpa.free(deployment);
    try std.testing.expectEqualStrings("second", deployment);
    const explicit = try resolveDeploymentName(gpa, "m", &environ, .{ .deployment_name = "explicit" });
    defer gpa.free(explicit);
    try std.testing.expectEqualStrings("explicit", explicit);
    const resource = try resolveConfig(gpa, "", null, .{ .resource_name = "my-resource" });
    defer resource.deinit(gpa);
    try std.testing.expectEqualStrings("https://my-resource.openai.azure.com/openai/v1", resource.base_url);
    try std.testing.expectEqualStrings("v1", resource.api_version);
    try std.testing.expectError(error.MissingAzureBaseUrl, resolveConfig(gpa, "", null, .{}));
}

fn allocationProbe(gpa: std.mem.Allocator) !void {
    const config = try resolveConfig(gpa, "", null, .{ .resource_name = "fixture" });
    defer config.deinit(gpa);
    const deployment = try resolveDeploymentName(gpa, "catalog-model", null, .{ .deployment_name = "deployment" });
    defer gpa.free(deployment);
    const url = try endpoint(gpa, config.base_url, "responses", config.api_version);
    defer gpa.free(url);
}
test "Azure endpoint configuration releases every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

//! Vertex ADC refresh inside the owned HTTP worker, without any guest values.
const std = @import("std");
const adc = @import("../ai/google_adc.zig");
const prep = @import("native_ai_http_prepare.zig");
const v = @import("native_ai_provider_values.zig");
pub fn data(scope: *v.Scope, dependencies: v.c.JSValue, options: v.c.JSValue) ![]u8 {
    const environment = try scope.object();
    inline for (.{ "GOOGLE_APPLICATION_CREDENTIALS", "HOME", "USERPROFILE" }) |name| {
        const value = try scope.invoke(try scope.get(dependencies, "env"), "getProviderEnvValue", &.{ try scope.text(name), try v.optional(scope, options, "env") });
        if (scope.truthy(value)) try scope.put(environment, name, value);
    }
    return scope.engine.toString(try scope.invoke(try scope.global("JSON"), "stringify", &.{environment}));
}
pub fn prepare(a: std.mem.Allocator, view: prep.View, raw: []const u8, budget: prep.Budget) !prep.Prepared {
    _ = try budget.remaining();
    const parsed = try std.json.parseFromSlice(std.json.Value, a, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidGoogleADCEnvironment;
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var fields = parsed.value.object.iterator();
    while (fields.next()) |field| {
        if (field.value_ptr.* != .string) return error.InvalidGoogleADCEnvironment;
        try environment.put(field.key_ptr.*, field.value_ptr.string);
    }
    var credential = (try adc.load(a, budget.io, &environment)) orelse return error.GoogleApplicationDefaultCredentialsNotFound;
    defer credential.deinit(a);
    const options: @import("../ai/bootstrap_http.zig").Options = .{ .policy = .{ .max_retries = 0, .timeout_ms = try budget.remaining() }, .abort_flag = budget.abort_flag };
    var token = switch (credential.kind) {
        .authorized_user => try adc.refreshAuthorizedUserWithOptions(a, budget.io, &credential, options),
        .service_account => try adc.refreshServiceAccountWithOptions(a, budget.io, &credential, options),
    };
    defer {
        @memset(token.token, 0);
        token.deinit(a);
    }
    _ = try budget.remaining();
    var headers: std.ArrayList(std.http.Header) = .empty;
    errdefer {
        for (headers.items) |header| {
            a.free(header.name);
            @memset(@constCast(header.value), 0);
            a.free(header.value);
        }
        headers.deinit(a);
    }
    var explicit_auth = false;
    var explicit_quota = false;
    for (view.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "authorization")) explicit_auth = true;
        if (std.ascii.eqlIgnoreCase(header.name, "x-goog-user-project")) explicit_quota = true;
    }
    if (!explicit_auth) {
        const name = try a.dupe(u8, "authorization");
        errdefer a.free(name);
        const value = try std.fmt.allocPrint(a, "Bearer {s}", .{token.token});
        errdefer {
            @memset(value, 0);
            a.free(value);
        }
        try headers.append(a, .{ .name = name, .value = value });
    }
    if (!explicit_quota) if (credential.quota_project_id) |quota| {
        const name = try a.dupe(u8, "x-goog-user-project");
        errdefer a.free(name);
        const value = try a.dupe(u8, quota);
        errdefer a.free(value);
        try headers.append(a, .{ .name = name, .value = value });
    };
    return .{ .headers = try headers.toOwnedSlice(a) };
}

test "native AI Google Mistral ADC preparation cancels before credential file access" {
    var aborted = true;
    try std.testing.expectError(error.ProviderRequestAborted, prepare(std.testing.allocator, .{ .method = .POST, .url = "http://127.0.0.1/owned", .payload = "{}", .headers = &.{} }, "{\"GOOGLE_APPLICATION_CREDENTIALS\":\"must-not-be-read\"}", .{ .io = std.testing.io, .abort_flag = &aborted, .deadline_ms = null }));
    aborted = false;
    try std.testing.expectError(error.ProviderRequestTimeout, prepare(std.testing.allocator, .{ .method = .POST, .url = "http://127.0.0.1/owned", .payload = "{}", .headers = &.{} }, "{\"GOOGLE_APPLICATION_CREDENTIALS\":\"must-not-be-read\"}", .{ .io = std.testing.io, .abort_flag = &aborted, .deadline_ms = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() - 1 }));
}

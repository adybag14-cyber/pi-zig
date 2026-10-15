//! Byte-only AWS credential chain. Called by the HTTP worker before signing.
//! Every result owns its secrets; no VM value, callback, or VM allocator crosses.
const std = @import("std");
const shared = @import("../ai/aws_credentials.zig");
const bedrock = @import("../ai/bedrock.zig");
const web = @import("../ai/aws_web_identity.zig");
const process = @import("../ai/aws_process.zig");
const container = @import("../ai/aws_container.zig");
const imds = @import("../ai/aws_imds.zig");
const role = @import("../ai/aws_assume_role.zig");
const Budget = @import("native_ai_http_prepare.zig").Budget;
fn httpOptions(budget: Budget) !@import("../ai/bootstrap_http.zig").Options {
    return .{ .abort_flag = budget.abort_flag, .policy = .{ .max_retries = 0, .timeout_ms = (try budget.remaining()) orelse 15000 } };
}
pub const Credentials = struct {
    access_key_id: []u8,
    secret_access_key: []u8,
    session_token: ?[]u8 = null,
    expiration_unix: ?i64 = null,
    pub fn deinit(self: *Credentials, a: std.mem.Allocator) void {
        @memset(self.secret_access_key, 0);
        a.free(self.access_key_id);
        a.free(self.secret_access_key);
        if (self.session_token) |token| {
            @memset(token, 0);
            a.free(token);
        }
        self.* = undefined;
    }
    pub fn borrowed(self: *const Credentials) bedrock.AwsCredentials {
        return .{ .access_key_id = self.access_key_id, .secret_access_key = self.secret_access_key, .session_token = self.session_token };
    }
};
fn copy(a: std.mem.Allocator, input: bedrock.AwsCredentials, expiration: ?i64, now: i64) !Credentials {
    if (expiration) |expires| if (expires <= now) return error.AwsCredentialsExpired;
    const access = try a.dupe(u8, input.access_key_id);
    errdefer a.free(access);
    const secret = try a.dupe(u8, input.secret_access_key);
    errdefer a.free(secret);
    return .{ .access_key_id = access, .secret_access_key = secret, .session_token = if (input.session_token) |token| try a.dupe(u8, token) else null, .expiration_unix = expiration };
}
fn envCredentials(env: *const std.process.Environ.Map) ?bedrock.AwsCredentials {
    const access = env.get("AWS_ACCESS_KEY_ID") orelse return null;
    const secret = env.get("AWS_SECRET_ACCESS_KEY") orelse return null;
    if (access.len == 0 or secret.len == 0) return null;
    const token = env.get("AWS_SESSION_TOKEN");
    return .{ .access_key_id = access, .secret_access_key = secret, .session_token = if (token != null and token.?.len > 0) token else null };
}
pub fn resolve(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, profile: ?[]const u8, region: []const u8, now: i64, budget: Budget) !Credentials {
    _ = try budget.remaining();
    // An explicitly configured options.profile/scoped AWS_PROFILE wins over env keys.
    // Ambient AWS_PROFILE alone does not suppress the Source explicit env credentials.
    if (profile == null) if (envCredentials(env)) |credentials| return copy(a, credentials, null, now);
    var chain: [32]?[]const u8 = @splat(null);
    const name = profile orelse env.get("AWS_PROFILE") orelse "default";
    if (try resolveProfile(a, io, env, name, region, now, &chain, 0, budget)) |credentials| return credentials;
    if (web.resolveConfig(env, null)) |config| {
        var resolved = config;
        const generated = try std.fmt.allocPrint(a, "aws-sdk-js-session-{d}", .{std.Io.Clock.real.now(io).toMilliseconds()});
        defer a.free(generated);
        if (env.get("AWS_ROLE_SESSION_NAME") == null) resolved.session_name = generated;
        var temporary = try web.assumeRoleWithOptions(a, io, resolved, try httpOptions(budget));
        defer temporary.deinit(a);
        return copy(a, temporary.borrowed(), temporary.expiration_unix, now);
    }
    if (try container.resolveConfig(a, io, env)) |initial| {
        var config = initial;
        defer config.deinit(a);
        var temporary = try container.fetchCredentialsWithOptions(a, io, config, try httpOptions(budget));
        defer temporary.deinit(a);
        return copy(a, temporary.borrowed(), temporary.expiration_unix, now);
    }
    if (imds.metadataDisabled(env)) return error.MissingBedrockCredentials;
    var temporary = try imds.fetchCredentialsWithOptions(a, io, try imds.resolveConfig(env, null), try httpOptions(budget));
    defer temporary.deinit(a);
    return copy(a, temporary.borrowed(), temporary.expiration_unix, now);
}
fn resolveProfile(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, name: []const u8, region: []const u8, now: i64, chain: *[32]?[]const u8, depth: usize, budget: Budget) anyerror!?Credentials {
    _ = try budget.remaining();
    if (depth >= chain.len) return error.AwsProfileChainTooDeep;
    for (chain[0..depth]) |previous| if (std.mem.eql(u8, previous.?, name)) return error.AwsProfileCycle;
    chain[depth] = name;
    var profile = (try shared.loadProfileByName(a, io, env, name)) orelse return null;
    defer profile.deinit(a);
    if (depth > 0) if (profile.staticCredentials()) |credentials| return try copy(a, credentials, null, now);
    if (profile.role_arn != null and profile.web_identity_token_file == null and ((profile.source_profile != null) != (profile.credential_source != null))) {
        if (profile.mfa_serial != null) return error.AwsProfileRequiresMfaCallback;
        var source: Credentials = undefined;
        if (profile.source_profile) |source_name| {
            source = (try resolveProfile(a, io, env, source_name, region, now, chain, depth + 1, budget)) orelse return error.AwsSourceProfileMissing;
        } else if (profile.credential_source) |kind| {
            if (std.mem.eql(u8, kind, "Environment")) {
                source = try copy(a, envCredentials(env) orelse return error.MissingBedrockCredentials, null, now);
            } else if (std.mem.eql(u8, kind, "EcsContainer")) {
                var config = (try container.resolveConfig(a, io, env)) orelse return error.MissingContainerCredentials;
                defer config.deinit(a);
                var temporary = try container.fetchCredentialsWithOptions(a, io, config, try httpOptions(budget));
                defer temporary.deinit(a);
                source = try copy(a, temporary.borrowed(), temporary.expiration_unix, now);
            } else if (std.mem.eql(u8, kind, "Ec2InstanceMetadata")) {
                var temporary = try imds.fetchCredentialsWithOptions(a, io, try imds.resolveConfig(env, &profile), try httpOptions(budget));
                defer temporary.deinit(a);
                source = try copy(a, temporary.borrowed(), temporary.expiration_unix, now);
            } else return error.UnsupportedAwsCredentialSource;
        } else return error.AwsRoleSourceMissing;
        defer source.deinit(a);
        const generated = try std.fmt.allocPrint(a, "aws-sdk-js-{d}", .{std.Io.Clock.real.now(io).toMilliseconds()});
        defer a.free(generated);
        var temporary = try assumeRole(a, io, env, source.borrowed(), .{ .role_arn = profile.role_arn.?, .role_session_name = profile.role_session_name orelse generated, .external_id = profile.external_id, .duration_seconds = profile.duration_seconds orelse 3600, .region = profile.region orelse region }, now, budget);
        defer temporary.deinit(a);
        return try copy(a, temporary.borrowed(), temporary.expiration_unix, now);
    }
    if (profile.staticCredentials()) |credentials| return try copy(a, credentials, null, now);
    if (profile.hasWebIdentity()) {
        const generated = try std.fmt.allocPrint(a, "aws-sdk-js-session-{d}", .{std.Io.Clock.real.now(io).toMilliseconds()});
        defer a.free(generated);
        var temporary = try web.assumeRoleWithOptions(a, io, .{ .role_arn = profile.role_arn.?, .token_file = profile.web_identity_token_file.?, .session_name = profile.role_session_name orelse env.get("AWS_ROLE_SESSION_NAME") orelse generated, .endpoint = env.get("AWS_ENDPOINT_URL_STS") orelse "https://sts.amazonaws.com" }, try httpOptions(budget));
        defer temporary.deinit(a);
        return try copy(a, temporary.borrowed(), temporary.expiration_unix, now);
    }
    if (profile.credential_process) |command| {
        var temporary = try runProcess(a, io, command, budget);
        defer temporary.deinit(a);
        return try copy(a, temporary.borrowed(), temporary.expiration_unix, now);
    }
    if (profile.sso_session != null or profile.sso_start_url != null or profile.sso_account_id != null or profile.sso_role_name != null or profile.sso_region != null) return error.UnsupportedAwsSsoProfile;
    if (profile.login_session != null) return error.UnsupportedAwsLoginProfile;
    return null;
}
fn assumeRole(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, source: bedrock.AwsCredentials, options: role.Options, now: i64, budget: Budget) !role.OwnedAssumedCredentials {
    const endpoint = if (env.get("AWS_ENDPOINT_URL_STS")) |url| try a.dupe(u8, url) else try role.endpointForRegion(a, options.region);
    defer a.free(endpoint);
    const body = try role.buildAssumeRoleBody(a, options);
    defer a.free(body);
    const content_type = "application/x-www-form-urlencoded; charset=utf-8";
    var signed = try bedrock.signAwsRequestForService(a, "POST", endpoint, body, source, options.region, "sts", content_type, now);
    defer signed.deinit(a);
    var headers: std.ArrayList(std.http.Header) = .empty;
    defer headers.deinit(a);
    try headers.appendSlice(a, &.{ .{ .name = "content-type", .value = content_type }, .{ .name = "authorization", .value = signed.authorization }, .{ .name = "x-amz-date", .value = &signed.amz_date } });
    if (source.session_token) |token| try headers.append(a, .{ .name = "x-amz-security-token", .value = token });
    var response = try @import("../ai/bootstrap_http.zig").request(a, io, .{ .url = endpoint, .method = .POST, .payload = body, .headers = headers.items, .options = try httpOptions(budget) });
    defer response.deinit(a);
    return role.parseAssumeRoleResponse(a, response.body);
}
fn runProcess(a: std.mem.Allocator, io: std.Io, command: []const u8, budget: Budget) !process.OwnedProcessCredentials {
    const owned = try process.splitCommand(a, command);
    defer process.freeArgv(a, owned);
    const argv: []const []const u8 = owned;
    const milliseconds = @min((try budget.remaining()) orelse 15000, 15000);
    const Completion = union(enum) { child: anyerror!std.process.RunResult, canceled: anyerror!void };
    var results: [2]Completion = undefined;
    var selected = std.Io.Select(Completion).init(io, &results);
    // Canceling process.run reaches its pipe/wait cancellation point and then
    // kills and reaps only the Child handle created inside that invocation.
    // Drain racing successful results too: their stdout can contain secrets.
    defer while (selected.cancel()) |completion| switch (completion) {
        .child => |finished| if (finished) |value| freeProcessOutput(a, value) else |_| {},
        .canceled => {},
    };
    try selected.concurrent(.child, std.process.run, .{ a, io, std.process.RunOptions{ .argv = argv, .stdout_limit = .limited(64 * 1024), .stderr_limit = .limited(8 * 1024), .create_no_window = true, .timeout = .{ .duration = .{ .raw = .fromMilliseconds(@intCast(milliseconds)), .clock = .awake } } } });
    try selected.concurrent(.canceled, watchBudget, .{budget});
    const result = switch (try selected.await()) {
        .child => |finished| try finished,
        .canceled => |finished| {
            try finished;
            unreachable;
        },
    };
    defer freeProcessOutput(a, result);
    _ = try budget.remaining();
    switch (result.term) {
        .exited => |code| if (code != 0) return error.CredentialProcessFailed,
        else => return error.CredentialProcessFailed,
    }
    return process.parseCredentialProcessJson(a, result.stdout);
}
fn watchBudget(budget: Budget) !void {
    while (true) {
        _ = try budget.remaining();
        try budget.io.sleep(.fromMilliseconds(20), .awake);
    }
}
fn freeProcessOutput(a: std.mem.Allocator, output: std.process.RunResult) void {
    @memset(output.stdout, 0);
    @memset(output.stderr, 0);
    a.free(output.stdout);
    a.free(output.stderr);
}
test "native AI Bedrock credential process cancellation joins and reaps only its owned subprocess" {
    const io = std.testing.io;
    var aborted = false;
    const Cancel = struct {
        fn later(task_io: std.Io, flag: *bool) !void {
            try task_io.sleep(.fromMilliseconds(100), .awake);
            @atomicStore(bool, flag, true, .release);
        }
    };
    var cancellation = try io.concurrent(Cancel.later, .{ io, &aborted });
    defer cancellation.await(io) catch {};
    const start = std.Io.Clock.awake.now(io).toMilliseconds();
    const command = if (@import("builtin").os.tag == .windows) "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -NonInteractive -Command \"Start-Sleep -Seconds 30\"" else "/bin/sleep 30";
    try std.testing.expectError(error.ProviderRequestAborted, runProcess(std.testing.allocator, io, command, .{ .io = io, .abort_flag = &aborted, .deadline_ms = start + 5000 }));
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - start < 3000);
}

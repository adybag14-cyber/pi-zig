//! Actual provider-specific ApiKeyAuth bodies. Caller values remain VM roots.
//! No ambient credential file or endpoint is read by these constructors.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const helpers = @import("native_ai_auth_helpers.zig");
pub const Kind = enum { anthropic, bedrock, vertex, cloudflare_workers, cloudflare_gateway };
const Stage = enum(c_int) { login, env_value, anthropic, bedrock, vertex_key, vertex_path, vertex_file, vertex_project, vertex_project_fallback, vertex_location, cloudflare_value, cloudflare_result };
const federation_required = [_][]const u8{ "ANTHROPIC_FEDERATION_RULE_ID", "ANTHROPIC_ORGANIZATION_ID", "ANTHROPIC_IDENTITY_TOKEN_FILE" };
const federation_optional = [_][]const u8{ "ANTHROPIC_SERVICE_ACCOUNT_ID", "ANTHROPIC_WORKSPACE_ID" };
const bedrock_names = [_][]const u8{ "AWS_BEARER_TOKEN_BEDROCK", "AWS_PROFILE", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "AWS_CONTAINER_CREDENTIALS_FULL_URI", "AWS_WEB_IDENTITY_TOKEN_FILE" };

fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn opt(s: *Scope, object: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (v.nullish(object)) c.pi_js_undefined() else s.get(object, key);
}
fn kindOf(s: *Scope, owner: c.JSValue) !Kind {
    var n: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &n, try s.get(owner, "agent")) < 0) return v.js.capture(s.engine);
    return @enumFromInt(n);
}
fn currentIndex(s: *Scope, owner: c.JSValue) !usize {
    var n: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &n, try s.get(owner, "index")) < 0) return v.js.capture(s.engine);
    return n;
}
fn setIndex(s: *Scope, owner: c.JSValue, value: usize) !void {
    try s.put(owner, "index", c.JS_NewInt32(s.engine.context, @intCast(value)));
}
fn abort(s: *Scope, owner: c.JSValue) !void {
    _ = try s.invoke(try s.get(owner, "signal"), "throwIfAborted", &.{});
}
fn done(s: *Scope, owner: c.JSValue, result: c.JSValue) !void {
    return flow.settle(s.engine, owner, false, result);
}
fn wait(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, s.engine, owner, value, @intFromEnum(stage));
}
fn raise(s: *Scope, prefix: []const u8, value: c.JSValue) !void {
    const constructor = try s.global("Error");
    const message = try s.concat(try s.text(prefix), try s.stringify(value));
    var arguments = [_]c.JSValue{message};
    _ = try s.engine.checked(c.JS_Throw(s.engine.context, try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, arguments.len, &arguments))));
    unreachable;
}

pub fn create(engine: *v.em.Engine, kind: Kind) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.object();
    try s.put(result, "name", try s.text(switch (kind) {
        .anthropic => "Anthropic API key",
        .bedrock => "AWS credentials or bearer token",
        .vertex => "Google Cloud credentials",
        else => "Cloudflare API key",
    }));
    const roots = [_]c.JSValue{c.JS_NewInt32(engine.context, @intFromEnum(kind))};
    try s.put(result, "login", try s.own(try helpers.asyncArrow(engine, "login", 1, login, &roots)));
    try s.put(result, "resolve", try s.own(try helpers.asyncArrow(engine, "resolve", 1, resolve, &roots)));
    return c.JS_DupValue(engine.context, result);
}
fn login(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startLogin(&s, pending.owner, arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn prompt(s: *Scope, owner: c.JSValue, kind: []const u8, message: []const u8, options: c.JSValue) !void {
    const interaction = try s.get(owner, "interaction");
    const method = try s.get(interaction, "prompt");
    const input = try s.object();
    try s.put(input, "type", try s.text(kind));
    try s.put(input, "message", try s.text(message));
    if (!c.JS_IsUndefined(options)) try s.put(input, "options", options);
    return wait(s, owner, try s.call(method, interaction, &.{input}), .login);
}
fn startLogin(s: *Scope, owner: c.JSValue, interaction: c.JSValue) !void {
    try s.put(owner, "interaction", interaction);
    try setIndex(s, owner, 0);
    const kind = try kindOf(s, owner);
    if (kind == .cloudflare_workers or kind == .cloudflare_gateway) return prompt(s, owner, "secret", "Enter Cloudflare API key", c.pi_js_undefined());
    try s.put(owner, "signal", try s.get(interaction, "signal"));
    try abort(s, owner);
    if (kind == .anthropic) return prompt(s, owner, "secret", "Enter Anthropic API key", c.pi_js_undefined());
    const options = try s.array();
    const choices: []const struct { []const u8, []const u8 } = if (kind == .bedrock) &.{ .{ "bearer-token", "Bearer token" }, .{ "aws-profile", "AWS profile" }, .{ "credential-chain", "Existing AWS credential chain" } } else &.{ .{ "api-key", "Google Cloud API key" }, .{ "adc", "Application Default Credentials" }, .{ "service-account", "Service account credentials file" } };
    for (choices, 0..) |choice, i| {
        const item = try s.object();
        try s.put(item, "id", try s.text(choice[0]));
        try s.put(item, "label", try s.text(choice[1]));
        try s.index(options, @intCast(i), item);
    }
    return prompt(s, owner, "select", if (kind == .bedrock) "Select Amazon Bedrock authentication method:" else "Select Google Vertex AI authentication method:", options);
}
fn credential(s: *Scope, owner: c.JSValue, key: c.JSValue, env: c.JSValue) !void {
    const value = try s.object();
    try s.put(value, "type", try s.text("api_key"));
    const kind = try kindOf(s, owner);
    const method = try s.get(owner, "method");
    if (!c.JS_IsUndefined(key) or kind == .anthropic or kind == .cloudflare_workers or kind == .cloudflare_gateway or try v.eq(s, method, "bearer-token") or try v.eq(s, method, "api-key")) try s.put(value, "key", key);
    if (!c.JS_IsUndefined(env)) try s.put(value, "env", env);
    return done(s, owner, value);
}
fn loginReady(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    const kind = try kindOf(s, owner);
    const step = try currentIndex(s, owner);
    if (kind == .anthropic) {
        try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
        try abort(s, owner);
        return credential(s, owner, value, c.pi_js_undefined());
    }
    if (kind == .cloudflare_workers or kind == .cloudflare_gateway) {
        if (step == 0) {
            try s.put(owner, "key", value);
            try setIndex(s, owner, 1);
            return prompt(s, owner, "text", "Enter Cloudflare account ID", c.pi_js_undefined());
        }
        if (step == 1 and kind == .cloudflare_gateway) {
            try s.put(owner, "account", value);
            try setIndex(s, owner, 2);
            return prompt(s, owner, "text", "Enter Cloudflare AI Gateway ID", c.pi_js_undefined());
        }
        const env = try s.object();
        try s.put(env, "CLOUDFLARE_ACCOUNT_ID", if (step == 1) value else try s.get(owner, "account"));
        if (step == 2) try s.put(env, "CLOUDFLARE_GATEWAY_ID", value);
        return credential(s, owner, try s.get(owner, "key"), env);
    }
    if (step == 0) {
        // Source reads interaction.signal again after the selection await.
        try s.put(owner, "signal", try s.get(try s.get(owner, "interaction"), "signal"));
        try abort(s, owner);
        try s.put(owner, "method", value);
        try setIndex(s, owner, 1);
        if (try v.eq(s, value, if (kind == .bedrock) "bearer-token" else "api-key")) return prompt(s, owner, "secret", if (kind == .bedrock) "Enter Amazon Bedrock bearer token" else "Enter Google Cloud API key", c.pi_js_undefined());
        if (kind == .vertex and !(try v.eq(s, value, "adc")) and !(try v.eq(s, value, "service-account"))) return raise(s, "Unknown Google Vertex AI auth method: ", value);
        const interaction = try s.get(owner, "interaction");
        const notify = try s.get(interaction, "notify");
        const notification = try s.object();
        try s.put(notification, "type", try s.text("info"));
        try s.put(notification, "message", try s.text(if (kind == .bedrock) "Amazon Bedrock supports AWS profiles, IAM credentials, and role-based credentials." else if (try v.eq(s, value, "adc")) "Run `gcloud auth application-default login`, then provide the project and location." else "Provide a service account credentials file, project, and location."));
        const links = try s.array();
        const link = try s.object();
        try s.put(link, "label", try s.text(if (kind == .bedrock) "AWS credential provider chain" else "Application Default Credentials"));
        try s.put(link, "url", try s.text(if (kind == .bedrock) "https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html" else "https://cloud.google.com/docs/authentication/provide-credentials-adc"));
        try s.index(links, 0, link);
        try s.put(notification, "links", links);
        _ = try s.call(notify, interaction, &.{notification});
        if (kind == .bedrock) {
            if (try v.eq(s, value, "aws-profile")) return prompt(s, owner, "text", "Enter AWS profile name", c.pi_js_undefined());
            if (!(try v.eq(s, value, "credential-chain"))) return raise(s, "Unknown Amazon Bedrock auth method: ", value);
            return prompt(s, owner, "text", "Configure AWS credentials, then press Enter to continue", c.pi_js_undefined());
        }
        return prompt(s, owner, "text", "Enter Google Cloud project ID", c.pi_js_undefined());
    }
    const method = try s.get(owner, "method");
    if (try v.eq(s, method, if (kind == .bedrock) "bearer-token" else "api-key")) return credential(s, owner, value, c.pi_js_undefined());
    const env = try s.object();
    if (kind == .bedrock) {
        if (try v.eq(s, method, "aws-profile")) {
            try s.put(env, "AWS_PROFILE", value);
            return credential(s, owner, c.pi_js_undefined(), env);
        }
        return credential(s, owner, c.pi_js_undefined(), c.pi_js_undefined());
    }
    if (step == 1) {
        try s.put(owner, "project", value);
        try setIndex(s, owner, 2);
        return prompt(s, owner, "text", "Enter Google Cloud location", c.pi_js_undefined());
    }
    if (step == 2 and try v.eq(s, method, "service-account")) {
        try s.put(owner, "location", value);
        try setIndex(s, owner, 3);
        return prompt(s, owner, "text", "Enter service account credentials file path", c.pi_js_undefined());
    }
    try s.put(env, "GOOGLE_CLOUD_PROJECT", try s.get(owner, "project"));
    try s.put(env, "GOOGLE_CLOUD_LOCATION", if (step == 2) value else try s.get(owner, "location"));
    if (step == 3 and s.truthy(value)) try s.put(env, "GOOGLE_APPLICATION_CREDENTIALS", value);
    return credential(s, owner, c.pi_js_undefined(), env);
}
fn resolve(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startResolve(&s, pending.owner, arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn authResult(s: *Scope, owner: c.JSValue, auth: c.JSValue, env: c.JSValue, source: c.JSValue) !void {
    const output = try s.object();
    try s.put(output, "auth", auth);
    if (!c.JS_IsUndefined(env) or s.truthy(try s.get(owner, "envField"))) try s.put(output, "env", env);
    try s.put(output, "source", source);
    return done(s, owner, output);
}
fn keyAuth(s: *Scope, owner: c.JSValue, key: c.JSValue, source: c.JSValue, include_env: bool) !void {
    try s.put(owner, "envField", c.JS_NewBool(s.engine.context, include_env));
    const auth = try s.object();
    try s.put(auth, "apiKey", key);
    return authResult(s, owner, auth, if (include_env) try opt(s, try s.get(owner, "credential"), "env") else c.pi_js_undefined(), source);
}
fn credentialEnv(s: *Scope, owner: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return opt(s, try opt(s, try s.get(owner, "credential"), "env"), name);
}
fn startResolve(s: *Scope, owner: c.JSValue, input: c.JSValue) !void {
    inline for (.{ "ctx", "credential", "signal" }) |name| try s.put(owner, name, try s.get(input, name));
    const kind = try kindOf(s, owner);
    const stored = try s.get(owner, "credential");
    if (kind == .anthropic) try abort(s, owner);
    if (kind == .anthropic or kind == .bedrock) {
        if (s.truthy(try opt(s, stored, "key"))) return keyAuth(s, owner, try opt(s, stored, "key"), try s.text("stored credential"), true);
        try setIndex(s, owner, 0);
        if (kind == .anthropic) {
            try s.put(owner, "federation", try s.object());
            return directEnv(s, owner, "ANTHROPIC_AUTH_TOKEN", .anthropic);
        }
        return awaitEnv(s, owner, bedrock_names[0], .bedrock);
    }
    if (kind == .vertex) {
        const key = try opt(s, stored, "key");
        return if (v.nullish(key)) awaitEnv(s, owner, "GOOGLE_CLOUD_API_KEY", .vertex_key) else vertexKey(s, owner, key);
    }
    const nested = try flow.create(s.engine, try s.get(owner, "agent"));
    defer s.engine.freeValue(nested.owner);
    const promise = try s.own(nested.promise);
    inline for (.{ "ctx", "credential", "signal" }) |name| try s.put(nested.owner, name, try s.get(owner, name));
    try setIndex(s, nested.owner, 0);
    try s.put(nested.owner, "values", try s.array());
    cloudflareValue(s, nested.owner) catch |err| try flow.rejectError(s.engine, nested.owner, err);
    return wait(s, owner, promise, .cloudflare_result);
}
fn directEnv(s: *Scope, owner: c.JSValue, name: []const u8, stage: Stage) !void {
    return wait(s, owner, try s.invoke(try s.get(owner, "ctx"), "env", &.{try s.text(name)}), stage);
}
fn awaitEnv(s: *Scope, owner: c.JSValue, name: []const u8, stage: Stage) !void {
    const nested = try flow.create(s.engine, c.pi_js_undefined());
    defer s.engine.freeValue(nested.owner);
    const promise = try s.own(nested.promise);
    try s.put(nested.owner, "signal", try s.get(owner, "signal"));
    const Start = struct {
        fn run(local: *Scope, target: c.JSValue, source: c.JSValue, key: []const u8) !void {
            try abort(local, target);
            return wait(local, target, try local.invoke(try local.get(source, "ctx"), "env", &.{try local.text(key)}), .env_value);
        }
    };
    Start.run(s, nested.owner, owner, name) catch |err| try flow.rejectError(s.engine, nested.owner, err);
    return wait(s, owner, promise, stage);
}
fn anthropicReady(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    try abort(s, owner);
    const step = try currentIndex(s, owner);
    if (step == 0 and s.truthy(value)) {
        const headers = try s.object();
        try s.put(headers, "Authorization", try s.concat(try s.text("Bearer "), try s.stringify(value)));
        const auth = try s.object();
        try s.put(auth, "headers", headers);
        return authResult(s, owner, auth, c.pi_js_undefined(), try s.text("ANTHROPIC_AUTH_TOKEN"));
    }
    if (step == 1 or step == 2) {
        if (s.truthy(value)) return keyAuth(s, owner, value, try s.text(if (step == 1) "ANTHROPIC_OAUTH_TOKEN" else "ANTHROPIC_API_KEY"), false);
    }
    if (step >= 3 and step <= 5) {
        if (!s.truthy(value)) return done(s, owner, c.pi_js_undefined());
        try v.js.setKey(s.engine, try s.get(owner, "federation"), try s.text(federation_required[step - 3]), value);
    }
    if (step >= 6 and s.truthy(value)) try v.js.setKey(s.engine, try s.get(owner, "federation"), try s.text(federation_optional[step - 6]), value);
    if (step == 7) return authResult(s, owner, try s.object(), try s.get(owner, "federation"), try s.text("workload identity federation"));
    try setIndex(s, owner, step + 1);
    const name: []const u8 = if (step == 0) "ANTHROPIC_OAUTH_TOKEN" else if (step == 1) "ANTHROPIC_API_KEY" else if (step < 5) federation_required[step - 2] else federation_optional[step - 5];
    return directEnv(s, owner, name, .anthropic);
}
fn bedrockReady(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    const step = try currentIndex(s, owner);
    if (step == 0 and s.truthy(value)) return authResult(s, owner, try s.object(), c.pi_js_undefined(), try s.text("AWS_BEARER_TOKEN_BEDROCK"));
    if (step == 1 and s.truthy(value)) {
        try s.put(owner, "envField", c.JS_NewBool(s.engine.context, true));
        return authResult(s, owner, try s.object(), try opt(s, try s.get(owner, "credential"), "env"), try s.text(if (s.truthy(try credentialEnv(s, owner, "AWS_PROFILE"))) "stored credential" else "AWS_PROFILE"));
    }
    if (step == 3 and s.truthy(value)) return authResult(s, owner, try s.object(), c.pi_js_undefined(), try s.text("AWS access keys"));
    if (step >= 4 and s.truthy(value)) return authResult(s, owner, try s.object(), c.pi_js_undefined(), try s.text(if (step == 6) "web identity token" else "ECS task role"));
    if (step == 6) return done(s, owner, c.pi_js_undefined());
    const next = if (step == 2 and !s.truthy(value)) @as(usize, 4) else step + 1;
    try setIndex(s, owner, next);
    if (next == 1) {
        const stored = try credentialEnv(s, owner, "AWS_PROFILE");
        if (!v.nullish(stored)) return bedrockReady(s, owner, stored);
    }
    return awaitEnv(s, owner, bedrock_names[next], .bedrock);
}
fn vertexKey(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    if (s.truthy(value)) return keyAuth(s, owner, value, try s.text(if (s.truthy(try opt(s, try s.get(owner, "credential"), "key"))) "stored credential" else "GOOGLE_CLOUD_API_KEY"), false);
    const path = try credentialEnv(s, owner, "GOOGLE_APPLICATION_CREDENTIALS");
    return if (v.nullish(path)) awaitEnv(s, owner, "GOOGLE_APPLICATION_CREDENTIALS", .vertex_path) else vertexPath(s, owner, path);
}
fn vertexPath(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    try abort(s, owner);
    return wait(s, owner, try s.invoke(try s.get(owner, "ctx"), "fileExists", &.{if (v.nullish(value)) try s.text("~/.config/gcloud/application_default_credentials.json") else value}), .vertex_file);
}
fn vertexProject(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    if (v.nullish(value)) return awaitEnv(s, owner, "GCLOUD_PROJECT", .vertex_project_fallback);
    return vertexLocation(s, owner, value);
}
fn vertexLocation(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    try s.put(owner, "project", value);
    const location = try credentialEnv(s, owner, "GOOGLE_CLOUD_LOCATION");
    return if (v.nullish(location)) awaitEnv(s, owner, "GOOGLE_CLOUD_LOCATION", .vertex_location) else vertexDone(s, owner, location);
}
fn vertexDone(s: *Scope, owner: c.JSValue, location: c.JSValue) !void {
    if (!s.truthy(try s.get(owner, "hasCredentials")) or !s.truthy(try s.get(owner, "project")) or !s.truthy(location)) return done(s, owner, c.pi_js_undefined());
    const stored = try s.get(owner, "credential");
    try s.put(owner, "envField", c.JS_NewBool(s.engine.context, true));
    return authResult(s, owner, try s.object(), try opt(s, stored, "env"), try s.text(if (s.truthy(stored)) "stored credential" else "gcloud application default credentials"));
}
fn cloudflareValue(s: *Scope, owner: c.JSValue) !void {
    const step = try currentIndex(s, owner);
    const name = ([_][]const u8{ "CLOUDFLARE_API_KEY", "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_GATEWAY_ID" })[step];
    const nested = try flow.create(s.engine, c.pi_js_undefined());
    defer s.engine.freeValue(nested.owner);
    const promise = try s.own(nested.promise);
    try s.put(nested.owner, "signal", try s.get(owner, "signal"));
    const Resolve = struct {
        fn run(local: *Scope, target: c.JSValue, source: c.JSValue, key: []const u8, position: usize) !void {
            const stored = try local.get(source, "credential");
            const environment = if (position == 0 or !local.truthy(stored)) c.pi_js_undefined() else try opt(local, stored, "env");
            const value = if (!local.truthy(stored)) c.pi_js_undefined() else if (position == 0) try local.get(stored, "key") else if (v.nullish(environment)) c.pi_js_undefined() else try local.own(try v.js.getKey(local.engine, environment, try local.text(key)));
            if (!c.JS_IsUndefined(value)) return done(local, target, value);
            try abort(local, target);
            return directEnv(local, target, key, .env_value);
        }
    };
    try s.put(nested.owner, "ctx", try s.get(owner, "ctx"));
    Resolve.run(s, nested.owner, owner, name, step) catch |err| try flow.rejectError(s.engine, nested.owner, err);
    return wait(s, owner, promise, .cloudflare_value);
}
fn cloudflareReady(s: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    const step = try currentIndex(s, owner);
    const values = try s.get(owner, "values");
    try s.index(values, @intCast(step), value);
    const kind = try kindOf(s, owner);
    if (step < (if (kind == .cloudflare_gateway) @as(usize, 2) else 1)) {
        try setIndex(s, owner, step + 1);
        return cloudflareValue(s, owner);
    }
    const key = try v.at(s, values, 0);
    const account = try v.at(s, values, 1);
    const gateway = if (kind == .cloudflare_gateway) try v.at(s, values, 2) else c.pi_js_undefined();
    if (!s.truthy(key) or !s.truthy(account) or (kind == .cloudflare_gateway and !s.truthy(gateway))) return done(s, owner, c.pi_js_undefined());
    const resolved = try s.object();
    try s.put(resolved, "apiKey", key);
    const environment = try s.object();
    try s.put(environment, "CLOUDFLARE_ACCOUNT_ID", account);
    if (s.truthy(gateway)) try s.put(environment, "CLOUDFLARE_GATEWAY_ID", gateway);
    try s.put(resolved, "env", environment);
    try s.put(resolved, "source", try s.text(if (s.truthy(try s.get(owner, "credential"))) "stored credential" else "CLOUDFLARE_API_KEY"));
    return done(s, owner, resolved);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    advance(&s, owner, value, @enumFromInt(raw)) catch |err| try flow.rejectError(engine, owner, err);
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .login => return loginReady(s, owner, value),
        .env_value => {
            try abort(s, owner);
            return done(s, owner, value);
        },
        .anthropic => return anthropicReady(s, owner, value),
        .bedrock => return bedrockReady(s, owner, value),
        .vertex_key => return vertexKey(s, owner, value),
        .vertex_path => return vertexPath(s, owner, value),
        .vertex_file => {
            try abort(s, owner);
            try s.put(owner, "hasCredentials", value);
            const project = try credentialEnv(s, owner, "GOOGLE_CLOUD_PROJECT");
            return if (v.nullish(project)) awaitEnv(s, owner, "GOOGLE_CLOUD_PROJECT", .vertex_project) else vertexProject(s, owner, project);
        },
        .vertex_project => return vertexProject(s, owner, value),
        .vertex_project_fallback => return vertexLocation(s, owner, value),
        .vertex_location => return vertexDone(s, owner, value),
        .cloudflare_value => return cloudflareReady(s, owner, value),
        .cloudflare_result => {
            if (c.JS_IsUndefined(value)) return done(s, owner, value);
            const auth = try s.object();
            if (try kindOf(s, owner) == .cloudflare_gateway) {
                const headers = try s.object();
                try s.put(headers, "cf-aig-authorization", try s.concat(try s.text("Bearer "), try s.stringify(try s.get(value, "apiKey"))));
                try s.put(headers, "Authorization", c.pi_js_null());
                try s.put(headers, "x-api-key", c.pi_js_null());
                try s.put(auth, "headers", headers);
            } else try s.put(auth, "apiKey", try s.get(value, "apiKey"));
            return authResult(s, owner, auth, try s.get(value, "env"), try s.get(value, "source"));
        },
    }
}

//! Original provider env lookup and API-key discovery over live guest values.
//! Filesystem/home/path functions represent the original lazy Node imports;
//! undefined dependencies preserve the pre-load/browser ADC branch.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const temp = @import("native_models_stream_scope.zig");
const c = em.c;
pub const NodeDependencies = struct { exists_sync: ?c.JSValue = null, homedir: ?c.JSValue = null, join: ?c.JSValue = null };
const env_map = .{
    .{ "ant-ling", "ANT_LING_API_KEY" },                           .{ "qwen-token-plan", "QWEN_TOKEN_PLAN_API_KEY" },             .{ "qwen-token-plan-cn", "QWEN_TOKEN_PLAN_CN_API_KEY" }, .{ "qwen-token-plan-individual", "QWEN_TOKEN_PLAN_API_KEY" },
    .{ "openai", "OPENAI_API_KEY" },                               .{ "azure", "AZURE_OPENAI_API_KEY" },                          .{ "nvidia", "NVIDIA_API_KEY" },                         .{ "deepseek", "DEEPSEEK_API_KEY" },
    .{ "google", "GEMINI_API_KEY" },                               .{ "google-vertex", "GOOGLE_CLOUD_API_KEY" },                  .{ "groq", "GROQ_API_KEY" },                             .{ "cerebras", "CEREBRAS_API_KEY" },
    .{ "xai", "XAI_API_KEY" },                                     .{ "typesafe", "TYPESAFE_API_KEY" },                           .{ "radius", "RADIUS_API_KEY" },                         .{ "openrouter", "OPENROUTER_API_KEY" },
    .{ "vercel-ai-gateway", "AI_GATEWAY_API_KEY" },                .{ "zai", "ZAI_API_KEY" },                                     .{ "zai-coding-cn", "ZAI_CODING_CN_API_KEY" },           .{ "mistral", "MISTRAL_API_KEY" },
    .{ "minimax", "MINIMAX_API_KEY" },                             .{ "minimax-cn", "MINIMAX_CN_API_KEY" },                       .{ "moonshotai", "MOONSHOT_API_KEY" },                   .{ "moonshotai-cn", "MOONSHOT_API_KEY" },
    .{ "huggingface", "HF_TOKEN" },                                .{ "fireworks", "FIREWORKS_API_KEY" },                         .{ "together", "TOGETHER_API_KEY" },                     .{ "baseten", "BASETEN_API_KEY" },
    .{ "opencode", "OPENCODE_API_KEY" },                           .{ "opencode-go", "OPENCODE_API_KEY" },                        .{ "kimi-coding", "KIMI_API_KEY" },                      .{ "meta", "META_API_KEY" },
    .{ "cloudflare-workers-ai", "CLOUDFLARE_API_KEY" },            .{ "cloudflare-ai-gateway", "CLOUDFLARE_API_KEY" },            .{ "xiaomi", "XIAOMI_API_KEY" },                         .{ "xiaomi-token-plan-cn", "XIAOMI_TOKEN_PLAN_CN_API_KEY" },
    .{ "xiaomi-token-plan-ams", "XIAOMI_TOKEN_PLAN_AMS_API_KEY" }, .{ "xiaomi-token-plan-sgp", "XIAOMI_TOKEN_PLAN_SGP_API_KEY" },
};
const constants = .{ "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_FEDERATION_RULE_ID", "ANTHROPIC_ORGANIZATION_ID", "ANTHROPIC_SERVICE_ACCOUNT_ID", "ANTHROPIC_IDENTITY_TOKEN_FILE", "ANTHROPIC_WORKSPACE_ID" };
const Method = enum { getProviderEnvValue, findEnvKeys, getEnvApiKey };
pub fn create(engine: *em.Engine, dependencies: NodeDependencies) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "procEnvCache", c.pi_js_null());
    try scope.put(owner, "adcExists", c.pi_js_null());
    try scope.put(owner, "existsSync", dependencies.exists_sync orelse c.pi_js_undefined());
    try scope.put(owner, "homedir", dependencies.homedir orelse c.pi_js_undefined());
    try scope.put(owner, "join", dependencies.join orelse c.pi_js_undefined());
    const map = try scope.object();
    inline for (env_map) |pair| try scope.put(map, pair[0], try scope.text(pair[1]));
    try scope.put(owner, "map", map);
    const exports = try scope.object();
    inline for (constants) |constant| try scope.put(exports, constant ++ "_ENV", try scope.text(constant));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return operation(host, roots[0], method, argument(args, 0), argument(args, 1));
            }
        };
        try scope.put(exports, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, 2, Adapter.call, &.{owner})));
    }
    return c.JS_DupValue(engine.context, exports);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn optional(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, name);
}
fn equal(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn key(scope: *Scope, value: c.JSValue, name: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, value, name));
}
fn at(scope: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, index)));
}
fn isNode(scope: *Scope) !bool {
    const process = try scope.global("process");
    if (c.JS_IsUndefined(process)) return false;
    const versions = try scope.get(process, "versions");
    return scope.truthy(try optional(scope, versions, "node")) or scope.truthy(try optional(scope, versions, "bun"));
}
fn providerEnv(scope: *Scope, owner: c.JSValue, name: c.JSValue, env: c.JSValue) !c.JSValue {
    const scoped = if (temp.nullish(env)) c.pi_js_undefined() else try key(scope, env, name);
    if (scope.truthy(scoped)) return scoped;
    const process = try scope.global("process");
    const inherited = if (c.JS_IsUndefined(process)) c.pi_js_undefined() else try key(scope, try scope.get(process, "env"), name);
    if (scope.truthy(inherited)) return inherited;
    const fallback = try bunEnv(scope, owner, name);
    return if (scope.truthy(fallback)) fallback else c.pi_js_undefined();
}
fn bunEnv(scope: *Scope, owner: c.JSValue, name: c.JSValue) !c.JSValue {
    const process = try scope.global("process");
    if (c.JS_IsUndefined(process) or !scope.truthy(try optional(scope, try scope.get(process, "versions"), "bun"))) return c.pi_js_undefined();
    const keys = try scope.invoke(try scope.global("Object"), "keys", &.{try scope.get(process, "env")});
    if (try scope.positive(try scope.get(keys, "length"))) return c.pi_js_undefined();
    var cache = try scope.get(owner, "procEnvCache");
    if (c.JS_IsNull(cache)) {
        cache = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
        try scope.set(owner, "procEnvCache", cache);
        parseBunEnv(scope, cache) catch |err| {
            if (err == error.OutOfMemory) return err;
            // Original catch suppresses require/filesystem/parse errors.
            if (scope.engine.captured_exception) |value| {
                scope.engine.freeValue(value);
                scope.engine.captured_exception = null;
            }
        };
    }
    return scope.invoke(cache, "get", &.{name});
}
fn parseBunEnv(scope: *Scope, cache: c.JSValue) !void {
    const fs = try scope.call(try scope.global("require"), c.pi_js_undefined(), &.{try scope.text("node:fs")});
    const data = try scope.call(try scope.get(fs, "readFileSync"), c.pi_js_undefined(), &.{ try scope.text("/proc/self/environ"), try scope.text("utf-8") });
    const entries = try scope.invoke(data, "split", &.{try scope.text("\x00")});
    var iterator = try js.Iterator.init(scope.engine, entries, try scope.get(try scope.global("Symbol"), "iterator"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        _ = try row.own(entry);
        const index = try row.invoke(entry, "indexOf", &.{try row.text("=")});
        if (try row.positive(index)) {
            const after = try row.own(try row.engine.checked(c.JS_PiBinaryOperator(row.engine.context, 0, index, c.JS_NewInt32(row.engine.context, 1))));
            _ = try row.invoke(cache, "set", &.{ try row.invoke(entry, "slice", &.{ c.JS_NewInt32(row.engine.context, 0), index }), try row.invoke(entry, "slice", &.{after}) });
        }
    }
}
fn vars(scope: *Scope, owner: c.JSValue, provider: c.JSValue) !c.JSValue {
    const result = try scope.array();
    if (try equal(scope, provider, "github-copilot")) {
        try scope.index(result, 0, try scope.text("COPILOT_GITHUB_TOKEN"));
        return result;
    }
    if (try equal(scope, provider, "anthropic")) {
        inline for (.{ "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY" }, 0..) |name, i| try scope.index(result, i, try scope.text(name));
        return result;
    }
    const value = try key(scope, try scope.get(owner, "map"), provider);
    if (!scope.truthy(value)) return c.pi_js_undefined();
    try scope.index(result, 0, value);
    return result;
}
fn foundKeys(scope: *Scope, owner: c.JSValue, provider: c.JSValue, env: c.JSValue) !c.JSValue {
    const names = try vars(scope, owner, provider);
    if (!scope.truthy(names)) return c.pi_js_undefined();
    const filter = try scope.get(names, "filter");
    var roots = [_]c.JSValue{ owner, env };
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, envPredicate, "", 1, 0, roots.len, &roots)));
    const found = try scope.call(filter, names, &.{callback});
    return if (try scope.positive(try scope.get(found, "length"))) found else c.pi_js_undefined();
}
fn envPredicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = providerEnv(&scope, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), roots[1]) catch |err| return @import("native_sdk.zig").fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(scope.truthy(value)));
}
fn notBearer(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const excluded = scope.text("ANTHROPIC_AUTH_TOKEN") catch |err| return @import("native_sdk.zig").fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(!scope.equal(if (argc > 0) argv[0] else c.pi_js_undefined(), excluded)));
}
fn envName(scope: *Scope, owner: c.JSValue, env: c.JSValue, name: []const u8) !c.JSValue {
    return providerEnv(scope, owner, try scope.text(name), env);
}
fn adc(scope: *Scope, owner: c.JSValue, env: c.JSValue) !bool {
    const path = try optional(scope, env, "GOOGLE_APPLICATION_CREDENTIALS");
    const exists = try scope.get(owner, "existsSync");
    if (scope.truthy(path)) return scope.truthy(exists) and scope.truthy(try scope.call(exists, c.pi_js_undefined(), &.{path}));
    var cached = try scope.get(owner, "adcExists");
    if (c.JS_IsNull(cached)) {
        const home = try scope.get(owner, "homedir");
        const join = try scope.get(owner, "join");
        if (!scope.truthy(exists) or !scope.truthy(home) or !scope.truthy(join)) {
            if (!try isNode(scope)) try scope.set(owner, "adcExists", c.pi_js_bool(scope.engine.context, 0));
            return false;
        }
        const configured = try envName(scope, owner, env, "GOOGLE_APPLICATION_CREDENTIALS");
        const location = if (scope.truthy(configured)) configured else try scope.call(join, c.pi_js_undefined(), &.{ try scope.call(home, c.pi_js_undefined(), &.{}), try scope.text(".config"), try scope.text("gcloud"), try scope.text("application_default_credentials.json") });
        cached = try scope.call(exists, c.pi_js_undefined(), &.{location});
        try scope.set(owner, "adcExists", cached);
    }
    return scope.truthy(cached);
}
fn operation(engine: *em.Engine, owner: c.JSValue, method: Method, provider: c.JSValue, env: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .getProviderEnvValue) return c.JS_DupValue(engine.context, try providerEnv(&scope, owner, provider, env));
    const found = try foundKeys(&scope, owner, provider, env);
    if (method == .findEnvKeys) return c.JS_DupValue(engine.context, found);
    const first = if (temp.nullish(found)) c.pi_js_undefined() else try at(&scope, found, 0);
    if (scope.truthy(first)) {
        var chosen = first;
        if (try equal(&scope, provider, "anthropic")) {
            const find = try scope.get(found, "find");
            const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, notBearer, "", 1)));
            chosen = try scope.call(find, found, &.{callback});
        }
        if (scope.truthy(chosen)) return c.JS_DupValue(engine.context, try providerEnv(&scope, owner, chosen, env));
    }
    if (try equal(&scope, provider, "google-vertex")) {
        const credentials = try adc(&scope, owner, env);
        const project = scope.truthy(try envName(&scope, owner, env, "GOOGLE_CLOUD_PROJECT")) or scope.truthy(try envName(&scope, owner, env, "GCLOUD_PROJECT"));
        const location = scope.truthy(try envName(&scope, owner, env, "GOOGLE_CLOUD_LOCATION"));
        if (credentials and project and location) return @import("native_sdk.zig").text(engine, "<authenticated>");
    }
    if (try equal(&scope, provider, "amazon-bedrock")) {
        const configured = scope.truthy(try envName(&scope, owner, env, "AWS_PROFILE")) or
            (scope.truthy(try envName(&scope, owner, env, "AWS_ACCESS_KEY_ID")) and scope.truthy(try envName(&scope, owner, env, "AWS_SECRET_ACCESS_KEY"))) or
            scope.truthy(try envName(&scope, owner, env, "AWS_BEARER_TOKEN_BEDROCK")) or scope.truthy(try envName(&scope, owner, env, "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")) or
            scope.truthy(try envName(&scope, owner, env, "AWS_CONTAINER_CREDENTIALS_FULL_URI")) or scope.truthy(try envName(&scope, owner, env, "AWS_WEB_IDENTITY_TOKEN_FILE"));
        if (configured) return @import("native_sdk.zig").text(engine, "<authenticated>");
    }
    return c.pi_js_undefined();
}

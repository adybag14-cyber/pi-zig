//! Accessed pinned OpenAI6.40 constructor/default option behavior for Pi's
//! createClient call. This private record is not a substitute public SDK class.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const headers = @import("native_ai_openai_sdk_headers.zig");
const logging = @import("native_ai_openai_client_log.zig");
pub const Provided = struct { api_key: c.JSValue, base_url: c.JSValue, fetch: c.JSValue, default_headers: c.JSValue };
pub fn initialize(engine: *v.em.Engine) !void {
    try logging.initialize(engine);
}
/// Exact primary readEnv optional chaining and truthiness, including raw
/// process/env/value getters and user-provided trim/get callbacks.
fn readEnv(scope: *Scope, name: []const u8) !c.JSValue {
    const first_process = try scope.get(try scope.global("globalThis"), "process");
    if (!c.JS_IsUndefined(first_process)) {
        const process = try scope.get(try scope.global("globalThis"), "process");
        const env = try scope.get(process, "env");
        const value = if (v.nullish(env)) c.pi_js_undefined() else try scope.own(try v.js.getKey(scope.engine, env, try scope.text(name)));
        const trimmed = if (v.nullish(value)) c.pi_js_undefined() else try scope.invoke(value, "trim", &.{});
        return if (scope.truthy(trimmed)) trimmed else c.pi_js_undefined();
    }
    const first_deno = try scope.get(try scope.global("globalThis"), "Deno");
    if (!c.JS_IsUndefined(first_deno)) {
        const deno = try scope.get(try scope.global("globalThis"), "Deno");
        const env = try scope.get(deno, "env");
        if (v.nullish(env)) return c.pi_js_undefined();
        const get = try scope.get(env, "get");
        const value = if (v.nullish(get)) c.pi_js_undefined() else try scope.call(get, env, &.{try scope.text(name)});
        const trimmed = if (v.nullish(value)) c.pi_js_undefined() else try scope.invoke(value, "trim", &.{});
        return if (scope.truthy(trimmed)) trimmed else c.pi_js_undefined();
    }
    return c.pi_js_undefined();
}
fn optionalEnv(scope: *Scope, name: []const u8) !c.JSValue {
    const value = try readEnv(scope, name);
    return if (v.nullish(value)) c.pi_js_null() else value;
}
fn defaultFetch(scope: *Scope) !c.JSValue {
    if (!c.JS_IsUndefined(try scope.global("fetch"))) return scope.global("fetch");
    return v.errorText(scope, try scope.text("`fetch` is not defined as a global; Either pass `fetch` to the client, `new OpenAI({ fetch })` or polyfill the global, `globalThis.fetch = fetch`"));
}
pub fn capture(engine: *v.em.Engine, provided: Provided) !c.JSValue {
    const generation = engine.native_allocation_generation;
    return captureValues(engine, provided) catch |err| return engine.nativeAllocationError(err, generation);
}
fn captureValues(engine: *v.em.Engine, provided: Provided) !c.JSValue {
    try initialize(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Pi supplies only these constructor options. Unspecified SDK defaults
    // evaluate in the actual destructuring order before the constructor body.
    const base = if (c.JS_IsUndefined(provided.base_url)) try readEnv(&scope, "OPENAI_BASE_URL") else provided.base_url;
    const api_key = if (c.JS_IsUndefined(provided.api_key)) try optionalEnv(&scope, "OPENAI_API_KEY") else provided.api_key;
    const admin = try optionalEnv(&scope, "OPENAI_ADMIN_KEY");
    const organization = try optionalEnv(&scope, "OPENAI_ORG_ID");
    const project = try optionalEnv(&scope, "OPENAI_PROJECT_ID");
    const webhook = try optionalEnv(&scope, "OPENAI_WEBHOOK_SECRET");
    if (!scope.truthy(api_key) and !scope.truthy(admin)) return v.errorText(&scope, try scope.text("Missing credentials. Please pass an `apiKey`, `workloadIdentity`, `adminAPIKey`, or set the `OPENAI_API_KEY` or `OPENAI_ADMIN_KEY` environment variable."));
    const result = try scope.object();
    try scope.put(result, "baseURL", if (scope.truthy(base)) base else try scope.text("https://api.openai.com/v1"));
    try scope.put(result, "logger", try scope.global("console"));
    try scope.put(result, "logLevel", try scope.text("warn"));
    const configured_log = try logging.parse(&scope, try readEnv(&scope, "OPENAI_LOG"), "process.env['OPENAI_LOG']", result);
    if (!v.nullish(configured_log)) try scope.put(result, "logLevel", configured_log);
    try scope.put(result, "fetch", if (v.nullish(provided.fetch)) try defaultFetch(&scope) else provided.fetch);
    const custom = try readEnv(&scope, "OPENAI_CUSTOM_HEADERS");
    if (scope.truthy(custom)) {
        const parsed = try scope.object();
        var lines = try v.iterator(&scope, try scope.invoke(custom, "split", &.{try scope.text("\n")}));
        defer lines.deinit();
        errdefer lines.closePreserving();
        while (try lines.next()) |line| {
            defer engine.freeValue(line);
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const colon = try row.invoke(line, "indexOf", &.{try row.text(":")});
            if (try @import("native_image_arithmetic.zig").compare(engine, .greater_equal, colon, c.JS_NewInt32(engine.context, 0))) {
                const name = try row.invoke(try row.invoke(line, "substring", &.{ c.JS_NewInt32(engine.context, 0), colon }), "trim", &.{});
                const next = try row.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, colon, c.JS_NewInt32(engine.context, 1))));
                const value = try row.invoke(try row.invoke(line, "substring", &.{next}), "trim", &.{});
                try v.js.setKey(engine, parsed, name, value);
            }
        }
        const built = try headers.build(engine, &.{ parsed, provided.default_headers });
        defer engine.freeValue(built.values);
        defer engine.freeValue(built.nulls);
        try scope.put(result, "defaultHeaders", built.values);
        try scope.put(result, "headerNulls", built.nulls);
        try scope.put(result, "headersPrepared", c.JS_NewBool(engine.context, true));
    } else {
        try scope.put(result, "defaultHeaders", provided.default_headers);
        try scope.put(result, "headerNulls", c.pi_js_undefined());
        try scope.put(result, "headersPrepared", c.JS_NewBool(engine.context, false));
    }
    // The SDK commits these fields only after the optional constructor merge.
    try scope.put(result, "apiKey", if (c.JS_IsString(api_key)) api_key else c.pi_js_null());
    try scope.put(result, "adminAPIKey", admin);
    try scope.put(result, "organization", organization);
    try scope.put(result, "project", project);
    try scope.put(result, "webhookSecret", webhook);
    return c.JS_DupValue(engine.context, result);
}

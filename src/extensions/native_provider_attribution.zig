//! Original provider attribution and telemetry decisions over live guest values.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn create(engine: *em.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "mergeProviderAttributionHeaders", 3, call, &.{});
}
pub fn createTelemetry(engine: *em.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "isInstallTelemetryEnabled", 1, telemetryCall, &.{});
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn telemetryCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try telemetry(&scope, arg(args, 0), arg(args, 1)));
}
fn telemetry(scope: *Scope, settings: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const value = if (c.JS_IsUndefined(supplied)) try scope.get(try scope.get(try scope.global("process"), "env"), "PI_TELEMETRY") else supplied;
    if (c.JS_IsUndefined(value)) return scope.invoke(settings, "getEnableInstallTelemetry", &.{});
    const enabled = scope.truthy(value) and (try is(scope, value, "1") or
        try is(scope, try scope.invoke(value, "toLowerCase", &.{}), "true") or
        try is(scope, try scope.invoke(value, "toLowerCase", &.{}), "yes"));
    return c.pi_js_bool(scope.engine.context, @intFromBool(enabled));
}
fn matchesHost(scope: *Scope, base_url: c.JSValue, hostname: []const u8) !bool {
    const generation = scope.engine.native_allocation_generation;
    return parsedHost(scope, base_url, hostname) catch |err| {
        const failure = scope.engine.nativeAllocationError(err, generation);
        if (failure != error.JavaScriptException) return failure;
        if (scope.engine.captured_exception) |exception| scope.engine.freeValue(exception);
        scope.engine.captured_exception = null;
        return false;
    };
}
fn parsedHost(scope: *Scope, base_url: c.JSValue, hostname: []const u8) !bool {
    const url = try scope.own(try js.builtin(scope.engine, "URL", &.{base_url}));
    return is(scope, try scope.get(url, "hostname"), hostname);
}
fn defaultHeaders(scope: *Scope, model: c.JSValue, settings: c.JSValue) !c.JSValue {
    if (!scope.truthy(try telemetry(scope, settings, c.pi_js_undefined()))) return c.pi_js_undefined();
    if (try is(scope, try scope.get(model, "provider"), "openrouter") or
        scope.truthy(try scope.invoke(try scope.get(model, "baseUrl"), "includes", &.{try scope.text("openrouter.ai")})))
    {
        const headers = try scope.object();
        try scope.put(headers, "HTTP-Referer", try scope.text("https://pi.dev"));
        try scope.put(headers, "X-OpenRouter-Title", try scope.text("pi"));
        try scope.put(headers, "X-OpenRouter-Categories", try scope.text("cli-agent"));
        return headers;
    }
    if (try is(scope, try scope.get(model, "provider"), "nvidia") or
        try matchesHost(scope, try scope.get(model, "baseUrl"), "integrate.api.nvidia.com"))
    {
        const headers = try scope.object();
        try scope.put(headers, "X-BILLING-INVOKE-ORIGIN", try scope.text("Pi"));
        return headers;
    }
    if (try is(scope, try scope.get(model, "provider"), "cloudflare-workers-ai") or
        try is(scope, try scope.get(model, "provider"), "cloudflare-ai-gateway") or
        try matchesHost(scope, try scope.get(model, "baseUrl"), "api.cloudflare.com") or
        try matchesHost(scope, try scope.get(model, "baseUrl"), "gateway.ai.cloudflare.com"))
    {
        const headers = try scope.object();
        try scope.put(headers, "User-Agent", try scope.text("pi-coding-agent"));
        return headers;
    }
    return c.pi_js_undefined();
}
fn sessionHeaders(scope: *Scope, model: c.JSValue, session_id: c.JSValue) !c.JSValue {
    if (!scope.truthy(session_id)) return c.pi_js_undefined();
    if (!try is(scope, try scope.get(model, "provider"), "opencode") and
        !try is(scope, try scope.get(model, "provider"), "opencode-go") and
        !try matchesHost(scope, try scope.get(model, "baseUrl"), "opencode.ai")) return c.pi_js_undefined();
    const headers = try scope.object();
    try scope.put(headers, "x-opencode-session", session_id);
    try scope.put(headers, "x-opencode-client", try scope.text("pi"));
    return headers;
}
fn call(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return merge(engine, arg(args, 0), arg(args, 1), arg(args, 2), if (args.len > 3) args[3..] else &.{});
}
pub fn merge(engine: *em.Engine, model: c.JSValue, settings: c.JSValue, session_id: c.JSValue, sources: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try js.spreadInto(engine, result, try sessionHeaders(&scope, model, session_id));
    try js.spreadInto(engine, result, try defaultHeaders(&scope, model, settings));
    const rest = try scope.array();
    for (sources, 0..) |source, index| try scope.index(rest, @intCast(index), source);
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, rest, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |headers| {
        defer engine.freeValue(headers);
        if (scope.truthy(headers)) _ = try scope.invoke(try scope.global("Object"), "assign", &.{ result, headers });
    }
    const keys = try scope.invoke(try scope.global("Object"), "keys", &.{result});
    return if (try scope.positive(try scope.get(keys, "length"))) c.JS_DupValue(engine.context, result) else c.pi_js_undefined();
}

//! Actual Source prompt auth preflight before model events/messages.
//! Each model/provider lookup stays fresh, and checkAuth awaits intrinsically.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn begin(engine: *em.Engine, session: c.JSValue, runtime: c.JSValue) !?c.JSValue {
    const model = try sdk.get(engine, session, "model");
    defer engine.freeValue(model);
    if (c.JS_ToBool(engine.context, model) != 1) {
        try noModel(engine);
        return error.JavaScriptException;
    }
    const method = try sdk.get(engine, runtime, "hasConfiguredAuth");
    defer engine.freeValue(method);
    const provider = try currentProvider(engine, session);
    defer engine.freeValue(provider);
    const configured = try js.call(engine, method, runtime, &.{provider});
    defer engine.freeValue(configured);
    if (c.JS_ToBool(engine.context, configured) == 1) return null;
    const checker = try sdk.get(engine, runtime, "checkAuth");
    defer engine.freeValue(checker);
    const actual_provider = try currentProvider(engine, session);
    defer engine.freeValue(actual_provider);
    const pending = try js.call(engine, checker, runtime, &.{actual_provider});
    defer engine.freeValue(pending);
    return try engine.checked(c.JS_PiPromiseResolve(engine.context, pending));
}
pub fn finish(engine: *em.Engine, session: c.JSValue, runtime: c.JSValue, status: c.JSValue) !void {
    if (!c.JS_IsUndefined(status)) return; // Source uses !== undefined, including null/false/0.
    const oauth = try sdk.get(engine, runtime, "isUsingOAuth");
    defer engine.freeValue(oauth);
    const provider = try currentProvider(engine, session);
    defer engine.freeValue(provider);
    const using_oauth = try js.call(engine, oauth, runtime, &.{provider});
    defer engine.freeValue(using_oauth);
    if (c.JS_ToBool(engine.context, using_oauth) == 1) return oauthError(engine, session);
    return noKey(engine, session);
}
fn currentProvider(engine: *em.Engine, session: c.JSValue) !c.JSValue {
    const model = try sdk.get(engine, session, "model");
    defer engine.freeValue(model);
    return sdk.get(engine, model, "provider");
}
fn raise(scope: *Scope, constructor: c.JSValue, message: c.JSValue) !void {
    var arguments = [_]c.JSValue{message};
    const error_value = try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, arguments.len, &arguments));
    _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, error_value));
}
pub fn loginHelp(scope: *Scope) !c.JSValue {
    const lines = try scope.array();
    try scope.index(lines, 0, try scope.text("Use /login to log into a provider via OAuth or API key. See:"));
    const providers = try scope.own(try @import("native_sdk_prompt_render.zig").resolvePackagePath(scope.engine, "docs/providers.md"));
    try scope.index(lines, 1, try scope.concat(try scope.text("  "), try scope.stringify(providers)));
    const models = try scope.own(try @import("native_sdk_prompt_render.zig").resolvePackagePath(scope.engine, "docs/models.md"));
    try scope.index(lines, 2, try scope.concat(try scope.text("  "), try scope.stringify(models)));
    return scope.invoke(lines, "join", &.{try scope.text("\n")});
}
fn noModel(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.global("Error");
    const help = try scope.stringify(try loginHelp(&scope));
    const message = try scope.concat(try scope.concat(try scope.text("No model selected.\n\n"), help), try scope.text("\n\nThen use /model to select a model."));
    try raise(&scope, constructor, message);
}
fn noKey(engine: *em.Engine, session: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.global("Error");
    const provider = try scope.own(try currentProvider(engine, session));
    const unknown = try scope.text("unknown");
    const display = if (scope.equal(provider, unknown)) try scope.text("the selected model") else provider;
    const prefix = try scope.concat(try scope.concat(try scope.text("No API key found for "), try scope.stringify(display)), try scope.text(".\n\n"));
    const message = try scope.concat(prefix, try scope.stringify(try loginHelp(&scope)));
    try raise(&scope, constructor, message);
}
fn oauthError(engine: *em.Engine, session: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.global("Error");
    const provider = try scope.own(try currentProvider(engine, session));
    var message = try scope.concat(try scope.concat(try scope.text("Authentication failed for \""), try scope.stringify(provider)), try scope.text("\". Credentials may have expired or network is unavailable. Run '/login "));
    const next_provider = try scope.own(try currentProvider(engine, session));
    message = try scope.concat(try scope.concat(message, try scope.stringify(next_provider)), try scope.text("' to re-authenticate."));
    try raise(&scope, constructor, message);
}

// Ordinary session prompt preflight reads _modelRuntime afresh at every
// Source access; a caller may replace it from a preceding getter or callback.
pub fn beginLive(engine: *em.Engine, session: c.JSValue) !?c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(session, "model"))) {
        try noModel(engine);
        return error.JavaScriptException;
    }
    const runtime = try scope.get(session, "_modelRuntime");
    const configured = try scope.get(runtime, "hasConfiguredAuth");
    const provider = try scope.own(try currentProvider(engine, session));
    if (scope.truthy(try scope.call(configured, runtime, &.{provider}))) return null;
    const actual_runtime = try scope.get(session, "_modelRuntime");
    const check = try scope.get(actual_runtime, "checkAuth");
    const actual_provider = try scope.own(try currentProvider(engine, session));
    const pending = try scope.call(check, actual_runtime, &.{actual_provider});
    return try engine.checked(c.JS_PiPromiseResolve(engine.context, pending));
}
pub fn finishLive(engine: *em.Engine, session: c.JSValue, status: c.JSValue) !void {
    if (!c.JS_IsUndefined(status)) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(session, "_modelRuntime");
    const oauth = try scope.get(runtime, "isUsingOAuth");
    const provider = try scope.own(try currentProvider(engine, session));
    if (scope.truthy(try scope.call(oauth, runtime, &.{provider}))) return oauthError(engine, session);
    return noKey(engine, session);
}

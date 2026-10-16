//! Native namespace bodies of core/provider-composer.ts at 4954d760.
//! No SDK.State, builtin catalogue, blocking await or evaluated host source.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const nf = @import("native_node_function.zig");
const async_api = @import("native_agent_async.zig");
const sc = @import("native_sdk_prompt_scope.zig");
const Scope = sc.Scope;
const c = em.c;
pub const Imports = struct {
    isModelType: c.JSValue,
    lazyStream: c.JSValue,
    getApiProvider: c.JSValue,
    imageErrorResult: c.JSValue,
    classifierErrorResult: c.JSValue,
    configValues: c.JSValue,
};
fn u() c.JSValue {
    return c.pi_js_undefined();
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (i < args.len) args[i] else u();
}
fn get(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (sc.nullish(object)) u() else s.get(object, name);
}
fn key(s: *Scope, object: c.JSValue, name: c.JSValue) !c.JSValue {
    return if (sc.nullish(object)) u() else s.own(try js.getKey(s.engine, object, name));
}
fn at(s: *Scope, object: c.JSValue, i: usize) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, object, @intCast(i))));
}
fn len(s: *Scope, array: c.JSValue) !u32 {
    var n: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &n, try get(s, array, "length")) < 0) return js.capture(s.engine);
    return n;
}
fn fallback(a: c.JSValue, b: c.JSValue) c.JSValue {
    return if (sc.nullish(a)) b else a;
}
const Field = struct { object: c.JSValue, name: [*:0]const u8 };
fn coalesce(s: *Scope, fields: []const Field, otherwise: c.JSValue) !c.JSValue {
    for (fields) |field| {
        const value = try get(s, field.object, field.name);
        if (!sc.nullish(value)) return value;
    }
    return otherwise;
}
fn merge(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const object = try s.object();
    for (values) |v| try js.spreadInto(s.engine, object, v);
    return object;
}
fn objectType(s: *Scope, value: c.JSValue) bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(s.engine.context, value);
}
fn push(s: *Scope, array: c.JSValue, value: c.JSValue) !void {
    _ = try s.invoke(array, "push", &.{value});
}
fn entries(s: *Scope, object: c.JSValue, method: [*:0]const u8) !c.JSValue {
    return s.own(try js.objectMethod(s.engine, method, object));
}
fn isChat(s: *Scope, imports: c.JSValue, row: c.JSValue) !bool {
    return s.truthy(try s.call(try s.get(imports, "isModelType"), u(), &.{ row, try s.text("chat") }));
}
fn errorMessage(s: *Scope, text: c.JSValue) anyerror {
    const exception = js.builtin(s.engine, "Error", &.{text}) catch |err| return err;
    _ = s.engine.checked(c.JS_Throw(s.engine.context, exception)) catch |err| return err;
    unreachable;
}
fn message(s: *Scope, segments: []const c.JSValue) !c.JSValue {
    var result = try s.text("");
    for (segments) |v| result = try s.concat(result, v);
    return result;
}
fn providerError(s: *Scope, id: c.JSValue, suffix: []const u8) anyerror {
    const msg = message(s, &.{ s.text("Provider ") catch |e| return e, id, s.text(suffix) catch |e| return e }) catch |e| return e;
    return errorMessage(s, msg);
}
fn modelError(s: *Scope, id: c.JSValue, definition: c.JSValue, suffix: []const u8) anyerror {
    const msg = message(s, &.{ s.text("Provider ") catch |e| return e, id, s.text(", model ") catch |e| return e, get(s, definition, "id") catch |e| return e, s.text(suffix) catch |e| return e }) catch |e| return e;
    return errorMessage(s, msg);
}
fn allProviderModels(s: *Scope, base: c.JSValue) !c.JSValue {
    if (!s.truthy(base)) return s.array();
    const getter = try s.get(base, "getAllModels");
    const all = if (sc.nullish(getter)) u() else try s.call(getter, base, &.{});
    return if (sc.nullish(all)) s.invoke(base, "getModels", &.{}) else all;
}
fn mergeCompat(s: *Scope, base: c.JSValue, override: c.JSValue) !c.JSValue {
    if (!s.truthy(override)) return base;
    const merged = try merge(s, &.{ base, override });
    inline for (.{ "openRouterRouting", "vercelGatewayRouting", "chatTemplateKwargs", "chatTemplateArgs" }) |field| {
        const a = try get(s, base, field);
        const b = try s.get(override, field);
        if (objectType(s, a) or objectType(s, b)) try s.put(merged, field, try merge(s, &.{ a, b }));
    }
    return merged;
}
fn mergeInputLimits(s: *Scope, base: c.JSValue, override: c.JSValue) !c.JSValue {
    if (!s.truthy(override)) return base;
    const out = try merge(s, &.{ base, override });
    const old = try get(s, base, "images");
    const changed = try s.get(override, "images");
    var images = old;
    if (s.truthy(changed)) {
        images = try merge(s, &.{ old, changed });
        const resize = try s.get(changed, "resize");
        try s.put(images, "resize", if (s.truthy(resize)) try merge(s, &.{ try get(s, old, "resize"), resize }) else try get(s, old, "resize"));
    }
    try s.put(out, "images", images);
    return out;
}
fn mergeSampling(s: *Scope, base: c.JSValue, override: c.JSValue) !c.JSValue {
    if (!s.truthy(override)) return base;
    const out = try merge(s, &.{base});
    inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }) |level| {
        const changed = try s.get(override, level);
        if (s.truthy(changed)) try s.put(out, level, try merge(s, &.{ try get(s, base, level), changed }));
    }
    return out;
}
fn applyOverride(s: *Scope, model: c.JSValue, override: c.JSValue) !c.JSValue {
    const out = try merge(s, &.{model});
    inline for (.{ "name", "reasoning" }) |field| try s.put(out, field, try coalesce(s, &.{ .{ .object = override, .name = field }, .{ .object = model, .name = field } }, u()));
    const thinking = try s.get(override, "thinkingLevelMap");
    try s.put(out, "thinkingLevelMap", if (s.truthy(thinking)) try merge(s, &.{ try s.get(model, "thinkingLevelMap"), try s.get(override, "thinkingLevelMap") }) else try s.get(model, "thinkingLevelMap"));
    try s.put(out, "input", try coalesce(s, &.{ .{ .object = override, .name = "input" }, .{ .object = model, .name = "input" } }, u()));
    try s.put(out, "inputLimits", try mergeInputLimits(s, try s.get(model, "inputLimits"), try s.get(override, "inputLimits")));
    const cost = try s.get(override, "cost");
    if (s.truthy(cost)) {
        const merged = try s.object();
        inline for (.{ "input", "output", "cacheRead", "cacheWrite", "tiers" }) |field| {
            const changed = try s.get(try s.get(override, "cost"), field);
            try s.put(merged, field, if (sc.nullish(changed)) try s.get(try s.get(model, "cost"), field) else changed);
        }
        try s.put(out, "cost", merged);
    } else try s.put(out, "cost", try s.get(model, "cost"));
    const cache = try s.get(override, "promptCache");
    try s.put(out, "promptCache", if (s.truthy(cache)) try merge(s, &.{ try s.get(model, "promptCache"), try s.get(override, "promptCache") }) else try s.get(model, "promptCache"));
    inline for (.{ "contextWindow", "maxTokens" }) |field| try s.put(out, field, try coalesce(s, &.{ .{ .object = override, .name = field }, .{ .object = model, .name = field } }, u()));
    const sampling = try s.get(override, "samplingParams");
    try s.put(out, "samplingParams", if (s.truthy(sampling)) try merge(s, &.{ try s.get(model, "samplingParams"), try s.get(override, "samplingParams") }) else try s.get(model, "samplingParams"));
    try s.put(out, "samplingParamsByThinkingLevel", try mergeSampling(s, try s.get(model, "samplingParamsByThinkingLevel"), try s.get(override, "samplingParamsByThinkingLevel")));
    try s.put(out, "compat", try mergeCompat(s, try s.get(model, "compat"), try s.get(override, "compat")));
    return out;
}
fn modelType(s: *Scope, row: c.JSValue) !c.JSValue {
    return fallback(try s.get(row, "type"), try s.text("chat"));
}
fn findDefaults(s: *Scope, imports: c.JSValue, models: c.JSValue, definition: c.JSValue, api: c.JSValue, extension: bool) !c.JSValue {
    const kind = if (extension) try modelType(s, definition) else try s.text("chat");
    const id = try s.get(definition, "id");
    var first_row = u();
    var api_row = u();
    var openai = u();
    for (0..try len(s, models)) |i| {
        const row = try at(s, models, i);
        const matches = s.truthy(try s.call(try s.get(imports, "isModelType"), u(), &.{ row, kind }));
        if (!matches) continue;
        if (sc.nullish(first_row)) first_row = row;
        if (s.equal(try s.get(row, "id"), id)) return row;
        const row_api = try s.get(row, "api");
        if (sc.nullish(api_row) and s.truthy(api) and s.equal(row_api, api)) api_row = row;
        if (sc.nullish(openai) and s.equal(kind, try s.text("chat")) and s.equal(row_api, try s.text("openai-completions"))) openai = row;
    }
    return fallback(api_row, fallback(openai, first_row));
}
fn modelFromJson(s: *Scope, id: c.JSValue, definition: c.JSValue, config: c.JSValue, defaults: c.JSValue) !c.JSValue {
    const api = try coalesce(s, &.{ .{ .object = definition, .name = "api" }, .{ .object = config, .name = "api" }, .{ .object = defaults, .name = "api" } }, u());
    if (!s.truthy(api)) return modelError(s, id, definition, ": no \"api\" specified. Set at provider or model level.");
    const url = try coalesce(s, &.{ .{ .object = definition, .name = "baseUrl" }, .{ .object = config, .name = "baseUrl" }, .{ .object = defaults, .name = "baseUrl" } }, u());
    if (!s.truthy(url)) return providerError(s, id, ": \"baseUrl\" is required when defining custom models.");
    inline for (.{ "contextWindow", "maxTokens" }) |field| {
        const v = try s.get(definition, field);
        if (!c.JS_IsUndefined(v)) {
            const invalid = try s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 5, v, c.JS_NewInt32(s.engine.context, 0))));
            if (s.truthy(invalid)) return modelError(s, id, definition, ": invalid " ++ field);
        }
    }
    const out = try s.object();
    const model_id = try s.get(definition, "id");
    try s.put(out, "id", model_id);
    try s.put(out, "name", fallback(try s.get(definition, "name"), model_id));
    try s.put(out, "api", api);
    try s.put(out, "provider", id);
    try s.put(out, "baseUrl", url);
    try s.put(out, "reasoning", fallback(try s.get(definition, "reasoning"), c.pi_js_bool(s.engine.context, 0)));
    const input = try s.array();
    try push(s, input, try s.text("text"));
    try s.put(out, "input", fallback(try s.get(definition, "input"), input));
    const cost = try s.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite" }) |field| try s.put(cost, field, c.JS_NewInt32(s.engine.context, 0));
    try s.put(out, "cost", fallback(try s.get(definition, "cost"), cost));
    try s.put(out, "contextWindow", fallback(try s.get(definition, "contextWindow"), c.JS_NewInt32(s.engine.context, 128000)));
    try s.put(out, "maxTokens", fallback(try s.get(definition, "maxTokens"), c.JS_NewInt32(s.engine.context, 16384)));
    inline for (.{ "thinkingLevelMap", "inputLimits", "promptCache", "samplingParams", "samplingParamsByThinkingLevel" }) |field| try s.put(out, field, try s.get(definition, field));
    try s.put(out, "headers", u());
    try s.put(out, "compat", try mergeCompat(s, try s.get(config, "compat"), try s.get(definition, "compat")));
    return out;
}
fn extensionModel(s: *Scope, imports: c.JSValue, id: c.JSValue, models: c.JSValue, config: c.JSValue, definition: c.JSValue) !c.JSValue {
    const kind = try modelType(s, definition);
    const chat = s.equal(kind, try s.text("chat"));
    const defaults = try findDefaults(s, imports, models, definition, try s.get(definition, "api"), true);
    const api = try coalesce(s, &.{ .{ .object = definition, .name = "api" }, .{ .object = if (chat) config else u(), .name = "api" }, .{ .object = defaults, .name = "api" } }, u());
    if (!s.truthy(api)) return modelError(s, id, definition, if (chat) ": no \"api\" specified. Set it at model level or provider level." else ": no \"api\" specified. Set it at model level.");
    const url = try coalesce(s, &.{ .{ .object = definition, .name = "baseUrl" }, .{ .object = config, .name = "baseUrl" }, .{ .object = defaults, .name = "baseUrl" } }, u());
    if (!s.truthy(url)) return providerError(s, id, ": \"baseUrl\" is required when defining custom models.");
    const out = try merge(s, &.{definition});
    try s.put(out, "api", api);
    try s.put(out, "provider", id);
    try s.put(out, "baseUrl", url);
    try s.put(out, "headers", u());
    return out;
}
fn applyJson(s: *Scope, imports: c.JSValue, id: c.JSValue, base: c.JSValue, config: c.JSValue) !c.JSValue {
    const out = try s.array();
    if (!s.truthy(config)) {
        for (0..try len(s, base)) |i| try push(s, out, try at(s, base, i));
        return out;
    }
    const oauth = try s.get(config, "oauth");
    const url = try s.get(config, "baseUrl");
    if (s.truthy(oauth) and !s.truthy(url)) return providerError(s, id, ": \"baseUrl\" is required when \"oauth\" is set.");
    const overrides = try s.get(config, "modelOverrides");
    const has_overrides = s.truthy(overrides) and try len(s, try entries(s, overrides, "keys")) > 0;
    const definitions = try s.get(config, "models");
    var any = s.truthy(try get(s, definitions, "length")) or s.truthy(url) or has_overrides or !c.JS_IsUndefined(try s.get(config, "authHeader"));
    inline for (.{ "headers", "compat", "apiKey", "oauth" }) |field| any = any or s.truthy(try s.get(config, field));
    if (!any) return providerError(s, id, ": must specify \"baseUrl\", \"headers\", \"compat\", \"modelOverrides\", or \"models\".");
    for (0..try len(s, base)) |i| {
        const row = try at(s, base, i);
        const next = try merge(s, &.{row});
        try s.put(next, "baseUrl", if (s.equal(oauth, try s.text("radius"))) try s.get(row, "baseUrl") else fallback(url, try s.get(row, "baseUrl")));
        if (try isChat(s, imports, row)) try s.put(next, "compat", try mergeCompat(s, try s.get(row, "compat"), try s.get(config, "compat")));
        try push(s, out, next);
    }
    if (!sc.nullish(definitions)) for (0..try len(s, definitions)) |i| {
        const def = try at(s, definitions, i);
        var found: ?usize = null;
        for (0..try len(s, out)) |j| {
            const row = try at(s, out, j);
            if (try isChat(s, imports, row) and s.equal(try s.get(row, "id"), try s.get(def, "id"))) {
                found = j;
                break;
            }
        }
        const defaults = try findDefaults(s, imports, out, def, try coalesce(s, &.{ .{ .object = def, .name = "api" }, .{ .object = config, .name = "api" } }, u()), false);
        const row = try modelFromJson(s, id, def, config, defaults);
        if (found) |j| try s.index(out, @intCast(j), row) else try push(s, out, row);
    };
    return out;
}
fn applyExtension(s: *Scope, imports: c.JSValue, id: c.JSValue, models: c.JSValue, config: c.JSValue) !c.JSValue {
    const out = try s.array();
    const defs = try get(s, config, "models");
    const url = try get(s, config, "baseUrl");
    if (!s.truthy(config) or !s.truthy(defs)) {
        for (0..try len(s, models)) |i| {
            var row = try at(s, models, i);
            if (s.truthy(config) and s.truthy(url)) {
                row = try merge(s, &.{row});
                try s.put(row, "baseUrl", url);
            }
            try push(s, out, row);
        }
        return out;
    }
    for (0..try len(s, defs)) |i| try push(s, out, try extensionModel(s, imports, id, models, config, try at(s, defs, i)));
    return out;
}
fn configuredKey(s: *Scope, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    return coalesce(s, &.{ .{ .object = extension, .name = "apiKey" }, .{ .object = config, .name = "apiKey" } }, u());
}
fn configuredHeaders(s: *Scope, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    const a = try get(s, config, "headers");
    if (!s.truthy(a) and !s.truthy(try get(s, extension, "headers"))) return u();
    return merge(s, &.{ try get(s, config, "headers"), try get(s, extension, "headers") });
}
fn authHeader(s: *Scope, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    return coalesce(s, &.{ .{ .object = extension, .name = "authHeader" }, .{ .object = config, .name = "authHeader" } }, c.pi_js_bool(s.engine.context, 0));
}
fn configCall(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.invoke(try s.get(imports, "configValues"), name, args);
}
fn rawHeaders(s: *Scope, imports: c.JSValue, model: c.JSValue, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    const chat = try isChat(s, imports, model);
    const id = try s.get(model, "id");
    var definition = u();
    var ext_model = u();
    const defs = try get(s, config, "models");
    if (chat and !sc.nullish(defs)) for (0..try len(s, defs)) |i| {
        const row = try at(s, defs, i);
        if (s.equal(try s.get(row, "id"), id)) {
            definition = row;
            break;
        }
    };
    const ext = try get(s, extension, "models");
    if (!sc.nullish(ext)) for (0..try len(s, ext)) |i| {
        const row = try at(s, ext, i);
        if (s.equal(try modelType(s, row), try modelType(s, model)) and s.equal(try s.get(row, "id"), id)) {
            ext_model = row;
            break;
        }
    };
    const override = if (chat) try key(s, try get(s, config, "modelOverrides"), id) else u();
    const out = try merge(s, &.{ try get(s, override, "headers"), try get(s, definition, "headers"), try get(s, ext_model, "headers") });
    return if (try len(s, try entries(s, out, "keys")) > 0) out else u();
}
fn description(s: *Scope, model: c.JSValue) !c.JSValue {
    return message(s, &.{ try s.text("model \""), try s.get(model, "provider"), try s.text("/"), try s.get(model, "id"), try s.text("\"") });
}
fn withAuth(s: *Scope, auth: c.JSValue, headers: c.JSValue, flag: c.JSValue) !c.JSValue {
    const old = try s.get(auth, "headers");
    var merged = if (s.truthy(old) or s.truthy(headers)) try merge(s, &.{ old, headers }) else u();
    if (s.truthy(flag)) {
        const api_key = try s.get(auth, "apiKey");
        if (!s.truthy(api_key)) return errorMessage(s, try s.text("authHeader requires a resolved API key"));
        merged = try merge(s, &.{merged});
        try s.put(merged, "Authorization", try s.concat(try s.text("Bearer "), api_key));
    }
    const out = try merge(s, &.{auth});
    try s.put(out, "headers", merged);
    return out;
}
const Op = enum { compose, validate, headers, compat, status, all, chat, stream, simple, stream_body, refresh, update, filter, filter_all, fetch, cancel, images, classify, login, check, resolve, oauth_login, oauth_refresh, oauth_key, oauth_auth, notify_auth, notify_device, prompt_text, notify_progress, prompt_manual, prompt_select };
fn function(s: *Scope, name: [*:0]const u8, length: c_int, op: Op, state: c.JSValue, arrow: bool) !c.JSValue {
    const roots = [_]c.JSValue{ state, c.JS_NewInt32(s.engine.context, @intFromEnum(op)) };
    const f = try s.own(try (if (arrow) nf.createArrow(s.engine, name, length, callback, &roots) else nf.create(s.engine, name, length, callback, &roots)));
    switch (op) {
        .login, .check, .resolve, .oauth_login, .oauth_refresh, .oauth_key, .oauth_auth, .refresh, .stream_body => {
            const proto = try s.own(try s.engine.checked(c.JS_GetAsyncFunctionPrototype(s.engine.context)));
            if (c.JS_SetPrototype(s.engine.context, f, proto) < 0) return js.capture(s.engine);
        },
        else => {},
    }
    return f;
}
fn allModels(s: *Scope, state: c.JSValue) !c.JSValue {
    const imports = try s.get(state, "imports");
    const config = try s.get(state, "config");
    const extension = try s.get(state, "extension");
    const refreshed = try s.get(state, "refreshed");
    var current = extension;
    if (s.truthy(extension) and s.truthy(refreshed)) {
        current = try merge(s, &.{extension});
        try s.put(current, "models", refreshed);
    }
    const id = try s.get(state, "id");
    var rows = try applyExtension(s, imports, id, try applyJson(s, imports, id, try allProviderModels(s, try s.get(state, "base")), config), current);
    const credential = try s.get(state, "oauthCredential");
    const oauth = if (s.truthy(credential)) try get(s, extension, "oauth") else u();
    const modify = if (s.truthy(credential)) try get(s, oauth, "modifyModels") else u();
    if (s.truthy(credential) and s.truthy(modify)) {
        const chats = try s.array();
        const other = try s.array();
        for (0..try len(s, rows)) |i| {
            const row = try at(s, rows, i);
            try push(s, if (try isChat(s, imports, row)) chats else other, row);
        }
        const modified = try s.call(modify, oauth, &.{ chats, credential });
        rows = try s.invoke(modified, "concat", &.{other});
    }
    const out = try s.array();
    const overrides = try get(s, config, "modelOverrides");
    for (0..try len(s, rows)) |i| {
        const row = try at(s, rows, i);
        const override = try key(s, overrides, try s.get(row, "id"));
        try push(s, out, if (s.truthy(override) and try isChat(s, imports, row)) try applyOverride(s, row, override) else row);
    }
    return out;
}
fn adaptOAuth(s: *Scope, config: c.JSValue) !c.JSValue {
    const out = try s.object();
    try s.put(out, "name", try s.get(config, "name"));
    try s.put(out, "isSubscription", try s.get(config, "isSubscription"));
    try s.put(out, "login", try function(s, "login", 1, .oauth_login, config, true));
    try s.put(out, "refresh", try function(s, "refresh", 2, .oauth_refresh, config, true));
    try s.put(out, "toAuth", try function(s, "toAuth", 1, .oauth_key, config, true));
    return out;
}
fn authMethods(s: *Scope, state: c.JSValue) !c.JSValue {
    const base = try s.get(state, "base");
    const extension = try s.get(state, "extension");
    const config = try s.get(state, "config");
    const inherited = if (sc.nullish(base)) u() else try s.get(try s.get(base, "auth"), "apiKey");
    const raw = try configuredKey(s, config, extension);
    const ext_oauth = try get(s, extension, "oauth");
    const inherited_oauth = if (sc.nullish(ext_oauth)) (if (sc.nullish(base)) u() else try s.get(try s.get(base, "auth"), "oauth")) else ext_oauth;
    const out = try s.object();
    if (s.truthy(inherited) or !c.JS_IsUndefined(raw) or !s.truthy(inherited_oauth)) {
        const api_state = try merge(s, &.{state});
        try s.put(api_state, "inherited", inherited);
        try s.put(api_state, "rawKey", raw);
        try s.put(api_state, "rawHeaders", try configuredHeaders(s, config, extension));
        try s.put(api_state, "authHeader", try authHeader(s, config, extension));
        const method = try s.object();
        try s.put(method, "name", fallback(try get(s, inherited, "name"), try s.text("API key")));
        const old_login = try get(s, inherited, "login");
        try s.put(method, "login", if (sc.nullish(old_login)) try function(s, "", 1, .login, api_state, true) else old_login);
        try s.put(method, "check", try function(s, "check", 1, .check, api_state, true));
        try s.put(method, "resolve", try function(s, "resolve", 1, .resolve, api_state, true));
        try s.put(out, "apiKey", method);
    }
    const extension_oauth = try get(s, extension, "oauth");
    const oauth = if (s.truthy(extension_oauth)) try adaptOAuth(s, try get(s, extension, "oauth")) else (if (sc.nullish(base)) u() else try s.get(try s.get(base, "auth"), "oauth"));
    if (s.truthy(oauth)) {
        const oauth_state = try merge(s, &.{state});
        try s.put(oauth_state, "oauth", oauth);
        try s.put(oauth_state, "rawHeaders", try configuredHeaders(s, config, extension));
        try s.put(oauth_state, "authHeader", try authHeader(s, config, extension));
        const method = try merge(s, &.{oauth});
        try s.put(method, "toAuth", try function(s, "toAuth", 1, .oauth_auth, oauth_state, true));
        try s.put(out, "oauth", method);
    }
    if (!s.truthy(try get(s, out, "apiKey")) and !s.truthy(try get(s, out, "oauth"))) return providerError(s, try s.get(state, "id"), ": no authentication method configured.");
    return out;
}
fn compose(s: *Scope, imports: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const state = try s.object();
    const id = arg(args, 0);
    const base = arg(args, 1);
    const extension = arg(args, 3);
    const config = try s.invoke(arg(args, 2), "getProvider", &.{id});
    try s.put(state, "imports", imports);
    try s.put(state, "id", id);
    try s.put(state, "base", base);
    try s.put(state, "config", config);
    try s.put(state, "extension", extension);
    _ = try allModels(s, state);
    const auth = try authMethods(s, state);
    const out = try s.object();
    try s.put(out, "id", id);
    var name = try coalesce(s, &.{ .{ .object = extension, .name = "name" }, .{ .object = config, .name = "name" }, .{ .object = base, .name = "name" } }, u());
    if (sc.nullish(name)) name = fallback(try get(s, try get(s, extension, "oauth"), "name"), id);
    try s.put(out, "name", name);
    try s.put(out, "baseUrl", try coalesce(s, &.{ .{ .object = extension, .name = "baseUrl" }, .{ .object = config, .name = "baseUrl" }, .{ .object = base, .name = "baseUrl" } }, u()));
    try s.put(out, "headers", try get(s, base, "headers"));
    try s.put(out, "auth", auth);
    try s.put(out, "getModels", try function(s, "getModels", 0, .chat, state, true));
    try s.put(out, "getAllModels", try function(s, "getAllModels", 0, .all, state, true));
    const refresh = s.truthy(try get(s, base, "refreshModels")) or s.truthy(try get(s, extension, "refreshModels")) or s.truthy(try get(s, try get(s, extension, "oauth"), "modifyModels"));
    try s.put(out, "refreshModels", if (refresh) try function(s, "", 1, .refresh, state, true) else u());
    inline for (.{ .{ "filterModels", Op.filter }, .{ "filterAllModels", Op.filter_all } }) |row| try s.put(out, row[0], if (s.truthy(try get(s, base, row[0]))) try function(s, "", 2, row[1], state, true) else u());
    try s.put(out, "stream", try function(s, "stream", 3, .stream, state, true));
    try s.put(out, "streamSimple", try function(s, "streamSimple", 3, .simple, state, true));
    inline for (.{ .{ "fetchDeferred", Op.fetch }, .{ "cancelDeferred", Op.cancel } }) |row| {
        const original = try get(s, base, row[0]);
        if (s.truthy(original)) {
            try s.put(state, row[0], original);
            try s.put(out, row[0], try function(s, "", 3, row[1], state, true));
        }
    }
    inline for (.{ .{ "generateImages", "images", Op.images }, .{ "classify", "classifiers", Op.classify } }) |row| {
        const original = try get(s, base, row[0]);
        const implementations = try get(s, extension, row[1]);
        if (s.truthy(original) or (!sc.nullish(implementations) and try len(s, try entries(s, implementations, "keys")) > 0)) {
            try s.put(state, row[0], original);
            try s.put(state, row[1], implementations);
            try s.put(out, row[0], try function(s, "", 3, row[2], state, true));
        }
    }
    return out;
}
fn configEnvironment(engine: *em.Engine, imports: c.JSValue, values: c.JSValue, ctx: c.JSValue, explicit: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = try s.object();
    try s.put(job, "ctx", ctx);
    const env = try merge(&s, &.{explicit});
    try s.put(job, "env", env);
    try s.put(job, "index", c.JS_NewInt32(engine.context, 0));
    const names = try s.array();
    for (0..try len(&s, values)) |i| {
        const refs = try configCall(&s, imports, "getConfigValueEnvVarNames", &.{try at(&s, values, i)});
        for (0..try len(&s, refs)) |j| {
            const name = try at(&s, refs, j);
            if (!s.truthy(try s.invoke(names, "includes", &.{name}))) try push(&s, names, name);
        }
    }
    try s.put(job, "names", names);
    const pending = try async_api.create(engine, job);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    envStep(engine, pending.owner, u(), false, 0) catch |err| try async_api.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn envStep(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return async_api.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = try s.get(owner, "agent");
    const env = try s.get(job, "env");
    if (stage == 1 and !c.JS_IsUndefined(value)) try js.setKey(engine, env, try s.get(job, "current"), value);
    const names = try s.get(job, "names");
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, try s.get(job, "index")) < 0) return js.capture(engine);
    while (index < try len(&s, names)) {
        const name = try at(&s, names, index);
        index += 1;
        try s.put(job, "index", c.JS_NewUint32(engine.context, index));
        if (!c.JS_IsUndefined(try key(&s, env, name))) continue;
        try s.put(job, "current", name);
        const awaiting = try s.invoke(try s.get(job, "ctx"), "env", &.{name});
        return async_api.wait(envStep, engine, owner, awaiting, 1);
    }
    return async_api.settle(engine, owner, false, if (try len(&s, try entries(&s, env, "keys")) > 0) env else u());
}
fn apiStatus(s: *Scope, source: c.JSValue) !c.JSValue {
    const out = try s.object();
    try s.put(out, "type", try s.text("api_key"));
    try s.put(out, "source", source);
    return out;
}
fn localAuthResult(s: *Scope, api_key: c.JSValue, env: c.JSValue, source: []const u8, include_env: bool) !c.JSValue {
    const out = try s.object();
    const auth = try s.object();
    try s.put(auth, "apiKey", api_key);
    try s.put(out, "auth", auth);
    if (include_env) try s.put(out, "env", env);
    try s.put(out, "source", try s.text(source));
    return out;
}
fn rawValues(s: *Scope, value: c.JSValue) !c.JSValue {
    const values = try s.array();
    try push(s, values, value);
    return values;
}
fn providerDescription(s: *Scope, state: c.JSValue) !c.JSValue {
    return message(s, &.{ try s.text("provider \""), try s.get(state, "id"), try s.text("\"") });
}
fn awaitResolved(s: *Scope, owner: c.JSValue, job: c.JSValue, result: c.JSValue) !void {
    const engine = s.engine;
    if (!s.truthy(result)) return async_api.settle(engine, owner, false, u());
    try s.put(job, "result", result);
    const state = try s.get(job, "state");
    const input = try at(s, try s.get(job, "args"), 0);
    const explicit = try merge(s, &.{ try get(s, try get(s, input, "credential"), "env"), try s.get(result, "env") });
    const headers = try s.get(state, "rawHeaders");
    const values = try entries(s, if (sc.nullish(headers)) try s.object() else headers, "values");
    const awaiting = try s.own(try configEnvironment(engine, try s.get(state, "imports"), values, try s.get(input, "ctx"), explicit));
    return async_api.wait(asyncStep, engine, owner, awaiting, 14);
}
fn invokeInherited(s: *Scope, inherited: c.JSValue, input: c.JSValue, method: [*:0]const u8) !c.JSValue {
    return if (sc.nullish(inherited)) u() else s.invoke(inherited, method, &.{input});
}
fn asyncStart(engine: *em.Engine, state: c.JSValue, op: Op, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = try s.object();
    try s.put(job, "state", state);
    try s.put(job, "op", c.JS_NewInt32(engine.context, @intFromEnum(op)));
    const argv = try s.array();
    for (args) |v| try push(&s, argv, v);
    try s.put(job, "args", argv);
    const pending = try async_api.create(engine, job);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    asyncStep(engine, pending.owner, u(), false, 0) catch |err| try async_api.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn asyncStep(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return async_api.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const job = try s.get(owner, "agent");
    const state = try s.get(job, "state");
    const args = try s.get(job, "args");
    const input = try at(&s, args, 0);
    var op_int: u32 = 0;
    if (c.JS_ToUint32(engine.context, &op_int, try s.get(job, "op")) < 0) return js.capture(engine);
    const op: Op = @enumFromInt(op_int);
    if (stage == 99) return async_api.settle(engine, owner, false, value);
    switch (op) {
        .login => {
            if (stage == 1) {
                const out = try s.object();
                try s.put(out, "type", try s.text("api_key"));
                try s.put(out, "key", value);
                return async_api.settle(engine, owner, false, out);
            }
            const prompt = try s.object();
            try s.put(prompt, "type", try s.text("secret"));
            try s.put(prompt, "message", try s.text("Enter API key"));
            return async_api.wait(asyncStep, engine, owner, try s.invoke(input, "prompt", &.{prompt}), 1);
        },
        .check => {
            const imports = try s.get(state, "imports");
            const inherited = try s.get(state, "inherited");
            const credential = try s.get(input, "credential");
            const raw = try s.get(state, "rawKey");
            if (stage == 2) return async_api.settle(engine, owner, false, if (s.truthy(value)) try apiStatus(&s, try s.get(value, "source")) else u());
            if (stage == 3 and c.JS_IsUndefined(value)) return async_api.settle(engine, owner, false, u());
            if (stage == 3) {
                const names = try s.get(job, "names");
                var index: u32 = 0;
                if (c.JS_ToUint32(engine.context, &index, try s.get(job, "index")) < 0) return js.capture(engine);
                if (index < try len(&s, names)) {
                    try s.put(job, "index", c.JS_NewUint32(engine.context, index + 1));
                    return async_api.wait(asyncStep, engine, owner, try s.invoke(try s.get(input, "ctx"), "env", &.{try at(&s, names, index)}), 3);
                }
                return async_api.settle(engine, owner, false, try apiStatus(&s, try s.text("configured API key")));
            }
            if (s.truthy(credential)) {
                if (s.truthy(try get(&s, inherited, "check"))) return async_api.wait(asyncStep, engine, owner, try s.invoke(inherited, "check", &.{input}), 99);
                if (s.truthy(try s.get(credential, "key"))) return async_api.settle(engine, owner, false, try apiStatus(&s, try s.text("stored credential")));
                return async_api.wait(asyncStep, engine, owner, try invokeInherited(&s, inherited, input, "resolve"), 2);
            }
            if (!c.JS_IsUndefined(raw)) {
                if (s.truthy(try configCall(&s, imports, "isCommandConfigValue", &.{raw}))) return async_api.settle(engine, owner, false, try apiStatus(&s, try s.text("configured API key")));
                const names = try configCall(&s, imports, "getConfigValueEnvVarNames", &.{raw});
                try s.put(job, "names", names);
                try s.put(job, "index", c.JS_NewInt32(engine.context, 0));
                // The initial loop must execute synchronously until its first await.
                if (try len(&s, names) == 0) return async_api.settle(engine, owner, false, try apiStatus(&s, try s.text("configured API key")));
                try s.put(job, "index", c.JS_NewInt32(engine.context, 1));
                return async_api.wait(asyncStep, engine, owner, try s.invoke(try s.get(input, "ctx"), "env", &.{try at(&s, names, 0)}), 3);
            }
            if (s.truthy(try get(&s, inherited, "check"))) return async_api.wait(asyncStep, engine, owner, try s.invoke(inherited, "check", &.{input}), 99);
            return async_api.wait(asyncStep, engine, owner, try invokeInherited(&s, inherited, input, "resolve"), 2);
        },
        .resolve => {
            const imports = try s.get(state, "imports");
            const inherited = try s.get(state, "inherited");
            const credential = try s.get(input, "credential");
            if (stage == 11) {
                const description_key = try message(&s, &.{ try s.text("API key for provider \""), try s.get(state, "id"), try s.text("\"") });
                const resolved = try configCall(&s, imports, "resolveConfigValueOrThrow", &.{ try s.get(state, "rawKey"), description_key, value });
                if (s.truthy(inherited)) {
                    const adjusted = try merge(&s, &.{input});
                    const cred = try s.object();
                    try s.put(cred, "type", try s.text("api_key"));
                    try s.put(cred, "key", resolved);
                    try s.put(adjusted, "credential", cred);
                    return async_api.wait(asyncStep, engine, owner, try s.invoke(inherited, "resolve", &.{adjusted}), 12);
                }
                return awaitResolved(&s, owner, job, try localAuthResult(&s, resolved, u(), "configured API key", false));
            }
            if (stage == 12) return awaitResolved(&s, owner, job, value);
            if (stage == 14) {
                const headers = try configCall(&s, imports, "resolveHeadersOrThrow", &.{ try s.get(state, "rawHeaders"), try providerDescription(&s, state), value });
                const result = try s.get(job, "result");
                const out = try merge(&s, &.{result});
                try s.put(out, "auth", try withAuth(&s, try s.get(result, "auth"), headers, try s.get(state, "authHeader")));
                return async_api.settle(engine, owner, false, out);
            }
            if (s.truthy(credential)) {
                if (s.truthy(inherited)) return async_api.wait(asyncStep, engine, owner, try s.invoke(inherited, "resolve", &.{input}), 12);
                const credential_key = try s.get(credential, "key");
                return awaitResolved(&s, owner, job, if (s.truthy(credential_key)) try localAuthResult(&s, credential_key, try s.get(credential, "env"), "stored credential", true) else u());
            }
            const raw = try s.get(state, "rawKey");
            if (!c.JS_IsUndefined(raw)) {
                const awaiting = try s.own(try configEnvironment(engine, imports, try rawValues(&s, raw), try s.get(input, "ctx"), u()));
                return async_api.wait(asyncStep, engine, owner, awaiting, 11);
            }
            return async_api.wait(asyncStep, engine, owner, try invokeInherited(&s, inherited, input, "resolve"), 12);
        },
        .oauth_login => {
            if (stage == 1) {
                const out = try merge(&s, &.{value});
                try s.put(out, "type", try s.text("oauth"));
                return async_api.settle(engine, owner, false, out);
            }
            const callbacks = try s.object();
            inline for (.{ .{ "onAuth", Op.notify_auth, 1 }, .{ "onDeviceCode", Op.notify_device, 1 }, .{ "onPrompt", Op.prompt_text, 1 }, .{ "onProgress", Op.notify_progress, 1 }, .{ "onManualCodeInput", Op.prompt_manual, 0 }, .{ "onSelect", Op.prompt_select, 1 } }) |row| try s.put(callbacks, row[0], try function(&s, "", row[2], row[1], input, true));
            try s.put(callbacks, "signal", try s.get(input, "signal"));
            return async_api.wait(asyncStep, engine, owner, try s.invoke(state, "login", &.{callbacks}), 1);
        },
        .oauth_refresh => {
            if (stage == 1) {
                const out = try merge(&s, &.{value});
                try s.put(out, "type", try s.text("oauth"));
                return async_api.settle(engine, owner, false, out);
            }
            return async_api.wait(asyncStep, engine, owner, try s.invoke(state, "refreshToken", &.{ input, try at(&s, args, 1) }), 1);
        },
        .oauth_key => {
            const out = try s.object();
            try s.put(out, "apiKey", try s.invoke(state, "getApiKey", &.{input}));
            return async_api.settle(engine, owner, false, out);
        },
        .oauth_auth => {
            if (stage == 1) {
                const env = try s.get(input, "env");
                const imports = try s.get(state, "imports");
                const headers = try configCall(&s, imports, "resolveHeadersOrThrow", &.{ try s.get(state, "rawHeaders"), try providerDescription(&s, state), if (objectType(&s, env)) env else u() });
                return async_api.settle(engine, owner, false, try withAuth(&s, value, headers, try s.get(state, "authHeader")));
            }
            return async_api.wait(asyncStep, engine, owner, try s.invoke(try s.get(state, "oauth"), "toAuth", &.{input}), 1);
        },
        .refresh => {
            const base = try s.get(state, "base");
            const extension = try s.get(state, "extension");
            if (stage == 0) {
                const method = try get(&s, base, "refreshModels");
                return async_api.wait(asyncStep, engine, owner, if (sc.nullish(method)) u() else try s.call(method, base, &.{input}), 1);
            }
            if (stage == 1) {
                const method = try get(&s, extension, "refreshModels");
                if (s.truthy(method)) return async_api.wait(asyncStep, engine, owner, try s.call(method, extension, &.{input}), 2);
            }
            if (stage == 2) try s.put(job, "refreshed", value);
            if (stage == 3) return async_api.settle(engine, owner, false, u());
            if (s.truthy(try s.get(try s.get(input, "signal"), "aborted"))) return async_api.settle(engine, owner, false, u());
            const credential = try s.get(input, "credential");
            try s.put(job, "oauthCredential", if (s.equal(try get(&s, credential, "type"), try s.text("oauth"))) credential else u());
            const publication = try s.object();
            try s.put(publication, "update", try function(&s, "update", 0, .update, job, true));
            return async_api.wait(asyncStep, engine, owner, try s.invoke(input, "publish", &.{publication}), 3);
        },
        .stream_body => {
            const original = try s.get(state, "providerState");
            const base = try s.get(original, "base");
            const extension = try s.get(original, "extension");
            const model = input;
            const context = try at(&s, args, 1);
            const opts = try at(&s, args, 2);
            const api = try s.get(model, "api");
            const simple = s.truthy(try s.get(state, "simple"));
            if (s.truthy(try get(&s, extension, "streamSimple")) and s.equal(api, try get(&s, extension, "api"))) return async_api.settle(engine, owner, false, try s.invoke(extension, "streamSimple", &.{ model, context, opts }));
            if (s.truthy(base)) {
                const models = try s.invoke(base, "getModels", &.{});
                var supported = false;
                for (0..try len(&s, models)) |i| {
                    if (s.equal(try s.get(try at(&s, models, i), "api"), api)) {
                        supported = true;
                        break;
                    }
                }
                if (supported) return async_api.settle(engine, owner, false, try s.invoke(base, if (simple) "streamSimple" else "stream", &.{ model, context, opts }));
            }
            const imports = try s.get(original, "imports");
            const implementation = try s.call(try s.get(imports, "getApiProvider"), u(), &.{api});
            if (!s.truthy(implementation)) return errorMessage(&s, try s.concat(try s.text("No API provider registered for api: "), api));
            return async_api.settle(engine, owner, false, try s.invoke(implementation, if (simple) "streamSimple" else "stream", &.{ model, context, opts }));
        },
        else => return error.InvalidProviderComposerAsyncOperation,
    }
}
fn callback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = roots[0];
    var op_int: u32 = 0;
    if (c.JS_ToUint32(engine.context, &op_int, roots[1]) < 0) return js.capture(engine);
    const op: Op = @enumFromInt(op_int);
    switch (op) {
        .login, .check, .resolve, .oauth_login, .oauth_refresh, .oauth_key, .oauth_auth, .refresh => return asyncStart(engine, state, op, args),
        .compose => return c.JS_DupValue(engine.context, try compose(&s, state, args)),
        .validate => {
            const extension = arg(args, 3);
            if (s.truthy(try s.get(extension, "streamSimple")) and !s.truthy(try s.get(extension, "api"))) return providerError(&s, arg(args, 0), ": \"api\" is required when registering streamSimple.");
            _ = try applyExtension(&s, state, arg(args, 0), try applyJson(&s, state, arg(args, 0), try allProviderModels(&s, arg(args, 1)), arg(args, 2)), extension);
            return u();
        },
        .headers => {
            const model = arg(args, 0);
            return c.JS_DupValue(engine.context, try configCall(&s, state, "resolveHeadersOrThrow", &.{ try rawHeaders(&s, state, model, arg(args, 1), arg(args, 2)), try description(&s, model), arg(args, 3) }));
        },
        .compat => {
            const model = arg(args, 0);
            const config = arg(args, 1);
            const extension = arg(args, 2);
            const configured = try configCall(&s, state, "resolveHeadersOrThrow", &.{ try merge(&s, &.{ try configuredHeaders(&s, config, extension), try rawHeaders(&s, state, model, config, extension) }), try description(&s, model) });
            const headers = try s.get(model, "headers");
            const out = try s.object();
            try s.put(out, "headers", if (s.truthy(headers) or s.truthy(configured)) try merge(&s, &.{ headers, configured }) else u());
            try s.put(out, "authHeader", try authHeader(&s, config, extension));
            return c.JS_DupValue(engine.context, out);
        },
        .status => {
            const config = arg(args, 0);
            const extension = arg(args, 1);
            const value = try configuredKey(&s, config, extension);
            if (c.JS_IsUndefined(value)) return u();
            const out = try s.object();
            try s.put(out, "configured", c.pi_js_bool(engine.context, 1));
            if (s.truthy(try configCall(&s, state, "isCommandConfigValue", &.{value}))) {
                try s.put(out, "source", try s.text("models_json_command"));
                return c.JS_DupValue(engine.context, out);
            }
            const names = try configCall(&s, state, "getConfigValueEnvVarNames", &.{value});
            if (try len(&s, names) > 0) {
                if (s.truthy(try configCall(&s, state, "isConfigValueConfigured", &.{value}))) {
                    try s.put(out, "source", try s.text("environment"));
                    try s.put(out, "label", try s.invoke(names, "join", &.{try s.text(", ")}));
                } else try s.put(out, "configured", c.pi_js_bool(engine.context, 0));
            } else try s.put(out, "source", try s.text(if (!c.JS_IsUndefined(try get(&s, extension, "apiKey"))) "fallback" else "models_json_key"));
            return c.JS_DupValue(engine.context, out);
        },
        .all, .chat => {
            const rows = try allModels(&s, state);
            if (op == .all) return c.JS_DupValue(engine.context, rows);
            const out = try s.array();
            const imports = try s.get(state, "imports");
            for (0..try len(&s, rows)) |i| {
                const row = try at(&s, rows, i);
                if (try isChat(&s, imports, row)) try push(&s, out, row);
            }
            return c.JS_DupValue(engine.context, out);
        },
        .stream, .simple => {
            const job = try s.object();
            try s.put(job, "providerState", state);
            try s.put(job, "simple", c.pi_js_bool(engine.context, @intFromBool(op == .simple)));
            const captured = try s.array();
            for ([_]c.JSValue{ arg(args, 0), arg(args, 1), arg(args, 2) }) |v| try push(&s, captured, v);
            try s.put(job, "streamArgs", captured);
            const starter = try function(&s, "", 0, .stream_body, job, true);
            const imports = try s.get(state, "imports");
            return c.JS_DupValue(engine.context, try s.call(try s.get(imports, "lazyStream"), u(), &.{ arg(args, 0), starter }));
        },
        .stream_body => {
            const captured = try s.get(state, "streamArgs");
            return asyncStart(engine, state, .stream_body, &.{ try at(&s, captured, 0), try at(&s, captured, 1), try at(&s, captured, 2) });
        },
        .update => {
            const provider = try s.get(state, "state");
            const refreshed = try get(&s, state, "refreshed");
            if (s.truthy(refreshed)) {
                const extension = try merge(&s, &.{try s.get(provider, "extension")});
                try s.put(extension, "models", refreshed);
                _ = try applyExtension(&s, try s.get(provider, "imports"), try s.get(provider, "id"), try applyJson(&s, try s.get(provider, "imports"), try s.get(provider, "id"), try allProviderModels(&s, try s.get(provider, "base")), try s.get(provider, "config")), extension);
                try s.put(provider, "refreshed", refreshed);
            }
            try s.put(provider, "oauthCredential", try s.get(state, "oauthCredential"));
            return u();
        },
        .filter, .filter_all => return c.JS_DupValue(engine.context, try s.invoke(try s.get(state, "base"), if (op == .filter) "filterModels" else "filterAllModels", &.{ arg(args, 0), arg(args, 1) })),
        .fetch, .cancel => return c.JS_DupValue(engine.context, try s.call(try s.get(state, if (op == .fetch) "fetchDeferred" else "cancelDeferred"), u(), &.{ arg(args, 0), arg(args, 1), arg(args, 2) })),
        .images, .classify => {
            const model = arg(args, 0);
            const api = try s.get(model, "api");
            const implementations = try s.get(state, if (op == .images) "images" else "classifiers");
            const implementation = try key(&s, implementations, api);
            const method: [*:0]const u8 = if (op == .images) "generateImages" else "classify";
            if (s.truthy(implementation)) return c.JS_DupValue(engine.context, try s.invoke(implementation, method, &.{ model, arg(args, 1), arg(args, 2) }));
            const base = try s.get(state, method);
            if (s.truthy(base)) return c.JS_DupValue(engine.context, try s.call(base, u(), &.{ model, arg(args, 1), arg(args, 2) }));
            const err = try s.own(try js.builtin(engine, "Error", &.{try message(&s, &.{ try s.text("Provider "), try s.get(state, "id"), try s.text(if (op == .images) " has no image implementation for \"" else " has no classifier implementation for \""), api, try s.text("\"") })}));
            const result = try s.call(try s.get(try s.get(state, "imports"), if (op == .images) "imageErrorResult" else "classifierErrorResult"), u(), &.{ model, err });
            return engine.checked(c.JS_PiPromiseResolve(engine.context, result));
        },
        .notify_auth, .notify_device, .prompt_text, .notify_progress, .prompt_manual, .prompt_select => {
            const request = try s.object();
            const tag = switch (op) {
                .notify_auth => "auth_url",
                .notify_device => "device_code",
                .prompt_text => "text",
                .notify_progress => "progress",
                .prompt_manual => "manual_code",
                .prompt_select => "select",
                else => unreachable,
            };
            try s.put(request, "type", try s.text(tag));
            if (op == .notify_progress) try s.put(request, "message", arg(args, 0)) else if (op == .prompt_manual) try s.put(request, "message", try s.text("Paste the authorization code")) else try js.spreadInto(engine, request, arg(args, 0));
            return c.JS_DupValue(engine.context, try s.invoke(state, if (op == .prompt_text or op == .prompt_manual or op == .prompt_select) "prompt" else "notify", &.{request}));
        },
    }
}
pub fn install(engine: *em.Engine, namespace: c.JSValue, imports: Imports) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const captures = try s.object();
    inline for (std.meta.fieldNames(Imports)) |field| try s.put(captures, field, @field(imports, field));
    // Source exports this exact alias, including identity and ordinary function metadata.
    try s.put(namespace, "clearApiKeyCache", try s.get(imports.configValues, "clearConfigValueCache"));
    inline for (.{ .{ "composeModelProvider", Op.compose, 4 }, .{ "configuredRequestAuthStatus", Op.status, 2 }, .{ "resolveCompatibilityRequestConfig", Op.compat, 3 }, .{ "resolveConfiguredModelHeaders", Op.headers, 4 }, .{ "validateExtensionProvider", Op.validate, 4 } }) |row| try s.put(namespace, row[0], try function(&s, row[0], row[2], row[1], captures, false));
}

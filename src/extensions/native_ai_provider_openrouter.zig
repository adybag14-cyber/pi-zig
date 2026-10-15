//! Original OpenRouter personalization and per-million/tier price conversion.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const arithmetic = @import("native_image_arithmetic.zig");
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const http = @import("native_ai_oauth_http.zig");
fn arg(args: []const c.JSValue, n: usize) c.JSValue {
    return if (n < args.len) args[n] else c.pi_js_undefined();
}
fn opt(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (v.nullish(object)) c.pi_js_undefined() else s.get(object, name);
}
fn perMillion(s: *Scope, value: c.JSValue, fallback: c.JSValue) !c.JSValue {
    const number = try s.global("Number");
    const parse = try s.get(number, "parseFloat");
    const per_token = try s.call(parse, number, &.{if (v.nullish(value)) try s.text("") else value});
    if (!(try arithmetic.compare(s.engine, .greater_equal, per_token, c.JS_NewInt32(s.engine.context, 0)))) return fallback;
    const constructor = try s.global("Number");
    const rate = try s.own(try arithmetic.binary(s.engine, .multiply, per_token, c.JS_NewInt32(s.engine.context, 1000000)));
    return s.call(constructor, c.pi_js_undefined(), &.{try s.invoke(rate, "toFixed", &.{c.JS_NewInt32(s.engine.context, 6)})});
}
pub fn cost(s: *Scope, pricing: c.JSValue) !c.JSValue {
    const base = try s.object();
    inline for (.{ .{ "input", "prompt" }, .{ "output", "completion" }, .{ "cacheRead", "input_cache_read" }, .{ "cacheWrite", "input_cache_write" } }) |field| try s.put(base, field[0], try perMillion(s, try opt(s, pricing, field[1]), c.JS_NewInt32(s.engine.context, 0)));
    const raw = try opt(s, pricing, "overrides");
    const overrides = if (v.nullish(raw)) try s.array() else raw;
    const flat_map = try s.get(overrides, "flatMap");
    const Tier = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const value = arg(args, 0);
            const result = try local.array();
            if (c.JS_IsUndefined(try local.get(value, "min_prompt_tokens")) or !c.JS_IsUndefined(try local.get(value, "utc_start")) or !c.JS_IsUndefined(try local.get(value, "utc_end")) or !c.JS_IsUndefined(try local.get(value, "utc_days"))) return c.JS_DupValue(engine.context, result);
            const tier = try local.object();
            try local.put(tier, "inputTokensAbove", try local.get(value, "min_prompt_tokens"));
            inline for (.{ .{ "input", "prompt" }, .{ "output", "completion" }, .{ "cacheRead", "input_cache_read" }, .{ "cacheWrite", "input_cache_write" } }) |field| try local.put(tier, field[0], try perMillion(&local, try local.get(value, field[1]), try local.get(roots[0], field[0])));
            try local.index(result, 0, tier);
            return c.JS_DupValue(engine.context, result);
        }
    };
    const tiers = try s.call(flat_map, overrides, &.{try s.own(try functions.createArrow(s.engine, "", 1, Tier.call, &.{base}))});
    if (!(try arithmetic.compare(s.engine, .greater, try s.get(tiers, "length"), c.JS_NewInt32(s.engine.context, 0)))) return base;
    const result = try s.own(try v.js.spread(s.engine, base));
    try s.put(result, "tiers", tiers);
    return result;
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    return @import("native_ai_auth_helpers.zig").asyncArrow(engine, "personalizeOpenRouterCatalog", 2, personalize, &.{});
}
pub fn costFunction(engine: *v.em.Engine) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            return c.JS_DupValue(host.context, try cost(&local, arg(args, 0)));
        }
    };
    return functions.create(engine, "openRouterCost", 1, Adapter.call, &.{});
}
fn personalize(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(&s, pending.owner, arg(args, 0), arg(args, 1)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(s: *Scope, owner: c.JSValue, catalog: c.JSValue, context: c.JSValue) !void {
    try s.put(owner, "catalog", catalog);
    try s.put(owner, "context", context);
    const credential = try s.get(context, "credential");
    const key = if (try v.eq(s, try opt(s, credential, "type"), "oauth")) try s.get(try s.get(context, "credential"), "access") else try opt(s, try s.get(context, "credential"), "key");
    if (!s.truthy(key)) return flow.settle(s.engine, owner, false, catalog);
    const captured = try http.captureFetch(s);
    const supplied = try s.get(context, "baseUrl");
    const base = if (v.nullish(supplied)) try s.text("https://openrouter.ai/api/v1") else supplied;
    var regex_args = [_]c.JSValue{try s.text("/+$")};
    const pattern = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, regex_args.len, &regex_args)));
    const url = try s.concat(try s.stringify(try s.invoke(base, "replace", &.{ pattern, try s.text("") })), try s.text("/models/user"));
    const init = try s.object();
    const headers = try s.object();
    try s.put(headers, "accept", try s.text("application/json"));
    try s.put(headers, "authorization", try s.concat(try s.text("Bearer "), try s.stringify(key)));
    try s.put(init, "headers", headers);
    const signal_class = try s.global("AbortSignal");
    const any = try s.get(signal_class, "any");
    const signals = try s.array();
    try s.index(signals, 0, try s.get(context, "signal"));
    const timeout_class = try s.global("AbortSignal");
    const timeout = try s.get(timeout_class, "timeout");
    try s.index(signals, 1, try s.call(timeout, timeout_class, &.{c.JS_NewInt32(s.engine.context, 15000)}));
    try s.put(init, "signal", try s.call(any, signal_class, &.{signals}));
    return flow.wait(continued, s.engine, owner, try s.own(try http.requestWithFetch(s.engine, captured, url, init)), 0);
}
fn throwError(s: *Scope, constructor: c.JSValue, message: c.JSValue) !void {
    var values = [_]c.JSValue{message};
    _ = try s.engine.checked(c.JS_Throw(s.engine.context, try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, values.len, &values))));
    unreachable;
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    advance(&s, owner, value, stage) catch |err| try flow.rejectError(engine, owner, err);
}
fn has(s: *Scope, value: c.JSValue, name: [*:0]const u8) !bool {
    const atom = c.JS_NewAtom(s.engine.context, name);
    defer c.JS_FreeAtom(s.engine.context, atom);
    const result = c.JS_HasProperty(s.engine.context, value, atom);
    if (result < 0) return v.js.capture(s.engine);
    return result != 0;
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: c_int) !void {
    if (stage == 0) {
        if (s.equal(try s.get(value, "status"), c.JS_NewInt32(s.engine.context, 401)) or s.equal(try s.get(value, "status"), c.JS_NewInt32(s.engine.context, 403)) or s.equal(try s.get(value, "status"), c.JS_NewInt32(s.engine.context, 404))) return flow.settle(s.engine, owner, false, try s.get(owner, "catalog"));
        if (!s.truthy(try s.get(value, "ok"))) {
            const constructor = try s.global("Error");
            try throwError(s, constructor, try s.concat(try s.text("OpenRouter model list request failed: "), try s.stringify(try s.get(value, "status"))));
            unreachable;
        }
        return flow.wait(continued, s.engine, owner, try s.invoke(value, "json", &.{}), 1);
    }
    if (!c.JS_IsObject(value) or c.JS_IsFunction(s.engine.context, value) or !(try has(s, value, "data")) or !s.truthy(try s.invoke(try s.global("Array"), "isArray", &.{try s.get(value, "data")}))) {
        const constructor = try s.global("Error");
        try throwError(s, constructor, try s.text("Invalid OpenRouter model list response"));
        unreachable;
    }
    const allowed = try s.own(try v.js.builtin(s.engine, "Map", &.{}));
    var entries = try v.iterator(s, try s.get(value, "data"));
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer s.engine.freeValue(entry);
        if (!c.JS_IsObject(entry) or c.JS_IsFunction(s.engine.context, entry) or !(try has(s, entry, "id")) or !c.JS_IsString(try s.get(entry, "id"))) continue;
        const set = try s.get(allowed, "set");
        _ = try s.call(set, allowed, &.{ try s.get(entry, "id"), entry });
    }
    const catalog = try s.get(owner, "catalog");
    const flat_map = try s.get(catalog, "flatMap");
    const Select = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const model = arg(args, 0);
            const result = try local.array();
            const raw = try local.get(model, "type");
            if (!(try v.eq(&local, if (v.nullish(raw)) try local.text("chat") else raw, "chat"))) {
                try local.index(result, 0, model);
                return c.JS_DupValue(engine.context, result);
            }
            const get = try local.get(roots[0], "get");
            const entry = try local.call(get, roots[0], &.{try local.get(model, "id")});
            if (!local.truthy(entry)) return c.JS_DupValue(engine.context, result);
            const selected = try local.own(try v.js.spread(engine, model));
            var context_window = try opt(&local, try local.get(entry, "top_provider"), "context_length");
            if (!local.truthy(context_window)) context_window = try local.get(entry, "context_length");
            if (!local.truthy(context_window)) context_window = try local.get(model, "contextWindow");
            try local.put(selected, "contextWindow", context_window);
            const maximum = try opt(&local, try local.get(entry, "top_provider"), "max_completion_tokens");
            try local.put(selected, "maxTokens", if (local.truthy(maximum)) maximum else try local.get(model, "maxTokens"));
            try local.put(selected, "cost", if (local.truthy(try local.get(entry, "pricing"))) try cost(&local, try local.get(entry, "pricing")) else try local.get(model, "cost"));
            try local.index(result, 0, selected);
            return c.JS_DupValue(engine.context, result);
        }
    };
    return flow.settle(s.engine, owner, false, try s.call(flat_map, catalog, &.{try s.own(try functions.createArrow(s.engine, "", 1, Select.call, &.{allowed}))}));
}

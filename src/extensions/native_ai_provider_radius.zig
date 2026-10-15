//! Radius's replacing catalog, persisted publication and gateway config bodies.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const functions = @import("native_node_function.zig");
const http = @import("native_ai_oauth_http.zig");
const default_gateway = "https://radius.pi.dev";
const Stage = enum(c_int) { restored, legacy, response, json, text, config_ready, published };
fn arg(args: []const c.JSValue, n: usize) c.JSValue {
    return if (n < args.len) args[n] else c.pi_js_undefined();
}
fn opt(s: *Scope, object: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (v.nullish(object)) c.pi_js_undefined() else s.get(object, key);
}
fn literal(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    var values = [_]c.JSValue{ try s.text(pattern), try s.text(flags) };
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, values.len, &values)));
}
pub fn normalize(s: *Scope, raw: c.JSValue) !c.JSValue {
    const scheme = try literal(s, "^https?://", "iu");
    const value = if (s.truthy(try s.invoke(scheme, "test", &.{raw}))) raw else try s.concat(try s.text("https://"), try s.stringify(raw));
    return s.invoke(value, "replace", &.{ try literal(s, "/+$", "u"), try s.text("") });
}
fn isArray(s: *Scope, value: c.JSValue) !bool {
    return s.truthy(try s.invoke(try s.global("Array"), "isArray", &.{value}));
}
fn objectType(engine: *v.em.Engine, value: c.JSValue) bool {
    return c.JS_IsNull(value) or (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value));
}
fn validModel(s: *Scope, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(s.engine.context, value) or try isArray(s, value)) return false;
    return c.JS_IsString(try s.get(value, "id")) and c.JS_IsString(try s.get(value, "name")) and c.JS_IsBool(try s.get(value, "reasoning")) and try isArray(s, try s.get(value, "input")) and objectType(s.engine, try s.get(value, "cost")) and !c.JS_IsNull(try s.get(value, "cost")) and !(try isArray(s, try s.get(value, "cost"))) and c.JS_IsNumber(try s.get(value, "contextWindow")) and c.JS_IsNumber(try s.get(value, "maxTokens"));
}
pub fn sanitize(s: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(s.engine.context, value) or try isArray(s, value)) return c.pi_js_undefined();
    const base = try s.get(value, "baseUrl");
    const models = try s.get(value, "models");
    if (!c.JS_IsString(base) or !(try isArray(s, models))) return c.pi_js_undefined();
    const Select = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            return c.JS_NewBool(engine.context, try validModel(&local, arg(args, 0)));
        }
    };
    const Copy = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return v.js.spread(engine, arg(args, 0));
        }
    };
    const filter = try s.get(models, "filter");
    const selected = try s.call(filter, models, &.{try s.own(try functions.createArrow(s.engine, "", 1, Select.call, &.{}))});
    const map = try s.get(selected, "map");
    const copied = try s.call(map, selected, &.{try s.own(try functions.createArrow(s.engine, "", 1, Copy.call, &.{}))});
    const config = try s.object();
    try s.put(config, "baseUrl", base);
    try s.put(config, "models", copied);
    return config;
}
pub fn fromConfig(s: *Scope, provider: c.JSValue, config: c.JSValue) !c.JSValue {
    const models = try s.get(config, "models");
    const map = try s.get(models, "map");
    const Map = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const model = try local.own(try v.js.spread(engine, arg(args, 0)));
            try local.put(model, "api", try local.text("pi-messages"));
            try local.put(model, "provider", roots[0]);
            try local.put(model, "baseUrl", try local.get(roots[1], "baseUrl"));
            return c.JS_DupValue(engine.context, model);
        }
    };
    return s.call(map, models, &.{try s.own(try functions.createArrow(s.engine, "", 1, Map.call, &.{ provider, config }))});
}
fn legacy(s: *Scope, provider: c.JSValue, credential: c.JSValue) !c.JSValue {
    const config = try sanitize(s, try opt(s, credential, "gatewayConfig"));
    return if (c.JS_IsUndefined(config)) s.array() else fromConfig(s, provider, config);
}
pub fn create(engine: *v.em.Engine, dependencies: c.JSValue, supplied: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const options = if (c.JS_IsUndefined(supplied)) try s.object() else supplied;
    const raw_id = try s.get(options, "id");
    const id = if (v.nullish(raw_id)) try s.text("radius") else raw_id;
    const raw_name = try s.get(options, "name");
    const name = if (v.nullish(raw_name)) try s.text("Radius") else raw_name;
    const raw_gateway = try s.get(options, "gateway");
    const gateway = try normalize(&s, if (v.nullish(raw_gateway)) try s.text(default_gateway) else raw_gateway);
    const state = try s.object();
    try s.put(state, "id", id);
    try s.put(state, "gateway", gateway);
    try s.put(state, "dynamic", c.pi_js_undefined());
    const baseline = if (s.equal(gateway, try normalize(&s, try s.text(default_gateway)))) baseline: {
        const object_constructor = try s.global("Object");
        const values = try s.get(object_constructor, "values");
        const catalog = try s.own(try @import("native_ai_catalog_values.zig").providerChatCatalog(engine, try s.text("radius")));
        const models = try s.call(values, object_constructor, &.{catalog});
        const map = try s.get(models, "map");
        const Copy = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                const model = try local.own(try v.js.spread(host, arg(args, 0)));
                try local.put(model, "provider", roots[0]);
                return c.JS_DupValue(host.context, model);
            }
        };
        break :baseline try s.call(map, models, &.{try s.own(try functions.createArrow(engine, "", 1, Copy.call, &.{id}))});
    } else try s.array();
    try s.put(state, "baseline", baseline);
    const streams = try s.call(try s.get(try s.get(dependencies, "apis"), "piMessagesApi"), c.pi_js_undefined(), &.{});
    try s.put(state, "streams", streams);
    const provider = try s.object();
    try s.put(provider, "id", id);
    try s.put(provider, "name", name);
    const authentication = try s.object();
    const variables = try s.array();
    try s.index(variables, 0, try s.text("RADIUS_API_KEY"));
    try s.put(authentication, "apiKey", try s.own(try helpers.envApiKeyAuth(engine, try s.text("Radius API key"), variables)));
    const load_options = try s.object();
    try s.put(load_options, "name", name);
    try s.put(load_options, "gateway", gateway);
    const Load = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const options_value = try local.object();
            try local.put(options_value, "name", try local.get(roots[1], "name"));
            try local.put(options_value, "gateway", try local.get(roots[1], "gateway"));
            return v.js.call(host, roots[0], c.pi_js_undefined(), &.{options_value});
        }
    };
    const oauth = try s.object();
    try s.put(oauth, "name", name);
    try s.put(oauth, "load", try s.own(try functions.createArrow(engine, "load", 0, Load.call, &.{ try s.get(try s.get(dependencies, "oauth"), "loadRadiusOAuth"), load_options })));
    try s.put(authentication, "oauth", try s.own(try helpers.lazyOAuth(engine, oauth)));
    try s.put(provider, "auth", authentication);
    const Get = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const dynamic = try local.get(roots[0], "dynamic");
            return c.JS_DupValue(host.context, if (v.nullish(dynamic)) try local.get(roots[0], "baseline") else dynamic);
        }
    };
    try s.put(provider, "getModels", try s.own(try functions.createArrow(engine, "getModels", 0, Get.call, &.{state})));
    try s.put(provider, "refreshModels", try s.own(try helpers.asyncArrow(engine, "refreshModels", 1, refresh, &.{state})));
    inline for (.{ "stream", "streamSimple" }) |method| {
        const Call = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                const callback = try local.get(roots[0], method);
                return v.js.call(host, callback, roots[0], &.{ arg(args, 0), arg(args, 1), arg(args, 2) });
            }
        };
        try s.put(provider, method, try s.own(try functions.createArrow(engine, method, 3, Call.call, &.{streams})));
    }
    return c.JS_DupValue(engine.context, provider);
}
fn publish(s: *Scope, owner: c.JSValue, models: c.JSValue, persist: bool, stage: Stage) !void {
    const context = try s.get(owner, "context");
    const callback = try s.get(context, "publish");
    const publication = try s.object();
    if (persist) {
        const stored = try s.object();
        try s.put(stored, "models", models);
        try s.put(stored, "checkedAt", try s.invoke(try s.global("Date"), "now", &.{}));
        try s.put(publication, "persist", stored);
    }
    const Update = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            try local.set(roots[0], "dynamic", roots[1]);
            return c.pi_js_undefined();
        }
    };
    try s.put(publication, "update", try s.own(try functions.createArrow(s.engine, "update", 0, Update.call, &.{ try s.get(owner, "agent"), models })));
    return flow.wait(continued, s.engine, owner, try s.call(callback, context, &.{publication}), @intFromEnum(stage));
}
fn refresh(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(&s, pending.owner, arg(args, 0)) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(s: *Scope, owner: c.JSValue, context: c.JSValue) !void {
    try s.put(owner, "context", context);
    const stored = try s.get(context, "stored");
    try s.put(owner, "stored", stored);
    if (s.truthy(stored)) {
        const models = try s.get(stored, "models");
        const filter = try s.get(models, "filter");
        const Select = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                return c.JS_NewBool(host.context, local.equal(try local.get(arg(args, 0), "provider"), roots[0]));
            }
        };
        const restored = try s.call(filter, models, &.{try s.own(try functions.createArrow(s.engine, "", 1, Select.call, &.{try s.get(try s.get(owner, "agent"), "id")}))});
        const Identity = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return c.JS_DupValue(host.context, arg(args, 0));
            }
        };
        const map = try s.get(restored, "map");
        return publish(s, owner, try s.call(map, restored, &.{try s.own(try functions.createArrow(s.engine, "", 1, Identity.call, &.{}))}), false, .restored);
    }
    return beforeNetwork(s, owner);
}
fn beforeNetwork(s: *Scope, owner: c.JSValue) !void {
    const context = try s.get(owner, "context");
    if (!s.truthy(try s.get(owner, "stored")) and try v.eq(s, try opt(s, try s.get(context, "credential"), "type"), "oauth")) {
        const models = try legacy(s, try s.get(try s.get(owner, "agent"), "id"), try s.get(context, "credential"));
        if (try v.length(s, models) > 0) return publish(s, owner, models, true, .legacy);
    }
    return network(s, owner);
}
fn network(s: *Scope, owner: c.JSValue) !void {
    const context = try s.get(owner, "context");
    if (!s.truthy(try s.get(context, "allowNetwork")) or s.truthy(try s.get(try s.get(context, "signal"), "aborted"))) return flow.settle(s.engine, owner, false, c.pi_js_undefined());
    const stored = try s.get(context, "credential");
    const key = if (try v.eq(s, try opt(s, stored, "type"), "oauth")) try s.get(try s.get(context, "credential"), "access") else try opt(s, try s.get(context, "credential"), "key");
    const signal = try s.get(context, "signal");
    const nested = try flow.create(s.engine, try s.get(owner, "agent"));
    defer s.engine.freeValue(nested.owner);
    const promise = try s.own(nested.promise);
    try s.put(nested.owner, "signal", signal);
    loadConfig(s, nested.owner, key) catch |err| try flow.rejectError(s.engine, nested.owner, err);
    return flow.wait(continued, s.engine, owner, promise, @intFromEnum(Stage.config_ready));
}
fn loadConfig(s: *Scope, owner: c.JSValue, key: c.JSValue) !void {
    const headers = try s.object();
    try s.put(headers, "accept", try s.text("application/json"));
    if (s.truthy(key)) try s.put(headers, "authorization", try s.concat(try s.text("Bearer "), try s.stringify(key)));
    const captured = try http.captureFetch(s);
    const gateway = try s.get(try s.get(owner, "agent"), "gateway");
    const url = try s.own(try v.js.builtin(s.engine, "URL", &.{ try s.text("/v1/config"), gateway }));
    const init = try s.object();
    try s.put(init, "headers", headers);
    try s.put(init, "signal", try s.get(owner, "signal"));
    return flow.wait(continued, s.engine, owner, try s.own(try http.requestWithFetch(s.engine, captured, url, init)), @intFromEnum(Stage.response));
}
fn failure(s: *Scope, constructor: c.JSValue, message: c.JSValue) !void {
    var values = [_]c.JSValue{message};
    _ = try s.engine.checked(c.JS_Throw(s.engine.context, try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, values.len, &values))));
    unreachable;
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    advance(&s, owner, value, @enumFromInt(raw)) catch |err| try flow.rejectError(engine, owner, err);
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .restored => {
            if (!s.truthy(value)) return flow.settle(s.engine, owner, false, c.pi_js_undefined());
            return beforeNetwork(s, owner);
        },
        .legacy => {
            if (!s.truthy(value)) return flow.settle(s.engine, owner, false, c.pi_js_undefined());
            return network(s, owner);
        },
        .response => {
            try s.put(owner, "response", value);
            const ok = s.truthy(try s.get(value, "ok"));
            if (!ok) {
                try s.put(owner, "errorConstructor", try s.global("Error"));
                const gateway = try s.stringify(try s.get(try s.get(owner, "agent"), "gateway"));
                const prefix = try s.concat(try s.concat(try s.concat(try s.text("Could not load Radius config from "), gateway), try s.text(": ")), try s.stringify(try s.get(value, "status")));
                try s.put(owner, "errorPrefix", try s.concat(prefix, try s.text(": ")));
            }
            return flow.wait(continued, s.engine, owner, try s.invoke(value, if (ok) "json" else "text", &.{}), @intFromEnum(if (ok) Stage.json else Stage.text));
        },
        .json => {
            const config = try sanitize(s, value);
            if (c.JS_IsUndefined(config)) {
                const constructor = try s.global("Error");
                const gateway = try s.get(try s.get(owner, "agent"), "gateway");
                try failure(s, constructor, try s.concat(try s.text("Invalid Radius config from "), try s.stringify(gateway)));
                unreachable;
            }
            return flow.settle(s.engine, owner, false, config);
        },
        .config_ready => {
            if (s.truthy(try s.get(try s.get(try s.get(owner, "context"), "signal"), "aborted"))) return flow.settle(s.engine, owner, false, c.pi_js_undefined());
            return publish(s, owner, try fromConfig(s, try s.get(try s.get(owner, "agent"), "id"), value), true, .published);
        },
        .text => {
            const trimmed = try s.invoke(value, "trim", &.{});
            const body = if (try v.length(s, trimmed) > 512) try s.concat(try s.invoke(trimmed, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 512) }), try s.text("…")) else trimmed;
            const message = try s.concat(try s.get(owner, "errorPrefix"), body);
            try failure(s, try s.get(owner, "errorConstructor"), message);
            unreachable;
        },
        .published => return flow.settle(s.engine, owner, false, c.pi_js_undefined()),
    }
}

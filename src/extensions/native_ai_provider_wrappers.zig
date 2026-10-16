//! Native Cloudflare endpoint and OpenCode session wrappers from Source.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
pub const Kind = enum { cloudflare, opencode };
fn argument(args: []const c.JSValue, n: usize) c.JSValue {
    return if (n < args.len) args[n] else c.pi_js_undefined();
}
fn optional(s: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (v.nullish(value)) c.pi_js_undefined() else s.get(value, key);
}

pub fn cloudflareModel(s: *Scope, model: c.JSValue, environment: c.JSValue) !c.JSValue {
    if (!s.truthy(environment)) return model;
    const original = try s.get(model, "baseUrl");
    const replace_account = try s.get(original, "replaceAll");
    const account = try s.get(environment, "CLOUDFLARE_ACCOUNT_ID");
    const account_key = try s.text("{CLOUDFLARE_ACCOUNT_ID}");
    const first = try s.call(replace_account, original, &.{ account_key, if (v.nullish(account)) account_key else account });
    const replace_gateway = try s.get(first, "replaceAll");
    const gateway = try s.get(environment, "CLOUDFLARE_GATEWAY_ID");
    const gateway_key = try s.text("{CLOUDFLARE_GATEWAY_ID}");
    const base = try s.call(replace_gateway, first, &.{ gateway_key, if (v.nullish(gateway)) gateway_key else gateway });
    if (s.equal(base, try s.get(model, "baseUrl"))) return model;
    const changed = try s.own(try v.js.spread(s.engine, model));
    try s.put(changed, "baseUrl", base);
    return changed;
}
fn hasSessionHeader(s: *Scope, headers: c.JSValue) !bool {
    const expected = try s.invoke(try s.text("x-opencode-session"), "toLowerCase", &.{});
    const object = try s.global("Object");
    const keys = try s.get(object, "keys");
    const names = try s.call(keys, object, &.{if (v.nullish(headers)) try s.object() else headers});
    const some = try s.get(names, "some");
    const Match = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            return c.JS_NewBool(engine.context, local.equal(try local.invoke(argument(args, 0), "toLowerCase", &.{}), roots[0]));
        }
    };
    const predicate = try s.own(try functions.createArrow(s.engine, "", 1, Match.call, &.{expected}));
    return s.truthy(try s.call(some, names, &.{predicate}));
}
pub fn sessionOptions(s: *Scope, options: c.JSValue) !c.JSValue {
    if (!s.truthy(try optional(s, options, "sessionId")) or try hasSessionHeader(s, try s.get(options, "headers"))) return options;
    const changed = try s.own(try v.js.spread(s.engine, options));
    const headers = try s.own(try v.js.spread(s.engine, try s.get(options, "headers")));
    try s.put(headers, "x-opencode-session", try s.get(options, "sessionId"));
    try s.put(changed, "headers", headers);
    return changed;
}
pub fn streams(engine: *v.em.Engine, kind: Kind, original: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const wrapped = if (kind == .opencode) try s.own(try v.js.spread(engine, original)) else try s.object();
    inline for (.{ "stream", "streamSimple" }) |method| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                const callback = try local.get(roots[0], method);
                var n: i32 = 0;
                if (c.JS_ToInt32(host.context, &n, roots[1]) < 0) return v.js.capture(host);
                const model = argument(args, 0);
                const context = argument(args, 1);
                const options = argument(args, 2);
                return if (@as(Kind, @enumFromInt(n)) == .cloudflare)
                    v.js.call(host, callback, roots[0], &.{ try cloudflareModel(&local, model, try optional(&local, options, "env")), context, options })
                else
                    v.js.call(host, callback, roots[0], &.{ model, context, try sessionOptions(&local, options) });
            }
        };
        try s.put(wrapped, method, try s.own(try functions.createArrow(engine, method, 3, Adapter.call, &.{ original, c.JS_NewInt32(engine.context, @intFromEnum(kind)) })));
    }
    return c.JS_DupValue(engine.context, wrapped);
}
pub fn classifier(engine: *v.em.Engine, original: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const callback = try local.get(roots[0], "classify");
            return v.js.call(host, callback, roots[0], &.{ try cloudflareModel(&local, argument(args, 0), try optional(&local, argument(args, 2), "env")), argument(args, 1), argument(args, 2) });
        }
    };
    const wrapped = try s.object();
    try s.put(wrapped, "classify", try s.own(try functions.createArrow(engine, "classify", 3, Adapter.call, &.{original})));
    return c.JS_DupValue(engine.context, wrapped);
}
pub fn filter(engine: *v.em.Engine, copilot: bool) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var s: Scope = .{ .engine = host };
            defer s.deinit();
            const models = argument(args, 0);
            const credential = argument(args, 1);
            if (!(try v.eq(&s, try optional(&s, credential, "type"), "oauth"))) return c.JS_DupValue(host.context, models);
            const github = s.truthy(roots[0]);
            var available = c.pi_js_undefined();
            if (github) {
                const ids = try s.get(credential, "availableModelIds");
                if (!s.truthy(try s.invoke(try s.global("Array"), "isArray", &.{ids}))) return c.JS_DupValue(host.context, models);
                const Every = struct {
                    fn call(e: *v.em.Engine, _: c.JSValue, values: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                        return c.JS_NewBool(e.context, c.JS_IsString(argument(values, 0)));
                    }
                };
                const every = try s.get(ids, "every");
                const strings = try s.own(try functions.createArrow(host, "", 1, Every.call, &.{}));
                if (!s.truthy(try s.call(every, ids, &.{strings}))) return c.JS_DupValue(host.context, models);
                available = try s.own(try v.js.builtin(host, "Set", &.{ids}));
            }
            const method = try s.get(models, "filter");
            const Select = struct {
                fn call(e: *v.em.Engine, _: c.JSValue, values: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
                    var local: Scope = .{ .engine = e };
                    defer local.deinit();
                    const model = argument(values, 0);
                    if (local.truthy(captures[0])) {
                        const has = try local.get(captures[1], "has");
                        return v.js.call(e, has, captures[1], &.{try local.get(model, "id")});
                    }
                    const raw = try local.get(model, "type");
                    const kind = if (v.nullish(raw)) try local.text("chat") else raw;
                    return c.JS_NewBool(e.context, !(try v.eq(&local, kind, "classifier")));
                }
            };
            const predicate = try s.own(try functions.createArrow(host, "", 1, Select.call, &.{ roots[0], available }));
            return v.js.call(host, method, models, &.{predicate});
        }
    };
    return functions.createArrow(engine, if (copilot) "filterModels" else "filterAllModels", 2, Adapter.call, &.{c.JS_NewBool(engine.context, copilot)});
}

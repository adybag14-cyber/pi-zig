//! Azure provider's separate endpoint/deployment wrappers. The Responses config
//! helper also resolves API version; this Source path must not read that option.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const flow = @import("native_agent_async.zig");
const helpers = @import("native_ai_auth_helpers.zig");
fn arg(args: []const c.JSValue, n: usize) c.JSValue {
    return if (n < args.len) args[n] else c.pi_js_undefined();
}
fn opt(s: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (v.nullish(value)) c.pi_js_undefined() else s.get(value, name);
}
fn regex(s: *Scope, pattern: []const u8) !c.JSValue {
    var values = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, values.len, &values)));
}
fn env(s: *Scope, lookup: c.JSValue, options: c.JSValue, name: []const u8) !c.JSValue {
    return s.call(lookup, c.pi_js_undefined(), &.{ try s.text(name), try opt(s, options, "env") });
}
fn throwMessage(s: *Scope, message: c.JSValue) !void {
    var values = [_]c.JSValue{message};
    _ = try s.engine.checked(c.JS_Throw(s.engine.context, try s.engine.checked(c.JS_CallConstructor(s.engine.context, try s.global("Error"), values.len, &values))));
    unreachable;
}
pub fn baseUrl(s: *Scope, lookup: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const supplied = try opt(s, options, "azureBaseUrl");
    var base = if (v.nullish(supplied)) c.pi_js_undefined() else try s.invoke(supplied, "trim", &.{});
    if (!s.truthy(base)) {
        const value = try env(s, lookup, options, "AZURE_OPENAI_BASE_URL");
        base = if (v.nullish(value)) c.pi_js_undefined() else try s.invoke(value, "trim", &.{});
    }
    const supplied_resource = try opt(s, options, "azureResourceName");
    const resource = if (s.truthy(supplied_resource)) supplied_resource else try env(s, lookup, options, "AZURE_OPENAI_RESOURCE_NAME");
    if (!s.truthy(base) and s.truthy(resource)) base = try s.concat(try s.concat(try s.text("https://"), try s.stringify(resource)), try s.text(".openai.azure.com/openai/v1"));
    if (!s.truthy(base) and s.truthy(try s.get(model, "baseUrl"))) base = try s.get(model, "baseUrl");
    if (!s.truthy(base)) {
        try throwMessage(s, try s.text("Azure OpenAI base URL is required. Set AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME, or pass azureBaseUrl, azureResourceName, or model.baseUrl."));
        unreachable;
    }
    const trimmed = try s.invoke(try s.invoke(base, "trim", &.{}), "replace", &.{ try regex(s, "/+$"), try s.text("") });
    const generation = s.engine.native_allocation_generation;
    const url = try s.own(v.js.builtin(s.engine, "URL", &.{trimmed}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        const constructor = try s.global("Error");
        const message = try s.concat(try s.text("Invalid Azure OpenAI base URL: "), try s.stringify(base));
        var values = [_]c.JSValue{message};
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, values.len, &values))));
        unreachable;
    });
    const azure = s.truthy(try s.invoke(try s.get(url, "hostname"), "endsWith", &.{try s.text(".openai.azure.com")})) or s.truthy(try s.invoke(try s.get(url, "hostname"), "endsWith", &.{try s.text(".cognitiveservices.azure.com")})) or s.truthy(try s.invoke(try s.get(url, "hostname"), "endsWith", &.{try s.text(".ai.azure.com")}));
    const path = try s.invoke(try s.get(url, "pathname"), "replace", &.{ try regex(s, "/+$"), try s.text("") });
    if (azure and (try v.eq(s, path, "") or try v.eq(s, path, "/") or try v.eq(s, path, "/openai") or try v.eq(s, path, "/openai/v1/responses"))) {
        try s.set(url, "pathname", try s.text("/openai/v1"));
        try s.set(url, "search", try s.text(""));
    }
    return s.invoke(try s.invoke(url, "toString", &.{}), "replace", &.{ try regex(s, "/+$"), try s.text("") });
}
pub fn deployment(s: *Scope, lookup: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    if (s.truthy(try opt(s, options, "azureDeploymentName"))) return opt(s, options, "azureDeploymentName");
    const raw = try env(s, lookup, options, "AZURE_OPENAI_DEPLOYMENT_NAME_MAP");
    const map = try s.own(try v.js.builtin(s.engine, "Map", &.{}));
    if (s.truthy(raw)) {
        var entries = try v.iterator(s, try s.invoke(raw, "split", &.{try s.text(",")}));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer s.engine.freeValue(entry);
            const trimmed = try s.invoke(entry, "trim", &.{});
            if (!s.truthy(trimmed)) continue;
            var parts = try v.iterator(s, try s.invoke(trimmed, "split", &.{ try s.text("="), c.JS_NewInt32(s.engine.context, 2) }));
            defer parts.deinit();
            errdefer parts.closePreserving();
            const model_id = try s.own((try parts.next()) orelse c.pi_js_undefined());
            const name = try s.own((try parts.next()) orelse c.pi_js_undefined());
            try parts.close();
            if (!s.truthy(model_id) or !s.truthy(name)) continue;
            const set = try s.get(map, "set");
            _ = try s.call(set, map, &.{ try s.invoke(model_id, "trim", &.{}), try s.invoke(name, "trim", &.{}) });
        }
    }
    const get = try s.get(map, "get");
    const mapped = try s.call(get, map, &.{try s.get(model, "id")});
    return if (s.truthy(mapped)) mapped else s.get(model, "id");
}
fn optionsFor(s: *Scope, lookup: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const name = try deployment(s, lookup, model, options);
    if (s.equal(name, try s.get(model, "id"))) return options;
    const changed = try s.own(try v.js.spread(s.engine, options));
    const Payload = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const pending = try flow.create(engine, c.pi_js_undefined());
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            start(&local, pending.owner, args, roots) catch |err| try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        }
        fn start(local: *Scope, owner: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !void {
            const params = try local.own(try v.js.spread(local.engine, arg(args, 0)));
            try local.put(params, "model", roots[1]);
            try local.put(owner, "params", params);
            const callback = try opt(local, roots[0], "onPayload");
            const value = if (v.nullish(callback)) c.pi_js_undefined() else try local.call(callback, roots[0], &.{ params, arg(args, 1) });
            return flow.wait(ready, local.engine, owner, value, 0);
        }
        fn ready(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
            if (rejected) return flow.settle(engine, owner, true, value);
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            return flow.settle(engine, owner, false, if (v.nullish(value)) try local.get(owner, "params") else value);
        }
    };
    try s.put(changed, "onPayload", try s.own(try helpers.asyncArrow(s.engine, "onPayload", 2, Payload.call, &.{ options, name })));
    return changed;
}
pub fn streams(engine: *v.em.Engine, original: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const lookup = try s.own(try @import("native_provider_env.zig").create(engine));
    const wrapped = try s.object();
    inline for (.{ "stream", "streamSimple" }) |method| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                const state = try local.object();
                inline for (.{ "model", "context", "options" }, 0..) |name, n| try local.put(state, name, arg(args, n));
                const setup = try local.own(try helpers.asyncArrow(host, "", 0, begin, &.{ roots[0], roots[1], state }));
                return @import("native_ai_lazy_api.zig").lazyStream(host, arg(args, 0), setup);
            }
            fn begin(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var local: Scope = .{ .engine = host };
                defer local.deinit();
                const pending = try flow.create(host, c.pi_js_undefined());
                defer host.freeValue(pending.owner);
                errdefer host.freeValue(pending.promise);
                start(&local, pending.owner, roots) catch |err| try flow.rejectError(host, pending.owner, err);
                return pending.promise;
            }
            fn start(local: *Scope, owner: c.JSValue, roots: []const c.JSValue) !void {
                const callback = try local.get(roots[0], method);
                const model = try local.get(roots[2], "model");
                const options = try local.get(roots[2], "options");
                const resolved_model = try local.own(try v.js.spread(local.engine, model));
                try local.put(resolved_model, "baseUrl", try baseUrl(local, roots[1], model, options));
                const value = try local.call(callback, roots[0], &.{ resolved_model, try local.get(roots[2], "context"), try optionsFor(local, roots[1], model, options) });
                return flow.settle(local.engine, owner, false, value);
            }
        };
        try s.put(wrapped, method, try s.own(try functions.createArrow(engine, method, 3, Adapter.call, &.{ original, lookup })));
    }
    return c.JS_DupValue(engine.context, wrapped);
}

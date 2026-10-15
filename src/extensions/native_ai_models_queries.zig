//! Source ModelsImpl synchronous bodies. All receiver fields and methods stay
//! live; this module does not bind a hidden provider registry to an instance.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
pub const Kind = enum { setProvider, deleteProvider, clearProviders, getProviders, getProvider, getModels, getAllModels, getModelsOfType, getModel, getModelOfType, supersedeProviderRefresh, beginProviderRefresh, requireProvider, requireChatProvider };

fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
pub fn create(engine: *v.em.Engine, comptime kind: Kind, models_error: c.JSValue, operations: c.JSValue) !c.JSValue {
    const Handler = struct {
        fn call(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return invoke(host, kind, receiver, args, roots[0], roots[1]);
        }
    };
    return functions.createMethod(engine, @tagName(kind), switch (kind) {
        .clearProviders, .getProviders => 0,
        .getModelsOfType, .getModel => 2,
        .getModelOfType => 3,
        else => 1,
    }, Handler.call, &.{ models_error, operations });
}
fn fieldCall(s: *Scope, receiver: c.JSValue, field: [*:0]const u8, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.invoke(try s.get(receiver, field), method, args);
}
fn collectInto(s: *Scope, target: c.JSValue, value: c.JSValue) !void {
    var iterator = try v.iterator(s, value);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer s.engine.freeValue(item);
        const ignored = try s.invoke(target, "push", &.{item});
        _ = ignored;
    }
}
fn providerModels(s: *Scope, provider: c.JSValue, all: bool) !c.JSValue {
    if (!all) return s.invoke(provider, "getModels", &.{});
    const get_all = try s.get(provider, "getAllModels");
    const preferred = if (v.nullish(get_all)) c.pi_js_undefined() else try s.call(get_all, provider, &.{});
    return if (v.nullish(preferred)) s.invoke(provider, "getModels", &.{}) else preferred;
}
fn catalogs(s: *Scope, receiver: c.JSValue, provider_id: c.JSValue, all: bool) !c.JSValue {
    if (!c.JS_IsUndefined(provider_id)) {
        const provider = try fieldCall(s, receiver, "providers", "get", &.{provider_id});
        if (!s.truthy(provider)) return s.array();
        const generation = s.engine.native_allocation_generation;
        return providerModels(s, provider, all) catch |err| {
            try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
            return s.array();
        };
    }
    const result = try s.array();
    var iterator = try v.iterator(s, try fieldCall(s, receiver, "providers", "values", &.{}));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |provider| {
        defer s.engine.freeValue(provider);
        var row: Scope = .{ .engine = s.engine };
        defer row.deinit();
        const generation = s.engine.native_allocation_generation;
        appendProvider(&row, result, provider, all) catch |err| try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
    }
    return result;
}
fn appendProvider(s: *Scope, result: c.JSValue, provider: c.JSValue, all: bool) !void {
    const push = try s.get(result, "push");
    const values = try providerModels(s, provider, all);
    const arguments = try s.own(try v.js.collect(s.engine, values, try s.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)))));
    var supplied: @import("std").ArrayList(c.JSValue) = .empty;
    defer supplied.deinit(s.engine.gpa);
    for (0..try v.length(s, arguments)) |index| try supplied.append(s.engine.gpa, try v.at(s, arguments, @intCast(index)));
    _ = try s.call(push, result, supplied.items);
}
pub fn invoke(engine: *v.em.Engine, comptime kind: Kind, receiver: c.JSValue, args: []const c.JSValue, models_error: c.JSValue, operations: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const first = arg(args, 0);
    switch (kind) {
        .setProvider => {
            _ = try s.invoke(receiver, "supersedeProviderRefresh", &.{try s.get(first, "id")});
            const providers = try s.get(receiver, "providers");
            const set = try s.get(providers, "set");
            _ = try s.call(set, providers, &.{ try s.get(first, "id"), first });
        },
        .deleteProvider => {
            _ = try s.invoke(receiver, "supersedeProviderRefresh", &.{first});
            _ = try fieldCall(&s, receiver, "providers", "delete", &.{first});
        },
        .clearProviders => {
            const set_constructor = try s.global("Set");
            const ids = try s.array();
            try collectInto(&s, ids, try fieldCall(&s, receiver, "providers", "keys", &.{}));
            try collectInto(&s, ids, try fieldCall(&s, receiver, "refreshControllers", "keys", &.{}));
            const unique = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, 1, @constCast(&[_]c.JSValue{ids}))));
            var iterator = try v.iterator(&s, unique);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |id| {
                defer engine.freeValue(id);
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                _ = try row.invoke(receiver, "supersedeProviderRefresh", &.{id});
            }
            _ = try fieldCall(&s, receiver, "providers", "clear", &.{});
        },
        .getProviders => return c.JS_DupValue(engine.context, try s.invoke(try s.global("Array"), "from", &.{try fieldCall(&s, receiver, "providers", "values", &.{})})),
        .getProvider => return c.JS_DupValue(engine.context, try fieldCall(&s, receiver, "providers", "get", &.{first})),
        .getModels, .getAllModels => return c.JS_DupValue(engine.context, try catalogs(&s, receiver, first, kind == .getAllModels)),
        .getModelsOfType => {
            const Predicate = struct {
                fn call(host: *v.em.Engine, _: c.JSValue, values: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                    return v.js.call(host, roots[0], c.pi_js_undefined(), &.{ arg(values, 0), roots[1] });
                }
            };
            const models = try s.invoke(receiver, "getAllModels", &.{arg(args, 1)});
            const predicate = try s.own(try functions.createArrow(engine, "", 1, Predicate.call, &.{ try s.get(operations, "isModelType"), first }));
            return c.JS_DupValue(engine.context, try s.invoke(models, "filter", &.{predicate}));
        },
        .getModel, .getModelOfType => {
            const models = if (kind == .getModel) try s.invoke(receiver, "getModels", &.{first}) else try s.invoke(receiver, "getModelsOfType", &.{ first, arg(args, 1) });
            const Find = struct {
                fn call(host: *v.em.Engine, _: c.JSValue, values: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                    const id = try v.js.get(host, arg(values, 0), "id");
                    defer host.freeValue(id);
                    return c.JS_NewBool(host.context, c.JS_IsStrictEqual(host.context, id, roots[0]));
                }
            };
            const predicate = try s.own(try functions.createArrow(engine, "", 1, Find.call, &.{arg(args, if (kind == .getModel) 1 else 2)}));
            return c.JS_DupValue(engine.context, try s.invoke(models, "find", &.{predicate}));
        },
        .supersedeProviderRefresh => {
            const old = try fieldCall(&s, receiver, "refreshGenerations", "get", &.{first});
            const generation = try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, if (v.nullish(old)) c.JS_NewInt32(engine.context, 0) else old, c.JS_NewInt32(engine.context, 1))));
            _ = try fieldCall(&s, receiver, "refreshGenerations", "set", &.{ first, generation });
            const previous = try fieldCall(&s, receiver, "refreshControllers", "get", &.{first});
            if (s.truthy(previous)) {
                _ = try fieldCall(&s, receiver, "refreshControllers", "delete", &.{first});
                _ = try s.invoke(previous, "abort", &.{});
            }
            return c.JS_DupValue(engine.context, generation);
        },
        .beginProviderRefresh => {
            const generation = try s.invoke(receiver, "supersedeProviderRefresh", &.{first});
            const controller = try s.own(try v.js.builtin(engine, "AbortController", &.{}));
            _ = try fieldCall(&s, receiver, "refreshControllers", "set", &.{ first, controller });
            const result = try s.object();
            try s.put(result, "generation", generation);
            try s.put(result, "controller", controller);
            return c.JS_DupValue(engine.context, result);
        },
        .requireChatProvider => {
            _ = try s.call(try s.get(operations, "assertChatModel"), c.pi_js_undefined(), &.{first});
            return c.JS_DupValue(engine.context, try s.invoke(receiver, "requireProvider", &.{first}));
        },
        .requireProvider => {
            const provider = try fieldCall(&s, receiver, "providers", "get", &.{try s.get(first, "provider")});
            if (s.truthy(provider)) return c.JS_DupValue(engine.context, provider);
            const name = try s.own(try engine.checked(c.JS_ToString(engine.context, try s.get(first, "provider"))));
            const message = try s.concat(try s.text("Unknown provider: "), name);
            const error_arguments = [_]c.JSValue{ try s.text("provider"), message };
            const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, models_error, error_arguments.len, @constCast(&error_arguments))));
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        },
    }
    return c.pi_js_undefined();
}

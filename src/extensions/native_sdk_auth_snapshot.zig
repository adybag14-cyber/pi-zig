//! Cached public authentication status. Getters never perform credential I/O.
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub const Query = enum { configured, status, oauth, subscription, err, registered_ids, registered_native };
pub fn collection(engine: *engine_mod.Engine, kind: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, kind);
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
pub fn initialize(engine: *engine_mod.Engine, data: c.JSValue) !void {
    inline for (.{ "authSnapshot", "registeredNative", "registeredExtensions" }) |name| try sdk.put(engine, data, name, try collection(engine, "Map"));
    inline for (.{ "configuredProviders", "storedProviders" }) |name| try sdk.put(engine, data, name, try collection(engine, "Set"));
    try sdk.put(engine, data, "availabilityError", c.pi_js_undefined());
}
pub fn contains(engine: *engine_mod.Engine, data: c.JSValue, field: [*:0]const u8, id: c.JSValue) !bool {
    const set = try sdk.get(engine, data, field);
    defer engine.freeValue(set);
    const result = try sdk.invoke(engine, set, "has", &.{id});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 1;
}
pub fn query(engine: *engine_mod.Engine, data: c.JSValue, kind: Query, id: c.JSValue) !c.JSValue {
    if (kind == .configured) return c.pi_js_bool(engine.context, @intFromBool(try contains(engine, data, "configuredProviders", id)));
    if (kind == .err) {
        const errors = try sdk.array(engine);
        defer engine.freeValue(errors);
        const config = try sdk.get(engine, data, "modelConfig");
        defer engine.freeValue(config);
        if (c.JS_IsObject(config)) {
            const failure = try sdk.get(engine, config, "error");
            defer engine.freeValue(failure);
            if (c.JS_ToBool(engine.context, failure) == 1) try sdk.append(engine, errors, c.JS_DupValue(engine.context, failure));
        }
        const composition = try sdk.get(engine, data, "compositionErrors");
        defer engine.freeValue(composition);
        if (c.JS_IsObject(composition)) {
            const iterator = try sdk.invoke(engine, composition, "values", &.{});
            defer engine.freeValue(iterator);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const constructor = try sdk.get(engine, global, "Array");
            defer engine.freeValue(constructor);
            const messages = try sdk.invoke(engine, constructor, "from", &.{iterator});
            defer engine.freeValue(messages);
            for (0..try sdk.length(engine, messages)) |index| try sdk.append(engine, errors, try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index))));
        }
        const failure = try sdk.get(engine, data, "availabilityError");
        defer engine.freeValue(failure);
        if (!c.JS_IsUndefined(failure)) {
            const text = try engine.toString(failure);
            defer engine.gpa.free(text);
            const message = try @import("std").fmt.allocPrint(engine.gpa, "Availability refresh: {s}", .{text});
            defer engine.gpa.free(message);
            try sdk.append(engine, errors, try sdk.text(engine, message));
        }
        if (try sdk.length(engine, errors) == 0) return c.pi_js_undefined();
        const separator = try sdk.text(engine, "\n\n");
        defer engine.freeValue(separator);
        return sdk.invoke(engine, errors, "join", &.{separator});
    }
    if (kind == .registered_native) {
        const map = try sdk.get(engine, data, "registeredNative");
        defer engine.freeValue(map);
        return sdk.invoke(engine, map, "get", &.{id});
    }
    if (kind == .registered_ids) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const array = try sdk.get(engine, global, "Array");
        defer engine.freeValue(array);
        const set = try collection(engine, "Set");
        defer engine.freeValue(set);
        inline for (.{ "registeredExtensions", "registeredNative" }) |name| {
            const map = try sdk.get(engine, data, name);
            defer engine.freeValue(map);
            const iterator = try sdk.invoke(engine, map, "keys", &.{});
            defer engine.freeValue(iterator);
            const keys = try sdk.invoke(engine, array, "from", &.{iterator});
            defer engine.freeValue(keys);
            for (0..try sdk.length(engine, keys)) |index| {
                const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, keys, @intCast(index)));
                defer engine.freeValue(key);
                const ignored = try sdk.invoke(engine, set, "add", &.{key});
                engine.freeValue(ignored);
            }
        }
        return sdk.invoke(engine, array, "from", &.{set});
    }
    const auth = try sdk.get(engine, data, "authSnapshot");
    defer engine.freeValue(auth);
    const check = try sdk.invoke(engine, auth, "get", &.{id});
    defer engine.freeValue(check);
    if (kind == .status) {
        const value = try sdk.object(engine);
        errdefer engine.freeValue(value);
        const keys = try sdk.get(engine, data, "keys");
        defer engine.freeValue(keys);
        const key = try @import("native_sdk_models.zig").property(engine, keys, id);
        defer engine.freeValue(key);
        if (c.JS_IsUndefined(key) and !try contains(engine, data, "storedProviders", id)) {
            if (try @import("native_sdk_provider_composer.zig").configuredStatus(engine, data, id)) |status| {
                engine.freeValue(value);
                return status;
            }
        }
        const source: ?[]const u8 = if (!c.JS_IsUndefined(key)) "runtime" else if (try contains(engine, data, "storedProviders", id)) "stored" else if (c.JS_IsObject(check)) "environment" else null;
        try sdk.put(engine, value, "configured", c.pi_js_bool(engine.context, @intFromBool(source != null)));
        if (source) |label| {
            try sdk.put(engine, value, "source", try sdk.text(engine, label));
            if (@import("std").mem.eql(u8, label, "environment")) try sdk.put(engine, value, "label", try sdk.get(engine, check, "source"));
        }
        return value;
    }
    const type_value = if (c.JS_IsObject(check)) try sdk.get(engine, check, "type") else c.pi_js_undefined();
    defer engine.freeValue(type_value);
    const oauth = try sdk.text(engine, "oauth");
    defer engine.freeValue(oauth);
    const using_oauth = c.JS_IsStrictEqual(engine.context, type_value, oauth);
    if (kind == .oauth or !using_oauth) return c.pi_js_bool(engine.context, @intFromBool(using_oauth));
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const provider = try sdk.invoke(engine, catalog, "getProvider", &.{id});
    defer engine.freeValue(provider);
    if (!c.JS_IsObject(provider)) return c.pi_js_bool(engine.context, 0);
    const handlers = try sdk.get(engine, provider, "auth");
    defer engine.freeValue(handlers);
    const handler = try sdk.get(engine, handlers, "oauth");
    defer engine.freeValue(handler);
    const subscribed = if (c.JS_IsObject(handler)) try sdk.get(engine, handler, "isSubscription") else c.pi_js_undefined();
    defer engine.freeValue(subscribed);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsBool(subscribed) and c.JS_ToBool(engine.context, subscribed) == 1));
}
pub fn registered(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, provider: c.JSValue, native: bool, remove: bool) !void {
    inline for (.{ "registeredExtensions", "registeredNative" }) |name| {
        if (remove or !@import("std").mem.eql(u8, name, if (native) "registeredNative" else "registeredExtensions")) {
            const map = try sdk.get(engine, data, name);
            defer engine.freeValue(map);
            const deleted = try sdk.invoke(engine, map, "delete", &.{id});
            engine.freeValue(deleted);
        }
    }
    if (!remove) {
        const map = try sdk.get(engine, data, if (native) "registeredNative" else "registeredExtensions");
        defer engine.freeValue(map);
        const effective = if (native) c.JS_DupValue(engine.context, provider) else try sdk.object(engine);
        defer engine.freeValue(effective);
        if (!native) {
            const previous = try sdk.invoke(engine, map, "get", &.{id});
            defer engine.freeValue(previous);
            try @import("native_sdk_models.zig").copy(engine, effective, previous);
            var names: [*c]c.JSPropertyEnum = null;
            var count: u32 = 0;
            if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, provider, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
            defer c.JS_FreePropertyEnum(engine.context, names, count);
            for (0..count) |index| {
                const value = try engine.checked(c.JS_GetProperty(engine.context, provider, names[index].atom));
                if (c.JS_IsUndefined(value)) {
                    engine.freeValue(value);
                    continue;
                }
                if (c.JS_DefinePropertyValue(engine.context, effective, names[index].atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            }
        }
        const ignored = try sdk.invoke(engine, map, "set", &.{ id, effective });
        engine.freeValue(ignored);
    }
}
pub fn updateModels(engine: *engine_mod.Engine, data: c.JSValue) !void {
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const all = try sdk.invoke(engine, catalog, "getModels", &.{});
    defer engine.freeValue(all);
    try sdk.put(engine, data, "allModelsSnapshot", c.JS_DupValue(engine.context, all));
    const available = try sdk.array(engine);
    defer engine.freeValue(available);
    for (0..try sdk.length(engine, all)) |index| {
        const model = try engine.checked(c.JS_GetPropertyUint32(engine.context, all, @intCast(index)));
        defer engine.freeValue(model);
        const id = try sdk.get(engine, model, "provider");
        defer engine.freeValue(id);
        if (try contains(engine, data, "configuredProviders", id)) try sdk.append(engine, available, c.JS_DupValue(engine.context, model));
    }
    try sdk.put(engine, data, "available", c.JS_DupValue(engine.context, available));
}
pub fn markProvisional(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, provider: c.JSValue) !void {
    const status = try @import("native_sdk_provider_composer.zig").configuredStatus(engine, data, id);
    defer if (status) |value| engine.freeValue(value);
    const configured_value = if (status) |value| try sdk.get(engine, value, "configured") else c.pi_js_undefined();
    defer engine.freeValue(configured_value);
    if (!try contains(engine, data, "storedProviders", id) and c.JS_ToBool(engine.context, configured_value) != 1) return;
    const configured = try sdk.get(engine, data, "configuredProviders");
    defer engine.freeValue(configured);
    const added = try sdk.invoke(engine, configured, "add", &.{id});
    engine.freeValue(added);
    const auth = try sdk.get(engine, data, "authSnapshot");
    defer engine.freeValue(auth);
    const existing = try sdk.invoke(engine, auth, "get", &.{id});
    defer engine.freeValue(existing);
    if (c.JS_ToBool(engine.context, existing) != 1) {
        const handlers = try sdk.get(engine, provider, "auth");
        defer engine.freeValue(handlers);
        const oauth = if (c.JS_IsObject(handlers)) try sdk.get(engine, handlers, "oauth") else c.pi_js_undefined();
        defer engine.freeValue(oauth);
        const api = if (c.JS_IsObject(handlers)) try sdk.get(engine, handlers, "apiKey") else c.pi_js_undefined();
        defer engine.freeValue(api);
        const check = try sdk.object(engine);
        defer engine.freeValue(check);
        try sdk.put(engine, check, "type", try sdk.text(engine, if (c.JS_ToBool(engine.context, oauth) == 1 and c.JS_ToBool(engine.context, api) != 1) "oauth" else "api_key"));
        try sdk.put(engine, check, "source", try sdk.text(engine, "configured provider"));
        const set = try sdk.invoke(engine, auth, "set", &.{ id, check });
        engine.freeValue(set);
    }
    const all = try sdk.get(engine, data, "allModelsSnapshot");
    defer engine.freeValue(all);
    const available = try sdk.array(engine);
    defer engine.freeValue(available);
    for (0..try sdk.length(engine, all)) |index| {
        const model = try engine.checked(c.JS_GetPropertyUint32(engine.context, all, @intCast(index)));
        defer engine.freeValue(model);
        const provider_id = try sdk.get(engine, model, "provider");
        defer engine.freeValue(provider_id);
        if (try contains(engine, data, "configuredProviders", provider_id)) try sdk.append(engine, available, c.JS_DupValue(engine.context, model));
    }
    try sdk.put(engine, data, "available", c.JS_DupValue(engine.context, available));
}
pub fn prepareProvider(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, check: c.JSValue, credential: c.JSValue) !c.JSValue {
    const next = try sdk.object(engine);
    errdefer engine.freeValue(next);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "authSnapshot", "Map" }, .{ "configuredProviders", "Set" }, .{ "storedProviders", "Set" } }) |entry| {
        const current = try sdk.get(engine, data, entry[0]);
        defer engine.freeValue(current);
        const constructor = try sdk.get(engine, global, entry[1]);
        defer engine.freeValue(constructor);
        var args = [_]c.JSValue{current};
        try sdk.put(engine, next, entry[0], try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args)));
    }
    const auth = try sdk.get(engine, next, "authSnapshot");
    defer engine.freeValue(auth);
    const configured = try sdk.get(engine, next, "configuredProviders");
    defer engine.freeValue(configured);
    const stored = try sdk.get(engine, next, "storedProviders");
    defer engine.freeValue(stored);
    const auth_result = if (!c.JS_IsUndefined(check)) try sdk.invoke(engine, auth, "set", &.{ id, check }) else try sdk.invoke(engine, auth, "delete", &.{id});
    engine.freeValue(auth_result);
    const configured_result = try sdk.invoke(engine, configured, if (!c.JS_IsUndefined(check)) "add" else "delete", &.{id});
    engine.freeValue(configured_result);
    const stored_result = try sdk.invoke(engine, stored, if (c.JS_IsObject(credential)) "add" else "delete", &.{id});
    engine.freeValue(stored_result);
    return next;
}

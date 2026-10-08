//! Virtual catalog entries and asynchronous routing stay on the engine owner.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const thinking = @import("../ai/thinking.zig");

fn reject(engine: *engine_mod.Engine, message: []const u8) error{ JavaScriptException, OutOfMemory } {
    const value = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(value);
    try sdk.put(engine, value, "message", try sdk.text(engine, message));
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    return error.JavaScriptException;
}
pub fn isVirtual(engine: *engine_mod.Engine, model: c.JSValue) !bool {
    if (!c.JS_IsObject(model)) return false;
    const api = try sdk.get(engine, model, "api");
    defer engine.freeValue(api);
    const expected = try sdk.text(engine, "pi-virtual");
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, api, expected);
}
pub fn physical(engine: *engine_mod.Engine, data: c.JSValue, provider: c.JSValue, id: c.JSValue) !c.JSValue {
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const result = try sdk.invoke(engine, catalog, "getModel", &.{ provider, id });
    if (!try isVirtual(engine, result)) return result;
    engine.freeValue(result);
    return c.pi_js_undefined();
}
fn entries(engine: *engine_mod.Engine, data: c.JSValue, provider: c.JSValue) !c.JSValue {
    const map = try sdk.get(engine, data, "virtualModels");
    defer engine.freeValue(map);
    return sdk.invoke(engine, map, "get", &.{provider});
}
fn mapValues(engine: *engine_mod.Engine, map: c.JSValue) !c.JSValue {
    const iterator = try sdk.invoke(engine, map, "values", &.{});
    defer engine.freeValue(iterator);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.freeValue(array);
    return sdk.invoke(engine, array, "from", &.{iterator});
}
fn fallback(engine: *engine_mod.Engine, definition: c.JSValue, name: [*:0]const u8, default: c.JSValue) !c.JSValue {
    const value = try sdk.get(engine, definition, name);
    if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) return value;
    engine.freeValue(value);
    return c.JS_DupValue(engine.context, default);
}
fn catalogEntry(engine: *engine_mod.Engine, definition: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ "id", "name", "provider" }) |field| try sdk.put(engine, result, field, try sdk.get(engine, definition, field));
    try sdk.put(engine, result, "api", try sdk.text(engine, "pi-virtual"));
    try sdk.put(engine, result, "baseUrl", try sdk.text(engine, ""));
    const default_levels = try sdk.jsonObject(engine, "[\"off\"]");
    defer engine.freeValue(default_levels);
    const levels = try fallback(engine, definition, "thinkingLevels", default_levels);
    defer engine.freeValue(levels);
    const map = try sdk.object(engine);
    defer engine.freeValue(map);
    var reasoning = false;
    for (thinking.extended_levels) |level| {
        const name = try sdk.text(engine, @tagName(level));
        defer engine.freeValue(name);
        const included = try sdk.invoke(engine, levels, "includes", &.{name});
        defer engine.freeValue(included);
        const offered = c.JS_ToBool(engine.context, included) == 1;
        const key = try engine.gpa.dupeZ(u8, @tagName(level));
        defer engine.gpa.free(key);
        try sdk.put(engine, map, key, if (offered) c.JS_DupValue(engine.context, name) else c.pi_js_null());
        reasoning = reasoning or (offered and level != .off);
    }
    // An unknown offered level still makes the source entry reasoning-capable.
    const off = try sdk.text(engine, "off");
    defer engine.freeValue(off);
    for (0..try sdk.length(engine, levels)) |index| {
        const level = try engine.checked(c.JS_GetPropertyUint32(engine.context, levels, @intCast(index)));
        defer engine.freeValue(level);
        reasoning = reasoning or !c.JS_IsStrictEqual(engine.context, off, level);
    }
    try sdk.put(engine, result, "reasoning", c.pi_js_bool(engine.context, @intFromBool(reasoning)));
    try sdk.put(engine, result, "thinkingLevelMap", c.JS_DupValue(engine.context, map));
    const input = try sdk.jsonObject(engine, "[\"text\",\"image\"]");
    defer engine.freeValue(input);
    try sdk.put(engine, result, "input", try fallback(engine, definition, "input", input));
    try sdk.put(engine, result, "cost", try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}"));
    inline for (.{ "contextWindow", "maxTokens" }) |field| try sdk.put(engine, result, field, try fallback(engine, definition, field, c.JS_NewInt32(engine.context, 0)));
    return result;
}
pub fn register(engine: *engine_mod.Engine, runtime: c.JSValue, definition: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, runtime);
    const provider = try sdk.get(engine, definition, "provider");
    defer engine.freeValue(provider);
    const id = try sdk.get(engine, definition, "id");
    defer engine.freeValue(id);
    inline for (.{ provider, id }) |value| {
        const trimmed = try sdk.invoke(engine, value, "trim", &.{});
        defer engine.freeValue(trimmed);
        if (try sdk.length(engine, trimmed) == 0) return reject(engine, "Virtual model provider and id must not be empty.");
    }
    const existing = try physical(engine, owner.data, provider, id);
    defer engine.freeValue(existing);
    if (c.JS_IsObject(existing)) {
        const p = try engine.toString(provider);
        defer engine.gpa.free(p);
        const m = try engine.toString(id);
        defer engine.gpa.free(m);
        const message = try std.fmt.allocPrint(engine.gpa, "Virtual model {s}/{s} conflicts with a physical model.", .{ p, m });
        defer engine.gpa.free(message);
        return reject(engine, message);
    }
    const providers = try sdk.get(engine, owner.data, "virtualModels");
    defer engine.freeValue(providers);
    const previous = try entries(engine, owner.data, provider);
    defer engine.freeValue(previous);
    const records = if (c.JS_IsObject(previous)) c.JS_DupValue(engine.context, previous) else try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.freeValue(records);
    const record = try sdk.object(engine);
    defer engine.freeValue(record);
    try sdk.put(engine, record, "model", try catalogEntry(engine, definition));
    try sdk.put(engine, record, "definition", c.JS_DupValue(engine.context, definition));
    const stored = try sdk.invoke(engine, records, "set", &.{ id, record });
    engine.freeValue(stored);
    const attached = try sdk.invoke(engine, providers, "set", &.{ provider, records });
    engine.freeValue(attached);
    try @import("native_sdk_provider_composer.zig").recompose(engine, owner.data, provider);
    try @import("native_sdk_auth_snapshot.zig").updateModels(engine, owner.data);
    try @import("native_sdk_availability.zig").registrationRefresh(engine, runtime);
    return c.pi_js_undefined();
}
pub fn unregister(engine: *engine_mod.Engine, runtime: c.JSValue, provider: c.JSValue, id: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, runtime);
    const records = try entries(engine, owner.data, provider);
    defer engine.freeValue(records);
    if (!c.JS_IsObject(records)) return c.pi_js_undefined();
    const removed = try sdk.invoke(engine, records, "delete", &.{id});
    defer engine.freeValue(removed);
    if (c.JS_ToBool(engine.context, removed) != 1) return c.pi_js_undefined();
    const size = try sdk.get(engine, records, "size");
    defer engine.freeValue(size);
    var count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &count, size) < 0) return error.JavaScriptException;
    if (count == 0) {
        const map = try sdk.get(engine, owner.data, "virtualModels");
        defer engine.freeValue(map);
        const deleted = try sdk.invoke(engine, map, "delete", &.{provider});
        engine.freeValue(deleted);
    }
    try @import("native_sdk_provider_composer.zig").recompose(engine, owner.data, provider);
    try @import("native_sdk_auth_snapshot.zig").updateModels(engine, owner.data);
    try @import("native_sdk_availability.zig").registrationRefresh(engine, runtime);
    return c.pi_js_undefined();
}
const ProviderMethod = enum(c_int) { chat, all, filter_chat, filter_all, stream, stream_simple, resolve };
fn providerFunction(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, method: ProviderMethod, state: c.JSValue) !void {
    var capture = [_]c.JSValue{state};
    try sdk.put(engine, target, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, providerCallback, name, 2, @intFromEnum(method), 1, &capture)));
}
fn providerCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, capture: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return providerCall(engine, capture[0], @enumFromInt(magic), if (argc > 0) args[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn partition(engine: *engine_mod.Engine, rows: c.JSValue, virtual: bool, ids: c.JSValue) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const is_virtual = try isVirtual(engine, row);
        if (virtual != is_virtual) continue;
        if (!virtual) {
            const kind = try sdk.get(engine, row, "type");
            defer engine.freeValue(kind);
            const chat = try sdk.text(engine, "chat");
            defer engine.freeValue(chat);
            if (c.JS_IsUndefined(kind) or c.JS_IsStrictEqual(engine.context, kind, chat)) {
                const id = try sdk.get(engine, row, "id");
                defer engine.freeValue(id);
                const hidden = try sdk.invoke(engine, ids, "includes", &.{id});
                defer engine.freeValue(hidden);
                if (c.JS_ToBool(engine.context, hidden) == 1) continue;
            }
        }
        try sdk.append(engine, result, c.JS_DupValue(engine.context, row));
    }
    return result;
}
fn appendRows(engine: *engine_mod.Engine, target: c.JSValue, rows: c.JSValue) !void {
    for (0..try sdk.length(engine, rows)) |index| try sdk.append(engine, target, try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index))));
}
fn providerCall(engine: *engine_mod.Engine, state: c.JSValue, method: ProviderMethod, args: []const c.JSValue) !c.JSValue {
    if (method == .resolve) {
        const result = try sdk.jsonObject(engine, "{\"auth\":{},\"source\":\"virtual\"}");
        defer engine.freeValue(result);
        return sdk.promise(engine, result);
    }
    const base = try sdk.get(engine, state, "base");
    defer engine.freeValue(base);
    if (method == .stream or method == .stream_simple) {
        if (args.len == 0) return error.NativeSDKMissingArgument;
        if (try isVirtual(engine, args[0])) {
            const provider = try sdk.get(engine, args[0], "provider");
            defer engine.freeValue(provider);
            const id = try sdk.get(engine, args[0], "id");
            defer engine.freeValue(id);
            const p = try engine.toString(provider);
            defer engine.gpa.free(p);
            const m = try engine.toString(id);
            defer engine.gpa.free(m);
            const message = try std.fmt.allocPrint(engine.gpa, "Virtual model {s}/{s} must be routed before streaming", .{ p, m });
            defer engine.gpa.free(message);
            return reject(engine, message);
        }
        return sdk.invoke(engine, base, if (method == .stream) "stream" else "streamSimple", args);
    }
    const ids = try sdk.get(engine, state, "ids");
    defer engine.freeValue(ids);
    if (method == .chat or method == .all) {
        const getter = if (c.JS_IsObject(base)) try sdk.get(engine, base, "getAllModels") else c.pi_js_undefined();
        defer engine.freeValue(getter);
        const raw = if (c.JS_IsObject(base)) try sdk.invoke(engine, base, if (method == .all and c.JS_IsFunction(engine.context, getter)) "getAllModels" else "getModels", &.{}) else try sdk.array(engine);
        defer engine.freeValue(raw);
        const result = try partition(engine, raw, false, ids);
        errdefer engine.freeValue(result);
        const rows = try sdk.get(engine, state, "rows");
        defer engine.freeValue(rows);
        try appendRows(engine, result, rows);
        return result;
    }
    if (args.len == 0) return error.NativeSDKMissingArgument;
    const real = try partition(engine, args[0], false, ids);
    defer engine.freeValue(real);
    const filter = if (c.JS_IsObject(base)) try sdk.get(engine, base, if (method == .filter_all) "filterAllModels" else "filterModels") else c.pi_js_undefined();
    defer engine.freeValue(filter);
    const filtered = if (c.JS_IsFunction(engine.context, filter)) try engine.checked(c.JS_Call(engine.context, filter, base, 2, @constCast(&[_]c.JSValue{ real, if (args.len > 1) args[1] else c.pi_js_undefined() }))) else c.JS_DupValue(engine.context, real);
    defer engine.freeValue(filtered);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    try appendRows(engine, result, filtered);
    const virtual = try partition(engine, args[0], true, ids);
    defer engine.freeValue(virtual);
    try appendRows(engine, result, virtual);
    return result;
}
pub fn withModels(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, base: c.JSValue) !c.JSValue {
    const records = try entries(engine, data, id);
    defer engine.freeValue(records);
    if (!c.JS_IsObject(records)) return c.JS_DupValue(engine.context, base);
    const values = try mapValues(engine, records);
    defer engine.freeValue(values);
    if (try sdk.length(engine, values) == 0) return c.JS_DupValue(engine.context, base);
    const state = try sdk.object(engine);
    defer engine.freeValue(state);
    try sdk.put(engine, state, "base", c.JS_DupValue(engine.context, base));
    const rows = try sdk.array(engine);
    defer engine.freeValue(rows);
    const ids = try sdk.array(engine);
    defer engine.freeValue(ids);
    for (0..try sdk.length(engine, values)) |index| {
        const record = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
        defer engine.freeValue(record);
        const model = try sdk.get(engine, record, "model");
        defer engine.freeValue(model);
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, model));
        try sdk.append(engine, ids, try sdk.get(engine, model, "id"));
    }
    try sdk.put(engine, state, "rows", c.JS_DupValue(engine.context, rows));
    try sdk.put(engine, state, "ids", c.JS_DupValue(engine.context, ids));
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try models.copy(engine, result, base);
    try sdk.put(engine, result, "id", c.JS_DupValue(engine.context, id));
    try providerFunction(engine, result, "getModels", .chat, state);
    try providerFunction(engine, result, "getAllModels", .all, state);
    try providerFunction(engine, result, "stream", .stream, state);
    try providerFunction(engine, result, "streamSimple", .stream_simple, state);
    if (c.JS_IsObject(base)) {
        try providerFunction(engine, result, "filterModels", .filter_chat, state);
        const all = try sdk.get(engine, base, "filterAllModels");
        defer engine.freeValue(all);
        if (c.JS_ToBool(engine.context, all) == 1) try providerFunction(engine, result, "filterAllModels", .filter_all, state);
    } else {
        try sdk.put(engine, result, "name", c.JS_DupValue(engine.context, id));
        const authentication = try sdk.object(engine);
        defer engine.freeValue(authentication);
        const key = try sdk.object(engine);
        defer engine.freeValue(key);
        try sdk.put(engine, key, "name", try sdk.text(engine, "Virtual model"));
        try providerFunction(engine, key, "resolve", .resolve, state);
        try sdk.put(engine, authentication, "apiKey", c.JS_DupValue(engine.context, key));
        try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, authentication));
        if (!try @import("native_sdk_auth_snapshot.zig").contains(engine, data, "configuredProviders", id)) {
            const configured = try sdk.get(engine, data, "configuredProviders");
            defer engine.freeValue(configured);
            const added = try sdk.invoke(engine, configured, "add", &.{id});
            engine.freeValue(added);
            const auth = try sdk.get(engine, data, "authSnapshot");
            defer engine.freeValue(auth);
            const check = try sdk.jsonObject(engine, "{\"type\":\"api_key\",\"source\":\"virtual\"}");
            defer engine.freeValue(check);
            const stored = try sdk.invoke(engine, auth, "set", &.{ id, check });
            engine.freeValue(stored);
        }
    }
    return result;
}
fn function(engine: *engine_mod.Engine, job: c.JSValue, finish: bool) !c.JSValue {
    var capture = [_]c.JSValue{job};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, resolveCallback, "sdkVirtualRoute", 1, @intFromBool(finish), 1, &capture));
}
fn resolveCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, finish: c_int, capture: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return advance(engine, capture[0], finish != 0, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
pub fn resolve(engine: *engine_mod.Engine, data: c.JSValue, model: c.JSValue, messages: c.JSValue, options: c.JSValue) !c.JSValue {
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    inline for (.{ .{ "data", data }, .{ "model", model }, .{ "messages", messages }, .{ "options", options } }) |field| try sdk.put(engine, job, field[0], c.JS_DupValue(engine.context, field[1]));
    // An async source method invokes the router before returning its Promise.
    // Preserve that reentry point while converting synchronous failures into
    // Promise rejections with their original exception identity.
    return advance(engine, job, false, c.pi_js_undefined()) catch |err| {
        _ = sdk.fail(engine, err);
        const failure = c.JS_GetException(engine.context);
        defer engine.freeValue(failure);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try sdk.get(engine, global, "Promise");
        defer engine.freeValue(constructor);
        return sdk.invoke(engine, constructor, "reject", &.{failure});
    };
}
fn response(engine: *engine_mod.Engine, data: c.JSValue, message: c.JSValue, failed: bool) !c.JSValue {
    if (!c.JS_IsObject(message)) return c.pi_js_undefined();
    const provider = try sdk.get(engine, message, "provider");
    defer engine.freeValue(provider);
    const id = try sdk.get(engine, message, "model");
    defer engine.freeValue(id);
    const model = try physical(engine, data, provider, id);
    defer engine.freeValue(model);
    if (!c.JS_IsObject(model)) return c.pi_js_undefined();
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "model", c.JS_DupValue(engine.context, model));
    try sdk.put(engine, result, "thinkingLevel", try sdk.get(engine, message, "thinkingLevel"));
    if (failed) try sdk.put(engine, result, "message", c.JS_DupValue(engine.context, message));
    return result;
}
fn advance(engine: *engine_mod.Engine, job: c.JSValue, finish: bool, value: c.JSValue) !c.JSValue {
    const data = try sdk.get(engine, job, "data");
    defer engine.freeValue(data);
    const model = try sdk.get(engine, job, "model");
    defer engine.freeValue(model);
    const provider = try sdk.get(engine, model, "provider");
    defer engine.freeValue(provider);
    const id = try sdk.get(engine, model, "id");
    defer engine.freeValue(id);
    const p = try engine.toString(provider);
    defer engine.gpa.free(p);
    const m = try engine.toString(id);
    defer engine.gpa.free(m);
    if (!finish) {
        const records = try entries(engine, data, provider);
        defer engine.freeValue(records);
        const record = if (c.JS_IsObject(records)) try sdk.invoke(engine, records, "get", &.{id}) else c.pi_js_undefined();
        defer engine.freeValue(record);
        if (!c.JS_IsObject(record)) {
            const message = try std.fmt.allocPrint(engine.gpa, "Virtual model {s}/{s} is not registered.", .{ p, m });
            defer engine.gpa.free(message);
            return reject(engine, message);
        }
        const definition = try sdk.get(engine, record, "definition");
        defer engine.freeValue(definition);
        const options = try sdk.get(engine, job, "options");
        defer engine.freeValue(options);
        const request = try sdk.object(engine);
        defer engine.freeValue(request);
        try models.copy(engine, request, options);
        const failed_atom = c.JS_NewAtom(engine.context, "failed");
        defer c.JS_FreeAtom(engine.context, failed_atom);
        if (c.JS_DeleteProperty(engine.context, request, failed_atom, 0) < 0) return error.JavaScriptException;
        try sdk.put(engine, request, "model", c.JS_DupValue(engine.context, model));
        const messages = try sdk.get(engine, job, "messages");
        defer engine.freeValue(messages);
        var latest = c.pi_js_undefined();
        defer engine.freeValue(latest);
        var index = try sdk.length(engine, messages);
        while (index > 0) {
            index -= 1;
            const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index)));
            defer engine.freeValue(candidate);
            const role = try sdk.get(engine, candidate, "role");
            defer engine.freeValue(role);
            const role_text = try engine.toString(role);
            defer engine.gpa.free(role_text);
            if (!std.mem.eql(u8, role_text, "assistant")) continue;
            const stop = try sdk.get(engine, candidate, "stopReason");
            defer engine.freeValue(stop);
            const stop_text = try engine.toString(stop);
            defer engine.gpa.free(stop_text);
            if (std.mem.eql(u8, stop_text, "error") or std.mem.eql(u8, stop_text, "aborted")) continue;
            latest = c.JS_DupValue(engine.context, candidate);
            break;
        }
        try sdk.put(engine, request, "previous", try response(engine, data, latest, false));
        const failed = try sdk.get(engine, options, "failed");
        defer engine.freeValue(failed);
        try sdk.put(engine, request, "failed", try response(engine, data, failed, true));
        try sdk.put(engine, request, "messages", c.JS_DupValue(engine.context, messages));
        const routed = try sdk.invoke(engine, definition, "route", &.{request});
        defer engine.freeValue(routed);
        const pending = try sdk.promise(engine, routed);
        defer engine.freeValue(pending);
        const done = try function(engine, job, true);
        defer engine.freeValue(done);
        return sdk.invoke(engine, pending, "then", &.{done});
    }
    const selected = try sdk.get(engine, value, "model");
    defer engine.freeValue(selected);
    const target_provider = try sdk.get(engine, selected, "provider");
    defer engine.freeValue(target_provider);
    const target_id = try sdk.get(engine, selected, "id");
    defer engine.freeValue(target_id);
    const target = try physical(engine, data, target_provider, target_id);
    defer engine.freeValue(target);
    if (!c.JS_IsObject(target) or !try @import("native_sdk_auth_snapshot.zig").contains(engine, data, "configuredProviders", target_provider)) {
        const tp = try engine.toString(target_provider);
        defer engine.gpa.free(tp);
        const tm = try engine.toString(target_id);
        defer engine.gpa.free(tm);
        const message = try std.fmt.allocPrint(engine.gpa, "Virtual model {s}/{s} routed to {s}/{s}, which {s}.", .{ p, m, tp, tm, if (!c.JS_IsObject(target)) "is not a physical model" else "has no credentials" });
        defer engine.gpa.free(message);
        return reject(engine, message);
    }
    const level = try sdk.get(engine, value, "thinkingLevel");
    defer engine.freeValue(level);
    const requested = try engine.toString(level);
    defer engine.gpa.free(requested);
    const reason = try sdk.get(engine, target, "reasoning");
    defer engine.freeValue(reason);
    const raw_map = try sdk.get(engine, target, "thinkingLevelMap");
    defer engine.freeValue(raw_map);
    var map: thinking.ThinkingLevelMap = .{};
    if (c.JS_IsObject(raw_map)) inline for (std.meta.fields(thinking.ThinkingLevelMap)) |field| {
        const entry = try sdk.get(engine, raw_map, field.name ++ "");
        defer engine.freeValue(entry);
        @field(map, field.name) = if (c.JS_IsUndefined(entry)) .absent else if (c.JS_IsNull(entry)) .unsupported else .{ .mapped = "" };
    };
    const clamped = thinking.clamp(c.JS_ToBool(engine.context, reason) == 1, if (c.JS_IsObject(raw_map)) map else null, std.meta.stringToEnum(thinking.ThinkingLevel, requested) orelse .off);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "model", c.JS_DupValue(engine.context, target));
    try sdk.put(engine, result, "thinkingLevel", try sdk.text(engine, @tagName(clamped)));
    try sdk.put(engine, result, "state", try sdk.get(engine, value, "state"));
    return result;
}

/// Project a session request while retaining its selected virtual model.
/// State is recorded on the current branch before the physical request starts.
pub fn sessionProjection(engine: *engine_mod.Engine, runtime: c.JSValue, manager: c.JSValue, model: c.JSValue, messages: c.JSValue, level: c.JSValue, signal: c.JSValue) !c.JSValue {
    const branch = try sdk.invoke(engine, manager, "getBranch", &.{});
    defer engine.freeValue(branch);
    const provider = try sdk.get(engine, model, "provider");
    defer engine.freeValue(provider);
    const id = try sdk.get(engine, model, "id");
    defer engine.freeValue(id);
    var state = c.pi_js_undefined();
    defer engine.freeValue(state);
    var index = try sdk.length(engine, branch);
    while (index > 0) {
        index -= 1;
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, branch, @intCast(index)));
        defer engine.freeValue(entry);
        const kind = try sdk.get(engine, entry, "type");
        defer engine.freeValue(kind);
        const kind_text = try engine.toString(kind);
        defer engine.gpa.free(kind_text);
        if (!std.mem.eql(u8, kind_text, "custom")) continue;
        const custom = try sdk.get(engine, entry, "customType");
        defer engine.freeValue(custom);
        const custom_text = try engine.toString(custom);
        defer engine.gpa.free(custom_text);
        if (!std.mem.eql(u8, custom_text, "pi.virtual-model-state")) continue;
        const data = try sdk.get(engine, entry, "data");
        defer engine.freeValue(data);
        if (!c.JS_IsObject(data)) continue;
        const p = try sdk.get(engine, data, "provider");
        defer engine.freeValue(p);
        const m = try sdk.get(engine, data, "modelId");
        defer engine.freeValue(m);
        if (c.JS_IsStrictEqual(engine.context, p, provider) and c.JS_IsStrictEqual(engine.context, m, id)) {
            state = try sdk.get(engine, data, "state");
            break;
        }
    }
    var user_turn = false;
    index = try sdk.length(engine, messages);
    while (index > 0) {
        index -= 1;
        const message = try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index)));
        defer engine.freeValue(message);
        const role = try sdk.get(engine, message, "role");
        defer engine.freeValue(role);
        const text = try engine.toString(role);
        defer engine.gpa.free(text);
        if (std.mem.eql(u8, text, "assistant")) break;
        user_turn = user_turn or std.mem.eql(u8, text, "user");
    }
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "reason", try sdk.text(engine, if (user_turn) "user" else "continuation"));
    try sdk.put(engine, options, "thinkingLevel", c.JS_DupValue(engine.context, level));
    try sdk.put(engine, options, "signal", c.JS_DupValue(engine.context, signal));
    try sdk.put(engine, options, "state", c.JS_DupValue(engine.context, state));
    const owner = try sdk.state(engine, runtime);
    const pending = try resolve(engine, owner.data, model, messages, options);
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    errdefer engine.freeValue(result);
    const next = try sdk.get(engine, result, "state");
    defer engine.freeValue(next);
    if (!c.JS_IsUndefined(next) and !c.JS_IsStrictEqual(engine.context, next, state)) {
        const data = try sdk.object(engine);
        defer engine.freeValue(data);
        try sdk.put(engine, data, "provider", c.JS_DupValue(engine.context, provider));
        try sdk.put(engine, data, "modelId", c.JS_DupValue(engine.context, id));
        try sdk.put(engine, data, "state", c.JS_DupValue(engine.context, next));
        const kind = try sdk.text(engine, "pi.virtual-model-state");
        defer engine.freeValue(kind);
        const entry_id = try sdk.invoke(engine, manager, "appendCustomEntry", &.{ kind, data });
        defer engine.freeValue(entry_id);
        try sdk.put(engine, result, "stateEntry", try sdk.invoke(engine, manager, "getEntry", &.{entry_id}));
    }
    return result;
}

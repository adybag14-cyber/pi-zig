//! Native models.json provider overlays. Captured objects and callbacks belong
//! to the engine owner; recomposition never borrows a worker's VM values.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const models = @import("native_sdk_models.zig");
fn keys(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    return sdk.invoke(engine, object, "keys", &.{value});
}
fn merged(engine: *engine_mod.Engine, base: c.JSValue, overlay: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try models.copy(engine, result, base);
    try models.copy(engine, result, overlay);
    return result;
}
fn valueOr(engine: *engine_mod.Engine, source: c.JSValue, key: [*:0]const u8, fallback: c.JSValue) !c.JSValue {
    const value = if (c.JS_IsObject(source)) try sdk.get(engine, source, key) else c.pi_js_undefined();
    if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) return value;
    engine.freeValue(value);
    return c.JS_DupValue(engine.context, fallback);
}
fn chat(engine: *engine_mod.Engine, row: c.JSValue) !bool {
    const kind = try sdk.get(engine, row, "type");
    defer engine.freeValue(kind);
    const text = try sdk.text(engine, "chat");
    defer engine.freeValue(text);
    return c.JS_IsUndefined(kind) or c.JS_IsStrictEqual(engine.context, kind, text);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return (switch (magic) {
        0, 1 => providerList(engine, data[0], magic == 0),
        4, 5, 6 => dispatch(engine, data[0], if (argc > 0) args[0..@intCast(argc)] else &.{}, magic),
        else => error.NativeSDKMethodUnavailable,
    }) catch |err| sdk.fail(engine, err);
}
fn dispatch(engine: *engine_mod.Engine, state: c.JSValue, args: []const c.JSValue, magic: c_int) !c.JSValue {
    if (args.len == 0) return error.NativeSDKMissingArgument;
    const base = try sdk.get(engine, state, "base");
    defer engine.freeValue(base);
    const extension = try sdk.get(engine, state, "extension");
    defer engine.freeValue(extension);
    const api = try sdk.get(engine, args[0], "api");
    defer engine.freeValue(api);
    const method: [*:0]const u8 = if (magic == 4) "streamSimple" else if (magic == 5) "generateImages" else "classify";
    if (c.JS_IsObject(extension)) {
        if (magic == 4) {
            const extension_api = try sdk.get(engine, extension, "api");
            defer engine.freeValue(extension_api);
            const implementation = try sdk.get(engine, extension, method);
            defer engine.freeValue(implementation);
            if (c.JS_IsStrictEqual(engine.context, extension_api, api) and c.JS_IsFunction(engine.context, implementation)) return sdk.invoke(engine, extension, method, args);
        } else {
            const implementations = try sdk.get(engine, extension, if (magic == 5) "images" else "classifiers");
            defer engine.freeValue(implementations);
            if (c.JS_IsObject(implementations)) {
                const implementation = try models.property(engine, implementations, api);
                defer engine.freeValue(implementation);
                if (c.JS_IsObject(implementation)) return sdk.invoke(engine, implementation, method, args);
            }
        }
    }
    if (c.JS_IsObject(base)) {
        var supported = magic != 4;
        if (!supported) {
            const rows = try sdk.invoke(engine, base, "getModels", &.{});
            defer engine.freeValue(rows);
            for (0..try sdk.length(engine, rows)) |index| {
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
                defer engine.freeValue(row);
                const row_api = try sdk.get(engine, row, "api");
                defer engine.freeValue(row_api);
                supported = supported or c.JS_IsStrictEqual(engine.context, row_api, api);
            }
        }
        const implementation = try sdk.get(engine, base, method);
        defer engine.freeValue(implementation);
        if (supported and c.JS_IsFunction(engine.context, implementation)) return sdk.invoke(engine, base, method, args);
    }
    const fallback = try sdk.get(engine, state, method);
    defer engine.freeValue(fallback);
    return engine.checked(c.JS_Call(engine.context, fallback, c.pi_js_undefined(), @intCast(args.len), @constCast(args.ptr)));
}
fn function(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, magic: c_int, value: c.JSValue) !void {
    var data = [_]c.JSValue{value};
    try sdk.put(engine, target, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, 1, magic, 1, &data)));
}
fn list(engine: *engine_mod.Engine, rows: c.JSValue, chat_only: bool) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        if (!chat_only or try chat(engine, row)) try sdk.append(engine, result, c.JS_DupValue(engine.context, row));
    }
    return result;
}
fn providerList(engine: *engine_mod.Engine, state: c.JSValue, chat_only: bool) !c.JSValue {
    const id = try sdk.get(engine, state, "id");
    defer engine.freeValue(id);
    const base = try sdk.get(engine, state, "base");
    defer engine.freeValue(base);
    const config = try sdk.get(engine, state, "config");
    defer engine.freeValue(config);
    const extension = try sdk.get(engine, state, "extension");
    defer engine.freeValue(extension);
    const rows = try composeRows(engine, id, base, config, extension);
    defer engine.freeValue(rows);
    return list(engine, rows, chat_only);
}
fn mergeField(engine: *engine_mod.Engine, result: c.JSValue, base: c.JSValue, override: c.JSValue, field: [*:0]const u8) !void {
    const changed = try sdk.get(engine, override, field);
    defer engine.freeValue(changed);
    if (!c.JS_IsObject(changed)) return;
    const previous = try sdk.get(engine, base, field);
    defer engine.freeValue(previous);
    try sdk.put(engine, result, field, try merged(engine, previous, changed));
}
fn compat(engine: *engine_mod.Engine, base: c.JSValue, overlay: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(overlay)) return c.JS_DupValue(engine.context, base);
    const result = try merged(engine, base, overlay);
    errdefer engine.freeValue(result);
    inline for (.{ "openRouterRouting", "vercelGatewayRouting", "chatTemplateKwargs", "chatTemplateArgs" }) |field| {
        const a = if (c.JS_IsObject(base)) try sdk.get(engine, base, field) else c.pi_js_undefined();
        defer engine.freeValue(a);
        const b = try sdk.get(engine, overlay, field);
        defer engine.freeValue(b);
        if (c.JS_IsObject(a) or c.JS_IsObject(b)) try sdk.put(engine, result, field, try merged(engine, a, b));
    }
    return result;
}
fn overrideModel(engine: *engine_mod.Engine, row: c.JSValue, overlay: c.JSValue) !c.JSValue {
    const result = try merged(engine, row, overlay);
    errdefer engine.freeValue(result);
    // Header definitions are resolved at request time, never exposed on rows.
    try sdk.put(engine, result, "headers", try sdk.get(engine, row, "headers"));
    inline for (.{ "cost", "thinkingLevelMap", "promptCache", "samplingParams" }) |field| try mergeField(engine, result, row, overlay, field);
    const old_compat = try sdk.get(engine, row, "compat");
    defer engine.freeValue(old_compat);
    const new_compat = try sdk.get(engine, overlay, "compat");
    defer engine.freeValue(new_compat);
    try sdk.put(engine, result, "compat", try compat(engine, old_compat, new_compat));
    inline for (.{ "inputLimits", "samplingParamsByThinkingLevel" }) |field| try mergeField(engine, result, row, overlay, field);
    const levels = try sdk.get(engine, overlay, "samplingParamsByThinkingLevel");
    defer engine.freeValue(levels);
    if (c.JS_IsObject(levels)) {
        const target = try sdk.get(engine, result, "samplingParamsByThinkingLevel");
        defer engine.freeValue(target);
        const previous = try sdk.get(engine, row, "samplingParamsByThinkingLevel");
        defer engine.freeValue(previous);
        inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }) |level| try mergeField(engine, target, previous, levels, level);
    }
    const limits = try sdk.get(engine, overlay, "inputLimits");
    defer engine.freeValue(limits);
    if (c.JS_IsObject(limits)) {
        const target = try sdk.get(engine, result, "inputLimits");
        defer engine.freeValue(target);
        const previous = try sdk.get(engine, row, "inputLimits");
        defer engine.freeValue(previous);
        try mergeField(engine, target, previous, limits, "images");
        const images = try sdk.get(engine, limits, "images");
        defer engine.freeValue(images);
        if (c.JS_IsObject(images)) {
            const image_target = try sdk.get(engine, target, "images");
            defer engine.freeValue(image_target);
            const old_images = if (c.JS_IsObject(previous)) try sdk.get(engine, previous, "images") else c.pi_js_undefined();
            defer engine.freeValue(old_images);
            try mergeField(engine, image_target, old_images, images, "resize");
        }
    }
    return result;
}
fn reject(engine: *engine_mod.Engine, message: []const u8) error{JavaScriptException} {
    const text = engine.gpa.dupeZ(u8, message) catch {
        _ = c.JS_ThrowOutOfMemory(engine.context);
        return error.JavaScriptException;
    };
    defer engine.gpa.free(text);
    _ = c.JS_ThrowInternalError(engine.context, "%s", text.ptr);
    return error.JavaScriptException;
}
fn invalid(engine: *engine_mod.Engine, id: []const u8, model: []const u8, detail: []const u8) !void {
    const message = try std.fmt.allocPrint(engine.gpa, "Provider {s}, model {s}: {s}", .{ id, model, detail });
    defer engine.gpa.free(message);
    return reject(engine, message);
}
fn defaults(engine: *engine_mod.Engine, rows: c.JSValue, definition: c.JSValue, config: c.JSValue, extension: bool) !c.JSValue {
    const id = try sdk.get(engine, definition, "id");
    defer engine.freeValue(id);
    const chat_kind = try sdk.text(engine, "chat");
    defer engine.freeValue(chat_kind);
    const kind = if (extension) try valueOr(engine, definition, "type", chat_kind) else c.JS_DupValue(engine.context, chat_kind);
    defer engine.freeValue(kind);
    const is_chat = c.JS_IsStrictEqual(engine.context, kind, chat_kind);
    const provider_api = if (is_chat) try sdk.get(engine, config, "api") else c.pi_js_undefined();
    defer engine.freeValue(provider_api);
    const api = try valueOr(engine, definition, "api", provider_api);
    defer engine.freeValue(api);
    var first = c.pi_js_undefined();
    var by_api = c.pi_js_undefined();
    var completions = c.pi_js_undefined();
    defer engine.freeValue(first);
    defer engine.freeValue(by_api);
    defer engine.freeValue(completions);
    const completions_api = try sdk.text(engine, "openai-completions");
    defer engine.freeValue(completions_api);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const row_kind = try valueOr(engine, row, "type", chat_kind);
        defer engine.freeValue(row_kind);
        if (!c.JS_IsStrictEqual(engine.context, row_kind, kind)) continue;
        const row_id = try sdk.get(engine, row, "id");
        defer engine.freeValue(row_id);
        if (c.JS_IsStrictEqual(engine.context, row_id, id)) return c.JS_DupValue(engine.context, row);
        const row_api = try sdk.get(engine, row, "api");
        defer engine.freeValue(row_api);
        if (c.JS_IsUndefined(first)) first = c.JS_DupValue(engine.context, row);
        if (c.JS_IsUndefined(by_api) and c.JS_IsStrictEqual(engine.context, row_api, api)) by_api = c.JS_DupValue(engine.context, row);
        if (is_chat and c.JS_IsUndefined(completions) and c.JS_IsStrictEqual(engine.context, row_api, completions_api)) completions = c.JS_DupValue(engine.context, row);
    }
    return c.JS_DupValue(engine.context, if (c.JS_IsObject(by_api)) by_api else if (c.JS_IsObject(completions)) completions else first);
}
fn fromJson(engine: *engine_mod.Engine, id: c.JSValue, definition: c.JSValue, config: c.JSValue, fallback: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const provider_name = try engine.toString(id);
    defer engine.gpa.free(provider_name);
    const model_id = try sdk.get(engine, definition, "id");
    defer engine.freeValue(model_id);
    const model_name = try engine.toString(model_id);
    defer engine.gpa.free(model_name);
    inline for (.{ "api", "baseUrl" }) |field| {
        const base = if (c.JS_IsObject(fallback)) try sdk.get(engine, fallback, field) else c.pi_js_undefined();
        defer engine.freeValue(base);
        const provider = try valueOr(engine, config, field, base);
        defer engine.freeValue(provider);
        const value = try valueOr(engine, definition, field, provider);
        defer engine.freeValue(value);
        if (c.JS_ToBool(engine.context, value) != 1) {
            if (std.mem.eql(u8, field, "api")) try invalid(engine, provider_name, model_name, "no \"api\" specified. Set at provider or model level.");
            const message = try std.fmt.allocPrint(engine.gpa, "Provider {s}: \"baseUrl\" is required when defining custom models.", .{provider_name});
            defer engine.gpa.free(message);
            return reject(engine, message);
        }
        try sdk.put(engine, result, field, c.JS_DupValue(engine.context, value));
    }
    try sdk.put(engine, result, "id", c.JS_DupValue(engine.context, model_id));
    try sdk.put(engine, result, "provider", c.JS_DupValue(engine.context, id));
    try sdk.put(engine, result, "name", try valueOr(engine, definition, "name", model_id));
    try sdk.put(engine, result, "reasoning", try valueOr(engine, definition, "reasoning", c.pi_js_bool(engine.context, 0)));
    const text_input = try sdk.array(engine);
    defer engine.freeValue(text_input);
    try sdk.append(engine, text_input, try sdk.text(engine, "text"));
    try sdk.put(engine, result, "input", try valueOr(engine, definition, "input", text_input));
    const cost = try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}");
    defer engine.freeValue(cost);
    try sdk.put(engine, result, "cost", try valueOr(engine, definition, "cost", cost));
    inline for (.{ .{ "contextWindow", 128000 }, .{ "maxTokens", 16384 } }) |field| {
        const value = try valueOr(engine, definition, field[0], c.JS_NewInt32(engine.context, field[1]));
        defer engine.freeValue(value);
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
        if (number <= 0) try invalid(engine, provider_name, model_name, "invalid " ++ field[0]);
        try sdk.put(engine, result, field[0], c.JS_DupValue(engine.context, value));
    }
    inline for (.{ "thinkingLevelMap", "inputLimits", "promptCache", "samplingParams", "samplingParamsByThinkingLevel" }) |field| try sdk.put(engine, result, field, try sdk.get(engine, definition, field));
    const a = try sdk.get(engine, config, "compat");
    defer engine.freeValue(a);
    const b = try sdk.get(engine, definition, "compat");
    defer engine.freeValue(b);
    try sdk.put(engine, result, "compat", try compat(engine, a, b));
    return result;
}
fn composeRows(engine: *engine_mod.Engine, id: c.JSValue, base: c.JSValue, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    const all_getter = if (c.JS_IsObject(base)) try sdk.get(engine, base, "getAllModels") else c.pi_js_undefined();
    defer engine.freeValue(all_getter);
    const original = if (c.JS_IsObject(base)) try sdk.invoke(engine, base, if (c.JS_IsFunction(engine.context, all_getter)) "getAllModels" else "getModels", &.{}) else try sdk.array(engine);
    defer engine.freeValue(original);
    var rows = try sdk.array(engine);
    errdefer engine.freeValue(rows);
    for (0..try sdk.length(engine, original)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, original, @intCast(index)));
        defer engine.freeValue(row);
        const projected = try merged(engine, row, c.pi_js_undefined());
        defer engine.freeValue(projected);
        const previous_url = try sdk.get(engine, row, "baseUrl");
        defer engine.freeValue(previous_url);
        try sdk.put(engine, projected, "baseUrl", try valueOr(engine, config, "baseUrl", previous_url));
        if (try chat(engine, row)) {
            const a = try sdk.get(engine, row, "compat");
            defer engine.freeValue(a);
            const b = try sdk.get(engine, config, "compat");
            defer engine.freeValue(b);
            try sdk.put(engine, projected, "compat", try compat(engine, a, b));
        }
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, projected));
    }
    const definitions = try sdk.get(engine, config, "models");
    defer engine.freeValue(definitions);
    if (c.JS_IsArray(definitions)) for (0..try sdk.length(engine, definitions)) |index| {
        const definition = try engine.checked(c.JS_GetPropertyUint32(engine.context, definitions, @intCast(index)));
        defer engine.freeValue(definition);
        const fallback = try defaults(engine, rows, definition, config, false);
        defer engine.freeValue(fallback);
        const row = try fromJson(engine, id, definition, config, fallback);
        defer engine.freeValue(row);
        const row_id = try sdk.get(engine, row, "id");
        defer engine.freeValue(row_id);
        var replacement: ?usize = null;
        for (0..try sdk.length(engine, rows)) |current| {
            const old = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(current)));
            defer engine.freeValue(old);
            const old_id = try sdk.get(engine, old, "id");
            defer engine.freeValue(old_id);
            if (try chat(engine, old) and c.JS_IsStrictEqual(engine.context, old_id, row_id)) {
                replacement = current;
                break;
            }
        }
        if (replacement) |current| {
            if (c.JS_SetPropertyUint32(engine.context, rows, @intCast(current), c.JS_DupValue(engine.context, row)) < 0) return error.JavaScriptException;
        } else try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
    };
    if (c.JS_IsObject(extension)) {
        const definitions_ext = try sdk.get(engine, extension, "models");
        defer engine.freeValue(definitions_ext);
        const url = try sdk.get(engine, extension, "baseUrl");
        defer engine.freeValue(url);
        if (c.JS_IsArray(definitions_ext)) {
            const replacement = try sdk.array(engine);
            errdefer engine.freeValue(replacement);
            for (0..try sdk.length(engine, definitions_ext)) |index| {
                const definition = try engine.checked(c.JS_GetPropertyUint32(engine.context, definitions_ext, @intCast(index)));
                defer engine.freeValue(definition);
                const fallback = try defaults(engine, rows, definition, extension, true);
                defer engine.freeValue(fallback);
                const row = try merged(engine, definition, c.pi_js_undefined());
                defer engine.freeValue(row);
                inline for (.{ "api", "baseUrl" }) |field| {
                    const old = if (c.JS_IsObject(fallback)) try sdk.get(engine, fallback, field) else c.pi_js_undefined();
                    defer engine.freeValue(old);
                    const provider_value = if (std.mem.eql(u8, field, "baseUrl") or try chat(engine, definition)) try valueOr(engine, extension, field, old) else c.JS_DupValue(engine.context, old);
                    defer engine.freeValue(provider_value);
                    const value = try valueOr(engine, definition, field, provider_value);
                    defer engine.freeValue(value);
                    if (c.JS_ToBool(engine.context, value) != 1) {
                        const provider_name = try engine.toString(id);
                        defer engine.gpa.free(provider_name);
                        const model_id = try sdk.get(engine, definition, "id");
                        defer engine.freeValue(model_id);
                        const model_name = try engine.toString(model_id);
                        defer engine.gpa.free(model_name);
                        if (std.mem.eql(u8, field, "api")) try invalid(engine, provider_name, model_name, if (try chat(engine, definition)) "no \"api\" specified. Set it at model level or provider level." else "no \"api\" specified. Set it at model level.");
                        const message = try std.fmt.allocPrint(engine.gpa, "Provider {s}: \"baseUrl\" is required when defining custom models.", .{provider_name});
                        defer engine.gpa.free(message);
                        return reject(engine, message);
                    }
                    try sdk.put(engine, row, field, c.JS_DupValue(engine.context, value));
                }
                try sdk.put(engine, row, "provider", c.JS_DupValue(engine.context, id));
                try sdk.put(engine, row, "headers", c.pi_js_undefined());
                try sdk.append(engine, replacement, c.JS_DupValue(engine.context, row));
            }
            engine.freeValue(rows);
            rows = replacement;
        } else if (c.JS_ToBool(engine.context, url) == 1) {
            for (0..try sdk.length(engine, rows)) |index| {
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
                defer engine.freeValue(row);
                try sdk.put(engine, row, "baseUrl", c.JS_DupValue(engine.context, url));
            }
        }
    }
    const overrides = try sdk.get(engine, config, "modelOverrides");
    defer engine.freeValue(overrides);
    if (c.JS_IsObject(overrides)) for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        if (!try chat(engine, row)) continue;
        const row_id = try sdk.get(engine, row, "id");
        defer engine.freeValue(row_id);
        const overlay = try models.property(engine, overrides, row_id);
        defer engine.freeValue(overlay);
        if (c.JS_IsObject(overlay) and c.JS_SetPropertyUint32(engine.context, rows, @intCast(index), try overrideModel(engine, row, overlay)) < 0) return error.JavaScriptException;
    };
    return rows;
}
fn compose(engine: *engine_mod.Engine, id: c.JSValue, base: c.JSValue, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    if (c.JS_IsObject(config)) {
        const oauth = try sdk.get(engine, config, "oauth");
        defer engine.freeValue(oauth);
        const url = try sdk.get(engine, config, "baseUrl");
        defer engine.freeValue(url);
        const name = try engine.toString(id);
        defer engine.gpa.free(name);
        if (c.JS_ToBool(engine.context, oauth) == 1 and c.JS_ToBool(engine.context, url) != 1) {
            const message = try std.fmt.allocPrint(engine.gpa, "Provider {s}: \"baseUrl\" is required when \"oauth\" is set.", .{name});
            defer engine.gpa.free(message);
            return reject(engine, message);
        }
        const definitions = try sdk.get(engine, config, "models");
        defer engine.freeValue(definitions);
        var meaningful = c.JS_IsArray(definitions) and try sdk.length(engine, definitions) != 0;
        inline for (.{ "baseUrl", "headers", "compat", "apiKey", "oauth" }) |field| {
            const value = try sdk.get(engine, config, field);
            defer engine.freeValue(value);
            meaningful = meaningful or c.JS_ToBool(engine.context, value) == 1;
        }
        const flag = try sdk.get(engine, config, "authHeader");
        defer engine.freeValue(flag);
        meaningful = meaningful or !c.JS_IsUndefined(flag);
        const overrides = try sdk.get(engine, config, "modelOverrides");
        defer engine.freeValue(overrides);
        if (c.JS_IsObject(overrides)) {
            const entries = try keys(engine, overrides);
            defer engine.freeValue(entries);
            meaningful = meaningful or try sdk.length(engine, entries) != 0;
        }
        if (!meaningful) {
            const message = try std.fmt.allocPrint(engine.gpa, "Provider {s}: must specify \"baseUrl\", \"headers\", \"compat\", \"modelOverrides\", or \"models\".", .{name});
            defer engine.gpa.free(message);
            return reject(engine, message);
        }
    }
    const state = try sdk.object(engine);
    defer engine.freeValue(state);
    const settings = if (c.JS_IsObject(config)) c.JS_DupValue(engine.context, config) else try sdk.object(engine);
    defer engine.freeValue(settings);
    try sdk.put(engine, state, "id", c.JS_DupValue(engine.context, id));
    try sdk.put(engine, state, "base", c.JS_DupValue(engine.context, base));
    try sdk.put(engine, state, "config", c.JS_DupValue(engine.context, settings));
    try sdk.put(engine, state, "extension", c.JS_DupValue(engine.context, extension));
    const checked = try composeRows(engine, id, base, settings, extension);
    engine.freeValue(checked);
    const provider = try merged(engine, base, c.pi_js_undefined());
    errdefer engine.freeValue(provider);
    try sdk.put(engine, provider, "id", c.JS_DupValue(engine.context, id));
    try function(engine, provider, "getModels", 0, state);
    try function(engine, provider, "getAllModels", 1, state);
    const auth_config = try merged(engine, settings, extension);
    defer engine.freeValue(auth_config);
    const old_headers = try sdk.get(engine, settings, "headers");
    defer engine.freeValue(old_headers);
    const new_headers = if (c.JS_IsObject(extension)) try sdk.get(engine, extension, "headers") else c.pi_js_undefined();
    defer engine.freeValue(new_headers);
    if (c.JS_IsObject(old_headers) or c.JS_IsObject(new_headers)) try sdk.put(engine, auth_config, "headers", try merged(engine, old_headers, new_headers));
    try @import("native_sdk_provider_auth.zig").install(engine, provider, base, auth_config, id);
    try @import("native_sdk_operations.zig").install(engine, provider);
    try @import("native_sdk_chat_transport.zig").install(engine, provider);
    inline for (.{ .{ "streamSimple", 4 }, .{ "generateImages", 5 }, .{ "classify", 6 } }) |operation| {
        try sdk.put(engine, state, operation[0], try sdk.get(engine, provider, operation[0]));
        try function(engine, provider, operation[0], operation[1], state);
    }
    return provider;
}
pub fn initialize(engine: *engine_mod.Engine, data: c.JSValue) !void {
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    try sdk.put(engine, data, "builtinProviders", try sdk.invoke(engine, catalog, "getProviders", &.{}));
    try reload(engine, data, c.pi_js_undefined());
}
pub fn configuredStatus(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !?c.JSValue {
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.freeValue(config);
    if (!c.JS_IsObject(config)) return null;
    const providers = try sdk.get(engine, config, "providers");
    defer engine.freeValue(providers);
    const provider = try models.property(engine, providers, id);
    defer engine.freeValue(provider);
    const extensions = try sdk.get(engine, data, "registeredExtensions");
    defer engine.freeValue(extensions);
    const extension = try sdk.invoke(engine, extensions, "get", &.{id});
    defer engine.freeValue(extension);
    const configured_key = if (c.JS_IsObject(provider)) try sdk.get(engine, provider, "apiKey") else c.pi_js_undefined();
    defer engine.freeValue(configured_key);
    const raw_value = try valueOr(engine, extension, "apiKey", configured_key);
    defer engine.freeValue(raw_value);
    if (c.JS_IsUndefined(raw_value)) return null;
    const raw = try engine.toString(raw_value);
    defer engine.gpa.free(raw);
    const references = try @import("native_sdk_config_value.zig").names(engine.gpa, raw);
    defer engine.gpa.free(references);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const configured = try @import("native_sdk_config_value.zig").configured(engine, raw);
    try sdk.put(engine, result, "configured", c.pi_js_bool(engine.context, @intFromBool(configured)));
    if (configured) {
        const extension_key = if (c.JS_IsObject(extension)) try sdk.get(engine, extension, "apiKey") else c.pi_js_undefined();
        defer engine.freeValue(extension_key);
        const source = if (std.mem.startsWith(u8, raw, "!")) "models_json_command" else if (references.len > 0) "environment" else if (!c.JS_IsUndefined(extension_key)) "fallback" else "models_json_key";
        try sdk.put(engine, result, "source", try sdk.text(engine, source));
        if (references.len > 0) {
            const names = try std.mem.join(engine.gpa, ", ", references);
            defer engine.gpa.free(names);
            try sdk.put(engine, result, "label", try sdk.text(engine, names));
        }
    }
    return result;
}
fn mapKeys(engine: *engine_mod.Engine, map: c.JSValue) !c.JSValue {
    const iterator = try sdk.invoke(engine, map, "keys", &.{});
    defer engine.freeValue(iterator);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.freeValue(array);
    return sdk.invoke(engine, array, "from", &.{iterator});
}
fn baseProvider(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !c.JSValue {
    const native = try sdk.get(engine, data, "registeredNative");
    defer engine.freeValue(native);
    const provider = try sdk.invoke(engine, native, "get", &.{id});
    if (c.JS_IsObject(provider)) return provider;
    engine.freeValue(provider);
    return builtinProvider(engine, data, id);
}
fn builtinProvider(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !c.JSValue {
    const builtins = try sdk.get(engine, data, "builtinProviders");
    defer engine.freeValue(builtins);
    for (0..try sdk.length(engine, builtins)) |index| {
        const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, builtins, @intCast(index)));
        defer engine.freeValue(candidate);
        const candidate_id = try sdk.get(engine, candidate, "id");
        defer engine.freeValue(candidate_id);
        if (c.JS_IsStrictEqual(engine.context, candidate_id, id)) return c.JS_DupValue(engine.context, candidate);
    }
    return c.pi_js_undefined();
}
fn prepare(engine: *engine_mod.Engine, data: c.JSValue, config: c.JSValue, id: c.JSValue, errors: c.JSValue) !c.JSValue {
    const providers = try sdk.get(engine, config, "providers");
    defer engine.freeValue(providers);
    const settings = try models.property(engine, providers, id);
    defer engine.freeValue(settings);
    const base = try baseProvider(engine, data, id);
    defer engine.freeValue(base);
    const deleted = try sdk.invoke(engine, errors, "delete", &.{id});
    engine.freeValue(deleted);
    const extensions = try sdk.get(engine, data, "registeredExtensions");
    defer engine.freeValue(extensions);
    const extension = try sdk.invoke(engine, extensions, "get", &.{id});
    defer engine.freeValue(extension);
    if (!c.JS_IsObject(settings) and !c.JS_IsObject(extension)) {
        // Unmodified native providers retain their actual object identity.
        return c.JS_DupValue(engine.context, base);
    }
    return compose(engine, id, base, settings, extension) catch |err| {
        if (err != error.JavaScriptException) return err;
        const exception = if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else return err;
        defer engine.freeValue(exception);
        const message = try sdk.get(engine, exception, "message");
        defer engine.freeValue(message);
        const name = try engine.toString(id);
        defer engine.gpa.free(name);
        const reason = try engine.toString(message);
        defer engine.gpa.free(reason);
        const text = try std.fmt.allocPrint(engine.gpa, "Provider \"{s}\": {s}", .{ name, reason });
        defer engine.gpa.free(text);
        const value = try sdk.text(engine, text);
        defer engine.freeValue(value);
        const ignored = try sdk.invoke(engine, errors, "set", &.{ id, value });
        engine.freeValue(ignored);
        return c.JS_DupValue(engine.context, base);
    };
}
pub fn extensionProvider(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, extension: c.JSValue) !c.JSValue {
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.freeValue(config);
    const providers = try sdk.get(engine, config, "providers");
    defer engine.freeValue(providers);
    const settings = try models.property(engine, providers, id);
    defer engine.freeValue(settings);
    const base = try builtinProvider(engine, data, id);
    defer engine.freeValue(base);
    const stream = try sdk.get(engine, extension, "streamSimple");
    defer engine.freeValue(stream);
    const api = try sdk.get(engine, extension, "api");
    defer engine.freeValue(api);
    if (c.JS_IsFunction(engine.context, stream) and c.JS_ToBool(engine.context, api) != 1) {
        const name = try engine.toString(id);
        defer engine.gpa.free(name);
        const message = try std.fmt.allocPrint(engine.gpa, "Provider {s}: \"api\" is required when registering streamSimple.", .{name});
        defer engine.gpa.free(message);
        return reject(engine, message);
    }
    return compose(engine, id, base, settings, extension);
}
pub fn recompose(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !void {
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.freeValue(config);
    const errors = try sdk.get(engine, data, "compositionErrors");
    defer engine.freeValue(errors);
    const provider = try prepare(engine, data, config, id, errors);
    defer engine.freeValue(provider);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const result = if (c.JS_IsObject(provider)) try sdk.invoke(engine, catalog, "setProvider", &.{provider}) else try sdk.invoke(engine, catalog, "deleteProvider", &.{id});
    engine.freeValue(result);
}
pub fn reload(engine: *engine_mod.Engine, data: c.JSValue, selected: c.JSValue) !void {
    const options = try sdk.get(engine, data, "options");
    defer engine.freeValue(options);
    const config = try @import("native_sdk_model_config.zig").load(engine, options);
    defer engine.freeValue(config);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const errors = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.freeValue(errors);
    const ids = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Set");
    defer engine.freeValue(ids);
    if (c.JS_IsArray(selected)) {
        const previous = try sdk.get(engine, data, "compositionErrors");
        defer engine.freeValue(previous);
        if (c.JS_IsObject(previous)) {
            const previous_ids = try mapKeys(engine, previous);
            defer engine.freeValue(previous_ids);
            for (0..try sdk.length(engine, previous_ids)) |index| {
                const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, previous_ids, @intCast(index)));
                defer engine.freeValue(id);
                const message = try sdk.invoke(engine, previous, "get", &.{id});
                defer engine.freeValue(message);
                const ignored = try sdk.invoke(engine, errors, "set", &.{ id, message });
                engine.freeValue(ignored);
            }
        }
        for (0..try sdk.length(engine, selected)) |index| {
            const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, selected, @intCast(index)));
            defer engine.freeValue(id);
            const ignored = try sdk.invoke(engine, ids, "add", &.{id});
            engine.freeValue(ignored);
        }
    } else {
        const builtins = try sdk.get(engine, data, "builtinProviders");
        defer engine.freeValue(builtins);
        for (0..try sdk.length(engine, builtins)) |index| {
            const provider = try engine.checked(c.JS_GetPropertyUint32(engine.context, builtins, @intCast(index)));
            defer engine.freeValue(provider);
            const id = try sdk.get(engine, provider, "id");
            defer engine.freeValue(id);
            const ignored = try sdk.invoke(engine, ids, "add", &.{id});
            engine.freeValue(ignored);
        }
        inline for (.{ "registeredNative", "modelConfig", "registeredExtensions" }) |field| {
            const map = if (comptime std.mem.eql(u8, field, "modelConfig")) try sdk.get(engine, config, "providers") else try sdk.get(engine, data, field);
            defer engine.freeValue(map);
            const names = if (comptime std.mem.eql(u8, field, "modelConfig")) try keys(engine, map) else try mapKeys(engine, map);
            defer engine.freeValue(names);
            for (0..try sdk.length(engine, names)) |index| {
                const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, @intCast(index)));
                defer engine.freeValue(id);
                const ignored = try sdk.invoke(engine, ids, "add", &.{id});
                engine.freeValue(ignored);
            }
        }
    }
    const ordered = try mapKeys(engine, ids);
    defer engine.freeValue(ordered);
    const prepared = try sdk.array(engine);
    defer engine.freeValue(prepared);
    for (0..try sdk.length(engine, ordered)) |index| {
        const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, ordered, @intCast(index)));
        defer engine.freeValue(id);
        try sdk.append(engine, prepared, try prepare(engine, data, config, id, errors));
    }
    if (!c.JS_IsArray(selected)) {
        const cleared = try sdk.invoke(engine, catalog, "clearProviders", &.{});
        engine.freeValue(cleared);
    }
    for (0..try sdk.length(engine, prepared)) |index| {
        const provider = try engine.checked(c.JS_GetPropertyUint32(engine.context, prepared, @intCast(index)));
        defer engine.freeValue(provider);
        if (c.JS_IsObject(provider)) {
            const ignored = try sdk.invoke(engine, catalog, "setProvider", &.{provider});
            engine.freeValue(ignored);
        } else if (c.JS_IsArray(selected)) {
            const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, ordered, @intCast(index)));
            defer engine.freeValue(id);
            const ignored = try sdk.invoke(engine, catalog, "deleteProvider", &.{id});
            engine.freeValue(ignored);
        }
    }
    try sdk.put(engine, data, "modelConfig", c.JS_DupValue(engine.context, config));
    try sdk.put(engine, data, "compositionErrors", c.JS_DupValue(engine.context, errors));
    try @import("native_sdk_auth_snapshot.zig").updateModels(engine, data);
}

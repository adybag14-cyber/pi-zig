//! Native models.json provider overlays. Captured objects and callbacks belong
//! to the engine owner; recomposition never borrows a worker's VM values.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const models = @import("native_sdk_models.zig");
// A direct native allocator outcome is a producer before deferred JS roots
// can publish a later cleanup event. Other typed failures retain their class.
fn nativeAllocation(engine: anytype, result: anytype) @TypeOf(result) {
    return result catch |err| {
        if (@as(anyerror, err) == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    };
}
fn nativeText(engine: anytype, value: c.JSValue) anyerror![]u8 {
    try engine.checkNativeEntry();
    return nativeAllocation(engine, engine.toString(value));
}

fn keys(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.releaseNativeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.releaseNativeValue(object);
    return sdk.invoke(engine, object, "keys", &.{value});
}
fn merged(engine: *engine_mod.Engine, base: c.JSValue, overlay: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
    try models.copy(engine, result, base);
    try models.copy(engine, result, overlay);
    return result;
}
fn valueOr(engine: *engine_mod.Engine, source: c.JSValue, key: [*:0]const u8, fallback: c.JSValue) !c.JSValue {
    const value = if (c.JS_IsObject(source)) try sdk.get(engine, source, key) else c.pi_js_undefined();
    if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) return value;
    engine.releaseNativeValue(value);
    return c.JS_DupValue(engine.context, fallback);
}
fn chat(engine: *engine_mod.Engine, row: c.JSValue) !bool {
    const kind = try sdk.get(engine, row, "type");
    defer engine.releaseNativeValue(kind);
    const text = try sdk.text(engine, "chat");
    defer engine.releaseNativeValue(text);
    return c.JS_IsUndefined(kind) or c.JS_IsStrictEqual(engine.context, kind, text);
}
fn callback(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(callbackOwnedBody(context, ignored0, argc, args, magic, data));
}
fn callbackOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) c.JSValue {
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
    defer engine.releaseNativeValue(base);
    const extension = try sdk.get(engine, state, "extension");
    defer engine.releaseNativeValue(extension);
    const api = try sdk.get(engine, args[0], "api");
    defer engine.releaseNativeValue(api);
    const method: [*:0]const u8 = if (magic == 4) "streamSimple" else if (magic == 5) "generateImages" else "classify";
    if (c.JS_IsObject(extension)) {
        if (magic == 4) {
            const extension_api = try sdk.get(engine, extension, "api");
            defer engine.releaseNativeValue(extension_api);
            const implementation = try sdk.get(engine, extension, method);
            defer engine.releaseNativeValue(implementation);
            if (c.JS_IsStrictEqual(engine.context, extension_api, api) and c.JS_IsFunction(engine.context, implementation)) return sdk.invoke(engine, extension, method, args);
        } else {
            const implementations = try sdk.get(engine, extension, if (magic == 5) "images" else "classifiers");
            defer engine.releaseNativeValue(implementations);
            if (c.JS_IsObject(implementations)) {
                const implementation = try models.property(engine, implementations, api);
                defer engine.releaseNativeValue(implementation);
                if (c.JS_IsObject(implementation)) return sdk.invoke(engine, implementation, method, args);
            }
        }
    }
    if (c.JS_IsObject(base)) {
        var supported = magic != 4;
        if (!supported) {
            const rows = try sdk.invoke(engine, base, "getModels", &.{});
            defer engine.releaseNativeValue(rows);
            for (0..try sdk.length(engine, rows)) |index| {
                try engine.checkNativeEntry();
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
                defer engine.releaseNativeValue(row);
                const row_api = try sdk.get(engine, row, "api");
                defer engine.releaseNativeValue(row_api);
                supported = supported or c.JS_IsStrictEqual(engine.context, row_api, api);
            }
        }
        const implementation = try sdk.get(engine, base, method);
        defer engine.releaseNativeValue(implementation);
        if (supported and c.JS_IsFunction(engine.context, implementation)) return sdk.invoke(engine, base, method, args);
    }
    const fallback = try sdk.get(engine, state, method);
    defer engine.releaseNativeValue(fallback);
    try engine.checkNativeEntry();
    return engine.checked(c.JS_Call(engine.context, fallback, c.pi_js_undefined(), @intCast(args.len), @constCast(args.ptr)));
}
fn function(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, magic: c_int, value: c.JSValue) !void {
    var data = [_]c.JSValue{value};
    try sdk.put(engine, target, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, 1, magic, 1, &data)));
}
fn list(engine: *engine_mod.Engine, rows: c.JSValue, chat_only: bool) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.releaseNativeValue(result);
    for (0..try sdk.length(engine, rows)) |index| {
        try engine.checkNativeEntry();
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.releaseNativeValue(row);
        if (!chat_only or try chat(engine, row)) try sdk.append(engine, result, c.JS_DupValue(engine.context, row));
    }
    return result;
}
fn providerList(engine: *engine_mod.Engine, state: c.JSValue, chat_only: bool) !c.JSValue {
    const id = try sdk.get(engine, state, "id");
    defer engine.releaseNativeValue(id);
    const base = try sdk.get(engine, state, "base");
    defer engine.releaseNativeValue(base);
    const config = try sdk.get(engine, state, "config");
    defer engine.releaseNativeValue(config);
    const extension = try sdk.get(engine, state, "extension");
    defer engine.releaseNativeValue(extension);
    const rows = try composeRows(engine, id, base, config, extension);
    defer engine.releaseNativeValue(rows);
    return list(engine, rows, chat_only);
}
fn mergeField(engine: *engine_mod.Engine, result: c.JSValue, base: c.JSValue, override: c.JSValue, field: [*:0]const u8) !void {
    const changed = try sdk.get(engine, override, field);
    defer engine.releaseNativeValue(changed);
    if (!c.JS_IsObject(changed)) return;
    const previous = try sdk.get(engine, base, field);
    defer engine.releaseNativeValue(previous);
    try sdk.put(engine, result, field, try merged(engine, previous, changed));
}
fn compat(engine: *engine_mod.Engine, base: c.JSValue, overlay: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(overlay)) return c.JS_DupValue(engine.context, base);
    const result = try merged(engine, base, overlay);
    errdefer engine.releaseNativeValue(result);
    inline for (.{ "openRouterRouting", "vercelGatewayRouting", "chatTemplateKwargs", "chatTemplateArgs" }) |field| {
        const a = if (c.JS_IsObject(base)) try sdk.get(engine, base, field) else c.pi_js_undefined();
        defer engine.releaseNativeValue(a);
        const b = try sdk.get(engine, overlay, field);
        defer engine.releaseNativeValue(b);
        if (c.JS_IsObject(a) or c.JS_IsObject(b)) try sdk.put(engine, result, field, try merged(engine, a, b));
    }
    return result;
}
fn overrideModel(engine: *engine_mod.Engine, row: c.JSValue, overlay: c.JSValue) !c.JSValue {
    const result = try merged(engine, row, overlay);
    errdefer engine.releaseNativeValue(result);
    // Header definitions are resolved at request time, never exposed on rows.
    try sdk.put(engine, result, "headers", try sdk.get(engine, row, "headers"));
    inline for (.{ "cost", "thinkingLevelMap", "promptCache", "samplingParams" }) |field| try mergeField(engine, result, row, overlay, field);
    const old_compat = try sdk.get(engine, row, "compat");
    defer engine.releaseNativeValue(old_compat);
    const new_compat = try sdk.get(engine, overlay, "compat");
    defer engine.releaseNativeValue(new_compat);
    try sdk.put(engine, result, "compat", try compat(engine, old_compat, new_compat));
    inline for (.{ "inputLimits", "samplingParamsByThinkingLevel" }) |field| try mergeField(engine, result, row, overlay, field);
    const levels = try sdk.get(engine, overlay, "samplingParamsByThinkingLevel");
    defer engine.releaseNativeValue(levels);
    if (c.JS_IsObject(levels)) {
        const target = try sdk.get(engine, result, "samplingParamsByThinkingLevel");
        defer engine.releaseNativeValue(target);
        const previous = try sdk.get(engine, row, "samplingParamsByThinkingLevel");
        defer engine.releaseNativeValue(previous);
        inline for (.{ "off", "minimal", "low", "medium", "high", "xhigh", "max" }) |level| try mergeField(engine, target, previous, levels, level);
    }
    const limits = try sdk.get(engine, overlay, "inputLimits");
    defer engine.releaseNativeValue(limits);
    if (c.JS_IsObject(limits)) {
        const target = try sdk.get(engine, result, "inputLimits");
        defer engine.releaseNativeValue(target);
        const previous = try sdk.get(engine, row, "inputLimits");
        defer engine.releaseNativeValue(previous);
        try mergeField(engine, target, previous, limits, "images");
        const images = try sdk.get(engine, limits, "images");
        defer engine.releaseNativeValue(images);
        if (c.JS_IsObject(images)) {
            const image_target = try sdk.get(engine, target, "images");
            defer engine.releaseNativeValue(image_target);
            const old_images = if (c.JS_IsObject(previous)) try sdk.get(engine, previous, "images") else c.pi_js_undefined();
            defer engine.releaseNativeValue(old_images);
            try mergeField(engine, image_target, old_images, images, "resize");
        }
    }
    return result;
}
fn reject(engine: *engine_mod.Engine, message: []const u8) error{JavaScriptException} {
    const text = engine.gpa.dupeZ(u8, message) catch {
        _ = engine.throwNativeOutOfMemoryFatal();
        return error.JavaScriptException;
    };
    defer engine.gpa.free(text);
    _ = c.JS_ThrowInternalError(engine.context, "%s", text.ptr);
    return error.JavaScriptException;
}
fn invalid(engine: *engine_mod.Engine, id: []const u8, model: []const u8, detail: []const u8) !void {
    const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider {s}, model {s}: {s}", .{ id, model, detail }));
    defer engine.gpa.free(message);
    return reject(engine, message);
}
fn defaults(engine: *engine_mod.Engine, rows: c.JSValue, definition: c.JSValue, config: c.JSValue, extension: bool) !c.JSValue {
    const id = try sdk.get(engine, definition, "id");
    defer engine.releaseNativeValue(id);
    const chat_kind = try sdk.text(engine, "chat");
    defer engine.releaseNativeValue(chat_kind);
    const kind = if (extension) try valueOr(engine, definition, "type", chat_kind) else c.JS_DupValue(engine.context, chat_kind);
    defer engine.releaseNativeValue(kind);
    const is_chat = c.JS_IsStrictEqual(engine.context, kind, chat_kind);
    const provider_api = if (is_chat) try sdk.get(engine, config, "api") else c.pi_js_undefined();
    defer engine.releaseNativeValue(provider_api);
    const api = try valueOr(engine, definition, "api", provider_api);
    defer engine.releaseNativeValue(api);
    var first = c.pi_js_undefined();
    var by_api = c.pi_js_undefined();
    var completions = c.pi_js_undefined();
    defer engine.releaseNativeValue(first);
    defer engine.releaseNativeValue(by_api);
    defer engine.releaseNativeValue(completions);
    const completions_api = try sdk.text(engine, "openai-completions");
    defer engine.releaseNativeValue(completions_api);
    for (0..try sdk.length(engine, rows)) |index| {
        try engine.checkNativeEntry();
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.releaseNativeValue(row);
        const row_kind = try valueOr(engine, row, "type", chat_kind);
        defer engine.releaseNativeValue(row_kind);
        if (!c.JS_IsStrictEqual(engine.context, row_kind, kind)) continue;
        const row_id = try sdk.get(engine, row, "id");
        defer engine.releaseNativeValue(row_id);
        if (c.JS_IsStrictEqual(engine.context, row_id, id)) return c.JS_DupValue(engine.context, row);
        const row_api = try sdk.get(engine, row, "api");
        defer engine.releaseNativeValue(row_api);
        if (c.JS_IsUndefined(first)) first = c.JS_DupValue(engine.context, row);
        if (c.JS_IsUndefined(by_api) and c.JS_IsStrictEqual(engine.context, row_api, api)) by_api = c.JS_DupValue(engine.context, row);
        if (is_chat and c.JS_IsUndefined(completions) and c.JS_IsStrictEqual(engine.context, row_api, completions_api)) completions = c.JS_DupValue(engine.context, row);
    }
    return c.JS_DupValue(engine.context, if (c.JS_IsObject(by_api)) by_api else if (c.JS_IsObject(completions)) completions else first);
}
fn fromJson(engine: *engine_mod.Engine, id: c.JSValue, definition: c.JSValue, config: c.JSValue, fallback: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
    const provider_name = try nativeText(engine, id);
    defer engine.gpa.free(provider_name);
    const model_id = try sdk.get(engine, definition, "id");
    defer engine.releaseNativeValue(model_id);
    const model_name = try nativeText(engine, model_id);
    defer engine.gpa.free(model_name);
    inline for (.{ "api", "baseUrl" }) |field| {
        const base = if (c.JS_IsObject(fallback)) try sdk.get(engine, fallback, field) else c.pi_js_undefined();
        defer engine.releaseNativeValue(base);
        const provider = try valueOr(engine, config, field, base);
        defer engine.releaseNativeValue(provider);
        const value = try valueOr(engine, definition, field, provider);
        defer engine.releaseNativeValue(value);
        if (c.JS_ToBool(engine.context, value) != 1) {
            if (std.mem.eql(u8, field, "api")) try invalid(engine, provider_name, model_name, "no \"api\" specified. Set at provider or model level.");
            const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider {s}: \"baseUrl\" is required when defining custom models.", .{provider_name}));
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
    defer engine.releaseNativeValue(text_input);
    try sdk.append(engine, text_input, try sdk.text(engine, "text"));
    try sdk.put(engine, result, "input", try valueOr(engine, definition, "input", text_input));
    const cost = try sdk.jsonObject(engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}");
    defer engine.releaseNativeValue(cost);
    try sdk.put(engine, result, "cost", try valueOr(engine, definition, "cost", cost));
    inline for (.{ .{ "contextWindow", 128000 }, .{ "maxTokens", 16384 } }) |field| {
        const value = try valueOr(engine, definition, field[0], c.JS_NewInt32(engine.context, field[1]));
        defer engine.releaseNativeValue(value);
        var number: f64 = 0;
        try engine.checkNativeEntry();
        if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
        if (number <= 0) try invalid(engine, provider_name, model_name, "invalid " ++ field[0]);
        try sdk.put(engine, result, field[0], c.JS_DupValue(engine.context, value));
    }
    inline for (.{ "thinkingLevelMap", "inputLimits", "promptCache", "samplingParams", "samplingParamsByThinkingLevel" }) |field| try sdk.put(engine, result, field, try sdk.get(engine, definition, field));
    const a = try sdk.get(engine, config, "compat");
    defer engine.releaseNativeValue(a);
    const b = try sdk.get(engine, definition, "compat");
    defer engine.releaseNativeValue(b);
    try sdk.put(engine, result, "compat", try compat(engine, a, b));
    return result;
}
fn composeRows(engine: *engine_mod.Engine, id: c.JSValue, base: c.JSValue, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    const all_getter = if (c.JS_IsObject(base)) try sdk.get(engine, base, "getAllModels") else c.pi_js_undefined();
    defer engine.releaseNativeValue(all_getter);
    const original = if (c.JS_IsObject(base)) try sdk.invoke(engine, base, if (c.JS_IsFunction(engine.context, all_getter)) "getAllModels" else "getModels", &.{}) else try sdk.array(engine);
    defer engine.releaseNativeValue(original);
    var rows = try sdk.array(engine);
    errdefer engine.releaseNativeValue(rows);
    for (0..try sdk.length(engine, original)) |index| {
        try engine.checkNativeEntry();
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, original, @intCast(index)));
        defer engine.releaseNativeValue(row);
        const projected = try merged(engine, row, c.pi_js_undefined());
        defer engine.releaseNativeValue(projected);
        const previous_url = try sdk.get(engine, row, "baseUrl");
        defer engine.releaseNativeValue(previous_url);
        try sdk.put(engine, projected, "baseUrl", try valueOr(engine, config, "baseUrl", previous_url));
        if (try chat(engine, row)) {
            const a = try sdk.get(engine, row, "compat");
            defer engine.releaseNativeValue(a);
            const b = try sdk.get(engine, config, "compat");
            defer engine.releaseNativeValue(b);
            try sdk.put(engine, projected, "compat", try compat(engine, a, b));
        }
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, projected));
    }
    const definitions = try sdk.get(engine, config, "models");
    defer engine.releaseNativeValue(definitions);
    if (c.JS_IsArray(definitions)) for (0..try sdk.length(engine, definitions)) |index| {
        try engine.checkNativeEntry();
        const definition = try engine.checked(c.JS_GetPropertyUint32(engine.context, definitions, @intCast(index)));
        defer engine.releaseNativeValue(definition);
        const fallback = try defaults(engine, rows, definition, config, false);
        defer engine.releaseNativeValue(fallback);
        const row = try fromJson(engine, id, definition, config, fallback);
        defer engine.releaseNativeValue(row);
        const row_id = try sdk.get(engine, row, "id");
        defer engine.releaseNativeValue(row_id);
        var replacement: ?usize = null;
        for (0..try sdk.length(engine, rows)) |current| {
            try engine.checkNativeEntry();
            const old = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(current)));
            defer engine.releaseNativeValue(old);
            const old_id = try sdk.get(engine, old, "id");
            defer engine.releaseNativeValue(old_id);
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
        defer engine.releaseNativeValue(definitions_ext);
        const url = try sdk.get(engine, extension, "baseUrl");
        defer engine.releaseNativeValue(url);
        if (c.JS_IsArray(definitions_ext)) {
            const replacement = try sdk.array(engine);
            errdefer engine.releaseNativeValue(replacement);
            for (0..try sdk.length(engine, definitions_ext)) |index| {
                try engine.checkNativeEntry();
                const definition = try engine.checked(c.JS_GetPropertyUint32(engine.context, definitions_ext, @intCast(index)));
                defer engine.releaseNativeValue(definition);
                const fallback = try defaults(engine, rows, definition, extension, true);
                defer engine.releaseNativeValue(fallback);
                const row = try merged(engine, definition, c.pi_js_undefined());
                defer engine.releaseNativeValue(row);
                inline for (.{ "api", "baseUrl" }) |field| {
                    const old = if (c.JS_IsObject(fallback)) try sdk.get(engine, fallback, field) else c.pi_js_undefined();
                    defer engine.releaseNativeValue(old);
                    const provider_value = if (std.mem.eql(u8, field, "baseUrl") or try chat(engine, definition)) try valueOr(engine, extension, field, old) else c.JS_DupValue(engine.context, old);
                    defer engine.releaseNativeValue(provider_value);
                    const value = try valueOr(engine, definition, field, provider_value);
                    defer engine.releaseNativeValue(value);
                    if (c.JS_ToBool(engine.context, value) != 1) {
                        const provider_name = try nativeText(engine, id);
                        defer engine.gpa.free(provider_name);
                        const model_id = try sdk.get(engine, definition, "id");
                        defer engine.releaseNativeValue(model_id);
                        const model_name = try nativeText(engine, model_id);
                        defer engine.gpa.free(model_name);
                        if (std.mem.eql(u8, field, "api")) try invalid(engine, provider_name, model_name, if (try chat(engine, definition)) "no \"api\" specified. Set it at model level or provider level." else "no \"api\" specified. Set it at model level.");
                        const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider {s}: \"baseUrl\" is required when defining custom models.", .{provider_name}));
                        defer engine.gpa.free(message);
                        return reject(engine, message);
                    }
                    try sdk.put(engine, row, field, c.JS_DupValue(engine.context, value));
                }
                try sdk.put(engine, row, "provider", c.JS_DupValue(engine.context, id));
                try sdk.put(engine, row, "headers", c.pi_js_undefined());
                try sdk.append(engine, replacement, c.JS_DupValue(engine.context, row));
            }
            engine.releaseNativeValue(rows);
            rows = replacement;
        } else if (c.JS_ToBool(engine.context, url) == 1) {
            for (0..try sdk.length(engine, rows)) |index| {
                try engine.checkNativeEntry();
                const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
                defer engine.releaseNativeValue(row);
                try sdk.put(engine, row, "baseUrl", c.JS_DupValue(engine.context, url));
            }
        }
    }
    const overrides = try sdk.get(engine, config, "modelOverrides");
    defer engine.releaseNativeValue(overrides);
    if (c.JS_IsObject(overrides)) for (0..try sdk.length(engine, rows)) |index| {
        try engine.checkNativeEntry();
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.releaseNativeValue(row);
        if (!try chat(engine, row)) continue;
        const row_id = try sdk.get(engine, row, "id");
        defer engine.releaseNativeValue(row_id);
        const overlay = try models.property(engine, overrides, row_id);
        defer engine.releaseNativeValue(overlay);
        if (c.JS_IsObject(overlay) and c.JS_SetPropertyUint32(engine.context, rows, @intCast(index), try overrideModel(engine, row, overlay)) < 0) return error.JavaScriptException;
    };
    return rows;
}
fn compose(engine: *engine_mod.Engine, id: c.JSValue, base: c.JSValue, config: c.JSValue, extension: c.JSValue) !c.JSValue {
    if (c.JS_IsObject(config)) {
        const oauth = try sdk.get(engine, config, "oauth");
        defer engine.releaseNativeValue(oauth);
        const url = try sdk.get(engine, config, "baseUrl");
        defer engine.releaseNativeValue(url);
        const name = try nativeText(engine, id);
        defer engine.gpa.free(name);
        if (c.JS_ToBool(engine.context, oauth) == 1 and c.JS_ToBool(engine.context, url) != 1) {
            const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider {s}: \"baseUrl\" is required when \"oauth\" is set.", .{name}));
            defer engine.gpa.free(message);
            return reject(engine, message);
        }
        const definitions = try sdk.get(engine, config, "models");
        defer engine.releaseNativeValue(definitions);
        var meaningful = c.JS_IsArray(definitions) and try sdk.length(engine, definitions) != 0;
        inline for (.{ "baseUrl", "headers", "compat", "apiKey", "oauth" }) |field| {
            const value = try sdk.get(engine, config, field);
            defer engine.releaseNativeValue(value);
            meaningful = meaningful or c.JS_ToBool(engine.context, value) == 1;
        }
        const flag = try sdk.get(engine, config, "authHeader");
        defer engine.releaseNativeValue(flag);
        meaningful = meaningful or !c.JS_IsUndefined(flag);
        const overrides = try sdk.get(engine, config, "modelOverrides");
        defer engine.releaseNativeValue(overrides);
        if (c.JS_IsObject(overrides)) {
            const entries = try keys(engine, overrides);
            defer engine.releaseNativeValue(entries);
            meaningful = meaningful or try sdk.length(engine, entries) != 0;
        }
        if (!meaningful) {
            const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider {s}: must specify \"baseUrl\", \"headers\", \"compat\", \"modelOverrides\", or \"models\".", .{name}));
            defer engine.gpa.free(message);
            return reject(engine, message);
        }
    }
    const state = try sdk.object(engine);
    defer engine.releaseNativeValue(state);
    const settings = if (c.JS_IsObject(config)) c.JS_DupValue(engine.context, config) else try sdk.object(engine);
    defer engine.releaseNativeValue(settings);
    try sdk.put(engine, state, "id", c.JS_DupValue(engine.context, id));
    try sdk.put(engine, state, "base", c.JS_DupValue(engine.context, base));
    try sdk.put(engine, state, "config", c.JS_DupValue(engine.context, settings));
    try sdk.put(engine, state, "extension", c.JS_DupValue(engine.context, extension));
    const checked = try composeRows(engine, id, base, settings, extension);
    engine.releaseNativeValue(checked);
    const provider = try merged(engine, base, c.pi_js_undefined());
    errdefer engine.releaseNativeValue(provider);
    try sdk.put(engine, provider, "id", c.JS_DupValue(engine.context, id));
    try function(engine, provider, "getModels", 0, state);
    try function(engine, provider, "getAllModels", 1, state);
    const auth_config = try merged(engine, settings, extension);
    defer engine.releaseNativeValue(auth_config);
    const old_headers = try sdk.get(engine, settings, "headers");
    defer engine.releaseNativeValue(old_headers);
    const new_headers = if (c.JS_IsObject(extension)) try sdk.get(engine, extension, "headers") else c.pi_js_undefined();
    defer engine.releaseNativeValue(new_headers);
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
    defer engine.releaseNativeValue(catalog);
    try sdk.put(engine, data, "builtinProviders", try sdk.invoke(engine, catalog, "getProviders", &.{}));
    try reload(engine, data, c.pi_js_undefined());
}
pub fn configuredStatus(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !?c.JSValue {
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.releaseNativeValue(config);
    if (!c.JS_IsObject(config)) return null;
    const providers = try sdk.get(engine, config, "providers");
    defer engine.releaseNativeValue(providers);
    const provider = try models.property(engine, providers, id);
    defer engine.releaseNativeValue(provider);
    const extensions = try sdk.get(engine, data, "registeredExtensions");
    defer engine.releaseNativeValue(extensions);
    const extension = try sdk.invoke(engine, extensions, "get", &.{id});
    defer engine.releaseNativeValue(extension);
    const configured_key = if (c.JS_IsObject(provider)) try sdk.get(engine, provider, "apiKey") else c.pi_js_undefined();
    defer engine.releaseNativeValue(configured_key);
    const raw_value = try valueOr(engine, extension, "apiKey", configured_key);
    defer engine.releaseNativeValue(raw_value);
    if (c.JS_IsUndefined(raw_value)) return null;
    const raw = try nativeText(engine, raw_value);
    defer engine.gpa.free(raw);
    const references = try nativeAllocation(engine, @import("native_sdk_config_value.zig").names(engine.gpa, raw));
    defer engine.gpa.free(references);
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
    const configured = try @import("native_sdk_config_value.zig").configured(engine, raw);
    try sdk.put(engine, result, "configured", c.pi_js_bool(engine.context, @intFromBool(configured)));
    if (configured) {
        const extension_key = if (c.JS_IsObject(extension)) try sdk.get(engine, extension, "apiKey") else c.pi_js_undefined();
        defer engine.releaseNativeValue(extension_key);
        const source = if (std.mem.startsWith(u8, raw, "!")) "models_json_command" else if (references.len > 0) "environment" else if (!c.JS_IsUndefined(extension_key)) "fallback" else "models_json_key";
        try sdk.put(engine, result, "source", try sdk.text(engine, source));
        if (references.len > 0) {
            const names = try nativeAllocation(engine, std.mem.join(engine.gpa, ", ", references));
            defer engine.gpa.free(names);
            try sdk.put(engine, result, "label", try sdk.text(engine, names));
        }
    }
    return result;
}
fn mapKeys(engine: *engine_mod.Engine, map: c.JSValue) !c.JSValue {
    const iterator = try sdk.invoke(engine, map, "keys", &.{});
    defer engine.releaseNativeValue(iterator);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.releaseNativeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.releaseNativeValue(array);
    return sdk.invoke(engine, array, "from", &.{iterator});
}
fn baseProvider(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !c.JSValue {
    const native = try sdk.get(engine, data, "registeredNative");
    defer engine.releaseNativeValue(native);
    const provider = try sdk.invoke(engine, native, "get", &.{id});
    if (c.JS_IsObject(provider)) return provider;
    engine.releaseNativeValue(provider);
    return builtinProvider(engine, data, id);
}
fn builtinProvider(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !c.JSValue {
    const builtins = try sdk.get(engine, data, "builtinProviders");
    defer engine.releaseNativeValue(builtins);
    for (0..try sdk.length(engine, builtins)) |index| {
        try engine.checkNativeEntry();
        const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, builtins, @intCast(index)));
        defer engine.releaseNativeValue(candidate);
        const candidate_id = try sdk.get(engine, candidate, "id");
        defer engine.releaseNativeValue(candidate_id);
        if (c.JS_IsStrictEqual(engine.context, candidate_id, id)) return c.JS_DupValue(engine.context, candidate);
    }
    return c.pi_js_undefined();
}
fn prepare(engine: *engine_mod.Engine, data: c.JSValue, config: c.JSValue, id: c.JSValue, errors: c.JSValue) !c.JSValue {
    const base = try preparePhysical(engine, data, config, id, errors);
    defer engine.releaseNativeValue(base);
    return @import("native_sdk_virtual.zig").withModels(engine, data, id, base);
}
fn preparePhysical(engine: *engine_mod.Engine, data: c.JSValue, config: c.JSValue, id: c.JSValue, errors: c.JSValue) !c.JSValue {
    const providers = try sdk.get(engine, config, "providers");
    defer engine.releaseNativeValue(providers);
    const settings = try models.property(engine, providers, id);
    defer engine.releaseNativeValue(settings);
    const base = try baseProvider(engine, data, id);
    defer engine.releaseNativeValue(base);
    const deleted = try sdk.invoke(engine, errors, "delete", &.{id});
    engine.releaseNativeValue(deleted);
    const extensions = try sdk.get(engine, data, "registeredExtensions");
    defer engine.releaseNativeValue(extensions);
    const extension = try sdk.invoke(engine, extensions, "get", &.{id});
    defer engine.releaseNativeValue(extension);
    if (!c.JS_IsObject(settings) and !c.JS_IsObject(extension)) {
        // Unmodified native providers retain their actual object identity.
        return c.JS_DupValue(engine.context, base);
    }
    return compose(engine, id, base, settings, extension) catch |err| {
        try @import("native_pending_owner.zig").catchFailure(engine, err);
        if (err != error.JavaScriptException) return err;
        const exception = if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else return err;
        defer engine.releaseNativeValue(exception);
        const message = try sdk.get(engine, exception, "message");
        defer engine.releaseNativeValue(message);
        const name = try nativeText(engine, id);
        defer engine.gpa.free(name);
        const reason = try nativeText(engine, message);
        defer engine.gpa.free(reason);
        const text = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider \"{s}\": {s}", .{ name, reason }));
        defer engine.gpa.free(text);
        const value = try sdk.text(engine, text);
        defer engine.releaseNativeValue(value);
        const ignored = try sdk.invoke(engine, errors, "set", &.{ id, value });
        engine.releaseNativeValue(ignored);
        return c.JS_DupValue(engine.context, base);
    };
}
pub fn extensionProvider(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, extension: c.JSValue) !c.JSValue {
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.releaseNativeValue(config);
    const providers = try sdk.get(engine, config, "providers");
    defer engine.releaseNativeValue(providers);
    const settings = try models.property(engine, providers, id);
    defer engine.releaseNativeValue(settings);
    const base = try builtinProvider(engine, data, id);
    defer engine.releaseNativeValue(base);
    const stream = try sdk.get(engine, extension, "streamSimple");
    defer engine.releaseNativeValue(stream);
    const api = try sdk.get(engine, extension, "api");
    defer engine.releaseNativeValue(api);
    if (c.JS_IsFunction(engine.context, stream) and c.JS_ToBool(engine.context, api) != 1) {
        const name = try nativeText(engine, id);
        defer engine.gpa.free(name);
        const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider {s}: \"api\" is required when registering streamSimple.", .{name}));
        defer engine.gpa.free(message);
        return reject(engine, message);
    }
    return compose(engine, id, base, settings, extension);
}
pub fn recompose(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !void {
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.releaseNativeValue(config);
    const errors = try sdk.get(engine, data, "compositionErrors");
    defer engine.releaseNativeValue(errors);
    const provider = try prepare(engine, data, config, id, errors);
    defer engine.releaseNativeValue(provider);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.releaseNativeValue(catalog);
    const result = if (c.JS_IsObject(provider)) try sdk.invoke(engine, catalog, "setProvider", &.{provider}) else try sdk.invoke(engine, catalog, "deleteProvider", &.{id});
    engine.releaseNativeValue(result);
}
pub fn reload(engine: *engine_mod.Engine, data: c.JSValue, selected: c.JSValue) !void {
    const options = try sdk.get(engine, data, "options");
    defer engine.releaseNativeValue(options);
    const config = try @import("native_sdk_model_config.zig").load(engine, options);
    defer engine.releaseNativeValue(config);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.releaseNativeValue(catalog);
    const errors = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.releaseNativeValue(errors);
    const ids = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Set");
    defer engine.releaseNativeValue(ids);
    if (c.JS_IsArray(selected)) {
        const previous = try sdk.get(engine, data, "compositionErrors");
        defer engine.releaseNativeValue(previous);
        if (c.JS_IsObject(previous)) {
            const previous_ids = try mapKeys(engine, previous);
            defer engine.releaseNativeValue(previous_ids);
            for (0..try sdk.length(engine, previous_ids)) |index| {
                try engine.checkNativeEntry();
                const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, previous_ids, @intCast(index)));
                defer engine.releaseNativeValue(id);
                const message = try sdk.invoke(engine, previous, "get", &.{id});
                defer engine.releaseNativeValue(message);
                const ignored = try sdk.invoke(engine, errors, "set", &.{ id, message });
                engine.releaseNativeValue(ignored);
            }
        }
        for (0..try sdk.length(engine, selected)) |index| {
            try engine.checkNativeEntry();
            const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, selected, @intCast(index)));
            defer engine.releaseNativeValue(id);
            const ignored = try sdk.invoke(engine, ids, "add", &.{id});
            engine.releaseNativeValue(ignored);
        }
    } else {
        const builtins = try sdk.get(engine, data, "builtinProviders");
        defer engine.releaseNativeValue(builtins);
        for (0..try sdk.length(engine, builtins)) |index| {
            try engine.checkNativeEntry();
            const provider = try engine.checked(c.JS_GetPropertyUint32(engine.context, builtins, @intCast(index)));
            defer engine.releaseNativeValue(provider);
            const id = try sdk.get(engine, provider, "id");
            defer engine.releaseNativeValue(id);
            const ignored = try sdk.invoke(engine, ids, "add", &.{id});
            engine.releaseNativeValue(ignored);
        }
        inline for (.{ "registeredNative", "modelConfig", "registeredExtensions", "virtualModels" }) |field| {
            const map = if (comptime std.mem.eql(u8, field, "modelConfig")) try sdk.get(engine, config, "providers") else try sdk.get(engine, data, field);
            defer engine.releaseNativeValue(map);
            const names = if (comptime std.mem.eql(u8, field, "modelConfig")) try keys(engine, map) else try mapKeys(engine, map);
            defer engine.releaseNativeValue(names);
            for (0..try sdk.length(engine, names)) |index| {
                try engine.checkNativeEntry();
                const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, @intCast(index)));
                defer engine.releaseNativeValue(id);
                const ignored = try sdk.invoke(engine, ids, "add", &.{id});
                engine.releaseNativeValue(ignored);
            }
        }
    }
    const ordered = try mapKeys(engine, ids);
    defer engine.releaseNativeValue(ordered);
    const prepared = try sdk.array(engine);
    defer engine.releaseNativeValue(prepared);
    for (0..try sdk.length(engine, ordered)) |index| {
        try engine.checkNativeEntry();
        const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, ordered, @intCast(index)));
        defer engine.releaseNativeValue(id);
        try sdk.append(engine, prepared, try prepare(engine, data, config, id, errors));
    }
    if (!c.JS_IsArray(selected)) {
        const cleared = try sdk.invoke(engine, catalog, "clearProviders", &.{});
        engine.releaseNativeValue(cleared);
    }
    for (0..try sdk.length(engine, prepared)) |index| {
        try engine.checkNativeEntry();
        const provider = try engine.checked(c.JS_GetPropertyUint32(engine.context, prepared, @intCast(index)));
        defer engine.releaseNativeValue(provider);
        if (c.JS_IsObject(provider)) {
            const ignored = try sdk.invoke(engine, catalog, "setProvider", &.{provider});
            engine.releaseNativeValue(ignored);
        } else if (c.JS_IsArray(selected)) {
            try engine.checkNativeEntry();
            const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, ordered, @intCast(index)));
            defer engine.releaseNativeValue(id);
            const ignored = try sdk.invoke(engine, catalog, "deleteProvider", &.{id});
            engine.releaseNativeValue(ignored);
        }
    }
    try sdk.put(engine, data, "modelConfig", c.JS_DupValue(engine.context, config));
    try sdk.put(engine, data, "compositionErrors", c.JS_DupValue(engine.context, errors));
    try @import("native_sdk_auth_snapshot.zig").updateModels(engine, data);
}

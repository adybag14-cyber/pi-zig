//! models.json auth overlays; asynchronous user environment and inherited auth
//! are chained on the VM owner, preserving original callback exceptions.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const model = @import("native_sdk_models.zig");
const config_value = @import("native_sdk_config_value.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Stage = enum(c_int) { check, resolve, checked, key, decorate, header };
fn function(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage) !c.JSValue {
    var data = [_]c.JSValue{job};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "configuredProviderAuth", 1, @intFromEnum(stage), 1, &data));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return advance(engine, data[0], @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn then(engine: *engine_mod.Engine, pending: c.JSValue, job: c.JSValue, stage: Stage) !c.JSValue {
    const adopted = try sdk.promise(engine, pending);
    defer engine.freeValue(adopted);
    const done = try function(engine, job, stage);
    defer engine.freeValue(done);
    return sdk.invoke(engine, adopted, "then", &.{done});
}
pub fn install(engine: *engine_mod.Engine, provider: c.JSValue, base: c.JSValue, config: c.JSValue, id: c.JSValue) !void {
    const auth = try sdk.object(engine);
    defer engine.freeValue(auth);
    const base_auth = if (c.JS_IsObject(base)) try sdk.get(engine, base, "auth") else c.pi_js_undefined();
    defer engine.freeValue(base_auth);
    try model.copy(engine, auth, base_auth);
    const inherited = if (c.JS_IsObject(base_auth)) try sdk.get(engine, base_auth, "apiKey") else c.pi_js_undefined();
    defer engine.freeValue(inherited);
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "config", c.JS_DupValue(engine.context, config));
    try sdk.put(engine, job, "inherited", c.JS_DupValue(engine.context, inherited));
    try sdk.put(engine, job, "id", c.JS_DupValue(engine.context, id));
    const method = try sdk.object(engine);
    defer engine.freeValue(method);
    try model.copy(engine, method, inherited);
    try sdk.put(engine, method, "check", try function(engine, job, .check));
    try sdk.put(engine, method, "resolve", try function(engine, job, .resolve));
    try sdk.put(engine, auth, "apiKey", c.JS_DupValue(engine.context, method));
    try sdk.put(engine, provider, "auth", c.JS_DupValue(engine.context, auth));
}
fn output(engine: *engine_mod.Engine, value: c.JSValue, resolve: bool, source: []const u8) !c.JSValue {
    if (c.JS_ToBool(engine.context, value) != 1) return c.pi_js_undefined();
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "source", try sdk.text(engine, source));
    if (resolve) {
        const auth = try sdk.object(engine);
        defer engine.freeValue(auth);
        try sdk.put(engine, auth, "apiKey", c.JS_DupValue(engine.context, value));
        try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, auth));
    } else try sdk.put(engine, result, "type", try sdk.text(engine, "api_key"));
    return result;
}
fn advance(engine: *engine_mod.Engine, state: c.JSValue, stage: Stage, value: c.JSValue) !c.JSValue {
    if (stage == .check or stage == .resolve) {
        const job = try sdk.object(engine);
        defer engine.freeValue(job);
        try model.copy(engine, job, state);
        try sdk.put(engine, job, "input", c.JS_DupValue(engine.context, value));
        try sdk.put(engine, job, "resolve", c.pi_js_bool(engine.context, @intFromBool(stage == .resolve)));
        const inherited = try sdk.get(engine, job, "inherited");
        defer engine.freeValue(inherited);
        const credential = try sdk.get(engine, value, "credential");
        defer engine.freeValue(credential);
        const config = try sdk.get(engine, job, "config");
        defer engine.freeValue(config);
        const raw = try sdk.get(engine, config, "apiKey");
        defer engine.freeValue(raw);
        const method = if (stage == .resolve) "resolve" else "check";
        if (c.JS_IsObject(credential) or c.JS_IsUndefined(raw)) {
            const implementation = if (c.JS_IsObject(inherited)) try sdk.get(engine, inherited, method) else c.pi_js_undefined();
            defer engine.freeValue(implementation);
            const result = if (c.JS_IsFunction(engine.context, implementation)) try sdk.invoke(engine, inherited, method, &.{value}) else if (c.JS_IsObject(credential)) fallback: {
                const key = try sdk.get(engine, credential, "key");
                defer engine.freeValue(key);
                break :fallback try output(engine, key, stage == .resolve, "stored credential");
            } else c.pi_js_undefined();
            defer engine.freeValue(result);
            return if (stage == .resolve) then(engine, result, job, .decorate) else sdk.promise(engine, result);
        }
        const ctx = try sdk.get(engine, value, "ctx");
        defer engine.freeValue(ctx);
        const id = try sdk.get(engine, job, "id");
        defer engine.freeValue(id);
        const name = try engine.toString(id);
        defer engine.gpa.free(name);
        const description = try std.fmt.allocPrint(engine.gpa, "API key for provider \"{s}\"", .{name});
        defer engine.gpa.free(description);
        const desc = try sdk.text(engine, description);
        defer engine.freeValue(desc);
        const pending = try config_value.start(engine, raw, ctx, c.pi_js_undefined(), stage == .check, desc);
        defer engine.freeValue(pending);
        return then(engine, pending, job, if (stage == .check) .checked else .key);
    }
    if (stage == .checked) return output(engine, value, false, "configured API key");
    if (stage == .key) {
        const input = try sdk.get(engine, state, "input");
        defer engine.freeValue(input);
        const inherited = try sdk.get(engine, state, "inherited");
        defer engine.freeValue(inherited);
        const implementation = if (c.JS_IsObject(inherited)) try sdk.get(engine, inherited, "resolve") else c.pi_js_undefined();
        defer engine.freeValue(implementation);
        const pending = if (c.JS_IsFunction(engine.context, implementation)) delegated: {
            const parameters = try sdk.object(engine);
            defer engine.freeValue(parameters);
            try model.copy(engine, parameters, input);
            const credential = try sdk.object(engine);
            defer engine.freeValue(credential);
            try sdk.put(engine, credential, "type", try sdk.text(engine, "api_key"));
            try sdk.put(engine, credential, "key", c.JS_DupValue(engine.context, value));
            try sdk.put(engine, parameters, "credential", c.JS_DupValue(engine.context, credential));
            break :delegated try sdk.invoke(engine, inherited, "resolve", &.{parameters});
        } else try output(engine, value, true, "configured API key");
        defer engine.freeValue(pending);
        return then(engine, pending, state, .decorate);
    }
    if (stage == .decorate) {
        if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
        const result = try sdk.object(engine);
        defer engine.freeValue(result);
        try model.copy(engine, result, value);
        const auth = try sdk.object(engine);
        defer engine.freeValue(auth);
        const original = try sdk.get(engine, value, "auth");
        defer engine.freeValue(original);
        try model.copy(engine, auth, original);
        try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, auth));
        try sdk.put(engine, state, "result", c.JS_DupValue(engine.context, result));
        const config = try sdk.get(engine, state, "config");
        defer engine.freeValue(config);
        const headers = try sdk.get(engine, config, "headers");
        defer engine.freeValue(headers);
        const merged = try sdk.object(engine);
        defer engine.freeValue(merged);
        const old = try sdk.get(engine, auth, "headers");
        defer engine.freeValue(old);
        try model.copy(engine, merged, old);
        try sdk.put(engine, state, "headers", c.JS_DupValue(engine.context, merged));
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const object = try sdk.get(engine, global, "Object");
        defer engine.freeValue(object);
        try sdk.put(engine, state, "headerNames", if (c.JS_IsObject(headers)) try sdk.invoke(engine, object, "keys", &.{headers}) else try sdk.array(engine));
        try sdk.put(engine, state, "headerIndex", c.JS_NewInt32(engine.context, 0));
        return decorateNext(engine, state);
    }
    const headers = try sdk.get(engine, state, "headers");
    defer engine.freeValue(headers);
    const key = try sdk.get(engine, state, "headerKey");
    defer engine.freeValue(key);
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, headers, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return decorateNext(engine, state);
}
fn decorateNext(engine: *engine_mod.Engine, job: c.JSValue) !c.JSValue {
    const config = try sdk.get(engine, job, "config");
    defer engine.freeValue(config);
    const result = try sdk.get(engine, job, "result");
    errdefer engine.freeValue(result);
    const names = try sdk.get(engine, job, "headerNames");
    defer engine.freeValue(names);
    const position = try sdk.get(engine, job, "headerIndex");
    defer engine.freeValue(position);
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, position) < 0) return error.JavaScriptException;
    if (index < try sdk.length(engine, names)) {
        defer engine.freeValue(result);
        const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, index));
        defer engine.freeValue(key);
        try sdk.put(engine, job, "headerIndex", c.JS_NewUint32(engine.context, index + 1));
        try sdk.put(engine, job, "headerKey", c.JS_DupValue(engine.context, key));
        const raw_headers = try sdk.get(engine, config, "headers");
        defer engine.freeValue(raw_headers);
        const raw = try model.property(engine, raw_headers, key);
        defer engine.freeValue(raw);
        const input = try sdk.get(engine, job, "input");
        defer engine.freeValue(input);
        const ctx = try sdk.get(engine, input, "ctx");
        defer engine.freeValue(ctx);
        const explicit = try sdk.object(engine);
        defer engine.freeValue(explicit);
        const credential = try sdk.get(engine, input, "credential");
        defer engine.freeValue(credential);
        const credential_env = if (c.JS_IsObject(credential)) try sdk.get(engine, credential, "env") else c.pi_js_undefined();
        defer engine.freeValue(credential_env);
        const env = try sdk.get(engine, result, "env");
        defer engine.freeValue(env);
        try model.copy(engine, explicit, credential_env);
        try model.copy(engine, explicit, env);
        const id = try sdk.get(engine, job, "id");
        defer engine.freeValue(id);
        const id_text = try engine.toString(id);
        defer engine.gpa.free(id_text);
        const key_text = try engine.toString(key);
        defer engine.gpa.free(key_text);
        const desc_text = try std.fmt.allocPrint(engine.gpa, "header \"{s}\" for provider \"{s}\"", .{ key_text, id_text });
        defer engine.gpa.free(desc_text);
        const desc = try sdk.text(engine, desc_text);
        defer engine.freeValue(desc);
        const pending = try config_value.start(engine, raw, ctx, explicit, false, desc);
        defer engine.freeValue(pending);
        return then(engine, pending, job, .header);
    }
    const auth = try sdk.get(engine, result, "auth");
    defer engine.freeValue(auth);
    const headers = try sdk.get(engine, job, "headers");
    defer engine.freeValue(headers);
    const flag = try sdk.get(engine, config, "authHeader");
    defer engine.freeValue(flag);
    if (c.JS_ToBool(engine.context, flag) == 1) {
        const key = try sdk.get(engine, auth, "apiKey");
        defer engine.freeValue(key);
        if (c.JS_ToBool(engine.context, key) != 1) {
            _ = c.JS_ThrowInternalError(engine.context, "authHeader requires a resolved API key");
            return error.JavaScriptException;
        }
        const key_text = try engine.toString(key);
        defer engine.gpa.free(key_text);
        const bearer = try std.fmt.allocPrint(engine.gpa, "Bearer {s}", .{key_text});
        defer engine.gpa.free(bearer);
        try sdk.put(engine, headers, "Authorization", try sdk.text(engine, bearer));
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    const keys = try sdk.invoke(engine, object, "keys", &.{headers});
    defer engine.freeValue(keys);
    if (try sdk.length(engine, keys) != 0) try sdk.put(engine, auth, "headers", c.JS_DupValue(engine.context, headers));
    return result;
}

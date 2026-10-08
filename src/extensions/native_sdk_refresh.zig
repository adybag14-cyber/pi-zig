//! ModelRuntime refresh delegates real provider catalog work, then admits an
//! owned availability snapshot. No VM value crosses the owner thread.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const availability = @import("native_sdk_availability.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Stage = enum(c_int) { catalog, available, available_failed, provider_available, provider_failed, complete, created };
fn function(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage) !c.JSValue {
    var captured = [_]c.JSValue{job};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "sdkModelRefresh", 1, @intFromEnum(stage), 1, &captured));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, stage: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return advance(engine, data[0], @enumFromInt(stage), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn then(engine: *engine_mod.Engine, value: c.JSValue, job: c.JSValue, good: Stage, bad: ?Stage) !c.JSValue {
    const pending = try sdk.promise(engine, value);
    defer engine.freeValue(pending);
    const fulfilled = try function(engine, job, good);
    defer engine.freeValue(fulfilled);
    const rejected = if (bad) |stage| try function(engine, job, stage) else c.pi_js_undefined();
    defer engine.freeValue(rejected);
    return sdk.invoke(engine, pending, "then", &.{ fulfilled, rejected });
}
fn sequences(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const stored = try sdk.get(engine, data, "providerAvailabilitySequences");
    if (c.JS_IsObject(stored)) return stored;
    engine.freeValue(stored);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const map = try sdk.get(engine, global, "Map");
    defer engine.freeValue(map);
    const result = try engine.checked(c.JS_CallConstructor(engine.context, map, 0, null));
    errdefer engine.freeValue(result);
    try sdk.put(engine, data, "providerAvailabilitySequences", c.JS_DupValue(engine.context, result));
    return result;
}
fn bump(engine: *engine_mod.Engine, map: c.JSValue, id: c.JSValue) !c.JSValue {
    const previous = try sdk.invoke(engine, map, "get", &.{id});
    defer engine.freeValue(previous);
    var number: f64 = 0;
    if (!c.JS_IsUndefined(previous) and c.JS_ToFloat64(engine.context, &number, previous) < 0) return error.JavaScriptException;
    if (number >= 9007199254740991) return error.NativeSDKRevisionOverflow;
    const next = c.JS_NewFloat64(engine.context, number + 1);
    const result = try sdk.invoke(engine, map, "set", &.{ id, next });
    engine.freeValue(result);
    return next;
}
pub fn invalidateProviderQueries(engine: *engine_mod.Engine, data: c.JSValue) !void {
    const map = try sequences(engine, data);
    defer engine.freeValue(map);
    const iterator = try sdk.invoke(engine, map, "keys", &.{});
    defer engine.freeValue(iterator);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.freeValue(array);
    const ids = try sdk.invoke(engine, array, "from", &.{iterator});
    defer engine.freeValue(ids);
    for (0..try sdk.length(engine, ids)) |index| {
        const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, ids, @intCast(index)));
        defer engine.freeValue(id);
        _ = try bump(engine, map, id);
    }
}
fn networkEnabled(engine: *engine_mod.Engine) !bool {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try sdk.get(engine, global, "process");
    defer engine.freeValue(process);
    const env = try sdk.get(engine, process, "env");
    defer engine.freeValue(env);
    const offline = try sdk.get(engine, env, "PI_OFFLINE");
    defer engine.freeValue(offline);
    return c.JS_IsUndefined(offline);
}
pub fn start(engine: *engine_mod.Engine, runtime: c.JSValue, options: c.JSValue) !c.JSValue {
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "runtime", c.JS_DupValue(engine.context, runtime));
    const copied = try sdk.object(engine);
    defer engine.freeValue(copied);
    try @import("native_sdk_models.zig").copy(engine, copied, options);
    const allow = try sdk.get(engine, copied, "allowNetwork");
    defer engine.freeValue(allow);
    if (c.JS_IsUndefined(allow) or c.JS_IsNull(allow)) try sdk.put(engine, copied, "allowNetwork", c.pi_js_bool(engine.context, @intFromBool(try networkEnabled(engine))));
    try sdk.put(engine, job, "options", c.JS_DupValue(engine.context, copied));
    const owner = try sdk.state(engine, runtime);
    const selected = try sdk.get(engine, copied, "providers");
    defer engine.freeValue(selected);
    try @import("native_sdk_provider_composer.zig").reload(engine, owner.data, selected);
    const catalog = try sdk.get(engine, owner.data, "models");
    defer engine.freeValue(catalog);
    const pending = try sdk.invoke(engine, catalog, "refresh", &.{copied});
    defer engine.freeValue(pending);
    return then(engine, pending, job, .catalog, null);
}
pub fn created(engine: *engine_mod.Engine, runtime: c.JSValue, options: c.JSValue) !c.JSValue {
    const refresh_on_create = if (c.JS_IsObject(options)) try sdk.get(engine, options, "refreshOnCreate") else c.pi_js_undefined();
    defer engine.freeValue(refresh_on_create);
    if (c.JS_IsBool(refresh_on_create) and c.JS_ToBool(engine.context, refresh_on_create) == 0) return sdk.promise(engine, runtime);
    const allow = if (c.JS_IsObject(options)) try sdk.get(engine, options, "allowModelNetwork") else c.pi_js_undefined();
    defer engine.freeValue(allow);
    const refresh_options = try sdk.object(engine);
    defer engine.freeValue(refresh_options);
    try sdk.put(engine, refresh_options, "allowNetwork", c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, allow) == 1 and try networkEnabled(engine))));
    if (c.JS_IsObject(options)) try sdk.put(engine, refresh_options, "signal", try sdk.get(engine, options, "signal"));
    const pending = try start(engine, runtime, refresh_options);
    defer engine.freeValue(pending);
    return then(engine, pending, runtime, .created, null);
}
fn settledResult(engine: *engine_mod.Engine, job: c.JSValue) !c.JSValue {
    const value = try sdk.get(engine, job, "result");
    errdefer engine.freeValue(value);
    const options = try sdk.get(engine, job, "options");
    defer engine.freeValue(options);
    const signal = try sdk.get(engine, options, "signal");
    defer engine.freeValue(signal);
    if (c.JS_IsObject(signal)) {
        const aborted = try sdk.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        if (c.JS_ToBool(engine.context, aborted) == 1) try sdk.put(engine, value, "aborted", c.pi_js_bool(engine.context, 1));
    }
    return value;
}
fn advance(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage, value: c.JSValue) !c.JSValue {
    if (stage == .created) return c.JS_DupValue(engine.context, job);
    if (stage == .complete or stage == .available or stage == .available_failed) return settledResult(engine, job);
    const runtime = try sdk.get(engine, job, "runtime");
    defer engine.freeValue(runtime);
    const owner = try sdk.state(engine, runtime);
    const options = try sdk.get(engine, job, "options");
    defer engine.freeValue(options);
    const catalog = try sdk.get(engine, owner.data, "models");
    defer engine.freeValue(catalog);
    if (stage == .catalog) {
        try sdk.put(engine, job, "result", c.JS_DupValue(engine.context, value));
        try @import("native_sdk_auth_snapshot.zig").updateModels(engine, owner.data);
        const selected = try sdk.get(engine, options, "providers");
        defer engine.freeValue(selected);
        if (!c.JS_IsArray(selected)) {
            const pending = try availability.getAvailable(engine, runtime, &.{ c.pi_js_undefined(), options });
            defer engine.freeValue(pending);
            return then(engine, pending, job, .available, .available_failed);
        }
        const map = try sequences(engine, owner.data);
        defer engine.freeValue(map);
        const pending = try sdk.array(engine);
        defer engine.freeValue(pending);
        for (0..try sdk.length(engine, selected)) |index| {
            const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, selected, @intCast(index)));
            defer engine.freeValue(id);
            const first_index = try sdk.invoke(engine, selected, "indexOf", &.{id});
            defer engine.freeValue(first_index);
            var earliest: u32 = 0;
            if (c.JS_ToUint32(engine.context, &earliest, first_index) < 0) return error.JavaScriptException;
            if (earliest != index) continue;
            const child = try sdk.object(engine);
            defer engine.freeValue(child);
            inline for (.{ "runtime", "options", "result" }) |name| try sdk.put(engine, child, name, try sdk.get(engine, job, name));
            try sdk.put(engine, child, "id", c.JS_DupValue(engine.context, id));
            try sdk.put(engine, child, "sequence", try bump(engine, map, id));
            if (owner.availability_sequence >= 9007199254740991) return error.NativeSDKRevisionOverflow;
            owner.availability_sequence += 1;
            owner.availability_error_sequence = std.math.add(u64, owner.availability_error_sequence, 1) catch return error.NativeSDKRevisionOverflow;
            try sdk.put(engine, child, "errorSequence", c.JS_NewFloat64(engine.context, @floatFromInt(owner.availability_error_sequence)));
            const available = try sdk.invoke(engine, catalog, "getAvailable", &.{ id, options });
            defer engine.freeValue(available);
            const checked = try sdk.invoke(engine, catalog, "checkAuth", &.{ id, options });
            defer engine.freeValue(checked);
            const credentials = try @import("native_sdk_models.zig").credentials(engine, owner.data);
            defer engine.freeValue(credentials);
            const credential = try sdk.invoke(engine, credentials, "read", &.{ id, options });
            defer engine.freeValue(credential);
            const inputs = try sdk.array(engine);
            defer engine.freeValue(inputs);
            inline for (.{ available, checked, credential }) |input| try sdk.append(engine, inputs, c.JS_DupValue(engine.context, input));
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const promise = try sdk.get(engine, global, "Promise");
            defer engine.freeValue(promise);
            const gathered = try sdk.invoke(engine, promise, "all", &.{inputs});
            defer engine.freeValue(gathered);
            try sdk.append(engine, pending, try then(engine, gathered, child, .provider_available, .provider_failed));
        }
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const promise = try sdk.get(engine, global, "Promise");
        defer engine.freeValue(promise);
        const all = try sdk.invoke(engine, promise, "all", &.{pending});
        defer engine.freeValue(all);
        return then(engine, all, job, .complete, null);
    }
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const signal = try sdk.get(engine, options, "signal");
    defer engine.freeValue(signal);
    if (c.JS_IsObject(signal)) {
        const aborted = try sdk.get(engine, signal, "aborted");
        defer engine.freeValue(aborted);
        if (c.JS_ToBool(engine.context, aborted) == 1) return c.pi_js_undefined();
    }
    if (stage == .provider_failed) {
        const error_serial = try sdk.get(engine, job, "errorSequence");
        defer engine.freeValue(error_serial);
        try availability.recordFailure(engine, runtime, error_serial, options, value);
        const output = try sdk.get(engine, job, "result");
        defer engine.freeValue(output);
        const errors = try sdk.get(engine, output, "errors");
        defer engine.freeValue(errors);
        const failure = if (c.JS_IsError(value)) c.JS_DupValue(engine.context, value) else wrapped: {
            const message = try engine.toString(value);
            defer engine.gpa.free(message);
            const error_value = try engine.checked(c.JS_NewError(engine.context));
            errdefer engine.freeValue(error_value);
            try sdk.put(engine, error_value, "message", try sdk.text(engine, message));
            break :wrapped error_value;
        };
        defer engine.freeValue(failure);
        const ignored = try sdk.invoke(engine, errors, "set", &.{ id, failure });
        engine.freeValue(ignored);
        return c.pi_js_undefined();
    }
    const map = try sequences(engine, owner.data);
    defer engine.freeValue(map);
    const expected = try sdk.get(engine, job, "sequence");
    defer engine.freeValue(expected);
    const latest = try sdk.invoke(engine, map, "get", &.{id});
    defer engine.freeValue(latest);
    if (!c.JS_IsStrictEqual(engine.context, expected, latest)) return c.pi_js_undefined();
    const available_rows = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, 0));
    defer engine.freeValue(available_rows);
    const auth_check = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, 1));
    defer engine.freeValue(auth_check);
    const credential = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, 2));
    defer engine.freeValue(credential);
    const previous = try sdk.get(engine, owner.data, "available");
    defer engine.freeValue(previous);
    const candidates = try sdk.array(engine);
    defer engine.freeValue(candidates);
    for (0..try sdk.length(engine, previous)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, previous, @intCast(index)));
        defer engine.freeValue(row);
        const provider = try sdk.get(engine, row, "provider");
        defer engine.freeValue(provider);
        if (!c.JS_IsStrictEqual(engine.context, provider, id)) try sdk.append(engine, candidates, c.JS_DupValue(engine.context, row));
    }
    for (0..try sdk.length(engine, available_rows)) |index| try sdk.append(engine, candidates, try engine.checked(c.JS_GetPropertyUint32(engine.context, available_rows, @intCast(index))));
    const all = try sdk.invoke(engine, catalog, "getModels", &.{});
    defer engine.freeValue(all);
    const rows = try sdk.array(engine);
    defer engine.freeValue(rows);
    for (0..try sdk.length(engine, all)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, all, @intCast(index)));
        defer engine.freeValue(row);
        const provider = try sdk.get(engine, row, "provider");
        defer engine.freeValue(provider);
        const model_id = try sdk.get(engine, row, "id");
        defer engine.freeValue(model_id);
        for (0..try sdk.length(engine, candidates)) |candidate_index| {
            const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, candidates, @intCast(candidate_index)));
            defer engine.freeValue(candidate);
            const candidate_provider = try sdk.get(engine, candidate, "provider");
            defer engine.freeValue(candidate_provider);
            const candidate_id = try sdk.get(engine, candidate, "id");
            defer engine.freeValue(candidate_id);
            if (c.JS_IsStrictEqual(engine.context, provider, candidate_provider) and c.JS_IsStrictEqual(engine.context, model_id, candidate_id)) {
                try sdk.append(engine, rows, c.JS_DupValue(engine.context, candidate));
                break;
            }
        }
    }
    const error_serial = try sdk.get(engine, job, "errorSequence");
    defer engine.freeValue(error_serial);
    const auth_state = try @import("native_sdk_auth_snapshot.zig").prepareProvider(engine, owner.data, id, auth_check, credential);
    defer engine.freeValue(auth_state);
    try availability.admitAuth(engine, runtime, rows, auth_state, error_serial);
    return c.pi_js_undefined();
}

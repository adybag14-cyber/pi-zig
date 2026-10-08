//! Typed Main-provider calls stay inside their admitted callback owner's VM.
//! Only JSON crosses the broker; signal/model roots are made on this owner.
const std = @import("std");
const engine_mod = @import("engine.zig");
const values = @import("native_values.zig");
const providers = @import("native_providers.zig");
const c = engine_mod.c;
pub const Operation = enum { classify, generate_images };
fn copyProperties(engine: *engine_mod.Engine, target: c.JSValue, source: c.JSValue) !void {
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        const value = try engine.checked(c.JS_GetProperty(engine.context, source, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, target, entry.atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
}
fn canonicalModel(engine: *engine_mod.Engine, callback: providers.Providers.Invocation, selected: c.JSValue, operation: Operation) !c.JSValue {
    const root_path = if (operation == .classify) "classify" else "generateImages";
    if (!std.mem.eql(u8, callback.path, root_path)) return c.JS_DupValue(engine.context, selected);
    var getter = try values.get(engine, callback.receiver, "getAllModels");
    defer engine.freeValue(getter);
    if (!c.JS_IsFunction(engine.context, getter)) {
        const next = try values.get(engine, callback.receiver, "getModels");
        engine.freeValue(getter);
        getter = next;
    }
    if (!c.JS_IsFunction(engine.context, getter)) return c.JS_DupValue(engine.context, selected);
    const pending = try engine.checked(c.JS_Call(engine.context, getter, callback.receiver, 0, null));
    defer engine.freeValue(pending);
    const models = try engine.awaitValue(pending);
    defer engine.freeValue(models);
    if (!c.JS_IsArray(models)) return error.InvalidNativeProviderModels;
    const wanted_id = try values.get(engine, selected, "id");
    defer engine.freeValue(wanted_id);
    const wanted_type = try engine.checked(c.JS_NewString(engine.context, if (operation == .classify) "classifier" else "image"));
    defer engine.freeValue(wanted_type);
    for (0..try values.length(engine, models)) |index| {
        const model = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(index)));
        errdefer engine.freeValue(model);
        const id = try values.get(engine, model, "id");
        defer engine.freeValue(id);
        const typ = try values.get(engine, model, "type");
        defer engine.freeValue(typ);
        if (c.JS_IsStrictEqual(engine.context, wanted_id, id) and c.JS_IsStrictEqual(engine.context, wanted_type, typ)) return model;
        engine.freeValue(model);
    }
    return error.UnknownNativeTypedModel;
}
pub fn invoke(
    engine: *engine_mod.Engine,
    registered: *providers.Providers,
    callback_id: []const u8,
    provider: []const u8,
    generation: u64,
    operation: Operation,
    model: c.JSValue,
    context: c.JSValue,
    options: c.JSValue,
    signal: c.JSValue,
    auth_rewrites_model: bool,
) !c.JSValue {
    const initial = try values.invoke(engine, signal, "throwIfAborted", &.{});
    engine.freeValue(initial);
    var callback = try registered.captureInvocation(callback_id, provider, generation);
    defer callback.deinit();
    const canonical = try canonicalModel(engine, callback, model, operation);
    defer engine.freeValue(canonical);
    // Re-registration while a getter awaited cannot redirect an old lease.
    try registered.validate(callback_id, provider, generation);
    const checked = try values.invoke(engine, signal, "throwIfAborted", &.{});
    engine.freeValue(checked);
    const request_model = if (auth_rewrites_model) try values.object(engine) else c.JS_DupValue(engine.context, canonical);
    defer engine.freeValue(request_model);
    if (auth_rewrites_model) {
        try copyProperties(engine, request_model, canonical);
        try values.put(engine, request_model, "baseUrl", try values.get(engine, model, "baseUrl"));
    }
    const request_options = try values.object(engine);
    defer engine.freeValue(request_options);
    if (c.JS_IsObject(options)) try copyProperties(engine, request_options, options);
    try values.put(engine, request_options, "signal", c.JS_DupValue(engine.context, signal));
    var args = [_]c.JSValue{ request_model, context, request_options };
    const pending = try engine.checked(c.JS_Call(engine.context, callback.function, callback.receiver, args.len, &args));
    defer engine.freeValue(pending);
    return engine.awaitValue(pending);
}

fn exerciseOwner(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("abort_signal.zig").install(engine);
    var registered = providers.Providers.init(engine);
    defer registered.deinit();
    const module = try engine.evalModule(@embedFile("fixtures/typed-provider-owner-6fb2e78.txt"), "typed-provider-owner.mjs");
    defer engine.freeValue(module);
    const provider = try values.get(engine, module, "provider");
    defer engine.freeValue(provider);
    const encoded = try registered.register("owned", provider, true);
    defer engine.freeValue(encoded);
    const result = try values.array(engine);
    defer engine.freeValue(result);
    for ([_]Operation{ .classify, .generate_images, .classify }, 0..) |operation, index| {
        const field: [:0]const u8 = if (operation == .classify) "classify" else "generateImages";
        const raw_descriptor = try values.get(engine, encoded, field);
        defer engine.freeValue(raw_descriptor);
        const descriptor_json = try engine.stringify(raw_descriptor);
        defer gpa.free(descriptor_json);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, descriptor_json, .{});
        defer parsed.deinit();
        const descriptor = try @import("provider_method_ref.zig").ProviderMethodRef.fromJson(parsed.value);
        const selected = try values.object(engine);
        defer engine.freeValue(selected);
        try values.put(engine, selected, "id", try engine.checked(c.JS_NewString(engine.context, "same")));
        try values.put(engine, selected, "baseUrl", try engine.checked(c.JS_NewString(engine.context, if (index == 2) "https://auth.invalid" else "https://fixture.invalid")));
        const context_text = if (operation == .classify) "{\"state\":{},\"questions\":{}}" else "{\"input\":[]}";
        const context = try engine.checked(c.JS_ParseJSON(engine.context, context_text, context_text.len, "context"));
        defer engine.freeValue(context);
        const options_text = if (index == 2) "{\"apiKey\":\"fixture-key\",\"headers\":{\"X-Auth\":\"one\"},\"env\":{\"AUTH_ENV\":\"yes\",\"REWRITE\":\"yes\"}}" else "{\"apiKey\":\"fixture-key\",\"headers\":{\"X-Auth\":\"one\"},\"env\":{\"AUTH_ENV\":\"yes\"}}";
        const options = try engine.checked(c.JS_ParseJSON(engine.context, options_text, options_text.len, "options"));
        defer engine.freeValue(options);
        const signal = try @import("abort_signal.zig").create(engine);
        defer engine.freeValue(signal);
        const value = try invoke(engine, &registered, descriptor.callback_id, "owned", descriptor.generation, operation, selected, context, options, signal, index == 2);
        if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), value) < 0) return error.JavaScriptException;
        try std.testing.expectError(error.StaleNativeProviderGeneration, registered.captureInvocation(descriptor.callback_id, "owned", descriptor.generation + 1));
        try @import("abort_signal.zig").abort(engine, signal, c.pi_js_undefined());
        try std.testing.expectError(error.JavaScriptException, invoke(engine, &registered, descriptor.callback_id, "owned", descriptor.generation, operation, selected, context, options, signal, false));
        engine.beginInvocation();
    }
    const actual = try engine.stringify(result);
    defer gpa.free(actual);
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("fixtures/typed-provider-owner-6fb2e78.json"), "\r\n"), actual);
    registered.unregister("owned");
    c.JS_RunGC(engine.runtime);
}

test "typed provider owner Source receiver canonical kind collision third option signal and auth clone" {
    try exerciseOwner(std.testing.allocator);
}
test "typed provider owner releases every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseOwner, .{});
}

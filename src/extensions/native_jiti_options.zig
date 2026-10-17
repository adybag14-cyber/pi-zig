//! jiti2.7 options.ts. Real realm globals/env reads and Source object spreads.
//! Derived from jiti2.7, Copyright Pooya Parsa, MIT (retained authority license).
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
const functions = @import("native_node_module_callable.zig");
fn put(engine: *v.em.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    return functions.create(engine, "resolveJitiOptions", 1, true, invoke, &.{});
}
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return resolve(engine, if (args.len > 0) args[0] else c.pi_js_undefined());
}
fn literal(s: *Scope, strings: []const []const u8) !c.JSValue {
    const array = try s.array();
    for (strings, 0..) |text, index| {
        const value = try s.text(text);
        if (c.JS_DefinePropertyValueUint32(s.engine.context, array, @intCast(index), c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
    }
    return array;
}
fn ignoreOrdinary(engine: *v.em.Engine, err: anyerror, generation: u64) !void {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingJitiOptionsCapturedReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    engine.freeValue(reason);
}
/// Exactly _jsonEnv: first process/env/value read, then a second live
/// process/env lookup for `in`. Only the JSON lookup/call is inside the catch.
fn jsonEnv(engine: *v.em.Engine, name: []const u8, fallback: c.JSValue, raw: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const key = try s.text(name);
    const value = try s.own(try v.js.getKey(engine, try s.get(try s.global("process"), "env"), key));
    if (!try v.js.hasKey(engine, try s.get(try s.global("process"), "env"), key)) return c.JS_DupValue(engine.context, fallback);
    const generation = engine.native_allocation_generation;
    const result = parseEnv(engine, value) catch |err| {
        try ignoreOrdinary(engine, err, generation);
        return c.JS_DupValue(engine.context, if (raw) value else fallback);
    };
    return result;
}
fn parseEnv(engine: *v.em.Engine, value: c.JSValue) !c.JSValue {
    const json = try v.js.global(engine, "JSON"); defer engine.freeValue(json);
    return v.js.invoke(engine, json, "parse", &.{value});
}
/// Boolean is the actual live global callable, not a native truthiness shortcut.
fn booleanEnv(engine: *v.em.Engine, name: []const u8, fallback: c.JSValue) !c.JSValue {
    const value = try jsonEnv(engine, name, fallback, false); defer engine.freeValue(value);
    const boolean = try v.js.global(engine, "Boolean"); defer engine.freeValue(boolean);
    return v.js.call(engine, boolean, c.pi_js_undefined(), &.{value});
}
fn invokeIgnored(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const function = try v.js.get(engine, receiver, name); defer engine.freeValue(function);
    const result = try v.js.call(engine, function, receiver, args); engine.freeValue(result);
}
/// Owned Source result. No factory, file cache or namespace is synthesized.
pub fn resolve(engine: *v.em.Engine, user_options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const yes = c.pi_js_bool(engine.context, 1);
    const no = c.pi_js_bool(engine.context, 0);
    const defaults = try s.object();
    {
        const fallback = try booleanEnv(engine, "JITI_CACHE", yes); defer engine.freeValue(fallback);
        const value = try booleanEnv(engine, "JITI_FS_CACHE", fallback); defer engine.freeValue(value);
        try put(engine, defaults, "fsCache", value);
    }
    try put(engine, defaults, "rebuildFsCache", try s.own(try booleanEnv(engine, "JITI_REBUILD_FS_CACHE", no)));
    {
        const fallback = try booleanEnv(engine, "JITI_REQUIRE_CACHE", yes); defer engine.freeValue(fallback);
        const value = try booleanEnv(engine, "JITI_MODULE_CACHE", fallback); defer engine.freeValue(value);
        try put(engine, defaults, "moduleCache", value);
    }
    try put(engine, defaults, "debug", try s.own(try booleanEnv(engine, "JITI_DEBUG", no)));
    try put(engine, defaults, "sourceMaps", try s.own(try booleanEnv(engine, "JITI_SOURCE_MAPS", no)));
    try put(engine, defaults, "interopDefault", try s.own(try booleanEnv(engine, "JITI_INTEROP_DEFAULT", yes)));
    const extensions = try literal(&s, &.{ ".js", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts", ".mtsx", ".ctsx" });
    try put(engine, defaults, "extensions", try s.own(try jsonEnv(engine, "JITI_EXTENSIONS", extensions, false)));
    try put(engine, defaults, "alias", try s.own(try jsonEnv(engine, "JITI_ALIAS", try s.object(), false)));
    try put(engine, defaults, "nativeModules", try s.own(try jsonEnv(engine, "JITI_NATIVE_MODULES", try literal(&s, &.{}), false)));
    try put(engine, defaults, "transformModules", try s.own(try jsonEnv(engine, "JITI_TRANSFORM_MODULES", try literal(&s, &.{}), false)));
    const bun = try v.js.hasKey(engine, try s.global("globalThis"), try s.text("Bun"));
    try put(engine, defaults, "tryNative", try s.own(try jsonEnv(engine, "JITI_TRY_NATIVE", c.pi_js_bool(engine.context, @intFromBool(bun)), false)));
    try put(engine, defaults, "esmEvalTempFile", try s.own(try booleanEnv(engine, "JITI_ESM_EVAL_TEMP_FILE", no)));
    try put(engine, defaults, "jsx", try s.own(try booleanEnv(engine, "JITI_JSX", no)));
    try put(engine, defaults, "tsconfigPaths", try s.own(try jsonEnv(engine, "JITI_TSCONFIG_PATHS", no, true)));
    if (s.truthy(try s.get(defaults, "jsx"))) try invokeIgnored(engine, try s.get(defaults, "extensions"), "push", &.{ try s.text(".jsx"), try s.text(".tsx") });
    const deprecated = try s.object();
    if (!c.JS_IsUndefined(try s.get(user_options, "cache"))) try s.set(deprecated, "fsCache", try s.get(user_options, "cache"));
    if (!c.JS_IsUndefined(try s.get(user_options, "requireCache"))) try s.set(deprecated, "moduleCache", try s.get(user_options, "requireCache"));
    const result = try s.object();
    try v.js.spreadInto(engine, result, defaults);
    try v.js.spreadInto(engine, result, deprecated);
    try v.js.spreadInto(engine, result, user_options);
    return c.JS_DupValue(engine.context, result);
}

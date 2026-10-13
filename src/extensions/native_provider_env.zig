//! Source provider environment lookup, including its private Bun fallback cache.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn create(engine: *em.Engine) !c.JSValue {
    if (engine.native_provider_env_lookup) |function| return c.JS_DupValue(engine.context, function);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const cache = try scope.object();
    try scope.put(cache, "value", c.pi_js_null());
    const function = try @import("native_node_function.zig").create(engine, "getProviderEnvValue", 2, lookup, &.{cache});
    engine.native_provider_env_lookup = c.JS_DupValue(engine.context, function);
    return function;
}
fn keyed(scope: *Scope, value: c.JSValue, name: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, value, name));
}
fn lookup(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const name = if (args.len > 0) args[0] else c.pi_js_undefined();
    const env = if (args.len > 1) args[1] else c.pi_js_undefined();
    if (!temp.nullish(env)) {
        const scoped = try keyed(&scope, env, name);
        if (scope.truthy(scoped)) return c.JS_DupValue(engine.context, scoped);
    }
    const process = try scope.global("process");
    if (!c.JS_IsUndefined(process)) {
        const value = try keyed(&scope, try scope.get(process, "env"), name);
        if (scope.truthy(value)) return c.JS_DupValue(engine.context, value);
    }
    const value = try fallback(&scope, process, roots[0], name);
    return if (scope.truthy(value)) c.JS_DupValue(engine.context, value) else c.pi_js_undefined();
}
fn fallback(scope: *Scope, process: c.JSValue, cache: c.JSValue, name: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(process)) return c.pi_js_undefined();
    const versions = try scope.get(process, "versions");
    if (temp.nullish(versions) or !scope.truthy(try scope.get(versions, "bun"))) return c.pi_js_undefined();
    const keys = try scope.invoke(try scope.global("Object"), "keys", &.{try scope.get(process, "env")});
    if (try arithmetic.compare(scope.engine, .greater, try scope.get(keys, "length"), c.JS_NewInt32(scope.engine.context, 0))) return c.pi_js_undefined();
    var map = try scope.get(cache, "value");
    if (c.JS_IsNull(map)) {
        map = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
        try scope.set(cache, "value", map);
        const generation = scope.engine.native_allocation_generation;
        populate(scope, map) catch |err| {
            const failure = scope.engine.nativeAllocationError(err, generation);
            if (failure == error.OutOfMemory) return failure;
            if (failure != error.JavaScriptException) return failure;
            if (scope.engine.captured_exception) |exception| scope.engine.freeValue(exception);
            scope.engine.captured_exception = null;
        };
    }
    return scope.invoke(map, "get", &.{name});
}
fn populate(scope: *Scope, map: c.JSValue) !void {
    const fs = try scope.call(try scope.global("require"), c.pi_js_undefined(), &.{try scope.text("node:fs")});
    const data = try scope.call(try scope.get(fs, "readFileSync"), c.pi_js_undefined(), &.{ try scope.text("/proc/self/environ"), try scope.text("utf-8") });
    const entries = try scope.invoke(data, "split", &.{try scope.text("\x00")});
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, entries, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const index = try scope.invoke(entry, "indexOf", &.{try scope.text("=")});
        if (try arithmetic.compare(scope.engine, .greater, index, c.JS_NewInt32(scope.engine.context, 0))) {
            const key = try scope.invoke(entry, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), index });
            const start = try scope.own(try arithmetic.binary(scope.engine, .add, index, c.JS_NewInt32(scope.engine.context, 1)));
            _ = try scope.invoke(map, "set", &.{ key, try scope.invoke(entry, "slice", &.{start}) });
        }
    }
}

//! Actual TypeBox1.3.27 Memory/Settings shared closure over owner-realm values.
//! Pure clone traversal is shared with the native Chord SystemClone body.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
const Operation = enum(c_int) { assign, clone, create, discard, update, reset, set, get, freeze };
const setting_names = .{ "immutableTypes", "maxErrors", "maxInstantiationCount", "useAcceleration", "exactOptionalPropertyTypes", "enumerableKind", "correctiveParse", "unionPrioritySort" };
fn defaultValue(engine: *v.em.Engine, index: usize) c.JSValue {
    return switch (index) {
        1 => c.JS_NewInt32(engine.context, 8),
        2 => c.JS_NewInt32(engine.context, 128),
        3, 7 => c.pi_js_bool(engine.context, 1),
        else => c.pi_js_bool(engine.context, 0),
    };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn method(scope: *Scope, name: [*:0]const u8, length: c_int, operation: Operation, env: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var op: i32 = 0;
            if (c.JS_ToInt32(engine.context, &op, roots[1]) < 0) return v.js.capture(engine);
            return execute(engine, roots[0], @enumFromInt(op), args);
        }
    };
    return scope.own(try @import("native_node_function.zig").create(scope.engine, name, length, Adapter.call, &.{ env, c.JS_NewInt32(scope.engine.context, @intFromEnum(operation)) }));
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const env = try scope.object();
    const settings = try scope.object();
    inline for (setting_names, 0..) |name, index| try scope.put(settings, name, defaultValue(engine, index));
    const metrics = try scope.object();
    inline for (.{ "assign", "create", "clone", "discard", "update" }) |name| try scope.put(metrics, name, c.JS_NewInt32(engine.context, 0));
    try scope.put(env, "settings", settings);
    try scope.put(env, "metrics", metrics);
    const settings_exports = try scope.object();
    inline for (.{ .{ "Reset", 0, Operation.reset }, .{ "Set", 1, Operation.set }, .{ "Get", 0, Operation.get } }) |entry| try scope.put(settings_exports, entry[0], try method(&scope, entry[0], entry[1], entry[2], env));
    const memory_exports = try scope.object();
    inline for (.{ .{ "Assign", 2, Operation.assign }, .{ "Clone", 1, Operation.clone }, .{ "Create", 2, Operation.create }, .{ "Discard", 2, Operation.discard }, .{ "Update", 3, Operation.update } }) |entry| try scope.put(memory_exports, entry[0], try method(&scope, entry[0], entry[1], entry[2], env));
    try scope.put(memory_exports, "Metrics", metrics);
    const graph = try scope.object();
    try scope.put(graph, "Settings", try scope.own(try engine.valueNamespace(settings_exports)));
    try scope.put(graph, "Memory", try scope.own(try engine.valueNamespace(memory_exports)));
    try scope.put(graph, "Freeze", try method(&scope, "Freeze", 1, .freeze, env));
    return c.JS_DupValue(engine.context, graph);
}
fn bump(scope: *Scope, env: c.JSValue, name: [*:0]const u8) !void {
    const metrics = try scope.get(env, "metrics");
    const next = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .add, try scope.get(metrics, name), c.JS_NewInt32(scope.engine.context, 1)));
    try scope.set(metrics, name, next);
}
fn freezeValue(scope: *Scope, env: c.JSValue, value: c.JSValue) !c.JSValue {
    return if (scope.truthy(try scope.get(try scope.get(env, "settings"), "immutableTypes"))) scope.invoke(try scope.global("Object"), "freeze", &.{value}) else value;
}
fn cloned(scope: *Scope, env: c.JSValue, value: c.JSValue) !c.JSValue {
    try bump(scope, env, "clone");
    return scope.own(try @import("native_chord_clone.zig").clone(scope.engine, value));
}
fn keyList(scope: *Scope, value: c.JSValue, enumerable: bool) !c.JSValue {
    return scope.invoke(try scope.global("Object"), if (enumerable) "keys" else "getOwnPropertyNames", &.{value});
}
fn defineFrom(scope: *Scope, target: c.JSValue, key: c.JSValue, fields: c.JSValue, settings: c.JSValue, visible: bool) !void {
    const object = try scope.global("Object");
    const define_fn = try scope.get(object, "defineProperty");
    const descriptor = try scope.object();
    try scope.put(descriptor, "configurable", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(descriptor, "writable", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(descriptor, "enumerable", if (c.JS_IsUndefined(settings)) c.pi_js_bool(scope.engine.context, @intFromBool(visible)) else try scope.get(settings, "enumerableKind"));
    try scope.put(descriptor, "value", try scope.own(try v.js.getKey(scope.engine, fields, key)));
    _ = try scope.call(define_fn, object, &.{ target, key, descriptor });
}
fn execute(engine: *v.em.Engine, env: c.JSValue, operation: Operation, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = arg(args, 0);
    const second = arg(args, 1);
    var result = c.pi_js_undefined();
    switch (operation) {
        .get => result = try scope.get(env, "settings"),
        .reset => {
            const settings = try scope.get(env, "settings");
            inline for (setting_names, 0..) |name, index| try scope.set(settings, name, defaultValue(engine, index));
        },
        .set => {
            const settings = try scope.get(env, "settings");
            var iterator = try v.iterator(&scope, try keyList(&scope, first, false));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |key| {
                defer engine.freeValue(key);
                const value = try scope.own(try v.js.getKey(engine, first, key));
                if (c.JS_IsUndefined(value)) continue;
                const descriptor = try scope.object();
                try scope.put(descriptor, "value", value);
                _ = try scope.invoke(try scope.global("Object"), "defineProperty", &.{ settings, key, descriptor });
            }
        },
        .freeze => result = try freezeValue(&scope, env, first),
        .clone => result = try cloned(&scope, env, first),
        .assign => {
            try bump(&scope, env, "assign");
            const object = try scope.own(try v.js.spread(engine, first));
            try v.js.spreadInto(engine, object, second);
            result = try freezeValue(&scope, env, object);
        },
        .create => {
            try bump(&scope, env, "create");
            const options = if (c.JS_IsUndefined(arg(args, 2))) try scope.object() else args[2];
            const object = try scope.own(try v.js.spread(engine, second));
            try v.js.spreadInto(engine, object, options);
            const enumerable = scope.truthy(try scope.get(try scope.get(env, "settings"), "enumerableKind"));
            if (enumerable) try v.js.spreadInto(engine, object, first) else {
                var iterator = try v.iterator(&scope, try keyList(&scope, first, true));
                defer iterator.deinit();
                errdefer iterator.closePreserving();
                while (try iterator.next()) |key| {
                    defer engine.freeValue(key);
                    try defineFrom(&scope, object, key, first, c.pi_js_undefined(), false);
                }
            }
            result = try freezeValue(&scope, env, object);
        },
        .update => {
            try bump(&scope, env, "update");
            const settings = try scope.get(env, "settings");
            const object = try cloned(&scope, env, first);
            inline for (.{ false, true }) |visible| {
                const fields = if (visible) arg(args, 2) else second;
                var iterator = try v.iterator(&scope, try keyList(&scope, fields, true));
                defer iterator.deinit();
                errdefer iterator.closePreserving();
                while (try iterator.next()) |key| {
                    defer engine.freeValue(key);
                    // Source reads settings.enumerableKind per hidden field.
                    try defineFrom(&scope, object, key, fields, if (visible) c.pi_js_undefined() else settings, true);
                }
            }
            result = try freezeValue(&scope, env, object);
        },
        .discard => {
            try bump(&scope, env, "discard");
            const object = try scope.object();
            var iterator = try v.iterator(&scope, try keyList(&scope, first, false));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |key| {
                defer engine.freeValue(key);
                if (scope.truthy(try scope.invoke(second, "includes", &.{key}))) continue;
                const descriptor = try scope.invoke(try scope.global("Object"), "getOwnPropertyDescriptor", &.{ first, key });
                try scope.set(descriptor, "value", try cloned(&scope, env, try scope.get(descriptor, "value")));
                _ = try scope.invoke(try scope.global("Object"), "defineProperty", &.{ object, key, descriptor });
            }
            result = try freezeValue(&scope, env, object);
        },
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn invoke(scope: *Scope, graph: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.invoke(try scope.get(graph, "Memory"), name, args);
}

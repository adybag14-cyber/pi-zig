//! Source Stats/BigIntStats graph over the exact native libuv metadata snapshot.
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const uv = @import("native_uv_api").c;
const c = js.c;
const keys = [_][*:0]const u8{ "dev", "mode", "nlink", "uid", "gid", "rdev", "blksize", "ino", "size", "blocks", "atimeMs", "mtimeMs", "ctimeMs", "birthtimeMs" };
const date_keys = [_][*:0]const u8{ "atime", "mtime", "ctime", "birthtime" };
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue, constructing: bool) !c.JSValue {
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = if (constructing) try scope.own(try @import("native_class.zig").object(engine, target)) else target;
    const big = scope.truthy(constants[0]);
    for (keys, 0..) |key, index| {
        var field = h.arg(args, index);
        if (big and index >= 10) field = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 3, field, c.JS_NewBigInt64(engine.context, 1_000_000))));
        try scope.set(value, key, field);
    }
    if (big) inline for (.{ "atimeNs", "mtimeNs", "ctimeNs", "birthtimeNs" }, 10..) |key, index| try scope.set(value, key, h.arg(args, index));
    return if (constructing) c.JS_DupValue(engine.context, value) else c.pi_js_undefined();
}
fn baseConstruct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, constructing: bool) !c.JSValue {
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = if (constructing) try scope.own(try @import("native_class.zig").object(engine, target)) else target;
    for (keys[0..10], 0..) |key, index| try scope.set(value, key, h.arg(args, index));
    return if (constructing) c.JS_DupValue(engine.context, value) else c.pi_js_undefined();
}
fn checkMode(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, big: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const property = h.arg(if (argc > 0) argv[0..@intCast(argc)] else &.{}, 0);
    if (builtin.os.tag == .windows) inline for (.{ 0o010000, 0o060000, 0o140000 }) |unsupported| {
        if (c.JS_IsStrictEqual(context, property, c.JS_NewInt32(context, unsupported))) return c.pi_js_bool(context, 0);
    };
    const mode = scope.get(receiver, "mode") catch |err| return @import("native_durable.zig").reject(engine, err);
    if (big != 0) {
        var raw: i64 = undefined;
        if (c.JS_ToBigInt64(context, &raw, mode) < 0) return c.JS_Throw(context, c.JS_GetException(context));
        const expected = scope.call(scope.global("BigInt") catch |err| return @import("native_durable.zig").reject(engine, err), c.pi_js_undefined(), &.{property}) catch |err| return @import("native_durable.zig").reject(engine, err);
        const masked = scope.own(engine.checked(c.JS_NewBigInt64(context, raw & 0o170000)) catch |err| return @import("native_durable.zig").reject(engine, err)) catch |err| return @import("native_durable.zig").reject(engine, err);
        return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, masked, expected)));
    }
    var raw: i32 = undefined;
    if (c.JS_ToInt32(context, &raw, mode) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, c.JS_NewInt32(context, raw & 0o170000), property)));
}
fn isKind(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const function = c.JS_GetPropertyStr(context, receiver, "_checkModeProperty");
    if (c.JS_IsException(function)) return function;
    defer engine.freeValue(function);
    return c.JS_Call(context, function, receiver, 1, data);
}
fn lazyDate(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const index: usize = @intCast(@divTrunc(raw, 2));
    const value = (if (@mod(raw, 2) == 1) c.JS_DupValue(context, h.arg(if (argc > 0) argv[0..@intCast(argc)] else &.{}, 0)) else date: {
        const ms = scope.get(receiver, keys[10 + index]) catch |err| return @import("native_durable.zig").reject(engine, err);
        const num = scope.call(scope.global("Number") catch |err| return @import("native_durable.zig").reject(engine, err), c.pi_js_undefined(), &.{ms}) catch |err| return @import("native_durable.zig").reject(engine, err);
        const rounded = scope.invoke(scope.global("Math") catch |err| return @import("native_durable.zig").reject(engine, err), "round", &.{num}) catch |err| return @import("native_durable.zig").reject(engine, err);
        break :date js.builtin(engine, "Date", &.{rounded}) catch |err| return @import("native_durable.zig").reject(engine, err);
    });
    defer engine.freeValue(value);
    if (c.JS_DefinePropertyValueStr(context, receiver, date_keys[index], c.JS_DupValue(context, value), c.JS_PROP_WRITABLE) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.JS_DupValue(context, value);
}
fn constructors(scope: *h.Scope, bindings: c.JSValue) !void {
    if (!c.JS_IsUndefined(try scope.get(bindings, "Stats"))) return;
    const engine = scope.engine;
    const base_prototype = try scope.object();
    const base = try scope.own(try @import("native_function_constructor.zig").constructor(engine, "StatsBase", 10, base_prototype, baseConstruct, &.{}));
    inline for (.{ .{ "isDirectory", 0o040000 }, .{ "isFile", 0o100000 }, .{ "isBlockDevice", 0o060000 }, .{ "isCharacterDevice", 0o020000 }, .{ "isSymbolicLink", 0o120000 }, .{ "isFIFO", 0o010000 }, .{ "isSocket", 0o140000 } }) |entry| {
        var data = [_]c.JSValue{c.JS_NewInt32(engine.context, entry[1])};
        try scope.put(base_prototype, entry[0], try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, isKind, "", 0, 0, 1, &data))));
    }
    inline for (.{ "Stats", "BigIntStats" }, 0..) |name, big| {
        const prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype)));
        const constructor = try scope.own(try @import("native_function_constructor.zig").constructor(engine, name, 14, prototype, construct, &.{c.pi_js_bool(engine.context, @intCast(big))}));
        if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
        inline for (date_keys, 0..) |key, index| {
            const atom = c.JS_NewAtom(engine.context, key);
            defer c.JS_FreeAtom(engine.context, atom);
            const getter = try engine.checked(c.JS_NewCFunctionMagic(engine.context, lazyDate, "get", 0, c.JS_CFUNC_generic_magic, @intCast(index * 2)));
            const setter = engine.checked(c.JS_NewCFunctionMagic(engine.context, lazyDate, "set", 1, c.JS_CFUNC_generic_magic, @intCast(index * 2 + 1))) catch |err| {
                engine.freeValue(getter);
                return err;
            };
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, setter, c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
        }
        try scope.put(prototype, "_checkModeProperty", try scope.own(try engine.checked(c.JS_NewCFunctionMagic(engine.context, checkMode, "", 1, c.JS_CFUNC_generic_magic, @intCast(big)))));
        try scope.put(bindings, name, constructor);
    }
}
fn timeValue(scope: *h.Scope, value: uv.uv_timespec_t, big: bool) !c.JSValue {
    const engine = scope.engine;
    if (big) {
        const sec = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 2, c.JS_NewBigInt64(engine.context, value.tv_sec), c.JS_NewBigInt64(engine.context, 1_000_000_000))));
        return scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, sec, c.JS_NewBigInt64(engine.context, value.tv_nsec))));
    }
    return c.JS_NewFloat64(engine.context, @as(f64, @floatFromInt(value.tv_sec)) * 1000 + @as(f64, @floatFromInt(value.tv_nsec)) / 1_000_000);
}
pub fn create(scope: *h.Scope, bindings: c.JSValue, info: uv.uv_stat_t, big: bool) !c.JSValue {
    try constructors(scope, bindings);
    const raw = [_]u64{ info.st_dev, info.st_mode, info.st_nlink, info.st_uid, info.st_gid, info.st_rdev, info.st_blksize, info.st_ino, info.st_size, info.st_blocks };
    var args: [14]c.JSValue = undefined;
    for (raw, 0..) |value, index| args[index] = if (big) try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, value))) else c.JS_NewFloat64(scope.engine.context, @floatFromInt(value));
    inline for (.{ info.st_atim, info.st_mtim, info.st_ctim, info.st_birthtim }, 10..) |value, index| args[index] = try timeValue(scope, value, big);
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, if (big) "BigIntStats" else "Stats"), args.len, &args)));
}

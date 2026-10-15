//! Shared native values for the public Durable Env and pi-env guest modules.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const class = @import("native_class.zig");
pub const Engine = js.Engine;
pub const c = js.c;
const Method = enum(c_int) { ok, err, getOrThrow, getOrUndefined, toError, nodePlatform, isConnectionLost };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn result(scope: *Scope, successful: bool, value: c.JSValue) !c.JSValue {
    const object = try scope.object();
    try scope.put(object, "ok", c.pi_js_bool(scope.engine.context, @intFromBool(successful)));
    try scope.put(object, if (successful) "value" else "error", value);
    return object;
}
fn errorConstruct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const file = scope.truthy(values[1]);
    const cause = arg(args, if (file) 3 else 2);
    const options = if (c.JS_IsUndefined(cause)) c.pi_js_undefined() else try scope.object();
    if (!c.JS_IsUndefined(cause)) try scope.put(options, "cause", cause);
    const super_args = [_]c.JSValue{ arg(args, 1), options };
    const object = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, values[0], target, super_args.len, @constCast(&super_args))));
    // Source class fields are defined before constructor assignments; their insertion order and setters matter.
    try scope.put(object, "code", c.pi_js_undefined());
    try scope.put(object, if (file) "path" else "spillPath", c.pi_js_undefined());
    try scope.set(object, "name", try scope.text(if (file) "FileError" else "ExecutionError"));
    try scope.set(object, "code", arg(args, 0));
    if (file) try scope.set(object, "path", arg(args, 2));
    return c.JS_DupValue(engine.context, object);
}
fn errorClass(scope: *Scope, name: [:0]const u8, file: bool) !c.JSValue {
    const base = try scope.global("Error");
    const prototype = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, try scope.get(base, "prototype"))));
    const constructor = try scope.own(try class.constructor(scope.engine, name, if (file) 4 else 3, prototype, errorConstruct, &.{ base, c.pi_js_bool(scope.engine.context, @intFromBool(file)) }));
    if (c.JS_SetPrototype(scope.engine.context, constructor, base) < 0) return js.capture(scope.engine);
    return constructor;
}
fn remoteConstruct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fields = arg(args, 0);
    const given = try scope.get(fields, "message");
    const message = if (c.JS_IsString(given)) try scope.get(fields, "message") else try scope.text("Remote operation failed");
    const super_args = [_]c.JSValue{message};
    const object = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, values[0], target, super_args.len, @constCast(&super_args))));
    inline for (.{ "code", "path", "fields" }) |key| try scope.put(object, key, c.pi_js_undefined());
    try scope.set(object, "name", try scope.text("RemoteError"));
    const code = try scope.get(fields, "code");
    try scope.set(object, "code", if (c.JS_IsString(code)) try scope.get(fields, "code") else try scope.text("unknown"));
    const path = try scope.get(fields, "path");
    if (c.JS_IsString(path)) try scope.set(object, "path", try scope.get(fields, "path"));
    try scope.set(object, "fields", fields);
    return c.JS_DupValue(engine.context, object);
}
fn remoteClass(scope: *Scope) !c.JSValue {
    const base = try scope.global("Error");
    const prototype = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, try scope.get(base, "prototype"))));
    const constructor = try scope.own(try class.constructor(scope.engine, "RemoteError", 1, prototype, remoteConstruct, &.{base}));
    if (c.JS_SetPrototype(scope.engine.context, constructor, base) < 0) return js.capture(scope.engine);
    return constructor;
}
fn clearCaught(engine: *Engine) void {
    if (engine.captured_exception) |exception| engine.freeValue(exception);
    engine.captured_exception = null;
}
fn toError(scope: *Scope, input: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const base = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(engine.context, input, base);
    if (instance < 0) return js.capture(engine);
    if (instance != 0) return input;
    if (c.JS_IsString(input)) return scope.own(try js.builtin(engine, "Error", &.{input}));
    const json = try scope.global("JSON");
    const encoded = scope.invoke(json, "stringify", &.{input}) catch |err| {
        if (err != error.JavaScriptException) return err;
        clearCaught(engine);
        const string = try scope.global("String");
        const text = try scope.call(string, c.pi_js_undefined(), &.{input});
        return scope.own(try js.builtin(engine, "Error", &.{text}));
    };
    return scope.own(try js.builtin(engine, "Error", &.{encoded}));
}
fn dispatch(engine: *Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var raw: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &raw, values[0]) < 0) return js.capture(engine);
    const method: Method = @enumFromInt(raw);
    const input = arg(args, 0);
    const value = switch (method) {
        .ok => try result(&scope, true, input),
        .err => try result(&scope, false, input),
        .getOrThrow => outcome: {
            if (!scope.truthy(try scope.get(input, "ok"))) {
                _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, try scope.get(input, "error")));
                return js.capture(engine);
            }
            break :outcome try scope.get(input, "value");
        },
        .getOrUndefined => if (scope.truthy(try scope.get(input, "ok"))) try scope.get(input, "value") else c.pi_js_undefined(),
        .toError => try toError(&scope, input),
        .isConnectionLost => lost: {
            const instance = c.JS_IsInstanceOf(engine.context, input, values[1]);
            if (instance < 0) return js.capture(engine);
            if (instance == 0) break :lost c.pi_js_bool(engine.context, 0);
            break :lost c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, try scope.get(try scope.get(input, "fields"), "lost"), c.pi_js_bool(engine.context, 1))));
        },
        .nodePlatform => platform: {
            const platforms = try scope.object();
            try scope.put(platforms, "windows", try scope.text("win32"));
            try scope.put(platforms, "macos", try scope.text("darwin"));
            const archs = try scope.object();
            try scope.put(archs, "x86_64", try scope.text("x64"));
            try scope.put(archs, "aarch64", try scope.text("arm64"));
            try scope.put(archs, "x86", try scope.text("ia32"));
            const os_key = try scope.get(input, "os");
            const mapped_os = try scope.own(try js.getKey(engine, platforms, os_key));
            const os = if (c.JS_IsUndefined(mapped_os) or c.JS_IsNull(mapped_os)) try scope.get(input, "os") else mapped_os;
            const arch_key = try scope.get(input, "arch");
            const mapped_arch = try scope.own(try js.getKey(engine, archs, arch_key));
            const arch = if (c.JS_IsUndefined(mapped_arch) or c.JS_IsNull(mapped_arch)) try scope.get(input, "arch") else mapped_arch;
            const object = try scope.object();
            try scope.put(object, "platform", os);
            try scope.put(object, "arch", arch);
            break :platform object;
        },
    };
    return c.JS_DupValue(engine.context, value);
}
pub fn exports(engine: *Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.object();
    try scope.put(object, "FileError", try errorClass(&scope, "FileError", true));
    try scope.put(object, "ExecutionError", try errorClass(&scope, "ExecutionError", false));
    const remote = try remoteClass(&scope);
    try scope.put(object, "RemoteError", remote);
    inline for (std.meta.fields(Method)) |field| try scope.put(object, field.name, try scope.own(try ordinary.create(engine, field.name, 1, dispatch, &.{ c.JS_NewInt32(engine.context, @intCast(field.value)), remote })));
    return c.JS_DupValue(engine.context, object);
}

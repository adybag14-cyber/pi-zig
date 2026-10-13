//! Original ReadOnlyAuthStorage snapshot/validation semantics on owned IO.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const storage = @import("native_auth_storage.zig");
const c = em.c;
const Method = enum(c_int) { load, read, list, modify, delete };
fn object(value: c.JSValue) bool {
    return c.JS_IsObject(value) and !c.JS_IsNull(value) and !c.JS_IsArray(value);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn failure(scope: *Scope, message: []const u8) anyerror {
    const value = scope.own(js.builtin(scope.engine, "Error", &.{scope.text(message) catch |err| return err}) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |err| return err;
    unreachable;
}
fn authPath(scope: *Scope, input: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(input)) {
        if (!c.JS_IsString(input)) return js.typeError(scope.engine, "Auth path must be a string");
        // Source normalizes shell paths and expands tilde; file: URLs remain
        // literal input for this API, unlike the SDK session-path adapter.
        const text = try scope.engine.toString(input);
        defer scope.engine.gpa.free(text);
        if (std.mem.startsWith(u8, text, "file://")) return input;
        return scope.own(try @import("native_sdk_settings.zig").normalizePath(scope.engine, input));
    }
    const directory = try sdk.agentDir(scope.engine);
    defer scope.engine.gpa.free(directory);
    const path = try std.fs.path.join(scope.engine.gpa, &.{ directory, "auth.json" });
    defer scope.engine.gpa.free(path);
    return scope.text(path);
}
fn check(scope: *Scope, options: c.JSValue) !void {
    if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) return;
    const signal = try scope.get(options, "signal");
    if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
}
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const constructor = try scope.own(try engine.checked(c.JS_NewCFunction2(engine.context, construct, "ReadOnlyAuthStorage", 0, c.JS_CFUNC_constructor, 0)));
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, field.name, switch (@as(Method, @enumFromInt(field.value))) {
            .load => 0,
            .list => 1,
            .read, .delete => 2,
            .modify => 3,
        }, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try scope.put(exports, "ReadOnlyAuthStorage", constructor);
    try scope.put(exports, "readStoredCredential", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, readStoredCallback, "readStoredCredential", 1))));
}
fn construct(context: ?*c.JSContext, new_target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine, new_target, argument(argv[0..@intCast(argc)], 0)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn create(engine: *em.Engine, new_target: c.JSValue, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(new_target, "prototype");
    const result = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, prototype)));
    try scope.put(result, "authPath", try authPath(&scope, input));
    try scope.put(result, "data", c.pi_js_undefined());
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(raw);
    return invoke(engine, receiver, method, argv[0..@intCast(argc)]) catch |err| if (method == .load) @import("native_durable.zig").reject(engine, err) else @import("native_durable.zig").rejectedPromise(engine, err);
}
fn invalidCredential(scope: *Scope, id: c.JSValue) anyerror {
    const name = scope.engine.toString(id) catch |err| return err;
    defer scope.engine.gpa.free(name);
    const message = std.fmt.allocPrint(scope.engine.gpa, "Invalid auth.json credential for provider \"{s}\"", .{name}) catch |err| return err;
    defer scope.engine.gpa.free(message);
    return failure(scope, message);
}
fn validate(scope: *Scope, data: c.JSValue) !void {
    if (!object(data)) return failure(scope, "Invalid auth.json: expected an object");
    const entries = try scope.invoke(try scope.global("Object"), "entries", &.{data});
    for (0..try sdk.length(scope.engine, entries)) |i| {
        const pair = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, entries, @intCast(i))));
        const id = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, pair, 0)));
        const credential = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, pair, 1)));
        if (!object(credential)) return invalidCredential(scope, id);
        const kind = try scope.get(credential, "type");
        if (scope.equal(kind, try scope.text("api_key"))) {
            const key = try scope.get(credential, "key");
            if (!c.JS_IsUndefined(key) and !c.JS_IsString(key)) return invalidCredential(scope, id);
            const env = try scope.get(credential, "env");
            if (c.JS_IsUndefined(env)) continue;
            if (!object(env)) return invalidCredential(scope, id);
            const values = try scope.invoke(try scope.global("Object"), "values", &.{env});
            for (0..try sdk.length(scope.engine, values)) |j| {
                const value = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, values, @intCast(j))));
                if (!c.JS_IsString(value)) return invalidCredential(scope, id);
            }
            continue;
        }
        if (scope.equal(kind, try scope.text("oauth")) and c.JS_IsString(try scope.get(credential, "access")) and c.JS_IsString(try scope.get(credential, "refresh"))) {
            const expires = try scope.get(credential, "expires");
            var number: f64 = 0;
            if (c.JS_IsNumber(expires) and c.JS_ToFloat64(scope.engine.context, &number, expires) == 0 and std.math.isFinite(number)) continue;
        }
        return invalidCredential(scope, id);
    }
}
fn parsedFile(scope: *Scope, bytes: []const u8) !c.JSValue {
    const text = if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) bytes[3..] else bytes;
    return scope.invoke(try scope.global("JSON"), "parse", &.{try scope.text(text)});
}
fn load(scope: *Scope, receiver: c.JSValue) !c.JSValue {
    const cached = try scope.get(receiver, "data");
    if (scope.truthy(cached)) return cached;
    const path = try scope.engine.toString(try scope.get(receiver, "authPath"));
    defer scope.engine.gpa.free(path);
    const bytes = @import("native_auth_file_io.zig").read(scope.engine, path) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (err == error.FileNotFound) {
            const empty = try scope.object();
            try scope.set(receiver, "data", empty);
            return empty;
        }
        const message = try std.fmt.allocPrint(scope.engine.gpa, "Failed to read auth.json: {s}", .{@errorName(err)});
        defer scope.engine.gpa.free(message);
        return failure(scope, message);
    };
    defer scope.engine.gpa.free(bytes);
    const generation = scope.engine.native_allocation_generation;
    const parsed = parsedFile(scope, bytes) catch |err| {
        if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        if (err != error.JavaScriptException) return err;
        const exception = scope.engine.captured_exception orelse return err;
        const detail = try scope.engine.toString(try scope.get(exception, "message"));
        defer scope.engine.gpa.free(detail);
        const message = try std.fmt.allocPrint(scope.engine.gpa, "Failed to read auth.json: {s}", .{detail});
        defer scope.engine.gpa.free(message);
        return failure(scope, message);
    };
    try validate(scope, parsed);
    try scope.set(receiver, "data", parsed);
    return parsed;
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .modify or method == .delete) return failure(&scope, "Read-only credential storage cannot modify auth.json");
    if (method == .load) return c.JS_DupValue(engine.context, try load(&scope, receiver));
    const options = argument(args, if (method == .list) 0 else 1);
    try check(&scope, options);
    const data = try scope.invoke(receiver, "load", &.{});
    if (method == .list) {
        const entries = try scope.invoke(try scope.global("Object"), "entries", &.{data});
        const list = try scope.array();
        for (0..try sdk.length(engine, entries)) |i| {
            const pair = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(i))));
            const id = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 0)));
            const credential = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 1)));
            const item = try scope.object();
            try scope.put(item, "providerId", id);
            try scope.put(item, "type", try scope.get(credential, "type"));
            try scope.index(list, @intCast(i), item);
        }
        try check(&scope, options);
        return sdk.promise(engine, list);
    }
    const credential = try scope.own(try js.getKey(engine, data, argument(args, 0)));
    try check(&scope, options);
    if (!scope.truthy(credential)) return sdk.promise(engine, c.pi_js_undefined());
    const kind = try scope.get(credential, "type");
    const key = try scope.get(credential, "key");
    if (!scope.equal(kind, try scope.text("api_key")) or !scope.truthy(key)) return sdk.promise(engine, try scope.own(try @import("native_structured_clone.zig").clone(engine, credential)));
    const text = try engine.toString(key);
    defer engine.gpa.free(text);
    const value = if (@import("../coding_agent/config_value.zig").isCommandConfigValue(text)) try scope.own(try @import("native_structured_clone.zig").clone(engine, credential)) else try storage.resolvedCredential(&scope, credential);
    return sdk.promise(engine, value);
}
fn readStoredCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const generation = engine.native_allocation_generation;
    return readStored(engine, argv[0..@intCast(argc)]) catch |err| if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) @import("native_durable.zig").reject(engine, error.OutOfMemory) else c.pi_js_undefined();
}
fn readStored(engine: *em.Engine, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = try engine.toString(try authPath(&scope, argument(args, 1)));
    defer engine.gpa.free(path);
    const bytes = try @import("native_auth_file_io.zig").read(engine, path);
    defer engine.gpa.free(bytes);
    const data = try parsedFile(&scope, bytes);
    return js.getKey(engine, data, argument(args, 0));
}

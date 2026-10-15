//! Private assembly over the actual native descriptor, Source fsCall lifecycle
//! and byte-stream controller. Public full FileHandle export stays uninstalled.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const lifecycle = @import("native_env_node_file_lifecycle.zig");
const frontend = @import("native_env_node_file_frontend.zig");
const contents = @import("native_env_node_fs_contents.zig");
const c = js.c;
const Scope = h.Scope;
const Method = enum(c_int) { getAsyncId, fd, ref, unref, transfer, transferList, deserialize, asyncDispose, read, write, readv, writev, stat, truncate, chmod, chown, utimes, sync, datasync, readFile, writeFile, appendFile, readableWebStream };
fn operation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const result = operationValue(&scope, roots[0], args, @enumFromInt(raw)) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    return c.JS_DupValue(context, result);
}
fn operationValue(scope: *Scope, bindings: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    const descriptor = try lifecycle.get(scope, bindings, h.arg(args, 0), .handle);
    const supplied = if (args.len > 0) args[1..] else &.{};
    if (method == .readFile) {
        const options = if (c.JS_IsString(h.arg(supplied, 0))) normalized: {
            const object = try scope.object();
            try scope.put(object, "encoding", h.arg(supplied, 0));
            break :normalized object;
        } else h.arg(supplied, 0);
        return scope.own(try contents.readRetained(scope.engine, bindings, descriptor, options));
    }
    if (method == .writeFile or method == .appendFile) {
        const options = h.arg(supplied, 1);
        const content = h.arg(supplied, 0);
        const encoding = if (c.JS_IsString(options)) options else try h.optional(scope, options, "encoding");
        const bytes = if (c.JS_IsString(content)) try scope.invoke(try scope.get(bindings, "fileHandleBuffer"), "from", &.{ content, encoding }) else content;
        return scope.own(try contents.writeRetained(scope.engine, bindings, descriptor, bytes, try h.optional(scope, if (c.JS_IsString(options)) c.pi_js_undefined() else options, "signal")));
    }
    return scope.invoke(descriptor, @tagName(method), supplied);
}
fn invoke(scope: *Scope, receiver: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    switch (method) {
        .getAsyncId => return lifecycle.getAsyncId(scope, bindings, receiver),
        .fd => return lifecycle.get(scope, bindings, receiver, .fd),
        .ref => {
            try lifecycle.ref(scope, bindings, receiver);
            return c.pi_js_undefined();
        },
        .unref => {
            try lifecycle.unref(scope, bindings, receiver);
            return c.pi_js_undefined();
        },
        .transfer => return lifecycle.transfer(scope, bindings, receiver),
        .transferList => return lifecycle.transferList(scope, bindings, receiver),
        .deserialize => {
            try lifecycle.deserialize(scope, bindings, receiver, args);
            return c.pi_js_undefined();
        },
        .asyncDispose => return lifecycle.asyncDispose(scope, bindings, receiver),
        .readableWebStream => return scope.own(try @import("native_env_node_file_webstream.zig").create(scope, bindings, receiver, h.arg(args, 0))),
        else => {
            const operations = try scope.get(bindings, "fileHandleOperations");
            return lifecycle.call(scope, bindings, receiver, try scope.get(operations, @tagName(method)), args, @tagName(method));
        },
    }
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const method: Method = @enumFromInt(raw);
    const result = invoke(&scope, receiver, roots[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, method) catch |err| {
        if (raw >= @intFromEnum(Method.read) and raw <= @intFromEnum(Method.appendFile)) return @import("native_durable.zig").rejectedPromise(engine, err);
        return @import("native_durable.zig").reject(engine, err);
    };
    return c.JS_DupValue(context, result);
}
fn define(scope: *Scope, prototype: c.JSValue, bindings: c.JSValue, key: c.JSValue, method: Method, name: [*:0]const u8, length: c_int, getter: bool) !void {
    var roots = [_]c.JSValue{bindings};
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(method), roots.len, &roots)));
    const atom = c.JS_ValueToAtom(scope.engine.context, key);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (getter) {
        if (c.JS_DefinePropertyGetSet(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
    } else if (c.JS_DefinePropertyValue(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(scope.engine);
}
pub fn prepare(scope: *Scope, bindings: c.JSValue) !void {
    if (scope.truthy(try scope.get(bindings, "fileHandleAssemblyReady"))) return;
    try lifecycle.prepare(scope, bindings);
    try @import("native_readable_byte_stream.zig").prepare(scope, bindings);
    try @import("node_buffer.zig").install(scope.engine);
    try scope.put(bindings, "fileHandleBuffer", try scope.global("Buffer"));
    const event_exports = scope.engine.native_module_values.get("node:events") orelse return error.NativeEventEmitterUnavailable;
    const emitter = try scope.get(event_exports, "EventEmitter");
    const parent_prototype = try scope.get(emitter, "prototype");
    const prototype = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, parent_prototype)));
    const constructor = try scope.own(try @import("native_class.zig").constructor(scope.engine, "FileHandle", 1, prototype, lifecycle.construct, &.{bindings}));
    if (c.JS_SetPrototype(scope.engine.context, constructor, emitter) < 0) return js.capture(scope.engine);
    try scope.put(bindings, "FileHandle", constructor);
    const operations = try scope.object();
    var roots = [_]c.JSValue{bindings};
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        if (field.value >= @intFromEnum(Method.read) and field.value <= @intFromEnum(Method.appendFile)) {
            try scope.put(operations, field.name, try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, operation, field.name, 1, @intCast(field.value), roots.len, &roots))));
        }
        if (field.value >= @intFromEnum(Method.read) or method == .getAsyncId or method == .fd) {
            try define(scope, prototype, bindings, try scope.text(field.name), method, field.name, switch (method) {
                .read, .write => 4,
                .readv, .writev, .chown, .utimes, .writeFile, .appendFile => 2,
                .getAsyncId, .fd, .sync, .datasync, .truncate, .readableWebStream => 0,
                else => 1,
            }, method == .fd);
        }
    }
    inline for (.{ .{ lifecycle.Key.ref_method, Method.ref, "[kRef]" }, .{ lifecycle.Key.unref_method, Method.unref, "[kUnref]" }, .{ lifecycle.Key.transfer_method, Method.transfer, "[messaging_transfer_symbol]" }, .{ lifecycle.Key.transfer_list_method, Method.transferList, "[messaging_transfer_list_symbol]" }, .{ lifecycle.Key.deserialize_method, Method.deserialize, "[messaging_deserialize_symbol]" }, .{ lifecycle.Key.async_dispose, Method.asyncDispose, "[Symbol.asyncDispose]" } }) |entry| try define(scope, prototype, bindings, try lifecycle.symbol(scope, bindings, entry[0]), entry[1], entry[2], if (entry[1] == .deserialize) 1 else 0, false);
    try scope.put(bindings, "fileHandleOperations", operations);
    try scope.put(bindings, "fileHandleAssemblyReady", c.pi_js_bool(scope.engine.context, 1));
}
fn asyncId(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return js.get(engine, roots[0], "asyncId") catch |err| @import("native_durable.zig").reject(engine, err);
}
/// The descriptor remains the real C/libuv owner. The public-looking wrapper
/// owns only Source symbols and refs; streams use that same descriptor path.
pub fn create(scope: *Scope, descriptor: c.JSValue, bindings: c.JSValue) !c.JSValue {
    try prepare(scope, bindings);
    try frontend.installPrivate(scope, descriptor);
    const event_exports = scope.engine.native_module_values.get("node:events").?;
    const resource_constructor = try scope.get(event_exports, "EventEmitterAsyncResource");
    const options = try scope.object();
    try scope.put(options, "name", try scope.text("FILEHANDLE"));
    var resource_args = [_]c.JSValue{options};
    const resource = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, resource_constructor, resource_args.len, &resource_args)));
    var roots = [_]c.JSValue{resource};
    try scope.put(descriptor, "getAsyncId", try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, asyncId, "getAsyncId", 0, 0, roots.len, &roots))));
    var args = [_]c.JSValue{descriptor};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "FileHandle"), args.len, &args)));
}

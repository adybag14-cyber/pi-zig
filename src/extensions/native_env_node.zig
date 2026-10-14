//! Original NodeExecutionEnv public fields and LocalExecutionEnv's private borrowed connection.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const paths = @import("native_env_node_path.zig");
const Scope = h.Scope;
const c = js.c;
pub const Method = @import("native_env_node_methods.zig").Method;
fn constructNode(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.put(receiver, "id", try scope.text("node:local"));
    inline for (.{ "cwd", "shellPath", "shellEnv", "watchOptions" }) |key| try scope.put(receiver, key, c.pi_js_undefined());
    try scope.put(receiver, "activeChildPids", try scope.own(try js.builtin(engine, "Set", &.{})));
    inline for (.{ "cwd", "shellPath", "shellEnv" }) |key| try scope.set(receiver, key, try scope.get(h.arg(args, 0), key));
    const watch = try scope.get(h.arg(args, 0), "watch");
    try scope.set(receiver, "watchOptions", if (h.nullish(watch)) try scope.object() else watch);
    return c.JS_DupValue(engine.context, receiver);
}
fn restNodeOptions(scope: *Scope, options: c.JSValue) !c.JSValue {
    const object = try scope.object();
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(scope.engine.context, &names, &count, options, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(scope.engine);
    defer c.JS_FreePropertyEnum(scope.engine.context, names, count);
    const excluded = c.JS_NewAtom(scope.engine.context, "connection");
    defer c.JS_FreeAtom(scope.engine.context, excluded);
    for (0..count) |index| {
        if (names[index].atom == excluded) continue;
        const value = try scope.engine.checked(c.JS_GetProperty(scope.engine.context, options, names[index].atom));
        if (c.JS_DefinePropertyValue(scope.engine.context, object, names[index].atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
    }
    return object;
}
fn constructLocal(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = h.arg(args, 0);
    const connection = try scope.get(options, "connection");
    const node = try restNodeOptions(&scope, options);
    const constructor = try scope.get(constants[0], "local");
    const base = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, constructor)));
    const receiver = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, base, target, 1, @constCast(&node))));
    _ = try scope.call(try scope.get(constants[0], "weakSet"), try scope.get(constants[0], "connections"), &.{ receiver, connection });
    return c.JS_DupValue(engine.context, receiver);
}
const Stage = enum(c_int) { listing, exists, joined };
fn advance(engine: *js.Engine, saved: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return h.throw(&scope, value);
    const stage: Stage = @enumFromInt(raw);
    if (stage == .exists) {
        if (scope.truthy(try scope.get(value, "ok"))) return c.JS_DupValue(engine.context, try h.values.result(&scope, true, c.pi_js_bool(engine.context, 1)));
        const failure = try scope.get(value, "error");
        return c.JS_DupValue(engine.context, if (scope.equal(try scope.get(failure, "code"), try scope.text("not_found"))) try h.values.result(&scope, true, c.pi_js_bool(engine.context, 0)) else try h.values.result(&scope, false, failure));
    }
    if (!scope.truthy(try scope.get(value, "ok"))) return c.JS_DupValue(engine.context, value);
    const bindings = try scope.get(saved, "bindings");
    const receiver = try scope.get(saved, "self");
    const map = try scope.get(bindings, "connections");
    if (!scope.truthy(try scope.call(try scope.get(bindings, "weakHas"), map, &.{receiver}))) return js.typeError(engine, "Cannot read private member #connection from an object whose class did not declare it");
    const connection = try scope.call(try scope.get(bindings, "weakGet"), map, &.{receiver});
    const pending = try scope.call(try scope.get(bindings, "listFilesOver"), c.pi_js_undefined(), &.{ connection, try scope.get(value, "value"), try scope.get(saved, "options"), try scope.get(saved, "context") });
    return c.JS_DupValue(engine.context, pending);
}
fn localListing(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, bindings: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try scope.object();
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "self", receiver);
    try scope.put(saved, "options", h.arg(args, 1));
    try scope.put(saved, "context", h.arg(args, 2));
    return c.JS_DupValue(engine.context, try h.wait(advance, &scope, saved, try scope.invoke(receiver, "absolutePath", &.{ h.arg(args, 0), h.arg(args, 2) }), Stage.listing));
}
fn localDispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return localListing(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, bindings: c.JSValue, method: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .absolutePath) return c.JS_DupValue(engine.context, try h.values.result(&scope, true, try paths.resolve(&scope, bindings, try scope.get(receiver, "cwd"), h.arg(args, 0))));
    if (method == .joinPath) {
        var values: std.ArrayList(c.JSValue) = .empty;
        defer values.deinit(engine.gpa);
        var iterator = try js.Iterator.init(engine, h.arg(args, 0), try scope.get(try scope.global("Symbol"), "iterator"));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |value| try values.append(engine.gpa, try scope.own(value));
        return c.JS_DupValue(engine.context, try h.values.result(&scope, true, try scope.invoke(try scope.get(bindings, "paths"), "join", values.items)));
    }
    const saved = try scope.object();
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "self", receiver);
    try scope.put(saved, "method", c.JS_NewInt32(engine.context, @intFromEnum(method)));
    try scope.put(saved, "path", h.arg(args, 0));
    try scope.put(saved, "options", if (method == .createTempFile) h.arg(args, 0) else h.arg(args, 1));
    const context = h.arg(args, switch (method) {
        .watch, .exec, .readTextLines, .openBinaryReader, .writeFile, .appendFile, .truncateFile, .renameFile, .createDir, .remove => 2,
        .cleanup => 0,
        else => 1,
    });
    try scope.put(saved, "context", context);
    if (method == .exists) return c.JS_DupValue(engine.context, try h.wait(advance, &scope, saved, try scope.invoke(receiver, "fileInfo", &.{ h.arg(args, 0), context }), Stage.exists));
    if (method == .readTextLines) {
        try scope.put(saved, "method", c.JS_NewInt32(engine.context, @intFromEnum(@import("native_env_remote.zig").Method.readTextLines)));
        return c.JS_DupValue(engine.context, try @import("native_env_remote_readers.zig").invoke(&scope, saved, @import("native_env_remote.zig").Method.readTextLines, args));
    }
    return switch (method) {
        .exec, .cleanup => @import("native_env_node_exec.zig").invoke(engine, receiver, args, bindings, method),
        .watch => @import("native_env_node_watch.zig").invoke(engine, receiver, args, bindings),
        else => @import("native_env_node_files.zig").invoke(engine, receiver, args, bindings, method),
    };
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const value = invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0], @enumFromInt(raw)) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(value);
    return @import("native_durable.zig").resolvedPromise(engine, value) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn create(engine: *js.Engine, shared: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (.{ "FileError", "ExecutionError", "RemoteError", "toError" }) |key| try scope.put(bindings, key, try scope.get(shared, key));
    var intrinsic = try @import("native_durable_await.zig").Intrinsics.init(engine);
    defer intrinsic.deinit(engine);
    try scope.put(bindings, "promise_constructor", intrinsic.constructor);
    try scope.put(bindings, "promise_resolve", intrinsic.resolve);
    try scope.put(bindings, "promise_then", intrinsic.then_function);
    if (!engine.native_module_names.contains("node:path")) try @import("node_path.zig").install(engine, engine.native_io orelse return error.NativeIoRequired);
    try @import("node_url.zig").install(engine);
    try scope.put(bindings, "paths", engine.native_module_values.get("node:path").?);
    try scope.put(bindings, "fileURLToPath", try scope.get(engine.native_module_values.get("node:url").?, "fileURLToPath"));
    try scope.put(bindings, "listFilesOver", try scope.own(try @import("native_env_list_files.zig").create(engine, shared)));
    const weak = try scope.own(try js.builtin(engine, "WeakMap", &.{}));
    try scope.put(bindings, "connections", weak);
    inline for (.{ .{ "weakHas", "has" }, .{ "weakGet", "get" }, .{ "weakSet", "set" } }) |entry| try scope.put(bindings, entry[0], try scope.get(weak, entry[1]));
    const prototype = try scope.object();
    const node = try scope.own(try @import("native_class.zig").constructor(engine, "NodeExecutionEnv", 1, prototype, constructNode, &.{}));
    var data = [_]c.JSValue{bindings};
    const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const length: c_int = switch (method) {
            .cleanup => 1,
            .watch, .exec, .readTextLines, .openBinaryReader, .writeFile, .appendFile, .truncateFile, .renameFile, .createDir, .remove => 3,
            else => 2,
        };
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, length, @intCast(field.value), 1, &data)));
        if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) return js.capture(engine);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const local_prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, prototype)));
    const local = try scope.own(try @import("native_class.zig").constructor(engine, "LocalExecutionEnv", 1, local_prototype, constructLocal, &.{bindings}));
    try scope.put(bindings, "local", local);
    if (c.JS_SetPrototype(engine.context, local, node) < 0) return js.capture(engine);
    const listing = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, localDispatch, "listFiles", 3, 0, 1, &data)));
    if (c.JS_SetPrototype(engine.context, listing, async_prototype) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, local_prototype, "listFiles", c.JS_DupValue(engine.context, listing), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const result = try scope.object();
    try scope.put(result, "NodeExecutionEnv", node);
    try scope.put(result, "LocalExecutionEnv", local);
    return c.JS_DupValue(engine.context, result);
}

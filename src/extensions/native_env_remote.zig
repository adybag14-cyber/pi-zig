//! Source RemoteExecutionEnv. Guest property reads and Connection calls remain virtual.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const Scope = h.Scope;
const classes = @import("native_class.zig");
const c = js.c;
pub const Method = enum(c_int) { absolutePath, joinPath, readTextFile, readBinaryFile, openBinaryReader, openTextLineReader, readTextLines, writeFile, appendFile, truncateFile, flushFile, renameFile, fileInfo, listDir, listFiles, openDirReader, canonicalPath, exists, createDir, remove, createTempDir, createTempFile, watch, exec, cleanup };
const Stage = enum(c_int) { resolved, joined, reply, info, rename_destination, exists, temp_info, temp_paths, temp_reply };
const State = struct { engine: *js.Engine, fields: c.JSValue };
fn state(engine: *js.Engine, receiver: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, engine.native_env_remote_class) orelse return js.capture(engine)));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_env_remote_class) orelse return));
    c.JS_FreeValueRT(runtime, owned.fields);
    engine.gpa.destroy(owned);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_env_remote_class) orelse return));
    c.JS_MarkValue(runtime, owned.fields, visit);
}
fn method(scope: *Scope, captures: c.JSValue) !Method {
    var raw: i32 = undefined;
    if (c.JS_ToInt32(scope.engine.context, &raw, try scope.get(captures, "method")) < 0) return js.capture(scope.engine);
    return @enumFromInt(raw);
}
fn requestAfterResolve(scope: *Scope, captures: c.JSValue, resolved: c.JSValue) !c.JSValue {
    try scope.put(captures, "path", resolved);
    const operation = try method(scope, captures);
    const receiver = try scope.get(captures, "self");
    if (operation == .absolutePath) return h.values.result(scope, true, resolved);
    if (operation == .listFiles) return scope.call(try scope.get(try scope.get(captures, "bindings"), "listFilesOver"), c.pi_js_undefined(), &.{ try scope.get(receiver, "connection"), resolved, try scope.get(captures, "options"), try scope.get(captures, "context") });
    if (operation == .renameFile) {
        try scope.put(captures, "source", resolved);
        try scope.put(captures, "path", try scope.get(captures, "input"));
        return h.wait(advance, scope, captures, try h.path.resolve(scope, try scope.get(captures, "bindings"), receiver, try scope.get(captures, "destination")), Stage.rename_destination);
    }
    if (try h.errors.aborted(scope, captures)) |early| return early;
    const json = try scope.object();
    try scope.put(json, "path", resolved);
    const options = try scope.get(captures, "options");
    const op: []const u8 = switch (operation) {
        .fileInfo => "lstat",
        .canonicalPath => "realpath",
        .createDir => "mkdir",
        .remove => "rm",
        .truncateFile => "truncate",
        .flushFile => "fsync",
        else => unreachable,
    };
    switch (operation) {
        .createDir => {
            const recursive = try h.optional(scope, options, "recursive");
            try scope.put(json, "recursive", if (h.nullish(recursive)) c.pi_js_bool(scope.engine.context, 1) else recursive);
        },
        .remove => inline for (.{ "recursive", "force" }) |key| {
            const value = try h.optional(scope, options, key);
            try scope.put(json, key, if (h.nullish(value)) c.pi_js_bool(scope.engine.context, 0) else value);
        },
        .truncateFile => {
            const size = try scope.get(captures, "size");
            if (!try h.validInteger(scope, size, false)) return h.fieldError(scope, captures, "invalid", "File size must be a non-negative safe integer");
            try scope.put(json, "size", size);
        },
        else => {},
    }
    return h.wait(advance, scope, captures, try h.request(scope, receiver, op, json, null), Stage.reply);
}
fn continueReply(scope: *Scope, captures: c.JSValue, reply: c.JSValue) !c.JSValue {
    const operation = try method(scope, captures);
    if (operation == .truncateFile or operation == .flushFile) if (try h.errors.aborted(scope, captures)) |early| return early;
    if (operation == .fileInfo) {
        try scope.put(captures, "remote", try scope.get(reply, "json"));
        const receiver = try scope.get(captures, "self");
        return h.wait(advance, scope, captures, try scope.invoke(try scope.get(receiver, "connection"), "info", &.{}), Stage.info);
    }
    const value = if (operation == .canonicalPath) try scope.get(try scope.get(reply, "json"), "path") else c.pi_js_undefined();
    return h.values.result(scope, true, value);
}
fn advance(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .exists) return h.throw(&scope, value);
        return c.JS_DupValue(engine.context, try h.errors.mapError(&scope, captures, value));
    }
    const result = continued: {
        const next = continuation(&scope, captures, value, stage) catch |err| {
            if (err != error.JavaScriptException) return err;
            break :continued try h.errors.mapError(&scope, captures, try h.errors.captured(&scope));
        };
        break :continued next;
    };
    return c.JS_DupValue(engine.context, result);
}
fn continuation(scope: *Scope, captures: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    const bindings = try scope.get(captures, "bindings");
    const receiver = try scope.get(captures, "self");
    return switch (stage) {
        .resolved => requestAfterResolve(scope, captures, value),
        .joined => joined: {
            const paths = try h.path.paths(scope, bindings, value);
            const parts = try scope.get(captures, "parts");
            var iterator = try js.Iterator.init(scope.engine, parts, try scope.get(try scope.global("Symbol"), "iterator"));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            var args: std.ArrayList(c.JSValue) = .empty;
            defer args.deinit(scope.engine.gpa);
            while (try iterator.next()) |item| try args.append(scope.engine.gpa, try scope.own(item));
            break :joined try h.values.result(scope, true, try scope.invoke(paths, "join", args.items));
        },
        .reply => continueReply(scope, captures, value),
        .info => h.fileInfo(scope, captures, try scope.get(captures, "remote"), try h.path.paths(scope, bindings, value)),
        .rename_destination => renamed: {
            // Resolution failures use the original source path. Aborts use the destination, request failures the source.
            try scope.put(captures, "path", value);
            if (try h.errors.aborted(scope, captures)) |early| break :renamed early;
            try scope.put(captures, "path", try scope.get(captures, "source"));
            const json = try scope.object();
            try scope.put(json, "path", try scope.get(captures, "source"));
            try scope.put(json, "to", value);
            break :renamed try h.wait(advance, scope, captures, try h.request(scope, receiver, "rename", json, null), Stage.reply);
        },
        .exists => exists: {
            if (scope.truthy(try scope.get(value, "ok"))) break :exists try h.values.result(scope, true, c.pi_js_bool(scope.engine.context, 1));
            if (scope.equal(try scope.get(try scope.get(value, "error"), "code"), try scope.text("not_found"))) break :exists try h.values.result(scope, true, c.pi_js_bool(scope.engine.context, 0));
            break :exists value;
        },
        .temp_info => tmp_info: {
            try scope.put(captures, "tmpdir", try scope.get(value, "tmpdir"));
            break :tmp_info try h.wait(advance, scope, captures, try scope.invoke(try scope.get(receiver, "connection"), "info", &.{}), Stage.temp_paths);
        },
        .temp_paths => tmp_paths: {
            const prefix = try scope.get(captures, "prefix");
            const json = try scope.object();
            try scope.put(json, "path", try scope.invoke(try h.path.paths(scope, bindings, value), "join", &.{ try scope.get(captures, "tmpdir"), if (h.nullish(prefix)) try scope.text("tmp-") else prefix }));
            break :tmp_paths try h.wait(advance, scope, captures, try h.request(scope, receiver, "mkdtemp", json, null), Stage.temp_reply);
        },
        .temp_reply => h.values.result(scope, true, try scope.get(try scope.get(value, "json"), "path")),
    };
}
fn makeCaptures(scope: *Scope, receiver: c.JSValue, args: []const c.JSValue, operation: Method) !c.JSValue {
    const fields = (try state(scope.engine, receiver)).fields;
    const result = try scope.object();
    try scope.put(result, "self", receiver);
    try scope.put(result, "bindings", try scope.get(fields, "bindings"));
    try scope.put(result, "private", fields);
    try scope.put(result, "method", c.JS_NewInt32(scope.engine.context, @intFromEnum(operation)));
    try scope.put(result, "path", h.arg(args, 0));
    try scope.put(result, "input", h.arg(args, 0));
    try scope.put(result, "context", h.arg(args, switch (operation) {
        .joinPath, .absolutePath, .readTextFile, .readBinaryFile, .openTextLineReader, .flushFile, .fileInfo, .listDir, .openDirReader, .canonicalPath, .exists, .createTempDir, .createTempFile => 1,
        .cleanup => 0,
        else => 2,
    }));
    try scope.put(result, "options", h.arg(args, 1));
    if (operation == .createTempFile) try scope.put(result, "options", h.arg(args, 0));
    try scope.put(result, "size", h.arg(args, 1));
    try scope.put(result, "destination", h.arg(args, 1));
    try scope.put(result, "parts", h.arg(args, 0));
    try scope.put(result, "prefix", h.arg(args, 0));
    if (operation == .joinPath or operation == .createTempDir or operation == .watch or operation == .cleanup) try scope.put(result, "path", c.pi_js_undefined());
    return result;
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, operation: Method) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try makeCaptures(&scope, receiver, args, operation);
    const bindings = try scope.get(saved, "bindings");
    const pending = switch (operation) {
        .absolutePath, .fileInfo, .canonicalPath, .createDir, .remove, .truncateFile, .flushFile, .renameFile, .listFiles => try h.wait(advance, &scope, saved, h.path.resolve(&scope, bindings, receiver, h.arg(args, 0)) catch |err| try h.rejected(&scope, err), Stage.resolved),
        .joinPath => try h.wait(advance, &scope, saved, try scope.invoke(try scope.get(receiver, "connection"), "info", &.{}), Stage.joined),
        .exists => try h.wait(advance, &scope, saved, try scope.invoke(receiver, "fileInfo", &.{ h.arg(args, 0), h.arg(args, 1) }), Stage.exists),
        .createTempDir => temp: {
            try scope.put(saved, "path", c.pi_js_undefined());
            if (try h.errors.aborted(&scope, saved)) |early| break :temp try h.resolved(&scope, early);
            break :temp try h.wait(advance, &scope, saved, try scope.invoke(try scope.get(receiver, "connection"), "info", &.{}), Stage.temp_info);
        },
        .readTextFile, .readBinaryFile, .openBinaryReader, .openTextLineReader, .readTextLines, .listDir, .openDirReader => try @import("native_env_remote_readers.zig").invoke(&scope, saved, operation, args),
        .writeFile, .appendFile, .createTempFile => try @import("native_env_remote_write.zig").invoke(&scope, saved, operation, args),
        .exec, .cleanup => try @import("native_env_remote_exec.zig").invoke(&scope, saved, operation, args),
        .watch => try @import("native_env_remote_watch.zig").invoke(&scope, saved, args),
    };
    return c.JS_DupValue(engine.context, pending);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(raw)) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(target, "prototype");
    const receiver = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.native_env_remote_class)));
    inline for (.{ "id", "cwd", "connection" }) |key| try scope.put(receiver, key, c.pi_js_undefined());
    const fields = try scope.object();
    const owner = try engine.gpa.create(State);
    owner.* = .{ .engine = engine, .fields = c.JS_DupValue(engine.context, fields) };
    _ = c.JS_SetOpaque(receiver, owner);
    inline for (.{ "id", "cwd", "connection" }) |key| try scope.set(receiver, key, try scope.get(h.arg(args, 0), key));
    inline for (.{ "shellPath", "shellEnv" }) |key| try scope.put(fields, key, try scope.get(h.arg(args, 0), key));
    const watch_options = try scope.get(h.arg(args, 0), "watch");
    try scope.put(fields, "watch", if (h.nullish(watch_options)) try scope.object() else watch_options);
    try scope.put(fields, "bindings", constants[0]);
    try scope.put(fields, "running", try scope.own(try js.builtin(engine, "Map", &.{})));
    return c.JS_DupValue(engine.context, receiver);
}
pub fn create(engine: *js.Engine, shared: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (engine.native_env_remote_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_remote_class);
        const definition: c.JSClassDef = .{ .class_name = "RemoteExecutionEnv", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, engine.native_env_remote_class, &definition) < 0) return error.OutOfMemory;
    }
    const bindings = try scope.object();
    inline for (.{ "FileError", "RemoteError", "ExecutionError", "nodePlatform", "isConnectionLost" }) |key| try scope.put(bindings, key, try scope.get(shared, key));
    var promises = try @import("native_durable_await.zig").Intrinsics.init(engine);
    defer promises.deinit(engine);
    try scope.put(bindings, "promise_constructor", promises.constructor);
    try scope.put(bindings, "promise_resolve", promises.resolve);
    try scope.put(bindings, "promise_then", promises.then_function);
    try @import("node_path.zig").install(engine, engine.native_io orelse return error.NativeIoRequired);
    try @import("node_url.zig").install(engine);
    try scope.put(bindings, "paths", engine.native_module_values.get("node:path").?);
    try scope.put(bindings, "fileURLToPath", try scope.get(engine.native_module_values.get("node:url").?, "fileURLToPath"));
    try scope.put(bindings, "listFilesOver", try scope.own(try @import("native_env_list_files.zig").create(engine, shared)));
    try @import("native_env_remote_reader_values.zig").install(&scope, bindings);
    try scope.put(bindings, "RemoteWatcher", try @import("native_env_remote_watch.zig").create(&scope, bindings));
    const prototype = try scope.object();
    inline for (std.meta.fields(Method)) |field| {
        const operation: Method = @enumFromInt(field.value);
        const length: c_int = switch (operation) {
            .cleanup => 1,
            .openBinaryReader, .readTextLines, .writeFile, .appendFile, .truncateFile, .renameFile, .listFiles, .createDir, .remove, .watch, .exec => 3,
            else => 2,
        };
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, length, @intCast(field.value), 0, null)));
        const async_method = switch (operation) {
            .writeFile, .appendFile, .flushFile, .listDir, .canonicalPath, .createDir, .remove => false,
            else => true,
        };
        if (async_method) {
            const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return classes.constructor(engine, "RemoteExecutionEnv", 1, prototype, construct, &.{bindings});
}

//! Retained Source binary, directory and text readers. Their state belongs to the VM graph.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const range = @import("native_env_remote_range.zig");
const Scope = h.Scope;
const c = js.c;
const Kind = enum(c_int) { binary, directory, text };
const Method = enum(c_int) { info, read, scanLines, next, readLine, close };
const Stage = enum(c_int) { metadata, info, range, scan, dir_paths, directory, text, close };
const State = struct { engine: *js.Engine, fields: c.JSValue };
fn classId(engine: *js.Engine, kind: Kind) *c.JSClassID {
    return switch (kind) {
        .binary => &engine.native_env_binary_reader_class,
        .directory => &engine.native_env_dir_reader_class,
        .text => &engine.native_env_text_reader_class,
    };
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.fields);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.fields, visit);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var raw: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &raw, constants[1]) < 0) return js.capture(engine);
    const kind: Kind = @enumFromInt(raw);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, try scope.get(target, "prototype"), classId(engine, kind).*)));
    const fields = try scope.object();
    try scope.put(fields, "handle", h.arg(args, 0));
    try scope.put(fields, "bindings", constants[0]);
    try scope.put(fields, "closed", c.pi_js_bool(engine.context, 0));
    try scope.put(fields, "done", c.pi_js_bool(engine.context, 0));
    if (kind == .text) {
        try scope.put(fields, "offset", c.JS_NewInt32(engine.context, 0));
        try scope.put(fields, "buffered", try scope.text(""));
        try scope.put(fields, "ended", c.pi_js_bool(engine.context, 0));
        const constructor = try scope.get(constants[0], "StreamDecoder");
        try scope.put(fields, "decoder", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null))));
    }
    const owner = try engine.gpa.create(State);
    owner.* = .{ .engine = engine, .fields = c.JS_DupValue(engine.context, fields) };
    _ = c.JS_SetOpaque(receiver, owner);
    return c.JS_DupValue(engine.context, receiver);
}
fn snapshot(scope: *Scope, receiver: c.JSValue, fields: c.JSValue, context: c.JSValue) !c.JSValue {
    const captures = try scope.object();
    try scope.put(captures, "self", receiver);
    try scope.put(captures, "private", fields);
    try scope.put(captures, "bindings", try scope.get(fields, "bindings"));
    const handle = try scope.get(fields, "handle");
    try scope.put(captures, "handle", handle);
    try scope.put(captures, "path", try scope.get(handle, "path"));
    try scope.put(captures, "context", context);
    return captures;
}
fn directoryPump(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const fields = try scope.get(captures, "private");
    const entries = try scope.get(captures, "entries");
    const count = try scope.get(entries, "length");
    const maximum = try scope.get(captures, "maximum");
    const less = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 4, count, maximum)));
    if (scope.truthy(try scope.get(fields, "done")) or !scope.truthy(less)) {
        const page = try scope.object();
        try scope.put(page, "entries", entries);
        try scope.put(page, "done", try scope.get(fields, "done"));
        return h.values.result(scope, true, page);
    }
    const json = try scope.object();
    try scope.put(json, "max", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, maximum, count))));
    return h.wait(advance, scope, captures, try h.handleRequest(scope, try scope.get(captures, "handle"), "readdir", json, null), Stage.directory);
}
fn textPump(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const fields = try scope.get(captures, "private");
    const buffered = try scope.get(fields, "buffered");
    const newline = try scope.invoke(buffered, "indexOf", &.{try scope.text("\n")});
    if (!scope.equal(newline, c.JS_NewInt32(scope.engine.context, -1))) {
        const line = try scope.object();
        try scope.put(line, "text", try scope.invoke(buffered, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), newline }));
        try scope.put(line, "terminated", c.pi_js_bool(scope.engine.context, 1));
        const from = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, newline, c.JS_NewInt32(scope.engine.context, 1))));
        try scope.put(fields, "buffered", try scope.invoke(buffered, "slice", &.{from}));
        return h.values.result(scope, true, line);
    }
    if (scope.truthy(try scope.get(fields, "ended"))) {
        if (scope.equal(try scope.get(buffered, "length"), c.JS_NewInt32(scope.engine.context, 0))) return h.values.result(scope, true, c.pi_js_undefined());
        const line = try scope.object();
        try scope.put(line, "text", buffered);
        try scope.put(line, "terminated", c.pi_js_bool(scope.engine.context, 0));
        try scope.put(fields, "buffered", try scope.text(""));
        return h.values.result(scope, true, line);
    }
    return h.wait(advance, scope, captures, try scope.invoke(try scope.get(captures, "handle"), "pread", &.{ try scope.get(fields, "offset"), c.JS_NewInt32(scope.engine.context, 64 * 1024) }), Stage.text);
}
fn continuation(scope: *Scope, captures: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    const fields = try scope.get(captures, "private");
    const handle = try scope.get(captures, "handle");
    const bindings = try scope.get(captures, "bindings");
    switch (stage) {
        .metadata => {
            try scope.put(captures, "remote", try scope.get(value, "json"));
            return h.wait(advance, scope, captures, try scope.invoke(try scope.get(try scope.get(handle, "env"), "connection"), "info", &.{}), Stage.info);
        },
        .info => return h.fileInfo(scope, captures, try scope.get(captures, "remote"), try h.path.paths(scope, bindings, value)),
        .range => return if (c.JS_IsUndefined(value)) h.fieldError(scope, captures, "aborted", "aborted") else h.values.result(scope, true, try range.concat(scope, value, false)),
        .scan => return h.values.result(scope, true, try scope.get(value, "json")),
        .close => return c.pi_js_undefined(),
        .dir_paths => {
            try scope.put(captures, "paths", try h.path.paths(scope, bindings, value));
            return directoryPump(scope, captures);
        },
        .directory => {
            if (try h.errors.aborted(scope, captures)) |early| return early;
            const json = try scope.get(value, "json");
            const paths = try scope.get(captures, "paths");
            var iterator = try js.Iterator.init(scope.engine, try scope.get(json, "entries"), try scope.get(try scope.global("Symbol"), "iterator"));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |entry| {
                var row: Scope = .{ .engine = scope.engine };
                defer row.deinit();
                _ = try row.own(entry);
                const entry_path = try row.invoke(paths, "resolve", &.{ try row.get(captures, "path"), try row.get(entry, "name") });
                const failure = try row.get(entry, "error");
                if (!c.JS_IsUndefined(failure)) {
                    if (row.equal(try row.get(failure, "code"), try row.text("ENOENT"))) continue;
                    const constructor = try row.get(bindings, "RemoteError");
                    const remote = try row.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&failure))));
                    const error_state = try row.object();
                    try row.put(error_state, "bindings", bindings);
                    try row.put(error_state, "path", entry_path);
                    return scope.own(c.JS_DupValue(scope.engine.context, try h.errors.mapError(&row, error_state, remote)));
                }
                const entry_state = try row.object();
                try row.put(entry_state, "bindings", bindings);
                try row.put(entry_state, "path", entry_path);
                const result = try h.fileInfo(&row, entry_state, try row.get(entry, "info"), paths);
                if (row.truthy(try row.get(result, "ok"))) _ = try row.invoke(try row.get(captures, "entries"), "push", &.{try row.get(result, "value")});
            }
            try scope.put(fields, "done", c.pi_js_bool(scope.engine.context, @intFromBool(scope.equal(try scope.get(json, "done"), c.pi_js_bool(scope.engine.context, 1)))));
            return directoryPump(scope, captures);
        },
        .text => {
            if (try h.errors.aborted(scope, captures)) |early| return early;
            const length = try scope.get(value, "length");
            try scope.put(fields, "offset", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, try scope.get(fields, "offset"), length))));
            const decoder = try scope.get(fields, "decoder");
            const text = if (scope.equal(length, c.JS_NewInt32(scope.engine.context, 0))) ended: {
                try scope.put(fields, "ended", c.pi_js_bool(scope.engine.context, 1));
                break :ended try scope.invoke(decoder, "decode", &.{});
            } else try scope.invoke(decoder, "decode", &.{value});
            try scope.put(fields, "buffered", try scope.concat(try scope.get(fields, "buffered"), text));
            return textPump(scope, captures);
        },
    }
}
fn advance(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .close) return h.throw(&scope, value);
        return c.JS_DupValue(engine.context, try h.errors.mapError(&scope, captures, value));
    }
    const result = continuation(&scope, captures, value, stage) catch |err| {
        if (err != error.JavaScriptException) return err;
        return c.JS_DupValue(engine.context, try h.errors.mapError(&scope, captures, try h.errors.captured(&scope)));
    };
    return c.JS_DupValue(engine.context, result);
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, kind: Kind, operation: Method) !c.JSValue {
    const owner: *State = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, classId(engine, kind).*) orelse return js.capture(engine)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fields = owner.fields;
    const context = h.arg(args, switch (operation) {
        .read => 2,
        .scanLines, .next => 1,
        else => 0,
    });
    const captures = try snapshot(&scope, receiver, fields, context);
    if (operation == .close) {
        if (scope.truthy(try scope.get(fields, "closed"))) return @import("native_durable.zig").resolvedPromise(engine, c.pi_js_undefined());
        try scope.put(fields, "closed", c.pi_js_bool(engine.context, 1));
        if (kind == .text) try scope.put(fields, "buffered", try scope.text(""));
        const pending = try scope.invoke(try scope.get(captures, "handle"), "close", &.{});
        return c.JS_DupValue(engine.context, try h.wait(advance, &scope, captures, pending, Stage.close));
    }
    if (try h.errors.aborted(&scope, captures)) |early| return @import("native_durable.zig").resolvedPromise(engine, early);
    if (scope.truthy(try scope.get(fields, "closed"))) return @import("native_durable.zig").resolvedPromise(engine, try h.fieldError(&scope, captures, "invalid", switch (kind) {
        .binary => "Binary reader is closed",
        .directory => "Directory reader is closed",
        .text => "Text line reader is closed",
    }));
    const result = switch (operation) {
        .info => try h.wait(advance, &scope, captures, try h.handleRequest(&scope, try scope.get(captures, "handle"), "fstat", null, null), Stage.metadata),
        .read => read: {
            if (!try h.validInteger(&scope, h.arg(args, 0), false) or !try h.validInteger(&scope, h.arg(args, 1), false)) break :read try h.resolved(&scope, try h.fieldError(&scope, captures, "invalid", "Offset and length must be non-negative safe integers"));
            break :read try h.wait(advance, &scope, captures, try range.start(&scope, captures, try scope.get(captures, "handle"), h.arg(args, 0), h.arg(args, 1), 256 * 1024), Stage.range);
        },
        .scanLines => scan: {
            const start = try scope.get(h.arg(args, 0), "startLine");
            const end = try scope.get(h.arg(args, 0), "endLine");
            if (!try h.validInteger(&scope, start, false) or (!c.JS_IsUndefined(end) and (!try h.validInteger(&scope, end, false) or scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 5, end, start))))))) break :scan try h.resolved(&scope, try h.fieldError(&scope, captures, "invalid", "Invalid line range"));
            const json = try scope.object();
            try scope.put(json, "startLine", start);
            if (!c.JS_IsUndefined(end)) try scope.put(json, "endLine", end);
            break :scan try h.wait(advance, &scope, captures, try h.handleRequest(&scope, try scope.get(captures, "handle"), "scanLines", json, try h.signalOptions(&scope, captures)), Stage.scan);
        },
        .next => directory: {
            if (!try h.validInteger(&scope, h.arg(args, 0), true)) break :directory try h.resolved(&scope, try h.fieldError(&scope, captures, "invalid", "maxEntries must be a positive safe integer"));
            try scope.put(captures, "maximum", h.arg(args, 0));
            try scope.put(captures, "entries", try scope.array());
            const connection = try scope.get(try scope.get(try scope.get(captures, "handle"), "env"), "connection");
            break :directory try h.wait(advance, &scope, captures, try scope.invoke(connection, "info", &.{}), Stage.dir_paths);
        },
        .readLine => try h.resolved(&scope, try textPump(&scope, captures)),
        .close => unreachable,
    };
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(@divTrunc(raw, 16)), @enumFromInt(@mod(raw, 16))) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn install(scope: *Scope, bindings: c.JSValue) !void {
    try scope.put(bindings, "StreamDecoder", try scope.own(try @import("native_env_decode.zig").create(scope.engine)));
    try scope.put(bindings, "Handle", try @import("native_env_handle.zig").create(scope, bindings));
    inline for (.{ Kind.binary, Kind.directory, Kind.text }) |kind| {
        const id = classId(scope.engine, kind);
        if (id.* == 0) {
            _ = c.JS_NewClassID(scope.engine.runtime, id);
            const definition: c.JSClassDef = .{ .class_name = "Env Reader", .finalizer = finalize, .gc_mark = mark };
            if (c.JS_NewClass(scope.engine.runtime, id.*, &definition) < 0) return error.OutOfMemory;
        }
        const prototype = try scope.object();
        const name: [:0]const u8 = switch (kind) {
            .binary => "RemoteBinaryReader",
            .directory => "RemoteDirReader",
            .text => "RemoteTextLineReader",
        };
        const constructor = try scope.own(try @import("native_class.zig").constructor(scope.engine, name, 1, prototype, construct, &.{ bindings, c.JS_NewInt32(scope.engine.context, @intFromEnum(kind)) }));
        inline for (std.meta.fields(Method)) |field| {
            const operation: Method = @enumFromInt(field.value);
            const selected = operation == .close or switch (kind) {
                .binary => operation == .info or operation == .read or operation == .scanLines,
                .directory => operation == .next,
                .text => operation == .readLine,
            };
            if (selected) {
                const length: c_int = switch (operation) {
                    .read => 3,
                    .scanLines, .next => 2,
                    else => 1,
                };
                const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, field.name, length, @intFromEnum(kind) * 16 + @intFromEnum(operation), 0, null)));
                const async_prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
                if (c.JS_SetPrototype(scope.engine.context, function, async_prototype) < 0) return js.capture(scope.engine);
                if (c.JS_DefinePropertyValueStr(scope.engine.context, prototype, field.name, c.JS_DupValue(scope.engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(scope.engine);
            }
        }
        try scope.put(bindings, name, constructor);
    }
}

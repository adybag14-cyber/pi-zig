//! Node readers retain Source's ordinary public fields and virtual file/dir calls.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const errors = @import("native_env_node_errors.zig");
const Scope = h.Scope;
const c = js.c;
pub const Kind = enum(c_int) { binary, text, directory };
const Method = enum(c_int) { info, read, scanLines, readLine, next, close };
const Stage = enum(c_int) { info, binary, scan, text, directory, directory_stat, close };
fn binary(scope: *Scope, op: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, op, left, right)));
}
fn kindValue(scope: *Scope, value: c.JSValue) !Kind {
    var raw: i32 = undefined;
    if (c.JS_ToInt32(scope.engine.context, &raw, value) < 0) return js.capture(scope.engine);
    return @enumFromInt(raw);
}
pub fn fileInfo(scope: *Scope, bindings: c.JSValue, path: c.JSValue, stats: c.JSValue) !c.JSValue {
    const kind: ?[]const u8 = if (scope.truthy(try scope.invoke(stats, "isFile", &.{}))) "file" else if (scope.truthy(try scope.invoke(stats, "isDirectory", &.{}))) "directory" else if (scope.truthy(try scope.invoke(stats, "isSymbolicLink", &.{}))) "symlink" else null;
    if (kind == null) return errors.expected(scope, bindings, "invalid", "Unsupported file type", path);
    const info = try scope.object();
    try scope.put(info, "name", try scope.invoke(try scope.get(bindings, "paths"), "basename", &.{path}));
    try scope.put(info, "path", path);
    try scope.put(info, "kind", try scope.text(kind.?));
    try scope.put(info, "size", try scope.get(stats, "size"));
    try scope.put(info, "mtimeMs", try scope.get(stats, "mtimeMs"));
    return h.values.result(scope, true, info);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const kind = try kindValue(&scope, constants[1]);
    const receiver = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.put(receiver, if (kind == .directory) "dir" else "file", c.pi_js_undefined());
    try scope.put(receiver, "path", c.pi_js_undefined());
    if (kind == .text) {
        const decoder = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(constants[0], "StreamDecoder"), 0, null)));
        try scope.put(receiver, "decoder", decoder);
        try scope.put(receiver, "chunk", try scope.own(try js.builtin(engine, "Uint8Array", &.{c.JS_NewInt32(engine.context, 64 * 1024)})));
        try scope.put(receiver, "byteOffset", c.JS_NewInt32(engine.context, 0));
        try scope.put(receiver, "buffered", try scope.text(""));
        try scope.put(receiver, "ended", c.pi_js_bool(engine.context, 0));
    }
    if (kind == .directory) try scope.put(receiver, "done", c.pi_js_bool(engine.context, 0));
    try scope.put(receiver, "closed", c.pi_js_bool(engine.context, 0));
    try scope.set(receiver, if (kind == .directory) "dir" else "file", h.arg(args, 0));
    try scope.set(receiver, "path", h.arg(args, 1));
    return c.JS_DupValue(engine.context, receiver);
}
fn abort(scope: *Scope, saved: c.JSValue) !?c.JSValue {
    const signal = try scope.get(try scope.get(saved, "context"), "abortSignal");
    const path = try scope.get(try scope.get(saved, "self"), "path");
    if (!h.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return try errors.expected(scope, try scope.get(saved, "bindings"), "aborted", "aborted", path);
    return null;
}
fn failure(scope: *Scope, saved: c.JSValue, reason: c.JSValue) !c.JSValue {
    return errors.failed(scope, try scope.get(saved, "bindings"), reason, try scope.get(try scope.get(saved, "self"), "path"));
}
fn caught(scope: *Scope, saved: c.JSValue, err: anyerror, generation: u64) !c.JSValue {
    if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    _ = @import("native_durable.zig").reject(scope.engine, err);
    return failure(scope, saved, try scope.own(c.JS_GetException(scope.engine.context)));
}
fn readCall(scope: *Scope, saved: c.JSValue, chunk: c.JSValue, offset: c.JSValue, stage: Stage) !c.JSValue {
    const receiver = try scope.get(saved, "self");
    const file = try scope.get(receiver, "file");
    const read = try scope.get(file, "read");
    const pending = try scope.call(read, file, &.{ chunk, c.JS_NewInt32(scope.engine.context, 0), try scope.get(chunk, "length"), offset });
    return h.wait(advance, scope, saved, pending, stage);
}
fn binaryPump(scope: *Scope, saved: c.JSValue) !c.JSValue {
    const total = try scope.get(saved, "total");
    const length = try scope.get(saved, "length");
    if (!scope.truthy(try binary(scope, 4, total, length))) return h.values.result(scope, true, try @import("native_env_remote_range.zig").concat(scope, saved, false));
    const count = try scope.invoke(try scope.global("Math"), "min", &.{ try binary(scope, 1, length, total), c.JS_NewInt32(scope.engine.context, 1024 * 1024) });
    const chunk = try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{count}));
    try scope.put(saved, "chunk", chunk);
    return readCall(scope, saved, chunk, try binary(scope, 0, try scope.get(saved, "offset"), total), .binary);
}
fn textPump(scope: *Scope, saved: c.JSValue) !c.JSValue {
    const receiver = try scope.get(saved, "self");
    const buffered = try scope.get(receiver, "buffered");
    const newline = try scope.invoke(buffered, "indexOf", &.{try scope.text("\n")});
    if (!scope.equal(newline, c.JS_NewInt32(scope.engine.context, -1))) {
        const text = try scope.invoke(try scope.get(receiver, "buffered"), "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), newline });
        try scope.set(receiver, "buffered", try scope.invoke(try scope.get(receiver, "buffered"), "slice", &.{try binary(scope, 0, newline, c.JS_NewInt32(scope.engine.context, 1))}));
        const line = try scope.object();
        try scope.put(line, "text", text);
        try scope.put(line, "terminated", c.pi_js_bool(scope.engine.context, 1));
        return h.values.result(scope, true, line);
    }
    if (scope.truthy(try scope.get(receiver, "ended"))) {
        if (scope.equal(try scope.get(try scope.get(receiver, "buffered"), "length"), c.JS_NewInt32(scope.engine.context, 0))) return h.values.result(scope, true, c.pi_js_undefined());
        const text = try scope.get(receiver, "buffered");
        try scope.set(receiver, "buffered", try scope.text(""));
        const line = try scope.object();
        try scope.put(line, "text", text);
        try scope.put(line, "terminated", c.pi_js_bool(scope.engine.context, 0));
        return h.values.result(scope, true, line);
    }
    const file = try scope.get(receiver, "file");
    const read = try scope.get(file, "read");
    const chunk = try scope.get(receiver, "chunk");
    const length = try scope.get(try scope.get(receiver, "chunk"), "length");
    const offset = try scope.get(receiver, "byteOffset");
    return h.wait(advance, scope, saved, try scope.call(read, file, &.{ chunk, c.JS_NewInt32(scope.engine.context, 0), length, offset }), Stage.text);
}
fn directoryPump(scope: *Scope, saved: c.JSValue) !c.JSValue {
    const receiver = try scope.get(saved, "self");
    const entries = try scope.get(saved, "entries");
    if (scope.truthy(try scope.get(receiver, "done")) or !scope.truthy(try binary(scope, 4, try scope.get(entries, "length"), try scope.get(saved, "maximum")))) {
        const page = try scope.object();
        try scope.put(page, "entries", entries);
        try scope.put(page, "done", try scope.get(receiver, "done"));
        return h.values.result(scope, true, page);
    }
    return h.wait(advance, scope, saved, try scope.invoke(try scope.get(receiver, "dir"), "read", &.{}), Stage.directory);
}
fn step(scope: *Scope, saved: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !c.JSValue {
    if (stage == .close) return c.pi_js_undefined();
    const receiver = try scope.get(saved, "self");
    const bindings = try scope.get(saved, "bindings");
    if (stage == .directory_stat and rejected) {
        const node_error = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
        if (node_error < 0) return js.capture(scope.engine);
        if (node_error != 0 and scope.equal(try scope.get(value, "code"), try scope.text("ENOENT"))) return directoryPump(scope, saved);
        return errors.failed(scope, bindings, value, try scope.get(saved, "entryPath"));
    }
    if (rejected) return failure(scope, saved, value);
    switch (stage) {
        .info => return fileInfo(scope, bindings, try scope.get(saved, "infoPath"), value),
        .directory => {
            if (c.JS_IsNull(value)) {
                try scope.set(receiver, "done", c.pi_js_bool(scope.engine.context, 1));
                return directoryPump(scope, saved);
            }
            if (try abort(scope, saved)) |aborted| return aborted;
            const path = try scope.invoke(try scope.get(bindings, "paths"), "resolve", &.{ try scope.get(receiver, "path"), try scope.get(value, "name") });
            try scope.put(saved, "entryPath", path);
            return h.wait(advance, scope, saved, try scope.invoke(try scope.get(bindings, "fs"), "lstat", &.{path}), Stage.directory_stat);
        },
        .directory_stat => {
            const info = try fileInfo(scope, bindings, try scope.get(saved, "entryPath"), value);
            if (scope.truthy(try scope.get(info, "ok"))) _ = try scope.invoke(try scope.get(saved, "entries"), "push", &.{try scope.get(info, "value")});
            return directoryPump(scope, saved);
        },
        .binary, .scan, .text => {
            const count = try scope.get(value, "bytesRead");
            if (try abort(scope, saved)) |aborted| return aborted;
            const empty = scope.equal(count, c.JS_NewInt32(scope.engine.context, 0));
            if (stage == .binary) {
                if (empty) return h.values.result(scope, true, try @import("native_env_remote_range.zig").concat(scope, saved, false));
                const chunk = try scope.get(saved, "chunk");
                const bytes = if (scope.equal(count, try scope.get(chunk, "length"))) chunk else try scope.invoke(chunk, "subarray", &.{ c.JS_NewInt32(scope.engine.context, 0), count });
                _ = try scope.invoke(try scope.get(saved, "chunks"), "push", &.{bytes});
                try scope.put(saved, "total", try binary(scope, 0, try scope.get(saved, "total"), count));
                return binaryPump(scope, saved);
            }
            if (stage == .scan) {
                const scanner = try scope.get(saved, "scanner");
                if (empty) return h.values.result(scope, true, try scope.invoke(scanner, "finish", &.{}));
                const chunk = try scope.get(saved, "chunk");
                _ = try scope.invoke(scanner, "push", &.{try scope.invoke(chunk, "subarray", &.{ c.JS_NewInt32(scope.engine.context, 0), count })});
                const position = try binary(scope, 0, try scope.get(saved, "position"), count);
                try scope.put(saved, "position", position);
                return readCall(scope, saved, chunk, position, .scan);
            }
            try scope.set(receiver, "byteOffset", try binary(scope, 0, try scope.get(receiver, "byteOffset"), count));
            const previous = try scope.get(receiver, "buffered");
            const decoder = try scope.get(receiver, "decoder");
            const decode = try scope.get(decoder, "decode");
            const text = if (empty) try scope.call(decode, decoder, &.{}) else try scope.call(decode, decoder, &.{try scope.invoke(try scope.get(receiver, "chunk"), "subarray", &.{ c.JS_NewInt32(scope.engine.context, 0), count })});
            try scope.set(receiver, "buffered", try scope.concat(previous, text));
            if (empty) try scope.set(receiver, "ended", c.pi_js_bool(scope.engine.context, 1));
            return textPump(scope, saved);
        },
        .close => unreachable,
    }
}
fn advance(engine: *js.Engine, saved: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    return c.JS_DupValue(engine.context, step(&scope, saved, value, rejected, @enumFromInt(raw)) catch |err| try caught(&scope, saved, err, generation));
}
fn start(scope: *Scope, saved: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    const receiver = try scope.get(saved, "self");
    const bindings = try scope.get(saved, "bindings");
    switch (method) {
        .info => {
            try scope.put(saved, "infoPath", try scope.get(receiver, "path"));
            return h.wait(advance, scope, saved, try scope.invoke(try scope.get(receiver, "file"), "stat", &.{}), Stage.info);
        },
        .read => {
            try scope.put(saved, "offset", h.arg(args, 0));
            try scope.put(saved, "length", h.arg(args, 1));
            try scope.put(saved, "chunks", try scope.array());
            try scope.put(saved, "total", c.JS_NewInt32(scope.engine.context, 0));
            return binaryPump(scope, saved);
        },
        .scanLines => {
            const generation = scope.engine.native_allocation_generation;
            const scanner = makeScanner(scope, bindings, h.arg(args, 0)) catch |err| {
                if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
                const reason = c.JS_GetException(scope.engine.context);
                scope.engine.freeValue(reason);
                return errors.expected(scope, bindings, "invalid", "Invalid line range", try scope.get(receiver, "path"));
            };
            try scope.put(saved, "scanner", scanner);
            const chunk = try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{c.JS_NewInt32(scope.engine.context, 64 * 1024)}));
            try scope.put(saved, "chunk", chunk);
            try scope.put(saved, "position", c.JS_NewInt32(scope.engine.context, 0));
            return readCall(scope, saved, chunk, c.JS_NewInt32(scope.engine.context, 0), .scan);
        },
        .readLine => return textPump(scope, saved),
        .next => {
            try scope.put(saved, "maximum", h.arg(args, 0));
            try scope.put(saved, "entries", try scope.array());
            return directoryPump(scope, saved);
        },
        .close => unreachable,
    }
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, bindings: c.JSValue, kind: Kind, method: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try scope.object();
    try scope.put(saved, "self", receiver);
    try scope.put(saved, "bindings", bindings);
    if (method == .close) {
        if (scope.truthy(try scope.get(receiver, "closed"))) return c.pi_js_undefined();
        try scope.set(receiver, "closed", c.pi_js_bool(engine.context, 1));
        if (kind == .text) try scope.set(receiver, "buffered", try scope.text(""));
        const generation = engine.native_allocation_generation;
        const pending = closeCall(&scope, receiver, kind) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
            if (kind != .text) return err;
            engine.freeValue(c.JS_GetException(engine.context));
            return c.pi_js_undefined();
        };
        return c.JS_DupValue(engine.context, try h.wait(advance, &scope, saved, pending, Stage.close));
    }
    const context = h.arg(args, switch (method) {
        .read => 2,
        .scanLines, .next => 1,
        else => 0,
    });
    try scope.put(saved, "context", context);
    if (try abort(&scope, saved)) |aborted| return c.JS_DupValue(engine.context, aborted);
    if (scope.truthy(try scope.get(receiver, "closed"))) return c.JS_DupValue(engine.context, try errors.expected(&scope, bindings, "invalid", switch (kind) {
        .binary => "Binary reader is closed",
        .text => "Text line reader is closed",
        .directory => "Directory reader is closed",
    }, try scope.get(receiver, "path")));
    if (method == .read and (!try h.validInteger(&scope, h.arg(args, 0), false) or !try h.validInteger(&scope, h.arg(args, 1), false))) return c.JS_DupValue(engine.context, try errors.expected(&scope, bindings, "invalid", "Offset and length must be non-negative safe integers", try scope.get(receiver, "path")));
    if (method == .next and !try h.validInteger(&scope, h.arg(args, 0), true)) return c.JS_DupValue(engine.context, try errors.expected(&scope, bindings, "invalid", "maxEntries must be a positive safe integer", try scope.get(receiver, "path")));
    const generation = engine.native_allocation_generation;
    return c.JS_DupValue(engine.context, start(&scope, saved, args, method) catch |err| try caught(&scope, saved, err, generation));
}
fn makeScanner(scope: *Scope, bindings: c.JSValue, options: c.JSValue) !c.JSValue {
    const scanner_args = [_]c.JSValue{ try scope.get(options, "startLine"), try scope.get(options, "endLine") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "LineScanner"), 2, @constCast(&scanner_args))));
}
fn ignored(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn closeCall(scope: *Scope, receiver: c.JSValue, kind: Kind) !c.JSValue {
    const pending = try scope.invoke(try scope.get(receiver, if (kind == .directory) "dir" else "file"), "close", &.{});
    if (kind == .text) return pending;
    const catcher = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, ignored, "", 0)));
    return scope.invoke(pending, "catch", &.{catcher});
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const kind = kindValue(&scope, data[1]) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    const value = invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0], kind, @enumFromInt(raw)) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(value);
    return @import("native_durable.zig").resolvedPromise(engine, value) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn create(scope: *Scope, bindings: c.JSValue, kind: Kind) !c.JSValue {
    const engine = scope.engine;
    const prototype = try scope.object();
    const kind_value = c.JS_NewInt32(engine.context, @intFromEnum(kind));
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, switch (kind) {
        .binary => "NodeBinaryReader",
        .text => "NodeTextLineReader",
        .directory => "NodeDirReader",
    }, 2, prototype, construct, &.{ bindings, kind_value }));
    const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    var data = [_]c.JSValue{ bindings, kind_value };
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const selected = method == .close or (kind == .binary and (method == .info or method == .read or method == .scanLines)) or (kind == .text and method == .readLine) or (kind == .directory and method == .next);
        if (selected) {
            const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, switch (method) {
                .read => 3,
                .scanLines, .next => 2,
                else => 1,
            }, @intFromEnum(method), 2, &data)));
            if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) return js.capture(engine);
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        }
    }
    return c.JS_DupValue(engine.context, constructor);
}

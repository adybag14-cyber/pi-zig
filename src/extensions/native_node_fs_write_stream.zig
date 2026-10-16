//! Writable-derived WriteStream producer, preserving the captured Node24 IO
//! callback and close ordering. Default filesystem callbacks use genuine Env
//! workers; options.fs remains live, including partial-write retry callbacks.
const std = @import("std");
const em = @import("engine.zig"); const c = em.c;
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const fnc = @import("native_node_function.zig");
const core = @import("native_node_stream.zig");
const key = "pi-native:node-write-stream";
const Op = enum(c_int) { construct, opened, write, writev, written, io_done, destroy, io_close, flush_done, closed, close, open, pending, auto_close, set_auto_close, emit_open };
fn module(engine: *em.Engine) !c.JSValue { return engine.native_module_values.get(key) orelse error.NativeWriteStreamNotInstalled; }
fn record(scope: *Scope) !c.JSValue { return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null()))); }
fn symbolGet(scope: *Scope, stream: c.JSValue, name: [*:0]const u8) !c.JSValue { return scope.own(try js.getKey(scope.engine, stream, try scope.get(try module(scope.engine), name))); }
fn symbolSet(scope: *Scope, stream: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { try js.setKey(scope.engine, stream, try scope.get(try module(scope.engine), name), value); }
const FsCall = struct { receiver: c.JSValue, function: c.JSValue };
fn fsCall(scope: *Scope, stream: c.JSValue, name: [*:0]const u8) !FsCall {
    const fs = try symbolGet(scope, stream, "fsSymbol"); return .{ .receiver = fs, .function = try scope.get(fs, name) };
}
fn validateThis(scope: *Scope, stream: c.JSValue) !void {
    if (!try js.hasKey(scope.engine, stream, try scope.get(try module(scope.engine), "fsSymbol"))) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_THIS", "Value of this must be of type WriteStream");
}
fn callback(scope: *Scope, stream: c.JSValue, op: Op, data: c.JSValue) !c.JSValue { return scope.own(try fnc.createArrow(scope.engine, "", 1, dispatch, &.{ stream, c.JS_NewInt32(scope.engine.context, @intFromEnum(op)), data })); }
fn call(scope: *Scope, cb: c.JSValue, args: []const c.JSValue) !void { _ = try scope.call(cb, c.pi_js_undefined(), args); }
fn validateFunction(scope: *Scope, value: c.JSValue) !void { if (!c.JS_IsFunction(scope.engine.context, value)) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The filesystem operation must be of type function"); }
fn length(scope: *Scope, value: c.JSValue) !u64 { var result: u64 = 0; if (c.JS_ToIndex(scope.engine.context, &result, try scope.get(value, "length")) < 0) return js.capture(scope.engine); return result; }
fn closeFile(scope: *Scope, stream: c.JSValue, reason: c.JSValue, cb: c.JSValue) !void {
    if (!scope.truthy(try scope.get(stream, "fd"))) { try call(scope, cb, &.{reason}); return; }
    const data = try record(scope); try scope.put(data, "callback", cb); try scope.put(data, "reason", reason);
    if (scope.truthy(try scope.get(stream, "flush"))) {
        const fs = try fsCall(scope, stream, "fsync"); _ = try scope.call(fs.function, fs.receiver, &.{ try scope.get(stream, "fd"), try callback(scope, stream, .flush_done, data) });
    } else try closeWithoutFlush(scope, stream, data);
}
fn closeWithoutFlush(scope: *Scope, stream: c.JSValue, data: c.JSValue) !void {
    const fs = try fsCall(scope, stream, "close"); _ = try scope.call(fs.function, fs.receiver, &.{ try scope.get(stream, "fd"), try callback(scope, stream, .closed, data) });
    try scope.set(stream, "fd", c.pi_js_null());
}
fn writeAll(scope: *Scope, stream: c.JSValue, data: c.JSValue, vector: bool) !void {
    const fs = try fsCall(scope, stream, if (vector) "writev" else "write"); const done = try callback(scope, stream, .written, data);
    if (vector) _ = try scope.call(fs.function, fs.receiver, &.{ try scope.get(stream, "fd"), try scope.get(data, "buffers"), try scope.get(stream, "pos"), done })
    else _ = try scope.call(fs.function, fs.receiver, &.{ try scope.get(stream, "fd"), try scope.get(data, "buffers"), c.JS_NewInt32(scope.engine.context, 0), try scope.get(data, "size"), try scope.get(data, "position"), done });
}
fn constructor(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const owner = try module(engine); const ctor = try scope.get(owner, "constructor"); const instance = c.JS_IsInstanceOf(engine.context, receiver, ctor); if (instance < 0) return js.capture(engine);
    if (instance == 0) { var input = [_]c.JSValue{ core.arg(args, 0), core.arg(args, 1) }; return engine.checked(c.JS_CallConstructor(engine.context, ctor, input.len, &input)); }
    var supplied = core.arg(args, 1); if (core.nullish(supplied)) supplied = try scope.object() else if (c.JS_IsString(supplied)) { const options = try scope.object(); try scope.put(options, "encoding", supplied); supplied = options; } else if (!c.JS_IsObject(supplied)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The options argument must be of type object");
    const options = try scope.own(try js.spread(engine, supplied)); try scope.put(options, "decodeStrings", c.pi_js_bool(engine.context, 1));
    const selected_fs = try scope.get(options, "fs"); const fs = if (scope.truthy(selected_fs)) selected_fs else try scope.get(owner, "fs"); try symbolSet(&scope, receiver, "fsSymbol", fs);
    const fd = try scope.get(options, "fd");
    if (core.nullish(fd)) {
        try scope.set(receiver, "fd", c.pi_js_null()); try validateFunction(&scope, try scope.get(fs, "open"));
        const supplied_path = core.arg(args, 0); const url = @import("native_url.zig"); var path = supplied_path;
        if (url.isURL(engine, path)) { const bytes = try url.filePath(engine, path, @import("builtin").os.tag == .windows); defer engine.gpa.free(bytes); path = try scope.text(bytes); }
        if (!c.JS_IsString(path) and c.JS_GetTypedArrayType(path) < 0) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The path argument must be of type string or an instance of Buffer or URL");
        if (c.JS_IsString(path)) { const bytes = try engine.toString(path); defer engine.gpa.free(bytes); if (std.mem.indexOfScalar(u8, bytes, 0) != null) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_VALUE", "The path argument must not contain null bytes"); }
        try scope.set(receiver, "path", path); const flags = try scope.get(options, "flags"); const mode = try scope.get(options, "mode"); try scope.set(receiver, "flags", if (c.JS_IsUndefined(flags)) try scope.text("w") else flags); try scope.set(receiver, "mode", if (c.JS_IsUndefined(mode)) c.JS_NewInt32(engine.context, 0o666) else mode);
    } else {
        var number: f64 = 0; if (!c.JS_IsNumber(fd) or c.JS_ToFloat64(engine.context, &number, fd) < 0 or number < 0 or number > 2147483647 or number != @floor(number)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The options.fd argument must be a native file descriptor"); try scope.set(receiver, "fd", fd);
    }
    const auto_close = try scope.get(options, "autoClose"); try scope.put(options, "autoDestroy", if (c.JS_IsUndefined(auto_close)) c.pi_js_bool(engine.context, 1) else auto_close);
    if (!scope.truthy(try scope.get(fs, "write")) and !scope.truthy(try scope.get(fs, "writev"))) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The options.fs.write property must be of type function");
    if (scope.truthy(try scope.get(fs, "write"))) try validateFunction(&scope, try scope.get(fs, "write")); if (scope.truthy(try scope.get(fs, "writev"))) try validateFunction(&scope, try scope.get(fs, "writev"));
    if (scope.truthy(try scope.get(options, "autoDestroy"))) try validateFunction(&scope, try scope.get(fs, "close"));
    var flush = try scope.get(options, "flush"); if (core.nullish(flush)) flush = c.pi_js_bool(engine.context, 0) else { if (!c.JS_IsBool(flush)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The options.flush property must be of type boolean"); try validateFunction(&scope, try scope.get(fs, "fsync")); } try scope.set(receiver, "flush", flush);
    if (!scope.truthy(try scope.get(fs, "write"))) try scope.set(receiver, "_write", c.pi_js_null()); if (!scope.truthy(try scope.get(fs, "writev"))) try scope.set(receiver, "_writev", c.pi_js_null());
    const start = try scope.get(options, "start"); try scope.set(receiver, "start", start); try scope.set(receiver, "pos", c.pi_js_undefined()); try scope.set(receiver, "bytesWritten", c.JS_NewInt32(engine.context, 0));
    try symbolSet(&scope, receiver, "performingSymbol", c.pi_js_bool(engine.context, 0));
    if (!c.JS_IsUndefined(start)) { var number: f64 = 0; if (!c.JS_IsNumber(start) or c.JS_ToFloat64(engine.context, &number, start) < 0 or !std.math.isFinite(number) or number < 0 or number > 9007199254740991 or number != @floor(number)) return @import("node_events.zig").codedError(engine, "RangeError", "ERR_OUT_OF_RANGE", "The start argument is out of range"); try scope.set(receiver, "pos", start); }
    _ = try scope.call(try scope.get(try core.owner(engine), "Writable"), receiver, &.{options});
    const encoding = try scope.get(options, "encoding"); if (scope.truthy(encoding)) _ = try scope.invoke(receiver, "setDefaultEncoding", &.{encoding});
    return c.pi_js_undefined();
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); var integer: i32 = 0; if (c.JS_ToInt32(engine.context, &integer, roots[1]) < 0) return js.capture(engine); const op: Op = @enumFromInt(integer); const stream = if (core.nullish(roots[0])) receiver else roots[0]; const data = if (roots.len > 2) roots[2] else c.pi_js_undefined();
    switch (op) {
        .open => {}, // The original deprecated openWriteFs body is a noop.
        .construct => {
            const cb = core.arg(args, 0); if (c.JS_IsNumber(try scope.get(stream, "fd"))) { try call(&scope, cb, &.{}); return c.pi_js_undefined(); }
            if (!scope.equal(try scope.get(stream, "open"), try scope.get(try module(engine), "open"))) {
                const emit_data = try record(&scope); try scope.put(emit_data, "callback", cb); try scope.put(emit_data, "emit", try scope.get(stream, "emit"));
                const replacement = try scope.own(try fnc.create(engine, "", 0, dispatch, &.{ c.pi_js_null(), c.JS_NewInt32(engine.context, @intFromEnum(Op.emit_open)), emit_data })); try scope.set(stream, "emit", replacement); _ = try scope.invoke(stream, "open", &.{});
            } else { const fs = try fsCall(&scope, stream, "open"); _ = try scope.call(fs.function, fs.receiver, &.{ try scope.get(stream, "path"), try scope.get(stream, "flags"), try scope.get(stream, "mode"), try callback(&scope, stream, .opened, cb) }); }
        },
        .emit_open => {
            const event = core.arg(args, 0); const original = try scope.get(data, "emit");
            if (scope.equal(event, try scope.text("open"))) { try scope.set(stream, "emit", original); try call(&scope, try scope.get(data, "callback"), &.{}); _ = try scope.call(original, stream, args); }
            else if (scope.equal(event, try scope.text("error"))) { try scope.set(stream, "emit", original); try call(&scope, try scope.get(data, "callback"), &.{core.arg(args, 1)}); }
            else _ = try scope.call(original, stream, args);
        },
        .opened => {
            if (scope.truthy(core.arg(args, 0))) try call(&scope, data, &.{core.arg(args, 0)}) else { try scope.set(stream, "fd", core.arg(args, 1)); try call(&scope, data, &.{}); const emit = try scope.get(stream, "emit"); _ = try scope.call(emit, stream, &.{ try scope.text("open"), try scope.get(stream, "fd") }); try core.emit(&scope, stream, "ready", &.{}); }
        },
        .write, .writev => {
            const vector = op == .writev; if (!vector) try symbolSet(&scope, stream, "performingSymbol", c.pi_js_bool(engine.context, 1)); const job = try record(&scope); var size: u64 = 0; var buffers = core.arg(args, 0);
            if (vector) { const chunks = try scope.array(); const count = try length(&scope, buffers); for (0..@as(usize, @intCast(count))) |i| { const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, buffers, @intCast(i)))); const chunk = try scope.get(entry, "chunk"); size += try length(&scope, chunk); try scope.index(chunks, @intCast(i), chunk); } buffers = chunks; } else size = try length(&scope, buffers);
            if (vector) try symbolSet(&scope, stream, "performingSymbol", c.pi_js_bool(engine.context, 1));
            try scope.put(job, "buffers", buffers); try scope.put(job, "size", c.JS_NewInt64(engine.context, @intCast(size))); try scope.put(job, "position", try scope.get(stream, "pos")); try scope.put(job, "retries", c.JS_NewInt32(engine.context, 0)); try scope.put(job, "vector", c.pi_js_bool(engine.context, @intFromBool(vector))); try scope.put(job, "callback", try callback(&scope, stream, .io_done, core.arg(args, if (vector) 1 else 2)));
            try writeAll(&scope, stream, job, vector);
            if (!c.JS_IsUndefined(try scope.get(stream, "pos"))) { const pos = try scope.get(stream, "pos"); const increment = if (vector) c.JS_NewInt64(engine.context, @intCast(size)) else try scope.get(core.arg(args, 0), "length"); try scope.set(stream, "pos", try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, pos, increment)))); }
        },
        .written => {
            var reason = core.arg(args, 0); var written = core.arg(args, 1); const done = try scope.get(data, "callback");
            if (!core.nullish(reason) and scope.equal(try scope.get(reason, "code"), try scope.text("EAGAIN"))) { reason = c.pi_js_null(); written = c.JS_NewInt32(engine.context, 0); }
            if (scope.truthy(try scope.get(stream, "destroyed")) or scope.truthy(reason)) { const failure = if (scope.truthy(reason)) reason else try scope.own(try core.errorValue(&scope, "Error", "ERR_STREAM_DESTROYED", if (scope.truthy(try scope.get(data, "vector"))) "Cannot call writev after a stream was destroyed" else "Cannot call write after a stream was destroyed")); try call(&scope, done, &.{failure}); return c.pi_js_undefined(); }
            try scope.set(stream, "bytesWritten", try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, try scope.get(stream, "bytesWritten"), written))));
            var retries: u32 = 0; if (c.JS_ToUint32(engine.context, &retries, try scope.get(data, "retries")) < 0) return js.capture(engine);
            retries = if (scope.truthy(written)) 0 else retries + 1; const remaining = try scope.own(try @import("native_image_arithmetic.zig").binary(engine, .subtract, try scope.get(data, "size"), written)); try scope.put(data, "size", remaining); try scope.put(data, "retries", c.JS_NewUint32(engine.context, retries)); try scope.put(data, "position", try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 0, try scope.get(data, "position"), written))));
            if (retries > 5) { const failure_value = try scope.own(try @import("native_node_fs_system_error.zig").retryFailure(&scope, scope.truthy(try scope.get(data, "vector")))); try call(&scope, done, &.{failure_value}); }
            else if (scope.truthy(remaining)) {
                const vector = scope.truthy(try scope.get(data, "vector")); const supplied = core.arg(args, 2); var tail: c.JSValue = undefined;
                if (vector) { const buffer_type = try scope.get(engine.native_module_values.get("node:buffer").?, "Buffer"); const joined = try scope.invoke(buffer_type, "concat", &.{supplied}); tail = try scope.invoke(joined, "slice", &.{written}); const next = try scope.array(); try scope.index(next, 0, tail); tail = next; } else tail = try scope.invoke(supplied, "slice", &.{written});
                try scope.put(data, "buffers", tail); try writeAll(&scope, stream, data, vector);
            } else try call(&scope, done, &.{});
        },
        .io_done => {
            try symbolSet(&scope, stream, "performingSymbol", c.pi_js_bool(engine.context, 0)); const destroyed = scope.truthy(try scope.get(stream, "destroyed"));
            try call(&scope, data, &.{core.arg(args, 0)});
            if (destroyed) _ = try scope.invoke(stream, "emit", &.{ try scope.get(try module(engine), "ioDoneSymbol"), core.arg(args, 0) });
        },
        .destroy => {
            if (scope.truthy(try symbolGet(&scope, stream, "performingSymbol"))) { const pending = try record(&scope); try scope.put(pending, "reason", core.arg(args, 0)); try scope.put(pending, "callback", core.arg(args, 1)); _ = try scope.invoke(stream, "once", &.{ try scope.get(try module(engine), "ioDoneSymbol"), try callback(&scope, stream, .io_close, pending) }); }
            else try closeFile(&scope, stream, core.arg(args, 0), core.arg(args, 1));
        },
        .io_close => { const original = try scope.get(data, "reason"); try closeFile(&scope, stream, if (scope.truthy(original)) original else core.arg(args, 0), try scope.get(data, "callback")); },
        .flush_done => { const original = try scope.get(data, "reason"); if (!scope.truthy(original)) try scope.put(data, "reason", core.arg(args, 0)); try closeWithoutFlush(&scope, stream, data); },
        .closed => { const reason = core.arg(args, 0); try call(&scope, try scope.get(data, "callback"), &.{if (scope.truthy(reason)) reason else try scope.get(data, "reason")}); },
        .close => {
            const cb = core.arg(args, 0); if (scope.truthy(cb)) { if (scope.truthy(try scope.get(stream, "closed"))) { try core.tick(&scope, cb, &.{}); return c.pi_js_undefined(); } _ = try scope.invoke(stream, "on", &.{ try scope.text("close"), cb }); }
            if (!scope.truthy(try scope.get(stream, "autoClose"))) _ = try scope.invoke(stream, "on", &.{ try scope.text("finish"), try scope.get(stream, "destroy") }); _ = try scope.invoke(stream, "end", &.{});
        },
        .pending => return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsNull(try scope.get(stream, "fd")))),
        .auto_close => { try validateThis(&scope, stream); return c.JS_DupValue(engine.context, try scope.get(try scope.get(stream, "_writableState"), "autoDestroy")); },
        .set_auto_close => { try validateThis(&scope, stream); try scope.set(try scope.get(stream, "_writableState"), "autoDestroy", core.arg(args, 0)); },
    }
    return c.pi_js_undefined();
}
fn createWriteStream(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { const ctor = try js.get(engine, try module(engine), "constructor"); defer engine.freeValue(ctor); var input = [_]c.JSValue{ core.arg(args, 0), core.arg(args, 1) }; return engine.checked(c.JS_CallConstructor(engine.context, ctor, input.len, &input)); }
pub fn install(engine: *em.Engine, fs: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); _ = try core.owner(engine); try @import("native_node_fs_write_ops.zig").install(engine, fs);
    try @import("native_node_fs_system_error.zig").install(engine);
    if (!engine.native_module_values.contains(key)) {
        const owner = try record(&scope); try scope.put(owner, "fs", fs); inline for (.{ "fsSymbol", "performingSymbol" }, .{ "kFs", "kIsPerformingIO" }) |name, label| try scope.put(owner, name, try scope.call(try scope.global("Symbol"), c.pi_js_undefined(), &.{try scope.text(label)}));
        try scope.put(owner, "ioDoneSymbol", try scope.call(try scope.global("Symbol"), c.pi_js_undefined(), &.{try scope.text("kIoDone")}));
        const ctor = try scope.own(try fnc.create(engine, "WriteStream", 2, constructor, &.{})); try scope.put(owner, "constructor", ctor); const prototype = try scope.get(ctor, "prototype"); const parent = try scope.get(try core.owner(engine), "Writable"); if (c.JS_SetPrototype(engine.context, prototype, try scope.get(parent, "prototype")) < 0 or c.JS_SetPrototype(engine.context, ctor, parent) < 0) return js.capture(engine);
        inline for (.{ "_construct", "_write", "_writev", "_destroy", "close", "open" }, .{ Op.construct, Op.write, Op.writev, Op.destroy, Op.close, Op.open }, .{ 1, 3, 2, 2, 1, 0 }) |name, op, arity| try scope.put(prototype, name, try scope.own(try fnc.create(engine, name, arity, dispatch, &.{ c.pi_js_null(), c.JS_NewInt32(engine.context, @intFromEnum(op)) })));
        try scope.put(owner, "open", try scope.get(prototype, "open")); try scope.put(prototype, "destroySoon", try scope.get(prototype, "end"));
        inline for (.{ "pending", "autoClose" }, .{ Op.pending, Op.auto_close }) |name, op| { const atom = c.JS_NewAtom(engine.context, name); if (atom == c.JS_ATOM_NULL) return js.capture(engine); defer c.JS_FreeAtom(engine.context, atom); const get = try scope.own(try fnc.createMethod(engine, "get", 0, dispatch, &.{ c.pi_js_null(), c.JS_NewInt32(engine.context, @intFromEnum(op)) })); const set = if (op == .auto_close) try scope.own(try fnc.createMethod(engine, "set", 1, dispatch, &.{ c.pi_js_null(), c.JS_NewInt32(engine.context, @intFromEnum(Op.set_auto_close)) })) else c.pi_js_undefined(); if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, get), c.JS_DupValue(engine.context, set), if (op == .pending) c.JS_PROP_CONFIGURABLE else 0) < 0) return js.capture(engine); }
        try scope.put(owner, "createWriteStream", try scope.own(try fnc.create(engine, "createWriteStream", 2, createWriteStream, &.{}))); try engine.registerValueModule(key, owner);
    }
    const owner = try module(engine); try scope.put(fs, "WriteStream", try scope.get(owner, "constructor")); try scope.put(fs, "createWriteStream", try scope.get(owner, "createWriteStream"));
}

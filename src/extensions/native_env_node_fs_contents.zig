//! Node 24 readFile/writeFile phase ordering around retained FileHandles.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const c = js.c;
const Scope = h.Scope;
const Stage = enum(c_int) { opened, stat, read, written, closed };
fn number(scope: *Scope, value: c.JSValue) !usize {
    var raw: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &raw, value) < 0) return js.capture(scope.engine);
    return @intFromFloat(raw);
}
fn integer(scope: *Scope, value: usize) c.JSValue {
    return c.JS_NewFloat64(scope.engine.context, @floatFromInt(value));
}
fn abort(scope: *Scope, saved: c.JSValue) !?c.JSValue {
    const signal = try scope.get(saved, "signal");
    if (h.nullish(signal) or !scope.truthy(try scope.get(signal, "aborted"))) return null;
    const result = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text("The operation was aborted")}));
    if (c.JS_DefinePropertyValueStr(scope.engine.context, result, "name", c.JS_DupValue(scope.engine.context, try scope.text("AbortError")), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(scope.engine);
    try scope.put(result, "code", try scope.text("ABORT_ERR"));
    if (c.JS_DefinePropertyValueStr(scope.engine.context, result, "cause", c.JS_DupValue(scope.engine.context, try scope.get(signal, "reason")), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(scope.engine);
    return result;
}
fn wait(scope: *Scope, saved: c.JSValue, pending: c.JSValue, stage: Stage) !c.JSValue {
    return h.wait(advance, scope, saved, pending, stage);
}
fn bufferConstructor(scope: *Scope, saved: c.JSValue) !c.JSValue {
    return if (scope.truthy(try scope.get(saved, "retained"))) scope.get(try scope.get(saved, "bindings"), "fileHandleBuffer") else scope.global("Buffer");
}
fn finish(scope: *Scope, saved: c.JSValue, value: c.JSValue, rejected: bool) !c.JSValue {
    // A borrowed FileHandle survives both successful and rejected content
    // operations. Its enclosing FileHandle fsCall owns the operation reference.
    if (scope.truthy(try scope.get(saved, "retained"))) {
        if (rejected) return h.throw(scope, value);
        return value;
    }
    try scope.put(saved, "result", value);
    try scope.put(saved, "rejected", c.pi_js_bool(scope.engine.context, @intFromBool(rejected)));
    return wait(scope, saved, try scope.invoke(try scope.get(saved, "file"), "close", &.{}), .closed);
}
fn readNext(scope: *Scope, saved: c.JSValue) !c.JSValue {
    if (try abort(scope, saved)) |reason| return finish(scope, saved, reason, true);
    const size = try number(scope, try scope.get(saved, "size"));
    const total = try number(scope, try scope.get(saved, "total"));
    const chunked = scope.truthy(try scope.get(saved, "chunked"));
    const count = if (chunked) @min(size - total, 512 * 1024) else try number(scope, try scope.get(try scope.get(saved, "buffer"), "length"));
    return wait(scope, saved, try scope.invoke(try scope.get(saved, "file"), "read", &.{ try scope.get(saved, "buffer"), integer(scope, if (chunked) total else 0), integer(scope, count), c.pi_js_null() }), .read);
}
fn writeNext(scope: *Scope, saved: c.JSValue) !c.JSValue {
    const remaining = try scope.get(saved, "buffer");
    const count = try number(scope, try scope.get(remaining, "length"));
    if (count == 0) return finish(scope, saved, c.pi_js_undefined(), false);
    if (try abort(scope, saved)) |reason| return finish(scope, saved, reason, true);
    return wait(scope, saved, try scope.invoke(try scope.get(saved, "file"), "write", &.{ remaining, integer(scope, 0), integer(scope, @min(count, 512 * 1024)), c.pi_js_null() }), .written);
}
fn step(scope: *Scope, saved: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !c.JSValue {
    if (stage == .closed) {
        if (rejected) return h.throw(scope, value);
        const result = try scope.get(saved, "result");
        if (scope.truthy(try scope.get(saved, "rejected"))) return h.throw(scope, result);
        return result;
    }
    if (rejected) return if (stage == .opened) h.throw(scope, value) else finish(scope, saved, value, true);
    switch (stage) {
        .opened => {
            try scope.put(saved, "file", value);
            if (try abort(scope, saved)) |reason| return finish(scope, saved, reason, true);
            if (scope.truthy(try scope.get(saved, "write"))) return writeNext(scope, saved);
            return wait(scope, saved, try scope.invoke(value, "stat", &.{}), .stat);
        },
        .stat => {
            if (try abort(scope, saved)) |reason| return finish(scope, saved, reason, true);
            const size = if (scope.truthy(try scope.invoke(value, "isFile", &.{}))) try number(scope, try scope.get(value, "size")) else 0;
            if (size > std.math.maxInt(i32)) {
                const reason = try scope.own(try js.builtin(scope.engine, "RangeError", &.{try scope.concat(try scope.concat(try scope.text("File size ("), try scope.stringify(integer(scope, size))), try scope.text(") is greater than 2 GiB"))}));
                try scope.put(reason, "code", try scope.text("ERR_FS_FILE_TOO_LARGE"));
                return finish(scope, saved, reason, true);
            }
            const encoded = scope.truthy(try scope.get(saved, "encoding"));
            const length = if (size == 0) 64 * 1024 else if (encoded) @min(size, 512 * 1024) else size;
            try scope.put(saved, "size", integer(scope, size));
            try scope.put(saved, "total", integer(scope, 0));
            try scope.put(saved, "chunked", c.pi_js_bool(scope.engine.context, @intFromBool(length > 512 * 1024)));
            try scope.put(saved, "buffer", try scope.invoke(try bufferConstructor(scope, saved), "allocUnsafeSlow", &.{integer(scope, length)}));
            try scope.put(saved, "chunks", try scope.array());
            try scope.put(saved, "decoded", try scope.text(""));
            return readNext(scope, saved);
        },
        .written => {
            const count = try scope.get(value, "bytesWritten");
            try scope.put(saved, "buffer", try scope.invoke(try scope.get(saved, "buffer"), "subarray", &.{count}));
            return writeNext(scope, saved);
        },
        .read => {
            const count = try number(scope, try scope.get(value, "bytesRead"));
            const previous = try number(scope, try scope.get(saved, "total"));
            const total = previous + count;
            const size = try number(scope, try scope.get(saved, "size"));
            const buffer = try scope.get(saved, "buffer");
            const length = try number(scope, try scope.get(buffer, "length"));
            const chunked = scope.truthy(try scope.get(saved, "chunked"));
            try scope.put(saved, "total", integer(scope, total));
            const done = count == 0 or total == size or (count != length and !chunked and size != 0);
            const encoded = scope.truthy(try scope.get(saved, "encoding"));
            const chunks = try scope.get(saved, "chunks");
            if (done) {
                const checked = if (chunked) total else count;
                const result = if (checked == length) buffer else try scope.invoke(buffer, "subarray", &.{ integer(scope, 0), integer(scope, checked) });
                if (encoded) return finish(scope, saved, if (previous == 0) try scope.invoke(result, "toString", &.{try scope.get(saved, "encoding")}) else try scope.concat(try scope.get(saved, "decoded"), try @import("native_env_node_fs_decoder.zig").decode(scope, saved, result, true)), false);
                if (size == 0 and previous != 0) {
                    _ = try scope.invoke(chunks, "push", &.{result});
                    return finish(scope, saved, try scope.invoke(try bufferConstructor(scope, saved), "concat", &.{ chunks, integer(scope, total) }), false);
                }
                return finish(scope, saved, result, false);
            }
            const read_buffer = if (count == length) buffer else try scope.invoke(buffer, "subarray", &.{ integer(scope, 0), integer(scope, count) });
            if (encoded) {
                try scope.put(saved, "decoded", try scope.concat(try scope.get(saved, "decoded"), try @import("native_env_node_fs_decoder.zig").decode(scope, saved, read_buffer, false)));
            } else if (size == 0) {
                _ = try scope.invoke(chunks, "push", &.{read_buffer});
                try scope.put(saved, "buffer", try scope.invoke(try bufferConstructor(scope, saved), "allocUnsafeSlow", &.{integer(scope, 64 * 1024)}));
            }
            return readNext(scope, saved);
        },
        .closed => unreachable,
    }
}
fn advance(engine: *js.Engine, saved: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try step(&scope, saved, value, rejected, @enumFromInt(raw)));
}
pub fn invoke(engine: *js.Engine, bindings: c.JSValue, args: []const c.JSValue, write: bool, append: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try scope.object();
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "write", c.pi_js_bool(engine.context, @intFromBool(write)));
    const options = h.arg(args, if (write) 2 else 1);
    try scope.put(saved, "signal", try h.optional(&scope, options, "signal"));
    try scope.put(saved, "encoding", try h.optional(&scope, options, "encoding"));
    if (write) {
        const content = h.arg(args, 1);
        try scope.put(saved, "buffer", if (c.JS_IsString(content)) try scope.invoke(try scope.global("Buffer"), "from", &.{content}) else content);
    }
    if (try abort(&scope, saved)) |reason| return h.throw(&scope, reason);
    return c.JS_DupValue(engine.context, try wait(&scope, saved, try scope.invoke(try scope.get(bindings, "fs"), "open", &.{ h.arg(args, 0), try scope.text(if (append) "a" else if (write) "w" else "r") }), .opened));
}

/// Internal content engine for an already owned descriptor. Options and buffer
/// arguments have been normalized by the public frontend before admission.
/// This does not install or emulate a partial public FileHandle class.
pub fn readRetained(engine: *js.Engine, bindings: c.JSValue, file: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try scope.object();
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "retained", c.pi_js_bool(engine.context, 1));
    try scope.put(saved, "file", file);
    try scope.put(saved, "write", c.pi_js_bool(engine.context, 0));
    try scope.put(saved, "signal", try h.optional(&scope, options, "signal"));
    try scope.put(saved, "encoding", try h.optional(&scope, options, "encoding"));
    if (try abort(&scope, saved)) |reason| return h.throw(&scope, reason);
    return c.JS_DupValue(engine.context, try wait(&scope, saved, try scope.invoke(file, "stat", &.{}), .stat));
}
pub fn writeRetained(engine: *js.Engine, bindings: c.JSValue, file: c.JSValue, bytes: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try scope.object();
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "retained", c.pi_js_bool(engine.context, 1));
    try scope.put(saved, "file", file);
    try scope.put(saved, "write", c.pi_js_bool(engine.context, 1));
    try scope.put(saved, "signal", signal);
    try scope.put(saved, "buffer", bytes);
    if (try abort(&scope, saved)) |reason| return h.throw(&scope, reason);
    return c.JS_DupValue(engine.context, try writeNext(&scope, saved));
}

//! Owner-thread Node classic streams. Separate readable/writable state and
//! callback completion implement real flow control; these are not Web aliases.
//! The production producer supplies actual read/write/final/destroy hooks.
pub const std = @import("std");
pub const em = @import("engine.zig");
pub const js = @import("native_js_values.zig");
pub const Scope = @import("native_models_stream_scope.zig").Scope;
pub const c = em.c;
const fnc = @import("native_node_function.zig");
const events = @import("node_events.zig");
const buffer = @import("node_buffer.zig");
const decoder = @import("native_node_string_decoder.zig");
const encoding = @import("binary_encoding.zig");
const utf16 = @import("native_utf16.zig");
pub const module_key = "pi-native:node-classic-streams";
pub const Side = enum { readable, writable };
const Kind = enum(c_int) { stream, readable, writable, duplex, transform, passthrough };
pub const Item = struct {
    chunk: c.JSValue,
    encoding: c.JSValue,
    callback: c.JSValue,
    size: usize,
    fn free(self: Item, engine: *em.Engine) void { engine.freeValue(self.chunk); engine.freeValue(self.encoding); engine.freeValue(self.callback); }
};
pub const State = struct {
    engine: *em.Engine,
    side: Side,
    owner: c.JSValue,
    error_value: c.JSValue,
    decoder_value: c.JSValue,
    default_encoding: c.JSValue,
    text_encoding: c.JSValue,
    after_info: c.JSValue,
    transform_callback: c.JSValue,
    destroy_record: c.JSValue,
    queue: std.ArrayList(Item) = .empty,
    end_callbacks: std.ArrayList(c.JSValue) = .empty,
    pipes: std.ArrayList(c.JSValue) = .empty,
    await_drain_writers: usize = 0,
    current: ?Item = null,
    length: usize = 0,
    high_water_mark: usize = 65536,
    object_mode: bool = false,
    decode_strings: bool = true,
    enabled: bool = true,
    auto_destroy: bool = true,
    emit_close: bool = true,
    destroyed: bool = false,
    closed: bool = false,
    close_emitted: bool = false,
    error_emitted: bool = false,
    constructed: bool = true,
    sync: bool = true,
    ended: bool = false,
    end_emitted: bool = false,
    end_scheduled: bool = false,
    flowing: ?bool = null,
    paused: bool = false,
    reading: bool = false,
    readable_listening: bool = false,
    need_readable: bool = false,
    emitted_readable: bool = false,
    resume_scheduled: bool = false,
    reading_more: bool = false,
    data_emitted: bool = false,
    data_listening: bool = false,
    writing: bool = false,
    processing: bool = false,
    corked: usize = 0,
    ending: bool = false,
    finished: bool = false,
    prefinished: bool = false,
    final_called: bool = false,
    finish_scheduled: bool = false,
    need_drain: bool = false,
    pending_callbacks: usize = 0,
    after_pending: bool = false,
    write_generation: u64 = 0,
    expect_callback: bool = false,
    fn set(self: *State, slot: *c.JSValue, value: c.JSValue) void {
        const kept = c.JS_DupValue(self.engine.context, value);
        self.engine.freeValue(slot.*);
        slot.* = kept;
    }
};
const Op = enum(c_int) {
    push, unshift, read, resume_stream, pause_stream, is_paused, on, remove_listener, remove_all,
    set_encoding, write, end, cork, uncork, set_default_encoding, destroy,
    default_read, default_write, default_destroy, default_transform, cannot_pipe, transform_read, transform_write, transform_final, pass_transform,
    resume_tick, read_more_tick, readable_tick, read_zero_tick, update_listening_tick, end_tick, half_end_tick,
    write_done, after_write_tick, final_done, finish_tick, destroy_done, close_tick,
    construct_tick, construct_callback, construct_done,
};
fn finalize(rt: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const stream_state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ stream_state.owner, stream_state.error_value, stream_state.decoder_value, stream_state.default_encoding, stream_state.text_encoding, stream_state.after_info, stream_state.transform_callback, stream_state.destroy_record }) |root| c.JS_FreeValueRT(rt, root);
    for (stream_state.queue.items) |item| { c.JS_FreeValueRT(rt, item.chunk); c.JS_FreeValueRT(rt, item.encoding); c.JS_FreeValueRT(rt, item.callback); }
    if (stream_state.current) |item| { c.JS_FreeValueRT(rt, item.chunk); c.JS_FreeValueRT(rt, item.encoding); c.JS_FreeValueRT(rt, item.callback); }
    for (stream_state.end_callbacks.items) |root| c.JS_FreeValueRT(rt, root);
    for (stream_state.pipes.items) |root| c.JS_FreeValueRT(rt, root);
    stream_state.queue.deinit(stream_state.engine.gpa); stream_state.end_callbacks.deinit(stream_state.engine.gpa); stream_state.pipes.deinit(stream_state.engine.gpa);
    stream_state.engine.gpa.destroy(stream_state);
}
fn mark(rt: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const stream_state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ stream_state.owner, stream_state.error_value, stream_state.decoder_value, stream_state.default_encoding, stream_state.text_encoding, stream_state.after_info, stream_state.transform_callback, stream_state.destroy_record }) |root| c.JS_MarkValue(rt, root, visit);
    for (stream_state.queue.items) |item| { c.JS_MarkValue(rt, item.chunk, visit); c.JS_MarkValue(rt, item.encoding, visit); c.JS_MarkValue(rt, item.callback, visit); }
    if (stream_state.current) |item| { c.JS_MarkValue(rt, item.chunk, visit); c.JS_MarkValue(rt, item.encoding, visit); c.JS_MarkValue(rt, item.callback, visit); }
    for (stream_state.end_callbacks.items) |root| c.JS_MarkValue(rt, root, visit);
    for (stream_state.pipes.items) |root| c.JS_MarkValue(rt, root, visit);
}
pub fn owner(engine: *em.Engine) !c.JSValue { return engine.native_module_values.get(module_key) orelse error.NativeNodeStreamsNotInstalled; }
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
pub fn optional(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue { return if (nullish(object)) c.pi_js_undefined() else scope.get(object, name); }
fn classId(scope: *Scope, side: Side) !u32 {
    var id: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &id, try scope.get(try owner(scope.engine), if (side == .readable) "readStateClass" else "writeStateClass")) < 0) return js.capture(scope.engine);
    return id;
}
pub fn state(scope: *Scope, stream: c.JSValue, side: Side) !?*State {
    const value = try scope.get(stream, if (side == .readable) "_readableState" else "_writableState");
    if (nullish(value)) return null;
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, try classId(scope, side)) orelse return error.RequiredRealNativeNodeStreamState));
}
fn required(scope: *Scope, stream: c.JSValue, side: Side) !*State { return (try state(scope, stream, side)) orelse error.RequiredRealNativeNodeStreamState; }
pub fn errorValue(scope: *Scope, kind: [*:0]const u8, code: []const u8, message: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(message)};
    const value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(try owner(scope.engine), kind), args.len, &args)));
    try scope.put(value, "code", try scope.text(code));
    return c.JS_DupValue(scope.engine.context, value);
}
pub fn emit(scope: *Scope, stream: c.JSValue, name: []const u8, args: []const c.JSValue) !void {
    var values: std.ArrayList(c.JSValue) = .empty;
    defer values.deinit(scope.engine.gpa);
    try values.append(scope.engine.gpa, try scope.text(name));
    try values.appendSlice(scope.engine.gpa, args);
    _ = try scope.invoke(stream, "emit", values.items);
}
pub fn tick(scope: *Scope, callback_fn: c.JSValue, args: []const c.JSValue) !void {
    const process = try scope.get(try owner(scope.engine), "process");
    var values: std.ArrayList(c.JSValue) = .empty;
    defer values.deinit(scope.engine.gpa);
    try values.append(scope.engine.gpa, callback_fn); try values.appendSlice(scope.engine.gpa, args);
    _ = try scope.invoke(process, "nextTick", values.items);
}
fn callback(scope: *Scope, stream: c.JSValue, op: Op, extra: c.JSValue) !c.JSValue {
    return scope.own(try fnc.createArrow(scope.engine, "", 1, dispatch, &.{ stream, c.JS_NewInt32(scope.engine.context, @intFromEnum(op)), extra }));
}
fn queueTick(scope: *Scope, stream: c.JSValue, op: Op, extra: c.JSValue) !void { try tick(scope, try callback(scope, stream, op, extra), &.{}); }
fn failed(scope: *Scope, stream: c.JSValue, reason: c.JSValue, sync: bool) !void {
    const r = try state(scope, stream, .readable); const w = try state(scope, stream, .writable);
    if ((r != null and r.?.destroyed) or (w != null and w.?.destroyed)) return;
    if ((r != null and r.?.auto_destroy) or (w != null and w.?.auto_destroy)) { _ = try scope.invoke(stream, "destroy", &.{reason}); return; }
    if (r) |s| if (nullish(s.error_value)) { s.set(&s.error_value, reason); };
    if (w) |s| if (nullish(s.error_value)) { s.set(&s.error_value, reason); };
    if (scope.truthy(reason)) {
        if (sync) try queueTick(scope, stream, .close_tick, reason) else {
            if (r) |s| s.error_emitted = true; if (w) |s| s.error_emitted = true;
            try emit(scope, stream, "error", &.{reason});
        }
    }
}
fn byteBuffer(scope: *Scope, value: c.JSValue, enc: c.JSValue) !c.JSValue {
    if (try buffer.isBuffer(scope.engine, value)) return scope.own(c.JS_DupValue(scope.engine.context, value));
    if (c.JS_IsString(value)) {
        const text = try scope.engine.toString(value); defer scope.engine.gpa.free(text);
        const name = try scope.engine.toString(enc); defer scope.engine.gpa.free(name);
        const parsed = encoding.parse(name) orelse return events.codedError(scope.engine, "TypeError", "ERR_UNKNOWN_ENCODING", "Unknown encoding");
        const data = try encoding.encode(scope.engine.gpa, text, parsed); defer scope.engine.gpa.free(data);
        return scope.own(try buffer.fromBytes(scope.engine, data));
    }
    if (c.JS_GetTypedArrayType(value) < 0 and !c.JS_IsDataView(value)) return events.codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"chunk\" argument must be of type string or an instance of Buffer, TypedArray, or DataView");
    var offset: usize = 0; var length: usize = 0; var width: usize = 0;
    const backing = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, value, &offset, &length, &width)));
    return scope.own(try buffer.fromBacking(scope.engine, backing, offset, length));
}
fn size(scope: *Scope, value: c.JSValue) !usize {
    var result: u64 = 0;
    if (c.JS_ToIndex(scope.engine.context, &result, try scope.get(value, "length")) < 0) return js.capture(scope.engine);
    return std.math.cast(usize, result) orelse error.NativeNodeStreamLength;
}
fn addItem(s: *State, chunk: c.JSValue, enc: c.JSValue, cb: c.JSValue, length: usize, front: bool) !void {
    const item: Item = .{ .chunk = c.JS_DupValue(s.engine.context, chunk), .encoding = c.JS_DupValue(s.engine.context, enc), .callback = c.JS_DupValue(s.engine.context, cb), .size = length };
    errdefer item.free(s.engine);
    if (front) try s.queue.insert(s.engine.gpa, 0, item) else try s.queue.append(s.engine.gpa, item);
    s.length += length;
}
fn canPush(s: *State) bool { return !s.ended and (s.length < s.high_water_mark or s.length == 0); }
fn readableEvent(scope: *Scope, stream: c.JSValue, s: *State) !void {
    s.need_readable = false;
    if (!s.emitted_readable) { s.emitted_readable = true; try queueTick(scope, stream, .readable_tick, c.pi_js_undefined()); }
}
fn maybeReadMore(scope: *Scope, stream: c.JSValue, s: *State) !void {
    if (!s.reading_more and !s.reading and s.constructed) { s.reading_more = true; try queueTick(scope, stream, .read_more_tick, c.pi_js_undefined()); }
}
fn emitReadableNow(scope: *Scope, stream: c.JSValue, s: *State) !void {
    if (!s.destroyed and nullish(s.error_value) and (s.length != 0 or s.ended)) { try emit(scope, stream, "readable", &.{}); s.emitted_readable = false; }
    if (s.flowing != true and !s.ended and s.length <= s.high_water_mark) s.need_readable = true;
    try flow(scope, stream);
}
fn endReadable(scope: *Scope, stream: c.JSValue, s: *State) !void {
    if (!s.end_emitted and !s.end_scheduled and s.ended and s.length == 0) { s.end_scheduled = true; try queueTick(scope, stream, .end_tick, c.pi_js_undefined()); }
}
fn push(scope: *Scope, stream: c.JSValue, value: c.JSValue, enc: c.JSValue, front: bool) !bool {
    const s = try required(scope, stream, .readable);
    if (c.JS_IsNull(value)) {
        if (!s.ended) {
            s.reading = false;
            if (!nullish(s.decoder_value)) {
                const tail = try scope.invoke(s.decoder_value, "end", &.{});
                const length = try size(scope, tail);
                if (length != 0) try addItem(s, tail, c.pi_js_undefined(), c.pi_js_undefined(), if (s.object_mode) 1 else length, false);
            }
            s.ended = true;
            if (s.sync) try readableEvent(scope, stream, s) else { s.need_readable = false; s.emitted_readable = true; try emitReadableNow(scope, stream, s); }
        }
        return false;
    }
    if (s.destroyed or !nullish(s.error_value)) return false;
    if ((!front and s.ended) or (front and s.end_emitted)) {
        const reason = try scope.own(try errorValue(scope, "Error", if (front) "ERR_STREAM_UNSHIFT_AFTER_END_EVENT" else "ERR_STREAM_PUSH_AFTER_EOF", if (front) "stream.unshift() after end event" else "stream.push() after EOF"));
        try failed(scope, stream, reason, false); return false;
    }
    var chunk = value;
    var converted = false;
    if (!s.object_mode) {
        if (c.JS_IsUndefined(value)) { s.reading = false; try maybeReadMore(scope, stream, s); return canPush(s); }
        if (!c.JS_IsString(value) and !try buffer.isBuffer(scope.engine, value) and c.JS_GetTypedArrayType(value) < 0 and !c.JS_IsDataView(value)) {
            const reason = try scope.own(try errorValue(scope, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"chunk\" argument must be of type string or an instance of Buffer, TypedArray, or DataView"));
            try failed(scope, stream, reason, false); return false;
        }
        const selected = if (scope.truthy(enc)) enc else s.default_encoding;
        if (!c.JS_IsString(value) or !c.JS_IsStrictEqual(scope.engine.context, selected, s.text_encoding)) { chunk = try byteBuffer(scope, value, selected); converted = true; }
    }
    if (!front) s.reading = false;
    if (!nullish(s.decoder_value) and (converted or !c.JS_IsString(chunk))) chunk = try scope.invoke(s.decoder_value, "write", &.{chunk});
    const length = if (s.object_mode) @as(usize, 1) else try size(scope, chunk);
    if (length == 0 and !s.object_mode) { try maybeReadMore(scope, stream, s); return canPush(s); }
    if (!front and s.flowing == true and s.data_listening and s.length == 0 and !s.sync) {
        s.await_drain_writers = 0;
        for (s.pipes.items) |record| try scope.set(record, "waiting", c.pi_js_bool(scope.engine.context, 0));
        s.data_emitted = true; try emit(scope, stream, "data", &.{chunk});
    } else { try addItem(s, chunk, c.pi_js_undefined(), c.pi_js_undefined(), length, front); if (s.need_readable) try readableEvent(scope, stream, s); }
    try maybeReadMore(scope, stream, s);
    return canPush(s);
}
fn consume(scope: *Scope, s: *State, count: usize) !c.JSValue {
    if (s.object_mode) { const item = s.queue.orderedRemove(0); defer item.free(scope.engine); s.length -= 1; return c.JS_DupValue(scope.engine.context, item.chunk); }
    if (s.queue.items[0].size == count) { const item = s.queue.orderedRemove(0); defer item.free(scope.engine); s.length -= count; return c.JS_DupValue(scope.engine.context, item.chunk); }
    var output: std.ArrayList(u8) = .empty; defer output.deinit(scope.engine.gpa);
    var text = try scope.text("");
    var remaining = count;
    while (remaining > 0) {
        var item = s.queue.orderedRemove(0); defer item.free(scope.engine);
        const take = @min(remaining, item.size);
        if (!nullish(s.decoder_value)) {
            const units = try utf16.unitsAlloc(scope.engine, item.chunk); defer scope.engine.gpa.free(units);
            const part = try scope.own(try utf16.string(scope.engine, units[0..take]));
            text = try scope.concat(text, part);
            if (take < item.size) { const tail = try scope.own(try utf16.string(scope.engine, units[take..])); try addItem(s, tail, item.encoding, item.callback, item.size - take, true); s.length -= item.size - take; }
        } else {
            const data = try decoder.bytes(scope, item.chunk);
            try output.appendSlice(scope.engine.gpa, data[0..take]);
            if (take < item.size) {
                var offset: usize = 0; var length: usize = 0; var width: usize = 0;
                const backing = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, item.chunk, &offset, &length, &width)));
                const tail = try scope.own(try buffer.fromBacking(scope.engine, backing, offset + take, length - take));
                try addItem(s, tail, item.encoding, item.callback, item.size - take, true); s.length -= item.size - take;
            }
        }
        s.length -= take; remaining -= take;
    }
    return if (!nullish(s.decoder_value)) c.JS_DupValue(scope.engine.context, text) else buffer.fromBytes(scope.engine, output.items);
}
fn read(scope: *Scope, stream: c.JSValue, requested: c.JSValue) !c.JSValue {
    const s = try required(scope, stream, .readable);
    const parsed = try scope.call(try scope.get(try owner(scope.engine), "numberParseInt"), c.pi_js_undefined(), &.{ requested, c.JS_NewInt32(scope.engine.context, 10) });
    var number: f64 = 0; if (c.JS_ToFloat64(scope.engine.context, &number, parsed) < 0) return js.capture(scope.engine);
    const unspecified = std.math.isNan(number);
    if (!unspecified and number > 1024 * 1024 * 1024) return events.codedError(scope.engine, "RangeError", "ERR_OUT_OF_RANGE", "The value of n is out of range");
    var count: usize = if (unspecified) (if (s.flowing == true and s.queue.items.len > 0) s.queue.items[0].size else s.length) else if (number <= 0) 0 else @intFromFloat(number);
    if (s.object_mode and count != 0) count = 1;
    if (count > 0) s.emitted_readable = false;
    if (!unspecified and count > s.high_water_mark) s.high_water_mark = std.math.ceilPowerOfTwo(usize, count) catch return error.NativeNodeStreamLength;
    if (count == 0 and s.need_readable and ((if (s.high_water_mark != 0) s.length >= s.high_water_mark else s.length > 0) or s.ended)) { if (s.length == 0 and s.ended) try endReadable(scope, stream, s) else try readableEvent(scope, stream, s); return c.pi_js_null(); }
    if (s.length == 0 and s.ended) { try endReadable(scope, stream, s); return c.pi_js_null(); }
    if (!s.ended and !s.reading and !s.destroyed and s.constructed and (s.length == 0 or s.length < s.high_water_mark or count > s.length)) {
        s.reading = true; s.sync = true; if (s.length == 0) s.need_readable = true;
        _ = scope.invoke(stream, "_read", &.{c.JS_NewInt64(scope.engine.context, @intCast(s.high_water_mark))}) catch |err| {
            s.sync = false; if (err == error.JavaScriptException) { try failed(scope, stream, scope.engine.captured_exception.?, false); return c.pi_js_null(); } return err;
        };
        s.sync = false;
        if (unspecified) count = if (s.object_mode) 1 else if (s.flowing == true and s.queue.items.len != 0) s.queue.items[0].size else s.length;
    }
    if (count > s.length) { if (!s.ended) { s.need_readable = true; return c.pi_js_null(); } count = s.length; }
    if (count == 0 or s.queue.items.len == 0) { s.need_readable = s.length <= s.high_water_mark; return c.pi_js_null(); }
    const value = try scope.own(try consume(scope, s, count));
    if (s.length == 0) { if (!s.ended) s.need_readable = true else try endReadable(scope, stream, s); }
    s.data_emitted = true; try emit(scope, stream, "data", &.{value});
    return c.JS_DupValue(scope.engine.context, value);
}
fn flow(scope: *Scope, stream: c.JSValue) !void {
    const s = try required(scope, stream, .readable);
    while (s.flowing == true and !s.destroyed) {
        var frame: Scope = .{ .engine = scope.engine }; defer frame.deinit();
        const result = try frame.invoke(stream, "read", &.{}); if (c.JS_IsNull(result)) break;
    }
}
fn write(scope: *Scope, stream: c.JSValue, chunk_arg: c.JSValue, enc_arg: c.JSValue, cb_arg: c.JSValue) !bool {
    const s = try required(scope, stream, .writable);
    var enc = enc_arg; var cb = cb_arg;
    if (c.JS_IsFunction(scope.engine.context, enc)) { cb = enc; enc = c.pi_js_undefined(); }
    if (!c.JS_IsFunction(scope.engine.context, cb)) cb = try scope.get(try owner(scope.engine), "nop");
    if (!scope.truthy(enc)) enc = s.default_encoding;
    var chunk = chunk_arg;
    if (c.JS_IsNull(chunk)) return events.codedError(scope.engine, "TypeError", "ERR_STREAM_NULL_VALUES", "May not write null values to stream");
    if (!s.object_mode) {
        if (!c.JS_IsString(enc)) return events.codedError(scope.engine, "TypeError", "ERR_UNKNOWN_ENCODING", "Unknown encoding");
        const name = try scope.engine.toString(enc); defer scope.engine.gpa.free(name);
        if (!std.mem.eql(u8, name, "buffer") and encoding.parse(name) == null) return events.codedError(scope.engine, "TypeError", "ERR_UNKNOWN_ENCODING", "Unknown encoding");
    }
    if (!s.object_mode and (!c.JS_IsString(chunk) or s.decode_strings)) { chunk = try byteBuffer(scope, chunk, enc); enc = try scope.text("buffer"); }
    const length = if (s.object_mode) @as(usize, 1) else try size(scope, chunk);
    if (s.ending or s.destroyed) {
        const reason = try scope.own(try errorValue(scope, "Error", if (s.ending) "ERR_STREAM_WRITE_AFTER_END" else "ERR_STREAM_DESTROYED", if (s.ending) "write after end" else "Cannot call write after a stream was destroyed"));
        try tick(scope, cb, &.{reason}); try failed(scope, stream, reason, true); return false;
    }
    try addItem(s, chunk, enc, cb, length, false);
    s.pending_callbacks += 1;
    if (!s.writing and s.corked == 0 and s.constructed and !s.processing and s.queue.items.len == 1) try doWrite(scope, stream, s, s.queue.orderedRemove(0), false, c.pi_js_undefined()) else try clearBuffer(scope, stream, s);
    const more = s.length < s.high_water_mark or s.length == 0;
    if (!more) s.need_drain = true;
    return more and !s.destroyed and nullish(s.error_value);
}
fn clearBuffer(scope: *Scope, stream: c.JSValue, s: *State) !void {
    if (s.processing or s.writing or s.corked != 0 or !s.constructed or s.destroyed) return;
    s.processing = true; defer s.processing = false;
    while (s.queue.items.len > 0 and !s.writing and !s.destroyed and s.corked == 0) {
        const writev = try scope.get(stream, "_writev");
        var item: Item = undefined;
        var vector = false;
        if (s.queue.items.len > 1 and c.JS_IsFunction(scope.engine.context, writev)) {
            const entries = try scope.array(); var all_buffers = true; var length: usize = 0;
            for (s.queue.items, 0..) |entry, i| {
                const object = try scope.object(); try scope.put(object, "chunk", entry.chunk); try scope.put(object, "encoding", entry.encoding); try scope.put(object, "callback", entry.callback); try scope.index(entries, @intCast(i), object);
                all_buffers = all_buffers and try buffer.isBuffer(scope.engine, entry.chunk); length += entry.size;
            }
            try scope.put(entries, "allBuffers", c.pi_js_bool(scope.engine.context, @intFromBool(all_buffers)));
            const aggregate = try scope.own(try fnc.createArrow(scope.engine, "callback", 1, vectorCallback, &.{entries}));
            s.pending_callbacks -= s.queue.items.len - 1;
            for (s.queue.items) |entry| entry.free(scope.engine);
            s.queue.clearRetainingCapacity();
            item = .{ .chunk = c.JS_DupValue(scope.engine.context, entries), .encoding = c.JS_DupValue(scope.engine.context, try scope.text("")), .callback = c.JS_DupValue(scope.engine.context, aggregate), .size = length }; vector = true;
        } else item = s.queue.orderedRemove(0);
        try doWrite(scope, stream, s, item, vector, writev);
    }
}
fn doWrite(scope: *Scope, stream: c.JSValue, s: *State, item: Item, vector: bool, writev: c.JSValue) !void {
    s.current = item; s.writing = true; s.expect_callback = true; s.sync = true; s.write_generation +%= 1;
    const done = try callback(scope, stream, .write_done, try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, s.write_generation))));
    if (vector) _ = try scope.call(writev, stream, &.{ item.chunk, done }) else _ = try scope.invoke(stream, "_write", &.{ item.chunk, item.encoding, done });
    s.sync = false;
}
fn vectorCallback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const length = try size(&scope, roots[0]);
    for (0..length) |i| {
        const entry = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, roots[0], @intCast(i))));
        _ = try scope.call(try scope.get(entry, "callback"), c.pi_js_undefined(), &.{arg(args, 0)});
    }
    return c.pi_js_undefined();
}
fn afterWrite(scope: *Scope, stream: c.JSValue, s: *State, cb: c.JSValue, count: usize, reason: c.JSValue) !void {
    s.after_pending = false;
    if (nullish(reason) and !s.ending and s.need_drain and !s.destroyed and s.length == 0) { s.need_drain = false; try emit(scope, stream, "drain", &.{}); }
    for (0..count) |_| { if (s.pending_callbacks != 0) s.pending_callbacks -= 1; _ = try scope.call(cb, c.pi_js_undefined(), &.{if (nullish(reason)) c.pi_js_null() else reason}); }
    if (!nullish(reason)) { try errorBuffer(scope, stream, s, reason); try failed(scope, stream, reason, false); }
    if (s.destroyed and !s.writing) {
        const err = if (!nullish(s.error_value)) s.error_value else try scope.own(try errorValue(scope, "Error", "ERR_STREAM_DESTROYED", "Cannot call write after a stream was destroyed"));
        try errorBuffer(scope, stream, s, err);
    }
    if (s.ending) try finishMaybe(scope, stream, s, true);
}
fn errorBuffer(scope: *Scope, _: c.JSValue, s: *State, reason: c.JSValue) !void {
    if (s.writing) return;
    while (s.queue.items.len > 0) {
        const entry = s.queue.orderedRemove(0); defer entry.free(scope.engine);
        s.length -= entry.size; if (s.pending_callbacks != 0) s.pending_callbacks -= 1;
        _ = try scope.call(entry.callback, c.pi_js_undefined(), &.{reason});
    }
    while (s.end_callbacks.items.len > 0) { const cb = s.end_callbacks.orderedRemove(0); defer scope.engine.freeValue(cb); _ = try scope.call(cb, c.pi_js_undefined(), &.{reason}); }
}
fn writeDone(scope: *Scope, stream: c.JSValue, generation: c.JSValue, reason: c.JSValue) !void {
    const s = try required(scope, stream, .writable); var token: u64 = 0;
    if (c.JS_ToBigUint64(scope.engine.context, &token, generation) < 0) return js.capture(scope.engine);
    if (!s.expect_callback or token != s.write_generation) { const err = try scope.own(try errorValue(scope, "Error", "ERR_MULTIPLE_CALLBACK", "Callback called multiple times")); try failed(scope, stream, err, false); return; }
    s.expect_callback = false; s.writing = false;
    const item = s.current.?; s.current = null; defer item.free(scope.engine); s.length -= item.size;
    const sync = s.sync;
    if (scope.truthy(reason)) {
        // Node observes stack before publishing the write error to either side.
        _ = try scope.get(reason, "stack");
        if (nullish(s.error_value)) s.set(&s.error_value, reason);
        if (try state(scope, stream, .readable)) |r| if (nullish(r.error_value)) { r.set(&r.error_value, reason); };
        if (sync) {
            const info = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
            try scope.put(info, "callback", item.callback); try scope.put(info, "count", c.JS_NewInt32(scope.engine.context, 1)); try scope.put(info, "error", reason);
            try queueTick(scope, stream, .after_write_tick, info);
        } else try afterWrite(scope, stream, s, item.callback, 1, reason);
        return;
    }
    try clearBuffer(scope, stream, s);
    if (!sync) { try afterWrite(scope, stream, s, item.callback, 1, c.pi_js_null()); return; }
    const nop = try scope.get(try owner(scope.engine), "nop");
    const needs_tick = (s.need_drain and s.length == 0) or s.destroyed or !scope.equal(item.callback, nop);
    if (scope.equal(item.callback, nop)) {
        if (!s.after_pending and needs_tick) {
            const info = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
            try scope.put(info, "callback", item.callback); try scope.put(info, "count", c.JS_NewInt32(scope.engine.context, 1)); try scope.put(info, "error", c.pi_js_null());
            s.after_pending = true; try queueTick(scope, stream, .after_write_tick, info);
        } else { s.pending_callbacks -= 1; if (s.ending) try finishMaybe(scope, stream, s, true); }
    } else if (!nullish(s.after_info) and scope.equal(try scope.get(s.after_info, "callback"), item.callback)) {
        const old = try scope.get(s.after_info, "count"); var count: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &count, old) < 0) return js.capture(scope.engine); try scope.set(s.after_info, "count", c.JS_NewUint32(scope.engine.context, count + 1));
    } else if (needs_tick) {
        const info = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
        try scope.put(info, "callback", item.callback); try scope.put(info, "count", c.JS_NewInt32(scope.engine.context, 1)); try scope.put(info, "error", c.pi_js_null());
        s.set(&s.after_info, info); s.after_pending = true; try queueTick(scope, stream, .after_write_tick, info);
    } else { s.pending_callbacks -= 1; if (s.ending) try finishMaybe(scope, stream, s, true); }
}
fn finishMaybe(scope: *Scope, stream: c.JSValue, s: *State, sync: bool) !void {
    if (!s.ending or s.finished or s.destroyed or !nullish(s.error_value) or s.length != 0 or s.writing or !s.constructed) return;
    if (!s.prefinished and !s.final_called) {
        const final = try scope.get(stream, "_final");
        if (c.JS_IsFunction(scope.engine.context, final)) {
            s.final_called = true; s.pending_callbacks += 1; s.sync = true;
            _ = try scope.call(final, stream, &.{try callback(scope, stream, .final_done, c.pi_js_undefined())}); s.sync = false; return;
        }
        s.prefinished = true; try emit(scope, stream, "prefinish", &.{});
    }
    if (s.pending_callbacks == 0 and s.prefinished and !s.finish_scheduled) {
        s.finish_scheduled = true; s.pending_callbacks += 1;
        if (sync) try queueTick(scope, stream, .finish_tick, c.pi_js_undefined()) else try finish(scope, stream, s);
    }
}
fn finish(scope: *Scope, stream: c.JSValue, s: *State) !void {
    if (s.finished or s.destroyed or !nullish(s.error_value)) return;
    if (s.pending_callbacks != 0) s.pending_callbacks -= 1; s.finished = true; s.finish_scheduled = false;
    while (s.end_callbacks.items.len > 0) { const cb = s.end_callbacks.orderedRemove(0); defer scope.engine.freeValue(cb); _ = try scope.call(cb, c.pi_js_undefined(), &.{c.pi_js_null()}); }
    try emit(scope, stream, "finish", &.{});
    const r = try state(scope, stream, .readable);
    if (s.auto_destroy and (r == null or (r.?.auto_destroy and (r.?.end_emitted or !r.?.enabled)))) _ = try scope.invoke(stream, "destroy", &.{});
}
fn end(scope: *Scope, stream: c.JSValue, chunk_arg: c.JSValue, enc_arg: c.JSValue, cb_arg: c.JSValue) !c.JSValue {
    const s = try required(scope, stream, .writable); var chunk = chunk_arg; var enc = enc_arg; var cb = cb_arg;
    if (c.JS_IsFunction(scope.engine.context, chunk)) { cb = chunk; chunk = c.pi_js_undefined(); enc = c.pi_js_undefined(); }
    else if (c.JS_IsFunction(scope.engine.context, enc)) { cb = enc; enc = c.pi_js_undefined(); }
    if (!nullish(chunk)) _ = try write(scope, stream, chunk, enc, c.pi_js_undefined());
    if (s.corked != 0) { s.corked = 1; _ = try scope.invoke(stream, "uncork", &.{}); }
    if (!s.ending and !s.destroyed) { s.ending = true; try finishMaybe(scope, stream, s, true); s.ended = true; }
    if (c.JS_IsFunction(scope.engine.context, cb)) {
        if (!nullish(s.error_value) or s.finished) try tick(scope, cb, &.{if (nullish(s.error_value)) c.pi_js_null() else s.error_value})
        else if (s.destroyed) { const reason = try scope.own(try errorValue(scope, "Error", "ERR_STREAM_DESTROYED", "Cannot call end after a stream was destroyed")); try tick(scope, cb, &.{reason}); }
        else { try s.end_callbacks.append(scope.engine.gpa, c.JS_DupValue(scope.engine.context, cb)); }
    }
    return c.JS_DupValue(scope.engine.context, stream);
}
fn destroy(scope: *Scope, stream: c.JSValue, reason: c.JSValue, cb: c.JSValue) !c.JSValue {
    const r = try state(scope, stream, .readable); const w = try state(scope, stream, .writable);
    if ((r != null and r.?.destroyed) or (w != null and w.?.destroyed)) { if (c.JS_IsFunction(scope.engine.context, cb)) _ = try scope.call(cb, c.pi_js_undefined(), &.{}); return c.JS_DupValue(scope.engine.context, stream); }
    if (r) |s| { s.destroyed = true; if (scope.truthy(reason) and nullish(s.error_value)) s.set(&s.error_value, reason); }
    if (w) |s| { s.destroyed = true; if (scope.truthy(reason) and nullish(s.error_value)) s.set(&s.error_value, reason); }
    const record = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
    try scope.put(record, "done", c.pi_js_bool(scope.engine.context, 0)); try scope.put(record, "callback", cb); try scope.put(record, "reason", reason);
    if ((r != null and !r.?.constructed) or (w != null and !w.?.constructed)) {
        const primary = w orelse r.?; primary.set(&primary.destroy_record, record);
    } else try invokeDestroy(scope, stream, record);
    return c.JS_DupValue(scope.engine.context, stream);
}
fn invokeDestroy(scope: *Scope, stream: c.JSValue, record: c.JSValue) !void {
    const done = try callback(scope, stream, .destroy_done, record);
    _ = scope.invoke(stream, "_destroy", &.{ if (scope.truthy(try scope.get(record, "reason"))) try scope.get(record, "reason") else c.pi_js_null(), done }) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try scope.call(done, c.pi_js_undefined(), &.{scope.engine.captured_exception.?});
        return;
    };
}
fn selectedHwm(scope: *Scope, options: c.JSValue, side: Side, duplex: bool, object_mode: bool) !usize {
    var value = try optional(scope, options, "highWaterMark");
    if (!nullish(value)) value = try optional(scope, options, "highWaterMark") else if (duplex) value = try optional(scope, options, if (side == .readable) "readableHighWaterMark" else "writableHighWaterMark");
    if (nullish(value)) {
        var result: u64 = 0;
        if (c.JS_ToIndex(scope.engine.context, &result, try scope.get(try owner(scope.engine), if (object_mode) "objectHwm" else "byteHwm")) < 0) return js.capture(scope.engine);
        return @intCast(result);
    }
    var number: f64 = 0;
    if (!c.JS_IsNumber(value) or c.JS_ToFloat64(scope.engine.context, &number, value) < 0 or !std.math.isFinite(number) or number < 0 or number != @floor(number)) return events.codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_VALUE", "The property 'options.highWaterMark' is invalid");
    if (number > @as(f64, @floatFromInt(std.math.maxInt(usize)))) return error.NativeNodeStreamLength;
    return @intFromFloat(number);
}
fn newState(scope: *Scope, stream: c.JSValue, side: Side, options: c.JSValue, duplex: bool) !*State {
    const module = try owner(scope.engine);
    const object = try scope.own(try scope.engine.checked(c.JS_NewObjectProtoClass(scope.engine.context, try scope.get(module, if (side == .readable) "readStatePrototype" else "writeStatePrototype"), try classId(scope, side))));
    const initial_encoding = try scope.text("utf8");
    const s = try scope.engine.gpa.create(State);
    s.* = .{ .engine = scope.engine, .side = side, .owner = c.JS_DupValue(scope.engine.context, module), .error_value = c.pi_js_null(), .decoder_value = c.pi_js_null(), .default_encoding = c.JS_DupValue(scope.engine.context, initial_encoding), .text_encoding = c.pi_js_null(), .after_info = c.pi_js_null(), .transform_callback = c.pi_js_null(), .destroy_record = c.pi_js_null() };
    _ = c.JS_SetOpaque(object, s);
    s.object_mode = scope.truthy(try optional(scope, options, "objectMode"));
    if (duplex and scope.truthy(try optional(scope, options, if (side == .readable) "readableObjectMode" else "writableObjectMode"))) s.object_mode = true;
    s.high_water_mark = try selectedHwm(scope, options, side, duplex, s.object_mode);
    if (side == .writable) s.decode_strings = !scope.equal(try optional(scope, options, "decodeStrings"), c.pi_js_bool(scope.engine.context, 0));
    s.emit_close = !scope.equal(try optional(scope, options, "emitClose"), c.pi_js_bool(scope.engine.context, 0));
    s.auto_destroy = !scope.equal(try optional(scope, options, "autoDestroy"), c.pi_js_bool(scope.engine.context, 0));
    const default = try optional(scope, options, "defaultEncoding");
    if (!nullish(default)) {
        if (!c.JS_IsString(default)) return events.codedError(scope.engine, "TypeError", "ERR_UNKNOWN_ENCODING", "Unknown encoding");
        const name = try scope.engine.toString(default); defer scope.engine.gpa.free(name);
        if (encoding.parse(name) == null) return events.codedError(scope.engine, "TypeError", "ERR_UNKNOWN_ENCODING", "Unknown encoding");
        s.set(&s.default_encoding, if (std.mem.eql(u8, name, "utf-8")) initial_encoding else default);
    }
    if (side == .readable and scope.truthy(try optional(scope, options, "encoding"))) {
        const dec = try scope.own(try decoder.create(scope.engine, try optional(scope, options, "encoding")));
        s.set(&s.decoder_value, dec); s.set(&s.text_encoding, try optional(scope, options, "encoding"));
    }
    try scope.set(stream, if (side == .readable) "_readableState" else "_writableState", object);
    return s;
}
fn optionHook(scope: *Scope, stream: c.JSValue, options: c.JSValue, name: [*:0]const u8, target: [*:0]const u8) !void {
    if (c.JS_IsFunction(scope.engine.context, try optional(scope, options, name))) try scope.set(stream, target, try optional(scope, options, name));
}
fn constructor(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
    const kind: Kind = @enumFromInt(raw);
    const names = [_][*:0]const u8{ "Stream", "Readable", "Writable", "Duplex", "Transform", "PassThrough" };
    const ctor = try scope.get(roots[0], names[@intFromEnum(kind)]);
    const instance = c.JS_IsInstanceOf(engine.context, receiver, ctor);
    if (instance < 0) return js.capture(engine);
    if (instance == 0) { var inputs = [_]c.JSValue{arg(args, 0)}; return engine.checked(c.JS_CallConstructor(engine.context, ctor, inputs.len, &inputs)); }
    var options = arg(args, 0);
    if (kind == .stream) { _ = try scope.call(try scope.get(roots[0], "EventEmitter"), receiver, &.{options}); return c.pi_js_undefined(); }
    const duplex = kind == .duplex or kind == .transform or kind == .passthrough;
    if (kind == .transform or kind == .passthrough) {
        const hwm = try selectedHwm(&scope, options, .readable, true, scope.truthy(try optional(&scope, options, "objectMode")));
        if (hwm == 0) {
            const copied = try scope.own(try js.spread(engine, options));
            try scope.put(copied, "highWaterMark", c.pi_js_null()); try scope.put(copied, "readableHighWaterMark", c.JS_NewInt32(engine.context, 0));
            const whwm = try optional(&scope, options, "writableHighWaterMark"); try scope.put(copied, "writableHighWaterMark", if (scope.truthy(whwm)) whwm else c.JS_NewInt32(engine.context, 0)); options = copied;
        }
    }
    if (nullish(try scope.get(receiver, "_events"))) {
        const table = try scope.object();
        inline for (.{ "close", "error" }) |name| try scope.put(table, name, c.pi_js_undefined());
        if (kind == .writable or duplex) inline for (.{ "prefinish", "finish", "drain" }) |name| try scope.put(table, name, c.pi_js_undefined());
        if (kind == .readable or duplex) inline for (.{ "data", "end", "readable" }) |name| try scope.put(table, name, c.pi_js_undefined());
        try scope.set(receiver, "_events", table);
    }
    var r: ?*State = null; var w: ?*State = null;
    if (kind == .readable or duplex) r = try newState(&scope, receiver, .readable, options, duplex);
    if (kind == .writable or duplex) w = try newState(&scope, receiver, .writable, options, duplex);
    if (duplex) {
        try scope.set(receiver, "allowHalfOpen", c.pi_js_bool(engine.context, @intFromBool(!scope.equal(try optional(&scope, options, "allowHalfOpen"), c.pi_js_bool(engine.context, 0)))));
        if (scope.equal(try optional(&scope, options, "readable"), c.pi_js_bool(engine.context, 0))) { r.?.enabled = false; r.?.ended = true; r.?.end_emitted = true; }
        if (scope.equal(try optional(&scope, options, "writable"), c.pi_js_bool(engine.context, 0))) { w.?.enabled = false; w.?.ending = true; w.?.ended = true; w.?.finished = true; }
    }
    if (r != null) try optionHook(&scope, receiver, options, "read", "_read");
    if (w != null) {
        try optionHook(&scope, receiver, options, "write", "_write"); try optionHook(&scope, receiver, options, "writev", "_writev");
    }
    try optionHook(&scope, receiver, options, "destroy", "_destroy");
    if (w != null) try optionHook(&scope, receiver, options, "final", "_final");
    try optionHook(&scope, receiver, options, "construct", "_construct");
    const signal = try optional(&scope, options, "signal");
    if (scope.truthy(signal)) _ = try @import("native_node_stream_lifecycle.zig").addAbortSignal(engine, signal, receiver);
    _ = try scope.call(try scope.get(roots[0], "EventEmitter"), receiver, &.{options});
    if (c.JS_IsFunction(engine.context, try scope.get(receiver, "_construct"))) {
        if (r) |s| s.constructed = false; if (w) |s| s.constructed = false;
        try queueTick(&scope, receiver, .construct_tick, c.pi_js_undefined());
    }
    if (kind == .transform or kind == .passthrough) {
        r.?.sync = false;
        try optionHook(&scope, receiver, options, "transform", "_transform"); try optionHook(&scope, receiver, options, "flush", "_flush");
        const prefinish = try scope.own(try fnc.create(engine, "prefinish", 0, prefinishTransform, &.{})); _ = try scope.invoke(receiver, "on", &.{ try scope.text("prefinish"), prefinish });
    }
    return c.pi_js_undefined();
}
fn prefinishTransform(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const expected = try scope.get(try owner(engine), "transformFinal");
    if (!scope.equal(try scope.get(receiver, "_final"), expected)) _ = try scope.call(expected, receiver, &.{});
    return c.pi_js_undefined();
}
fn transformDone(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const stream = roots[0]; const cb = roots[1];
    if (scope.truthy(arg(args, 0))) return js.call(engine, cb, c.pi_js_undefined(), &.{arg(args, 0)});
    if (!nullish(arg(args, 1))) _ = try scope.invoke(stream, "push", &.{arg(args, 1)});
    const r = try required(&scope, stream, .readable); const w = try required(&scope, stream, .writable);
    var old: u64 = 0; if (c.JS_ToIndex(engine.context, &old, roots[2]) < 0) return js.capture(engine);
    if (w.ended) try tick(&scope, cb, &.{})
    else if (r.ended or r.length == old or r.length < r.high_water_mark) _ = try scope.call(cb, c.pi_js_undefined(), &.{})
    else r.set(&r.transform_callback, cb);
    return c.pi_js_undefined();
}
fn flushDone(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const stream = roots[0]; const cb = roots[1];
    if (scope.truthy(arg(args, 0))) {
        if (c.JS_IsFunction(engine.context, cb)) _ = try scope.call(cb, c.pi_js_undefined(), &.{arg(args, 0)}) else _ = try scope.invoke(stream, "destroy", &.{arg(args, 0)});
    } else {
        if (!nullish(arg(args, 1))) _ = try scope.invoke(stream, "push", &.{arg(args, 1)});
        _ = try scope.invoke(stream, "push", &.{c.pi_js_null()});
        if (c.JS_IsFunction(engine.context, cb)) _ = try scope.call(cb, c.pi_js_undefined(), &.{});
    }
    return c.pi_js_undefined();
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine);
    const op: Op = @enumFromInt(raw); const stream = if (nullish(roots[0])) receiver else roots[0]; const extra = if (roots.len > 2) roots[2] else c.pi_js_undefined();
    switch (op) {
        .push, .unshift => return c.pi_js_bool(engine.context, @intFromBool(try push(&scope, stream, arg(args, 0), arg(args, 1), op == .unshift))),
        .read => return read(&scope, stream, arg(args, 0)),
        .resume_stream => {
            const s = try required(&scope, stream, .readable);
            if (s.flowing != true) { s.flowing = !s.readable_listening; if (!s.resume_scheduled) { s.resume_scheduled = true; try queueTick(&scope, stream, .resume_tick, c.pi_js_undefined()); } }
            s.paused = false; return c.JS_DupValue(engine.context, stream);
        },
        .pause_stream => { const s = try required(&scope, stream, .readable); if (s.flowing != false) { s.flowing = false; try emit(&scope, stream, "pause", &.{}); } s.paused = true; return c.JS_DupValue(engine.context, stream); },
        .is_paused => { const s = try required(&scope, stream, .readable); return c.pi_js_bool(engine.context, @intFromBool(s.paused or s.flowing == false)); },
        .on, .remove_listener, .remove_all => {
            const base = try scope.get(try owner(engine), "StreamPrototype");
            const result = try scope.call(try scope.get(base, if (op == .on) "on" else if (op == .remove_listener) "removeListener" else "removeAllListeners"), stream, args);
            const s = try required(&scope, stream, .readable); const event = arg(args, 0);
            const data = scope.equal(event, try scope.text("data")); const readable = scope.equal(event, try scope.text("readable"));
            if (op == .on) {
                if (data) {
                    s.data_listening = true;
                    s.readable_listening = s.readable_listening or scope.truthy(try scope.invoke(stream, "listenerCount", &.{try scope.text("readable")}));
                    if (s.flowing != false) _ = try scope.invoke(stream, "resume", &.{});
                } else if (readable and !s.end_emitted and !s.readable_listening) {
                    s.readable_listening = true; s.need_readable = true; s.flowing = false; s.emitted_readable = false;
                    if (s.length != 0) try readableEvent(&scope, stream, s) else if (!s.reading) try queueTick(&scope, stream, .read_zero_tick, c.pi_js_undefined());
                }
            } else if (readable or (op == .remove_all and c.JS_IsUndefined(event))) try queueTick(&scope, stream, .update_listening_tick, c.pi_js_undefined())
            else if (op == .remove_listener and data and !scope.truthy(try scope.invoke(stream, "listenerCount", &.{try scope.text("data")}))) s.data_listening = false;
            return c.JS_DupValue(engine.context, result);
        },
        .set_encoding => {
            const s = try required(&scope, stream, .readable); const dec = try scope.own(try decoder.create(engine, arg(args, 0)));
            s.set(&s.decoder_value, dec); s.set(&s.text_encoding, try scope.get(dec, "encoding"));
            var text = try scope.text("");
            for (s.queue.items) |entry| text = try scope.concat(text, try scope.invoke(dec, "write", &.{entry.chunk}));
            for (s.queue.items) |entry| entry.free(engine); s.queue.clearRetainingCapacity(); s.length = 0;
            const length = try size(&scope, text); if (length != 0) try addItem(s, text, c.pi_js_undefined(), c.pi_js_undefined(), length, false);
            return c.JS_DupValue(engine.context, stream);
        },
        .write => return c.pi_js_bool(engine.context, @intFromBool(try write(&scope, stream, arg(args, 0), arg(args, 1), arg(args, 2)))),
        .end => return end(&scope, stream, arg(args, 0), arg(args, 1), arg(args, 2)),
        .cork => { (try required(&scope, stream, .writable)).corked += 1; return c.pi_js_undefined(); },
        .uncork => { const s = try required(&scope, stream, .writable); if (s.corked > 0) s.corked -= 1; try clearBuffer(&scope, stream, s); return c.pi_js_undefined(); },
        .set_default_encoding => {
            const s = try required(&scope, stream, .writable); if (!c.JS_IsString(arg(args, 0))) return events.codedError(engine, "TypeError", "ERR_UNKNOWN_ENCODING", "Unknown encoding"); const original_name = try engine.toString(arg(args, 0)); defer engine.gpa.free(original_name);
            const name = try std.ascii.allocLowerString(engine.gpa, original_name); defer engine.gpa.free(name);
            if (encoding.parse(name) == null) return events.codedError(engine, "TypeError", "ERR_UNKNOWN_ENCODING", "Unknown encoding");
            s.set(&s.default_encoding, try scope.text(name)); return c.JS_DupValue(engine.context, stream);
        },
        .destroy => return destroy(&scope, stream, arg(args, 0), arg(args, 1)),
        .cannot_pipe => { const reason = try scope.own(try errorValue(&scope, "Error", "ERR_STREAM_CANNOT_PIPE", "Cannot pipe, not readable")); try failed(&scope, stream, reason, false); },
        .default_read => return events.codedError(engine, "Error", "ERR_METHOD_NOT_IMPLEMENTED", "The _read() method is not implemented"),
        .default_write => {
            const vector = try scope.get(stream, "_writev");
            if (c.JS_IsFunction(engine.context, vector)) { const entries = try scope.array(); const entry = try scope.object(); try scope.put(entry, "chunk", arg(args, 0)); try scope.put(entry, "encoding", arg(args, 1)); try scope.index(entries, 0, entry); return js.call(engine, vector, stream, &.{ entries, arg(args, 2) }); }
            const err = try scope.own(try errorValue(&scope, "Error", "ERR_METHOD_NOT_IMPLEMENTED", "The _write() method is not implemented")); return js.call(engine, arg(args, 2), c.pi_js_undefined(), &.{err});
        },
        .default_destroy => return js.call(engine, arg(args, 1), c.pi_js_undefined(), &.{arg(args, 0)}),
        .default_transform => return events.codedError(engine, "Error", "ERR_METHOD_NOT_IMPLEMENTED", "The _transform() method is not implemented"),
        .transform_read => { const s = try required(&scope, stream, .readable); if (!nullish(s.transform_callback)) { const cb = try scope.own(c.JS_DupValue(engine.context, s.transform_callback)); s.set(&s.transform_callback, c.pi_js_null()); _ = try scope.call(cb, c.pi_js_undefined(), &.{}); } return c.pi_js_undefined(); },
        .transform_write => {
            const s = try required(&scope, stream, .readable);
            const done = try scope.own(try fnc.createArrow(engine, "", 2, transformDone, &.{ stream, arg(args, 2), c.JS_NewInt64(engine.context, @intCast(s.length)) }));
            return js.invoke(engine, stream, "_transform", &.{ arg(args, 0), arg(args, 1), done });
        },
        .transform_final => {
            const flush = try scope.get(stream, "_flush"); const r = try required(&scope, stream, .readable);
            const done = try scope.own(try fnc.createArrow(engine, "", 2, flushDone, &.{ stream, arg(args, 0) }));
            if (c.JS_IsFunction(engine.context, flush) and !r.destroyed) _ = try scope.call(flush, stream, &.{done}) else _ = try scope.call(done, c.pi_js_undefined(), &.{});
            return c.pi_js_undefined();
        },
        .pass_transform => return js.call(engine, arg(args, 2), c.pi_js_undefined(), &.{ c.pi_js_null(), arg(args, 0) }),
        .resume_tick => {
            const s = try required(&scope, stream, .readable); if (!s.reading) _ = try scope.invoke(stream, "read", &.{c.JS_NewInt32(engine.context, 0)});
            s.resume_scheduled = false; try emit(&scope, stream, "resume", &.{}); try flow(&scope, stream);
            if (s.flowing == true and !s.reading) _ = try scope.invoke(stream, "read", &.{c.JS_NewInt32(engine.context, 0)});
        },
        .read_more_tick => {
            const s = try required(&scope, stream, .readable);
            while (!s.reading and !s.ended and !s.destroyed and (s.length < s.high_water_mark or (s.flowing == true and s.length == 0))) {
                var frame: Scope = .{ .engine = engine }; defer frame.deinit(); const previous = s.length;
                _ = try frame.invoke(stream, "read", &.{c.JS_NewInt32(engine.context, 0)}); if (previous == s.length) break;
            }
            s.reading_more = false;
        },
        .readable_tick => { const s = try required(&scope, stream, .readable); try emitReadableNow(&scope, stream, s); },
        .read_zero_tick => { _ = try scope.invoke(stream, "read", &.{c.JS_NewInt32(engine.context, 0)}); },
        .update_listening_tick => {
            const s = try required(&scope, stream, .readable); s.readable_listening = scope.truthy(try scope.invoke(stream, "listenerCount", &.{try scope.text("readable")}));
            if (s.resume_scheduled and !s.paused) s.flowing = true else if (s.data_listening) _ = try scope.invoke(stream, "resume", &.{}) else if (!s.readable_listening) s.flowing = null;
        },
        .end_tick => {
            const s = try required(&scope, stream, .readable); s.end_scheduled = false;
            if (!s.destroyed and !s.end_emitted and s.length == 0) {
                s.end_emitted = true; try emit(&scope, stream, "end", &.{});
                const w = try state(&scope, stream, .writable);
                if (w != null and !scope.truthy(try scope.get(stream, "allowHalfOpen")) and !w.?.ended) try queueTick(&scope, stream, .half_end_tick, c.pi_js_undefined())
                else if (s.auto_destroy and (w == null or (w.?.auto_destroy and (w.?.finished or !w.?.enabled)))) _ = try scope.invoke(stream, "destroy", &.{});
            }
        },
        .half_end_tick => { _ = try scope.invoke(stream, "end", &.{}); },
        .write_done => try writeDone(&scope, stream, extra, arg(args, 0)),
        .after_write_tick => { const s = try required(&scope, stream, .writable); var count: u32 = 0; if (c.JS_ToUint32(engine.context, &count, try scope.get(extra, "count")) < 0) return js.capture(engine); s.set(&s.after_info, c.pi_js_null()); try afterWrite(&scope, stream, s, try scope.get(extra, "callback"), count, try scope.get(extra, "error")); },
        .final_done => {
            const s = try required(&scope, stream, .writable);
            if (s.prefinished or s.finished) { const err = try scope.own(try errorValue(&scope, "Error", "ERR_MULTIPLE_CALLBACK", "Callback called multiple times")); try failed(&scope, stream, err, false); }
            else { if (s.pending_callbacks != 0) s.pending_callbacks -= 1; if (scope.truthy(arg(args, 0))) { try errorBuffer(&scope, stream, s, arg(args, 0)); try failed(&scope, stream, arg(args, 0), s.sync); } else { s.prefinished = true; try emit(&scope, stream, "prefinish", &.{}); if (!s.finish_scheduled) { s.finish_scheduled = true; s.pending_callbacks += 1; try queueTick(&scope, stream, .finish_tick, c.pi_js_undefined()); } } }
        },
        .finish_tick => try finish(&scope, stream, try required(&scope, stream, .writable)),
        .destroy_done => {
            if (!scope.truthy(try scope.get(extra, "done"))) {
                try scope.put(extra, "done", c.pi_js_bool(engine.context, 1)); const reason = arg(args, 0);
                if (try state(&scope, stream, .readable)) |s| { s.closed = true; if (scope.truthy(reason) and nullish(s.error_value)) s.set(&s.error_value, reason); }
                if (try state(&scope, stream, .writable)) |s| { s.closed = true; if (scope.truthy(reason) and nullish(s.error_value)) s.set(&s.error_value, reason); if (!s.writing) { const err = if (!nullish(s.error_value)) s.error_value else try scope.own(try errorValue(&scope, "Error", "ERR_STREAM_DESTROYED", "Cannot call write after a stream was destroyed")); try errorBuffer(&scope, stream, s, err); } }
                const cb = try scope.get(extra, "callback"); if (c.JS_IsFunction(engine.context, cb)) _ = try scope.call(cb, c.pi_js_undefined(), &.{reason});
                try queueTick(&scope, stream, .close_tick, reason);
            }
        },
        .close_tick => {
            const r = try state(&scope, stream, .readable); const w = try state(&scope, stream, .writable);
            const already_error = (r != null and r.?.error_emitted) or (w != null and w.?.error_emitted);
            if (scope.truthy(extra) and !already_error) { if (r) |s| s.error_emitted = true; if (w) |s| s.error_emitted = true; try emit(&scope, stream, "error", &.{extra}); }
            if ((r != null and r.?.closed and !r.?.close_emitted) or (w != null and w.?.closed and !w.?.close_emitted)) {
                if (r) |s| s.close_emitted = true; if (w) |s| s.close_emitted = true;
                if ((r != null and r.?.emit_close) or (w != null and w.?.emit_close)) try emit(&scope, stream, "close", &.{});
            }
        },
        .construct_tick => {
            const record = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))); try scope.put(record, "called", c.pi_js_bool(engine.context, 0));
            const done = try scope.own(try fnc.create(engine, "onConstruct", 1, dispatch, &.{ stream, c.JS_NewInt32(engine.context, @intFromEnum(Op.construct_done)), record }));
            const completed = try callback(&scope, stream, .construct_callback, done);
            const generation = engine.native_allocation_generation;
            _ = scope.invoke(stream, "_construct", &.{completed}) catch |err| {
                if (err != error.JavaScriptException) return err;
                const captured = engine.captured_exception orelse return err;
                if (c.JS_IsUncatchableError(captured)) return err;
                try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, captured, generation);
                // Transfer the handled ordinary reason before any allocation
                // or nextTick hook. A replacement capture belongs to that hook.
                engine.captured_exception = null;
                const reason = try scope.own(captured);
                try tick(&scope, done, &.{reason}); return c.pi_js_undefined();
            };
        },
        .construct_callback => try tick(&scope, extra, &.{arg(args, 0)}),
        .construct_done => {
            if (scope.truthy(try scope.get(extra, "called"))) { const err = if (!nullish(arg(args, 0))) arg(args, 0) else try scope.own(try errorValue(&scope, "Error", "ERR_MULTIPLE_CALLBACK", "Callback called multiple times")); try failed(&scope, stream, err, false); }
            else {
                try scope.put(extra, "called", c.pi_js_bool(engine.context, 1)); const r = try state(&scope, stream, .readable); const w = try state(&scope, stream, .writable);
                if (r) |s| s.constructed = true; if (w) |s| s.constructed = true;
                const primary = w orelse r.?;
                if (primary.destroyed) {
                    if (!nullish(primary.destroy_record)) { const record = try scope.own(c.JS_DupValue(engine.context, primary.destroy_record)); primary.set(&primary.destroy_record, c.pi_js_null()); const combined = try scope.own(try @import("native_node_stream_iterator.zig").aggregate(&scope, arg(args, 0), try scope.get(record, "reason"))); try scope.put(record, "reason", combined); try invokeDestroy(&scope, stream, record); }
                } else if (scope.truthy(arg(args, 0))) try failed(&scope, stream, arg(args, 0), true)
                else { if (w) |s| { try clearBuffer(&scope, stream, s); try finishMaybe(&scope, stream, s, true); } if (r) |s| if (s.need_readable) { try maybeReadMore(&scope, stream, s); }; }
            }
        },
    }
    return c.pi_js_undefined();
}
fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
fn writableHasInstance(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const module = try owner(engine); const object = arg(args, 0);
    if (scope.truthy(try scope.call(try scope.get(module, "functionHasInstance"), receiver, &.{object}))) return c.pi_js_bool(engine.context, 1);
    if (!scope.equal(receiver, try scope.get(module, "Writable"))) return c.pi_js_bool(engine.context, 0);
    if (!scope.truthy(object)) return c.JS_DupValue(engine.context, object);
    const value = try scope.get(object, "_writableState");
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_GetOpaque(value, try classId(&scope, .writable)) != null));
}
fn property(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const name = try engine.toString(roots[0]); defer engine.gpa.free(name);
    const internal = scope.truthy(roots[1]); const setting = scope.truthy(roots[2]);
    const side: Side = if (std.mem.startsWith(u8, name, "writable")) .writable else .readable;
    var s: ?*State = null;
    if (internal) {
        var raw = c.JS_GetOpaque(receiver, try classId(&scope, .readable)); if (raw == null) raw = c.JS_GetOpaque(receiver, try classId(&scope, .writable));
        if (raw) |handle| s = @ptrCast(@alignCast(handle)) else return error.RequiredRealNativeNodeStreamState;
    } else if (std.mem.eql(u8, name, "destroyed") or std.mem.eql(u8, name, "closed") or std.mem.eql(u8, name, "errored")) { s = try state(&scope, receiver, .writable); if (s == null) s = try state(&scope, receiver, .readable); }
    else s = try state(&scope, receiver, side);
    if (s == null) return if (std.mem.eql(u8, name, "errored")) c.pi_js_null() else c.pi_js_bool(engine.context, 0);
    const current = s.?;
    if (!internal and !setting and std.mem.eql(u8, name, "destroyed")) {
        const r = try state(&scope, receiver, .readable); const w = try state(&scope, receiver, .writable);
        return c.pi_js_bool(engine.context, @intFromBool(if (r != null and w != null) r.?.destroyed and w.?.destroyed else current.destroyed));
    }
    if (setting) {
        const value = arg(args, 0); const enabled = scope.truthy(value);
        if (std.mem.eql(u8, name, "destroyed")) {
            current.destroyed = enabled;
            if (!internal) if (try state(&scope, receiver, .readable)) |r| { r.destroyed = enabled; };
        } else if (std.mem.eql(u8, name, "flowing") or std.mem.eql(u8, name, "readableFlowing")) current.flowing = if (nullish(value)) null else enabled
        else if (std.mem.eql(u8, name, "reading")) current.reading = enabled
        else if (std.mem.eql(u8, name, "sync")) current.sync = enabled
        else if (std.mem.eql(u8, name, "needReadable")) current.need_readable = enabled
        else if (std.mem.eql(u8, name, "ended")) current.ended = enabled
        else if (std.mem.eql(u8, name, "endEmitted")) current.end_emitted = enabled
        else if (std.mem.eql(u8, name, "ending")) current.ending = enabled
        else if (std.mem.eql(u8, name, "finished")) current.finished = enabled
        else if (std.mem.eql(u8, name, "needDrain")) current.need_drain = enabled
        else if (std.mem.eql(u8, name, "constructed")) current.constructed = enabled
        else if (std.mem.eql(u8, name, "objectMode")) current.object_mode = enabled
        else if (std.mem.eql(u8, name, "emitClose")) current.emit_close = enabled
        else if (std.mem.eql(u8, name, "autoDestroy")) current.auto_destroy = enabled
        else if (std.mem.eql(u8, name, "decodeStrings")) current.decode_strings = enabled
        else if (std.mem.eql(u8, name, "errored")) current.set(&current.error_value, value)
        else if (std.mem.eql(u8, name, "decoder")) current.set(&current.decoder_value, value)
        else if (std.mem.eql(u8, name, "encoding")) current.set(&current.text_encoding, value)
        else if (std.mem.eql(u8, name, "defaultEncoding")) current.set(&current.default_encoding, value)
        else if (std.mem.eql(u8, name, "readable") or std.mem.eql(u8, name, "writable")) current.enabled = enabled
        else {
            var number: u64 = 0; if (c.JS_ToIndex(engine.context, &number, value) < 0) return js.capture(engine);
            if (std.mem.eql(u8, name, "length")) current.length = @intCast(number)
            else if (std.mem.eql(u8, name, "highWaterMark")) current.high_water_mark = @intCast(number)
            else if (std.mem.eql(u8, name, "corked")) current.corked = @intCast(number);
        }
        return c.pi_js_undefined();
    }
    if (std.mem.eql(u8, name, "readable")) return c.pi_js_bool(engine.context, @intFromBool(current.enabled and !current.destroyed and nullish(current.error_value) and !current.end_emitted));
    if (std.mem.eql(u8, name, "writable")) return c.pi_js_bool(engine.context, @intFromBool(current.enabled and !current.destroyed and nullish(current.error_value) and !current.ending));
    if (std.mem.eql(u8, name, "length") or std.mem.endsWith(u8, name, "Length")) return c.JS_NewInt64(engine.context, @intCast(current.length));
    if (std.mem.eql(u8, name, "highWaterMark") or std.mem.endsWith(u8, name, "HighWaterMark")) return c.JS_NewInt64(engine.context, @intCast(current.high_water_mark));
    if (std.mem.eql(u8, name, "objectMode") or std.mem.endsWith(u8, name, "ObjectMode")) return c.pi_js_bool(engine.context, @intFromBool(current.object_mode));
    if (std.mem.eql(u8, name, "flowing") or std.mem.eql(u8, name, "readableFlowing")) return if (current.flowing) |value| c.pi_js_bool(engine.context, @intFromBool(value)) else c.pi_js_null();
    if (std.mem.eql(u8, name, "errored")) return c.JS_DupValue(engine.context, current.error_value);
    if (std.mem.eql(u8, name, "decoder")) return c.JS_DupValue(engine.context, current.decoder_value);
    if (std.mem.eql(u8, name, "encoding")) return c.JS_DupValue(engine.context, current.text_encoding);
    if (std.mem.eql(u8, name, "defaultEncoding")) return c.JS_DupValue(engine.context, current.default_encoding);
    if (std.mem.eql(u8, name, "corked") or std.mem.eql(u8, name, "writableCorked")) return c.JS_NewInt64(engine.context, @intCast(current.corked));
    if (std.mem.eql(u8, name, "pendingcb")) return c.JS_NewInt64(engine.context, @intCast(current.pending_callbacks));
    const flag = if (std.mem.eql(u8, name, "destroyed")) current.destroyed
        else if (std.mem.eql(u8, name, "closed")) current.closed
        else if (std.mem.eql(u8, name, "ended") or std.mem.eql(u8, name, "writableEnded")) current.ended
        else if (std.mem.eql(u8, name, "endEmitted") or std.mem.eql(u8, name, "readableEnded")) current.end_emitted
        else if (std.mem.eql(u8, name, "readableAborted")) current.destroyed and !current.end_emitted
        else if (std.mem.eql(u8, name, "writableAborted")) current.destroyed and !current.finished
        else if (std.mem.eql(u8, name, "readableDidRead")) current.data_emitted
        else if (std.mem.eql(u8, name, "reading")) current.reading
        else if (std.mem.eql(u8, name, "sync")) current.sync
        else if (std.mem.eql(u8, name, "needReadable")) current.need_readable
        else if (std.mem.eql(u8, name, "needDrain") or std.mem.eql(u8, name, "writableNeedDrain")) current.need_drain
        else if (std.mem.eql(u8, name, "ending")) current.ending
        else if (std.mem.eql(u8, name, "finished") or std.mem.eql(u8, name, "writableFinished")) current.finished
        else if (std.mem.eql(u8, name, "prefinished")) current.prefinished
        else if (std.mem.eql(u8, name, "writing")) current.writing
        else if (std.mem.eql(u8, name, "constructed")) current.constructed
        else if (std.mem.eql(u8, name, "autoDestroy")) current.auto_destroy
        else if (std.mem.eql(u8, name, "emitClose")) current.emit_close
        else if (std.mem.eql(u8, name, "decodeStrings")) current.decode_strings
        else false;
    return c.pi_js_bool(engine.context, @intFromBool(flag));
}
fn accessor(scope: *Scope, prototype: c.JSValue, name: [*:0]const u8, internal: bool, writable: bool) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name); if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine); defer c.JS_FreeAtom(scope.engine.context, atom);
    const value = try scope.text(std.mem.span(name));
    const get = try scope.own(try fnc.createMethod(scope.engine, "get", 0, property, &.{ value, c.pi_js_bool(scope.engine.context, @intFromBool(internal)), c.pi_js_bool(scope.engine.context, 0) }));
    const set = if (writable) try scope.own(try fnc.createMethod(scope.engine, "set", 1, property, &.{ value, c.pi_js_bool(scope.engine.context, @intFromBool(internal)), c.pi_js_bool(scope.engine.context, 1) })) else c.pi_js_undefined();
    if (c.JS_DefinePropertyGetSet(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, get), c.JS_DupValue(scope.engine.context, set), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
}
fn method(scope: *Scope, prototype: c.JSValue, name: [*:0]const u8, length: c_int, op: Op) !c.JSValue {
    const function = try scope.own(try fnc.create(scope.engine, name, length, dispatch, &.{ c.pi_js_null(), c.JS_NewInt32(scope.engine.context, @intFromEnum(op)) }));
    try scope.put(prototype, name, function); return function;
}
/// Requires the actual process object. No synthetic tick host or transport is
/// created; the assembler must install this before guest extension execution.
pub fn install(engine: *em.Engine, process: c.JSValue) !void {
    if (engine.native_module_values.contains(module_key)) return;
    try events.install(engine); try buffer.install(engine); try decoder.install(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (!c.JS_IsObject(process) or !c.JS_IsFunction(engine.context, try scope.get(process, "nextTick"))) return error.RequiredGenuineNativeProcessTicks;
    const module = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(module, "process", process); try scope.put(module, "byteHwm", c.JS_NewInt32(engine.context, if (@import("builtin").os.tag == .windows) 16384 else 65536)); try scope.put(module, "objectHwm", c.JS_NewInt32(engine.context, 16));
    inline for (.{ "Error", "TypeError", "RangeError", "AggregateError" }) |name| try scope.put(module, name, try scope.global(name));
    try scope.put(module, "arrayPush", try scope.get(try scope.get(try scope.global("Array"), "prototype"), "push"));
    try scope.put(module, "numberParseInt", try scope.global("parseInt"));
    try scope.put(module, "nop", try scope.own(try fnc.createArrow(engine, "nop", 0, noop, &.{})));
    const emitter = try scope.get(engine.native_module_values.get("node:events").?, "EventEmitter"); try scope.put(module, "EventEmitter", emitter);
    // Register a private owner before any constructor can reenter a native
    // stream helper. Its mutable private object is not a public stream facade.
    try engine.registerValueModule(module_key, module);
    inline for (.{ Side.readable, Side.writable }, .{ "readStateClass", "writeStateClass" }, .{ "readStatePrototype", "writeStatePrototype" }) |side, class_name, proto_name| {
        var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = if (side == .readable) "ReadableState" else "WritableState", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        try scope.put(module, class_name, c.JS_NewUint32(engine.context, id));
        const prototype = try scope.object(); try scope.put(module, proto_name, prototype);
        inline for (.{ "length", "highWaterMark", "objectMode", "destroyed", "closed", "errored", "ended", "endEmitted", "flowing", "reading", "sync", "needReadable", "needDrain", "ending", "finished", "prefinished", "writing", "corked", "pendingcb", "constructed", "autoDestroy", "emitClose", "decodeStrings", "defaultEncoding", "decoder", "encoding", "readable", "writable" }) |name| try accessor(&scope, prototype, name, true, true);
    }
    const names = [_][*:0]const u8{ "Stream", "Readable", "Writable", "Duplex", "Transform", "PassThrough" };
    const kinds = [_]Kind{ .stream, .readable, .writable, .duplex, .transform, .passthrough };
    for (names, kinds) |name, kind| {
        const ctor = try scope.own(try fnc.create(engine, name, 1, constructor, &.{ module, c.JS_NewInt32(engine.context, @intFromEnum(kind)) }));
        try scope.put(module, name, ctor);
        const prototype = try scope.get(ctor, "prototype");
        const parent_name: [*:0]const u8 = switch (kind) { .stream => "EventEmitter", .readable, .writable => "Stream", .duplex => "Readable", .transform => "Duplex", .passthrough => "Transform" };
        const parent = try scope.get(module, parent_name);
        if (c.JS_SetPrototype(engine.context, prototype, try scope.get(parent, "prototype")) < 0 or c.JS_SetPrototype(engine.context, ctor, parent) < 0) return js.capture(engine);
        if (kind == .stream) try scope.put(module, "StreamPrototype", prototype);
        if (kind == .readable) {
            inline for (.{ "push", "unshift", "read", "resume", "pause", "isPaused", "on", "removeListener", "removeAllListeners", "setEncoding", "_read" }, .{ Op.push, Op.unshift, Op.read, Op.resume_stream, Op.pause_stream, Op.is_paused, Op.on, Op.remove_listener, Op.remove_all, Op.set_encoding, Op.default_read }, .{ 2, 2, 1, 0, 0, 0, 2, 2, 1, 1, 1 }) |n, op, length| _ = try method(&scope, prototype, n, length, op);
            try scope.put(prototype, "addListener", try scope.get(prototype, "on")); try scope.put(prototype, "off", try scope.get(prototype, "removeListener"));
            inline for (.{ "readable", "readableLength", "readableHighWaterMark", "readableObjectMode", "readableFlowing", "readableEnded", "readableAborted", "readableDidRead" }) |n| try accessor(&scope, prototype, n, false, std.mem.eql(u8, n, "readableFlowing"));
        }
        if (kind == .writable) {
            _ = try method(&scope, prototype, "pipe", 0, .cannot_pipe);
            inline for (.{ "write", "end", "cork", "uncork", "setDefaultEncoding", "_write" }, .{ Op.write, Op.end, Op.cork, Op.uncork, Op.set_default_encoding, Op.default_write }, .{ 3, 3, 0, 0, 1, 3 }) |n, op, length| _ = try method(&scope, prototype, n, length, op);
            inline for (.{ "writable", "writableLength", "writableHighWaterMark", "writableObjectMode", "writableEnded", "writableFinished", "writableNeedDrain", "writableCorked", "writableAborted" }) |n| try accessor(&scope, prototype, n, false, false);
        }
        if (kind == .readable or kind == .writable) {
            _ = try method(&scope, prototype, "destroy", 2, .destroy); _ = try method(&scope, prototype, "_destroy", 2, .default_destroy);
            inline for (.{ "destroyed", "closed", "errored" }) |n| try accessor(&scope, prototype, n, false, std.mem.eql(u8, n, "destroyed"));
        }
        if (kind == .duplex) {
            const writable = try scope.get(try scope.get(module, "Writable"), "prototype");
            inline for (.{ "write", "end", "cork", "uncork", "setDefaultEncoding", "_write" }) |n| try scope.put(prototype, n, try scope.get(writable, n));
            inline for (.{ "writable", "writableLength", "writableHighWaterMark", "writableObjectMode", "writableEnded", "writableFinished", "writableNeedDrain", "writableCorked", "writableAborted", "destroyed", "closed", "errored" }) |n| try accessor(&scope, prototype, n, false, std.mem.eql(u8, n, "destroyed"));
        }
        if (kind == .transform) {
            _ = try method(&scope, prototype, "_read", 0, .transform_read); _ = try method(&scope, prototype, "_write", 3, .transform_write); _ = try method(&scope, prototype, "_transform", 3, .default_transform);
            try scope.put(module, "transformFinal", try method(&scope, prototype, "_final", 1, .transform_final));
        }
        if (kind == .passthrough) _ = try method(&scope, prototype, "_transform", 3, .pass_transform);
    }
    const has_instance_symbol = try scope.get(try scope.global("Symbol"), "hasInstance");
    const function_prototype = try scope.own(try engine.checked(c.JS_GetFunctionProto(engine.context)));
    try scope.put(module, "functionHasInstance", try scope.own(try js.getKey(engine, function_prototype, has_instance_symbol)));
    const has_instance_atom = try js.atom(engine, has_instance_symbol); defer c.JS_FreeAtom(engine.context, has_instance_atom);
    const has_instance = try scope.own(try fnc.create(engine, "value", 1, writableHasInstance, &.{}));
    if (c.JS_DefinePropertyValue(engine.context, try scope.get(module, "Writable"), has_instance_atom, c.JS_DupValue(engine.context, has_instance), 0) < 0) return js.capture(engine);
    try @import("native_node_stream_lifecycle.zig").install(engine, module);
    try @import("native_node_stream_adapters.zig").install(engine, module);
    try @import("native_node_stream_iterator.zig").install(engine, module);
    // Only implemented real exports are registered. Full Node stream namespace
    // parity is a separate unqualified gate; there are no missing-body aliases.
    const stream = try scope.get(module, "Stream");
    for (names) |name| try scope.put(stream, name, try scope.get(module, name));
    inline for (.{ "pipeline", "finished", "addAbortSignal", "isDestroyed", "isErrored", "isReadable", "isWritable", "isDisturbed", "getDefaultHighWaterMark", "setDefaultHighWaterMark", "promises" }) |name| try scope.put(stream, name, try scope.get(module, name));
    try engine.registerDefaultModule("node:stream", stream); try engine.registerDefaultModule("stream", stream);
}
pub fn create(engine: *em.Engine, name: [*:0]const u8, options: c.JSValue) !c.JSValue {
    const constructor_value = try js.get(engine, try owner(engine), name); defer engine.freeValue(constructor_value);
    var args = [_]c.JSValue{options}; return engine.checked(c.JS_CallConstructor(engine.context, constructor_value, args.len, &args));
}
pub fn createReadable(engine: *em.Engine, options: c.JSValue) !c.JSValue { return create(engine, "Readable", options); }
pub fn createWritable(engine: *em.Engine, options: c.JSValue) !c.JSValue { return create(engine, "Writable", options); }
pub fn createDuplex(engine: *em.Engine, options: c.JSValue) !c.JSValue { return create(engine, "Duplex", options); }
/// The IO adapter calls this on the VM owner after copying its ephemeral bytes.
/// The live public push method is deliberately preserved; false stops OS drain.
pub fn pushBytes(engine: *em.Engine, stream: c.JSValue, data: []const u8) !bool {
    const chunk = try buffer.fromBytes(engine, data); defer engine.freeValue(chunk);
    const result = try js.invoke(engine, stream, "push", &.{chunk}); defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 1;
}
/// Only a confirmed producer EOF calls this. Child exit and destroy never do.
pub fn pushEnd(engine: *em.Engine, stream: c.JSValue) !void {
    const result = try js.invoke(engine, stream, "push", &.{c.pi_js_null()}); engine.freeValue(result);
}

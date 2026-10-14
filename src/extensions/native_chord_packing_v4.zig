//! Actual b45 protocol4 payload packing: args/value, raw deflate and binary envelopes.
const std = @import("std");
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const zlib = @import("native_chord_zlib.zig");
const encoding = @import("binary_encoding.zig");
pub const threshold = 64 * 1024;
pub fn isPacked(s: *Scope, bindings: c.JSValue, value: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(s.engine.context, value, try s.get(bindings, "Packed"));
    if (result < 0) return js.capture(s.engine);
    return result != 0;
}
pub fn bytes(s: *Scope, value: c.JSValue) ![]u8 {
    if (c.JS_IsString(value)) {
        const text = try s.engine.toString(value);
        defer s.engine.gpa.free(text);
        return encoding.encode(s.engine.gpa, text, .utf8);
    }
    var offset: usize = 0;
    var length: usize = 0;
    var backing = value;
    if (!c.JS_IsArrayBuffer(value)) {
        var element: usize = 0;
        backing = try s.keep(try s.engine.checked(c.JS_GetTypedArrayBuffer(s.engine.context, value, &offset, &length, &element)));
    }
    var total: usize = 0;
    const pointer = c.JS_GetArrayBuffer(s.engine.context, &total, backing);
    if (c.JS_HasException(s.engine.context)) return js.capture(s.engine);
    if (c.JS_IsArrayBuffer(value)) length = total;
    if (offset > total or length > total - offset or (pointer == null and length != 0)) {
        _ = try h.typeError(s, &.{try s.text("Invalid ArrayBuffer view")});
        return error.JavaScriptException;
    }
    return s.engine.gpa.dupe(u8, if (length == 0) &.{} else pointer[offset .. offset + length]);
}
pub fn uint8(s: *Scope, value: []const u8) !c.JSValue {
    const buffer = try s.keep(try s.engine.checked(c.JS_NewArrayBufferCopy(s.engine.context, value.ptr, value.len)));
    var args = [_]c.JSValue{buffer};
    return s.keep(try s.engine.checked(c.JS_NewTypedArray(s.engine.context, 1, &args, c.JS_TYPED_ARRAY_UINT8)));
}
fn zlibError(s: *Scope, err: anyerror, diagnostic: ?[]const u8) !c.JSValue {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    const ended = err == error.ZlibUnexpectedEnd;
    const exception = try s.keep(try js.builtin(s.engine, "Error", &.{try s.text(diagnostic orelse if (ended) "unexpected end of file" else "invalid compressed data")}));
    try h.field(s, exception, "errno", c.JS_NewInt32(s.engine.context, if (ended) -5 else -3));
    try h.field(s, exception, "code", try s.text(if (ended) "Z_BUF_ERROR" else "Z_DATA_ERROR"));
    return h.throwValue(s, exception);
}
pub fn unpack(s: *Scope, bindings: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (!try isPacked(s, bindings, value)) return value;
    const input = try bytes(s, try s.get(value, "bytes"));
    defer s.engine.gpa.free(input);
    var diagnostic: ?[]const u8 = null;
    const output = zlib.inflate(s.engine.gpa, input, &diagnostic) catch |err| return zlibError(s, err, diagnostic);
    defer s.engine.gpa.free(output);
    const text = try encoding.decode(s.engine.gpa, output, .utf8);
    defer s.engine.gpa.free(text);
    return s.builtin("JSON", "parse", &.{try s.text(text)});
}
fn payloadField(s: *Scope, frame: c.JSValue) !c.JSValue {
    const tag = try s.get(frame, "t");
    if (try s.equal(tag, "call")) return if (c.JS_IsUndefined(try s.get(frame, "args"))) c.pi_js_undefined() else s.text("args");
    if (try s.equal(tag, "result") or try s.equal(tag, "state")) return if (c.JS_IsUndefined(try s.get(frame, "value"))) c.pi_js_undefined() else s.text("value");
    return c.pi_js_undefined();
}
fn validField(s: *Scope, field: c.JSValue) !bool {
    inline for (.{ "args", "value" }) |name| if (try s.equal(field, name)) return true;
    return false;
}
fn envelope(s: *Scope, frame: c.JSValue, field: c.JSValue) !c.JSValue {
    const result = try s.record();
    try js.spreadInto(s.engine, result, frame);
    const atom = try js.atom(s.engine, field);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DeleteProperty(s.engine.context, result, atom, c.JS_PROP_THROW) < 0) return js.capture(s.engine);
    return result;
}
fn rest(s: *Scope, source: c.JSValue, excluded: c.JSValue) !c.JSValue {
    const result = try s.record();
    const exclude = try js.atom(s.engine, excluded);
    defer c.JS_FreeAtom(s.engine.context, exclude);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(s.engine);
    defer c.JS_FreePropertyEnum(s.engine.context, names, count);
    for (names[0..count]) |entry| {
        if (entry.atom == exclude) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(s.engine.context, &descriptor, source, entry.atom);
        if (present < 0) return js.capture(s.engine);
        if (present == 0) continue;
        defer s.engine.freeValue(descriptor.value);
        defer s.engine.freeValue(descriptor.getter);
        defer s.engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try s.engine.checked(c.JS_GetProperty(s.engine.context, source, entry.atom));
        if (c.JS_DefinePropertyValue(s.engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
    }
    return result;
}
fn packedBytes(s: *Scope, bindings: c.JSValue, value: c.JSValue, compress: bool, json: c.JSValue) !c.JSValue {
    if (try isPacked(s, bindings, value)) return s.get(value, "bytes");
    if (!compress or c.JS_IsUndefined(json) or !try r.greater(s, try s.get(json, "length"), c.JS_NewInt32(s.engine.context, threshold))) return c.pi_js_undefined();
    const text = try s.engine.toString(json);
    defer s.engine.gpa.free(text);
    const raw = try encoding.encode(s.engine.gpa, text, .utf8);
    defer s.engine.gpa.free(raw);
    const compressed = try zlib.deflate(s.engine.gpa, raw);
    defer s.engine.gpa.free(compressed);
    return s.keep(try @import("node_buffer.zig").fromBytes(s.engine, compressed));
}
pub fn packObject(s: *Scope, bindings: c.JSValue, frame: c.JSValue, compress: bool) !c.JSValue {
    const field = try payloadField(s, frame);
    if (c.JS_IsUndefined(field)) return frame;
    const value = try s.key(frame, field);
    const compressed_value = try packedBytes(s, bindings, value, compress, if (compress) try s.builtin("JSON", "stringify", &.{value}) else c.pi_js_undefined());
    if (c.JS_IsUndefined(compressed_value)) return frame;
    const result = try envelope(s, frame, field);
    const buffer = try s.builtin("Buffer", "from", &.{ try s.get(compressed_value, "buffer"), try s.get(compressed_value, "byteOffset"), try s.get(compressed_value, "byteLength") });
    try h.field(s, result, "z", try r.pair(s, field, try h.invoke(s, buffer, "toString", &.{try s.text("base64")})));
    return result;
}
pub fn unpackObject(s: *Scope, bindings: c.JSValue, message: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(message) or c.JS_IsFunction(s.engine.context, message) or !try js.hasKey(s.engine, message, try s.text("z"))) return message;
    const z = try s.get(message, "z");
    const result = try rest(s, message, try s.text("z"));
    if (!c.JS_IsArray(z) or !try validField(s, try s.at(z, 0)) or !c.JS_IsString(try s.at(z, 1))) return h.typeError(s, &.{try s.text("bad packed payload")});
    const buffer = try s.builtin("Buffer", "from", &.{ try s.at(z, 1), try s.text("base64") });
    const compressed_value = try h.construct(s, bindings, "Packed", &.{buffer});
    try js.setKey(s.engine, result, try s.at(z, 0), compressed_value);
    return result;
}
pub fn packMessage(s: *Scope, bindings: c.JSValue, frame: c.JSValue, compress: bool) !c.JSValue {
    const field = try payloadField(s, frame);
    if (c.JS_IsUndefined(field)) return s.builtin("JSON", "stringify", &.{frame});
    const value = try s.key(frame, field);
    const json = if (try isPacked(s, bindings, value)) c.pi_js_undefined() else try s.builtin("JSON", "stringify", &.{value});
    const compressed_value = try packedBytes(s, bindings, value, compress, json);
    const envelope_value = try envelope(s, frame, field);
    if (c.JS_IsUndefined(compressed_value)) {
        const head = try s.builtin("JSON", "stringify", &.{envelope_value});
        return r.concat(s, &.{ try h.invoke(s, head, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -1) }), try s.text(","), try s.builtin("JSON", "stringify", &.{field}), try s.text(":"), json, try s.text("}") });
    }
    try h.field(s, envelope_value, "z", field);
    const head_text = try s.engine.toString(try s.builtin("JSON", "stringify", &.{envelope_value}));
    defer s.engine.gpa.free(head_text);
    const head = try encoding.encode(s.engine.gpa, head_text, .utf8);
    defer s.engine.gpa.free(head);
    const compressed = try bytes(s, compressed_value);
    defer s.engine.gpa.free(compressed);
    const output = try s.engine.gpa.alloc(u8, 4 + head.len + compressed.len);
    defer s.engine.gpa.free(output);
    std.mem.writeInt(u32, output[0..4], @intCast(head.len), .big);
    @memcpy(output[4 .. 4 + head.len], head);
    @memcpy(output[4 + head.len ..], compressed);
    return uint8(s, output);
}
pub fn splitMessage(s: *Scope, data: c.JSValue) !c.JSValue {
    const raw = try bytes(s, data);
    defer s.engine.gpa.free(raw);
    if (raw.len < 4) {
        return h.throwValue(s, try s.keep(try js.builtin(s.engine, "RangeError", &.{try s.text("Offset is outside the bounds of the DataView")})));
    }
    const count = std.mem.readInt(u32, raw[0..4], .big);
    const end = @min(raw.len, @as(usize, count) + 4);
    const decoded = try encoding.decode(s.engine.gpa, raw[4..end], .utf8);
    defer s.engine.gpa.free(decoded);
    const parsed = try s.builtin("JSON", "parse", &.{try s.text(decoded)});
    if (!c.JS_IsObject(parsed) or c.JS_IsFunction(s.engine.context, parsed)) return h.typeError(s, &.{try s.text("bad envelope")});
    const field = try s.get(parsed, "z");
    const envelope_value = try rest(s, parsed, try s.text("z"));
    if (!c.JS_IsString(field) or !try validField(s, field)) return h.typeError(s, &.{try s.text("bad packed payload")});
    const result = try s.record();
    try h.field(s, result, "envelope", envelope_value);
    try h.field(s, result, "field", field);
    try h.field(s, result, "bytes", try uint8(s, raw[end..]));
    return result;
}
pub fn inflateMessage(s: *Scope, data: c.JSValue) anyerror!c.JSValue {
    const split = try splitMessage(s, data);
    const raw = try bytes(s, try s.get(split, "bytes"));
    defer s.engine.gpa.free(raw);
    var diagnostic: ?[]const u8 = null;
    const output = zlib.inflate(s.engine.gpa, raw, &diagnostic) catch |err| return zlibError(s, err, diagnostic);
    defer s.engine.gpa.free(output);
    const text = try encoding.decode(s.engine.gpa, output, .utf8);
    defer s.engine.gpa.free(text);
    const head = try s.builtin("JSON", "stringify", &.{try s.get(split, "envelope")});
    return r.concat(s, &.{ try h.invoke(s, head, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, -1) }), try s.text(","), try s.builtin("JSON", "stringify", &.{try s.get(split, "field")}), try s.text(":"), try s.text(text), try s.text("}") });
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const value = try s.keep(try @import("native_class.zig").object(engine, target));
    try h.field(&s, value, "bytes", h.arg(args, 0));
    return s.result(value);
}
pub fn install(s: *Scope, bindings: c.JSValue) !void {
    const prototype = try s.record();
    try js.define(s.engine, bindings, "Packed", try @import("native_class.zig").constructor(s.engine, "Packed", 1, prototype, construct, &.{}));
}

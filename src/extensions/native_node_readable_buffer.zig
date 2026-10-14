//! Node24 Readable's actual chunk-consumption engine for normalized stream state.
//! This does not install a partial Readable/Writable/FileHandle public graph.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = js.c;
pub const object_mode: u32 = 1;
pub const decoder: u32 = 1 << 21;
fn integer(scope: *Scope, value: c.JSValue) !usize {
    if (!c.JS_IsNumber(value)) return error.InvalidNativeReadableBufferCount;
    var raw: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &raw, value) < 0) return js.capture(scope.engine);
    if (!std.math.isFinite(raw) or raw < 0 or raw > 9007199254740991 or @trunc(raw) != raw) return error.InvalidNativeReadableBufferCount;
    return std.math.cast(usize, @as(u64, @intFromFloat(raw))) orelse error.InvalidNativeReadableBufferCount;
}
fn number(scope: *Scope, value: usize) c.JSValue {
    return c.JS_NewFloat64(scope.engine.context, @floatFromInt(value));
}
fn flags(scope: *Scope, bindings: c.JSValue, state: c.JSValue) !u32 {
    const value = try scope.own(try js.getKey(scope.engine, state, try scope.get(bindings, "streamStateSymbol")));
    var bits: u32 = undefined;
    if (c.JS_ToUint32(scope.engine.context, &bits, value) < 0) return js.capture(scope.engine);
    return bits;
}
fn item(scope: *Scope, buffer: c.JSValue, index: usize) !c.JSValue {
    const key = std.math.cast(u32, index) orelse return error.InvalidNativeReadableBufferIndex;
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, buffer, key)));
}
fn setItem(scope: *Scope, buffer: c.JSValue, index: usize, value: c.JSValue) !void {
    const key = std.math.cast(u32, index) orelse return error.InvalidNativeReadableBufferIndex;
    if (c.JS_SetPropertyUint32(scope.engine.context, buffer, key, c.JS_DupValue(scope.engine.context, value)) < 0) return js.capture(scope.engine);
}
fn copy(scope: *Scope, bindings: c.JSValue, destination: c.JSValue, source: c.JSValue, offset: usize) !void {
    _ = try scope.call(try scope.get(bindings, "streamTypedArraySet"), destination, &.{ source, number(scope, offset) });
}
fn fastView(scope: *Scope, data: c.JSValue, offset: usize, count: usize) !c.JSValue {
    const backing = try scope.get(data, "buffer");
    const byte_offset = try integer(scope, try scope.get(data, "byteOffset"));
    return scope.own(try @import("node_buffer.zig").fromBacking(scope.engine, backing, try std.math.add(usize, byte_offset, offset), count));
}
fn fastTail(scope: *Scope, data: c.JSValue, consumed: usize) !c.JSValue {
    const backing = try scope.get(data, "buffer");
    const byte_offset = try integer(scope, try scope.get(data, "byteOffset"));
    const length = try integer(scope, try scope.get(data, "length"));
    if (consumed > length) return error.InvalidNativeReadableBufferCount;
    return scope.own(try @import("node_buffer.zig").fromBacking(scope.engine, backing, try std.math.add(usize, byte_offset, consumed), length - consumed));
}
/// The caller supplies the actual shared kState symbol, captured Buffer and
/// TypedArray.prototype.set. Counts and state indexes are normalized by read().
/// Like the original _fromList, this function does not decrement state.length.
pub fn fromList(scope: *Scope, bindings: c.JSValue, count: usize, state: c.JSValue) !c.JSValue {
    if (scope.equal(try scope.get(state, "length"), c.JS_NewInt32(scope.engine.context, 0))) return c.pi_js_null();
    var index = try integer(scope, try scope.get(state, "bufferIndex"));
    const buffer = try scope.get(state, "buffer");
    const length = try integer(scope, try scope.get(buffer, "length"));
    if (index > length) return error.InvalidNativeReadableBufferIndex;
    const result = if (try flags(scope, bindings, state) & object_mode != 0) object: {
        const value = try item(scope, buffer, index);
        try setItem(scope, buffer, index, c.pi_js_null());
        index += 1;
        break :object value;
    } else if (count == 0 or count >= try integer(scope, try scope.get(state, "length"))) all: {
        if (try flags(scope, bindings, state) & decoder != 0) {
            var text = try scope.text("");
            while (index < length) : (index += 1) {
                text = try scope.concat(text, try item(scope, buffer, index));
                try setItem(scope, buffer, index, c.pi_js_null());
            }
            break :all text;
        }
        if (length - index == 0) break :all try scope.own(try @import("node_buffer.zig").fromBytes(scope.engine, &.{}));
        if (length - index == 1) {
            const value = try item(scope, buffer, index);
            try setItem(scope, buffer, index, c.pi_js_null());
            index += 1;
            break :all value;
        }
        const value = try scope.invoke(try scope.get(bindings, "streamBuffer"), "allocUnsafe", &.{try scope.get(state, "length")});
        var offset: usize = 0;
        while (index < length) : (index += 1) {
            try copy(scope, bindings, value, try item(scope, buffer, index), offset);
            offset = try std.math.add(usize, offset, try integer(scope, try scope.get(try item(scope, buffer, index), "length")));
            try setItem(scope, buffer, index, c.pi_js_null());
        }
        break :all value;
    } else partial: {
        const first_length = try integer(scope, try scope.get(try item(scope, buffer, index), "length"));
        if (count < first_length) {
            const value = try scope.invoke(try item(scope, buffer, index), "slice", &.{ number(scope, 0), number(scope, count) });
            try setItem(scope, buffer, index, try scope.invoke(try item(scope, buffer, index), "slice", &.{number(scope, count)}));
            break :partial value;
        }
        // The original re-reads the first chunk length for its strict equality.
        if (count == try integer(scope, try scope.get(try item(scope, buffer, index), "length"))) {
            const value = try item(scope, buffer, index);
            try setItem(scope, buffer, index, c.pi_js_null());
            index += 1;
            break :partial value;
        }
        var remaining = count;
        if (try flags(scope, bindings, state) & decoder != 0) {
            var text = try scope.text("");
            while (index < length) {
                const str = try item(scope, buffer, index);
                const str_length = try integer(scope, try scope.get(str, "length"));
                if (remaining > str_length) {
                    text = try scope.concat(text, str);
                    remaining -= try integer(scope, try scope.get(str, "length"));
                    try setItem(scope, buffer, index, c.pi_js_null());
                    index += 1;
                } else {
                    // Preserve Node24's actual comparison with the list length.
                    if (remaining == try integer(scope, try scope.get(buffer, "length"))) {
                        text = try scope.concat(text, str);
                        try setItem(scope, buffer, index, c.pi_js_null());
                        index += 1;
                    } else {
                        text = try scope.concat(text, try scope.invoke(str, "slice", &.{ number(scope, 0), number(scope, remaining) }));
                        try setItem(scope, buffer, index, try scope.invoke(str, "slice", &.{number(scope, remaining)}));
                    }
                    break;
                }
            }
            break :partial text;
        }
        const value = try scope.invoke(try scope.get(bindings, "streamBuffer"), "allocUnsafe", &.{number(scope, count)});
        while (index < length) {
            const data = try item(scope, buffer, index);
            const data_length = try integer(scope, try scope.get(data, "length"));
            if (remaining > data_length) {
                try copy(scope, bindings, value, data, count - remaining);
                remaining -= try integer(scope, try scope.get(data, "length"));
                try setItem(scope, buffer, index, c.pi_js_null());
                index += 1;
            } else {
                if (remaining == try integer(scope, try scope.get(data, "length"))) {
                    try copy(scope, bindings, value, data, count - remaining);
                    try setItem(scope, buffer, index, c.pi_js_null());
                    index += 1;
                } else {
                    try copy(scope, bindings, value, try fastView(scope, data, 0, remaining), count - remaining);
                    try setItem(scope, buffer, index, try fastTail(scope, data, remaining));
                }
                break;
            }
        }
        break :partial value;
    };
    if (index == length) {
        try scope.set(try scope.get(state, "buffer"), "length", number(scope, 0));
        try scope.set(state, "bufferIndex", number(scope, 0));
    } else if (index > 1024) {
        _ = try scope.invoke(try scope.get(state, "buffer"), "splice", &.{ number(scope, 0), number(scope, index) });
        try scope.set(state, "bufferIndex", number(scope, 0));
    } else try scope.set(state, "bufferIndex", number(scope, index));
    return result;
}

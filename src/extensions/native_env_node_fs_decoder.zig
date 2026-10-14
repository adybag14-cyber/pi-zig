//! Node StringDecoder chunk tails for fs readFile; state is rooted in the owner continuation.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const encoding = @import("binary_encoding.zig");
const c = js.c;
fn utf8Prefix(bytes: []const u8) usize {
    var index: usize = 0;
    while (index < bytes.len) {
        const first = bytes[index];
        const expected: usize = if (first >= 0xc0 and first <= 0xdf) 2 else if (first >= 0xe0 and first <= 0xef) 3 else if (first >= 0xf0 and first <= 0xf7) 4 else 1;
        var consumed: usize = 1;
        while (consumed < expected) {
            if (index + consumed == bytes.len) return index;
            if (bytes[index + consumed] & 0xc0 != 0x80) break;
            consumed += 1;
        }
        index += consumed;
    }
    return bytes.len;
}
fn bufferBytes(scope: *h.Scope, value: c.JSValue) ![]const u8 {
    const engine = scope.engine;
    var offset: usize = undefined;
    var length: usize = undefined;
    var element: usize = undefined;
    const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element)));
    var total: usize = undefined;
    const raw = c.JS_GetArrayBuffer(engine.context, &total, backing);
    if ((raw == null and length != 0) or offset > total or length > total - offset) return error.InvalidNativeNodeDecoderBuffer;
    return if (length == 0) &.{} else raw[offset..][0..length];
}
pub fn decode(scope: *h.Scope, saved: c.JSValue, input: c.JSValue, final: bool) !c.JSValue {
    const engine = scope.engine;
    const name = try engine.toString(try scope.get(saved, "encoding"));
    defer engine.gpa.free(name);
    const kind = encoding.parse(name) orelse return error.UnknownNativeNodeEncoding;
    const pending = try scope.get(saved, "decoderPending");
    var combined: std.ArrayList(u8) = .empty;
    defer combined.deinit(engine.gpa);
    const bytes = if (c.JS_IsUndefined(pending)) try bufferBytes(scope, input) else blk: {
        try combined.appendSlice(engine.gpa, try bufferBytes(scope, pending));
        try combined.appendSlice(engine.gpa, try bufferBytes(scope, input));
        break :blk combined.items;
    };
    const length = bytes.len;
    const prefix = if (final) length else switch (kind) {
        .utf8 => utf8Prefix(bytes),
        .utf16le => utf16: {
            var count = length - length % 2;
            if (count >= 2) {
                const unit = std.mem.readInt(u16, bytes[count - 2 ..][0..2], .little);
                if (unit >= 0xd800 and unit <= 0xdbff) count -= 2;
            }
            break :utf16 count;
        },
        .base64, .base64url => length - length % 3,
        else => length,
    };
    // Copy the suffix before the file read reuses its mutable buffer.
    try scope.put(saved, "decoderPending", if (prefix != length) try scope.own(try @import("node_buffer.zig").fromBytes(engine, bytes[prefix..])) else c.pi_js_undefined());
    const text = try encoding.decode(engine.gpa, bytes[0..prefix], kind);
    defer engine.gpa.free(text);
    return scope.own(try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len)));
}

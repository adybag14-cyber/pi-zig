// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The actual primitive-string ParseEncoding/StorageSize/bounded Write consumed
//! by StreamBase::Writev. No Buffer constructor or guest encoding shim is used.
//! String views retain their actual flat owner in the caller's HandleScope.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const temporary = @import("native_node_maybe_stack_buffer.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;

pub const Encoding = enum { ascii, latin1, utf8, ucs2, buffer, base64, base64url, hex };

fn unit(view: *const c.JSPiStringView, position: usize) u16 {
    return if (view.data8 != null) view.data8[position] else view.data16[position];
}
fn scalar(view: *const c.JSPiStringView, position: *usize) u21 {
    const first = unit(view, position.*);
    position.* += 1;
    if (first >= 0xd800 and first <= 0xdbff) {
        if (position.* < view.length) {
            const second = unit(view, position.*);
            if (second >= 0xdc00 and second <= 0xdfff) {
                position.* += 1;
                return 0x10000 + ((@as(u21, first) - 0xd800) << 10) +
                    (@as(u21, second) - 0xdc00);
            }
        }
        return 0xfffd;
    }
    if (first >= 0xdc00 and first <= 0xdfff) return 0xfffd;
    return first;
}
fn width(point: u21) usize {
    return if (point < 0x80) 1 else if (point < 0x800) 2
        else if (point < 0x10000) 3 else 4;
}
fn exactUtf8(view: *const c.JSPiStringView) usize {
    var at: usize = 0;
    var size: usize = 0;
    while (at < view.length) size +%= width(scalar(view, &at));
    return size;
}
fn encodeScalar(output: [*c]u8, point: u21) usize {
    if (point < 0x80) { output[0] = @intCast(point); return 1; }
    if (point < 0x800) {
        output[0] = @intCast(0xc0 | (point >> 6));
        output[1] = @intCast(0x80 | (point & 0x3f));
        return 2;
    }
    if (point < 0x10000) {
        output[0] = @intCast(0xe0 | (point >> 12));
        output[1] = @intCast(0x80 | ((point >> 6) & 0x3f));
        output[2] = @intCast(0x80 | (point & 0x3f));
        return 3;
    }
    output[0] = @intCast(0xf0 | (point >> 18));
    output[1] = @intCast(0x80 | ((point >> 12) & 0x3f));
    output[2] = @intCast(0x80 | ((point >> 6) & 0x3f));
    output[3] = @intCast(0x80 | (point & 0x3f));
    return 4;
}
fn boundedUtf8(view: *const c.JSPiStringView, output: [*c]u8,
    capacity: usize) usize
{
    var at: usize = 0;
    var size: usize = 0;
    while (at < view.length) {
        const point = scalar(view, &at);
        // V8 Utf8::Encode rolls a lead surrogate back when the whole pair
        // cannot fit. It does not emit a replacement for that clipped pair.
        if (width(point) > capacity - size) break;
        size += encodeScalar(output + size, point);
    }
    return size;
}
fn flat(s: *a.Scope, string: c.JSValue) !c.JSPiStringView {
    if (!c.JS_IsString(string)) check.assertion(s.engine, .{
        .file_line = "src/string_bytes.cc:246",
        .message = "val->IsString() == true",
        .function = "node::StringBytes::Write",
    });
    const generation = try s.beforeAllocation();
    const owner = try s.checkedAllocation(c.JS_ToString(s.engine.context, string), generation);
    var view: c.JSPiStringView = undefined;
    if (c.JS_PiBorrowFlatStringView(owner, &view) != 1)
        return error.ActualStreamStringBytesFlatOwnerRequired;
    return view;
}

/// Original ParseEncoding only coerces an already primitive string; objects,
/// numbers, Symbols, null and undefined choose the default without guest code.
/// Utf8Value's native temporary and C-string NUL termination are preserved.
pub fn parseEncoding(s: *a.Scope, environment: *callbacks.Environment,
    value: c.JSValue) !Encoding
{
    if (!c.JS_IsString(value)) return .utf8;
    const view = try flat(s, value);
    const storage = if (view.data8 != null)
        (if (1024 < view.length *% 2 +% 1) exactUtf8(&view)
            else view.length *% 2) +% 1
        else view.length *% 3 +% 1;
    var utf8: temporary.Buffer(u8, 1024) = undefined;
    try utf8.init(environment, storage);
    defer utf8.deinit();
    const data = utf8.data();
    const size = boundedUtf8(&view, data.ptr, data.len);
    data[size] = 0;
    const text = data[0..(std.mem.indexOfScalar(u8, data[0..size], 0) orelse size)];
    const aliases = .{
        .{ "utf8", Encoding.utf8 }, .{ "utf-8", Encoding.utf8 },
        .{ "ucs2", Encoding.ucs2 }, .{ "ucs-2", Encoding.ucs2 },
        .{ "utf16le", Encoding.ucs2 }, .{ "utf-16le", Encoding.ucs2 },
        .{ "latin1", Encoding.latin1 }, .{ "binary", Encoding.latin1 },
        .{ "buffer", Encoding.buffer }, .{ "base64", Encoding.base64 },
        .{ "base64url", Encoding.base64url }, .{ "ascii", Encoding.ascii },
        .{ "hex", Encoding.hex },
    };
    inline for (aliases) |alias| {
        if (std.ascii.eqlIgnoreCase(text, alias[0])) return alias[1];
    }
    return .utf8;
}

/// Selected StringBytes::StorageSize for an already converted primitive.
// Long UTF8 deliberately evaluates Size before StorageSize, matching the actual
// StreamBase boolean expression; the final capacity is still three times length.
pub fn storageSize(s: *a.Scope, string: c.JSValue, encoding: Encoding) !usize {
    const view = try flat(s, string);
    if (encoding == .utf8 and view.length > 65535) _ = exactUtf8(&view);
    return switch (encoding) {
        .ascii, .latin1 => view.length,
        .utf8, .buffer => view.length *% 3,
        .ucs2 => view.length *% 2,
        // Source calls base64_length_from_binary, including URL's no-padding
        // convention; it does not use the decoder's output-size estimate here.
        .base64 => ((view.length +% 2) / 3) *% 4,
        .base64url => (view.length / 3) *% 4 +
            (if (view.length % 3 == 0) @as(usize, 0) else view.length % 3 + 1),
        .hex => blk: {
            if (view.length % 2 != 0) check.assertion(s.engine, .{
                .file_line = "src/string_bytes.cc:429",
                .message = "view.length() % 2 == 0 && \"invalid hex string length\"",
                .function = "node::StringBytes::StorageSize",
            });
            break :blk view.length / 2;
        },
    };
}

fn unbase64(byte: u8) u8 {
    return if (byte >= 'A' and byte <= 'Z') byte - 'A'
        else if (byte >= 'a' and byte <= 'z') byte - 'a' + 26
        else if (byte >= '0' and byte <= '9') byte - '0' + 52
        else if (byte == '+' or byte == '-') 62
        else if (byte == '/' or byte == '_') 63 else 255;
}
fn base64Group(view: *const c.JSPiStringView, output: [*c]u8,
    capacity: usize, at: *usize, written: *usize) bool
{
    var high: u8 = 0;
    for (0..4) |part| {
        var low: u8 = undefined;
        while (true) {
            const byte: u8 = @truncate(unit(view, at.*));
            low = unbase64(byte);
            at.* += 1;
            if (low < 64) break;
            if (byte == '=' or at.* >= view.length) return false;
        }
        if (part != 0) {
            output[written.*] = switch (part) {
                1 => ((high & 0x3f) << 2) | ((low & 0x30) >> 4),
                2 => ((high & 0x0f) << 4) | ((low & 0x3c) >> 2),
                else => ((high & 0x03) << 6) | (low & 0x3f),
            };
            written.* += 1;
        }
        if (at.* >= view.length or written.* >= capacity) return false;
        high = low;
    }
    return true;
}
fn base64(view: *const c.JSPiStringView, output: [*c]u8,
    capacity: usize) usize
{
    // This is the retained nbytes decoder, not the public atob/Buffer helper.
    // Node's SIMD success has identical bytes; any invalid alphabet/padding or
    // short destination selects this exact decoder. Both alphabets and low-byte
    // wide input are intentional. There is no additional backing allocation.
    var estimated = view.length;
    if (estimated < 2) return 0;
    if (unit(view, estimated - 1) == '=') {
        estimated -= 1;
        if (unit(view, estimated - 1) == '=') estimated -= 1;
    }
    const decoded = if (estimated > 1)
        (estimated / 4) * 3 + (estimated % 4 + 1) / 2 else 0;
    const max_written = @min(capacity, decoded) / 3 * 3;
    var max_at = view.length / 4 * 4;
    var at: usize = 0;
    var written: usize = 0;
    while (at < max_at and written < max_written) {
        const x0 = unbase64(@truncate(unit(view, at)));
        const x1 = unbase64(@truncate(unit(view, at + 1)));
        const x2 = unbase64(@truncate(unit(view, at + 2)));
        const x3 = unbase64(@truncate(unit(view, at + 3)));
        if ((x0 | x1 | x2 | x3) & 0x80 != 0) {
            if (!base64Group(view, output, capacity, &at, &written)) return written;
            max_at = at + (view.length - at) / 4 * 4;
        } else {
            output[written] = (x0 << 2) | (x1 >> 4);
            output[written + 1] = (x1 << 4) | (x2 >> 2);
            output[written + 2] = (x2 << 6) | x3;
            at += 4;
            written += 3;
        }
    }
    if (at < view.length and written < capacity)
        _ = base64Group(view, output, capacity, &at, &written);
    return written;
}
fn unhex(byte: u8) ?u8 {
    return if (byte >= '0' and byte <= '9') byte - '0'
        else if (byte >= 'a' and byte <= 'f') byte - 'a' + 10
        else if (byte >= 'A' and byte <= 'F') byte - 'A' + 10 else null;
}
fn decode(view: *const c.JSPiStringView, output: [*c]u8,
    capacity: usize, encoding: Encoding) usize
{
    if (encoding != .hex) return base64(view, output, capacity);
    var written: usize = 0;
    while (written < capacity and written * 2 + 1 < view.length) : (written += 1) {
        const high = unhex(@truncate(unit(view, written * 2))) orelse return written;
        const low = unhex(@truncate(unit(view, written * 2 + 1))) orelse return written;
        output[written] = (high << 4) | low;
    }
    return written;
}

/// Actual StringBytes::Write clips capacity to INT_MAX and never emits a
/// partial UTF8 scalar or UCS2 code unit. The second pass may change encoding,
// string length, or string content; callers pass remaining actual backing bytes.
pub fn write(s: *a.Scope, environment: *callbacks.Environment, string: c.JSValue,
    encoding: Encoding, output: [*c]u8, available: usize) !usize
{
    const capacity = @min(available, @as(usize, std.math.maxInt(c_int)));
    var view = try flat(s, string);
    switch (encoding) {
        .ascii, .latin1 => {
            const size = @min(view.length, capacity);
            for (0..size) |at| output[at] = @truncate(unit(&view, at));
            return size;
        },
        .utf8, .buffer => return boundedUtf8(&view, output, capacity),
        .ucs2 => {
            const length = @min(view.length, capacity / 2);
            for (0..length) |at| {
                const value = unit(&view, at);
                output[at * 2] = @truncate(value);
                output[at * 2 + 1] = @intCast(value >> 8);
            }
            return length * 2;
        },
        .base64, .base64url, .hex => {
            if (view.data8 != null) return decode(&view, output, capacity, encoding);
            // StringBytes uses a genuine TwoByteValue, including the terminal
            // code unit and its 1024-unit stack/charged-heap boundary, even for
            // a zero destination. It dies before the caller advances its offset.
            var wide: temporary.Buffer(u16, 1024) = undefined;
            try wide.init(environment, view.length + 1);
            defer wide.deinit();
            const copy = wide.data();
            for (0..view.length) |at| copy[at] = unit(&view, at);
            copy[view.length] = 0;
            view.data16 = copy.ptr;
            return decode(&view, output, capacity, encoding);
        },
    }
}

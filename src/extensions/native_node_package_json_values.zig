// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Intrinsic native package binding strings and fresh dense serialization.
//! No public String/Array constructor, iterator, index setter or URL getter.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const parser = @cImport(@cInclude("native_node_package_json_parser.h"));

/// The binding's actual CHECK has already admitted a primitive String. Normal
/// UTF8 conversion joins pairs; lone surrogate code points are replaced exactly
/// as MakeUtf8String's WriteUtf8V2(kReplaceInvalidUtf8). Embedded NUL is retained.
pub fn utf8(s: *a.Scope, allocator: std.mem.Allocator, value: c.JSValue) ![:0]u8 {
    std.debug.assert(c.JS_IsString(value));
    var length: usize = 0;
    const generation = try s.beforeAllocation();
    const raw = c.JS_ToCStringLen(s.engine.context, &length, value);
    s.boundary.checkPendingSince(generation) catch |err| {
        if (raw != null) c.JS_FreeCString(s.engine.context, raw);
        return err;
    };
    if (raw == null) return error.ActualPackageStringBytesRequired;
    defer c.JS_FreeCString(s.engine.context, raw);
    const output = allocator.allocSentinel(u8, length, 0) catch |err| {
        if (err == error.OutOfMemory) _ = s.engine.throwNativeOutOfMemoryFatal();
        return err;
    };
    errdefer allocator.free(output);
    var iterator = (try std.unicode.Wtf8View.init(raw[0..length])).iterator();
    var cursor: usize = 0;
    while (iterator.nextCodepoint()) |point| {
        const scalar: u21 = if (point >= 0xd800 and point <= 0xdfff) 0xfffd else point;
        var encoded: [4]u8 = undefined;
        const count = try std.unicode.utf8Encode(scalar, &encoded);
        @memcpy(output[cursor .. cursor + count], encoded[0..count]);
        cursor += count;
    }
    // Replacement of one WTF8 surrogate uses exactly three UTF8 bytes.
    std.debug.assert(cursor == output.len);
    return output;
}
fn text(s: *a.Scope, value: parser.PiNodePackageJsonSpan) !c.JSValue {
    if (value.present == 0) return c.pi_js_undefined();
    const bytes: [*]const u8 = @ptrCast(value.data);
    return s.text(bytes[0..value.length]);
}
/// Config/path are borrowed from the retained genuine native binding owner.
/// Array::New(elements,6) creates own dense elements without ordinary [[Set]].
pub fn serialize(s: *a.Scope, config: *const parser.PiNodePackageJsonConfig,
    path: []const u8) !c.JSValue
{
    var views: parser.PiNodePackageJsonViews = undefined;
    parser.pi_node_package_json_config_views(config, &views);
    var elements = [_]c.JSValue{
        try text(s, views.name),
        try text(s, views.main),
        try text(s, views.type),
        try text(s, views.imports),
        try text(s, views.exports),
        try s.text(path),
    };
    const generation = try s.beforeAllocation();
    // The real C ArrayFrom consumes duplicates on either allocation outcome.
    for (&elements) |*value| value.* = a.duplicate(s.engine, value.*);
    return s.checkedAllocation(c.JS_NewArrayFrom(s.engine.context,
        @intCast(elements.len), &elements), generation);
}

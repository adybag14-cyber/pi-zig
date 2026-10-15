//! Actual bundled Undici dataURLProcessor over a serialized native URL.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const mime = @import("native_web_mime.zig");
const c = em.c;
pub const Result = struct { mime_type: c.JSValue, bytes: c.JSValue };
fn whitespace(byte: u8) bool {
    return byte == 9 or byte == 10 or byte == 12 or byte == 13 or byte == 32;
}
pub fn process(scope: *Scope, serialized_url: c.JSValue) !?Result {
    const href = try scope.engine.toString(serialized_url);
    defer scope.engine.gpa.free(href);
    if (!std.mem.startsWith(u8, href, "data:")) return error.NativeWebDataUrlSchemeRequired;
    const fragment = std.mem.indexOfScalar(u8, href, '#') orelse href.len;
    const input = href[5..fragment];
    const comma = std.mem.indexOfScalar(u8, input, ',') orelse return null;
    var media_type = input[0..comma];
    while (media_type.len > 0 and whitespace(media_type[0])) media_type = media_type[1..];
    while (media_type.len > 0 and whitespace(media_type[media_type.len - 1])) media_type = media_type[0 .. media_type.len - 1];
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(scope.engine.gpa);
    var position = comma + 1;
    while (position < input.len) : (position += 1) {
        if (input[position] == '%' and position + 2 < input.len) {
            const high = std.fmt.charToDigit(input[position + 1], 16) catch {
                try bytes.append(scope.engine.gpa, '%');
                continue;
            };
            const low = std.fmt.charToDigit(input[position + 2], 16) catch {
                try bytes.append(scope.engine.gpa, '%');
                continue;
            };
            try bytes.append(scope.engine.gpa, (high << 4) | low);
            position += 2;
        } else try bytes.append(scope.engine.gpa, input[position]);
    }
    var is_base64 = false;
    if (media_type.len >= 6 and std.ascii.eqlIgnoreCase(media_type[media_type.len - 6 ..], "base64")) {
        var prefix = media_type[0 .. media_type.len - 6];
        while (prefix.len > 0 and prefix[prefix.len - 1] == 32) prefix = prefix[0 .. prefix.len - 1];
        if (prefix.len > 0 and prefix[prefix.len - 1] == ';') {
            is_base64 = true;
            media_type = prefix[0 .. prefix.len - 1];
        }
    }
    var decoded: ?[]u8 = null;
    defer if (decoded) |owned| scope.engine.gpa.free(owned);
    if (is_base64) {
        var clean: std.ArrayList(u8) = .empty;
        defer clean.deinit(scope.engine.gpa);
        for (bytes.items) |byte| if (!whitespace(byte)) {
            try clean.append(scope.engine.gpa, byte);
        };
        var length = clean.items.len;
        if (length % 4 == 0 and length != 0 and clean.items[length - 1] == '=') {
            length -= 1;
            if (length != 0 and clean.items[length - 1] == '=') length -= 1;
        }
        if (length % 4 == 1) return null;
        for (clean.items[0..length]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '+' and byte != '/') return null;
        decoded = try @import("binary_encoding.zig").encode(scope.engine.gpa, clean.items, .base64);
    }
    var type_text = try scope.text(media_type);
    if (media_type.len > 0 and media_type[0] == ';') type_text = try scope.concat(try scope.text("text/plain"), type_text);
    const record = (try mime.parse(scope, type_text)) orelse (try mime.parse(scope, try scope.text("text/plain;charset=US-ASCII"))).?;
    const output = decoded orelse bytes.items;
    return .{ .mime_type = try mime.serialize(scope, record), .bytes = try scope.own(try scope.engine.checked(c.JS_NewUint8ArrayCopy(scope.engine.context, output.ptr, output.len))) };
}

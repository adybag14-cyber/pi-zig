//! Bundled Undici multipart Body action and parser, implemented in Zig.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const web = @import("native_headers_webidl.zig");
const utf = @import("native_utf16.zig");
const flow = @import("native_agent_async.zig");
const body = @import("native_web_body.zig");
const form = @import("native_web_form_data.zig");
const c = em.c;
pub const Encoded = struct { parts: c.JSValue, length: c.JSValue, content_type: c.JSValue };
fn newline(scope: *Scope, value: c.JSValue, escape: bool) !c.JSValue {
    const units = try utf.unitsAlloc(scope.engine, value);
    defer scope.engine.gpa.free(units);
    var output: std.ArrayList(u16) = .empty;
    defer output.deinit(scope.engine.gpa);
    var position: usize = 0;
    while (position < units.len) : (position += 1) {
        const unit = units[position];
        if (unit == 13 or unit == 10) {
            if (unit == 13 and position + 1 < units.len and units[position + 1] == 10) position += 1;
            try output.appendSlice(scope.engine.gpa, if (escape) &.{ '%', '0', 'D', '%', '0', 'A' } else &.{ 13, 10 });
        } else if (escape and unit == '"') try output.appendSlice(scope.engine.gpa, &.{ '%', '2', '2' }) else try output.append(scope.engine.gpa, unit);
    }
    return scope.own(try utf.string(scope.engine, output.items));
}
fn escapeName(scope: *Scope, value: c.JSValue) !c.JSValue {
    const units = try utf.unitsAlloc(scope.engine, value);
    defer scope.engine.gpa.free(units);
    var output: std.ArrayList(u16) = .empty;
    defer output.deinit(scope.engine.gpa);
    for (units) |unit| switch (unit) {
        10 => try output.appendSlice(scope.engine.gpa, &.{ '%', '0', 'A' }),
        13 => try output.appendSlice(scope.engine.gpa, &.{ '%', '0', 'D' }),
        '"' => try output.appendSlice(scope.engine.gpa, &.{ '%', '2', '2' }),
        else => try output.append(scope.engine.gpa, unit),
    };
    return scope.own(try utf.string(scope.engine, output.items));
}
fn add(scope: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, left, right)));
}
/// Builds the synchronous snapshot of actual for-of entries. File streams are
/// intentionally deferred to the async action, retaining public stream lookup.
pub fn encode(scope: *Scope, object: c.JSValue, encoder: c.JSValue) !Encoded {
    const maximum: u64 = 100_000_000_000;
    const ceiling: u64 = 281_474_976_710_656 - (281_474_976_710_656 % maximum);
    var entropy: [6]u8 = undefined;
    var number: u64 = undefined;
    while (true) {
        try std.Io.randomSecure(scope.engine.native_io orelse return error.NativeCryptoIoRequired, &entropy);
        number = 0;
        for (entropy) |byte| number = (number << 8) | byte;
        if (number < ceiling) break;
    }
    const boundary_bytes = try std.fmt.allocPrint(scope.engine.gpa, "----formdata-undici-0{d:0>11}", .{number % maximum});
    defer scope.engine.gpa.free(boundary_bytes);
    const boundary = try scope.text(boundary_bytes);
    const prefix = try scope.concat(try scope.concat(try scope.text("--"), boundary), try scope.text("\r\nContent-Disposition: form-data"));
    const parts = try scope.array();
    const rn = try scope.own(try scope.engine.checked(c.JS_NewUint8ArrayCopy(scope.engine.context, "\r\n", 2)));
    var length = c.JS_NewInt32(scope.engine.context, 0);
    var unknown = false;
    const iterator_method = try scope.own(try js.getKey(scope.engine, object, try web.iteratorSymbol(scope)));
    const iterator = try scope.call(iterator_method, object, &.{});
    while (true) {
        const row = try scope.invoke(iterator, "next", &.{});
        if (scope.truthy(try scope.get(row, "done"))) break;
        const pair = try scope.get(row, "value");
        const name = try web.index(scope, pair, 0);
        const value = try web.index(scope, pair, 1);
        var header = try scope.concat(try scope.concat(prefix, try scope.text("; name=\"")), try newline(scope, name, true));
        header = try scope.concat(header, try scope.text("\""));
        if (c.JS_IsString(value)) {
            const bytes = try scope.invoke(encoder, "encode", &.{try scope.concat(try scope.concat(try scope.concat(header, try scope.text("\r\n\r\n")), try newline(scope, value, false)), try scope.text("\r\n"))});
            _ = try scope.invoke(parts, "push", &.{bytes});
            length = try add(scope, length, try scope.get(bytes, "byteLength"));
        } else {
            const filename = try scope.get(value, "name");
            if (scope.truthy(filename)) header = try scope.concat(try scope.concat(try scope.concat(header, try scope.text("; filename=\"")), try escapeName(scope, filename)), try scope.text("\""));
            const mime = try scope.get(value, "type");
            header = try scope.concat(try scope.concat(try scope.concat(header, try scope.text("\r\nContent-Type: ")), if (scope.truthy(mime)) mime else try scope.text("application/octet-stream")), try scope.text("\r\n\r\n"));
            const bytes = try scope.invoke(encoder, "encode", &.{header});
            _ = try scope.invoke(parts, "push", &.{ bytes, value, rn });
            const size = try scope.get(value, "size");
            if (c.JS_IsNumber(size)) length = try add(scope, length, try add(scope, try add(scope, try scope.get(bytes, "byteLength"), size), try scope.get(rn, "byteLength"))) else unknown = true;
        }
    }
    const end = try scope.invoke(encoder, "encode", &.{try scope.concat(try scope.concat(try scope.text("--"), boundary), try scope.text("--\r\n"))});
    _ = try scope.invoke(parts, "push", &.{end});
    length = try add(scope, length, try scope.get(end, "byteLength"));
    return .{ .parts = parts, .length = if (unknown) c.pi_js_null() else length, .content_type = try scope.concat(try scope.text("multipart/form-data; boundary="), boundary) };
}
fn closeJob(context: ?*c.JSContext, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    body.closeController(&scope, captures[0]) catch |err| return @import("native_sdk.zig").fail(engine, err);
    return c.pi_js_undefined();
}
fn finish(scope: *Scope, owner: c.JSValue) !void {
    var captures = [_]c.JSValue{try scope.get(owner, "controller")};
    if (c.JS_EnqueueJob(scope.engine.context, closeJob, 1, &captures) < 0) return js.capture(scope.engine);
    try flow.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn advance(scope: *Scope, owner: c.JSValue) anyerror!void {
    const delegated = try scope.get(owner, "delegate");
    if (!c.JS_IsUndefined(delegated)) return flow.wait(step, scope.engine, owner, try scope.invoke(delegated, "next", &.{}), 1);
    const parts = try scope.get(owner, "parts");
    var position: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &position, try scope.get(owner, "position")) < 0) return js.capture(scope.engine);
    if (position >= try web.count(scope, parts)) return finish(scope, owner);
    const part = try web.index(scope, parts, position);
    try scope.set(owner, "position", c.JS_NewUint32(scope.engine.context, position + 1));
    if (scope.truthy(try scope.get(part, "stream"))) {
        const stream = try scope.invoke(part, "stream", &.{});
        const symbol = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
        const method = try scope.own(try js.getKey(scope.engine, stream, symbol));
        const iterator = try scope.call(method, stream, &.{});
        try scope.set(owner, "delegate", iterator);
        return advance(scope, owner);
    }
    try flow.wait(step, scope.engine, owner, part, 0);
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return flow.settle(engine, owner, true, value);
    if (stage == 2) return finish(&scope, owner);
    if (stage == 1) {
        if (scope.truthy(try scope.get(value, "done"))) {
            try scope.set(owner, "delegate", c.pi_js_undefined());
            return advance(&scope, owner);
        }
        return flow.wait(step, engine, owner, try scope.get(value, "value"), 0);
    }
    if (try body.errored(&scope, try scope.get(owner, "stream"))) {
        const iterator = try scope.get(owner, "delegate");
        if (!c.JS_IsUndefined(iterator)) {
            const method = try scope.get(iterator, "return");
            if (!c.JS_IsUndefined(method)) return flow.wait(step, engine, owner, try scope.call(method, iterator, &.{}), 2);
        }
        return finish(&scope, owner);
    }
    if (scope.truthy(try scope.get(value, "length"))) {
        const bytes = try scope.own(try js.builtin(engine, "Uint8Array", &.{value}));
        _ = try scope.invoke(try scope.get(owner, "controller"), "enqueue", &.{bytes});
    }
    try advance(&scope, owner);
}
/// Starts the actual eager async Body action. Real stream owns queue/state;
/// this promise has the same independent error lifetime as bundled async IIFE.
pub fn start(scope: *Scope, parts: c.JSValue, stream: c.JSValue, controller: c.JSValue) !void {
    const pending = try flow.create(scope.engine, c.pi_js_undefined());
    defer scope.engine.freeValue(pending.owner);
    defer scope.engine.freeValue(pending.promise);
    try scope.set(pending.owner, "parts", parts);
    try scope.set(pending.owner, "stream", stream);
    try scope.set(pending.owner, "controller", controller);
    try scope.set(pending.owner, "position", c.JS_NewInt32(scope.engine.context, 0));
    try scope.set(pending.owner, "delegate", c.pi_js_undefined());
    advance(scope, pending.owner) catch |err| try flow.rejectError(scope.engine, pending.owner, err);
}

fn parsingError(scope: *Scope, detail: []const u8) anyerror!noreturn {
    const cause = try scope.own(try js.builtin(scope.engine, "TypeError", &.{try scope.text(detail)}));
    const options = try scope.object();
    try scope.set(options, "cause", cause);
    const failure = try scope.own(try js.builtin(scope.engine, "TypeError", &.{ try scope.text("Failed to parse body as FormData."), options }));
    _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, failure)));
    unreachable;
}
fn decoded(scope: *Scope, bytes: []const u8, bom: bool) !c.JSValue {
    const output = if (bom) try @import("text_decoder.zig").decodeUtf8(scope.engine, bytes) else try @import("binary_encoding.zig").decode(scope.engine.gpa, bytes, .utf8);
    defer scope.engine.gpa.free(output);
    return scope.text(output);
}
fn latin1(scope: *Scope, bytes: []const u8) !c.JSValue {
    const output = try @import("binary_encoding.zig").decode(scope.engine.gpa, bytes, .latin1);
    defer scope.engine.gpa.free(output);
    return scope.text(output);
}
fn isToken(byte: u8) bool {
    if (byte <= 32 or byte >= 127) return false;
    return switch (byte) {
        '(', ')', '<', '>', '@', ',', ';', ':', '\\', '"', '/', '[', ']', '?', '=' => false,
        else => true,
    };
}
const Cursor = struct {
    bytes: []const u8,
    position: usize = 0,
    fn at(self: Cursor, offset: usize) ?u8 {
        return if (self.position +| offset < self.bytes.len) self.bytes[self.position + offset] else null;
    }
    fn collect(self: *Cursor, comptime predicate: fn (u8) bool) []const u8 {
        const begin = @min(self.position, self.bytes.len);
        while (self.position < self.bytes.len and predicate(self.bytes[self.position])) : (self.position += 1) {}
        return self.bytes[begin..@min(self.position, self.bytes.len)];
    }
};
fn space(byte: u8) bool {
    return byte == 32 or byte == 9;
}
fn line(byte: u8) bool {
    return byte != 13 and byte != 10;
}
fn headerName(byte: u8) bool {
    return line(byte) and byte != ':';
}
fn attrName(byte: u8) bool {
    return isToken(byte) and byte != '*' and byte != '=';
}
fn attrExtended(byte: u8) bool {
    return byte != 32 and line(byte) and byte != ';';
}
fn attrQuoted(byte: u8) bool {
    return line(byte) and byte != '"';
}
fn attrToken(byte: u8) bool {
    return isToken(byte) and byte != ';';
}
const Attribute = struct { name: []const u8, value: c.JSValue };
fn attribute(scope: *Scope, cursor: *Cursor) !?Attribute {
    if (cursor.at(0) == ';') cursor.position += 1;
    _ = cursor.collect(space);
    const name = cursor.collect(attrName);
    if (name.len == 0) return null;
    const extended = cursor.at(0) == '*';
    if (extended) cursor.position += 1;
    if (cursor.at(0) != '=') return null;
    cursor.position += 1;
    _ = cursor.collect(space);
    var value: c.JSValue = undefined;
    if (extended) {
        const raw = cursor.collect(attrExtended);
        if (raw.len < 5 or !std.ascii.eqlIgnoreCase(raw[0..5], "utf-8")) try parsingError(scope, "unknown encoding, expected utf-8''");
        value = try scope.call(try scope.global("decodeURIComponent"), c.pi_js_undefined(), &.{try decoded(scope, raw[@min(7, raw.len)..], true)});
    } else if (cursor.at(0) == '"') {
        cursor.position += 1;
        const raw = cursor.collect(attrQuoted);
        if (cursor.at(0) != '"') try parsingError(scope, "Closing quote not found");
        cursor.position += 1;
        const original = try decoded(scope, raw, true);
        const units = try utf.unitsAlloc(scope.engine, original);
        defer scope.engine.gpa.free(units);
        var output: std.ArrayList(u16) = .empty;
        defer output.deinit(scope.engine.gpa);
        var position: usize = 0;
        while (position < units.len) : (position += 1) {
            if (position + 2 < units.len and units[position] == '%' and units[position + 1] == '0' and (units[position + 2] == 'a' or units[position + 2] == 'A' or units[position + 2] == 'd' or units[position + 2] == 'D')) {
                try output.append(scope.engine.gpa, if (units[position + 2] == 'a' or units[position + 2] == 'A') 10 else 13);
                position += 2;
            } else if (position + 2 < units.len and units[position] == '%' and units[position + 1] == '2' and units[position + 2] == '2') {
                try output.append(scope.engine.gpa, '"');
                position += 2;
            } else try output.append(scope.engine.gpa, units[position]);
        }
        value = try scope.own(try utf.string(scope.engine, output.items));
    } else value = try decoded(scope, cursor.collect(attrToken), true);
    return .{ .name = name, .value = value };
}
const Fields = struct { name: c.JSValue, filename: c.JSValue, content_type: c.JSValue, encoding: c.JSValue };
fn parseHeaders(scope: *Scope, cursor: *Cursor) !Fields {
    var result: Fields = .{ .name = c.pi_js_null(), .filename = c.pi_js_null(), .content_type = c.pi_js_null(), .encoding = c.pi_js_null() };
    while (true) {
        if (cursor.at(0) == 13 and cursor.at(1) == 10) {
            if (c.JS_IsNull(result.name)) try parsingError(scope, "header name is null");
            return result;
        }
        const name = std.mem.trim(u8, cursor.collect(headerName), " \t");
        if (name.len == 0) try parsingError(scope, "header name does not match the field-name token production");
        for (name) |byte| if (!isToken(byte) or byte == '`') try parsingError(scope, "header name does not match the field-name token production");
        if (cursor.at(0) != ':') try parsingError(scope, "expected :");
        cursor.position += 1;
        _ = cursor.collect(space);
        if (std.ascii.eqlIgnoreCase(name, "content-disposition")) {
            result.name = c.pi_js_null();
            result.filename = c.pi_js_null();
            if (!std.ascii.eqlIgnoreCase(cursor.collect(isToken), "form-data")) try parsingError(scope, "expected form-data for content-disposition header");
            while (cursor.position < cursor.bytes.len and cursor.at(0) != 13 and cursor.at(1) != 10) {
                const attr = (try attribute(scope, cursor)) orelse break;
                if (std.ascii.eqlIgnoreCase(attr.name, "name")) result.name = attr.value else if (std.ascii.eqlIgnoreCase(attr.name, "filename")) result.filename = attr.value;
            }
            if (c.JS_IsNull(result.name)) try parsingError(scope, "name attribute is required in content-disposition header");
        } else if (std.ascii.eqlIgnoreCase(name, "content-type")) result.content_type = try latin1(scope, std.mem.trimEnd(u8, cursor.collect(line), " \t")) else if (std.ascii.eqlIgnoreCase(name, "content-transfer-encoding")) result.encoding = try latin1(scope, std.mem.trimEnd(u8, cursor.collect(line), " \t")) else _ = cursor.collect(line);
        // Preserve bundled Source's conjunction rather than tightening it.
        if (cursor.at(0) != 13 and cursor.at(1) != 10) try parsingError(scope, "expected CRLF");
        cursor.position += 2;
    }
}
pub fn parse(scope: *Scope, input: []const u8, mime: c.JSValue) !c.JSValue {
    const boundary_value = try scope.invoke(try scope.get(mime, "parameters"), "get", &.{try scope.text("boundary")});
    if (c.JS_IsUndefined(boundary_value)) try parsingError(scope, "missing boundary in content-type header");
    const boundary_text = try scope.concat(try scope.text("--"), boundary_value);
    const boundary = try scope.engine.toString(boundary_text);
    defer scope.engine.gpa.free(boundary);
    var cursor: Cursor = .{ .bytes = input, .position = std.mem.indexOf(u8, input, boundary) orelse {
        try parsingError(scope, "no boundary found in multipart body");
    } };
    const output = try scope.own(try form.create(scope.engine));
    while (true) {
        if (cursor.position > input.len or !std.mem.startsWith(u8, input[cursor.position..], boundary)) try parsingError(scope, "expected a value starting with -- and the boundary");
        cursor.position += boundary.len;
        if (cursor.at(0) == '-' and cursor.at(1) == '-') return output;
        if (cursor.at(0) != 13 or cursor.at(1) != 10) try parsingError(scope, "expected CRLF");
        cursor.position += 2;
        var fields = try parseHeaders(scope, &cursor);
        cursor.position += 2;
        const boundary_index = std.mem.indexOfPos(u8, input, @min(cursor.position, input.len), boundary[2..]) orelse {
            try parsingError(scope, "expected boundary after body");
        };
        const end = if (boundary_index >= 4) boundary_index - 4 else input.len - @min(input.len, 4 - boundary_index);
        var bytes = input[@min(cursor.position, input.len)..@max(@min(cursor.position, input.len), @min(end, input.len))];
        cursor.position += bytes.len;
        var decoded_base64: ?[]u8 = null;
        defer if (decoded_base64) |allocated| scope.engine.gpa.free(allocated);
        if (scope.equal(fields.encoding, try scope.text("base64"))) {
            const string = try decoded(scope, bytes, false);
            const encoded = try scope.engine.toString(string);
            defer scope.engine.gpa.free(encoded);
            decoded_base64 = try @import("binary_encoding.zig").encode(scope.engine.gpa, encoded, .base64);
            bytes = decoded_base64.?;
        }
        if (cursor.at(0) != 13 or cursor.at(1) != 10) try parsingError(scope, "expected CRLF");
        cursor.position += 2;
        var value: c.JSValue = undefined;
        if (!c.JS_IsNull(fields.filename)) {
            if (c.JS_IsNull(fields.content_type)) fields.content_type = try scope.text("text/plain");
            const units = try utf.unitsAlloc(scope.engine, fields.content_type);
            defer scope.engine.gpa.free(units);
            for (units) |unit| if (unit > 127) {
                fields.content_type = try scope.text("");
                break;
            };
            const raw = try scope.own(try scope.engine.checked(c.JS_NewUint8ArrayCopy(scope.engine.context, bytes.ptr, bytes.len)));
            const parts = try scope.array();
            try scope.index(parts, 0, raw);
            const options = try scope.object();
            try scope.set(options, "type", fields.content_type);
            var args = [_]c.JSValue{ parts, fields.filename, options };
            value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("File"), args.len, &args)));
        } else value = try decoded(scope, bytes, true);
        try form.appendParsedEntry(scope, output, fields.name, value, if (c.JS_IsNull(fields.filename)) c.pi_js_undefined() else fields.filename);
    }
}

//! Incremental AWS EventStream framing, CRC validation and Converse union decode.
//! Pending wire storage is an ArrayBuffer retained in the JS continuation graph.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const maximum_frame_bytes = 16 * 1024 * 1024;
fn read32(input: []const u8) u32 {
    return std.mem.readInt(u32, input[0..4], .big);
}
pub fn bytes(s: *Scope, value: c.JSValue) ![]const u8 {
    var offset: usize = 0;
    var length: usize = 0;
    var element: usize = 0;
    const backing = try s.own(try s.engine.checked(c.JS_GetTypedArrayBuffer(s.engine.context, value, &offset, &length, &element)));
    var total: usize = 0;
    const pointer = c.JS_GetArrayBuffer(s.engine.context, &total, backing);
    if (pointer == null or offset > total or length > total - offset) return error.InvalidBedrockBytes;
    return pointer[offset..][0..length];
}
fn buffer(s: *Scope, value: c.JSValue) ![]const u8 {
    if (v.nullish(value)) return &.{};
    var size: usize = 0;
    const pointer = c.JS_GetArrayBuffer(s.engine.context, &size, value);
    if (pointer == null and size != 0) return error.InvalidBedrockBytes;
    return if (size == 0) &.{} else pointer[0..size];
}
fn stringHeader(headers: []const u8, wanted: []const u8) !?[]const u8 {
    var i: usize = 0;
    while (i < headers.len) {
        const length: usize = headers[i];
        i += 1;
        if (length > headers.len - i or headers.len - i - length < 1) return error.InvalidBedrockEventHeaders;
        const name = headers[i..][0..length];
        i += length;
        const typ = headers[i];
        i += 1;
        const value_length: usize = switch (typ) {
            0, 1 => 0,
            2 => 1,
            3 => 2,
            4 => 4,
            5, 8 => 8,
            9 => 16,
            6, 7 => blk: {
                if (headers.len - i < 2) return error.InvalidBedrockEventHeaders;
                const n = std.mem.readInt(u16, headers[i..][0..2], .big);
                i += 2;
                break :blk n;
            },
            else => return error.InvalidBedrockEventHeaders,
        };
        if (value_length > headers.len - i) return error.InvalidBedrockEventHeaders;
        const value = headers[i..][0..value_length];
        i += value_length;
        if (std.mem.eql(u8, name, wanted)) {
            if (typ != 7) return error.InvalidBedrockEventHeaders;
            return value;
        }
    }
    return null;
}
pub fn decode(s: *Scope, value: c.JSValue) !c.JSValue {
    const frame = try buffer(s, value);
    try validateFrame(frame);
    return deserialize(s, value);
}
pub fn validate(s: *Scope, value: c.JSValue) !void {
    return validateFrame(try buffer(s, value));
}
fn validateFrame(frame: []const u8) !void {
    if (frame.len < 16 or read32(frame[0..4]) != frame.len) return error.InvalidBedrockEventFrame;
    const headers_length = read32(frame[4..8]);
    if (headers_length > frame.len - 16) return error.InvalidBedrockEventFrame;
    if (std.hash.Crc32.hash(frame[0..8]) != read32(frame[8..12])) return error.BedrockPreludeCrcMismatch;
    if (std.hash.Crc32.hash(frame[0 .. frame.len - 4]) != read32(frame[frame.len - 4 ..])) return error.BedrockMessageCrcMismatch;
}
pub fn deserialize(s: *Scope, value: c.JSValue) !c.JSValue {
    const frame = try buffer(s, value);
    const headers_length = read32(frame[4..8]);
    const headers = frame[12..][0..headers_length];
    const payload = frame[12 + headers_length .. frame.len - 4];
    const typ = (try stringHeader(headers, ":event-type")) orelse (try stringHeader(headers, ":exception-type")) orelse (try stringHeader(headers, ":error-code")) orelse return error.MissingBedrockEventType;
    const message_type = (try stringHeader(headers, ":message-type")) orelse "event";
    const key = try s.text(typ);
    if (std.mem.eql(u8, message_type, "error")) {
        const message = (try stringHeader(headers, ":error-message")) orelse typ;
        const exception = try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text(message)}));
        try s.set(exception, "name", key);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, exception)));
        unreachable;
    }
    const json = try s.invoke(try s.global("JSON"), "parse", &.{try s.text(payload)});
    const item = try s.object();
    if (std.mem.eql(u8, message_type, "exception")) {
        const exception = try serviceError(s, typ, json);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, exception)));
        unreachable;
    }
    const modeled = try modelJson(s, typ, json);
    try v.js.setKey(s.engine, item, key, modeled);
    return item;
}
pub fn readBody(s: *Scope, typ: []const u8, body: c.JSValue) !c.JSValue {
    const payload = try bytes(s, body);
    const json = if (payload.len == 0) try s.object() else try s.invoke(try s.global("JSON"), "parse", &.{try s.text(payload)});
    return modelJson(s, typ, json);
}
pub fn modeledType(typ: []const u8) bool {
    inline for (.{ "messageStart", "contentBlockStart", "contentBlockDelta", "contentBlockStop", "messageStop", "metadata", "internalServerException", "modelStreamErrorException", "validationException", "throttlingException", "serviceUnavailableException" }) |name| if (std.mem.eql(u8, typ, name)) return true;
    return false;
}
pub fn modelJson(s: *Scope, typ: []const u8, json: c.JSValue) !c.JSValue {
    // Smithy's runtime schema determines modeled property order and drops
    // unknown JSON members before exposing events to provider callbacks.
    const modeled = if (std.mem.eql(u8, typ, "contentBlockDelta")) blk: {
        const output = try pick(s, json, &.{ "delta", "contentBlockIndex" });
        const delta = try v.optional(s, output, "delta");
        if (!v.nullish(delta)) {
            const next = try pick(s, delta, &.{ "text", "toolUse", "toolResult", "reasoningContent", "citation", "image" });
            const reasoning = try v.optional(s, next, "reasoningContent");
            if (!v.nullish(reasoning)) try s.set(next, "reasoningContent", try pick(s, reasoning, &.{ "text", "redactedContent", "signature" }));
            try s.set(output, "delta", next);
        }
        break :blk output;
    } else if (std.mem.eql(u8, typ, "contentBlockStart")) try pick(s, json, &.{ "start", "contentBlockIndex" }) else if (std.mem.eql(u8, typ, "metadata")) blk: {
        const output = try pick(s, json, &.{ "usage", "metrics", "trace", "performanceConfig", "serviceTier" });
        const usage = try v.optional(s, output, "usage");
        if (!v.nullish(usage)) try s.set(output, "usage", try pick(s, usage, &.{ "inputTokens", "outputTokens", "totalTokens", "cacheReadInputTokens", "cacheWriteInputTokens", "cacheDetails" }));
        break :blk output;
    } else if (std.mem.eql(u8, typ, "messageStart")) try pick(s, json, &.{"role"}) else if (std.mem.eql(u8, typ, "contentBlockStop")) try pick(s, json, &.{"contentBlockIndex"}) else if (std.mem.eql(u8, typ, "messageStop")) try pick(s, json, &.{ "stopReason", "additionalModelResponseFields" }) else json;
    // Smithy's blob decoder exposes Uint8Array to the provider event callback.
    if (std.mem.eql(u8, typ, "contentBlockDelta")) {
        const reasoning = try v.optional(s, try s.get(modeled, "delta"), "reasoningContent");
        const encoded = try v.optional(s, reasoning, "redactedContent");
        if (!v.nullish(encoded)) try s.set(reasoning, "redactedContent", try @import("native_ai_bedrock_messages.zig").bytes(s, encoded));
    }
    return modeled;
}
/// The synchronous codec result yielded by MessageDecoderStream. Both
/// headers and body are actual guest objects retained by the next layer.
pub fn codec(s: *Scope, value: c.JSValue) !c.JSValue {
    var offset: usize = 0;
    var length: usize = 0;
    var element: usize = 0;
    const backing = try s.own(try s.engine.checked(c.JS_GetTypedArrayBuffer(s.engine.context, value, &offset, &length, &element)));
    const complete = try buffer(s, backing);
    if (offset > complete.len or length > complete.len - offset) return error.InvalidBedrockBytes;
    const frame = complete[offset..][0..length];
    try validateFrame(frame);
    const header_length: usize = read32(frame[4..8]);
    const raw = frame[12..][0..header_length];
    const headers = try s.object();
    var position: usize = 0;
    while (position < raw.len) {
        const name_length: usize = raw[position];
        position += 1;
        if (name_length >= raw.len - position) return error.InvalidBedrockEventHeaders;
        const name = raw[position..][0..name_length];
        position += name_length;
        const typ = raw[position];
        position += 1;
        const size: usize = switch (typ) {
            0, 1 => 0,
            2 => 1,
            3 => 2,
            4 => 4,
            5, 8 => 8,
            9 => 16,
            6, 7 => size: {
                if (raw.len - position < 2) return error.InvalidBedrockEventHeaders;
                const count = std.mem.readInt(u16, raw[position..][0..2], .big);
                position += 2;
                break :size count;
            },
            else => return error.InvalidBedrockEventHeaders,
        };
        if (size > raw.len - position) return error.InvalidBedrockEventHeaders;
        const data = raw[position..][0..size];
        position += size;
        const header = try s.object();
        const tag: []const u8 = switch (typ) {
            0, 1 => "boolean",
            2 => "byte",
            3 => "short",
            4 => "integer",
            5 => "long",
            6 => "binary",
            7 => "string",
            8 => "timestamp",
            9 => "uuid",
            else => unreachable,
        };
        try s.put(header, "type", try s.text(tag));
        const decoded = switch (typ) {
            0, 1 => c.pi_js_bool(s.engine.context, @intFromBool(typ == 0)),
            2 => c.JS_NewInt32(s.engine.context, @as(i8, @bitCast(data[0]))),
            3 => c.JS_NewInt32(s.engine.context, std.mem.readInt(i16, data[0..2], .big)),
            4 => c.JS_NewInt32(s.engine.context, std.mem.readInt(i32, data[0..4], .big)),
            5 => try int64(s, data[0..8].*),
            6 => try view(s, backing, offset + 12 + position - size, size),
            7 => try s.text(data),
            8 => try s.own(try v.js.builtin(s.engine, "Date", &.{c.JS_NewFloat64(s.engine.context, @floatFromInt(std.mem.readInt(i64, data[0..8], .big)))})),
            9 => uuid: {
                const hex = std.fmt.bytesToHex(data[0..16].*, .lower);
                const text = try std.fmt.allocPrint(s.engine.gpa, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
                defer s.engine.gpa.free(text);
                break :uuid try s.text(text);
            },
            else => unreachable,
        };
        try s.put(header, "value", decoded);
        try v.js.setKey(s.engine, headers, try s.text(name), header);
    }
    const message = try s.object();
    try s.put(message, "headers", headers);
    try s.put(message, "body", try view(s, backing, offset + 12 + header_length, frame.len - header_length - 16));
    return message;
}
fn view(s: *Scope, backing: c.JSValue, offset: usize, length: usize) !c.JSValue {
    return s.own(try v.js.builtin(s.engine, "Uint8Array", &.{ backing, c.JS_NewFloat64(s.engine.context, @floatFromInt(offset)), c.JS_NewFloat64(s.engine.context, @floatFromInt(length)) }));
}
fn int64(s: *Scope, data: [8]u8) !c.JSValue {
    const object = try s.object();
    const backing = try s.own(try s.engine.checked(c.JS_NewArrayBufferCopy(s.engine.context, &data, data.len)));
    try s.put(object, "bytes", try view(s, backing, 0, data.len));
    try s.put(object, "valueOf", try s.own(try @import("native_node_function.zig").create(s.engine, "valueOf", 0, longNumber, &.{})));
    try s.put(object, "toString", try s.own(try @import("native_node_function.zig").create(s.engine, "toString", 0, longString, &.{})));
    return object;
}
fn longNumber(engine: *v.em.Engine, this: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = try bytes(&s, try s.get(this, "bytes"));
    if (data.len != 8) return error.InvalidBedrockInt64;
    return c.JS_NewFloat64(engine.context, @floatFromInt(std.mem.readInt(i64, data[0..8], .big)));
}
fn longString(engine: *v.em.Engine, this: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = try bytes(&s, try s.get(this, "bytes"));
    if (data.len != 8) return error.InvalidBedrockInt64;
    const text = try std.fmt.allocPrint(engine.gpa, "{d}", .{std.mem.readInt(i64, data[0..8], .big)});
    defer engine.gpa.free(text);
    return c.JS_DupValue(engine.context, try s.text(text));
}
/// Append raw transport bytes without inspecting a following message. The
/// chunk/frame generator calls take only when its actual queue requests next.
pub fn append(s: *Scope, state: c.JSValue, chunk: c.JSValue) !void {
    const old = try buffer(s, try s.get(state, "pendingBytes"));
    const incoming = try bytes(s, chunk);
    if (incoming.len > maximum_frame_bytes or old.len > maximum_frame_bytes - incoming.len) return error.BedrockEventFrameTooLarge;
    const combined = try s.engine.gpa.alloc(u8, old.len + incoming.len);
    defer s.engine.gpa.free(combined);
    @memcpy(combined[0..old.len], old);
    @memcpy(combined[old.len..], incoming);
    try s.set(state, "pendingBytes", try s.own(try s.engine.checked(c.JS_NewArrayBufferCopy(s.engine.context, combined.ptr, combined.len))));
}
pub fn take(s: *Scope, state: c.JSValue) !c.JSValue {
    const pending = try buffer(s, try s.get(state, "pendingBytes"));
    if (pending.len < 4) return c.pi_js_undefined();
    const total: usize = read32(pending[0..4]);
    if (total < 16 or total > maximum_frame_bytes) return error.InvalidBedrockEventFrame;
    if (pending.len < total) return c.pi_js_undefined();
    const frame = try s.own(try s.engine.checked(c.JS_NewArrayBufferCopy(s.engine.context, pending.ptr, total)));
    const rest = pending[total..];
    try s.set(state, "pendingBytes", try s.own(try s.engine.checked(c.JS_NewArrayBufferCopy(s.engine.context, rest.ptr, rest.len))));
    return frame;
}
fn pick(s: *Scope, input: c.JSValue, keys: []const [*:0]const u8) !c.JSValue {
    const output = try s.object();
    for (keys) |key| {
        const value = try v.optional(s, input, key);
        if (!v.nullish(value)) try s.put(output, key, value);
    }
    return output;
}
pub fn serviceError(s: *Scope, typ: []const u8, json: c.JSValue) !c.JSValue {
    const name = try s.engine.gpa.dupe(u8, typ);
    defer s.engine.gpa.free(name);
    if (name.len != 0) name[0] = std.ascii.toUpper(name[0]);
    const lower = try v.optional(s, json, "message");
    const upper = try v.optional(s, json, "Message");
    const message = if (s.truthy(lower)) lower else if (s.truthy(upper)) upper else try s.text("UnknownError");
    const exception = try s.own(try v.js.builtin(s.engine, "Error", &.{message}));
    try s.set(exception, "name", try s.text(name));
    try s.put(exception, "__bedrockServiceException", c.pi_js_bool(s.engine.context, 1));
    return exception;
}
pub fn feed(s: *Scope, state: c.JSValue, chunk: c.JSValue) !c.JSValue {
    const old = try buffer(s, try s.get(state, "pendingBytes"));
    const incoming = try bytes(s, chunk);
    if (incoming.len > maximum_frame_bytes or old.len > maximum_frame_bytes - incoming.len) return error.BedrockEventFrameTooLarge;
    const combined = try s.engine.gpa.alloc(u8, old.len + incoming.len);
    defer s.engine.gpa.free(combined);
    @memcpy(combined[0..old.len], old);
    @memcpy(combined[old.len..], incoming);
    const events = try s.array();
    var offset: usize = 0;
    while (combined.len - offset >= 12) {
        const total: usize = read32(combined[offset..][0..4]);
        if (total < 16 or total > maximum_frame_bytes) return error.InvalidBedrockEventFrame;
        if (combined.len - offset < total) break;
        var row: Scope = .{ .engine = s.engine };
        defer row.deinit();
        const frame = combined[offset..][0..total];
        _ = try row.invoke(events, "push", &.{try row.own(try s.engine.checked(c.JS_NewArrayBufferCopy(s.engine.context, frame.ptr, frame.len)))});
        offset += total;
    }
    const remaining = combined[offset..];
    try s.set(state, "pendingBytes", try s.own(try s.engine.checked(c.JS_NewArrayBufferCopy(s.engine.context, remaining.ptr, remaining.len))));
    return events;
}
pub fn finish(s: *Scope, state: c.JSValue) !void {
    if ((try buffer(s, try s.get(state, "pendingBytes"))).len != 0) return error.TruncatedBedrockEventStream;
}

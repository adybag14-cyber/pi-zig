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
    const headers_length = read32(frame[4..8]);
    if (headers_length > frame.len - 16) return error.InvalidBedrockEventFrame;
    if (std.hash.Crc32.hash(frame[0..8]) != read32(frame[8..12])) return error.BedrockPreludeCrcMismatch;
    if (std.hash.Crc32.hash(frame[0 .. frame.len - 4]) != read32(frame[frame.len - 4 ..])) return error.BedrockMessageCrcMismatch;
    const headers = frame[12..][0..headers_length];
    const payload = frame[12 + headers_length .. frame.len - 4];
    const typ = (try stringHeader(headers, ":event-type")) orelse (try stringHeader(headers, ":exception-type")) orelse (try stringHeader(headers, ":error-code")) orelse return error.MissingBedrockEventType;
    const message_type = (try stringHeader(headers, ":message-type")) orelse "event";
    const json = try s.invoke(try s.global("JSON"), "parse", &.{try s.text(payload)});
    const item = try s.object();
    const key = try s.text(typ);
    if (std.mem.eql(u8, message_type, "error")) {
        const message = (try stringHeader(headers, ":error-message")) orelse typ;
        const exception = try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text(message)}));
        try s.set(exception, "name", key);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, exception)));
        unreachable;
    }
    if (std.mem.eql(u8, message_type, "exception")) {
        const exception = try serviceError(s, typ, json);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, exception)));
        unreachable;
    }
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
    } else json;
    // Smithy's blob decoder exposes Uint8Array to the provider event callback.
    if (std.mem.eql(u8, typ, "contentBlockDelta")) {
        const reasoning = try v.optional(s, try s.get(modeled, "delta"), "reasoningContent");
        const encoded = try v.optional(s, reasoning, "redactedContent");
        if (!v.nullish(encoded)) try s.set(reasoning, "redactedContent", try @import("native_ai_bedrock_messages.zig").bytes(s, encoded));
    }
    try v.js.setKey(s.engine, item, key, modeled);
    return item;
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
    var name = try s.engine.gpa.dupe(u8, typ);
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

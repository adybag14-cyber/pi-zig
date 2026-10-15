const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const fixture = @import("ai/http_fixture.zig");
fn appendHeader(a: std.mem.Allocator, output: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
    try output.append(a, @intCast(name.len));
    try output.appendSlice(a, name);
    try output.append(a, 7);
    var length: [2]u8 = undefined;
    std.mem.writeInt(u16, &length, @intCast(value.len), .big);
    try output.appendSlice(a, &length);
    try output.appendSlice(a, value);
}
fn frames(a: std.mem.Allocator, events: std.json.Value) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(a);
    for (events.array.items) |event| {
        var entries = event.object.iterator();
        const first = entries.next().?;
        const typ = first.key_ptr.*;
        const exception = std.mem.endsWith(u8, typ, "Exception");
        var headers: std.ArrayList(u8) = .empty;
        defer headers.deinit(a);
        try appendHeader(a, &headers, ":message-type", if (exception) "exception" else "event");
        try appendHeader(a, &headers, if (exception) ":exception-type" else ":event-type", typ);
        try appendHeader(a, &headers, ":content-type", "application/json");
        const payload = try std.json.Stringify.valueAlloc(a, first.value_ptr.*, .{});
        defer a.free(payload);
        var prelude: [12]u8 = undefined;
        std.mem.writeInt(u32, prelude[0..4], @intCast(16 + headers.items.len + payload.len), .big);
        std.mem.writeInt(u32, prelude[4..8], @intCast(headers.items.len), .big);
        std.mem.writeInt(u32, prelude[8..12], std.hash.Crc32.hash(prelude[0..8]), .big);
        const offset = output.items.len;
        try output.appendSlice(a, &prelude);
        try output.appendSlice(a, headers.items);
        try output.appendSlice(a, payload);
        var checksum: [4]u8 = undefined;
        std.mem.writeInt(u32, &checksum, std.hash.Crc32.hash(output.items[offset..]), .big);
        try output.appendSlice(a, &checksum);
    }
    return output.toOwnedSlice(a);
}
fn parse(engine: *v.em.Engine, value: std.json.Value) !c.JSValue {
    const bytes = try std.json.Stringify.valueAlloc(engine.gpa, value, .{});
    defer engine.gpa.free(bytes);
    const terminated = try engine.gpa.dupeZ(u8, bytes);
    defer engine.gpa.free(terminated);
    return engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, bytes.len, "bedrock-source-fixture.json"));
}
test "native AI Bedrock wire keeps seven-byte frame fragments and rejects altered message CRC" {
    const a = std.testing.allocator;
    const input = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-bedrock14-5ab.input.json"), .{});
    defer input.deinit();
    const events = input.value.array.items[0].object.get("events").?;
    const body = try frames(a, events);
    defer a.free(body);
    const engine = try v.em.Engine.init(a, .{});
    defer engine.deinit();
    var s: v.Scope = .{ .engine = engine };
    defer s.deinit();
    const owner = try s.object();
    var decoded: usize = 0;
    var offset: usize = 0;
    const wire = @import("extensions/native_ai_bedrock_wire.zig");
    while (offset < body.len) : (offset += @min(7, body.len - offset)) {
        var row: v.Scope = .{ .engine = engine };
        defer row.deinit();
        const bytes = body[offset..][0..@min(7, body.len - offset)];
        const backing = try row.own(try engine.checked(c.JS_NewArrayBufferCopy(engine.context, bytes.ptr, bytes.len)));
        const chunk = try row.own(try v.js.builtin(engine, "Uint8Array", &.{backing}));
        const queue = try wire.feed(&row, owner, chunk);
        const n = try v.length(&row, queue);
        for (0..n) |i| {
            _ = try wire.decode(&row, try v.at(&row, queue, @intCast(i)));
            decoded += 1;
        }
    }
    try wire.finish(&s, owner);
    try std.testing.expectEqual(events.array.items.len, decoded);
    body[body.len - 1] ^= 1;
    const backing = try s.own(try engine.checked(c.JS_NewArrayBufferCopy(engine.context, body.ptr, body.len)));
    const chunk = try s.own(try v.js.builtin(engine, "Uint8Array", &.{backing}));
    const queue = try wire.feed(&s, owner, chunk);
    const last = try v.at(&s, queue, (try v.length(&s, queue)) - 1);
    try std.testing.expectError(error.BedrockMessageCrcMismatch, wire.decode(&s, last));
}
test "native AI Bedrock actual facade matches14 genuine Source5ab SDK request callback event and result traces" {
    const a = std.testing.allocator;
    const input = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-bedrock14-5ab.input.json"), .{});
    defer input.deinit();
    const source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-bedrock14-5ab.json"), .{});
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqualStrings("5ab7fe74c400097b386662205cd93900695b8a71", source.value.object.get("sourceHead").?.string);
    try std.testing.expectEqual(@as(usize, 14), input.value.array.items.len);
    try std.testing.expectEqual(@as(usize, 14), rows.len);
    for (input.value.array.items, rows, 0..) |case, row, index| {
        const http_error = case.object.get("httpError");
        const body = if (http_error) |value| try a.dupe(u8, value.object.get("body").?.string) else try frames(a, case.object.get("events").?);
        defer a.free(body);
        const path = row.object.get("request").?.object.get("path").?.string;
        var expected_headers: std.ArrayList(std.http.Header) = .empty;
        defer expected_headers.deinit(a);
        var observed_headers = row.object.get("request").?.object.get("headers").?.object.iterator();
        while (observed_headers.next()) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, "authorization")) {
                // Source14 retained auth presence only. Preserve that scope and
                // independently assert the fake fixture's actual native token.
                try std.testing.expectEqualStrings("[fixture auth]", entry.value_ptr.string);
                try expected_headers.append(a, .{ .name = "authorization", .value = "Bearer fixture-placeholder-bearer" });
            } else try expected_headers.append(a, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
        }
        const server = try fixture.PlanServer.init(a, std.testing.io, &.{.{ .path = path, .body = body, .content_type = if (http_error != null) "application/json" else "application/vnd.amazon.eventstream", .status = if (http_error) |value| @enumFromInt(value.object.get("status").?.integer) else .ok, .headers = &.{ .{ .name = "x-amzn-requestid", .value = "fixture-request-id" }, .{ .name = "x-fixture-response", .value = "raw-gateway" } }, .expected_request_headers = expected_headers.items }});
        defer server.deinit();
        const endpoint = try server.url(a, "");
        defer a.free(endpoint);
        const engine = try v.em.Engine.init(a, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        var s: v.Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(global, "bedrockAPI", try s.own(try @import("extensions/native_ai_bedrock_factory.zig").create(engine)));
        try s.put(global, "bedrockInput", try s.own(try parse(engine, case)));
        try s.put(global, "bedrockSourceRow", try s.own(try parse(engine, row)));
        try s.put(global, "bedrockEndpoint", try s.text(endpoint));
        const actual = engine.evalModule(@embedFile("extensions/fixtures/ai-bedrock14-5ab.input.txt"), "native-bedrock14-source5ab.mjs") catch |err| {
            std.debug.print("Bedrock Source14 case {d}: {s}\n", .{ index, engine.last_error orelse "no diagnostic" });
            return err;
        };
        engine.freeValue(actual);
        try server.finish();
        try std.testing.expectEqual(@as(usize, 1), server.captured.items.len);
        const request = server.captured.items[0];
        const request_terminated = try a.dupeZ(u8, request.payload);
        defer a.free(request_terminated);
        const request_value = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, request_terminated.ptr, request.payload.len, "captured-bedrock-request.json")));
        const expected = try s.get(try s.get(try s.get(global, "bedrockSourceRow"), "request"), "body");
        const actual_json = try engine.stringify(request_value);
        defer a.free(actual_json);
        const expected_json = try engine.stringify(expected);
        defer a.free(expected_json);
        try std.testing.expectEqualStrings(expected_json, actual_json);
        c.JS_RunGC(engine.runtime);
    }
}

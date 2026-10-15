//! Source18 is a separate genuine capture; Source14 and its native negative stay intact.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const fixture = @import("ai/http_fixture.zig");
const shared = @import("native_ai_bedrock_test.zig");
test "native AI Bedrock18 exact Source SDK method URL path body auth hooks and streamSimple traces" {
    const a = std.testing.allocator;
    const input = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-bedrock18-5ab.input.json"), .{});
    defer input.deinit();
    const source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-bedrock18-5ab.json"), .{});
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqualStrings("5ab7fe74c400097b386662205cd93900695b8a71", source.value.object.get("sourceHead").?.string);
    try std.testing.expectEqual(@as(usize, 18), input.value.array.items.len);
    try std.testing.expectEqual(@as(usize, 18), rows.len);
    for (input.value.array.items, rows, 0..) |case, row, index| {
        const observed = row.object.get("requests").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), observed.len);
        const request = observed[0];
        const path = request.object.get("path").?.string;
        const source_url = request.object.get("url").?.string;
        // Validate the genuinely observed URL and target, then rebind only its
        // origin. Do not author a model route or remove a captured query string.
        const scheme = std.mem.indexOf(u8, source_url, "://") orelse return error.InvalidSourceUrl;
        const path_offset = std.mem.indexOfScalarPos(u8, source_url, scheme + 3, '/') orelse return error.InvalidSourceUrl;
        try std.testing.expectEqualStrings(path, source_url[path_offset..]);
        var expected_headers: std.ArrayList(std.http.Header) = .empty;
        defer expected_headers.deinit(a);
        var headers = request.object.get("headers").?.object.iterator();
        while (headers.next()) |entry| try expected_headers.append(a, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
        const http_error = case.object.get("httpError");
        const body = if (http_error) |value| try a.dupe(u8, value.object.get("body").?.string) else try shared.frames(a, case.object.get("events").?);
        defer a.free(body);
        const server = try fixture.PlanServer.init(a, std.testing.io, &.{.{ .path = path, .body = body, .content_type = if (http_error != null) "application/json" else "application/vnd.amazon.eventstream", .status = if (http_error) |value| @enumFromInt(value.object.get("status").?.integer) else .ok, .headers = &.{ .{ .name = "x-amzn-requestid", .value = "fixture-request-id" }, .{ .name = "x-fixture-response", .value = "raw-gateway" } }, .expected_request_headers = expected_headers.items }});
        defer server.deinit();
        const endpoint = try server.url(a, "");
        defer a.free(endpoint);
        const rebound = try std.fmt.allocPrint(a, "{s}{s}", .{ endpoint, source_url[path_offset..] });
        defer a.free(rebound);
        const engine = try v.em.Engine.init(a, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        var s: v.Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(global, "bedrockAPI", try s.own(try @import("extensions/native_ai_bedrock_factory.zig").create(engine)));
        try s.put(global, "bedrockInput", try s.own(try shared.parse(engine, case)));
        try s.put(global, "bedrockSourceRow", try s.own(try shared.parse(engine, row)));
        try s.put(global, "bedrockEndpoint", try s.text(endpoint));
        const actual = engine.evalModule(@embedFile("extensions/fixtures/ai-bedrock18-5ab.input.txt"), "native-bedrock18-source5ab.mjs") catch |err| {
            std.debug.print("Bedrock Source18 case {d}: {s}\n", .{ index, engine.last_error orelse "no diagnostic" });
            return err;
        };
        engine.freeValue(actual);
        try server.finish();
        try std.testing.expectEqual(@as(usize, 1), server.captured.items.len);
        const captured = server.captured.items[0];
        try std.testing.expectEqualStrings(request.object.get("method").?.string, @tagName(captured.method));
        try std.testing.expectEqualStrings(path, captured.path);
        const actual_url = try std.fmt.allocPrint(a, "{s}{s}", .{ endpoint, captured.path });
        defer a.free(actual_url);
        try std.testing.expectEqualStrings(rebound, actual_url);
        const payload_z = try a.dupeZ(u8, captured.payload);
        defer a.free(payload_z);
        const payload_value = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, payload_z.ptr, captured.payload.len, "captured-bedrock18-request.json")));
        const expected = try s.get(try v.at(&s, try s.get(try s.get(global, "bedrockSourceRow"), "requests"), 0), "body");
        const actual_json = try engine.stringify(payload_value);
        defer a.free(actual_json);
        const expected_json = try engine.stringify(expected);
        defer a.free(expected_json);
        try std.testing.expectEqualStrings(expected_json, actual_json);
        c.JS_RunGC(engine.runtime);
    }
}

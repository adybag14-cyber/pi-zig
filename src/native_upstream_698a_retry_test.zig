//! Genuine Source698 classifier replay; no authored expected classifications.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const ordinary = @import("extensions/native_node_function.zig");
const classifier = @import("extensions/native_ai_error_classification.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
const source_bytes = @embedFile("extensions/fixtures/upstream-698a-retry-source160.json");
const caller = @embedFile("extensions/fixtures/upstream-698a-retry-source160.input.mjs");
const source_head = "698a2d23b86a5045dd54554354a5e0cb7e466795";
const source_tree = "495eca20433379a8cdd995e53c31278d72886c2b";

fn retryable(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(try classifier.retryable(engine, if (args.len > 0) args[0] else c.pi_js_undefined())));
}
fn verifySource(source: std.json.Value) !void {
    try std.testing.expectEqualStrings(source_head, try json.asString(try json.required(source, "sourceHead")));
    try std.testing.expectEqualStrings(source_tree, try json.asString(try json.required(source, "sourceTree")));
    try std.testing.expectEqualStrings("v24.14.0", try json.asString(try json.required(try json.required(source, "actualNode"), "version")));
    try std.testing.expectEqualStrings("D7ACFF8DC7F0EEE04ECB116A79FBB8331337D9F091A0CEEE775D623D7478D448", try json.asString(try json.required(source, "moduleSha256")));
    try std.testing.expectEqualStrings("84C373D351B8D348EE03A922663DC6C74BC2E5479C29BEB760E4B2AD91248392", try json.asString(try json.required(source, "callerSha256")));
    try std.testing.expectEqual(@as(i64, 160), (try json.required(source, "cases")).integer);
    try std.testing.expectEqual(@as(usize, 160), (try json.required(source, "rows")).array.items.len);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(caller, &digest, .{});
    const encoded = std.fmt.bytesToHex(digest, .upper);
    try std.testing.expectEqualStrings("84C373D351B8D348EE03A922663DC6C74BC2E5479C29BEB760E4B2AD91248392", &encoded);
}

test "native upstream698 retry compares all160 genuine getter coercion regexp and function observations" {
    var expected = try json.Owned.parse(std.testing.allocator, source_bytes);
    defer expected.deinit();
    try verifySource(expected.value);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    // The actual native classifier body is bound as the Source ordinary function.
    // This does not claim whole-package public namespace/default SDK qualification.
    try sdk.put(engine, global, "retry698Actual", try ordinary.create(engine, "isRetryableAssistantError", 1, retryable, &.{}));
    try sdk.put(engine, global, "retry698Source", try engine.checked(c.JS_ParseJSON(engine.context, source_bytes.ptr, source_bytes.len, "upstream-698a-retry-source160.json")));
    const result = engine.evalModule(caller ++
        \\const actual=runRetry698ClassifierCases(retry698Actual),expected=retry698Source.rows;if(actual.length!==160||expected.length!==160)throw Error('All160 original Source698 rows required');for(let index=0;index<160;index++){if(actual[index].id!==expected[index].id||JSON.stringify(actual[index])!==JSON.stringify(expected[index]))throw Error(JSON.stringify({index,actual:actual[index],expected:expected[index]}))}delete globalThis.retry698Actual;delete globalThis.retry698Source;
    , "native-upstream698-retry-source160.mjs") catch |err| {
        std.debug.print("Source698 retry differential: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native upstream698 typed retry compares36 genuine error stop string observations" {
    var expected = try json.Owned.parse(std.testing.allocator, source_bytes);
    defer expected.deinit();
    try verifySource(expected.value);
    var checked: usize = 0;
    for ((try json.required(expected.value, "rows")).array.items) |row| {
        const id = try json.asString(try json.required(row, "id"));
        if (!std.mem.startsWith(u8, id, "error/")) continue;
        try std.testing.expectEqualStrings("error", try json.asString(try json.required(row, "stopReason")));
        const input = try json.asString(try json.required(row, "errorMessage"));
        try std.testing.expectEqual((try json.required(row, "result")).bool, @import("ai/retry.zig").isRetryableError(input));
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 36), checked);
}
//! Preserve the actual upstream public input-entry program before the native port.
const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = engine_mod.c;

test "native durable actual e6 input entry public contract uses a genuinely held user provider" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const result = engine.evalModule(@embedFile("durable/fixtures/durable-e6-input-entry-program.txt"), "actual-e6-input-entry-public") catch |err| {
        std.debug.print("Actual e6 input entry {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "e6InputEntryTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-e6-input-entry-source.json"));
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual e6 input entry trace: {s}\n", .{encoded});
        return error.SourceInputEntryPublicContractMismatch;
    }
}

test "native durable actual e6 input entry public contract preserves constructor and pick frames" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const result = engine.evalModule(@embedFile("durable/fixtures/durable-e6-input-entry-frame-program.txt"), "actual-e6-input-entry-frame") catch |err| {
        std.debug.print("Actual e6 input frame {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "e6InputEntryFrameTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-e6-input-entry-frame-source.json"));
    defer expected.deinit();
    // ToString(Symbol) throws each engine's own genuine TypeError. Its message
    // wording differs between V8 and QuickJS. Preserve the raw Source capture;
    // require the field/type/nonempty here and compare every other field.
    try normalizeEngineSymbolMessage(&actual.value);
    try normalizeEngineSymbolMessage(&expected.value);
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual e6 input frame trace: {s}\n", .{encoded});
        return error.SourceInputEntryFrameMismatch;
    }
}

fn normalizeEngineSymbolMessage(value: *json.Value) !void {
    const rows = value.object.getPtr("rows") orelse return error.MissingFrameRows;
    if (rows.* != .array or rows.array.items.len != 4) return error.InvalidFrameRows;
    const row = &rows.array.items[1];
    try std.testing.expectEqualStrings("symbol-return-before-construction", try json.asString(try json.required(row.*, "name")));
    const message = try json.asString(try json.required(row.*, "message"));
    try std.testing.expect(message.len != 0);
    _ = row.object.swapRemove("message");
}

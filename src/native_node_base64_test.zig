//! Replay actual Node24 scalar/coercion/error/metadata/constructor behavior.
const std = @import("std");
const em = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
test "native Node base64 original scalar coercion errors aliases and ordinary constructor contract" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/node_buffer.zig").install(engine);
    const result = engine.evalModule(@embedFile("extensions/fixtures/node-base64-node24-program.txt"), "actual-node24-base64") catch |err| {
        std.debug.print("Native base64 {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "nodeBase64Trace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("extensions/fixtures/node-base64-node24.json"));
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual Node base64 raw: {s}\n", .{encoded});
        return error.SourceNodeBase64ContractMismatch;
    }
}

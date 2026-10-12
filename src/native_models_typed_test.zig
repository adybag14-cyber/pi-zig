const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const durable = @import("extensions/native_durable.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
test "native Models actual Source9 credential resolution typed services and abort identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try @import("extensions/native_models.zig").populateExports(engine, exports);
    try engine.registerValueModule("native-typed-models", exports);
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-model-services-source.json"));
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "modelsServiceSource", try durable.jsValue(engine, fixture.value));
    const module = engine.evalModule(@embedFile("durable/fixtures/durable-19cb534-model-services-native.input.txt"), "native-model-services-source9") catch |err| {
        std.debug.print("Native Models services {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    defer engine.freeValue(module);
    const observed = try sdk.get(engine, global, "modelsServicesActual");
    defer engine.freeValue(observed);
    const raw = try engine.stringify(observed);
    defer engine.gpa.free(raw);
    std.debug.print("Native Models services raw {s}\n", .{raw});
    c.JS_RunGC(engine.runtime);
}

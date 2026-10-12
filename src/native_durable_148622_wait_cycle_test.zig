//! The exact public task program first executed against upstream148622.
const std = @import("std");
const em = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
test "native durable latest148622 wait cycle public graph rejection and background ownership" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const result = engine.evalModule(@embedFile("durable/fixtures/durable-148622-wait-cycle-program.txt"), "actual-148622-wait-cycle") catch |err| {
        std.debug.print("Actual148622 wait cycle {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        const failed_global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(failed_global);
        const progress = c.JS_GetPropertyStr(engine.context, failed_global, "waitCycleProgress");
        defer engine.freeValue(progress);
        const encoded = c.JS_JSONStringify(engine.context, progress, c.pi_js_undefined(), c.pi_js_undefined());
        if (c.JS_IsException(encoded)) {
            engine.freeValue(c.JS_GetException(engine.context));
        } else {
            defer engine.freeValue(encoded);
            var length: usize = 0;
            if (c.JS_ToCStringLen(engine.context, &length, encoded)) |bytes| {
                defer c.JS_FreeCString(engine.context, bytes);
                std.debug.print("Actual148622 original progress: {s}\n", .{bytes[0..length]});
            } else engine.freeValue(c.JS_GetException(engine.context));
        }
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "latestWaitCycleTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-148622-wait-cycle-source.json"));
    defer expected.deinit();
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual148622 wait cycle raw: {s}\n", .{encoded});
        return error.SourceWaitCycleContractMismatch;
    }
}

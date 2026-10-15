const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const leases = @import("extensions/native_env_io_lease.zig");
const c = js.c;

test "native Env IO lease transition compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nENV_IO_LEASE_TRANSITION_TEST_INVENTORY={s}\n", .{text});
}

// These are native ownership/accounting invariants, not a replacement for a
// genuinely executed Node FileHandle comparator. The exact V8 transfer source
// reuses backing only for equal-length fixed-to-fixed transfers; every RAB
// transfer copies even when transfer() preserves length and resizability.
fn transition(comptime resizable: bool, method: [*:0]const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const policy = try leases.Policy.init(engine, 32 * 1024 * 1024);
    const source = if (resizable) "new ArrayBuffer(16,{maxByteLength:32})" else "new ArrayBuffer(16)";
    const backing = try scope.own(try engine.eval(source, "native-lease-backing.js", c.JS_EVAL_TYPE_GLOBAL));
    var size: usize = undefined;
    const initial = c.JS_GetArrayBuffer(engine.context, &size, backing);
    try std.testing.expectEqual(@as(usize, 16), size);
    @memset(initial[0..size], 73);
    var lease = try leases.Lease.acquire(&policy, backing, 2, 4, false);
    var retained = true;
    defer if (retained) lease.deinit();
    const admitted = lease.buffer();
    const recipient = try scope.invoke(backing, method, &.{});
    const received = c.JS_GetArrayBuffer(engine.context, &size, recipient);
    try std.testing.expectEqual(@as(usize, 16), size);
    const recipient_resizable = scope.truthy(try scope.get(recipient, "resizable"));
    @memset(received[0..size], 99);
    c.JS_RunGC(engine.runtime);
    const status = lease.status(c.JS_PI_IO_WRITE, 0);
    if (resizable) {
        try std.testing.expectEqual(@as(c.JSPiIOReason, c.JS_PI_IO_RETIRED_MAPPING), status.reason);
        try std.testing.expectEqual(@as(usize, 0), status.available);
        try std.testing.expect(admitted.base != received + 2);
        try std.testing.expectEqualSlices(u8, &.{ 73, 73, 73, 73 }, admitted.base[0..4]);
        // Old reservation stays in both budgets until the actual last pin.
        try std.testing.expect(c.JS_PiIOMappingCharge(engine.runtime) > 0);
        try std.testing.expectEqual(@as(usize, 2), c.JS_PiIOOwnedGenerations(engine.runtime));
        try std.testing.expectEqual(policy.hooks.allocation_unit * @as(usize, if (recipient_resizable) 2 else 1), c.pi_js_native_virtual_reserved(engine.native_memory_owner));
    } else {
        try std.testing.expectEqual(@as(c.JSPiIOReason, c.JS_PI_IO_READY), status.reason);
        try std.testing.expect(admitted.base == received + 2);
        try std.testing.expectEqualSlices(u8, &.{ 99, 99, 99, 99 }, admitted.base[0..4]);
    }
    lease.deinit();
    retained = false;
    if (resizable) {
        // A resizable recipient has its own reservation; a fixed one has none.
        try std.testing.expectEqual(@as(usize, 1), c.JS_PiIOOwnedGenerations(engine.runtime));
        try std.testing.expectEqual(@as(usize, if (recipient_resizable) policy.hooks.allocation_unit else 0), c.pi_js_native_virtual_reserved(engine.native_memory_owner));
    }
}

test "native Env IO lease transition same length resizable transfer retires original storage" {
    try transition(true, "transfer");
}
test "native Env IO lease transition same length resizable fixed transfer retires original storage" {
    try transition(true, "transferToFixedLength");
}
test "native Env IO lease transition same length fixed transfer preserves actual storage" {
    try transition(false, "transfer");
}

test "native Env IO lease transition Windows allocation unit preserves admitted span after logical shrink" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const policy = try leases.Policy.init(engine, 32 * 1024 * 1024);
    try std.testing.expectEqual(@as(usize, 65536), policy.hooks.allocation_unit);
    const backing = try scope.own(try engine.eval("new ArrayBuffer(32768,{maxByteLength:65536})", "native-lease-shrink.js", c.JS_EVAL_TYPE_GLOBAL));
    var lease = try leases.Lease.acquire(&policy, backing, 2048, 8192, true);
    defer lease.deinit();
    _ = try scope.invoke(backing, "resize", &.{c.JS_NewInt32(engine.context, 4096)});
    const status = lease.status(c.JS_PI_IO_READ, 0);
    try std.testing.expectEqual(@as(c.JSPiIOReason, c.JS_PI_IO_READY), status.reason);
    try std.testing.expectEqual(@as(usize, 8192), status.available);
}

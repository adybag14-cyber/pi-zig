const std = @import("std");
const worker_mod = @import("mcp/codemode_vm_worker.zig");
const json = @import("mcp/protocol.zig").json;
const c = @import("extensions/engine.zig").c;
const deadline: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(50), .clock = .awake } };
fn receive(session: *worker_mod.Session) !json.Owned {
    const end = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 5000;
    while (std.Io.Clock.awake.now(std.testing.io).toMilliseconds() < end) {
        if (try session.next()) |event| return event;
        try session.wait(deadline);
    }
    return error.WorkerEventTimeout;
}

test "native CodeMode worker preserves all sixteen actual deterministic Source results on its own joined VM thread" {
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("mcp/fixtures/codemode-run-045-source.json"));
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    const programs = @import("native_codemode_run_test.zig").programs;
    var store = try json.Owned.parse(std.testing.allocator, "{\"original\":{\"nested\":[1,2]}}");
    defer store.deinit();
    try std.testing.expectEqual(programs.len, rows.len);
    for (rows, programs, 0..) |row, program, index| {
        const initial_owners = c.pi_js_native_memory_owners();
        const session = try worker_mod.Session.create(std.testing.allocator, std.testing.io, program, .{ .started_at = 1768471200000, .seed = if (index == 2) 2 else if (index == 3) 0 else if (index == 4) 4294967295 else 1, .tools = &.{ .{ .name = "echo" }, .{ .name = "wait" } }, .globals = &.{.{ .name = "math.echo", .spread = true }}, .store = store.value, .interrupt_budget = 50000 });
        defer session.deinit();
        try session.start();
        var calls = try json.Owned.empty(std.testing.allocator);
        defer calls.deinit();
        calls.value = .{ .array = .init(calls.arena.allocator()) };
        var idles = try json.Owned.empty(std.testing.allocator);
        defer idles.deinit();
        idles.value = .{ .array = .init(idles.arena.allocator()) };
        var seq: f64 = 0;
        var first_id: ?u64 = null;
        const begin = std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
        while (true) {
            var event = try receive(session);
            defer event.deinit();
            const value = event.value;
            const kind = value.object.get("type").?.string;
            if (std.mem.eql(u8, kind, "call")) {
                var call = try json.clone(calls.arena.allocator(), value);
                _ = call.object.orderedRemove("type");
                try calls.value.array.append(call);
                const id: u64 = @intCast(try json.asInteger(value.object.get("id").?));
                if (index == 7) {
                    if (first_id) |first| {
                        try session.post(2, 1768471202000, id, .{ .success = "\"b\"" });
                        try session.post(1, 1768471201000, first, .{ .success = "\"a\"" });
                    } else first_id = id;
                } else {
                    seq += 1;
                    const payload = if (value.object.get("args")) |args| try json.stringify(std.testing.allocator, args) else null;
                    defer if (payload) |bytes| std.testing.allocator.free(bytes);
                    try session.post(seq, if (index == 6) 1768471200000 - seq else 1768471200000 + 1000 * seq, id, if (index == 9) .{ .failure = .{ .message = "original failure", .properties = "{\"extra\":7,\"message\":\"ignored\",\"name\":\"ignored\",\"stack\":\"ignored\"}" } } else .{ .success = payload });
                }
            } else if (std.mem.eql(u8, kind, "idle")) {
                const a = idles.arena.allocator();
                var idle: json.Value = .{ .array = .init(a) };
                try idle.array.append(value.object.get("seq").?);
                try idle.array.append(value.object.get("issued").?);
                try idles.value.array.append(idle);
            } else if (std.mem.eql(u8, kind, "done")) {
                // done is only published after the real C VM was destroyed.
                try std.testing.expectEqual(initial_owners, c.pi_js_native_memory_owners());
                session.join();
                try std.testing.expect(session.isCompleted());
                var actual = try json.Owned.empty(std.testing.allocator);
                defer actual.deinit();
                actual.value = try json.clone(actual.arena.allocator(), value.object.get("result").?);
                const elapsed = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() - begin;
                for (actual.value.object.getPtr("calls").?.array.items) |*call| {
                    const measured = try json.asNumber(call.object.get("durationMs").?);
                    try std.testing.expect(std.math.isFinite(measured) and measured >= 0 and measured == @floor(measured) and measured <= @as(f64, @floatFromInt(elapsed + 1)));
                    _ = call.object.orderedRemove("durationMs");
                }
                if (!json.equal(row.object.get("result").?, actual.value)) {
                    const bytes = try json.stringify(std.testing.allocator, actual.value);
                    defer std.testing.allocator.free(bytes);
                    std.debug.print("Worker original row {d} actual={s}\n", .{ index, bytes });
                }
                try std.testing.expect(json.equal(row.object.get("result").?, actual.value));
                try std.testing.expect(json.equal(row.object.get("calls").?, calls.value));
                try std.testing.expect(json.equal(row.object.get("idles").?, idles.value));
                break;
            }
        }
    }
}

test "native CodeMode worker cancellation interrupts a computing VM without blocking the calling owner" {
    const baseline = c.pi_js_native_memory_owners();
    const session = try worker_mod.Session.create(std.testing.allocator, std.testing.io, "tools.echo('entered'); while(true) {}", .{ .started_at = 0, .seed = 1, .tools = &.{.{ .name = "echo" }} });
    defer session.deinit();
    try session.start();
    while (true) {
        var event = try receive(session);
        defer event.deinit();
        if (std.mem.eql(u8, event.value.object.get("type").?.string, "call")) break;
    }
    // A call from the script proves it entered the worker VM. The caller can
    // continue doing ordinary work while that VM computes synchronously.
    var owner_progress: usize = 0;
    for (0..10000) |_| owner_progress += 1;
    try std.testing.expectEqual(@as(usize, 10000), owner_progress);
    session.abort();
    while (true) {
        var event = try receive(session);
        defer event.deinit();
        if (std.mem.eql(u8, event.value.object.get("type").?.string, "done")) {
            const result = event.value.object.get("result").?;
            try std.testing.expect(!result.object.get("ok").?.bool);
            try std.testing.expectEqualStrings("aborted", result.object.get("error").?.object.get("kind").?.string);
            session.join();
            try std.testing.expectEqual(baseline, c.pi_js_native_memory_owners());
            break;
        }
    }
}

test "native CodeMode worker shutdown joins abandoned pending calls and frees every queued message" {
    const baseline = c.pi_js_native_memory_owners();
    const session = try worker_mod.Session.create(std.testing.allocator, std.testing.io, "await tools.echo({nested:[1,2,3]})", .{ .started_at = 0, .seed = 1, .tools = &.{.{ .name = "echo" }} });
    var released = false;
    defer if (!released) session.deinit();
    try session.start();
    while (true) {
        var event = try receive(session);
        const is_call = std.mem.eql(u8, event.value.object.get("type").?.string, "call");
        event.deinit();
        if (is_call) break;
    }
    session.deinit();
    released = true;
    try std.testing.expectEqual(baseline, c.pi_js_native_memory_owners());
}

test "native CodeMode worker releases every failed owner allocation across native thread startup execution event publication and joined teardown" {
    const Lifecycle = struct {
        fn exercise(gpa: std.mem.Allocator) !void {
            const before = c.pi_js_native_memory_owners();
            const session = try worker_mod.Session.create(gpa, std.testing.io, "store('k',{x:7}); text('complete'); return load('k')", .{ .started_at = 0, .seed = 1 });
            defer session.deinit();
            try session.start();
            // No caller allocation races the worker: this makes every induced
            // allocation boundary deterministic while still using a real thread.
            session.join();
            try std.testing.expectEqual(before, c.pi_js_native_memory_owners());
            if (session.failure) |failure| return failure;
            var done = false;
            while (try session.next()) |original| {
                var event = original;
                defer event.deinit();
                if (std.mem.eql(u8, event.value.object.get("type").?.string, "done")) {
                    const result = event.value.object.get("result").?;
                    try std.testing.expect(result.object.get("ok").?.bool);
                    try std.testing.expectEqual(@as(f64, 7), try json.asNumber(result.object.get("value").?.object.get("x").?));
                    done = true;
                }
            }
            try std.testing.expect(done);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Lifecycle.exercise, .{});
}

//! Whole-record component replay of the actual Node19 shared caller input.
//! Engine/global tracker, worker exit and physical CLI activation remain separate.
const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const rejections = @import("extensions/native_promise_rejections.zig");
const policy_mod = @import("extensions/native_promise_rejection_policy.zig");
const timers = @import("extensions/timers.zig");
fn tracker(_: ?*c.JSContext, promise: c.JSValue, reason: c.JSValue, handled: bool, raw: ?*anyopaque) callconv(.c) void {
    const queue: *rejections.Queue = @ptrCast(@alignCast(raw.?));
    queue.observe(promise, reason, handled);
}
fn script(engine: *js.Engine, source: []const u8) !void {
    engine.freeValue(try engine.eval(source, "original-node-policy-replay-host.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn checkpoint(engine: *js.Engine, queue: *rejections.Queue, policy: *policy_mod.Policy, process: c.JSValue) !?policy_mod.Fatal {
    var turns: usize = 0;
    while (turns < 100) : (turns += 1) {
        _ = try engine.drainReadyJobs();
        // Node processes asyncHandledRejections before swapping the pending map.
        // The exact original Source input registers a rejectionHandled observer.
        while (try queue.takeHandled()) |handled| {
            defer handled.deinit(engine.context);
            const event = try engine.checked(c.JS_NewString(engine.context, "rejectionHandled"));
            defer engine.freeValue(event);
            const emitted = try js.invoke(engine, process, "emit", &.{ event, handled.promise });
            defer engine.freeValue(emitted);
            if (c.JS_ToBool(engine.context, emitted) == 0) return error.OriginalSourceObserverMissing;
        }
        queue.checkpoint();
        while (try queue.take()) |pending| {
            defer pending.deinit(engine.context);
            try queue.noteReported(pending);
            if (try policy.reportUnhandled(process, pending)) |fatal| {
                defer fatal.deinit(engine);
                if (try policy.reportUncaught(process, fatal)) |terminal| return terminal;
            }
        }
        if (!c.JS_IsJobPending(engine.runtime) and queue.entries.items.len == 0 and queue.handled.items.len == 0) return null;
    }
    return error.NativeReplayCheckpointLimit;
}

test "Promise rejection Source original19 exact shared input whole events and typed terminal outcomes" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/node-rejection-policy-original19.json"), .{});
    defer fixture.deinit();
    const cases = fixture.value.object.get("cases").?.array.items;
    try std.testing.expectEqual(@as(usize, 19), cases.len);
    for (cases, 0..) |row, index| {
        const fixture_engine = try @import("native_error_stack_fixture.zig").Fixture.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
        defer fixture_engine.deinit();
        const engine = fixture_engine.engine;
        var queue = try rejections.Queue.init(engine, std.testing.allocator);
        defer queue.deinit();
        var policy = try policy_mod.Policy.init(engine);
        defer policy.deinit();
        var environment: std.process.Environ.Map = .init(std.testing.allocator);
        defer environment.deinit();
        try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "original-node-policy", row.object.get("id").?.string });
        try timers.install(engine, std.testing.io);
        c.JS_SetHostPromiseRejectionTracker(engine.runtime, tracker, &queue);
        defer c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
        const root = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(root);
        const bytes = @embedFile("extensions/fixtures/node-rejection-policy-original19.json");
        try js.define(engine, root, "policySource", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-node-policy-original19")));
        const source = try js.get(engine, root, "policySource");
        defer engine.freeValue(source);
        const case_array = try js.get(engine, source, "cases");
        defer engine.freeValue(case_array);
        try js.define(engine, root, "policySourceCase", try engine.checked(c.JS_GetPropertyUint32(engine.context, case_array, @intCast(index))));
        try script(engine, "globalThis.policyReplayRows=[];globalThis.policyReplayCapture=row=>policyReplayRows.push(row);");
        const process = try js.get(engine, root, "process");
        defer engine.freeValue(process);
        const module = try engine.evalModule(@embedFile("extensions/fixtures/rejection-policy-original.input.mjs"), "rejection-policy-original.input.mjs");
        defer engine.freeValue(module);
        const start = try js.get(engine, module, "startCase");
        defer engine.freeValue(start);
        const id = try engine.checked(c.JS_NewStringLen(engine.context, row.object.get("id").?.string.ptr, row.object.get("id").?.string.len));
        defer engine.freeValue(id);
        const capture = try js.get(engine, root, "policyReplayCapture");
        defer engine.freeValue(capture);
        const pending = try js.call(engine, start, c.pi_js_undefined(), &.{ id, capture });
        defer engine.freeValue(pending);
        // Explicit C ABI host-await ownership, equivalent to Source controller
        // awaiting startCase. The original program's discarded promises stay raw.
        c.JS_PromiseMarkAsHandled(engine.context, pending);
        engine.freeValue(try engine.awaitValue(pending));
        const first = try checkpoint(engine, &queue, &policy, process);
        defer if (first) |fatal| fatal.deinit(engine);
        var exit_code: i64 = 0;
        if (first) |fatal| {
            exit_code = fatal.exit_code;
        } else {
            try std.testing.io.sleep(.fromMilliseconds(30), .awake);
            _ = try timers.pumpReady(engine);
            const later = try checkpoint(engine, &queue, &policy, process);
            defer if (later) |fatal| fatal.deinit(engine);
            if (later) |fatal| exit_code = fatal.exit_code;
        }
        try std.testing.expectEqual(row.object.get("exitCode").?.integer, exit_code);
        script(engine, "if(JSON.stringify(policyReplayRows)!==JSON.stringify(policySourceCase.events))throw Error(JSON.stringify({id:policySourceCase.id,actual:policyReplayRows,expected:policySourceCase.events}));") catch |err| {
            std.debug.print("Original Node19 replay index={d} id={s}: {s}\n", .{ index, row.object.get("id").?.string, engine.last_error orelse @errorName(err) });
            return err;
        };
    }
}

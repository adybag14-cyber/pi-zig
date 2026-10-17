//! Prepared focused controls; no execution claimed by their source authoring.
const std = @import("std");
const p = @import("extensions/native_node_stack_observer.zig");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const node = @import("extensions/native_node_function.zig");
const c = em.c;

test "TypeBox stack observer nested records retain identities and balanced depth" {
    var storage: [8]p.Record = undefined;
    var observer: p.Observer = .init(&storage, 10);
    const first = observer.enter(10, 101, 201, 1000).?;
    const second = observer.enter(10, 102, 202, 900).?;
    observer.leave(10, 102, 202, 900, second, true);
    observer.leave(10, 101, 201, 1000, first, false);
    try std.testing.expect(observer.complete());
    try std.testing.expectEqual(@as(usize, 4), observer.used);
    try std.testing.expectEqual(@as(usize, 2), observer.maximum_depth);
    try std.testing.expectEqual(@as(u64, 1), observer.native_errors);
    for (storage[0..4], 0..) |record, index| try std.testing.expectEqual(@as(u64, @intCast(index + 1)), record.sequence);
    try std.testing.expectEqual(@as(u8, 2), storage[2].event);
    try std.testing.expectEqual(@as(usize, 102), storage[2].callback);
    try std.testing.expectEqual(@as(usize, 202), storage[2].function_state);
    try std.testing.expectEqual(@as(usize, 900), storage[2].frame_address);
    try std.testing.expectEqual(@as(usize, 2), storage[2].depth);
}

test "TypeBox stack observer fixed capacity reports incomplete and keeps unwind accounting" {
    var storage: [1]p.Record = undefined;
    var observer: p.Observer = .init(&storage, 10);
    const entered = observer.enter(10, 101, 201, 1000).?;
    observer.leave(10, 101, 201, 1000, entered, false);
    try std.testing.expect(!observer.complete());
    try std.testing.expectEqual(@as(usize, 1), observer.used);
    try std.testing.expectEqual(@as(u64, 1), observer.dropped);
    try std.testing.expectEqual(@as(u64, 2), observer.attempted);
    try std.testing.expectEqual(@as(usize, 0), observer.depth);
    try std.testing.expectEqual(@as(u64, 1), storage[0].sequence);
}

test "TypeBox stack observer foreign engine cannot mutate records or depth" {
    var storage: [2]p.Record = undefined;
    var observer: p.Observer = .init(&storage, 10);
    try std.testing.expect(observer.enter(11, 101, 201, 1000) == null);
    observer.captured(11);
    try std.testing.expectEqual(@as(usize, 0), observer.used);
    try std.testing.expectEqual(@as(usize, 0), observer.depth);
    try std.testing.expectEqual(@as(u64, 0), observer.capture_epoch);
    try std.testing.expectEqual(@as(u32, p.foreign_engine), observer.guard_flags.load(.monotonic));
    try std.testing.expect(!observer.complete());
}

fn foreignThread(observer: *p.Observer) void {
    _ = observer.enter(10, 101, 201, 1000);
    observer.leave(10, 101, 201, 1000, 1, false);
    observer.captured(10);
}
test "TypeBox stack observer actual foreign thread only sets atomic rejection flag" {
    var storage: [2]p.Record = undefined;
    var observer: p.Observer = .init(&storage, 10);
    const thread = try std.Thread.spawn(.{}, foreignThread, .{&observer});
    thread.join();
    try std.testing.expectEqual(@as(usize, 0), observer.used);
    try std.testing.expectEqual(@as(usize, 0), observer.depth);
    try std.testing.expectEqual(@as(u64, 0), observer.capture_epoch);
    try std.testing.expectEqual(@as(u32, p.foreign_thread), observer.guard_flags.load(.monotonic));
    try std.testing.expect(!observer.complete());
}

test "TypeBox stack observer mismatched unwind cannot pretend complete" {
    var storage: [2]p.Record = undefined;
    var observer: p.Observer = .init(&storage, 10);
    _ = observer.enter(10, 101, 201, 1000);
    observer.leave(10, 101, 201, 1000, 2, false);
    try std.testing.expectEqual(@as(usize, 1), observer.used);
    try std.testing.expectEqual(@as(usize, 1), observer.depth);
    try std.testing.expectEqual(@as(u32, p.unbalanced), observer.guard_flags.load(.monotonic));
    try std.testing.expect(!observer.complete());
    var saturated: p.Observer = .init(&storage, 10);
    saturated.capture_epoch = std.math.maxInt(u64);
    saturated.captured(10);
    try std.testing.expectEqual(std.math.maxInt(u64), saturated.capture_epoch);
    try std.testing.expectEqual(@as(u32, p.counter_saturated), saturated.guard_flags.load(.monotonic));
    try std.testing.expect(!saturated.complete());
}

fn inner(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewInt32(engine.context, 17);
}
fn outer(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return js.call(engine, roots[0], c.pi_js_undefined(), &.{});
}
fn throwing(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0])));
}
test "TypeBox stack observer actual native nested calls keep result and disabled calls record nothing" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const leaf = try node.createArrow(engine, "observedInner", 0, inner, &.{});
    defer engine.freeValue(leaf);
    const parent = try node.create(engine, "observedOuter", 0, outer, &.{leaf});
    defer engine.freeValue(parent);
    var storage: [8]p.Record = undefined;
    var observer: p.Observer = .init(&storage, @intFromPtr(engine));
    const disabled = try js.call(engine, parent, c.pi_js_undefined(), &.{});
    defer engine.freeValue(disabled);
    try std.testing.expectEqual(@as(usize, 0), observer.used);
    const host = @import("typebox_stack_observer_host.zig");
    var boundary: host.Boundary = .init(engine, &observer);
    engine.native_exception_diagnostics_suppressed = 3;
    defer engine.native_exception_diagnostics_suppressed = 0;
    try boundary.start();
    defer boundary.detach();
    const result = try js.call(engine, parent, c.pi_js_undefined(), &.{});
    defer engine.freeValue(result);
    boundary.detach();
    try std.testing.expectEqual(@as(usize, 3), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, disabled, result));
    try std.testing.expectEqual(@as(usize, 4), observer.used);
    try std.testing.expect(observer.complete());
    try std.testing.expectEqual(@intFromPtr(&outer), storage[0].callback);
    try std.testing.expectEqual(@intFromPtr(&inner), storage[1].callback);
    try std.testing.expectEqual(storage[0].function_state, storage[3].function_state);
    try std.testing.expectEqual(storage[1].function_state, storage[2].function_state);
    try std.testing.expect(storage[0].function_state != storage[1].function_state);
    try std.testing.expect(storage[0].frame_address != 0 and storage[1].frame_address != 0);
}

const FormattingMarker = struct {
    var calls: usize = 0;
    fn call(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
        calls += 1;
        return engine.checked(c.JS_NewString(engine.context, "diagnostic sentinel"));
    }
};
test "TypeBox stack observer actual native error preserves sentinel identity and records failure" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const sentinel = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(sentinel);
    FormattingMarker.calls = 0;
    const formatter = try node.createArrow(engine, "diagnosticToString", 0, FormattingMarker.call, &.{});
    defer engine.freeValue(formatter);
    if (c.JS_SetPropertyStr(engine.context, sentinel, "toString", c.JS_DupValue(engine.context, formatter)) < 0) return error.TestUnexpectedResult;
    const function = try node.createArrow(engine, "observedThrow", 0, throwing, &.{sentinel});
    defer engine.freeValue(function);
    var storage: [4]p.Record = undefined;
    var observer: p.Observer = .init(&storage, @intFromPtr(engine));
    const host = @import("typebox_stack_observer_host.zig");
    var boundary: host.Boundary = .init(engine, &observer);
    try boundary.start();
    defer boundary.detach();
    try std.testing.expectError(error.JavaScriptException, js.call(engine, function, c.pi_js_undefined(), &.{}));
    try std.testing.expectEqual(@as(usize, 0), FormattingMarker.calls);
    try std.testing.expect(observer.capture_epoch > 0);
    boundary.afterFailure(error.JavaScriptException);
    try std.testing.expectEqual(@as(usize, 1), FormattingMarker.calls);
    try std.testing.expect(engine.native_node_stack_observer == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expectEqualStrings("fresh_reason_diagnostic_recaptured", boundary.recapture_status);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, sentinel, engine.captured_exception.?));
    try std.testing.expect(observer.complete());
    try std.testing.expectEqual(@as(usize, 2), observer.used);
    try std.testing.expectEqual(@as(u8, 2), storage[1].event);
    try std.testing.expectEqual(@as(u64, 1), observer.native_errors);
    try std.testing.expectEqual(@as(usize, 0), observer.depth);
    // An old retained exception is not a fresh capture, and a direct host OOM
    // does not trigger diagnostic conversion of that old reason.
    var stale_observer: p.Observer = .init(&storage, @intFromPtr(engine));
    var stale: host.Boundary = .init(engine, &stale_observer);
    try stale.start();
    stale.afterFailure(error.JavaScriptException);
    try std.testing.expectEqualStrings("no_fresh_reason_no_recapture", stale.recapture_status);
    try std.testing.expectEqual(@as(usize, 1), FormattingMarker.calls);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, sentinel, engine.captured_exception.?));
    var oom: host.Boundary = .init(engine, &stale_observer);
    try oom.start();
    oom.afterFailure(error.OutOfMemory);
    try std.testing.expectEqualStrings("host_out_of_memory_untouched", oom.recapture_status);
    try std.testing.expectEqual(@as(usize, 1), FormattingMarker.calls);
    // Real private allocation tagging is created by the existing Engine API;
    // the diagnostic must neither retag nor clear its uncatchability.
    var fatal: host.Boundary = .init(engine, &stale_observer);
    try fatal.start();
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const fatal_reason = c.JS_DupValue(engine.context, engine.captured_exception.?);
    defer engine.freeValue(fatal_reason);
    const generation = engine.native_allocation_generation;
    const uncatchable = c.JS_IsUncatchableError(fatal_reason);
    fatal.afterFailure(error.JavaScriptException);
    try std.testing.expectEqualStrings(if (uncatchable) "uncatchable_reason_untouched" else "private_allocation_reason_untouched", fatal.recapture_status);
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    try std.testing.expectEqual(uncatchable, c.JS_IsUncatchableError(fatal_reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, fatal_reason, engine.captured_exception.?));
    try std.testing.expectEqual(@as(usize, 1), FormattingMarker.calls);
    // Suppression overflow rejects before attachment; a disturbed counter is
    // detected and exact prior policy restored, without wrapping arithmetic.
    engine.native_exception_diagnostics_suppressed = std.math.maxInt(usize);
    var saturated_boundary: host.Boundary = .init(engine, &stale_observer);
    try std.testing.expectError(error.ObserverSuppressionSaturated, saturated_boundary.start());
    try std.testing.expect(engine.native_node_stack_observer == null);
    engine.native_exception_diagnostics_suppressed = 2;
    var mismatch_observer: p.Observer = .init(&storage, @intFromPtr(engine));
    var mismatch: host.Boundary = .init(engine, &mismatch_observer);
    try mismatch.start();
    engine.native_exception_diagnostics_suppressed = 4;
    mismatch.detach();
    try std.testing.expectEqual(@as(usize, 2), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!mismatch.restoration_valid and !mismatch_observer.complete());
    engine.native_exception_diagnostics_suppressed = 0;
}

test "TypeBox stack observer report path rejects escapes aliases and nonfresh path forms" {
    const host = @import("typebox_stack_observer_host.zig");
    try host.validateReportPath("C:\\Users\\adyba\\pi-zig\\evidence\\fresh-observer-20261017\\trace.json");
    for ([_][]const u8{
        "C:\\Users\\adyba\\outside\\trace.json",
        "C:\\Users\\adyba\\pi-zig\\evidence\\..\\trace.json",
        "C:\\Users\\adyba\\pi-zig\\evidence\\fresh.\\trace.json",
        "C:\\Users\\adyba\\pi-zig\\evidence\\fresh\\trace.json:alternate",
        "C:\\Users\\adyba\\pi-zig\\evidence\\fresh\\trace.txt",
        "C:\\Users\\adyba\\pi-zig\\evidence\\fresh\\\\trace.json",
        "C:\\Users\\adyba\\pi-zig\\evidence\\fresh\\CON.json",
    }) |path| {
        if (host.validateReportPath(path)) |_| return error.UnsafeObserverPathAccepted else |_| {}
    }
}

test "TypeBox stack observer absent host opt in leaves engine observer detached" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var session = try @import("typebox_stack_observer_host.zig").Session.prepare(engine, std.testing.allocator, std.testing.io, .empty);
    defer session.deinit();
    try session.start();
    try std.testing.expect(session.state == null);
    try std.testing.expect(engine.native_node_stack_observer == null);
    try session.finish(false);
    try std.testing.expect(engine.native_node_stack_observer == null);
}

//! Prepared source-only shared thenable controls; no executed parity claim.
const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn returnValue(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_DupValue(engine.context, args[0]);
}
fn fatalStart(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return error.OutOfMemory;
}
fn resumedReturn(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    return switch (completion) {
        .start => .{ .awaited = c.JS_DupValue(engine.context, args[0]) },
        .fulfilled => .{ .returned = c.JS_DupValue(engine.context, args[1]) },
        .rejected => .{ .thrown = c.JS_DupValue(engine.context, input) },
    };
}
const Harness = struct {
    engine: *em.Engine,
    scope: Scope,
    global: c.JSValue,
    returner: c.JSValue,
    fn init() !Harness {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        errdefer engine.deinit();
        var scope: Scope = .{ .engine = engine };
        errdefer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        try scope.put(global, "thenCalls", c.JS_NewInt32(engine.context, 0));
        try scope.put(global, "fatalStart", try scope.own(try af.create(engine, "fatalStart", 0, fatalStart, &.{})));
        const returner = try scope.own(try af.create(engine, "returnValue", 1, returnValue, &.{}));
        return .{ .engine = engine, .scope = scope, .global = global, .returner = returner };
    }
    fn deinit(self: *Harness) void {
        self.scope.deinit();
        self.engine.deinit();
    }
    fn eval(self: *Harness, source: []const u8) !c.JSValue {
        return self.scope.own(try self.engine.eval(source, "shared-thenable-control.js", c.JS_EVAL_TYPE_GLOBAL));
    }
    fn adopt(self: *Harness, value: c.JSValue) c.JSValue {
        var args = [_]c.JSValue{value};
        return c.JS_Call(self.engine.context, self.returner, c.pi_js_undefined(), args.len, &args);
    }
    fn count(self: *Harness) !i32 {
        return readCount(self.engine.context);
    }
    fn taggedFatal(self: *Harness, reason: c.JSValue, expected: c.JSValue, boundary: u64) !void {
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.JS_IsStrictEqual(self.engine.context, reason, expected));
        try std.testing.expectError(error.JavaScriptException, self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason))));
        try std.testing.expect(self.engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
        try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn pump(self: *Harness) !void {
        var jobs: usize = 0;
        while (c.JS_IsJobPending(self.engine.runtime)) {
            if (jobs == 32) return error.ThenableJobBudget;
            const job = runJob(self.engine);
            defer self.engine.freeValue(job.reason);
            try std.testing.expect(job.status > 0);
            try std.testing.expect(!job.had_pending);
            jobs += 1;
        }
    }
};
fn readCount(context: ?*c.JSContext) !i32 {
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const value = c.JS_GetPropertyStr(context, global, "thenCalls");
    defer c.JS_FreeValue(context, value);
    var count: i32 = undefined;
    if (c.JS_ToInt32(context, &count, value) < 0) return error.JavaScriptException;
    return count;
}
const Job = struct { status: c_int, reason: c.JSValue, had_pending: bool };
fn runJob(engine: *em.Engine) Job {
    var context: ?*c.JSContext = null;
    const status = c.JS_ExecutePendingJob(engine.runtime, &context);
    const owner = context orelse engine.context;
    const had_pending = c.JS_HasException(owner);
    return .{ .status = status, .reason = if (had_pending) c.JS_GetException(owner) else c.pi_js_undefined(), .had_pending = had_pending };
}
const Mode = enum { none, before_fatal, after_fatal, second_fatal, replace, remove };
const alternate_magic: u64 = 0x6A7049434F4E5452;
const Alternate = struct { magic: u64 = alternate_magic, probe: *Probe };
const Probe = struct {
    engine: *em.Engine,
    target: c.JSValue, // Borrowed from the test's owned outer Promise.
    mode: Mode,
    events: [8]u8 = undefined,
    len: usize = 0,
    bad_state: bool = false,
    before_count: i32 = -1,
    after_count: i32 = -1,
    alternate: ?*Alternate = null,
    alternate_seen: bool = false,
    first_reason: ?c.JSValue = null, // Owned only by the second-fatal control.
    first_was_fatal: bool = false,
    fn record(self: *Probe, event: u8) void {
        if (self.len == self.events.len) {
            self.bad_state = true;
            return;
        }
        self.events[self.len] = event;
        self.len += 1;
    }
    fn deinit(self: *Probe) void {
        if (self.first_reason) |reason| self.engine.freeValue(reason);
    }
};
fn inject(probe: *Probe, context: ?*c.JSContext) void {
    _ = probe.engine.throwNativeOutOfMemory();
    c.JS_SetUncatchableError(context, probe.engine.native_allocation_exception.?);
}
fn alternateHook(context: ?*c.JSContext, kind: c.JSPromiseHookType, promise: c.JSValue, _: c.JSValue, hook_data: ?*anyopaque) callconv(.c) void {
    const alternate: *Alternate = @ptrCast(@alignCast(hook_data.?));
    // A mismatched old opaque fails the explicit token check without using its
    // second field as a pointer. Correct replacement must pass both new parts.
    if (alternate.magic != alternate_magic or kind != c.JS_PROMISE_HOOK_AFTER) return;
    const probe = alternate.probe;
    if (!c.JS_IsStrictEqual(context, promise, probe.target)) return;
    probe.alternate_seen = true;
    probe.after_count = readCount(context) catch {
        probe.bad_state = true;
        return;
    };
    probe.record(4);
}
fn hook(context: ?*c.JSContext, kind: c.JSPromiseHookType, promise: c.JSValue, _: c.JSValue, hook_data: ?*anyopaque) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(hook_data.?));
    if (!c.JS_IsStrictEqual(context, promise, probe.target)) return;
    if (kind == c.JS_PROMISE_HOOK_BEFORE) {
        probe.record(1);
        probe.before_count = readCount(context) catch {
            probe.bad_state = true;
            return;
        };
        switch (probe.mode) {
            .before_fatal => inject(probe, context),
            .replace => c.JS_SetPromiseHook(c.JS_GetRuntime(context), alternateHook, probe.alternate.?),
            .remove => c.JS_SetPromiseHook(c.JS_GetRuntime(context), null, null),
            else => {},
        }
    } else if (kind == c.JS_PROMISE_HOOK_AFTER) {
        probe.record(3);
        probe.after_count = readCount(context) catch {
            probe.bad_state = true;
            return;
        };
        if (probe.mode == .second_fatal) {
            // Public Get/Throw proves the original pending fatal is still
            // visible at AFTER; the owned duplicate records its identity.
            const prior = c.JS_GetException(context);
            probe.first_was_fatal = c.JS_IsUncatchableError(prior);
            probe.first_reason = c.JS_DupValue(context, prior);
            _ = c.JS_Throw(context, prior);
            inject(probe, context);
        } else if (probe.mode == .after_fatal) inject(probe, context);
    }
}

test "shared thenable fatal getter START and resumed native returns preserve active reason" {
    for ([_]bool{ false, true }) |later_resume| {
        var h = try Harness.init();
        defer h.deinit();
        const thenable = try h.eval("({get then(){fatalStart()}})");
        const boundary = h.engine.native_allocation_generation;
        if (!later_resume) {
            const result = h.adopt(thenable);
            defer h.engine.freeValue(result);
            const reason = c.JS_GetException(h.engine.context);
            defer h.engine.freeValue(reason);
            try h.taggedFatal(reason, h.engine.native_allocation_exception.?, boundary);
            try std.testing.expect(c.JS_IsException(result));
        } else {
            const ready = try h.scope.own(try h.engine.checked(c.JS_NewSettledPromise(h.engine.context, false, c.pi_js_undefined())));
            const function = try h.scope.own(try af.createResumable(h.engine, "resumedThenableReturn", 2, resumedReturn, &.{}));
            var args = [_]c.JSValue{ ready, thenable };
            const pending = c.JS_Call(h.engine.context, function, c.pi_js_undefined(), args.len, &args);
            defer h.engine.freeValue(pending);
            try std.testing.expect(!c.JS_IsException(pending));
            const job = runJob(h.engine);
            defer h.engine.freeValue(job.reason);
            try h.taggedFatal(job.reason, h.engine.native_allocation_exception.?, boundary);
            try std.testing.expect(job.status < 0);
        }
    }
}
test "shared thenable fatal deferred then call preserves paired hooks and exact pending reason across GC" {
    var h = try Harness.init();
    defer h.deinit();
    const thenable = try h.eval("({then(){thenCalls++;fatalStart()}})");
    const pending = h.adopt(thenable);
    defer h.engine.freeValue(pending);
    try std.testing.expect(!c.JS_IsException(pending));
    var probe: Probe = .{ .engine = h.engine, .target = pending, .mode = .none };
    defer probe.deinit();
    c.JS_SetPromiseHook(h.engine.runtime, hook, &probe);
    defer c.JS_SetPromiseHook(h.engine.runtime, null, null);
    const boundary = h.engine.native_allocation_generation;
    c.JS_RunGC(h.engine.runtime);
    const job = runJob(h.engine);
    defer h.engine.freeValue(job.reason);
    try h.taggedFatal(job.reason, h.engine.native_allocation_exception.?, boundary);
    try std.testing.expect(job.status < 0);
    try std.testing.expectEqualSlices(u8, &.{ 1, 3 }, probe.events[0..probe.len]);
    try std.testing.expectEqual(@as(i32, 0), probe.before_count);
    try std.testing.expectEqual(@as(i32, 1), probe.after_count);
    try std.testing.expect(!probe.bad_state);
}
test "shared thenable fatal BEFORE skips then and AFTER while AFTER fatal retains normal call order" {
    for ([_]Mode{ .before_fatal, .after_fatal }) |mode| {
        var h = try Harness.init();
        defer h.deinit();
        const thenable = try h.eval("({then(resolve){thenCalls++;resolve(19)}})");
        const pending = h.adopt(thenable);
        defer h.engine.freeValue(pending);
        try std.testing.expect(!c.JS_IsException(pending));
        var probe: Probe = .{ .engine = h.engine, .target = pending, .mode = mode };
        defer probe.deinit();
        c.JS_SetPromiseHook(h.engine.runtime, hook, &probe);
        defer c.JS_SetPromiseHook(h.engine.runtime, null, null);
        const boundary = h.engine.native_allocation_generation;
        const job = runJob(h.engine);
        defer h.engine.freeValue(job.reason);
        try h.taggedFatal(job.reason, h.engine.native_allocation_exception.?, boundary);
        try std.testing.expect(job.status < 0);
        if (mode == .before_fatal) {
            try std.testing.expectEqualSlices(u8, &.{1}, probe.events[0..probe.len]);
            try std.testing.expectEqual(@as(i32, 0), try h.count());
        } else {
            try std.testing.expectEqualSlices(u8, &.{ 1, 3 }, probe.events[0..probe.len]);
            try std.testing.expectEqual(@as(i32, 1), probe.after_count);
        }
        try std.testing.expect(!probe.bad_state);
    }
}
test "shared thenable fatal original then failure wins distinct AFTER failure without retagging" {
    var h = try Harness.init();
    defer h.deinit();
    const thenable = try h.eval("({then(){thenCalls++;fatalStart()}})");
    const pending = h.adopt(thenable);
    defer h.engine.freeValue(pending);
    try std.testing.expect(!c.JS_IsException(pending));
    var probe: Probe = .{ .engine = h.engine, .target = pending, .mode = .second_fatal };
    defer probe.deinit();
    c.JS_SetPromiseHook(h.engine.runtime, hook, &probe);
    defer c.JS_SetPromiseHook(h.engine.runtime, null, null);
    const boundary = h.engine.native_allocation_generation;
    const job = runJob(h.engine);
    defer h.engine.freeValue(job.reason);
    try std.testing.expect(probe.first_was_fatal);
    const first = probe.first_reason orelse return error.MissingFirstFatal;
    try std.testing.expect(!c.JS_IsStrictEqual(h.engine.context, first, h.engine.native_allocation_exception.?));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(first) < h.engine.native_allocation_generation);
    try h.taggedFatal(job.reason, first, boundary);
    try std.testing.expect(job.status < 0);
    try std.testing.expectEqualSlices(u8, &.{ 1, 3 }, probe.events[0..probe.len]);
    try std.testing.expect(!probe.bad_state);
}
test "shared thenable fatal ordinary raw historical and lookalike throws retain exact rejection values" {
    for (0..3) |kind| {
        for ([_]bool{ false, true }) |deferred| {
            var h = try Harness.init();
            defer h.deinit();
            const reason = if (kind == 0) try h.scope.object() else if (kind == 1) historical: {
                _ = h.engine.throwNativeOutOfMemory();
                const value = c.JS_GetException(h.engine.context);
                c.JS_ClearUncatchableError(h.engine.context, value);
                break :historical try h.scope.own(value);
            } else try h.eval("Object.assign(new Error('out of memory'),{name:'InternalError'})");
            try h.scope.put(h.global, "ordinaryReason", reason);
            const thenable = try h.eval(if (deferred) "({then(){throw ordinaryReason}})" else "({get then(){throw ordinaryReason}})");
            const boundary = h.engine.native_allocation_generation;
            const result = h.adopt(thenable);
            defer h.engine.freeValue(result);
            try std.testing.expect(!c.JS_IsException(result));
            try std.testing.expect(!c.JS_HasException(h.engine.context));
            try h.pump();
            try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(h.engine.context, result));
            const rejected = c.JS_PromiseResult(h.engine.context, result);
            defer h.engine.freeValue(rejected);
            try std.testing.expect(c.JS_IsStrictEqual(h.engine.context, reason, rejected));
            try std.testing.expectError(error.JavaScriptException, h.engine.checked(c.JS_Throw(h.engine.context, c.JS_DupValue(h.engine.context, rejected))));
            try std.testing.expect(h.engine.nativeAllocationError(error.JavaScriptException, boundary) == error.JavaScriptException);
        }
    }
}
test "shared thenable fatal flagged rejected data without pending exception stays ordinary data" {
    for ([_]bool{ false, true }) |adopt_rejected| {
        var h = try Harness.init();
        defer h.deinit();
        const reason = try h.eval("new Error('flagged data only')");
        c.JS_SetUncatchableError(h.engine.context, reason);
        try h.scope.put(h.global, "flaggedReason", reason);
        try std.testing.expect(!c.JS_HasException(h.engine.context));
        const resolution = if (adopt_rejected)
            try h.scope.own(try h.engine.checked(c.JS_NewSettledPromise(h.engine.context, true, reason)))
        else
            try h.eval("({then(resolve,reject){reject(flaggedReason)}})");
        const result = h.adopt(resolution);
        defer h.engine.freeValue(result);
        try std.testing.expect(!c.JS_IsException(result));
        try h.pump();
        try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(h.engine.context, result));
        const rejected = c.JS_PromiseResult(h.engine.context, result);
        defer h.engine.freeValue(rejected);
        try std.testing.expect(c.JS_IsStrictEqual(h.engine.context, reason, rejected));
        try std.testing.expect(c.JS_IsUncatchableError(rejected));
        try std.testing.expect(!c.JS_HasException(h.engine.context));
        try std.testing.expectEqual(@as(u64, 0), h.engine.native_allocation_generation);
        c.JS_ClearUncatchableError(h.engine.context, reason);
    }
}
test "shared thenable fatal normal hooks preserve replacement removal and new opaque identity" {
    for ([_]Mode{ .none, .replace, .remove }) |mode| {
        var h = try Harness.init();
        defer h.deinit();
        const thenable = try h.eval("({then(resolve){thenCalls++;resolve(23)}})");
        const result = h.adopt(thenable);
        defer h.engine.freeValue(result);
        try std.testing.expect(!c.JS_IsException(result));
        var probe: Probe = .{ .engine = h.engine, .target = result, .mode = mode };
        defer probe.deinit();
        var alternate: Alternate = .{ .probe = &probe };
        probe.alternate = &alternate;
        c.JS_SetPromiseHook(h.engine.runtime, hook, &probe);
        defer c.JS_SetPromiseHook(h.engine.runtime, null, null);
        try h.pump();
        try std.testing.expectEqual(@as(i32, 1), try h.count());
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(h.engine.context, result));
        const value = c.JS_PromiseResult(h.engine.context, result);
        defer h.engine.freeValue(value);
        var number: i32 = undefined;
        if (c.JS_ToInt32(h.engine.context, &number, value) < 0) return error.JavaScriptException;
        try std.testing.expectEqual(@as(i32, 23), number);
        switch (mode) {
            .none => try std.testing.expectEqualSlices(u8, &.{ 1, 3 }, probe.events[0..probe.len]),
            .replace => {
                try std.testing.expectEqualSlices(u8, &.{ 1, 4 }, probe.events[0..probe.len]);
                try std.testing.expect(probe.alternate_seen);
                try std.testing.expectEqual(@as(i32, 1), probe.after_count);
            },
            .remove => try std.testing.expectEqualSlices(u8, &.{1}, probe.events[0..probe.len]),
            else => unreachable,
        }
        try std.testing.expect(!probe.bad_state);
        try std.testing.expectEqual(@as(u64, 0), h.engine.native_allocation_generation);
    }
}
test "shared thenable fatal ordinary foreign callable and queued GC retain existing host context ownership" {
    var h = try Harness.init();
    defer h.deinit();
    const foreign = c.JS_NewContext(h.engine.runtime) orelse return error.OutOfMemory;
    var foreign_owned = true;
    defer if (foreign_owned) c.JS_FreeContext(foreign);
    const source = "(function(resolve){resolve(31)})";
    const function = c.JS_Eval(foreign, source.ptr, source.len, "foreign-then.js", c.JS_EVAL_TYPE_GLOBAL);
    if (c.JS_IsException(function)) {
        h.engine.freeValue(c.JS_GetException(foreign));
        return error.ForeignThenCompile;
    }
    var function_owned = true;
    defer if (function_owned) c.JS_FreeValue(foreign, function);
    const thenable = try h.scope.object();
    try h.scope.put(thenable, "then", function);
    c.JS_FreeValue(foreign, function);
    function_owned = false;
    const result = h.adopt(thenable);
    defer h.engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result));
    // The scheduled job captured the callable independently of the property.
    try h.scope.set(thenable, "then", c.pi_js_undefined());
    c.JS_FreeContext(foreign);
    foreign_owned = false;
    // Main job context remains host-owned; callable's own realm retains the
    // foreign context. This adds no claim that a job owns its raw ctx pointer.
    c.JS_RunGC(h.engine.runtime);
    try h.pump();
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(h.engine.context, result));
    const value = c.JS_PromiseResult(h.engine.context, result);
    defer h.engine.freeValue(value);
    var number: i32 = undefined;
    if (c.JS_ToInt32(h.engine.context, &number, value) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 31), number);
}

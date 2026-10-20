//! Actual Completion/NodeScope owners under native execution termination.
//! Source only. Uses the real Engine invocation stack, C finalizers and pending
//! events; no result comparator substitutes for native retirement.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const completion = @import("extensions/native_sdk_owned_completion.zig");
const af = @import("extensions/native_async_function.zig");
const Provider = @import("extensions/native_models_stream_scope.zig").Scope;
const NodeScope = @import("extensions/native_node_operation_scope.zig").Scope;
const functions = @import("extensions/native_node_module_callable.zig");

const Kind = enum { sdk, node };
const Mode = enum {
    none, ordinary, fatal, terminate, cancel_only, cancel_ordinary, cancel_fatal,
    mark_initial_then_fatal, clear_initial_then_fatal, cancel_rethrow,
};
const Plan = struct {
    fixture: *Fixture,
    mode: Mode,
    calls: usize = 0,
    saw_invocation: bool = false,
    service_status: c_int = 0,
    saw_active_before_cancel: bool = false,
    inactive_after_cancel: bool = false,
};
const Fixture = struct {
    engine: *em.Engine,
    class_id: c.JSClassID = 0,
    initial: c.JSValue,
    secondary: c.JSValue,
    data: c.JSValue,
    rejected: c.JSValue,
    plans: [16]Plan = undefined,
    count: usize = 0,
    alive: bool = true,
    callback_kind: Kind = .sdk,
    callback_cleanup_index: ?usize = null,

    fn init() !Fixture {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        errdefer engine.deinit();
        engine.native_exception_diagnostics_suppressed += 1;
        const initial = try engine.checked(c.JS_NewError(engine.context));
        errdefer engine.freeValue(initial);
        const secondary = try engine.checked(c.JS_NewError(engine.context));
        errdefer engine.freeValue(secondary);
        // The actual producer creates an old allocation-tagged Error; after
        // its pending ownership is consumed it is rejected Promise DATA.
        _ = engine.throwNativeOutOfMemory();
        const data = c.JS_GetException(engine.context);
        errdefer engine.freeValue(data);
        c.JS_SetUncatchableError(engine.context, data);
        const rejected = try engine.checked(c.JS_PiNewPendingPromise(engine.context));
        errdefer engine.freeValue(rejected);
        const settled = try engine.checked(c.JS_PiSettlePromise(engine.context, rejected, data, true));
        engine.freeValue(settled);
        var class_id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class_id);
        const definition: c.JSClassDef = .{
            .class_name = "Actual termination boundary native carrier",
            .finalizer = finalize,
        };
        if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
        return .{ .engine = engine, .class_id = class_id, .initial = initial,
            .secondary = secondary, .data = data, .rejected = rejected };
    }
    fn clear(self: *Fixture) void {
        // Only teardown uses this. A detached active event is first restored
        // by its real service, then cancelled with the actual pending token.
        _ = c.JS_PiCheckExecutionTermination(self.engine.context);
        c.JS_PiCancelExecutionTermination(self.engine.runtime);
        while (c.JS_HasException(self.engine.context))
            self.engine.freeValue(c.JS_GetException(self.engine.context));
        if (self.engine.captured_exception) |value| {
            self.engine.captured_exception = null;
            self.engine.freeValue(value);
        }
        _ = c.JS_PiCheckExecutionTermination(self.engine.context);
        c.JS_PiCancelExecutionTermination(self.engine.runtime);
        while (c.JS_HasException(self.engine.context))
            self.engine.freeValue(c.JS_GetException(self.engine.context));
    }
    fn deinit(self: *Fixture) void {
        self.alive = false;
        self.clear();
        self.engine.freeValue(self.rejected);
        self.engine.freeValue(self.data);
        self.engine.freeValue(self.secondary);
        self.engine.freeValue(self.initial);
        self.clear();
        self.engine.native_exception_diagnostics_suppressed -= 1;
        self.engine.deinit();
    }
    fn holder(self: *Fixture, mode: Mode) !struct { value: c.JSValue, index: usize } {
        if (self.count == self.plans.len) return error.TooManyActualBoundaryCarriers;
        const index = self.count;
        self.count += 1;
        self.plans[index] = .{ .fixture = self, .mode = mode };
        const value = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, self.class_id));
        _ = c.JS_SetOpaque(value, &self.plans[index]);
        return .{ .value = value, .index = index };
    }
    fn throwInitial(self: *Fixture, fatal: bool) void {
        if (fatal) c.JS_SetUncatchableError(self.engine.context, self.initial);
        _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.initial));
    }
    fn terminate(self: *Fixture) !void {
        c.JS_PiRequestExecutionTermination(self.engine.runtime);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(self.engine.context));
        try std.testing.expect(c.JS_PiIsExecutionTerminating(self.engine.runtime));
    }
};
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const plan: *Plan = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const f = plan.fixture;
    plan.calls += 1;
    if (!f.alive) return;
    const engine = f.engine;
    plan.saw_invocation = engine.native_fatal_invocation != null;
    switch (plan.mode) {
        .none => return,
        .terminate => {
            c.JS_PiRequestExecutionTermination(engine.runtime);
            plan.service_status = c.JS_PiCheckExecutionTermination(engine.context);
            return;
        },
        .cancel_only, .cancel_ordinary, .cancel_fatal, .cancel_rethrow => {
            // The actual service republishes a detached event. Public Cancel
            // applies to that pending event, never to an invented token.
            _ = engine.nativeCallbackResult(c.pi_js_undefined());
            plan.saw_active_before_cancel = c.JS_PiIsExecutionTerminating(engine.runtime);
            if (!plan.saw_active_before_cancel) return;
            if (plan.mode == .cancel_rethrow) {
                const held = c.JS_GetException(engine.context);
                _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, held));
                c.JS_PiCancelExecutionTermination(engine.runtime);
                plan.inactive_after_cancel = !c.JS_PiIsExecutionTerminating(engine.runtime);
                // The held actual native completion remains abrupt, but no
                // event lease is recreated by publishing it after Cancel.
                _ = c.JS_Throw(engine.context, held);
                return;
            }
            c.JS_PiCancelExecutionTermination(engine.runtime);
            plan.inactive_after_cancel = !c.JS_PiIsExecutionTerminating(engine.runtime);
            if (plan.mode == .cancel_only) return;
        },
        .mark_initial_then_fatal => c.JS_SetUncatchableError(engine.context, f.initial),
        .clear_initial_then_fatal => c.JS_ClearUncatchableError(engine.context, f.initial),
        .ordinary, .fatal => {},
    }
    const fatal = switch (plan.mode) {
        .fatal, .cancel_fatal, .mark_initial_then_fatal, .clear_initial_then_fatal => true,
        else => false,
    };
    if (fatal) c.JS_SetUncatchableError(engine.context, f.secondary);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, f.secondary));
}

const SdkOwner = struct { scope: Provider, owned: completion.Completion };
const NodeOwner = struct {
    scope: NodeScope,
    result: c.JSValue,
    host_error: ?anyerror = null,
    data_promise: ?c.JSValue = null, // Borrowed from the fixture until seed().
};
const Owner = struct {
    engine: *em.Engine,
    kind: Kind,
    selected: union(Kind) { sdk: SdkOwner, node: NodeOwner },
    finished: bool = false,

    // Both records are returned before either native invocation is linked.
    fn init(engine: *em.Engine, kind: Kind, result: anyerror!c.JSValue) Owner {
        return switch (kind) {
            .sdk => .{ .engine = engine, .kind = kind, .selected = .{ .sdk = .{
                .scope = .{ .engine = engine },
                .owned = completion.Completion.initValue(engine, result),
            } } },
            .node => .{ .engine = engine, .kind = kind, .selected = .{ .node = .{
                .scope = NodeScope.init(engine),
                .result = if (result) |value| value else |_| c.pi_js_undefined(),
                .host_error = if (result) |_| null else |err| err,
            } } },
        };
    }
    fn initData(f: *Fixture, kind: Kind) !Owner {
        return switch (kind) {
            .sdk => .{ .engine = f.engine, .kind = kind, .selected = .{ .sdk = .{
                .scope = .{ .engine = f.engine },
                .owned = completion.Completion.initAction(f.engine, .{
                    .thrown = try f.engine.checked(c.JS_PromiseResult(f.engine.context, f.rejected)),
                }),
            } } },
            .node => .{ .engine = f.engine, .kind = kind, .selected = .{ .node = .{
                .scope = NodeScope.init(f.engine), .result = c.pi_js_undefined(),
                .data_promise = f.rejected,
            } } },
        };
    }
    fn seed(self: *Owner) !void {
        switch (self.selected) {
            .sdk => {},
            .node => |*n| if (n.data_promise) |promise| {
                n.data_promise = null;
                n.scope.boundary.start();
                const result = self.engine.awaitValueOnly(promise);
                if (result) |unexpected| {
                    self.engine.freeValue(unexpected);
                    return error.ExpectedActualRejectedPromiseData;
                } else |err| {
                    n.host_error = err;
                    if (err == error.JavaScriptException) n.scope.boundary.escaping();
                    if (err == error.JavaScriptException) return;
                    return err;
                }
            },
        }
    }
    fn addRoot(self: *Owner, value: c.JSValue) !void {
        switch (self.selected) {
            .sdk => |*s| { _ = try s.scope.own(value); },
            .node => |*n| { _ = try n.scope.own(value); },
        }
    }
    fn touch(self: *Owner) !void {
        try self.seed();
        self.release(c.pi_js_undefined());
    }
    fn release(self: *Owner, value: c.JSValue) void {
        switch (self.selected) {
            .sdk => |*s| s.owned.release(value),
            .node => |*n| {
                var owned = value;
                n.scope.boundary.release(&owned);
            },
        }
    }
    fn invocationActive(self: *Owner) bool {
        return switch (self.selected) {
            .sdk => |*s| s.owned.invocation.active,
            .node => |*n| n.scope.boundary.invocation.active,
        };
    }
    fn finish(self: *Owner) anyerror!af.Action {
        std.debug.assert(!self.finished);
        self.finished = true;
        self.seed() catch |err| switch (self.selected) {
            .sdk => unreachable,
            .node => |*n| { n.host_error = err; },
        };
        return switch (self.selected) {
            .sdk => |*s| blk: {
                s.owned.releaseScope(&s.scope);
                break :blk s.owned.finishAction();
            },
            .node => |*n| blk: {
                const value = n.result;
                n.result = c.pi_js_undefined();
                const input: anyerror!c.JSValue = if (n.host_error) |err| err else value;
                break :blk .{ .returned = try n.scope.finish(input) };
            },
        };
    }
    fn deinit(self: *Owner) void {
        if (self.finished) return;
        const result = self.finish();
        if (result) |action| freeAction(self.engine, action) else |_| {}
    }
};
fn freeAction(engine: *em.Engine, action: af.Action) void {
    switch (action) { .returned, .thrown, .awaited => |value| engine.freeValue(value) }
}
const Expected = enum { ordinary, fatal, termination };
fn expectCompletion(f: *Fixture, owner: *Owner, expected: Expected, reason: c.JSValue) !void {
    const result = owner.finish();
    if (result) |action| {
        defer freeAction(f.engine, action);
        try std.testing.expect(expected == .ordinary and owner.kind == .sdk);
        try std.testing.expect(action == .thrown);
        try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, action.thrown, reason));
        try std.testing.expect(!c.JS_PiIsExecutionTermination(action.thrown));
    } else |err| {
        try std.testing.expectEqual(
            if (expected == .termination) error.ExecutionTerminated else error.JavaScriptException, err);
        if (expected == .termination) {
            try std.testing.expect(f.engine.captured_exception == null);
        } else {
            const actual = f.engine.captured_exception orelse return error.RequiredActualBoundaryReason;
            try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, actual, reason));
            try std.testing.expect(!c.JS_PiIsExecutionTermination(actual));
        }
    }
    try std.testing.expect(!owner.invocationActive());
    try std.testing.expect(f.engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 1), f.engine.native_exception_diagnostics_suppressed);
}
fn expectPrivatePending(f: *Fixture, active: bool) !void {
    try std.testing.expect(c.JS_HasException(f.engine.context));
    const was_active = c.JS_PiIsExecutionTerminating(f.engine.runtime);
    const reason = c.JS_GetException(f.engine.context);
    // Restore before assertions so even a failed assertion has real teardown.
    _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, reason));
    defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
    try std.testing.expectEqual(active, was_active);
    try std.testing.expectEqual(@as(c_int, if (active) 1 else -1),
        c.JS_PiNativePendingPriority(f.engine.runtime, reason));
    try std.testing.expect(f.engine.captured_exception == null);
}
fn expectPlan(f: *Fixture, index: usize) !void {
    try std.testing.expectEqual(@as(usize, 1), f.plans[index].calls);
    try std.testing.expect(f.plans[index].saw_invocation);
}
fn expectCancel(f: *Fixture, index: usize) !void {
    try expectPlan(f, index);
    try std.testing.expect(f.plans[index].saw_active_before_cancel);
    try std.testing.expect(f.plans[index].inactive_after_cancel);
}
fn makeResultOwner(f: *Fixture, kind: Kind) !struct { owner: Owner, result_index: usize, result_value: c.JSValue } {
    const result = try f.holder(.none);
    return .{ .owner = Owner.init(f.engine, kind, result.value), .result_index = result.index, .result_value = result.value };
}

test "native host termination normal owners retire roots before returning the actual result" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.none);
        try setup.owner.addRoot(root.value);
        const result = try setup.owner.finish();
        defer freeAction(f.engine, result);
        try std.testing.expect(result == .returned);
        try std.testing.expect(c.JS_IsStrictEqual(f.engine.context, result.returned, setup.result_value));
        try expectPlan(&f, root.index);
        try std.testing.expectEqual(@as(usize, 0), f.plans[setup.result_index].calls);
        try std.testing.expect(!setup.owner.invocationActive() and f.engine.native_fatal_invocation == null);
        try std.testing.expect(f.engine.captured_exception == null and !c.JS_HasException(f.engine.context));
    }
}
test "native host termination actual entry event survives owned roots and result retirement" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.none);
        try setup.owner.addRoot(root.value);
        try f.terminate();
        try setup.owner.touch();
        try std.testing.expect(setup.owner.invocationActive());
        try expectCompletion(&f, &setup.owner, .termination, c.pi_js_undefined());
        try expectPlan(&f, root.index); try expectPlan(&f, setup.result_index);
        try expectPrivatePending(&f, true);
    }
}
test "native host termination genuine cleanup event displaces the owned normal result" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.terminate);
        try setup.owner.addRoot(root.value);
        try expectCompletion(&f, &setup.owner, .termination, c.pi_js_undefined());
        try expectPlan(&f, root.index); try expectPlan(&f, setup.result_index);
        try std.testing.expectEqual(@as(c_int, -1), f.plans[root.index].service_status);
        try expectPrivatePending(&f, true);
    }
}
test "native host termination cancel during cleanup preserves only the native abrupt completion" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.cancel_only);
        try setup.owner.addRoot(root.value);
        try f.terminate(); try setup.owner.touch();
        try expectCompletion(&f, &setup.owner, .termination, c.pi_js_undefined());
        try expectCancel(&f, root.index); try expectPlan(&f, setup.result_index);
        try expectPrivatePending(&f, false);
    }
}
test "native host termination cancellation allows a later actual ordinary cleanup reason" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.cancel_ordinary);
        try setup.owner.addRoot(root.value);
        try f.terminate(); try setup.owner.touch();
        try expectCompletion(&f, &setup.owner, .ordinary, f.secondary);
        try expectCancel(&f, root.index); try expectPlan(&f, setup.result_index);
        try std.testing.expectEqual(@as(c_int, 0), c.JS_PiCheckExecutionTermination(f.engine.context));
    }
}
test "native host termination cancellation allows a later actual generic fatal cleanup" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.cancel_fatal);
        try setup.owner.addRoot(root.value);
        try f.terminate(); try setup.owner.touch();
        try expectCompletion(&f, &setup.owner, .fatal, f.secondary);
        try expectCancel(&f, root.index); try expectPlan(&f, setup.result_index);
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
        try std.testing.expectEqual(@as(c_int, 0), c.JS_PiCheckExecutionTermination(f.engine.context));
    }
}
test "native host termination earlier generic fatal retires a losing cleanup event lease" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.terminate);
        try setup.owner.addRoot(root.value);
        f.throwInitial(true); try setup.owner.touch();
        try expectCompletion(&f, &setup.owner, .fatal, f.initial);
        try expectPlan(&f, root.index); try expectPlan(&f, setup.result_index);
        try std.testing.expectEqual(@as(c_int, -1), f.plans[root.index].service_status);
        try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
        try std.testing.expectEqual(@as(c_int, 0), c.JS_PiCheckExecutionTermination(f.engine.context));
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
    }
}
test "native host termination cached ordinary owner remains ordinary after its flag is set" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.mark_initial_then_fatal);
        try setup.owner.addRoot(root.value);
        f.throwInitial(false); try setup.owner.touch();
        try expectCompletion(&f, &setup.owner, .fatal, f.secondary);
        try expectPlan(&f, root.index); try expectPlan(&f, setup.result_index);
        try std.testing.expect(c.JS_IsUncatchableError(f.initial));
    }
}
test "native host termination cached generic fatal survives later clearing of its public flag" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.clear_initial_then_fatal);
        try setup.owner.addRoot(root.value);
        f.throwInitial(true); try setup.owner.touch();
        try expectCompletion(&f, &setup.owner, .fatal, f.initial);
        try expectPlan(&f, root.index); try expectPlan(&f, setup.result_index);
    }
}
test "native host termination flagged actual Promise DATA stays ordinary through ordinary cleanup" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var owner = try Owner.initData(&f, kind); defer owner.deinit();
        const root = try f.holder(.ordinary);
        try owner.addRoot(root.value); try owner.touch();
        try expectCompletion(&f, &owner, .ordinary, f.data);
        try expectPlan(&f, root.index);
        try std.testing.expect(c.pi_js_native_allocation_error_generation(f.data) != 0);
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
    }
}
test "native host termination actual event overrides flagged DATA without publishing it as a native token" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var owner = try Owner.initData(&f, kind); defer owner.deinit();
        const root = try f.holder(.terminate);
        try owner.addRoot(root.value); try owner.touch();
        try expectCompletion(&f, &owner, .termination, c.pi_js_undefined());
        try expectPlan(&f, root.index);
        try expectPrivatePending(&f, true);
        try std.testing.expect(c.JS_IsUncatchableError(f.data));
    }
}
test "native host termination cancelled actual token remains native through repeated cleanup ownership" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        var setup = try makeResultOwner(&f, kind); defer setup.owner.deinit();
        const root = try f.holder(.cancel_rethrow);
        try setup.owner.addRoot(root.value);
        try f.terminate(); try setup.owner.touch();
        try expectCompletion(&f, &setup.owner, .termination, c.pi_js_undefined());
        try expectCancel(&f, root.index); try expectPlan(&f, setup.result_index);
        try expectPrivatePending(&f, false);
    }
}
fn cancelledFailure(f: *Fixture) anyerror!c.JSValue {
    c.JS_PiRequestExecutionTermination(f.engine.runtime);
    const status = c.JS_PiCheckExecutionTermination(f.engine.context);
    if (status != -1) return error.RequiredActualTerminationFailure;
    const failed = f.engine.checked(c.pi_js_exception());
    c.JS_PiCancelExecutionTermination(f.engine.runtime);
    return failed;
}
test "native host termination explicit error after Cancel survives without pending or diagnostic authority" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        const root = try f.holder(.none);
        var root_owned = true;
        defer if (root_owned) f.engine.freeValue(root.value);
        const failure = cancelledFailure(&f);
        // This independently retained flagged value is unrelated history.
        try std.testing.expect(f.engine.captured_exception == null);
        f.engine.captured_exception = c.JS_DupValue(f.engine.context, f.data);
        var owner = Owner.init(f.engine, kind, failure); defer owner.deinit();
        root_owned = false;
        try owner.addRoot(root.value);
        try expectCompletion(&f, &owner, .termination, c.pi_js_undefined());
        try expectPlan(&f, root.index);
        try std.testing.expect(!c.JS_HasException(f.engine.context));
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
        try std.testing.expect(c.JS_IsUncatchableError(f.data));
    }
}
test "native host termination later actual cleanup replaces an explicit already cancelled native error" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        const root = try f.holder(.ordinary);
        var root_owned = true;
        defer if (root_owned) f.engine.freeValue(root.value);
        const failure = cancelledFailure(&f);
        var owner = Owner.init(f.engine, kind, failure); defer owner.deinit();
        root_owned = false;
        try owner.addRoot(root.value);
        try expectCompletion(&f, &owner, .ordinary, f.secondary);
        try expectPlan(&f, root.index);
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
    }
}
fn cancelledOwnerBody(scope: anytype, f: *Fixture) anyerror!c.JSValue {
    const root = try f.holder(.none);
    f.callback_cleanup_index = root.index;
    _ = try scope.own(root.value);
    // This actual Engine error is saved before native Cancel clears its slot.
    // The outer real owner sees that explicit error before retiring this root.
    return cancelledFailure(f);
}
fn cancelledCallbackBody(engine: *em.Engine, _: c.JSValue,
    _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue
{
    const plan: *Plan = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])) orelse
        return error.RequiredActualBoundaryCallbackCarrier));
    const f = plan.fixture;
    return switch (f.callback_kind) {
        .sdk => blk: {
            var scope: Provider = .{ .engine = engine };
            break :blk completion.finishValue(&scope, cancelledOwnerBody(&scope, f));
        },
        .node => blk: {
            var scope = NodeScope.init(engine);
            break :blk scope.finish(cancelledOwnerBody(&scope, f));
        },
    };
}
test "native host termination real ModuleCallable preserves cancelled owner errors at the native return gateway" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        f.callback_kind = kind;
        const carrier = try f.holder(.none);
        defer f.engine.freeValue(carrier.value);
        const callable = try functions.create(f.engine, "actualCancelledBoundary", 0, true,
            cancelledCallbackBody, &.{carrier.value});
        defer f.engine.freeValue(callable);
        const raw = c.JS_Call(f.engine.context, callable, c.pi_js_undefined(), 0, null);
        const was_exception = c.JS_IsException(raw);
        const checked = f.engine.checked(raw); // Consumes the actual raw result.
        if (checked) |unexpected| {
            f.engine.freeValue(unexpected);
            return error.RequiredActualCancelledCallbackFailure;
        } else |err| try std.testing.expectEqual(error.ExecutionTerminated, err);
        try std.testing.expect(was_exception);
        try expectPrivatePending(&f, false);
        try expectPlan(&f, f.callback_cleanup_index orelse return error.RequiredActualCallbackCleanup);
        try std.testing.expect(f.engine.native_fatal_invocation == null);
    }
}
test "native host termination cancelled invocation record does not poison a later normal owned return" {
    inline for (.{ Kind.sdk, Kind.node }) |kind| {
        var f = try Fixture.init(); defer f.deinit();
        const root = try f.holder(.none);
        var root_owned = true;
        defer if (root_owned) f.engine.freeValue(root.value);
        var invocation: em.Engine.NativeInvocation = .{};
        f.engine.enterNativeInvocation(&invocation);
        defer if (invocation.active) {
            const abandoned = f.engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
            f.engine.freeValue(abandoned);
        };
        const failed = cancelledFailure(&f);
        if (failed) |unexpected| { f.engine.freeValue(unexpected); return error.RequiredActualCancelledCall; }
        else |err| try std.testing.expectEqual(error.ExecutionTerminated, err);
        try std.testing.expect(invocation.first != null);
        var owner = Owner.init(f.engine, kind, c.JS_NewInt32(f.engine.context, 37)); defer owner.deinit();
        root_owned = false;
        try owner.addRoot(root.value);
        const result = try owner.finish();
        defer freeAction(f.engine, result);
        try std.testing.expect(result == .returned);
        var number: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.engine.context, &number, result.returned));
        try std.testing.expectEqual(@as(i32, 37), number);
        const outer = f.engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
        defer f.engine.freeValue(outer);
        try std.testing.expect(!c.JS_IsException(outer));
        try std.testing.expect(!c.JS_HasException(f.engine.context));
        try std.testing.expect(f.engine.captured_exception == null);
        try expectPlan(&f, root.index);
        try std.testing.expect(f.engine.native_fatal_invocation == null);
    }
}

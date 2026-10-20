//! Real planned TypeBox activations preserve the native termination owner.
//! This root performs no substitute evaluation or private-result classification.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const node = @import("extensions/native_node_function.zig");
const heap = @import("extensions/native_typebox_continuation.zig");
const c = em.c;

const Mode = enum { active, cancelled, ordinary, generic, data, normal, child, raw_child };
const Cleanup = enum {
    count, cancel, cancel_ordinary, cancel_oom, terminate,
    terminate_request, clear_first_flag, flag_first_terminate,
};
const Token = struct { probe: *Probe, index: usize, action: Cleanup };
const Probe = struct {
    engine: *em.Engine = undefined,
    holder_class: c.JSClassID = 0,
    mode: Mode = .active,
    cleanup: Cleanup = .count,
    child_cancelled: bool = false,
    enabled: bool = true,
    tokens: [8]Token = undefined,
    created: [8]usize = @splat(0),
    retired: [8]usize = @splat(0),
    body: usize = 0,
    child_body: usize = 0,
    after: usize = 0,
    finally_count: usize = 0,
    child_finally: usize = 0,
    cleanup_active: bool = false,
    cleanup_status: c_int = 0,
    body_active: bool = false,
    after_cancel_active: bool = false,
    reasons: [3]c.JSValue = undefined,

    fn holder(self: *Probe, index: usize, action: Cleanup) !c.JSValue {
        self.tokens[index] = .{ .probe = self, .index = index, .action = action };
        const value = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, @intCast(self.holder_class)));
        _ = c.JS_SetOpaque(value, &self.tokens[index]);
        self.created[index] += 1;
        return value;
    }
};
fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    const p = token.probe;
    p.retired[token.index] += 1;
    if (!p.enabled) return;
    const engine = p.engine;
    switch (token.action) {
        .count => {},
        .cancel, .cancel_ordinary, .cancel_oom => {
            // The Machine holds the event off-slot. Genuine reentry republishes
            // that same event before the actual cancellation operation.
            p.cleanup_status = c.JS_PiCheckExecutionTermination(engine.context);
            p.cleanup_active = c.JS_PiIsExecutionTerminating(engine.runtime);
            c.JS_PiCancelExecutionTermination(engine.runtime);
            p.after_cancel_active = c.JS_PiIsExecutionTerminating(engine.runtime);
            if (token.action == .cancel_ordinary)
                _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, p.reasons[1]));
            if (token.action == .cancel_oom)
                _ = engine.throwNativeOutOfMemoryFatal();
        },
        .terminate, .terminate_request, .flag_first_terminate => {
            if (token.action == .flag_first_terminate)
                c.JS_SetUncatchableError(engine.context, p.reasons[0]);
            c.JS_PiRequestExecutionTermination(engine.runtime);
            p.cleanup_status = c.JS_PiCheckExecutionTermination(engine.context);
            p.cleanup_active = c.JS_PiIsExecutionTerminating(engine.runtime);
            if (token.action == .terminate_request)
                c.JS_PiRequestExecutionTermination(engine.runtime);
        },
        .clear_first_flag => c.JS_ClearUncatchableError(engine.context, p.reasons[0]),
    }
}
const Fixture = struct {
    engine: *em.Engine,
    probe: Probe,
    carrier: c.JSValue,

    fn init(self: *Fixture) !void {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        self.* = .{
            .engine = engine,
            .probe = .{ .engine = engine, .reasons = .{ c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined() } },
            .carrier = c.pi_js_undefined(),
        };
        errdefer self.deinit();
        var carrier_class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &carrier_class);
        const carrier_definition: c.JSClassDef = .{ .class_name = "TypeBox termination probe" };
        if (c.JS_NewClass(engine.runtime, carrier_class, &carrier_definition) < 0) return error.OutOfMemory;
        _ = c.JS_NewClassID(engine.runtime, &self.probe.holder_class);
        const holder_definition: c.JSClassDef = .{ .class_name = "TypeBox termination holder", .finalizer = retire };
        if (c.JS_NewClass(engine.runtime, self.probe.holder_class, &holder_definition) < 0) return error.OutOfMemory;
        self.carrier = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(carrier_class)));
        _ = c.JS_SetOpaque(self.carrier, &self.probe);
        for (&self.probe.reasons) |*reason| reason.* = try engine.checked(c.JS_NewError(engine.context));
    }
    fn deinit(self: *Fixture) void {
        self.probe.enabled = false;
        // Clear requests before republishing any detached event for Cancel.
        c.JS_PiCancelExecutionTermination(self.engine.runtime);
        _ = c.JS_PiCheckExecutionTermination(self.engine.context);
        c.JS_PiCancelExecutionTermination(self.engine.runtime);
        while (c.JS_HasException(self.engine.context))
            self.engine.freeValue(c.JS_GetException(self.engine.context));
        self.engine.freeValue(self.carrier);
        for (self.probe.reasons) |reason| self.engine.freeValue(reason);
        self.engine.deinit();
    }
    fn function(self: *Fixture, plan: *const heap.Plan) !c.JSValue {
        return node.createPlanned(self.engine, "termination-plan", 1, legacy, &.{self.carrier}, true, plan);
    }
    fn call(self: *Fixture, function_value: c.JSValue, args: []const c.JSValue) c.JSValue {
        return c.JS_Call(self.engine.context, function_value, c.pi_js_undefined(), @intCast(args.len), @constCast(args.ptr));
    }
    fn expectNative(self: *Fixture, result: c.JSValue, active: bool) !void {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.engine.context));
        try std.testing.expectEqual(active, c.JS_PiIsExecutionTerminating(self.engine.runtime));
        const reason = c.JS_GetException(self.engine.context);
        defer self.engine.freeValue(reason);
        try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expectEqual(@as(c_int, if (active) 1 else -1), c.JS_PiNativePendingPriority(self.engine.runtime, reason));
        if (active) {
            _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason));
            c.JS_PiCancelExecutionTermination(self.engine.runtime);
        }
    }
    fn expectReason(self: *Fixture, result: c.JSValue, expected: c.JSValue, fatal: bool) !void {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.engine.context));
        const reason = c.JS_GetException(self.engine.context);
        defer self.engine.freeValue(reason);
        try std.testing.expect(c.JS_IsSameValue(self.engine.context, expected, reason));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(reason));
        try std.testing.expect(!c.JS_PiIsExecutionTermination(reason));
    }
    fn retiredOnce(self: *Fixture, index: usize) !void {
        try std.testing.expectEqual(@as(usize, 1), self.probe.created[index]);
        try std.testing.expectEqual(@as(usize, 1), self.probe.retired[index]);
        try std.testing.expectEqual(@as(usize, 0), self.engine.native_exception_diagnostics_suppressed);
    }
};
fn legacy(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    return error.LegacyBodyMustNotExecute;
}
fn probeOf(a: *heap.Activation) *Probe {
    return @ptrCast(@alignCast(c.JS_GetOpaque(a.roots[0], c.JS_GetClassID(a.roots[0])).?));
}
fn enter(a: *heap.Activation) !heap.Action {
    const p = probeOf(a);
    _ = try a.scope.own(try p.holder(0, p.cleanup));
    return .{ .enter_finally = .{ .handler = 3, .next = 1 } };
}
fn terminate(p: *Probe, cancel: bool) anyerror!void {
    c.JS_PiRequestExecutionTermination(p.engine.runtime);
    if (c.JS_PiCheckExecutionTermination(p.engine.context) != -1) return error.TerminationWasNotServiced;
    p.body_active = c.JS_PiIsExecutionTerminating(p.engine.runtime);
    if (cancel) {
        c.JS_PiCancelExecutionTermination(p.engine.runtime);
        p.after_cancel_active = c.JS_PiIsExecutionTerminating(p.engine.runtime);
    }
    return error.ExecutionTerminated;
}
fn body(a: *heap.Activation) !heap.Action {
    const p = probeOf(a);
    p.body += 1;
    switch (p.mode) {
        .active => { try terminate(p, false); unreachable; },
        .cancelled => { try terminate(p, true); unreachable; },
        .ordinary => return .{ .thrown = p.reasons[0] },
        .generic => {
            c.JS_SetUncatchableError(a.engine().context, p.reasons[0]);
            _ = c.JS_Throw(a.engine().context, c.JS_DupValue(a.engine().context, p.reasons[0]));
            return error.JavaScriptException;
        },
        .data => return .{ .returned = p.reasons[0] },
        .normal => return .{ .returned = c.JS_NewInt32(a.engine().context, 37) },
        .child, .raw_child => return .{ .call = .{
            .function = a.args[0], .receiver = c.pi_js_undefined(),
            .args = a.values[0..0], .result = 0, .next = 2,
        } },
    }
}
fn after(a: *heap.Activation) !heap.Action {
    probeOf(a).after += 1;
    return .{ .returned = a.values[0] };
}
fn finally(a: *heap.Activation) !heap.Action {
    probeOf(a).finally_count += 1;
    return .finish_finally;
}
const steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{ enter, body, after, finally };
const plan: heap.Plan = .{ .source_callback = legacy, .slots = 1, .entry = 0, .steps = &steps };
fn childEnter(a: *heap.Activation) !heap.Action {
    _ = try a.scope.own(try probeOf(a).holder(1, .count));
    return .{ .enter_finally = .{ .handler = 2, .next = 1 } };
}
fn childBody(a: *heap.Activation) !heap.Action {
    const p = probeOf(a);
    p.child_body += 1;
    try terminate(p, p.child_cancelled);
    unreachable;
}
fn childFinally(a: *heap.Activation) !heap.Action {
    probeOf(a).child_finally += 1;
    return .finish_finally;
}
const child_steps = [_]*const fn (*heap.Activation) anyerror!heap.Action{ childEnter, childBody, childFinally };
const child_plan: heap.Plan = .{ .source_callback = legacy, .slots = 0, .entry = 0, .steps = &child_steps };
fn rawChild(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
    std.debug.assert(engine == p.engine);
    p.child_body += 1;
    try terminate(p, true);
    unreachable;
}

test "TypeBox native termination active step skips finally and retires its actual frame" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectNative(result, true);
    try std.testing.expect(f.probe.body_active);
    try std.testing.expectEqual(@as(usize, 1), f.probe.body);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(usize, 0), f.probe.after);
    try std.testing.expect(f.engine.captured_exception == null);
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try f.retiredOnce(0);
}
test "TypeBox native termination cancelled step keeps native unwind apart from diagnostic DATA" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .cancelled;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[2]);
    f.engine.captured_exception = c.JS_DupValue(f.engine.context, f.probe.reasons[2]);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectNative(result, false);
    try std.testing.expect(f.probe.body_active);
    try std.testing.expect(!f.probe.after_cancel_active);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, f.probe.reasons[2], f.engine.captured_exception.?));
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try f.retiredOnce(0);
}
test "TypeBox native termination planned child unwinds both actual finally owners" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .child;
    const child = try f.function(&child_plan); defer f.engine.freeValue(child);
    const parent = try f.function(&plan); defer f.engine.freeValue(parent);
    const result = f.call(parent, &.{child}); defer f.engine.freeValue(result);
    try f.expectNative(result, true);
    try std.testing.expectEqual(@as(usize, 1), f.probe.child_body);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(usize, 0), f.probe.child_finally);
    try std.testing.expectEqual(@as(usize, 0), f.probe.after);
    try f.retiredOnce(0); try f.retiredOnce(1);
}
test "TypeBox native termination cancelled planned child never resumes either guest frame" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .child; f.probe.child_cancelled = true;
    const child = try f.function(&child_plan); defer f.engine.freeValue(child);
    const parent = try f.function(&plan); defer f.engine.freeValue(parent);
    const result = f.call(parent, &.{child}); defer f.engine.freeValue(result);
    try f.expectNative(result, false);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(usize, 0), f.probe.child_finally);
    try std.testing.expectEqual(@as(usize, 0), f.probe.after);
    try std.testing.expect(f.engine.captured_exception == null);
    try f.retiredOnce(0); try f.retiredOnce(1);
}
test "TypeBox native termination actual callback failure stays native through Machine call" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .raw_child;
    const child = try node.createArrow(f.engine, "cancelled-native-child", 0, rawChild, &.{f.carrier});
    defer f.engine.freeValue(child);
    const parent = try f.function(&plan); defer f.engine.freeValue(parent);
    const result = f.call(parent, &.{child}); defer f.engine.freeValue(result);
    try f.expectNative(result, false);
    try std.testing.expectEqual(@as(usize, 1), f.probe.child_body);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(usize, 0), f.probe.after);
    try std.testing.expect(f.engine.captured_exception == null);
    try f.retiredOnce(0);
}
test "TypeBox native termination cleanup can cancel a detached event without reviving finally" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.cleanup = .cancel;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectNative(result, false);
    try std.testing.expectEqual(@as(c_int, -1), f.probe.cleanup_status);
    try std.testing.expect(f.probe.cleanup_active);
    try std.testing.expect(!f.probe.after_cancel_active);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try f.retiredOnce(0);
}
test "TypeBox native termination cancelled cleanup permits its later actual ordinary reason" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.cleanup = .cancel_ordinary;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectReason(result, f.probe.reasons[1], false);
    try std.testing.expect(f.probe.cleanup_active);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, f.probe.reasons[1], f.engine.captured_exception.?));
    try f.retiredOnce(0);
}
test "TypeBox native termination cancelled cleanup permits its later actual allocation fatal" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.cleanup = .cancel_oom;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const before = f.engine.native_allocation_generation;
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectReason(result, f.engine.native_allocation_exception.?, true);
    try std.testing.expectEqual(before + 1, f.engine.native_allocation_generation);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
    try f.retiredOnce(0);
}
test "TypeBox native termination losing cleanup event leaves the later request unserviced" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .generic; f.probe.cleanup = .terminate_request;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectReason(result, f.probe.reasons[0], true);
    try std.testing.expect(f.probe.cleanup_active);
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.engine.runtime));
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try f.retiredOnce(0);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.engine.context));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.engine.runtime));
    try std.testing.expectEqual(@as(u64, 2), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    c.JS_PiCancelExecutionTermination(f.engine.runtime);
}
test "TypeBox native termination cached generic fatal survives a later public flag clear" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .generic; f.probe.cleanup = .clear_first_flag;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectReason(result, f.probe.reasons[0], true);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(u64, 0), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try f.retiredOnce(0);
}
test "TypeBox native termination retains ordinary cleanup override and real finally behavior" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .ordinary; f.probe.cleanup = .cancel_ordinary;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectReason(result, f.probe.reasons[1], false);
    try std.testing.expectEqual(@as(c_int, 0), f.probe.cleanup_status);
    try std.testing.expect(!f.probe.cleanup_active);
    try std.testing.expectEqual(@as(usize, 1), f.probe.finally_count);
    try std.testing.expectEqual(@as(u64, 0), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try f.retiredOnce(0);
}
test "TypeBox native termination cached ordinary reason cannot acquire fatal authority during cleanup" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .ordinary; f.probe.cleanup = .flag_first_terminate;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectNative(result, true);
    try std.testing.expectEqual(@as(usize, 1), f.probe.finally_count);
    try std.testing.expect(f.probe.cleanup_active);
    try std.testing.expect(c.JS_IsUncatchableError(f.probe.reasons[0]));
    try f.retiredOnce(0);
}
test "TypeBox native termination returned flagged Error remains DATA through actual finally" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .data;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[0]);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, f.probe.reasons[0], result));
    try std.testing.expectEqual(@as(usize, 1), f.probe.finally_count);
    try std.testing.expect(f.engine.captured_exception == null);
    try f.retiredOnce(0);
}
test "TypeBox native termination explicit planned throw establishes actual generic authority" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .ordinary;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[0]);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectReason(result, f.probe.reasons[0], true);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(u64, 0), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try f.retiredOnce(0);
}
test "TypeBox native termination during captured-slot retirement preempts the planned ordinary throw" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.probe.mode = .ordinary;
    const function_value = try f.function(&plan); defer f.engine.freeValue(function_value);
    f.engine.captured_exception = try f.probe.holder(2, .terminate);
    const result = f.call(function_value, &.{}); defer f.engine.freeValue(result);
    try f.expectNative(result, true);
    try std.testing.expect(f.probe.cleanup_active);
    try std.testing.expectEqual(@as(usize, 0), f.probe.finally_count);
    try std.testing.expectEqual(@as(usize, 0), f.probe.after);
    try std.testing.expect(f.engine.captured_exception == null);
    try f.retiredOnce(0); try f.retiredOnce(2);
}

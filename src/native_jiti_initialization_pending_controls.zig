//! Prepared causal controls, never executed. All wrappers delegate actual
//! real TTY/color functions; no fake provider or positive bootstrap is used.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const colors = @import("extensions/native_jiti_colors.zig");
const utilities = @import("extensions/native_jiti_utils.zig");
const shared = @import("extensions/native_jiti_shared_dependencies.zig");
pub const Cause = enum { ordinary, fresh_native_oom };
pub const TtyBoundary = enum { has_colors_getter, has_colors_call };
const Probe = struct {
    engine: *v.em.Engine,
    allocator: *std.testing.FailingAllocator,
    reason: c.JSValue,
    observed: c.JSValue,
    cause: Cause,
    calls: usize = 0,
    fault_at: usize,
    triggered: bool = false,
    fn pending(self: *Probe) void {
        self.triggered = true;
        if (self.cause == .fresh_native_oom) {
            _ = self.engine.throwNativeOutOfMemory();
            const reason = c.JS_GetException(self.engine.context);
            self.observed = c.JS_DupValue(self.engine.context, reason);
            _ = c.JS_Throw(self.engine.context, reason);
        } else {
            self.observed = c.JS_DupValue(self.engine.context, self.reason);
            _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.reason));
        }
        // The real delegated return is already owned. Any later host allocation
        // before event capture now fails, making an outer-only guard insufficient.
        self.engine.gpa = self.allocator.allocator();
    }
};
fn probeOf(roots: [*c]c.JSValue) *Probe {
    return @ptrCast(@alignCast(c.JS_GetOpaque(roots[1], c.JS_GetClassID(roots[1])).?));
}
fn delegate(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = probeOf(roots);
    const actual = c.JS_Call(context, roots[0], receiver, argc, argv);
    if (c.JS_IsException(actual) or c.JS_HasException(context)) return actual;
    probe.calls += 1;
    if (!probe.triggered and probe.calls == probe.fault_at) probe.pending();
    return actual;
}
fn getter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = probeOf(roots);
    const actual = c.JS_DupValue(context, roots[0]);
    if (!probe.triggered) probe.pending();
    return actual;
}
fn holder(engine: *v.em.Engine, probe: *Probe) !c.JSValue {
    var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Scoped actual initialization pending probe" };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), id));
    _ = c.JS_SetOpaque(object, probe); return object;
}
fn wrapper(engine: *v.em.Engine, actual: c.JSValue, cell: c.JSValue, is_getter: bool) !c.JSValue {
    var roots = [_]c.JSValue{ actual, cell };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, if (is_getter) getter else delegate, "observedActualInitialization", if (is_getter) 0 else 1, 0, roots.len, &roots));
}
fn failure(engine: *v.em.Engine, attempt: anyerror!c.JSValue) !void {
    if (attempt) |unexpected| { engine.freeValue(unexpected); return error.UnexpectedInitializationSuccess; }
    else |err| try std.testing.expect(err == error.JavaScriptException);
}
fn observed(engine: *v.em.Engine, probe: *Probe, previous_generation: u64) !void {
    try std.testing.expect(probe.triggered);
    try std.testing.expectEqual(@as(usize, 0), probe.allocator.allocations);
    try std.testing.expect(!probe.allocator.has_induced_failure);
    const captured = engine.captured_exception orelse return error.MissingInitializationPendingEvent;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, probe.observed));
    if (probe.cause == .fresh_native_oom) {
        try std.testing.expect(engine.native_allocation_generation != previous_generation);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, engine.native_allocation_exception orelse return error.MissingActualFreshInitializationOOM));
    } else {
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, probe.reason));
        try std.testing.expectEqual(previous_generation, engine.native_allocation_generation);
    }
    try std.testing.expect(engine.last_error == null);
    try std.testing.expect(!c.JS_HasException(engine.context));
    engine.captured_exception = null; engine.freeValue(captured);
}
/// Actual completed TTY default object and real hasColors required. Exclusive
/// Engine/no jobs: the GPA decorator is armed only after the actual delegate.
pub fn verifyTtyImmediateBoundary(engine: *v.em.Engine, actual_tty: c.JSValue, ordinary_reason: c.JSValue, cause: Cause, boundary: TtyBoundary) !void {
    try ttyBoundary(engine, actual_tty, ordinary_reason, cause, boundary, null);
}
fn sharedAttempt(engine: *v.em.Engine, actual: shared.Inputs) !c.JSValue {
    const graph = try shared.create(engine, actual); defer graph.deinit(engine);
    return c.JS_DupValue(engine.context, graph.utilities);
}
/// Same actual hasColors event through the REAL full shared initializer. The
/// pending-success failure must remove its private reservation and publish no
/// namespace; real provider graph initialization is not substituted.
pub fn verifySharedImmediateRollback(engine: *v.em.Engine, actual: shared.Inputs, ordinary_reason: c.JSValue, cause: Cause) !void {
    try std.testing.expect(!engine.native_module_values.contains("#pi-native:jiti2.7-shared-dependencies"));
    const tty = try v.js.get(engine, actual.tty, "default"); defer engine.freeValue(tty);
    try ttyBoundary(engine, tty, ordinary_reason, cause, .has_colors_call, actual);
}
fn ttyBoundary(engine: *v.em.Engine, actual_tty: c.JSValue, ordinary_reason: c.JSValue, cause: Cause, boundary: TtyBoundary, actual_shared: ?shared.Inputs) !void {
    try std.testing.expect(engine.captured_exception == null);
    const backing = engine.gpa;
    var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = 0 });
    var probe: Probe = .{ .engine = engine, .allocator = &failing, .reason = ordinary_reason, .observed = c.pi_js_undefined(), .cause = cause, .fault_at = 1 };
    defer engine.freeValue(probe.observed);
    const cell = try holder(engine, &probe); defer engine.freeValue(cell);
    const constructor = try v.js.get(engine, actual_tty, "WriteStream"); defer engine.freeValue(constructor);
    const prototype = try v.js.get(engine, constructor, "prototype"); defer engine.freeValue(prototype);
    const atom = c.JS_NewAtom(engine.context, "hasColors"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var original: c.JSPropertyDescriptor = undefined;
    if (c.JS_GetOwnProperty(engine.context, &original, prototype, atom) != 1) return error.RequiredActualHasColors;
    defer engine.freeValue(original.value); defer engine.freeValue(original.getter); defer engine.freeValue(original.setter);
    if (!c.JS_IsFunction(engine.context, original.value) or !c.JS_IsUndefined(original.getter) or !c.JS_IsUndefined(original.setter)) return error.RequiredActualHasColorsDataMethod;
    const delegated = try wrapper(engine, original.value, cell, false); defer engine.freeValue(delegated);
    const installed = if (boundary == .has_colors_getter) try wrapper(engine, delegated, cell, true) else c.JS_DupValue(engine.context, delegated);
    defer engine.freeValue(installed);
    if (boundary == .has_colors_getter) {
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, installed), c.pi_js_undefined(), original.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE)) < 0) return v.js.capture(engine);
    } else if (c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, installed), original.flags & c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    defer { _ = c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, original.value), original.flags & c.JS_PROP_C_W_E); }
    const generation = engine.native_allocation_generation;
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    const modules = engine.native_module_values.count();
    const namespace_counter = engine.native_namespace_counter;
    const attempt = if (actual_shared) |actual| sharedAttempt(engine, actual) else colors.create(engine, actual_tty);
    engine.gpa = backing; // Restore same backing BEFORE assertions/GC/teardown.
    try failure(engine, attempt);
    try observed(engine, &probe, generation);
    try std.testing.expectEqual(@as(usize, if (boundary == .has_colors_getter) 0 else 1), probe.calls);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
    if (actual_shared != null) {
        try std.testing.expectEqual(modules, engine.native_module_values.count());
        try std.testing.expectEqual(namespace_counter, engine.native_namespace_counter);
    }
}
const color_names = .{ "gray", "green", "blue", "yellow", "cyan", "red" };
/// Run fault_at1..15 for BOTH ordinary/fresh-native causes. All six actual
/// exported color functions are instrumented in place, preserving real bodies.
/// No callback after the fault may run and no utility-function allocation may
/// replace the actual event. Original descriptors are restored before return.
pub fn verifyEachActualColorCall(engine: *v.em.Engine, actual: utilities.Inputs, ordinary_reason: c.JSValue, cause: Cause, fault_at: usize) !void {
    try utilityBoundary(engine, actual, ordinary_reason, cause, fault_at, null);
}
/// Real color export getter returns its SAME delegated function, with an actual
/// pending event. Capture must precede owner/map writes and ALL color calls.
pub fn verifyActualColorGetter(engine: *v.em.Engine, actual: utilities.Inputs, ordinary_reason: c.JSValue, cause: Cause, getter_index: usize) !void {
    if (getter_index >= 6) return error.InvalidActualColorGetterIndex;
    try utilityBoundary(engine, actual, ordinary_reason, cause, 1, getter_index);
}
fn utilityBoundary(engine: *v.em.Engine, actual: utilities.Inputs, ordinary_reason: c.JSValue, cause: Cause, fault_at: usize, getter_index: ?usize) !void {
    if (fault_at < 1 or fault_at > 15) return error.InvalidActualColorCallbackIndex;
    try std.testing.expect(engine.captured_exception == null);
    const backing = engine.gpa;
    var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = 0 });
    var probe: Probe = .{ .engine = engine, .allocator = &failing, .reason = ordinary_reason, .observed = c.pi_js_undefined(), .cause = cause, .fault_at = fault_at };
    defer engine.freeValue(probe.observed);
    const cell = try holder(engine, &probe); defer engine.freeValue(cell);
    var atoms: [6]c.JSAtom = undefined;
    var originals: [6]c.JSPropertyDescriptor = undefined;
    var initialized: usize = 0;
    defer for (0..initialized) |index| {
        _ = c.JS_DefinePropertyValue(engine.context, actual.colors, atoms[index], c.JS_DupValue(engine.context, originals[index].value), originals[index].flags & c.JS_PROP_C_W_E);
        engine.freeValue(originals[index].value); engine.freeValue(originals[index].getter); engine.freeValue(originals[index].setter); c.JS_FreeAtom(engine.context, atoms[index]);
    };
    inline for (color_names, 0..) |name, index| {
        const atom = c.JS_NewAtom(engine.context, name); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        var original: c.JSPropertyDescriptor = undefined;
        if (c.JS_GetOwnProperty(engine.context, &original, actual.colors, atom) != 1) { c.JS_FreeAtom(engine.context, atom); return error.RequiredActualColorOwnMethod; }
        atoms[index] = atom; originals[index] = original; initialized += 1;
        if (!c.JS_IsFunction(engine.context, original.value) or !c.JS_IsUndefined(original.getter) or !c.JS_IsUndefined(original.setter)) return error.RequiredActualColorDataMethod;
        const delegated = try wrapper(engine, original.value, cell, false); defer engine.freeValue(delegated);
        if (getter_index != null and getter_index.? == index) {
            const observed_getter = try wrapper(engine, delegated, cell, true); defer engine.freeValue(observed_getter);
            if (c.JS_DefinePropertyGetSet(engine.context, actual.colors, atom, c.JS_DupValue(engine.context, observed_getter), c.pi_js_undefined(), original.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE)) < 0) return v.js.capture(engine);
        } else if (c.JS_DefinePropertyValue(engine.context, actual.colors, atom, c.JS_DupValue(engine.context, delegated), original.flags & c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    }
    const generation = engine.native_allocation_generation;
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    const attempt = utilities.create(engine, actual);
    engine.gpa = backing;
    try failure(engine, attempt);
    try observed(engine, &probe, generation);
    try std.testing.expectEqual(if (getter_index != null) @as(usize, 0) else fault_at, probe.calls);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
}

//! Prepared negative control on the ACTUAL node:module export record. It
//! injects genuine native getter/finalizer events; no positive fake provider.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
pub fn run(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, success_with_pending: bool, fatal_cleanup: bool) !void {
    return profile(ActualAssembly, engine, actual, success_with_pending, fatal_cleanup, false);
}
pub fn hostOom(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, fatal_cleanup: bool) !void {
    return profile(ActualAssembly, engine, actual, false, fatal_cleanup, true);
}
fn profile(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, success_with_pending: bool, fatal_cleanup: bool, trusted_host_oom: bool) !void {
    const Control = struct {
        const State = struct {
            engine: *v.em.Engine, module: c.JSValue, reason: c.JSValue, replacement: c.JSValue,
            holder_class: c.JSClassID, pending_success: bool, fatal_cleanup: bool,
            next_getter: usize = 0, finalized: usize = 0, live_slot_at_free: bool = false,
            fatal: ?c.JSValue = null, raw_fatal: bool = false,
            trusted_host_oom: bool, real_create_require: c.JSValue, forward: c.JSValue,
            failing: *std.testing.FailingAllocator, armed: bool = false,
        };
        var active: ?*State = null;
        fn createRequireGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; std.debug.assert(context == state.engine.context);
            state.next_getter += 1;
            if (state.trusted_host_oom) return c.JS_DupValue(context, state.forward);
            return c.JS_Throw(context, c.JS_DupValue(context, state.reason));
        }
        fn createRequireForward(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; std.debug.assert(context == state.engine.context);
            const actual = c.JS_Call(context, state.real_create_require, state.module, argc, argv);
            if (!c.JS_IsException(actual)) { state.engine.gpa = state.failing.allocator(); state.armed = true; }
            return actual;
        }
        fn defaultGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; std.debug.assert(context == state.engine.context);
            if (state.pending_success) {
                _ = c.JS_Throw(context, c.JS_DupValue(context, state.reason));
                return c.JS_DupValue(context, state.module);
            }
            const holder = c.JS_NewObjectClass(context, state.holder_class);
            if (c.JS_IsException(holder)) return holder;
            _ = c.JS_SetOpaque(holder, state);
            const getter = c.JS_NewCFunction(context, createRequireGetter, "actualCreateRequireFailure", 0);
            if (c.JS_IsException(getter)) { c.JS_FreeValue(context, holder); return getter; }
            const atom = c.JS_NewAtom(context, "createRequire");
            if (atom == c.JS_ATOM_NULL) { c.JS_FreeValue(context, getter); c.JS_FreeValue(context, holder); return c.JS_Throw(context, c.JS_GetException(context)); }
            defer c.JS_FreeAtom(context, atom);
            if (c.JS_DefinePropertyGetSet(context, holder, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) { c.JS_FreeValue(context, holder); return c.JS_Throw(context, c.JS_GetException(context)); }
            return holder; // Sole owned temporary, no external holder root.
        }
        fn finalize(_: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
            const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)).?));
            state.finalized += 1;
            state.live_slot_at_free = c.JS_HasException(state.engine.context) or state.engine.captured_exception != null;
            if (state.fatal_cleanup) {
                _ = state.engine.throwNativeOutOfMemory();
                const reason = c.JS_GetException(state.engine.context);
                state.fatal = c.JS_DupValue(state.engine.context, reason);
                state.raw_fatal = !c.JS_IsUncatchableError(reason) and c.pi_js_native_allocation_error_generation(reason) == state.engine.native_allocation_generation;
                _ = c.JS_Throw(state.engine.context, reason);
            } else _ = c.JS_Throw(state.engine.context, c.JS_DupValue(state.engine.context, state.replacement));
        }
    };
    try std.testing.expect(Control.active == null);
    const record = engine.native_module_values.get("node:module") orelse return error.RequiredActualNodeModuleRecord;
    const module = (try engine.requireBuiltin("node:module")) orelse return error.RequiredActualNodeModule; defer engine.freeValue(module);
    const atom = c.JS_NewAtom(engine.context, "default"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var original: c.JSPropertyDescriptor = undefined;
    try std.testing.expect(c.JS_GetOwnProperty(engine.context, &original, record, atom) == 1);
    defer { engine.freeValue(original.value); engine.freeValue(original.getter); engine.freeValue(original.setter); }
    defer {
        const flags = (original.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_WRITABLE)) | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
            (if (original.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
        std.debug.assert(c.JS_DefineProperty(engine.context, record, atom, original.value, original.getter, original.setter, flags | c.JS_PROP_THROW) >= 0);
    }
    var holder_class: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &holder_class) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual TTY Assembly Temporary", .finalizer = Control.finalize };
    if (c.JS_NewClass(engine.runtime, holder_class, &definition) < 0) return error.OutOfMemory;
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    const replacement = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(replacement);
    const real_create_require = try engine.checked(c.JS_GetPropertyStr(engine.context, module, "createRequire")); defer engine.freeValue(real_create_require);
    const forward = try engine.checked(c.JS_NewCFunction(engine.context, Control.createRequireForward, "actualCreateRequireThenFailGpa", 1)); defer engine.freeValue(forward);
    const original_gpa = engine.gpa; defer engine.gpa = original_gpa;
    var failing = std.testing.FailingAllocator.init(original_gpa, .{ .fail_index = 0, .resize_fail_index = 0 });
    var state: Control.State = .{ .engine = engine, .module = module, .reason = reason, .replacement = replacement, .holder_class = holder_class, .pending_success = success_with_pending, .fatal_cleanup = fatal_cleanup,
        .trusted_host_oom = trusted_host_oom, .real_create_require = real_create_require, .forward = forward, .failing = &failing };
    defer if (state.fatal) |value| engine.freeValue(value);
    Control.active = &state; defer Control.active = null;
    const require_atom = c.JS_NewAtom(engine.context, "createRequire"); if (require_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, require_atom);
    var original_require: c.JSPropertyDescriptor = undefined;
    try std.testing.expect(c.JS_GetOwnProperty(engine.context, &original_require, module, require_atom) == 1);
    defer { engine.freeValue(original_require.value); engine.freeValue(original_require.getter); engine.freeValue(original_require.setter); }
    defer {
        const flags = (original_require.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_WRITABLE)) | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
            (if (original_require.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
        std.debug.assert(c.JS_DefineProperty(engine.context, module, require_atom, original_require.value, original_require.getter, original_require.setter, flags | c.JS_PROP_THROW) >= 0);
    }
    if (success_with_pending) {
        const next = try engine.checked(c.JS_NewCFunction(engine.context, Control.createRequireGetter, "mustNotReadAfterPending", 0));
        if (c.JS_DefinePropertyGetSet(engine.context, module, require_atom, next, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    }
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, Control.defaultGetter, "actualDefaultBoundary", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, record, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    const generation = engine.native_allocation_generation;
    const unexpected = ActualAssembly.create(engine, actual) catch |err| {
        engine.gpa = original_gpa;
        try std.testing.expect(err == error.JavaScriptException);
        const observed = engine.captured_exception orelse return error.MissingActualTtyAssemblyReason;
        const wanted = if (!success_with_pending and fatal_cleanup) state.fatal orelse return error.MissingActualCleanupFatal else if (trusted_host_oom) engine.native_allocation_exception orelse return error.MissingTrustedAllocationReason else reason;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, observed, wanted));
        try std.testing.expectEqual(@as(usize, if (success_with_pending) 0 else 1), state.next_getter);
        try std.testing.expectEqual(@as(usize, if (success_with_pending) 0 else 1), state.finalized);
        try std.testing.expect(!state.live_slot_at_free);
        if (trusted_host_oom) {
            try std.testing.expect(state.armed and failing.has_induced_failure);
            try std.testing.expectEqual(@as(u64, 1), engine.native_allocation_generation -% generation);
            try std.testing.expect(c.JS_IsUncatchableError(observed));
            try std.testing.expect(!c.JS_IsStrictEqual(engine.context, observed, replacement));
        }
        if (!success_with_pending and fatal_cleanup) try std.testing.expect(state.raw_fatal and c.JS_IsUncatchableError(observed));
        if (trusted_host_oom or (!success_with_pending and fatal_cleanup)) c.JS_ClearUncatchableError(engine.context, observed);
        engine.captured_exception = null; engine.freeValue(observed);
        try std.testing.expect(!c.JS_HasException(engine.context));
        return;
    };
    unexpected.deinit(engine); return error.ExpectedActualTtyAssemblyEvent;
}

/// A fresh real Windows composition: installing a throwing getter on the real
/// os.release must leave initialization untouched, then throw at first depth.
pub fn lazyOs(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs) !void {
    const Control = struct {
        const State = struct { engine: *v.em.Engine, reason: c.JSValue, reads: usize = 0 };
        var active: ?*State = null;
        fn getter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; std.debug.assert(state.engine.context == context); state.reads += 1;
            return c.JS_Throw(context, c.JS_DupValue(context, state.reason));
        }
    };
    try std.testing.expect(Control.active == null);
    const os = (try engine.requireBuiltin("os")) orelse return error.RequiredActualOs; defer engine.freeValue(os);
    const atom = c.JS_NewAtom(engine.context, "release"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var original: c.JSPropertyDescriptor = undefined;
    try std.testing.expect(c.JS_GetOwnProperty(engine.context, &original, os, atom) == 1);
    defer { engine.freeValue(original.value); engine.freeValue(original.getter); engine.freeValue(original.setter); }
    defer {
        const flags = (original.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_WRITABLE)) | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
            (if (original.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
        std.debug.assert(c.JS_DefineProperty(engine.context, os, atom, original.value, original.getter, original.setter, flags | c.JS_PROP_THROW) >= 0);
    }
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    var state: Control.State = .{ .engine = engine, .reason = reason }; Control.active = &state; defer Control.active = null;
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, Control.getter, "actualLazyOsRelease", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, os, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    const exports = try ActualAssembly.create(engine, actual); defer exports.deinit(engine);
    try std.testing.expectEqual(@as(usize, 0), state.reads);
    const write = try engine.checked(c.JS_GetPropertyStr(engine.context, exports.tty, "WriteStream")); defer engine.freeValue(write);
    const prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, write, "prototype")); defer engine.freeValue(prototype);
    const depth = try engine.checked(c.JS_GetPropertyStr(engine.context, prototype, "getColorDepth")); defer engine.freeValue(depth);
    const env = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())); defer engine.freeValue(env);
    var args = [_]c.JSValue{env};
    const result = c.JS_Call(engine.context, depth, prototype, 1, &args); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const observed = c.JS_GetException(engine.context); defer engine.freeValue(observed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, observed, reason));
    try std.testing.expectEqual(@as(usize, 1), state.reads);
}

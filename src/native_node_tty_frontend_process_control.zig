//! Prepared control on the genuine active embedded frontend. No fake bridge,
//! provider or positive namespace. The live process getter injects the actual
//! pending/sole-holder boundary BEFORE builtin initialization is permitted.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const Bootstrap = @import("extensions/native_node_tty_frontend_assembly.zig").Bootstrap;
fn restore(engine: *v.em.Engine, global: c.JSValue, atom: c.JSAtom, original: c.JSPropertyDescriptor) void {
    const flags = (original.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_WRITABLE)) | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
        (if (original.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
    std.debug.assert(c.JS_DefineProperty(engine.context, global, atom, original.value, original.getter, original.setter, flags | c.JS_PROP_THROW) >= 0);
}
pub fn run(comptime ActualFrontend: type, bootstrap: *const Bootstrap, canonical_provider: anytype, actual_net: c.JSValue, fatal_cleanup: bool) !void {
    const Control = struct {
        const State = struct { engine: *v.em.Engine, reason: c.JSValue, ordinary: c.JSValue, id: c.JSClassID, fatal_cleanup: bool, reads: usize = 0, frees: usize = 0, slot_live: bool = false, fatal: ?c.JSValue = null, raw: bool = false };
        var active: ?*State = null;
        fn getter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; std.debug.assert(context == state.engine.context); state.reads += 1;
            const holder = c.JS_NewObjectClass(context, state.id); if (c.JS_IsException(holder)) return holder;
            _ = c.JS_SetOpaque(holder, state);
            _ = c.JS_Throw(context, c.JS_DupValue(context, state.reason));
            return holder;
        }
        fn finalize(_: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
            const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)).?));
            state.frees += 1;
            state.slot_live = c.JS_HasException(state.engine.context) or state.engine.captured_exception != null;
            if (state.fatal_cleanup) {
                _ = state.engine.throwNativeOutOfMemory();
                const reason = c.JS_GetException(state.engine.context);
                state.fatal = c.JS_DupValue(state.engine.context, reason);
                state.raw = !c.JS_IsUncatchableError(reason) and c.pi_js_native_allocation_error_generation(reason) == state.engine.native_allocation_generation;
                _ = c.JS_Throw(state.engine.context, reason);
            } else _ = c.JS_Throw(state.engine.context, c.JS_DupValue(state.engine.context, state.ordinary));
        }
    };
    const engine = bootstrap.engine;
    try std.testing.expect(Control.active == null);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const atom = c.JS_NewAtom(engine.context, "process"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var original: c.JSPropertyDescriptor = undefined;
    try std.testing.expect(c.JS_GetOwnProperty(engine.context, &original, global, atom) == 1);
    defer { engine.freeValue(original.value); engine.freeValue(original.getter); engine.freeValue(original.setter); }
    defer restore(engine, global, atom, original);
    var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual Frontend Process Result", .finalizer = Control.finalize };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    const ordinary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary);
    var state: Control.State = .{ .engine = engine, .reason = reason, .ordinary = ordinary, .id = id, .fatal_cleanup = fatal_cleanup };
    defer if (state.fatal) |fatal| engine.freeValue(fatal);
    Control.active = &state; defer Control.active = null;
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, Control.getter, "actualFrontendProcessPending", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, global, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    const modules = engine.native_module_names.count();
    const aliases = engine.native_builtin_aliases.count();
    const hub = engine.native_env_context;
    const unexpected = ActualFrontend.install(bootstrap, canonical_provider, actual_net, false) catch |err| {
        try std.testing.expect(err == error.JavaScriptException);
        const actual = engine.captured_exception orelse return error.MissingActualFrontendReason;
        const wanted = if (fatal_cleanup) state.fatal orelse return error.MissingActualFrontendFatal else reason;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, wanted, actual));
        try std.testing.expectEqual(@as(usize, 1), state.reads);
        try std.testing.expectEqual(@as(usize, 1), state.frees);
        try std.testing.expect(!state.slot_live);
        try std.testing.expectEqual(modules, engine.native_module_names.count());
        try std.testing.expectEqual(aliases, engine.native_builtin_aliases.count());
        try std.testing.expect(engine.native_env_context == hub);
        if (fatal_cleanup) { try std.testing.expect(state.raw and c.JS_IsUncatchableError(actual)); c.JS_ClearUncatchableError(engine.context, actual); }
        engine.captured_exception = null; engine.freeValue(actual);
        restore(engine, global, atom, original);
        const retried = try ActualFrontend.install(bootstrap, canonical_provider, actual_net, false); defer retried.deinit(engine);
        return;
    };
    unexpected.deinit(engine); return error.ExpectedActualFrontendPendingFailure;
}

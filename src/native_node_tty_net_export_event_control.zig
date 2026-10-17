//! Prepared live getters on the ACTUAL canonical net carrier. No fake positive
//! module. First Socket read supplies its real constructor; the export-record
//! read returns a sole native holder with pending A. Stream must stay unread.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn restore(engine: *v.em.Engine, target: c.JSValue, atom: c.JSAtom, descriptor: c.JSPropertyDescriptor) void {
    const flags = (descriptor.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_WRITABLE)) | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
        (if (descriptor.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
    std.debug.assert(c.JS_DefineProperty(engine.context, target, atom, descriptor.value, descriptor.getter, descriptor.setter, flags | c.JS_PROP_THROW) >= 0);
}
pub fn run(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, fatal_cleanup: bool) !void {
    const Control = struct {
        const State = struct { engine: *v.em.Engine, constructor: c.JSValue, reason: c.JSValue, ordinary: c.JSValue, id: c.JSClassID, fatal_cleanup: bool, reads: usize = 0, late: usize = 0, frees: usize = 0, slot_live: bool = false, fatal: ?c.JSValue = null, raw: bool = false };
        var active: ?*State = null;
        fn socket(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; std.debug.assert(context == state.engine.context); state.reads += 1;
            if (state.reads == 1) return c.JS_DupValue(context, state.constructor);
            const holder = c.JS_NewObjectClass(context, state.id); if (c.JS_IsException(holder)) return holder;
            _ = c.JS_SetOpaque(holder, state); _ = c.JS_Throw(context, c.JS_DupValue(context, state.reason)); return holder;
        }
        fn stream(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; state.late += 1; return c.JS_DupValue(context, state.constructor);
        }
        fn finalize(_: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
            const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)).?)); state.frees += 1;
            state.slot_live = c.JS_HasException(state.engine.context) or state.engine.captured_exception != null;
            if (state.fatal_cleanup) {
                _ = state.engine.throwNativeOutOfMemory(); const reason = c.JS_GetException(state.engine.context);
                state.fatal = c.JS_DupValue(state.engine.context, reason);
                state.raw = !c.JS_IsUncatchableError(reason) and c.pi_js_native_allocation_error_generation(reason) == state.engine.native_allocation_generation;
                _ = c.JS_Throw(state.engine.context, reason);
            } else _ = c.JS_Throw(state.engine.context, c.JS_DupValue(state.engine.context, state.ordinary));
        }
    };
    try std.testing.expect(Control.active == null);
    var atoms: [2]c.JSAtom = .{ c.JS_ATOM_NULL, c.JS_ATOM_NULL };
    var descriptors: [2]c.JSPropertyDescriptor = undefined;
    var captured: usize = 0;
    defer {
        for (atoms[0..captured], descriptors[0..captured]) |atom, descriptor| {
            restore(engine, actual.actual_net, atom, descriptor);
            engine.freeValue(descriptor.value); engine.freeValue(descriptor.getter); engine.freeValue(descriptor.setter); c.JS_FreeAtom(engine.context, atom);
        }
    }
    inline for (.{ "Socket", "Stream" }, 0..) |name, index| {
        atoms[index] = c.JS_NewAtom(engine.context, name); if (atoms[index] == c.JS_ATOM_NULL) return error.OutOfMemory;
        const status = c.JS_GetOwnProperty(engine.context, &descriptors[index], actual.actual_net, atoms[index]);
        if (status != 1) { c.JS_FreeAtom(engine.context, atoms[index]); return error.RequiredActualNetOwnConstructor; }
        captured += 1;
    }
    var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual Net Export Result", .finalizer = Control.finalize };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    const ordinary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary);
    var state: Control.State = .{ .engine = engine, .constructor = actual.canonical_socket.constructor, .reason = reason, .ordinary = ordinary, .id = id, .fatal_cleanup = fatal_cleanup };
    defer if (state.fatal) |fatal| engine.freeValue(fatal);
    Control.active = &state; defer Control.active = null;
    const socket = try engine.checked(c.JS_NewCFunction(engine.context, Control.socket, "actualNetSocketPending", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, actual.actual_net, atoms[0], socket, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    const stream = try engine.checked(c.JS_NewCFunction(engine.context, Control.stream, "actualNetStreamMustStayUnread", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, actual.actual_net, atoms[1], stream, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    const before = engine.native_module_names.count();
    const hub = engine.native_env_context;
    const unexpected = ActualAssembly.create(engine, actual) catch |err| {
        try std.testing.expect(err == error.JavaScriptException);
        const result = engine.captured_exception orelse return error.MissingActualNetExportReason;
        const wanted = if (fatal_cleanup) state.fatal orelse return error.MissingActualNetExportFatal else reason;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, wanted, result));
        try std.testing.expectEqual(@as(usize, 2), state.reads); try std.testing.expectEqual(@as(usize, 0), state.late);
        try std.testing.expectEqual(@as(usize, 1), state.frees); try std.testing.expect(!state.slot_live);
        try std.testing.expectEqual(before, engine.native_module_names.count()); try std.testing.expect(engine.native_env_context == hub);
        if (fatal_cleanup) { try std.testing.expect(state.raw and c.JS_IsUncatchableError(result)); c.JS_ClearUncatchableError(engine.context, result); }
        engine.captured_exception = null; engine.freeValue(result);
        for (atoms[0..captured], descriptors[0..captured]) |atom, descriptor| restore(engine, actual.actual_net, atom, descriptor);
        const retried = try ActualAssembly.create(engine, actual); defer retried.deinit(engine);
        return;
    };
    unexpected.deinit(engine); return error.ExpectedActualNetExportPendingFailure;
}

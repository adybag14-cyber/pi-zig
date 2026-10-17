//! Prepared actual-carrier control: replacing the copied enumerable `default`
//! value finalizes its sole holder inside a successful DefineProperty. The
//! finalizer captures a genuine current fatal, leaving the VM slot EMPTY.
//! The next genuine node:module.default getter must remain unread.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;

fn restore(engine: *v.em.Engine, target: c.JSValue, atom: c.JSAtom, descriptor: c.JSPropertyDescriptor) void {
    const flags = (descriptor.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_WRITABLE)) | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
        (if (descriptor.flags & c.JS_PROP_GETSET != 0) @as(c_int, c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET) else @as(c_int, c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE));
    std.debug.assert(c.JS_DefineProperty(engine.context, target, atom, descriptor.value, descriptor.getter, descriptor.setter, flags | c.JS_PROP_THROW) >= 0);
}

pub fn run(comptime ActualAssembly: type, engine: *v.em.Engine, actual: ActualAssembly.Inputs, framed: bool) !void {
    const Control = struct {
        const State = struct { engine: *v.em.Engine, actual_module: c.JSValue, id: c.JSClassID, reads: usize = 0, late: usize = 0, frees: usize = 0, empty_vm: bool = false, captured: bool = false, fatal: ?c.JSValue = null };
        var active: ?*State = null;
        fn holder(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; state.reads += 1;
            const value = c.JS_NewObjectClass(context, state.id); if (c.JS_IsException(value)) return value;
            _ = c.JS_SetOpaque(value, state); return value;
        }
        fn module(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const state = active.?; state.late += 1; return c.JS_DupValue(context, state.actual_module);
        }
        fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
            const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?)); state.frees += 1;
            const result = state.engine.checked(state.engine.throwNativeOutOfMemoryFatal()) catch {
                state.empty_vm = !c.JS_HasException(state.engine.context);
                if (state.engine.captured_exception) |reason| {
                    state.captured = true; state.fatal = c.JS_DupValue(state.engine.context, reason);
                }
                return;
            };
            state.engine.freeValue(result);
        }
    };
    try std.testing.expect(Control.active == null and engine.native_fatal_invocation == null);
    const record = engine.native_module_values.get("node:module") orelse return error.RequiredActualNodeModuleRecord;
    const atom = c.JS_NewAtom(engine.context, "default"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var original: c.JSPropertyDescriptor = undefined;
    if (c.JS_GetOwnProperty(engine.context, &original, record, atom) != 1) return error.RequiredActualModuleDefault;
    defer { engine.freeValue(original.value); engine.freeValue(original.getter); engine.freeValue(original.setter); }
    if (original.flags & c.JS_PROP_GETSET != 0) return error.RequiredActualModuleDataDefault;
    var absent: c.JSPropertyDescriptor = undefined;
    const existing = c.JS_GetOwnProperty(engine.context, &absent, actual.actual_net, atom);
    if (existing != 0) {
        if (existing == 1) { engine.freeValue(absent.value); engine.freeValue(absent.getter); engine.freeValue(absent.setter); }
        return error.RequiredPristineActualNetCarrier;
    }
    var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Actual Net Consumed Default", .finalizer = Control.finalize };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    var state: Control.State = .{ .engine = engine, .actual_module = original.value, .id = id };
    defer if (state.fatal) |fatal| engine.freeValue(fatal);
    Control.active = &state; defer Control.active = null;
    const getter = try engine.checked(c.JS_NewCFunction(engine.context, Control.holder, "actualNetSoleDefault", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, actual.actual_net, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    defer std.debug.assert(c.JS_DeleteProperty(engine.context, actual.actual_net, atom, c.JS_PROP_THROW) >= 0);
    const late = try engine.checked(c.JS_NewCFunction(engine.context, Control.module, "actualModuleMustStayUnread", 0));
    if (c.JS_DefinePropertyGetSet(engine.context, record, atom, late, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    defer restore(engine, record, atom, original);
    var invocation: v.em.Engine.NativeInvocation = .{};
    if (framed) engine.enterNativeInvocation(&invocation);
    defer if (invocation.active) {
        const result = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); engine.freeValue(result);
        if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
    };
    const before = engine.native_module_names.count(); const hub = engine.native_env_context;
    const unexpected = ActualAssembly.create(engine, actual) catch |err| {
        try std.testing.expect(err == error.JavaScriptException);
        const reason = engine.captured_exception orelse return error.MissingActualStatusReason;
        const wanted = state.fatal orelse return error.MissingActualStatusProducer;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, wanted, reason));
        try std.testing.expect(state.empty_vm and state.captured and c.JS_IsUncatchableError(reason));
        try std.testing.expectEqual(@as(usize, 1), state.reads); try std.testing.expectEqual(@as(usize, 0), state.late);
        try std.testing.expectEqual(@as(usize, 1), state.frees); try std.testing.expectEqual(before, engine.native_module_names.count());
        try std.testing.expect(engine.native_env_context == hub);
        engine.captured_exception = null; engine.freeValue(reason);
        if (invocation.active) {
            const result = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); defer engine.freeValue(result);
            try std.testing.expect(c.JS_IsException(result));
            const leaving = c.JS_GetException(engine.context); defer engine.freeValue(leaving);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, wanted, leaving));
        }
        c.JS_ClearUncatchableError(engine.context, wanted);
        restore(engine, record, atom, original);
        try std.testing.expect(c.JS_DeleteProperty(engine.context, actual.actual_net, atom, c.JS_PROP_THROW) >= 0);
        const retried = try ActualAssembly.create(engine, actual); defer retried.deinit(engine);
        return;
    };
    unexpected.deinit(engine); return error.ExpectedActualStatusCapturedFailure;
}

//! Prepared genuine linked-runtime exotic descriptor/finalizer control.
//! Not build-selected, compiled or executed. No production host implementation.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const js = @import("extensions/native_js_values.zig");
const inspect = @import("extensions/native_node_util_inspect.zig");
const Control = struct {
    engine: *em.Engine, constructor_atom: c.JSAtom, holder_class: c.JSClassID,
    first: c.JSValue, replacement: c.JSValue,
    finalized: usize = 0, pending_at_finalization: bool = false,
    native_fatal_cleanup: bool = false,
    initial_fatal: bool = false,
    first_cleanup_fatal: ?c.JSValue = null,
    first_cleanup_was_raw: bool = false,
};
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Control = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    state.finalized += 1;
    state.pending_at_finalization = state.pending_at_finalization or c.JS_HasException(state.engine.context);
    if (state.native_fatal_cleanup and state.finalized <= 2) {
        _ = state.engine.throwNativeOutOfMemory();
        const actual = c.JS_GetException(state.engine.context);
        if (state.finalized == 1) {
            state.first_cleanup_fatal = c.JS_DupValue(state.engine.context, actual);
            state.first_cleanup_was_raw = !c.JS_IsUncatchableError(actual) and c.pi_js_native_allocation_error_generation(actual) == state.engine.native_allocation_generation;
        }
        _ = c.JS_Throw(state.engine.context, actual);
    } else _ = c.JS_Throw(state.engine.context, c.JS_DupValue(state.engine.context, state.replacement));
}
fn ownProperty(context: ?*c.JSContext, output: [*c]c.JSPropertyDescriptor, object: c.JSValue, atom: c.JSAtom) callconv(.c) c_int {
    const state: *Control = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)).?));
    if (atom != state.constructor_atom) return 0;
    if (output == null) return 1;
    const holder = c.JS_NewObjectClass(context, state.holder_class);
    if (c.JS_IsException(holder)) return -1;
    _ = c.JS_SetOpaque(holder, state);
    output.* = .{ .flags = c.JS_PROP_C_W_E, .value = holder, .getter = c.pi_js_undefined(), .setter = c.pi_js_undefined() };
    if (state.native_fatal_cleanup) {
        const getter = c.JS_NewObjectClass(context, state.holder_class);
        if (c.JS_IsException(getter)) { state.engine.freeValue(holder); return -1; }
        _ = c.JS_SetOpaque(getter, state); output.getter = getter;
        const setter = c.JS_NewObjectClass(context, state.holder_class);
        if (c.JS_IsException(setter)) { state.engine.freeValue(holder); state.engine.freeValue(getter); return -1; }
        _ = c.JS_SetOpaque(setter, state); output.setter = setter;
    }
    // Legal native extension callback success with a pending actual event.
    // The holder's sole reference now belongs to the returned descriptor.
    if (state.initial_fatal) c.JS_SetUncatchableError(context, state.first);
    _ = c.JS_Throw(context, c.JS_DupValue(context, state.first));
    return 1;
}
fn fatalProfile(initial_fatal: bool, history_only: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const first = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(first);
    const replacement = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(replacement);
    const primordials = try inspect.capturePrimordials(engine); defer primordials.deinit(engine);
    const actual = try inspect.create(engine, primordials); defer actual.deinit(engine);
    var holder_class: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &holder_class) == 0) return error.OutOfMemory;
    const holder_definition: c.JSClassDef = .{ .class_name = "Actual Fatal Descriptor Field", .finalizer = finalize };
    if (c.JS_NewClass(engine.runtime, holder_class, &holder_definition) < 0) return error.OutOfMemory;
    var subject_class: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &subject_class) == 0) return error.OutOfMemory;
    const subject_definition: c.JSClassDef = .{ .class_name = "Actual Native Fatal Descriptor Producer", .exotic = &exotic };
    if (c.JS_NewClass(engine.runtime, subject_class, &subject_definition) < 0) return error.OutOfMemory;
    const atom = c.JS_NewAtom(engine.context, "constructor"); if (atom == c.JS_ATOM_NULL) return js.capture(engine); defer c.JS_FreeAtom(engine.context, atom);
    var control: Control = .{ .engine = engine, .constructor_atom = atom, .holder_class = holder_class, .first = first, .replacement = replacement, .native_fatal_cleanup = !history_only, .initial_fatal = initial_fatal };
    defer if (control.first_cleanup_fatal) |reason| engine.freeValue(reason);
    const subject = try engine.checked(c.JS_NewObjectClass(engine.context, subject_class)); defer engine.freeValue(subject); _ = c.JS_SetOpaque(subject, &control);
    if (history_only) {
        // A real prior native allocation event is now captured HISTORY. Its
        // native generation/uncatchable flag must not displace current A.
        _ = engine.throwNativeOutOfMemory(); const history = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, history); engine.captured_exception = history;
    }
    var args = [_]c.JSValue{subject};
    const result = c.JS_Call(engine.context, actual.inspect, c.pi_js_undefined(), 1, &args);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    const wanted = if (history_only or initial_fatal) first else control.first_cleanup_fatal orelse return error.MissingActualCleanupFatal;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, wanted, reason));
    try std.testing.expectEqual(@as(usize, if (history_only) 1 else 3), control.finalized);
    try std.testing.expect(!control.pending_at_finalization);
    try std.testing.expectEqual(!history_only, c.JS_IsUncatchableError(reason));
    if (!history_only) try std.testing.expect(control.first_cleanup_was_raw);
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    c.JS_ClearUncatchableError(engine.context, reason);
}
test "util descriptor first actual raw native cleanup OOM wins over ordinary A and later cleanup OOM" { try fatalProfile(false, false); }
test "util descriptor original actual uncatchable A survives later actual cleanup OOM" { try fatalProfile(true, false); }
test "util descriptor prior native allocation capture is history rather than a current fatal event" { try fatalProfile(false, true); }
const exotic: c.JSClassExoticMethods = .{ .get_own_property = ownProperty };
test "util inspector drains first descriptor event before finalizer releases its fields" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const setup = try engine.evalModule("globalThis.inspectDiagnostics=0;globalThis.inspectFirst=new Error('first descriptor event');globalThis.inspectSecond=new Error('native finalizer replacement');for(const e of [inspectFirst,inspectSecond])e.toString=()=>{inspectDiagnostics++;return 'formatted'};export const proof=true;", "inspect-descriptor-pending-setup.mjs");
    engine.freeValue(setup);
    const first = try js.global(engine, "inspectFirst"); defer engine.freeValue(first);
    const replacement = try js.global(engine, "inspectSecond"); defer engine.freeValue(replacement);
    const primordials = try inspect.capturePrimordials(engine); defer primordials.deinit(engine);
    const actual = try inspect.create(engine, primordials); defer actual.deinit(engine);
    var holder_class: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &holder_class) == 0) return error.OutOfMemory;
    const holder_definition: c.JSClassDef = .{ .class_name = "Actual Pending Descriptor Field", .finalizer = finalize };
    if (c.JS_NewClass(engine.runtime, holder_class, &holder_definition) < 0) return error.OutOfMemory;
    var subject_class: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &subject_class) == 0) return error.OutOfMemory;
    const subject_definition: c.JSClassDef = .{ .class_name = "Actual Native Descriptor Producer", .exotic = &exotic };
    if (c.JS_NewClass(engine.runtime, subject_class, &subject_definition) < 0) return error.OutOfMemory;
    const constructor_atom = c.JS_NewAtom(engine.context, "constructor");
    if (constructor_atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, constructor_atom);
    var control: Control = .{ .engine = engine, .constructor_atom = constructor_atom, .holder_class = holder_class, .first = first, .replacement = replacement };
    const subject = try engine.checked(c.JS_NewObjectClass(engine.context, subject_class)); defer engine.freeValue(subject);
    _ = c.JS_SetOpaque(subject, &control);
    var args = [_]c.JSValue{subject};
    const result = c.JS_Call(engine.context, actual.inspect, c.pi_js_undefined(), 1, &args);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, reason));
    try std.testing.expectEqual(@as(usize, 1), control.finalized);
    try std.testing.expect(!control.pending_at_finalization);
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    const diagnostics = try js.global(engine, "inspectDiagnostics"); defer engine.freeValue(diagnostics);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, diagnostics, c.JS_NewInt32(engine.context, 0)));
}

//! Test-only actual C native sole holders. A carrier's native finalizer records
//! real retirement; no Models/auth/factory implementation is replaced here.
const std = @import("std");
const x = @import("extensions/native_sdk_initial_model_values.zig");
const c = x.c;
const Record = struct { engine: *x.em.Engine, holder_class: c.JSClassID, counts: [8]u32 = @splat(0), visits: [8]u32 = @splat(0), fatal_slot: ?usize = null, cancel_slot: ?usize = null, fatal_reason: ?c.JSValue = null, data_reason: ?c.JSValue = null };
const Holder = struct { record: c.JSValue, slot: usize };
fn recordOf(value: c.JSValue) *Record { return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?)); }
fn recordFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const record: *Record = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (record.fatal_reason) |reason| c.JS_FreeValueRT(runtime, reason);
    if (record.data_reason) |reason| c.JS_FreeValueRT(runtime, reason);
    record.engine.gpa.destroy(record);
}
fn recordMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const record: *Record = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (record.fatal_reason) |reason| c.JS_MarkValue(runtime, reason, visit);
    if (record.data_reason) |reason| c.JS_MarkValue(runtime, reason, visit);
}
fn holderMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const holder: *Holder = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, holder.record, visit);
}
fn holderFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const holder: *Holder = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const record = recordOf(holder.record); const engine = record.engine;
    record.counts[holder.slot] +|= 1;
    if (record.fatal_slot == holder.slot and engine.native_fatal_invocation != null) {
        record.fatal_slot = null;
        _ = engine.throwNativeOutOfMemoryFatal(); // ACTUAL producer in this free.
        if (c.JS_HasException(engine.context)) {
            const reason = c.JS_GetException(engine.context);
            record.fatal_reason = c.JS_DupValue(engine.context, reason);
            _ = c.JS_Throw(engine.context, reason);
        }
    }
    if (record.cancel_slot == holder.slot and engine.native_fatal_invocation != null) { record.cancel_slot = null; engine.cancelled.store(true, .release); }
    c.JS_FreeValueRT(runtime, holder.record);
    engine.gpa.destroy(holder);
}
pub fn createNativeRetirementHooks(engine: *x.em.Engine) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, createHooks(&o));
}
fn createHooks(o: *x.Ops) !c.JSValue {
    const e = o.s.engine;
    var record_class: c.JSClassID = 0; _ = c.JS_NewClassID(e.runtime, &record_class);
    const record_definition: c.JSClassDef = .{ .class_name = "Actual initial-model native retirement record", .finalizer = recordFinalizer, .gc_mark = recordMark };
    if (c.JS_NewClass(e.runtime, record_class, &record_definition) < 0) return error.OutOfMemory;
    var holder_class: c.JSClassID = 0; _ = c.JS_NewClassID(e.runtime, &holder_class);
    const holder_definition: c.JSClassDef = .{ .class_name = "Actual initial-model native sole holder", .finalizer = holderFinalizer, .gc_mark = holderMark };
    if (c.JS_NewClass(e.runtime, holder_class, &holder_definition) < 0) return error.OutOfMemory;
    const record_value = try o.allocation(c.JS_NewObjectClass(e.context, record_class), e.native_allocation_generation);
    const record = try e.gpa.create(Record); record.* = .{ .engine = e, .holder_class = holder_class };
    _ = c.JS_SetOpaque(record_value, record);
    try o.put(record_value, "guestReached", c.pi_js_bool(e.context, 0));
    try o.put(record_value, "coercionReached", c.pi_js_bool(e.context, 0));
    const hooks = try o.object();
    // Real opaque record is exposed only in this control namespace so a host
    // may inspect it after a fatal exit without invoking any guest function.
    try o.put(hooks, "record", record_value);
    inline for (.{ "make", "count", "armFatal", "visit", "armCancel", "freshPrivateData", "raiseNativeFatal", "isUnmarkedPrivateData" }, 0..) |name, index| {
        var roots = [_]c.JSValue{record_value};
        const method = try o.allocation(c.JS_NewCFunctionData2(e.context, callback, name, if (index == 5 or index == 6) 0 else 1, index, roots.len, &roots), e.native_allocation_generation);
        try o.put(hooks, name, method);
    }
    return c.JS_DupValue(e.context, hooks);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = x.em.Engine.fromContext(context.?);
    e.checkNativeEntry() catch return e.throwCaptured();
    e.native_exception_diagnostics_suppressed += 1;
    defer e.native_exception_diagnostics_suppressed -= 1;
    var invocation: x.em.Engine.NativeInvocation = .{}; e.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = e }; var o: x.Ops = .{ .s = &s };
    const value = x.owned.finishValue(&s, callbackBody(&o, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, roots[0])) catch |err| @import("extensions/native_sdk.zig").fail(e, err);
    return e.leaveNativeInvocation(&invocation, value);
}
fn callbackBody(o: *x.Ops, argument: c.JSValue, magic: c_int, record_value: c.JSValue) !c.JSValue {
    const e = o.s.engine; const record = recordOf(record_value);
    if (magic == 5) {
        // GENUINE successful native private DATA creation. The temporary
        // pending slot is consumed and the unmarked Error A is returned as
        // ordinary DATA. No B1/NativeInvocation fatal event is published.
        if (record.data_reason != null) return error.ProvenanceControlRequiresFreshDataRecord;
        _ = e.throwNativeOutOfMemory();
        const data = c.JS_GetException(e.context);
        record.data_reason = c.JS_DupValue(e.context, data);
        return data;
    }
    if (magic == 6) {
        if (record.fatal_reason != null) return error.RetirementControlRequiresFreshNativeFatalRecord;
        _ = e.throwNativeOutOfMemoryFatal(); // Actual fresh native producer B.
        const reason = c.JS_GetException(e.context);
        record.fatal_reason = c.JS_DupValue(e.context, reason);
        return e.checked(c.JS_Throw(e.context, reason));
    }
    if (magic == 7) return c.pi_js_bool(e.context, @intFromBool(c.pi_js_native_allocation_error_generation(argument) != 0 and !c.JS_IsUncatchableError(argument)));
    var slot: u32 = 0;
    if (c.JS_ToUint32(e.context, &slot, argument) < 0) return @import("extensions/native_js_values.zig").capture(e);
    if (slot >= record.counts.len) return o.typeError("retirement control slot out of range");
    if (magic == 1) return c.JS_NewUint32(e.context, record.counts[slot]);
    if (magic == 2) { record.fatal_slot = slot; return c.pi_js_undefined(); }
    if (magic == 3) { record.visits[slot] +|= 1; return c.pi_js_undefined(); }
    if (magic == 4) { record.cancel_slot = slot; return c.pi_js_undefined(); }
    const value = try o.allocation(c.JS_NewObjectClass(e.context, record.holder_class), e.native_allocation_generation);
    const holder = try e.gpa.create(Holder); holder.* = .{ .record = c.JS_DupValue(e.context, record_value), .slot = slot };
    _ = c.JS_SetOpaque(value, holder);
    return c.JS_DupValue(e.context, value);
}
/// Preparation returns a real closure retaining the two protocol carriers.
/// Root MUST end/drain the preparation job (the normal WeakRef kept-objects
/// boundary) before invoking it. This unit never manually clears kept objects.
pub fn prepareActualRetirementCaller(engine: *x.em.Engine, actual_imports: c.JSValue, actual_subject: c.JSValue, native_hooks: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, prepare(&o, actual_imports, actual_subject, native_hooks));
}
fn prepare(o: *x.Ops, actual_imports: c.JSValue, actual_subject: c.JSValue, native_hooks: c.JSValue) !c.JSValue {
    const e = o.s.engine;
    const function = try o.own(try e.eval(@embedFile("extensions/fixtures/sdk-initial-model-retirement-caller.mjs"), "prepare-initial-model-retirement.js", c.JS_EVAL_TYPE_GLOBAL));
    return c.JS_DupValue(e.context, try o.call(function, c.pi_js_undefined(), &.{ actual_imports, actual_subject, native_hooks }));
}
pub fn startPreparedRetirementCaller(engine: *x.em.Engine, prepared_runner: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, xDuplicate(&o, prepared_runner));
}
fn xDuplicate(o: *x.Ops, runner: c.JSValue) !c.JSValue { return c.JS_DupValue(o.s.engine.context, try o.call(runner, c.pi_js_undefined(), &.{})); }
/// Inspect only the retained native record; no guest lookup or evaluation.
pub fn verifyNoVisits(original_record: c.JSValue, comptime slots: anytype) !void {
    const record = recordOf(original_record);
    inline for (slots) |slot| try std.testing.expectEqual(@as(u32, 0), record.visits[slot]);
}
pub fn verifyActualRetirementFatal(engine: *x.em.Engine, original_record: c.JSValue, slot: usize) !void {
    const record = recordOf(original_record);
    try std.testing.expectEqual(@as(u32, 1), record.counts[slot]);
    const reason = engine.captured_exception orelse return error.MissingActualRetirementFatal;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, record.fatal_reason orelse return error.MissingActualRecordedRetirementFatal, reason));
    try std.testing.expectEqual(@as(u32, 0), record.visits[2]); // no guest close.
    // Dispose this fatal realm through its real owner; no guest restoration.
}
pub fn verifyActualCancellationNoGuestClose(engine: *x.em.Engine, original_record: c.JSValue) !void {
    const record = recordOf(original_record);
    try std.testing.expect(engine.cancelled.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), record.counts[0]);
    try std.testing.expectEqual(@as(u32, 0), record.visits[1]); // native loop must poll before next() body.
    try std.testing.expectEqual(@as(u32, 0), record.visits[2]); // no guest IteratorClose.
    const reason = engine.captured_exception orelse return error.MissingActualCancellation;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(reason));
    // Fresh disposable realm; owner handles the real cancel flag and teardown.
}
/// Real getter operation calls successful native DATA maker, then guest throws
/// that SAME freshly private A inside the SAME enclosing JS_GetProperty call.
/// No historical generation gap can accidentally make this control vacuous.
pub fn startSameOperationPrivateDataThrowCaller(engine: *x.em.Engine, actual_imports: c.JSValue, actual_options: c.JSValue, native_hooks: c.JSValue) !c.JSValue {
    return startProvenanceCaller(engine, actual_imports, actual_options, native_hooks, false);
}
pub fn startSameOperationActualNativeFatalCaller(engine: *x.em.Engine, actual_imports: c.JSValue, actual_options: c.JSValue, native_hooks: c.JSValue) !c.JSValue {
    return startProvenanceCaller(engine, actual_imports, actual_options, native_hooks, true);
}
fn startProvenanceCaller(engine: *x.em.Engine, actual_imports: c.JSValue, actual_options: c.JSValue, native_hooks: c.JSValue, fatal: bool) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, provenanceCaller(&o, actual_imports, actual_options, native_hooks, fatal));
}
fn provenanceCaller(o: *x.Ops, actual_imports: c.JSValue, actual_options: c.JSValue, native_hooks: c.JSValue, fatal: bool) !c.JSValue {
    const e = o.s.engine;
    const function = try o.own(try e.eval(@embedFile("extensions/fixtures/sdk-initial-model-provenance-caller.mjs"), "actual-initial-model-provenance.js", c.JS_EVAL_TYPE_GLOBAL));
    return c.JS_DupValue(e.context, try o.call(function, c.pi_js_undefined(), &.{ actual_imports, actual_options, native_hooks, c.pi_js_bool(e.context, @intFromBool(fatal)) }));
}
pub fn verifyRecordedActualNativeFatal(engine: *x.em.Engine, original_record: c.JSValue) !void {
    const record = recordOf(original_record);
    const reason = engine.captured_exception orelse return error.MissingActualNativeProvenanceFatal;
    const original = record.fatal_reason orelse return error.MissingRecordedActualNativeProvenanceFatal;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, reason));
    const prior_data = record.data_reason orelse return error.MissingSuccessfulPriorPrivateData;
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, prior_data, reason));
    try std.testing.expect(!c.JS_IsUncatchableError(prior_data));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expectEqual(@as(u32, 0), record.visits[3]); // no guest catch/rejection handler.
    const guest_reached = c.JS_GetPropertyStr(engine.context, original_record, "guestReached");
    // Known control-owned data property, no guest getter or coercion.
    const ordinary_path_ran = c.JS_ToBool(engine.context, guest_reached) == 1;
    engine.freeValue(guest_reached);
    try std.testing.expect(!ordinary_path_ran);
}
pub fn prepareActualModelReceiverCaller(engine: *x.em.Engine, actual_imports: c.JSValue, actual_subject: c.JSValue, native_hooks: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, prepareModelReceiver(&o, actual_imports, actual_subject, native_hooks));
}
fn prepareModelReceiver(o: *x.Ops, actual_imports: c.JSValue, actual_subject: c.JSValue, native_hooks: c.JSValue) !c.JSValue {
    const e = o.s.engine;
    const function = try o.own(try e.eval(@embedFile("extensions/fixtures/sdk-initial-model-model-receiver-caller.mjs"), "prepare-initial-model-model-receiver.js", c.JS_EVAL_TYPE_GLOBAL));
    return c.JS_DupValue(e.context, try o.call(function, c.pi_js_undefined(), &.{ actual_imports, actual_subject, native_hooks }));
}
pub fn verifyActualModelReceiverFatal(engine: *x.em.Engine, original_record: c.JSValue) !void {
    try verifyActualRetirementFatal(engine, original_record, 2);
    const record = recordOf(original_record);
    try std.testing.expectEqual(@as(u32, 0), record.visits[4]);
    const coercion_reached = c.JS_GetPropertyStr(engine.context, original_record, "coercionReached");
    const coerced = c.JS_ToBool(engine.context, coercion_reached) == 1;
    engine.freeValue(coercion_reached);
    try std.testing.expect(!coerced);
}

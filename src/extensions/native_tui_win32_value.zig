//! Clipboard-local raw value producers. No guest-capable operation is covered
//! by the VM allocation counter: each snapshot surrounds one proven primitive.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
pub const Snapshot = struct { native_generation: u64, vm_occurrence: u64 };
pub fn before(stage: *Scope) !Snapshot {
    const generation = try stage.beforeAllocation();
    return .{ .native_generation = generation, .vm_occurrence = c.JS_PiOutOfMemoryOccurrence(stage.engine.runtime) };
}
fn actualVmFailure(stage: *Scope, snapshot: Snapshot) bool {
    if (c.JS_PiOutOfMemoryOccurrence(stage.engine.runtime) == snapshot.vm_occurrence) return false;
    // This is the runtime's actual allocator occurrence around this exact
    // non-guest producer. Publish before retiring its result or prior roots.
    _ = stage.engine.throwNativeOutOfMemoryFatal();
    return true;
}
pub fn checked(stage: *Scope, value: c.JSValue, snapshot: Snapshot) !c.JSValue {
    if (actualVmFailure(stage, snapshot)) {
        var owned = value;
        stage.boundary.release(&owned);
        return error.OutOfMemory;
    }
    return stage.checkedAllocation(value, snapshot.native_generation);
}
pub fn status(stage: *Scope, result: c_int, snapshot: Snapshot) !void {
    if (actualVmFailure(stage, snapshot)) return error.OutOfMemory;
    try stage.boundary.checkPendingSince(snapshot.native_generation);
    if (result < 0) return error.MissingNativeClipboardValueReason;
}
pub fn text(stage: *Scope, bytes: []const u8) !c.JSValue {
    const snapshot = try before(stage);
    return checked(stage, c.JS_NewStringLen(stage.engine.context, bytes.ptr, bytes.len), snapshot);
}
fn utf16Body(stage: *Scope, units: []const u16) !c.JSValue {
    // QuickJS JS_STRING_LEN_MAX. The larger-length branch constructs a
    // RangeError with guest stack hooks; reject it before this raw span.
    if (units.len > ((@as(usize, 1) << 30) - 1)) return error.NativeClipboardStringRange;
    const snapshot = try before(stage);
    const value = try checked(stage, c.JS_NewStringUTF16(stage.engine.context, units.ptr, units.len), snapshot);
    return c.JS_DupValue(stage.engine.context, value);
}
pub fn fromUtf16(engine: *js.Engine, units: []const u16) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(utf16Body(&stage, units));
}
fn bytesBody(stage: *Scope, bytes: []const u8) !c.JSValue {
    const engine = stage.engine;
    // Same producer order and same Buffer prototype owner as node_buffer's
    // fromBytes/fromBacking. Inputs are a fresh ArrayBuffer and numeric bounds.
    if (bytes.len > engine.options.memory_limit or bytes.len > std.math.maxInt(i32)) return error.BufferRange;
    const backing_snapshot = try before(stage);
    const backing = try checked(stage, c.JS_NewArrayBufferCopy(engine.context, bytes.ptr, bytes.len), backing_snapshot);
    const prototype = engine.buffer_prototype orelse return error.NativeBufferUnavailable;
    const offset_snapshot = try before(stage);
    const offset = try checked(stage, c.JS_NewInt64(engine.context, 0), offset_snapshot);
    const length_snapshot = try before(stage);
    const length = try checked(stage, c.JS_NewInt64(engine.context, @intCast(bytes.len)), length_snapshot);
    var args = [_]c.JSValue{ backing, offset, length };
    const array_snapshot = try before(stage);
    const value = try checked(stage, c.JS_NewTypedArray(engine.context, args.len, &args, c.JS_TYPED_ARRAY_UINT8), array_snapshot);
    // value is the new ordinary typed array, not a guest proxy. SetPrototype
    // walks its native prototype chain without invoking guest properties.
    const prototype_snapshot = try before(stage);
    try status(stage, c.JS_SetPrototype(engine.context, value, prototype), prototype_snapshot);
    return c.JS_DupValue(engine.context, value);
}
pub fn fromBytes(engine: *js.Engine, bytes: []const u8) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(bytesBody(&stage, bytes));
}

fn inputBody(stage: *Scope, input: c.JSValue, raw: *?[*]const u16, length: *usize) !c.JSValue {
    // Caller established a primitive string before this conversion. This path
    // therefore cannot run Symbol.toPrimitive, toString or other guest code.
    const snapshot = try before(stage);
    const converted = c.JS_ToCStringLenUTF16(stage.engine.context, length, input);
    raw.* = converted;
    try status(stage, if (converted == null) -1 else 0, snapshot);
    return c.pi_js_undefined();
}
pub fn inputUtf16(engine: *js.Engine, input: c.JSValue) ![]const u16 {
    var stage = Scope.init(engine);
    var raw: ?[*]const u16 = null;
    var length: usize = 0;
    errdefer if (raw) |text_value| c.JS_FreeCStringUTF16(engine.context, text_value);
    const returned = try stage.finish(inputBody(&stage, input, &raw, &length));
    engine.freeValue(returned);
    return (raw orelse return error.MissingNativeClipboardText)[0..length];
}

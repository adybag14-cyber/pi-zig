// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The real binding-owned Float64Array and BigInt64Array used by Node's
//! FillGlobalStatsArray. Each has 36 slots for the two StatWatcher records.
//! A BigInt lstat updates only the BigInt array; numeric statValues stays live.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const owned = @import("native_sdk_owned_completion.zig");
const stat = @import("native_file_stat.zig");
const publication = @import("native_node_fs_private_publication.zig");
const cache_key = "\x00native.fs.statValues";
pub const field_count = 18;
pub const buffer_count = field_count * 2;
const State = struct {
    engine: *v.em.Engine,
    numeric: c.JSValue,
    bigint: c.JSValue,
};
fn state(holder: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)).?));
}
fn finalizer(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    c.JS_FreeValueRT(runtime, self.numeric);
    c.JS_FreeValueRT(runtime, self.bigint);
    const engine = self.engine;
    engine.gpa.destroy(self);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    c.JS_MarkValue(runtime, self.numeric, visit);
    c.JS_MarkValue(runtime, self.bigint, visit);
}
fn typedArray(s: *Scope, kind: c.JSTypedArrayEnum) !c.JSValue {
    const args = [_]c.JSValue{c.JS_NewInt32(s.engine.context, buffer_count)};
    const generation = try s.beforeAllocation();
    // Primitive length, real intrinsic typed-array constructor, no guest input.
    return s.checkedAllocation(c.JS_NewTypedArray(s.engine.context, 1, &args, kind), generation);
}
fn createBody(s: *Scope) !c.JSValue {
    try s.pending();
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native fs stat buffers", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const generation = try s.beforeAllocation();
    const holder = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, class_id), generation);
    const numeric_value = try typedArray(s, c.JS_TYPED_ARRAY_FLOAT64);
    const bigint_value = try typedArray(s, c.JS_TYPED_ARRAY_BIG_INT64);
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    errdefer c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(State));
    const self = try s.engine.gpa.create(State);
    self.* = .{ .engine = s.engine, .numeric = c.JS_DupValue(s.engine.context, numeric_value), .bigint = c.JS_DupValue(s.engine.context, bigint_value) };
    _ = c.JS_SetOpaque(holder, self);
    return c.JS_DupValue(s.engine.context, holder);
}
pub fn acquire(engine: *v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |known| return c.JS_DupValue(engine.context, known);
    var s = Scope.init(engine);
    const candidate = try s.finish(createBody(&s));
    if (engine.native_module_values.get(cache_key)) |known| {
        var completion = owned.Completion.initValue(engine, c.JS_DupValue(engine.context, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, cache_key, candidate);
}
/// Borrowed binding-owned arrays. Their owner must stay rooted across calls.
pub fn numeric(holder: c.JSValue) c.JSValue { return state(holder).numeric; }
pub fn bigint(holder: c.JSValue) c.JSValue { return state(holder).bigint; }
fn timePart(value: i128) f64 {
    // node_file-inl.h casts Win32 libuv signed long back to unsigned long.
    if (builtin.os.tag == .windows) return @floatFromInt(@as(u32, @truncate(@as(u128, @bitCast(value)))));
    return @floatFromInt(value);
}
fn timeBits(value: i128) u64 {
    if (builtin.os.tag == .windows) return @as(u32, @truncate(@as(u128, @bitCast(value))));
    // The Source macro casts through double before the AliasedBigInt64Array.
    return @bitCast(@as(i64, @intFromFloat(timePart(value))));
}
fn fill(bytes: []u8, info: stat.Stat, use_bigint: bool, second: bool) void {
    const first = if (second) field_count else 0;
    const fields = [_]u64{ info.dev, info.mode, info.nlink, info.uid, info.gid, info.rdev, info.blksize, info.ino, info.size, info.blocks };
    for (fields, 0..) |field, position| {
        const bits: u64 = if (use_bigint) field else @bitCast(@as(f64, @floatFromInt(field)));
        @memcpy(bytes[(first + position) * 8 ..][0..8], std.mem.asBytes(&bits));
    }
    const times = [_]i128{ info.atime_ns, info.mtime_ns, info.ctime_ns, info.birthtime_ns };
    for (times, 0..) |time, position| {
        const parts = [_]i128{ @divFloor(time, 1_000_000_000), @mod(time, 1_000_000_000) };
        for (parts, 0..) |part, half| {
            const bits: u64 = if (use_bigint) timeBits(part) else @bitCast(timePart(part));
            @memcpy(bytes[(first + 10 + position * 2 + half) * 8 ..][0..8], std.mem.asBytes(&bits));
        }
    }
}
fn recordBody(s: *Scope, holder: c.JSValue, use_bigint: bool, info: stat.Stat, second: bool) !c.JSValue {
    const selected = if (use_bigint) bigint(holder) else numeric(holder);
    var offset: usize = 0; var length: usize = 0; var element_bytes: usize = 0;
    try s.pending();
    const buffer = try s.checked(c.JS_GetTypedArrayBuffer(s.engine.context, selected, &offset, &length, &element_bytes));
    var capacity: usize = 0;
    const pointer = c.JS_GetArrayBuffer(s.engine.context, &capacity, buffer);
    try s.pending();
    if (pointer == null or element_bytes != 8 or length != buffer_count * 8 or offset > capacity or length > capacity - offset)
        return error.ActualFsStatBackingBufferUnavailable;
    // Like AliasedBuffer::SetValue this writes the actual backing bytes.
    // No getter, conversion, allocation or owner release occurs in this span.
    fill(pointer[offset..][0..length], info, use_bigint, second);
    return c.JS_DupValue(s.engine.context, selected);
}
pub fn record(engine: *v.em.Engine, holder: c.JSValue, use_bigint: bool, info: stat.Stat, second: bool) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(recordBody(&s, holder, use_bigint, info, second));
}
fn updateBody(s: *Scope, holder: c.JSValue, use_bigint: bool, info: stat.Stat) !c.JSValue {
    _ = try s.own(try record(s.engine, holder, use_bigint, info, false));
    return c.pi_js_undefined();
}
/// Existing public stat/lstat producers update this same owner once the real
/// module-loading FS profile has installed it; there is no second stat cache.
pub fn updateIfInstalled(engine: *v.em.Engine, use_bigint: bool, info: stat.Stat) !void {
    if (engine.native_module_values.get(cache_key)) |holder| {
        var s = Scope.init(engine);
        _ = try s.finish(updateBody(&s, holder, use_bigint, info));
    }
}

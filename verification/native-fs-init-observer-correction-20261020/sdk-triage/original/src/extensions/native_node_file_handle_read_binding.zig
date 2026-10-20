//! Node v24.13 src/node_file.cc Read, selected kUsePromises route.
//! Actual native CHECKs precede the genuine FSReqPromise constructor,
//! SetReturnValue and asynchronous ReqWrap dispatch. No fs namespace is
//! published here; callback/synchronous request routes are separate owners.
//!
//! The nonthrowing intrinsic view-length projection is a declared VM
//! prerequisite. It preserves V8 ByteLength's detached/OOB zero result before
//! these native checks; the independently owned backing lease stays throwing.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_function.zig");
const callbacks = @import("native_node_callback_scope.zig");
const io = @import("native_node_fs_request_io.zig");
const c = a.c;
const Engine = a.v.em.Engine;
const Scope = a.Scope;
const Check = callbacks.Check;

pub const Inputs = struct {
    controller: *io.Controller,
    use_promises: c.JSValue,
    request_factory: c.JSValue,
};
const Owner = struct { controller: *io.Controller };

fn require(controller: *io.Controller, condition: bool, check: Check) !void {
    if (!condition)
        return controller.environment.operations.native_check_failure(controller.environment, check);
}
fn primitiveNumber(s: *Scope, controller: *io.Controller, value: c.JSValue,
    check: Check) !f64
{
    try require(controller, c.JS_IsNumber(value), check);
    var number: f64 = 0;
    try s.pending();
    const status = c.JS_ToFloat64(s.engine.context, &number, value);
    try s.pending();
    if (status < 0) return error.ActualFSReadPrimitiveNumberRequired;
    return number;
}
fn int32(s: *Scope, controller: *io.Controller, value: c.JSValue, check: Check) !i32 {
    const number = try primitiveNumber(s, controller, value, check);
    // Value::IsInt32 uses IsInt32Double, whose !IsMinusZero is significant.
    const negative_zero = number == 0 and (@as(u64, @bitCast(number)) >> 63) != 0;
    try require(controller, std.math.isFinite(number) and @trunc(number) == number and
        number >= std.math.minInt(i32) and number <= std.math.maxInt(i32) and
        !negative_zero, check);
    return @intFromFloat(number);
}
fn safeInteger(s: *Scope, controller: *io.Controller, value: c.JSValue,
    check: Check) !i64
{
    const number = try primitiveNumber(s, controller, value, check);
    // Node's IsSafeJsInt accepts minus zero; this predicate is deliberately
    // separate from V8's IsInt32Double above.
    try require(controller, std.math.isFinite(number) and @trunc(number) == number and
        number >= -9007199254740991.0 and number <= 9007199254740991.0, check);
    return @intFromFloat(number);
}
fn position(s: *Scope, controller: *io.Controller, value: c.JSValue) !i64 {
    if (!c.JS_IsBigInt(value)) return safeInteger(s, controller, value, .fs_read_position);
    var result: i64 = 0;
    try s.pending();
    const status = c.JS_ToBigInt64(s.engine.context, &result, value);
    try s.pending();
    if (status < 0) return error.ActualFSReadPrimitiveBigIntRequired;
    return result;
}
fn storage(s: *Scope, view: c.JSValue, output: *c.JSPiArrayBufferLease) !void {
    try s.pending();
    const status = c.JS_PiAcquireArrayBufferView(s.engine.context, view, output);
    try s.pending();
    if (status < 0) return error.ActualFSReadBackingLeaseReasonRequired;
    // A foreign C allocation without an admitted native owner is not a safe
    // worker borrow. Internal Buffer/ArrayBuffer/TypedArray and admitted
    // serialized SAB storage use the actual independent native entitlement.
    if (status == 0) return error.NativeFileReadExternalBackingOwnerRequired;
}
fn ownerOf(engine: *Engine, value: c.JSValue) !*Owner {
    const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse
        return error.ActualFSReadBindingOwnerRequired;
    const self: *Owner = @ptrCast(@alignCast(raw));
    if ((try self.controller.environment.requireEngine()) != engine)
        return error.ActualFSReadBindingEnvironmentMismatch;
    return self;
}
fn readBody(s: *Scope, controller: *io.Controller, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    try require(controller, args.len >= 5, .fs_read_argument_count);
    const descriptor = try int32(s, controller, args[0], .fs_read_fd);
    try require(controller, c.JS_GetTypedArrayType(args[1]) >= 0 or
        c.JS_IsDataView(args[1]), .fs_read_buffer);
    // Buffer::Length is the original nonthrowing V8 ByteLength operation.
    // No guest getter or lease error can replace the following native CHECK.
    const buffer_length = c.JS_PiArrayBufferViewByteLength(args[1]);
    const offset_integer = try safeInteger(s, controller, args[2], .fs_read_offset_integer);
    try require(controller, offset_integer >= 0, .fs_read_offset_nonnegative);
    try require(controller, @as(u64, @intCast(offset_integer)) < buffer_length,
        .fs_read_offset_bounds);
    const offset: usize = @intCast(offset_integer);
    const length_integer = try int32(s, controller, args[3], .fs_read_length);
    // Original C++ casts the signed Int32 to size_t before IsWithinBounds.
    // A negative value fails that actual range predicate, not a new check.
    const length: usize = @bitCast(@as(isize, length_integer));
    try require(controller, length <= buffer_length - offset, .fs_read_range);
    const read_position = try position(s, controller, args[4]);

    if (args.len <= 5 or !c.JS_IsStrictEqual(s.engine.context, args[5], roots[0]))
        return error.NativeFileReadRequiresActualPromiseRequest;
    var lease: c.JSPiArrayBufferLease = std.mem.zeroes(c.JSPiArrayBufferLease);
    defer c.JS_PiReleaseArrayBufferLease(&lease);
    // All preceding operations are intrinsic primitive checks. Acquire the
    // original span before init/SetReturnValue can detach or transfer it.
    try storage(s, args[1], &lease);
    const request = controller.createReadRequest(s, roots[1]) catch |err| {
        s.boundary.escaping();
        // Original empty NewInstance/Resolver/Set Maybe leaves GetReqWrap
        // null, which reaches Read's native CHECK. An attached ordinary init
        // rethrow already completed its native constructor in createRequest.
        // Actual fatal/host/dependency failures retain their existing policy.
        if (err == error.JavaScriptException and !s.boundary.fatal)
            return controller.environment.operations.native_check_failure(
                controller.environment, .fs_read_request);
        return err;
    };
    var returned = c.pi_js_undefined();
    if (request.returnPromise()) |value| {
        returned = try s.own(value);
    } else |err| {
        s.boundary.escaping();
        // SetReturnValue is void. Its ordinary failed Get does not remove the
        // non-null request or skip the following native AsyncCall/Dispatch.
        if (err != error.JavaScriptException or s.boundary.fatal) return err;
    }
    try controller.dispatchRead(s, request, descriptor, &lease,
        offset, @intCast(length), read_position);
    return a.duplicate(s.engine, returned);
}
fn readCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    const self = try ownerOf(engine, roots[2]);
    // The whole native Read is one admission boundary. In particular, a live
    // promise getter cannot drain this service between construction/Dispatch.
    try self.controller.beginCall(engine);
    defer self.controller.endCall();
    var scope = Scope.init(engine);
    return scope.finish(readBody(&scope, self.controller, args, roots));
}
fn ownerFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value,
        c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    const controller = self.controller;
    controller.environment.allocator().destroy(self);
    controller.release();
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    try inputs.controller.beginCall(s.engine);
    defer inputs.controller.endCall();
    if (!c.JS_IsSymbol(inputs.use_promises) or !c.JS_IsObject(inputs.request_factory))
        return error.ActualFSReadBindingInputsRequired;
    const generation = try s.beforeAllocation();
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{
        .class_name = "Node native Read binding owner", .finalizer = ownerFinalizer,
    };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    try s.boundary.checkPendingSince(generation);
    const allocation = try s.beforeAllocation();
    const owner = try s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context,
        c.pi_js_null(), class_id), allocation);
    const self = try inputs.controller.environment.allocator().create(Owner);
    self.* = .{ .controller = inputs.controller.retain() };
    _ = c.JS_SetOpaque(owner, self);
    const function = try s.own(try functions.createMethod(s.engine, "read", 0, readCall,
        &.{ inputs.use_promises, inputs.request_factory, owner }));
    try s.pending();
    const status = c.JS_PiMarkNativeApiFunction(s.engine.context, function);
    try s.pending();
    if (status < 0) return error.ActualFSReadNativeApiProvenanceRequired;
    return a.duplicate(s.engine, function);
}
pub fn create(engine: *Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}

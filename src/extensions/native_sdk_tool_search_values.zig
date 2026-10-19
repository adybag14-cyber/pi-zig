//! Actual c268 tool-search expressions over the shared guest/owned boundary.
pub const h = @import("native_sdk_session_locals.zig");
pub const v = h.v;
pub const c = v.c;
pub const Engine = h.Engine;
pub const Scope = h.Scope;
pub const sync = @import("native_sync_arguments.zig");
pub const Arguments = sync.Arguments;
pub const Frame = @import("native_public_lexical_frame.zig").Frame;

pub fn function(s: *Scope, name: [*:0]const u8, length: c_int, definition: sync.Definition, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, v.function.createWithArguments(s.engine, name, length, definition, roots));
}
pub fn arrow(s: *Scope, name: [*:0]const u8, length: c_int, definition: sync.Definition, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, v.function.createArrowWithArguments(s.engine, name, length, definition, roots));
}
pub fn method(s: *Scope, name: [*:0]const u8, length: c_int, definition: sync.Definition, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, v.function.createMethodWithArguments(s.engine, name, length, definition, roots));
}
pub fn append(s: *Scope, target: c.JSValue, position: *u32, iterable: c.JSValue) !void {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_PiArrayAppend(s.engine.context, target, position, iterable));
}
pub fn literalRegex(s: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    return v.construct(s, s.engine.intrinsic_regexp_constructor, &.{try v.text(s, pattern), try v.text(s, flags)});
}
pub fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const method_value = try v.get(s, receiver, name);
    return v.call(s, method_value, receiver, args);
}
pub fn importCall(s: *Scope, module: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return v.call(s, try v.get(s, module, name), c.pi_js_undefined(), args);
}
pub fn fieldCompare(s: *Scope, target: c.JSValue, field: [*:0]const u8, operation: h.math.Operation, right: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try h.binary(s, operation, try v.get(s, target, field), right)));
}
pub fn fieldStrict(s: *Scope, target: c.JSValue, field: [*:0]const u8, right: c.JSValue) !c.JSValue {
    return v.boolean(s, c.JS_IsStrictEqual(s.engine.context, try v.get(s, target, field), right));
}
pub fn stringBody(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, value));
}
fn callReturn(s: *Scope, receiver: c.JSValue, called: *bool) !c.JSValue {
    const callee = try v.get(s, receiver, "return");
    if (v.nullish(callee)) return c.pi_js_undefined();
    called.* = true;
    return v.duplicate(s, try v.call(s, callee, receiver, &.{}));
}
pub fn closePair(s: *Scope, receiver: c.JSValue) !void {
    var called = false;
    const value = try v.own(s, try h.expression(s.engine, callReturn, .{receiver, &called}));
    if (called and !c.JS_IsObject(value)) return v.typeError(s, "not an object");
}

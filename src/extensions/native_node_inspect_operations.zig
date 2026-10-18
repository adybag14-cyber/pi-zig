//! Canonical operation and retirement seams for the real Node inspect owner.
//! Guest spans use actual pending/current-invocation provenance. A private
//! allocation generation is consulted only around a direct non-guest producer.
pub const v = @import("native_ai_provider_values.zig");
pub const c = v.c;
pub const Scope = @import("native_node_operation_scope.zig").Scope;
const guest = @import("native_sdk_guest_operation.zig");
const owned = @import("native_sdk_owned_completion.zig");

pub fn expression(engine: *v.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(@call(.auto, body, .{&s} ++ args));
}
pub fn own(s: *v.Scope, value: c.JSValue) !c.JSValue { return owned.ownRoot(s, value); }
fn bytesBody(s: *Scope, value: []const u8) !c.JSValue { return duplicate(s.engine, try s.text(value)); }
pub fn bytes(s: *v.Scope, value: []const u8) !c.JSValue { return own(s, try expression(s.engine, bytesBody, .{value})); }
fn objectBody(s: *Scope) !c.JSValue { return duplicate(s.engine, try s.object()); }
pub fn object(s: *v.Scope) !c.JSValue { return own(s, try expression(s.engine, objectBody, .{})); }
pub fn same(s: *v.Scope, value: c.JSValue, expected: []const u8) !bool { return s.equal(value, try bytes(s, expected)); }
fn duplicate(engine: *v.em.Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
fn keyBody(s: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    return duplicate(s.engine, try s.getKey(receiver, key));
}
pub fn key(s: *v.Scope, receiver: c.JSValue, property: c.JSValue) !c.JSValue {
    return owned.ownRoot(s, try expression(s.engine, keyBody, .{receiver, property}));
}
fn prototypeBody(s: *Scope, receiver: c.JSValue) !c.JSValue {
    return duplicate(s.engine, try s.prototype(receiver));
}
pub fn prototype(s: *v.Scope, receiver: c.JSValue) !c.JSValue {
    return owned.ownRoot(s, try expression(s.engine, prototypeBody, .{receiver}));
}
pub fn text(s: *v.Scope, value: c.JSValue) !c.JSValue { return guest.stringify(s, value); }
pub fn at(s: *v.Scope, receiver: c.JSValue, position: u32) !c.JSValue { return guest.at(s, receiver, position); }
fn atomBody(s: *Scope, property: c.JSAtom) !c.JSValue {
    const generation = try s.beforeAllocation();
    return duplicate(s.engine, try s.checkedAllocation(c.JS_AtomToValue(s.engine.context, property), generation));
}
pub fn atomValue(s: *v.Scope, property: c.JSAtom) !c.JSValue {
    return owned.ownRoot(s, try expression(s.engine, atomBody, .{property}));
}
fn nullObjectBody(s: *Scope) !c.JSValue { return duplicate(s.engine, try s.objectProto(c.pi_js_null())); }
pub fn nullObject(s: *v.Scope) !c.JSValue { return owned.ownRoot(s, try expression(s.engine, nullObjectBody, .{})); }
fn arrayBody(s: *Scope) !c.JSValue {
    const generation = try s.beforeAllocation();
    return duplicate(s.engine, try s.checkedAllocation(c.JS_NewArray(s.engine.context), generation));
}
pub fn array(s: *v.Scope) !c.JSValue { return owned.ownRoot(s, try expression(s.engine, arrayBody, .{})); }
fn utf16Body(s: *Scope, units: []const u16) !c.JSValue {
    const generation = try s.beforeAllocation();
    return duplicate(s.engine, try s.checkedAllocation(c.JS_NewStringUTF16(s.engine.context, units.ptr, units.len), generation));
}
pub fn utf16(s: *v.Scope, units: []const u16) !c.JSValue {
    return owned.ownRoot(s, try expression(s.engine, utf16Body, .{units}));
}
pub fn descriptor(s: *v.Scope, receiver: c.JSValue, key_value: c.JSValue) !?c.JSPropertyDescriptor {
    var stage = Scope.init(s.engine);
    var selected: ?c.JSPropertyDescriptor = null;
    var host_error: ?anyerror = null;
    if (stage.descriptor(receiver, key_value)) |result| selected = result else |err| host_error = err;
    var outputs = [_]c.JSValue{c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined()};
    if (selected) |item| outputs = .{item.value, item.getter, item.setter};
    try stage.boundary.finishMany(host_error, &stage.values, &outputs);
    if (selected) |item| return .{ .flags = item.flags, .value = outputs[0], .getter = outputs[1], .setter = outputs[2] };
    return null;
}
pub fn freeDescriptor(engine: *v.em.Engine, item: c.JSPropertyDescriptor) void {
    var completion = owned.Completion.initVoid(engine, {});
    completion.release(item.value);
    completion.release(item.getter);
    completion.release(item.setter);
    completion.finishVoid() catch {};
}
/// Placed AFTER the matching defer, so a typed failure is published before
/// the first descriptor owner retires on an error unwind.
pub fn recordFailure(engine: *v.em.Engine, err: anyerror) void {
    var completion = owned.Completion.initVoid(engine, err);
    completion.finishVoid() catch {};
}
pub fn discardCaught(engine: *v.em.Engine, err: anyerror) !void {
    const reason = try @import("native_agent_af_values.zig").caught(engine, err);
    var completion = owned.Completion.initVoid(engine, {});
    completion.release(reason);
    try completion.finishVoid();
}
pub fn keys(s: *v.Scope, receiver: c.JSValue, symbols: bool, hidden: bool) ![]c.JSPropertyEnum {
    var table: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    const flags: c_int = c.JS_GPN_STRING_MASK |
        (if (symbols) @as(c_int, c.JS_GPN_SYMBOL_MASK) else 0) |
        (if (hidden) @as(c_int, 0) else c.JS_GPN_ENUM_ONLY);
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const status = c.JS_GetOwnPropertyNames(s.engine.context, &table, &count, receiver, flags);
    boundary.finishStatus(status) catch |err| {
        if (status >= 0) c.JS_FreePropertyEnum(s.engine.context, table, count);
        return err;
    };
    return table[0..count];
}
fn instanceBody(s: *Scope, value: c.JSValue, constructor: c.JSValue) !c.JSValue {
    try s.pending();
    const status = c.JS_IsInstanceOf(s.engine.context, value, constructor);
    try s.pending();
    if (status < 0) return error.MissingActualInspectInstanceReason;
    return c.pi_js_bool(s.engine.context, @intFromBool(status != 0));
}
pub fn instance(s: *v.Scope, value: c.JSValue, constructor: c.JSValue) !bool {
    const result = expression(s.engine, instanceBody, .{value, constructor}) catch |err| {
        try discardCaught(s.engine, err);
        return false;
    };
    return c.JS_ToBool(s.engine.context, result) == 1;
}
fn targetBody(s: *Scope, value: c.JSValue) !c.JSValue {
    // This linked-VM primitive only unwraps a proxy; it invokes no proxy trap.
    const generation = try s.beforeAllocation();
    return duplicate(s.engine, try s.checkedAllocation(c.JS_GetProxyTarget(s.engine.context, value), generation));
}
pub fn proxyTarget(s: *v.Scope, value: c.JSValue) !c.JSValue {
    return owned.ownRoot(s, try expression(s.engine, targetBody, .{value}));
}
fn hasBody(s: *Scope, receiver: c.JSValue, key_value: c.JSValue) !c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(try s.hasKey(receiver, key_value)));
}
pub fn has(s: *v.Scope, receiver: c.JSValue, key_value: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try expression(s.engine, hasBody, .{receiver, key_value})) == 1;
}
pub fn setKey(s: *v.Scope, receiver: c.JSValue, key_value: c.JSValue, value: c.JSValue) !void {
    var stage = Scope.init(s.engine);
    var outputs: [0]c.JSValue = .{};
    const host_error: ?anyerror = failure: {
        setKeyBody(&stage, receiver, key_value, value) catch |err| break :failure err;
        break :failure null;
    };
    try stage.boundary.finishMany(host_error, &stage.values, &outputs);
}
fn setKeyBody(s: *Scope, receiver: c.JSValue, key_value: c.JSValue, value: c.JSValue) !void {
    try s.pending();
    const property = c.JS_ValueToAtom(s.engine.context, key_value);
    defer if (property != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, property);
    try s.pending();
    if (property == c.JS_ATOM_NULL) return error.MissingActualInspectPropertyKeyReason;
    const status = c.JS_SetProperty(s.engine.context, receiver, property, duplicate(s.engine, value));
    try s.pending();
    if (status < 0) return error.MissingActualInspectPropertySetReason;
}

pub fn defineAtom(s: *v.Scope, target: c.JSValue, property: c.JSAtom, value: c.JSValue, flags: c_int) !void {
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_DefinePropertyValue(s.engine.context, target, property, duplicate(s.engine, value), flags | c.JS_PROP_THROW));
}
pub fn define(s: *v.Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) !void {
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_DefinePropertyValueStr(s.engine.context, target, name, duplicate(s.engine, value), flags | c.JS_PROP_THROW));
}
pub fn index(s: *v.Scope, target: c.JSValue, position: u32, value: c.JSValue) !void { return guest.index(s, target, position, value); }
pub fn setPrototype(s: *v.Scope, target: c.JSValue, prototype_value: c.JSValue) !void {
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_SetPrototype(s.engine.context, target, prototype_value));
}
pub fn remove(s: *v.Scope, target: c.JSValue, property: c.JSAtom) !void {
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_DeleteProperty(s.engine.context, target, property, c.JS_PROP_THROW));
}
fn copyFieldBody(s: *Scope, target: c.JSValue, source: c.JSValue, property: c.JSAtom, item: c.JSPropertyDescriptor) !c.JSValue {
    if (item.flags & c.JS_PROP_ENUMERABLE != 0) {
        const value = try guest.getAtom(&s.values, source, property);
        try defineAtom(&s.values, target, property, value, c.JS_PROP_C_W_E);
    }
    return c.pi_js_undefined();
}
fn copyField(s: *Scope, target: c.JSValue, source: c.JSValue, property: c.JSAtom) !c.JSValue {
    const key_value = try atomValue(&s.values, property);
    const item = try s.descriptor(source, key_value) orelse return c.pi_js_undefined();
    var completion = owned.Completion.initValue(s.engine, copyFieldBody(s, target, source, property, item));
    completion.release(item.value); completion.release(item.getter); completion.release(item.setter);
    return completion.finishValue();
}
fn copyIntoBody(s: *Scope, target: c.JSValue, source: c.JSValue) !c.JSValue {
    if (c.JS_IsNull(source) or c.JS_IsUndefined(source)) return c.pi_js_undefined();
    const boxed = try guest.toObject(&s.values, source);
    const properties = try keys(&s.values, boxed, true, true);
    defer c.JS_FreePropertyEnum(s.engine.context, properties.ptr, @intCast(properties.len));
    for (properties) |entry| _ = try expression(s.engine, copyField, .{target, boxed, entry.atom});
    return c.pi_js_undefined();
}
pub fn copyInto(s: *v.Scope, target: c.JSValue, source: c.JSValue) !void {
    _ = try expression(s.engine, copyIntoBody, .{target, source});
}
fn spreadBody(s: *Scope, source: c.JSValue) !c.JSValue {
    const target = try s.object();
    try copyInto(&s.values, target, source);
    return duplicate(s.engine, target);
}
pub fn spread(s: *v.Scope, source: c.JSValue) !c.JSValue {
    return own(s, try expression(s.engine, spreadBody, .{source}));
}

pub fn float64(s: *v.Scope, value: c.JSValue) !f64 {
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    var result: f64 = 0;
    try boundary.finishStatus(c.JS_ToFloat64(s.engine.context, &result, value));
    return result;
}
pub fn uint32(s: *v.Scope, value: c.JSValue) !u32 {
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    var result: u32 = 0;
    try boundary.finishStatus(c.JS_ToUint32(s.engine.context, &result, value));
    return result;
}
pub fn preventExtensions(s: *v.Scope, value: c.JSValue) !void {
    var boundary: guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    try boundary.finishStatus(c.JS_PreventExtensions(s.engine.context, value));
}
fn accessorBody(s: *Scope, target: c.JSValue, name: [*:0]const u8, getter: c.JSValue, setter: c.JSValue, flags: c_int) !c.JSValue {
    // A fixed primitive atom producer invokes no guest conversion.
    const generation = try s.beforeAllocation();
    const property = c.JS_NewAtom(s.engine.context, name);
    defer if (property != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, property);
    try s.boundary.checkPendingSince(generation);
    if (property == c.JS_ATOM_NULL) return error.MissingActualInspectAccessorAtomReason;
    try s.pending();
    const status = c.JS_DefinePropertyGetSet(s.engine.context, target, property, duplicate(s.engine, getter), duplicate(s.engine, setter), flags | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualInspectAccessorDefinitionReason;
    return c.pi_js_undefined();
}
pub fn accessor(s: *v.Scope, target: c.JSValue, name: [*:0]const u8, getter: c.JSValue, setter: c.JSValue, flags: c_int) !void {
    _ = try expression(s.engine, accessorBody, .{target, name, getter, setter, flags});
}

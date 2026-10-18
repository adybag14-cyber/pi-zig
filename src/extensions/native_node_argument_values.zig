//! Local expression lifetimes for the genuine internal/errors graph.
//! Each caller chooses the Source expression boundary; there is no guest-wide
//! allocation generation inference or separate error identity registry.
pub const v = @import("native_ai_provider_values.zig");
pub const c = v.c;
pub const Scope = @import("native_node_operation_scope.zig").Scope;
pub const owned = @import("native_sdk_owned_completion.zig");
pub const frames = @import("native_public_lexical_frame.zig");
pub fn duplicate(engine: *v.em.Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
pub fn arg(args: []const c.JSValue, position: usize) c.JSValue { return if (position < args.len) args[position] else c.pi_js_undefined(); }
pub fn expression(engine: *v.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(@call(.auto, body, .{&s} ++ args));
}
pub fn condition(engine: *v.em.Engine, comptime body: anytype, args: anytype) !bool {
    return c.JS_ToBool(engine.context, try expression(engine, body, args)) == 1;
}
pub fn boolean(s: *Scope, value: bool) c.JSValue { return c.pi_js_bool(s.engine.context, @intFromBool(value)); }
pub fn finishFrame(s: *Scope, frame: anytype, result: anyerror!c.JSValue) !c.JSValue {
    var completion = owned.Completion.initValue(s.engine, result);
    frame.close(&completion);
    return s.finish(completion.finishValue());
}
pub fn add(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { return s.binary(0, left, right); }
pub fn fieldBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(s.engine, try s.get(receiver, name));
}
pub fn field(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return expression(engine, fieldBody, .{receiver, name});
}
pub fn fieldTruthy(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return boolean(s, s.truthy(try s.get(receiver, name)));
}
pub fn fieldTextBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return duplicate(s.engine, try s.toString(try s.get(receiver, name)));
}
pub fn fieldText(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return expression(engine, fieldTextBody, .{receiver, name});
}
pub fn callBody(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return duplicate(s.engine, try s.call(function, receiver, args));
}
pub fn call(engine: *v.em.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return expression(engine, callBody, .{function, receiver, args});
}
pub fn array(s: *Scope) !c.JSValue {
    const generation = try s.beforeAllocation();
    return s.checkedAllocation(c.JS_NewArray(s.engine.context), generation);
}
pub fn index(s: *Scope, receiver: c.JSValue, position: u32, value: c.JSValue) !void {
    try s.pending();
    const status = c.JS_DefinePropertyValueUint32(s.engine.context, receiver, position, duplicate(s.engine, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualArgumentIndexDefinitionReason;
}
pub fn raise(s: *Scope, reason: c.JSValue) anyerror {
    // This is an explicit synchronous Source throw. JS_Throw preserves the
    // actual value's flags; it becomes a pending event at this exact boundary.
    return s.boundary.rejectOwned(c.JS_Throw(s.engine.context, duplicate(s.engine, reason)));
}

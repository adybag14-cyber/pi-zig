//! Local TTY/Node operations use the canonical guest-operation boundary.
//! A successful flagged/private result remains DATA; only actual pending/current
//! invocation events stop a guest span. Scope ownership stays source-local.
const v = @import("native_ai_provider_values.zig");
const guest = @import("native_sdk_guest_operation.zig");
const owned = @import("native_sdk_owned_completion.zig");
pub const c = v.c;
pub const Scope = v.Scope;
pub fn pending(engine: *v.em.Engine) !void { return engine.checkNativeEntry(); }
pub fn success(engine: *v.em.Engine, value: c.JSValue) !c.JSValue {
    var completion = owned.Completion.initValue(engine, engine.checked(value));
    return completion.finishValue();
}
pub fn get(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return guest.get(s, receiver, name); }
pub fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue { return guest.call(s, function, receiver, args); }
pub fn invoke(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return guest.invoke(s, receiver, name, args); }
pub fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    var boundary: guest.Boundary = .{ .engine = engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW));
}
pub fn set(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { return guest.set(s, target, name, value); }
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn binary(s: *Scope, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !c.JSValue { return guest.binary(s, @intFromEnum(operation), left, right); }
pub fn same(s: *Scope, value: c.JSValue, text: []const u8) !bool { return s.equal(value, try s.text(text)); }
pub fn construct(s: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue { return guest.construct(s, function, args); }
pub fn throwValue(engine: *v.em.Engine, reason: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    unreachable;
}

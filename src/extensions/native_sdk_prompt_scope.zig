//! Private temporary roots for synchronous original prompt algorithms.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
pub const c = em.c;
pub const Scope = struct {
    engine: *em.Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    pub fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    pub fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    pub fn get(self: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
        return self.own(try sdk.get(self.engine, value, name));
    }
    pub fn global(self: *Scope, name: [*:0]const u8) !c.JSValue {
        return self.own(try js.global(self.engine, name));
    }
    pub fn text(self: *Scope, bytes: []const u8) !c.JSValue {
        return self.own(try sdk.text(self.engine, bytes));
    }
    pub fn object(self: *Scope) !c.JSValue {
        return self.own(try sdk.object(self.engine));
    }
    pub fn array(self: *Scope) !c.JSValue {
        return self.own(try sdk.array(self.engine));
    }
    pub fn call(self: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        return self.own(try js.call(self.engine, function, receiver, args));
    }
    pub fn invoke(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.call(try self.get(receiver, name), receiver, args);
    }
    pub fn put(self: *Scope, object_value: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        return sdk.put(self.engine, object_value, name, c.JS_DupValue(self.engine.context, value));
    }
    pub fn set(self: *Scope, object_value: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        if (c.JS_SetPropertyStr(self.engine.context, object_value, name, c.JS_DupValue(self.engine.context, value)) < 0) return js.capture(self.engine);
    }
    pub fn index(self: *Scope, target: c.JSValue, position: u32, value: c.JSValue) !void {
        if (c.JS_DefinePropertyValueUint32(self.engine.context, target, position, c.JS_DupValue(self.engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(self.engine);
    }
    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_PiBinaryOperator(self.engine.context, 0, left, right)));
    }
    pub fn stringify(self: *Scope, value: c.JSValue) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_ToString(self.engine.context, value)));
    }
    pub fn truthy(self: *Scope, value: c.JSValue) bool {
        return c.JS_ToBool(self.engine.context, value) == 1;
    }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool {
        return c.JS_IsStrictEqual(self.engine.context, left, right);
    }
    pub fn positive(self: *Scope, value: c.JSValue) !bool {
        return self.truthy(try self.own(try self.engine.checked(c.JS_PiBinaryOperator(self.engine.context, 6, value, c.JS_NewInt32(self.engine.context, 0)))));
    }
};
pub fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}

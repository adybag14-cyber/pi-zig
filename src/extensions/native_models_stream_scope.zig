//! Streaming continuation roots use bounded inline storage before heap overflow.
//! Iterator completion after terminal publication must not allocate host roots.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const guest = @import("native_sdk_guest_operation.zig");
const owned = @import("native_sdk_owned_completion.zig");
pub const c = em.c;
pub const Scope = struct {
    engine: *em.Engine,
    inline_values: [32]c.JSValue = undefined,
    inline_count: usize = 0,
    values: std.ArrayList(c.JSValue) = .empty,
    pub fn deinit(self: *Scope) void {
        const count = self.inline_count;
        self.inline_count = 0;
        var roots = self.values;
        self.values = .empty;
        for (self.inline_values[0..count]) |value| self.engine.releaseNativeValue(value);
        for (roots.items) |value| self.engine.releaseNativeValue(value);
        roots.deinit(self.engine.gpa);
    }
    pub fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        return owned.ownRoot(self, value);
    }
    pub fn get(self: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
        return guest.get(self, value, name);
    }
    pub fn global(self: *Scope, name: [*:0]const u8) !c.JSValue {
        return guest.global(self, name);
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
        return guest.call(self, function, receiver, args);
    }
    pub fn invoke(self: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return guest.invoke(self, receiver, name, args);
    }
    pub fn put(self: *Scope, object_value: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        return guest.put(self, object_value, name, value);
    }
    pub fn set(self: *Scope, object_value: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        return guest.set(self, object_value, name, value);
    }
    pub fn index(self: *Scope, target: c.JSValue, position: u32, value: c.JSValue) !void {
        return guest.index(self, target, position, value);
    }
    pub fn concat(self: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
        return guest.binary(self, 0, left, right);
    }
    pub fn stringify(self: *Scope, value: c.JSValue) !c.JSValue {
        return guest.stringify(self, value);
    }
    pub fn truthy(self: *Scope, value: c.JSValue) bool {
        return c.JS_ToBool(self.engine.context, value) == 1;
    }
    pub fn equal(self: *Scope, left: c.JSValue, right: c.JSValue) bool {
        return c.JS_IsStrictEqual(self.engine.context, left, right);
    }
    pub fn positive(self: *Scope, value: c.JSValue) !bool {
        return self.truthy(try guest.binary(self, 6, value, c.JS_NewInt32(self.engine.context, 0)));
    }
};
pub fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}

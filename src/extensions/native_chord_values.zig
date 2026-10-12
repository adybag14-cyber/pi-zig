//! Short-lived owner-thread roots for concrete Chord algorithms.
const std = @import("std");
pub const js = @import("native_js_values.zig");
pub const c = js.c;
pub const Scope = struct {
    engine: *js.Engine,
    owned: std.ArrayList(c.JSValue) = .empty,
    pub fn deinit(self: *Scope) void {
        for (self.owned.items) |value| self.engine.freeValue(value);
        self.owned.deinit(self.engine.gpa);
    }
    pub fn keep(self: *Scope, value: c.JSValue) !c.JSValue {
        self.owned.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    pub fn get(self: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
        return self.keep(try js.get(self.engine, object, name));
    }
    pub fn key(self: *Scope, object: c.JSValue, name: c.JSValue) !c.JSValue {
        return self.keep(try js.getKey(self.engine, object, name));
    }
    pub fn at(self: *Scope, object: c.JSValue, index: usize) !c.JSValue {
        return self.keep(try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, object, @intCast(index))));
    }
    pub fn builtin(self: *Scope, owner: [*:0]const u8, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        const object = try self.keep(try js.global(self.engine, owner));
        return self.keep(try js.invoke(self.engine, object, method, args));
    }
    pub fn text(self: *Scope, value: []const u8) !c.JSValue {
        return self.keep(try self.engine.checked(c.JS_NewStringLen(self.engine.context, value.ptr, value.len)));
    }
    pub fn record(self: *Scope) !c.JSValue {
        return self.keep(try js.object(self.engine));
    }
    pub fn list(self: *Scope) !c.JSValue {
        return self.keep(try js.array(self.engine));
    }
    pub fn keys(self: *Scope, value: c.JSValue) !c.JSValue {
        return self.builtin("Object", "keys", &.{value});
    }
    pub fn entries(self: *Scope, value: c.JSValue) !c.JSValue {
        return self.builtin("Object", "entries", &.{value});
    }
    pub fn has(self: *Scope, value: c.JSValue, name: []const u8) !bool {
        return js.hasKey(self.engine, value, try self.text(name));
    }
    pub fn equal(self: *Scope, value: c.JSValue, label: []const u8) !bool {
        return c.JS_IsStrictEqual(self.engine.context, value, try self.text(label));
    }
    pub fn result(self: *Scope, value: c.JSValue) c.JSValue {
        return c.JS_DupValue(self.engine.context, value);
    }
};

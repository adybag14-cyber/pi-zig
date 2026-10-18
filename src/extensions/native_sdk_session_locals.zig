//! Session Source locals and expression boundaries, sharing AF33/C435.
//! BCDF assigns a new for-of head before entering/resetting its body; an
//! uncaptured final slot remains live until its enclosing function returns.
pub const v = @import("native_public_values.zig");
pub const c = v.c;
pub const Engine = v.em.Engine;
pub const Scope = v.Scope;
pub const math = @import("native_image_arithmetic.zig");
pub fn Frame(comptime Names: type) type {
    return struct {
        engine: *Engine,
        values: [@typeInfo(Names).@"enum".fields.len]c.JSValue,
        const Self = @This();
        pub fn init(engine: *Engine) Self { return .{ .engine = engine, .values = @splat(c.pi_js_undefined()) }; }
        pub fn get(self: *const Self, comptime name: Names) c.JSValue { return self.values[@intFromEnum(name)]; }
        pub fn set(self: *Self, comptime name: Names, incoming: anyerror!c.JSValue) !void {
            // An abrupt RHS never assigns the Source slot. On success publish
            // before freeing the old value, exactly like BCDF set_value.
            const next = try incoming;
            const previous = self.values[@intFromEnum(name)];
            self.values[@intFromEnum(name)] = next;
            var completion = v.owned.Completion.initVoid(self.engine, {});
            completion.release(previous);
            return completion.finishVoid();
        }
        pub fn clear(self: *Self, comptime name: Names) !void { return self.set(name, c.pi_js_undefined()); }
        pub fn finish(self: *Self, result: anyerror!c.JSValue) !c.JSValue {
            var completion = v.owned.Completion.initValue(self.engine, result);
            // Function locals retire in their declaration order in BCDF.
            for (&self.values) |*value| { completion.release(value.*); value.* = c.pi_js_undefined(); }
            return completion.finishValue();
        }
        pub fn finishVoid(self: *Self, result: anyerror!void) !void {
            var completion = v.owned.Completion.initVoid(self.engine, result);
            for (&self.values) |*value| { completion.release(value.*); value.* = c.pi_js_undefined(); }
            return completion.finishVoid();
        }
    };
}
pub fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
pub fn statement(engine: *Engine, comptime body: anytype, args: anytype) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
pub fn duplicate(engine: *Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
pub fn truthy(engine: *Engine, value: c.JSValue) bool { return c.JS_ToBool(engine.context, value) == 1; }
pub fn number(engine: *Engine, value: f64) c.JSValue { return c.JS_NewFloat64(engine.context, value); }
pub fn text(engine: *Engine, bytes: []const u8) !c.JSValue { return expression(engine, textBody, .{bytes}); }
fn textBody(s: *Scope, bytes: []const u8) !c.JSValue { return v.duplicate(s, try v.text(s, bytes)); }
pub fn array(engine: *Engine) !c.JSValue { return expression(engine, arrayBody, .{}); }
fn arrayBody(s: *Scope) !c.JSValue { return v.duplicate(s, try v.array(s)); }
pub fn get(engine: *Engine, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return expression(engine, getBody, .{ target, name });
}
fn getBody(s: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue { return v.duplicate(s, try v.get(s, target, name)); }
pub fn nested(engine: *Engine, target: c.JSValue, first: [*:0]const u8, second: [*:0]const u8) !c.JSValue {
    return expression(engine, nestedBody, .{ target, first, second });
}
fn nestedBody(s: *Scope, target: c.JSValue, first: [*:0]const u8, second: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.get(s, target, first), second));
}
pub fn fieldEqual(engine: *Engine, target: c.JSValue, name: [*:0]const u8, expected: []const u8) !bool {
    return truthy(engine, try expression(engine, fieldEqualBody, .{ target, name, expected }));
}
fn fieldEqualBody(s: *Scope, target: c.JSValue, name: [*:0]const u8, expected: []const u8) !c.JSValue {
    return v.boolean(s, try v.eq(s, try v.get(s, target, name), expected));
}
pub const FieldTest = enum { truthy, nullish, string, number };
pub fn fieldTest(engine: *Engine, target: c.JSValue, name: [*:0]const u8, comptime kind: FieldTest) !bool {
    return truthy(engine, try expression(engine, fieldTestBody, .{ target, name, kind }));
}
fn fieldTestBody(s: *Scope, target: c.JSValue, name: [*:0]const u8, comptime kind: FieldTest) !c.JSValue {
    const value = try v.get(s, target, name);
    return v.boolean(s, switch (kind) {
        .truthy => v.truthy(s, value), .nullish => v.nullish(value),
        .string => c.JS_IsString(value), .number => c.JS_IsNumber(value),
    });
}
pub fn nestedEqual(engine: *Engine, target: c.JSValue, first: [*:0]const u8, second: [*:0]const u8, expected: []const u8) !bool {
    return truthy(engine, try expression(engine, nestedEqualBody, .{ target, first, second, expected }));
}
fn nestedEqualBody(s: *Scope, target: c.JSValue, first: [*:0]const u8, second: [*:0]const u8, expected: []const u8) !c.JSValue {
    const value = try v.own(s, try nested(s.engine, target, first, second));
    return v.boolean(s, try v.eq(s, value, expected));
}
pub fn binary(s: *Scope, operation: math.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.binary(s, @intFromEnum(operation), left, right);
}
pub fn compare(engine: *Engine, operation: math.Operation, left: c.JSValue, right: c.JSValue) !bool {
    return truthy(engine, try expression(engine, compareBody, .{ operation, left, right }));
}
fn compareBody(s: *Scope, operation: math.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try binary(s, operation, left, right)));
}
pub fn increment(engine: *Engine, value: c.JSValue) !c.JSValue {
    return expression(engine, incrementBody, .{value});
}
fn incrementBody(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.guest.increment(s, value));
}
pub fn key(engine: *Engine, target: c.JSValue, property: c.JSValue) !c.JSValue {
    return expression(engine, keyBody, .{ target, property });
}
fn keyBody(s: *Scope, target: c.JSValue, property: c.JSValue) !c.JSValue { return v.duplicate(s, try v.key(s, target, property)); }
pub fn discard(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    return statement(engine, discardBody, .{ receiver, name, args });
}
fn discardBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    _ = try v.invoke(s, receiver, name, args);
}
pub fn construct(engine: *Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return expression(engine, constructBody, .{ name, args });
}
fn constructBody(s: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.construct(s, try v.global(s, name), args));
}
pub fn assign(engine: *Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    return statement(engine, assignBody, .{ target, name, value });
}
fn assignBody(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void { return v.set(s, target, name, value); }

pub fn keyFromField(engine: *Engine, target: c.JSValue, source: c.JSValue, name: [*:0]const u8) !c.JSValue {
    var coercion: Scope = .{ .engine = engine }; var atom: c.JSAtom = c.JS_ATOM_NULL;
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(engine.context, atom);
    try v.owned.finishVoid(&coercion, fieldAtom(&coercion, source, name, &atom));
    return expression(engine, atomGet, .{ target, atom });
}
fn fieldAtom(s: *Scope, source: c.JSValue, name: [*:0]const u8, atom: *c.JSAtom) !void {
    const property = try v.get(s, source, name);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    atom.* = c.JS_ValueToAtom(s.engine.context, property);
    return boundary.finishStatus(if (atom.* == c.JS_ATOM_NULL) -1 else 0);
}
fn atomGet(s: *Scope, target: c.JSValue, atom: c.JSAtom) !c.JSValue {
    return v.duplicate(s, try v.guest.getAtom(s, target, atom));
}
pub fn delete(engine: *Engine, target: c.JSValue, name: []const u8) !void {
    return statement(engine, deleteBody, .{ target, name });
}
fn deleteBody(s: *Scope, target: c.JSValue, name: []const u8) !void {
    const property = try v.text(s, name);
    var coercion: v.guest.Boundary = .{ .engine = s.engine }; try coercion.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, property);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try coercion.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const status = c.JS_DeleteProperty(s.engine.context, target, atom, c.JS_PROP_THROW);
    return boundary.finishStatus(if (status < 0) status else 0);
}

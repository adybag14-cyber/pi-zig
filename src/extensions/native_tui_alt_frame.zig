//! Owner-thread rooted temporaries for alternate-screen Source algorithms.
//! The frame never hides ordinary Source fields or virtual method lookups.
const std = @import("std");
pub const js = @import("native_js_values.zig");
pub const c = js.c;
pub const v = @import("native_select_list.zig");
pub const Frame = struct {
    engine: *js.Engine,
    object: c.JSValue,
    bindings: c.JSValue,
    values: std.ArrayList(c.JSValue) = .empty,
    native_steps: usize = 0,
    pub fn deinit(self: *Frame) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    pub fn own(self: *Frame, value: c.JSValue) anyerror!c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    pub fn result(self: *Frame, value: c.JSValue) c.JSValue {
        return c.JS_DupValue(self.engine.context, value);
    }
    pub fn get(self: *Frame, object: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
        return self.own(try js.get(self.engine, object, name));
    }
    pub fn field(self: *Frame, name: [*:0]const u8) anyerror!c.JSValue {
        return self.get(self.object, name);
    }
    pub fn at(self: *Frame, object: c.JSValue, index: f64) anyerror!c.JSValue {
        return self.own(try js.getKey(self.engine, object, self.num(index)));
    }
    pub fn global(self: *Frame, name: [*:0]const u8) anyerror!c.JSValue {
        const root = c.JS_GetGlobalObject(self.engine.context);
        defer self.engine.freeValue(root);
        const atom = c.JS_NewAtom(self.engine.context, name);
        if (atom == c.JS_ATOM_NULL) return js.capture(self.engine);
        defer c.JS_FreeAtom(self.engine.context, atom);
        const exists = c.JS_HasProperty(self.engine.context, root, atom);
        if (exists < 0) return js.capture(self.engine);
        if (exists == 0) {
            _ = try self.engine.checked(c.JS_ThrowReferenceError(self.engine.context, "%s is not defined", name));
            unreachable;
        }
        return self.own(try js.global(self.engine, name));
    }
    pub fn text(self: *Frame, text_value: []const u8) anyerror!c.JSValue {
        return self.own(try v.text(self.engine, text_value));
    }
    pub fn array(self: *Frame) anyerror!c.JSValue {
        return self.own(try js.array(self.engine));
    }
    pub fn literal(self: *Frame, elements: []const c.JSValue) anyerror!c.JSValue {
        const output = try self.array();
        for (elements, 0..) |element, index| {
            if (c.JS_DefinePropertyValueUint32(self.engine.context, output, @intCast(index), c.JS_DupValue(self.engine.context, element), c.JS_PROP_C_W_E) < 0) return js.capture(self.engine);
        }
        return output;
    }
    pub fn record(self: *Frame) anyerror!c.JSValue {
        return self.own(try js.object(self.engine));
    }
    pub fn spread(self: *Frame, object: c.JSValue) anyerror!c.JSValue {
        return self.own(try js.spread(self.engine, object));
    }
    pub fn copy(self: *Frame, source_array: c.JSValue) anyerror!c.JSValue {
        const result_array = try self.array();
        const symbol = try self.get(self.bindings, "iteratorSymbol");
        var iterator = try js.Iterator.init(self.engine, source_array, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        var index: u32 = 0;
        while (try iterator.next()) |item| {
            defer self.engine.freeValue(item);
            if (c.JS_DefinePropertyValueUint32(self.engine.context, result_array, index, c.JS_DupValue(self.engine.context, item), c.JS_PROP_C_W_E) < 0) return js.capture(self.engine);
            index += 1;
        }
        return result_array;
    }
    pub fn pair(self: *Frame, iterable: c.JSValue) anyerror![2]c.JSValue {
        const values = try js.pair(self.engine, iterable, try self.get(self.bindings, "iteratorSymbol"));
        // Getting the symbol can grow the list, so reserve again before
        // transferring the two values returned by iterator destructuring.
        self.values.ensureUnusedCapacity(self.engine.gpa, 2) catch |err| {
            for (values) |value| self.engine.freeValue(value);
            return err;
        };
        self.values.appendAssumeCapacity(values[0]);
        self.values.appendAssumeCapacity(values[1]);
        return values;
    }
    pub fn set(self: *Frame, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        return v.set(self.engine, object, name, c.JS_DupValue(self.engine.context, value));
    }
    pub fn put(self: *Frame, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        return self.set(self.object, name, value);
    }
    pub fn define(self: *Frame, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!void {
        return js.define(self.engine, object, name, c.JS_DupValue(self.engine.context, value));
    }
    pub fn push(self: *Frame, object: c.JSValue, value: c.JSValue) anyerror!void {
        return js.push(self.engine, object, value);
    }
    pub fn call(self: *Frame, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
        return self.own(try js.call(self.engine, function, receiver, args));
    }
    pub fn method(self: *Frame, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) anyerror!c.JSValue {
        return self.own(try js.invoke(self.engine, object, name, args));
    }
    pub fn invoke(self: *Frame, name: [*:0]const u8, args: []const c.JSValue) anyerror!c.JSValue {
        return self.method(self.object, name, args);
    }
    pub fn imported(self: *Frame, name: [*:0]const u8, args: []const c.JSValue) anyerror!c.JSValue {
        return self.call(try self.get(self.bindings, name), c.pi_js_undefined(), args);
    }
    pub fn construct(self: *Frame, constructor: c.JSValue, args: []const c.JSValue) anyerror!c.JSValue {
        return self.own(try self.engine.checked(c.JS_CallConstructor(self.engine.context, constructor, @intCast(args.len), @constCast(args.ptr))));
    }
    pub fn math(self: *Frame, name: [*:0]const u8, args: []const c.JSValue) anyerror!f64 {
        return self.number(try self.method(try self.global("Math"), name, args));
    }
    pub fn number(self: *Frame, value: c.JSValue) anyerror!f64 {
        return v.number(self.engine, value);
    }
    pub fn n(self: *Frame, object: c.JSValue, name: [*:0]const u8) anyerror!f64 {
        // Native loop conditions must retain the VM's cancellation and work
        // budget even when a guest replaces callbacks with entirely native
        // functions or getters. No JavaScript value leaves the owner thread.
        self.native_steps +|= 1;
        if (self.engine.cancelled.load(.acquire) or (self.native_steps % 256 == 0 and blk: {
            self.engine.interrupts +|= 1;
            break :blk self.engine.interrupts > self.engine.options.interrupt_budget;
        })) {
            _ = try self.engine.checked(c.JS_ThrowInternalError(self.engine.context, "interrupted"));
            unreachable;
        }
        return self.number(try self.get(object, name));
    }
    pub fn num(self: *Frame, numeric_value: f64) c.JSValue {
        return v.numeric(self.engine, numeric_value);
    }
    pub fn boolean(self: *Frame, value: bool) c.JSValue {
        return c.pi_js_bool(self.engine.context, @intFromBool(value));
    }
    pub fn truth(self: *Frame, value: c.JSValue) bool {
        return v.truthy(self.engine, value);
    }
    pub fn equal(self: *Frame, a: c.JSValue, b: c.JSValue) bool {
        return c.JS_IsStrictEqual(self.engine.context, a, b);
    }
    pub fn is(self: *Frame, value: c.JSValue, expected_text: []const u8) anyerror!bool {
        return self.equal(value, try self.text(expected_text));
    }
    pub fn nullish(_: *Frame, value: c.JSValue) bool {
        return c.JS_IsNull(value) or c.JS_IsUndefined(value);
    }
    pub fn concat(self: *Frame, parts: []const c.JSValue) anyerror!c.JSValue {
        return self.own(try v.concat(self.engine, parts));
    }
    pub fn add(self: *Frame, a: c.JSValue, b: c.JSValue) anyerror!c.JSValue {
        return self.own(try @import("native_tui_value_arithmetic.zig").add(self.engine, a, b, try self.get(self.bindings, "primitiveSymbol")));
    }
    pub fn width(self: *Frame, value: c.JSValue) anyerror!f64 {
        return self.number(try self.imported("visibleWidth", &.{value}));
    }
    pub fn emptyLine(self: *Frame, lines: c.JSValue, row: f64) anyerror!c.JSValue {
        const value = try self.at(lines, row);
        return if (self.nullish(value)) self.text("") else value;
    }
    pub fn write(self: *Frame, value: c.JSValue) anyerror!void {
        _ = try self.method(try self.field("terminal"), "write", &.{value});
    }
};
pub fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowTypeError(engine.context, "Native TuiAltScreen: %s", @as([*:0]const u8, @errorName(err)));
}

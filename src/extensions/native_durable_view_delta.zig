//! Persistent application of already validated document operations to view mounts.
//! This is an internal projection helper, not the public Chord delta API.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn item(self: *Scope, object: c.JSValue, index: usize) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, object, @intCast(index))));
    }
    fn get(self: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue {
        const atom = try js.atom(self.engine, key);
        defer c.JS_FreeAtom(self.engine.context, atom);
        const present = c.JS_GetOwnProperty(self.engine.context, null, object, atom);
        if (present < 0) return js.capture(self.engine);
        if (present == 0) return error.UnresolvableViewDeltaPath;
        return self.own(try self.engine.checked(c.JS_GetProperty(self.engine.context, object, atom)));
    }
};
fn put(engine: *Engine, object: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const atom = try js.atom(engine, key);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, object, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
fn copy(scope: *Scope, value: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (c.JS_IsArray(value)) return scope.own(try vm.invoke(engine, value, "slice", &.{}));
    if (!c.JS_IsObject(value)) return error.UnresolvableViewDeltaPath;
    const prototype = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, value)));
    const result = try scope.own(try engine.checked(if (c.JS_IsNull(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context)));
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, value, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    for (properties[0..count]) |property| {
        const child = try engine.checked(c.JS_GetProperty(engine.context, value, property.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, property.atom, child, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    return result;
}
fn tag(scope: *Scope, operation: c.JSValue) !u8 {
    const value = try scope.item(operation, 0);
    const text = try scope.engine.toString(value);
    defer scope.engine.gpa.free(text);
    if (text.len != 1) return error.InvalidViewDelta;
    return text[0];
}
fn number(engine: *Engine, value: c.JSValue) !u32 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    if (!std.math.isFinite(result) or result < 0 or result != @trunc(result) or result > std.math.maxInt(u32)) return error.InvalidViewDelta;
    return @intFromFloat(result);
}
pub fn apply(engine: *Engine, initial: c.JSValue, operations: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var root = initial;
    for (0..try vm.length(engine, operations)) |operation_index| {
        const operation = try scope.item(operations, operation_index);
        const kind = try tag(&scope, operation);
        if (kind == 'r') {
            root = try scope.item(operation, 1);
            continue;
        }
        const path = try scope.item(operation, 1);
        const length = try vm.length(engine, path);
        const is_array_operation = kind == 'p' or kind == 'm';
        if (!is_array_operation and length == 0) return error.InvalidViewDelta;
        const ancestors = if (is_array_operation) length else length - 1;
        root = try copy(&scope, root);
        var destination = root;
        for (0..ancestors) |index| {
            const key = try scope.item(path, index);
            const child = try copy(&scope, try scope.get(destination, key));
            try put(engine, destination, key, child);
            destination = child;
        }
        if (kind == 'p') {
            if (!c.JS_IsArray(destination)) return error.UnresolvableViewDeltaPath;
            const at = try scope.item(operation, 2);
            const remove = try scope.item(operation, 3);
            _ = try scope.own(try vm.invoke(engine, destination, "splice", &.{ at, remove }));
            const inserted = try scope.item(operation, 4);
            var offset: usize = 0;
            while (offset < try vm.length(engine, inserted)) {
                const count = @min(10000, try vm.length(engine, inserted) - offset);
                var arguments: std.ArrayList(c.JSValue) = .empty;
                defer arguments.deinit(engine.gpa);
                try arguments.append(engine.gpa, c.JS_NewFloat64(engine.context, @as(f64, @floatFromInt(try number(engine, at))) + @as(f64, @floatFromInt(offset))));
                try arguments.append(engine.gpa, c.JS_NewInt32(engine.context, 0));
                for (0..count) |index| try arguments.append(engine.gpa, try scope.item(inserted, offset + index));
                _ = try scope.own(try vm.invoke(engine, destination, "splice", arguments.items));
                offset += count;
            }
            continue;
        }
        if (kind == 'm') {
            if (!c.JS_IsArray(destination)) return error.UnresolvableViewDeltaPath;
            const permutation = try scope.item(operation, 2);
            if (try vm.length(engine, permutation) != try vm.length(engine, destination)) return error.InvalidViewDelta;
            const previous = try scope.own(try vm.invoke(engine, destination, "slice", &.{}));
            for (0..try vm.length(engine, permutation)) |index| try put(engine, destination, c.JS_NewFloat64(engine.context, @floatFromInt(index)), try scope.item(previous, try number(engine, try scope.item(permutation, index))));
            continue;
        }
        const key = try scope.item(path, length - 1);
        if (kind == 'd') {
            if (c.JS_IsArray(destination)) {
                _ = try scope.own(try vm.invoke(engine, destination, "splice", &.{ key, c.JS_NewInt32(engine.context, 1) }));
            } else {
                const atom = try js.atom(engine, key);
                defer c.JS_FreeAtom(engine.context, atom);
                if (c.JS_DeleteProperty(engine.context, destination, atom, c.JS_PROP_THROW) < 0) return js.capture(engine);
            }
            continue;
        }
        const operand = try scope.item(operation, 2);
        const replacement = switch (kind) {
            's' => operand,
            'a' => try scope.own(try @import("native_utf16.zig").concat(engine, &.{ try scope.get(destination, key), operand })),
            't' => value: {
                const units = try @import("native_utf16.zig").unitsAlloc(engine, try scope.get(destination, key));
                defer engine.gpa.free(units);
                break :value try scope.own(try @import("native_utf16.zig").string(engine, units[@min(units.len, try number(engine, operand))..]));
            },
            else => return error.InvalidViewDelta,
        };
        try put(engine, destination, key, replacement);
    }
    return c.JS_DupValue(engine.context, root);
}

//! Owner-VM Pi tool argument normalization and TypeBox/plain schema coercion.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const clone_mod = @import("native_structured_clone.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const ConversionPair = struct { schema: c.JSValue, value: c.JSValue };
const Active = std.ArrayList(ConversionPair);
fn enter(engine: *Engine, active: *Active, schema: c.JSValue, value: c.JSValue) !void {
    for (active.items) |pair| {
        if (!c.JS_IsStrictEqual(engine.context, pair.schema, schema)) continue;
        var same = c.JS_IsStrictEqual(engine.context, pair.value, value);
        if (!same and c.JS_IsNumber(pair.value) and c.JS_IsNumber(value)) {
            var left: f64 = 0;
            var right: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &left, pair.value) < 0 or c.JS_ToFloat64(engine.context, &right, value) < 0) return error.JavaScriptException;
            same = std.math.isNan(left) and std.math.isNan(right);
        }
        if (same) {
            _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
            unreachable;
        }
    }
    try active.append(engine.gpa, .{ .schema = schema, .value = value });
}
pub const Validators = struct {
    engine: *Engine,
    context: *anyopaque,
    compile: *const fn (*anyopaque, c.JSValue) anyerror!c.JSValue,
    check: *const fn (*anyopaque, c.JSValue, c.JSValue) anyerror!bool,
    fn matches(self: Validators, schema: c.JSValue, value: c.JSValue) !?bool {
        const compiled = self.compile(self.context, schema) catch return null;
        defer self.engine.freeValue(compiled);
        return try self.check(self.context, compiled, value);
    }
};
fn property(engine: *Engine, value: c.JSValue, key: []const u8) !c.JSValue {
    const atom = c.JS_NewAtomLen(engine.context, key.ptr, key.len);
    defer c.JS_FreeAtom(engine.context, atom);
    return engine.checked(c.JS_GetProperty(engine.context, value, atom));
}
fn set(engine: *Engine, value: c.JSValue, key: []const u8, child: c.JSValue) !void {
    const atom = c.JS_NewAtomLen(engine.context, key.ptr, key.len);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_SetProperty(engine.context, value, atom, child) < 0) return error.JavaScriptException;
}
fn has(engine: *Engine, value: c.JSValue, key: []const u8) !bool {
    const atom = c.JS_NewAtomLen(engine.context, key.ptr, key.len);
    defer c.JS_FreeAtom(engine.context, atom);
    const result = c.JS_HasProperty(engine.context, value, atom);
    if (result < 0) return error.JavaScriptException;
    return result > 0;
}
fn keys(engine: *Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try vm.get(engine, global, "Object");
    defer engine.freeValue(object);
    return vm.invoke(engine, object, "keys", &.{value});
}
fn finite(engine: *Engine, value: c.JSValue) !?f64 {
    if (!c.JS_IsNumber(value)) return null;
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
    return if (std.math.isFinite(number)) number else null;
}
fn globalCall(engine: *Engine, name: [:0]const u8, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const callback = try vm.get(engine, global, name);
    defer engine.freeValue(callback);
    var args = [_]c.JSValue{value};
    return engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &args));
}
fn label(engine: *Engine, value: c.JSValue) ![]u8 {
    return engine.toString(value);
}
fn bigint(engine: *Engine, value: c.JSValue) !c.JSValue {
    return globalCall(engine, "BigInt", value);
}
fn typeMatches(engine: *Engine, name: []const u8, value: c.JSValue) !bool {
    if (std.mem.eql(u8, name, "number")) return c.JS_IsNumber(value);
    if (std.mem.eql(u8, name, "integer")) {
        const number = try finite(engine, value) orelse return false;
        return number == @trunc(number);
    }
    if (std.mem.eql(u8, name, "boolean")) return c.JS_IsBool(value);
    if (std.mem.eql(u8, name, "string")) return c.JS_IsString(value);
    if (std.mem.eql(u8, name, "null")) return c.JS_IsNull(value);
    if (std.mem.eql(u8, name, "array")) return c.JS_IsArray(value);
    if (std.mem.eql(u8, name, "object")) return c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value) and !c.JS_IsArray(value);
    return false;
}
pub fn normalize(engine: *Engine, schema: c.JSValue, value: c.JSValue, validators: Validators) anyerror!void {
    var active: Active = .empty;
    defer active.deinit(engine.gpa);
    return normalizeWalk(engine, schema, value, validators, &active);
}
fn normalizeWalk(engine: *Engine, schema: c.JSValue, value: c.JSValue, validators: Validators, active: *Active) anyerror!void {
    try enter(engine, active, schema, value);
    defer _ = active.pop();
    if (c.JS_IsArray(value)) {
        const items = try vm.get(engine, schema, "items");
        defer engine.freeValue(items);
        if (c.JS_IsArray(items)) {
            for (0..@min(try vm.length(engine, value), try vm.length(engine, items))) |index| {
                const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
                defer engine.freeValue(child);
                const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index)));
                defer engine.freeValue(rule);
                if (!c.JS_IsUndefined(rule) and !c.JS_IsNull(rule)) try normalizeWalk(engine, rule, child, validators, active);
            }
        } else if (!c.JS_IsUndefined(items) and !c.JS_IsNull(items)) for (0..try vm.length(engine, value)) |index| {
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
            defer engine.freeValue(child);
            try normalizeWalk(engine, items, child, validators, active);
        };
        return;
    }
    if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value)) return;
    const properties = try vm.get(engine, schema, "properties");
    defer engine.freeValue(properties);
    if (c.JS_IsUndefined(properties) or c.JS_IsNull(properties)) return;
    const required = try vm.get(engine, schema, "required");
    defer engine.freeValue(required);
    const names = try keys(engine, properties);
    defer engine.freeValue(names);
    for (0..try vm.length(engine, names)) |index| {
        const name_value = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, @intCast(index)));
        defer engine.freeValue(name_value);
        const name = try label(engine, name_value);
        defer engine.gpa.free(name);
        if (!try has(engine, value, name)) continue;
        const rule = try property(engine, properties, name);
        defer engine.freeValue(rule);
        const child = try property(engine, value, name);
        defer engine.freeValue(child);
        var mandatory = false;
        if (c.JS_IsArray(required)) for (0..try vm.length(engine, required)) |at| {
            const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, required, @intCast(at)));
            defer engine.freeValue(item);
            mandatory = mandatory or c.JS_IsStrictEqual(engine.context, item, name_value);
        };
        const reference = try vm.get(engine, rule, "$ref");
        defer engine.freeValue(reference);
        if (c.JS_IsNull(child) and !mandatory and !c.JS_IsString(reference)) {
            if (try validators.matches(rule, c.pi_js_null())) |valid| if (!valid) {
                const atom = c.JS_NewAtomLen(engine.context, name.ptr, name.len);
                defer c.JS_FreeAtom(engine.context, atom);
                if (c.JS_DeleteProperty(engine.context, value, atom, c.JS_PROP_THROW) < 0) return error.JavaScriptException;
                continue;
            };
        }
        try normalizeWalk(engine, rule, child, validators, active);
    }
}
fn primitive(engine: *Engine, value: c.JSValue, name: []const u8, typed: bool) !c.JSValue {
    if (std.mem.eql(u8, name, "number") or std.mem.eql(u8, name, "integer")) {
        var result: ?f64 = null;
        if (c.JS_IsNull(value) or (typed and c.JS_IsUndefined(value))) result = 0 else if (c.JS_IsBool(value)) result = if (c.JS_ToBool(engine.context, value) != 0) 1 else 0 else if (typed and try finite(engine, value) != null) result = (try finite(engine, value)).? else if (c.JS_IsString(value)) {
            if (typed) {
                var number: f64 = 0;
                if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
                if (std.math.isFinite(number)) result = number;
            } else {
                const trimmed = try vm.invoke(engine, value, "trim", &.{});
                defer engine.freeValue(trimmed);
                const empty = try engine.checked(c.JS_NewString(engine.context, ""));
                defer engine.freeValue(empty);
                if (!c.JS_IsStrictEqual(engine.context, trimmed, empty)) {
                    const converted = try globalCall(engine, "Number", value);
                    defer engine.freeValue(converted);
                    result = try finite(engine, converted);
                }
            }
            if (typed and result == null) {
                const lower = try vm.invoke(engine, value, "toLowerCase", &.{});
                defer engine.freeValue(lower);
                const lowered = if (c.JS_IsString(lower)) try label(engine, lower) else null;
                defer if (lowered) |text| engine.gpa.free(text);
                if (lowered != null and std.mem.eql(u8, lowered.?, "true")) result = 1 else if (lowered != null and std.mem.eql(u8, lowered.?, "false")) result = 0 else {
                    const converted = try tryBigInt(engine, value);
                    defer engine.freeValue(converted);
                    if (c.JS_IsBigInt(converted)) {
                        const number = try globalCall(engine, "Number", converted);
                        defer engine.freeValue(number);
                        const candidate = try finite(engine, number);
                        if (candidate != null and @abs(candidate.?) <= 9007199254740991) result = candidate;
                    }
                }
            }
        } else if (typed and c.JS_IsBigInt(value)) {
            const number = try globalCall(engine, "Number", value);
            defer engine.freeValue(number);
            const candidate = try finite(engine, number);
            if (candidate != null and @abs(candidate.?) <= 9007199254740991) result = candidate;
        }
        if (result) |number| {
            if (std.mem.eql(u8, name, "integer")) {
                if (typed) return engine.checked(c.JS_NewFloat64(engine.context, @trunc(number)));
                if (number != @trunc(number)) return c.JS_DupValue(engine.context, value);
            }
            return engine.checked(c.JS_NewFloat64(engine.context, number));
        }
    } else if (std.mem.eql(u8, name, "string")) {
        if (c.JS_IsNull(value)) return engine.checked(c.JS_NewString(engine.context, if (typed) "null" else ""));
        if (typed and c.JS_IsUndefined(value)) return engine.checked(c.JS_NewString(engine.context, ""));
        if (c.JS_IsBool(value) or (if (typed) try finite(engine, value) != null else c.JS_IsNumber(value)) or (typed and c.JS_IsBigInt(value))) return globalCall(engine, "String", value);
    } else if (std.mem.eql(u8, name, "boolean")) {
        if (c.JS_IsNull(value) or (typed and c.JS_IsUndefined(value))) return c.pi_js_bool(engine.context, 0);
        if (c.JS_IsBool(value)) return c.JS_DupValue(engine.context, value);
        if (c.JS_IsString(value)) {
            const lower = if (typed) try vm.invoke(engine, value, "toLowerCase", &.{}) else c.JS_DupValue(engine.context, value);
            defer engine.freeValue(lower);
            if (!c.JS_IsString(lower)) return c.JS_DupValue(engine.context, value);
            const text = try label(engine, lower);
            defer engine.gpa.free(text);
            if (std.mem.eql(u8, text, "true") or (typed and std.mem.eql(u8, text, "1"))) return c.pi_js_bool(engine.context, 1);
            if (std.mem.eql(u8, text, "false") or (typed and std.mem.eql(u8, text, "0"))) return c.pi_js_bool(engine.context, 0);
        } else if (try finite(engine, value)) |number| {
            if (number == 0 or number == 1) return c.pi_js_bool(engine.context, @intFromBool(number == 1));
        } else if (typed and c.JS_IsBigInt(value)) {
            const zero = try engine.checked(c.JS_NewBigInt64(engine.context, 0));
            defer engine.freeValue(zero);
            const one = try engine.checked(c.JS_NewBigInt64(engine.context, 1));
            defer engine.freeValue(one);
            if (c.JS_IsStrictEqual(engine.context, value, zero)) return c.pi_js_bool(engine.context, 0);
            if (c.JS_IsStrictEqual(engine.context, value, one)) return c.pi_js_bool(engine.context, 1);
        }
    } else if (std.mem.eql(u8, name, "null")) {
        if (c.JS_IsNull(value) or (typed and c.JS_IsUndefined(value))) return c.pi_js_null();
        if (c.JS_IsBool(value) and c.JS_ToBool(engine.context, value) == 0) return c.pi_js_null();
        if (try finite(engine, value)) |number| {
            if (number == 0) return c.pi_js_null();
        }
        if (c.JS_IsString(value)) {
            const original = try label(engine, value);
            defer engine.gpa.free(original);
            const lower = if (typed) try vm.invoke(engine, value, "toLowerCase", &.{}) else c.JS_DupValue(engine.context, value);
            defer engine.freeValue(lower);
            if (original.len == 0 or (typed and std.mem.eql(u8, original, "0"))) return c.pi_js_null();
            if (!c.JS_IsString(lower)) return c.JS_DupValue(engine.context, value);
            const text = try label(engine, lower);
            defer engine.gpa.free(text);
            if (typed and (std.mem.eql(u8, text, "null") or std.mem.eql(u8, text, "undefined"))) return c.pi_js_null();
        } else if (typed and c.JS_IsBigInt(value)) {
            const zero = try engine.checked(c.JS_NewBigInt64(engine.context, 0));
            defer engine.freeValue(zero);
            if (c.JS_IsStrictEqual(engine.context, value, zero)) return c.pi_js_null();
        }
    } else if (typed and std.mem.eql(u8, name, "bigint")) return tryBigInt(engine, value);
    return c.JS_DupValue(engine.context, value);
}
fn tryBigInt(engine: *Engine, value: c.JSValue) !c.JSValue {
    if (c.JS_IsBigInt(value)) return c.JS_DupValue(engine.context, value);
    if (c.JS_IsBool(value) or c.JS_IsNull(value) or c.JS_IsUndefined(value)) {
        const input = c.pi_js_int32(engine.context, if (c.JS_IsBool(value) and c.JS_ToBool(engine.context, value) != 0) 1 else 0);
        return bigint(engine, input);
    }
    if (try finite(engine, value)) |number| {
        const input = try engine.checked(c.JS_NewFloat64(engine.context, @trunc(number)));
        defer engine.freeValue(input);
        return bigint(engine, input);
    }
    if (c.JS_IsString(value)) {
        const lower = try vm.invoke(engine, value, "toLowerCase", &.{});
        defer engine.freeValue(lower);
        const lowered = if (c.JS_IsString(lower)) try label(engine, lower) else null;
        defer if (lowered) |text| engine.gpa.free(text);
        const text = try label(engine, value);
        defer engine.gpa.free(text);
        if (lowered != null and (std.mem.eql(u8, lowered.?, "true") or std.mem.eql(u8, lowered.?, "false"))) return bigint(engine, c.pi_js_int32(engine.context, if (std.mem.eql(u8, lowered.?, "true")) 1 else 0));
        var decimal = text;
        var index: usize = if (decimal.len != 0 and decimal[0] == '-') 1 else 0;
        if (index == decimal.len) return c.JS_DupValue(engine.context, value);
        if (decimal[index] == '0' and index + 1 < decimal.len and std.ascii.isDigit(decimal[index + 1])) return c.JS_DupValue(engine.context, value);
        const start = index;
        while (index < decimal.len and std.ascii.isDigit(decimal[index])) : (index += 1) {}
        if (index == start) return c.JS_DupValue(engine.context, value);
        if (index < decimal.len) {
            if (decimal[index] == 'n' and index + 1 == decimal.len) decimal = decimal[0..index] else if (decimal[index] == '.') {
                const end = index;
                index += 1;
                const fraction = index;
                while (index < decimal.len and std.ascii.isDigit(decimal[index])) : (index += 1) {}
                if (index != decimal.len or index == fraction) return c.JS_DupValue(engine.context, value);
                decimal = decimal[0..end];
            } else return c.JS_DupValue(engine.context, value);
        }
        const input = try engine.checked(c.JS_NewStringLen(engine.context, decimal.ptr, decimal.len));
        defer engine.freeValue(input);
        return bigint(engine, input);
    }
    return c.JS_DupValue(engine.context, value);
}
fn match(engine: *Engine, expression: []const u8, value: c.JSValue) !bool {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "RegExp");
    defer engine.freeValue(constructor);
    const source = try engine.checked(c.JS_NewStringLen(engine.context, expression.ptr, expression.len));
    defer engine.freeValue(source);
    const regexp = try @import("native_schema_regexp.zig").construct(engine, constructor, source, null);
    defer engine.freeValue(regexp);
    const result = try vm.invoke(engine, regexp, "test", &.{value});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn ownNames(engine: *Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try vm.get(engine, global, "Object");
    defer engine.freeValue(object);
    return vm.invoke(engine, object, "getOwnPropertyNames", &.{value});
}
fn isOptional(engine: *Engine, schema: c.JSValue) !bool {
    return c.JS_IsObject(schema) and !c.JS_IsFunction(engine.context, schema) and try has(engine, schema, "~optional");
}
pub fn convertTypeBox(engine: *Engine, schema: c.JSValue, value: c.JSValue, validators: Validators) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    var active: Active = .empty;
    defer active.deinit(engine.gpa);
    return typedValue(engine, schema, value, validators, c.pi_js_undefined(), &active) catch |err| return engine.nativeAllocationError(err, generation);
}
pub fn evaluateLiteralKind(engine: *Engine, schema: c.JSValue, enumeration: bool) !c.JSValue {
    const field = try vm.get(engine, schema, if (enumeration) "enum" else "pattern");
    defer engine.freeValue(field);
    const values = if (enumeration) c.JS_DupValue(engine.context, field) else (try @import("native_typebox_pattern.zig").literals(engine, field) orelse {
        const output = try vm.object(engine);
        errdefer engine.freeValue(output);
        try vm.put(engine, output, "type", try engine.checked(c.JS_NewString(engine.context, "string")));
        if (c.JS_DefinePropertyValueStr(engine.context, output, "~kind", c.JS_NewString(engine.context, "String"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
        return output;
    });
    defer engine.freeValue(values);
    return @import("typebox.zig").evaluateLiteralValues(engine, values);
}
fn typedValue(engine: *Engine, schema: c.JSValue, value: c.JSValue, validators: Validators, refs: c.JSValue, active: *Active) anyerror!c.JSValue {
    try enter(engine, active, schema, value);
    defer _ = active.pop();
    if (!c.JS_IsObject(schema) or c.JS_IsFunction(engine.context, schema)) return c.JS_DupValue(engine.context, value);
    const kind_value = try vm.get(engine, schema, "~kind");
    defer engine.freeValue(kind_value);
    if (!c.JS_IsString(kind_value)) return c.JS_DupValue(engine.context, value);
    const kind = try label(engine, kind_value);
    defer engine.gpa.free(kind);
    inline for (.{ "Number", "Integer", "String", "Boolean", "Null", "BigInt" }, .{ "number", "integer", "string", "boolean", "null", "bigint" }) |name, type_name| if (std.mem.eql(u8, kind, name)) return primitive(engine, value, type_name, true);
    if (std.mem.eql(u8, kind, "Undefined") or std.mem.eql(u8, kind, "Void")) {
        const converted = try primitive(engine, value, "null", true);
        if (c.JS_IsNull(converted)) {
            engine.freeValue(converted);
            return c.pi_js_undefined();
        }
        return converted;
    }
    if (std.mem.eql(u8, kind, "Literal")) {
        const constant = try vm.get(engine, schema, "const");
        defer engine.freeValue(constant);
        if (c.JS_IsStrictEqual(engine.context, constant, value)) return c.JS_DupValue(engine.context, value);
        const target: []const u8 = if (c.JS_IsBigInt(constant)) "bigint" else if (c.JS_IsBool(constant)) "boolean" else if (c.JS_IsNumber(constant)) "number" else if (c.JS_IsString(constant)) "string" else return error.InvalidTypeBoxLiteral;
        const converted = try primitive(engine, value, target, true);
        if (c.JS_IsStrictEqual(engine.context, converted, constant)) return converted;
        engine.freeValue(converted);
        return c.JS_DupValue(engine.context, value);
    }
    if (std.mem.eql(u8, kind, "Enum") or std.mem.eql(u8, kind, "TemplateLiteral")) {
        const evaluated = try evaluateLiteralKind(engine, schema, std.mem.eql(u8, kind, "Enum"));
        defer engine.freeValue(evaluated);
        return typedValue(engine, evaluated, value, validators, refs, active);
    }
    if (std.mem.eql(u8, kind, "Array")) {
        const items = try vm.get(engine, schema, "items");
        defer engine.freeValue(items);
        const output = try vm.array(engine);
        errdefer engine.freeValue(output);
        const count = if (c.JS_IsArray(value)) try vm.length(engine, value) else 1;
        try vm.put(engine, output, "length", c.JS_NewInt64(engine.context, @intCast(count)));
        for (0..count) |index| {
            const child = if (c.JS_IsArray(value)) try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index))) else c.JS_DupValue(engine.context, value);
            defer engine.freeValue(child);
            if (c.JS_IsArray(value)) {
                const atom = c.JS_NewAtomUInt32(engine.context, @intCast(index));
                defer c.JS_FreeAtom(engine.context, atom);
                const present = c.JS_HasProperty(engine.context, value, atom);
                if (present < 0) return error.JavaScriptException;
                if (present == 0) continue;
            }
            if (c.JS_SetPropertyUint32(engine.context, output, @intCast(index), try typedValue(engine, items, child, validators, refs, active)) < 0) return error.JavaScriptException;
        }
        return output;
    }
    if (std.mem.eql(u8, kind, "Tuple")) {
        if (!c.JS_IsArray(value)) return c.JS_DupValue(engine.context, value);
        const items = try vm.get(engine, schema, "items");
        defer engine.freeValue(items);
        for (0..@min(try vm.length(engine, items), try vm.length(engine, value))) |index| {
            const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index)));
            defer engine.freeValue(rule);
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
            defer engine.freeValue(child);
            if (c.JS_SetPropertyUint32(engine.context, value, @intCast(index), try typedValue(engine, rule, child, validators, refs, active)) < 0) return error.JavaScriptException;
        }
        return c.JS_DupValue(engine.context, value);
    }
    if (std.mem.eql(u8, kind, "Object") or std.mem.eql(u8, kind, "Record")) {
        if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value) or c.JS_IsArray(value)) return c.JS_DupValue(engine.context, value);
        const rules = try vm.get(engine, schema, if (std.mem.eql(u8, kind, "Object")) "properties" else "patternProperties");
        defer engine.freeValue(rules);
        const names = try ownNames(engine, rules);
        defer engine.freeValue(names);
        const actual = try ownNames(engine, value);
        defer engine.freeValue(actual);
        var expressions: std.ArrayList([]u8) = .empty;
        defer {
            for (expressions.items) |text| engine.gpa.free(text);
            expressions.deinit(engine.gpa);
        }
        for (0..try vm.length(engine, names)) |index| {
            const key_value = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, @intCast(index)));
            defer engine.freeValue(key_value);
            const key = try label(engine, key_value);
            defer engine.gpa.free(key);
            const rule = try property(engine, rules, key);
            defer engine.freeValue(rule);
            const expression = try std.fmt.allocPrint(engine.gpa, "^{s}$", .{key});
            expressions.append(engine.gpa, expression) catch |err| {
                engine.gpa.free(expression);
                return err;
            };
            for (0..try vm.length(engine, actual)) |at| {
                const name_value = try engine.checked(c.JS_GetPropertyUint32(engine.context, actual, @intCast(at)));
                defer engine.freeValue(name_value);
                if (!try match(engine, expression, name_value)) continue;
                const name = try label(engine, name_value);
                defer engine.gpa.free(name);
                const child = try property(engine, value, name);
                defer engine.freeValue(child);
                if (std.mem.eql(u8, kind, "Object") and try isOptional(engine, rule) and c.JS_IsUndefined(child)) continue;
                try set(engine, value, name, try typedValue(engine, rule, child, validators, refs, active));
            }
        }
        const additional = try vm.get(engine, schema, "additionalProperties");
        defer engine.freeValue(additional);
        if (c.JS_IsObject(additional)) {
            const current = try ownNames(engine, value);
            defer engine.freeValue(current);
            for (0..try vm.length(engine, current)) |index| {
                const name_value = try engine.checked(c.JS_GetPropertyUint32(engine.context, current, @intCast(index)));
                defer engine.freeValue(name_value);
                var covered = false;
                for (expressions.items) |expression| if (try match(engine, expression, name_value)) {
                    covered = true;
                    break;
                };
                if (covered) continue;
                const name = try label(engine, name_value);
                defer engine.gpa.free(name);
                const child = try property(engine, value, name);
                defer engine.freeValue(child);
                try set(engine, value, name, try typedValue(engine, additional, child, validators, refs, active));
            }
        }
        return c.JS_DupValue(engine.context, value);
    }
    if (std.mem.eql(u8, kind, "Union")) {
        const rules = try vm.get(engine, schema, "anyOf");
        defer engine.freeValue(rules);
        for (0..try vm.length(engine, rules)) |index| {
            const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, rules, @intCast(index)));
            defer engine.freeValue(rule);
            if (try @import("native_tool_validation.zig").checkWithContext(engine, refs, rule, value)) return c.JS_DupValue(engine.context, value);
        }
        var candidates: std.ArrayList(c.JSValue) = .empty;
        defer {
            for (candidates.items) |candidate| engine.freeValue(candidate);
            candidates.deinit(engine.gpa);
        }
        for (0..try vm.length(engine, rules)) |index| {
            const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, rules, @intCast(index)));
            defer engine.freeValue(rule);
            const detached = try @import("typebox.zig").cloneValue(engine, value);
            defer engine.freeValue(detached);
            const candidate = try typedValue(engine, rule, detached, validators, refs, active);
            candidates.append(engine.gpa, candidate) catch |err| {
                engine.freeValue(candidate);
                return err;
            };
        }
        for (candidates.items) |candidate| if (try @import("native_tool_validation.zig").checkWithContext(engine, refs, schema, candidate)) {
            // Array.find stops at the first passing candidate even if its value
            // is undefined. The caller then falls back to the original input.
            return c.JS_DupValue(engine.context, if (c.JS_IsUndefined(candidate)) value else candidate);
        };
        return c.JS_DupValue(engine.context, value);
    }
    if (std.mem.eql(u8, kind, "Intersect")) {
        const evaluated = try @import("typebox.zig").evaluateIntersection(engine, schema);
        defer engine.freeValue(evaluated);
        return typedValue(engine, evaluated, value, validators, refs, active);
    }
    if (std.mem.eql(u8, kind, "Ref")) {
        const reference = try vm.get(engine, schema, "$ref");
        defer engine.freeValue(reference);
        const name = try label(engine, reference);
        defer engine.gpa.free(name);
        if (c.JS_IsObject(refs) and try has(engine, refs, name)) {
            const target = try property(engine, refs, name);
            defer engine.freeValue(target);
            return typedValue(engine, target, value, validators, refs, active);
        }
    } else if (std.mem.eql(u8, kind, "Cyclic")) {
        const definitions = try vm.get(engine, schema, "$defs");
        defer engine.freeValue(definitions);
        const merged = try vm.object(engine);
        defer engine.freeValue(merged);
        for ([_]c.JSValue{ refs, definitions }) |dictionary| if (c.JS_IsObject(dictionary)) {
            const names = try keys(engine, dictionary);
            defer engine.freeValue(names);
            for (0..try vm.length(engine, names)) |index| {
                const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, @intCast(index)));
                defer engine.freeValue(key);
                const name = try label(engine, key);
                defer engine.gpa.free(name);
                try set(engine, merged, name, try property(engine, dictionary, name));
            }
        };
        const reference = try vm.get(engine, schema, "$ref");
        defer engine.freeValue(reference);
        const name = try label(engine, reference);
        defer engine.gpa.free(name);
        if (try has(engine, merged, name)) {
            const target = try property(engine, merged, name);
            defer engine.freeValue(target);
            return typedValue(engine, target, value, validators, merged, active);
        }
    }
    return c.JS_DupValue(engine.context, value);
}
pub fn convertJsonSchema(engine: *Engine, schema: c.JSValue, value: c.JSValue, validators: Validators) anyerror!c.JSValue {
    var active: Active = .empty;
    defer active.deinit(engine.gpa);
    return jsonWalk(engine, schema, value, validators, &active);
}
fn jsonWalk(engine: *Engine, schema: c.JSValue, value: c.JSValue, validators: Validators, active: *Active) anyerror!c.JSValue {
    try enter(engine, active, schema, value);
    defer _ = active.pop();
    var next = c.JS_DupValue(engine.context, value);
    errdefer engine.freeValue(next);
    const all = try vm.get(engine, schema, "allOf");
    defer engine.freeValue(all);
    if (c.JS_IsArray(all)) for (0..try vm.length(engine, all)) |index| {
        const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, all, @intCast(index)));
        defer engine.freeValue(rule);
        const converted = try jsonWalk(engine, rule, next, validators, active);
        engine.freeValue(next);
        next = converted;
    };
    inline for (.{ "anyOf", "oneOf" }) |keyword| {
        const rules = try vm.get(engine, schema, keyword);
        defer engine.freeValue(rules);
        if (c.JS_IsArray(rules)) {
            var matched = false;
            for (0..try vm.length(engine, rules)) |index| {
                const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, rules, @intCast(index)));
                defer engine.freeValue(rule);
                if (try validators.matches(rule, next)) |valid| if (valid) {
                    matched = true;
                    break;
                };
            }
            if (!matched) for (0..try vm.length(engine, rules)) |index| {
                const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, rules, @intCast(index)));
                defer engine.freeValue(rule);
                const detached = try clone_mod.clone(engine, next);
                defer engine.freeValue(detached);
                const candidate = try jsonWalk(engine, rule, detached, validators, active);
                if (try validators.matches(rule, candidate)) |valid| if (valid) {
                    engine.freeValue(next);
                    next = candidate;
                    break;
                };
                engine.freeValue(candidate);
            };
        }
    }
    const types = try vm.get(engine, schema, "type");
    defer engine.freeValue(types);
    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |name| engine.gpa.free(name);
        names.deinit(engine.gpa);
    }
    if (c.JS_IsString(types)) {
        const text = try label(engine, types);
        names.append(engine.gpa, text) catch |err| {
            engine.gpa.free(text);
            return err;
        };
    } else if (c.JS_IsArray(types)) for (0..try vm.length(engine, types)) |index| {
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, types, @intCast(index)));
        defer engine.freeValue(item);
        if (c.JS_IsString(item)) {
            const text = try label(engine, item);
            names.append(engine.gpa, text) catch |err| {
                engine.gpa.free(text);
                return err;
            };
        }
    };
    var matched = false;
    if (names.items.len > 1) for (names.items) |name| {
        matched = matched or try typeMatches(engine, name, next);
    };
    if (!matched) for (names.items) |name| {
        const candidate = try primitive(engine, next, name, false);
        if (!c.JS_IsStrictEqual(engine.context, candidate, next)) {
            engine.freeValue(next);
            next = candidate;
            break;
        }
        engine.freeValue(candidate);
    };
    var object = false;
    var array = false;
    for (names.items) |name| {
        object = object or std.mem.eql(u8, name, "object");
        array = array or std.mem.eql(u8, name, "array");
    }
    if (object and c.JS_IsObject(next) and !c.JS_IsFunction(engine.context, next) and !c.JS_IsArray(next)) {
        const properties = try vm.get(engine, schema, "properties");
        defer engine.freeValue(properties);
        const declared = if (c.JS_IsObject(properties)) try keys(engine, properties) else try vm.array(engine);
        defer engine.freeValue(declared);
        for (0..try vm.length(engine, declared)) |index| {
            const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, declared, @intCast(index)));
            defer engine.freeValue(key);
            const name = try label(engine, key);
            defer engine.gpa.free(name);
            if (!try has(engine, next, name)) continue;
            const rule = try property(engine, properties, name);
            defer engine.freeValue(rule);
            const child = try property(engine, next, name);
            defer engine.freeValue(child);
            try set(engine, next, name, try jsonWalk(engine, rule, child, validators, active));
        }
        const additional = try vm.get(engine, schema, "additionalProperties");
        defer engine.freeValue(additional);
        if (c.JS_IsObject(additional)) {
            const actual = try keys(engine, next);
            defer engine.freeValue(actual);
            for (0..try vm.length(engine, actual)) |index| {
                const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, actual, @intCast(index)));
                defer engine.freeValue(key);
                const name = try label(engine, key);
                defer engine.gpa.free(name);
                const included = try vm.invoke(engine, declared, "includes", &.{key});
                defer engine.freeValue(included);
                if (c.JS_ToBool(engine.context, included) != 0) continue;
                const child = try property(engine, next, name);
                defer engine.freeValue(child);
                try set(engine, next, name, try jsonWalk(engine, additional, child, validators, active));
            }
        }
    }
    if (array and c.JS_IsArray(next)) {
        const items = try vm.get(engine, schema, "items");
        defer engine.freeValue(items);
        if (c.JS_IsArray(items)) {
            for (0..@min(try vm.length(engine, next), try vm.length(engine, items))) |index| {
                const rule = try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index)));
                defer engine.freeValue(rule);
                if (c.JS_IsUndefined(rule) or c.JS_IsNull(rule)) continue;
                const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, next, @intCast(index)));
                defer engine.freeValue(child);
                if (c.JS_SetPropertyUint32(engine.context, next, @intCast(index), try jsonWalk(engine, rule, child, validators, active)) < 0) return error.JavaScriptException;
            }
        } else if (c.JS_IsObject(items)) for (0..try vm.length(engine, next)) |index| {
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, next, @intCast(index)));
            defer engine.freeValue(child);
            if (c.JS_SetPropertyUint32(engine.context, next, @intCast(index), try jsonWalk(engine, items, child, validators, active)) < 0) return error.JavaScriptException;
        };
    }
    return next;
}

fn testCompile(context: *anyopaque, schema: c.JSValue) !c.JSValue {
    const engine: *Engine = @ptrCast(@alignCast(context));
    return c.JS_DupValue(engine.context, schema);
}
fn testCheck(context: *anyopaque, schema: c.JSValue, value: c.JSValue) !bool {
    const engine: *Engine = @ptrCast(@alignCast(context));
    var result = try @import("native_tool_validation.zig").evaluate(engine, schema, value);
    defer result.deinit(engine.gpa);
    return result.valid;
}
fn testConvert(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc < 2) return c.JS_ThrowTypeError(context, "Expected schema and value");
    return testConvertOwned(engine, argv[0], argv[1]) catch |err| {
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(context, "Conversion: %s", @as([*:0]const u8, @errorName(err)));
    };
}
fn testConvertOwned(engine: *Engine, schema: c.JSValue, input: c.JSValue) !c.JSValue {
    const validators: Validators = .{ .engine = engine, .context = engine, .compile = testCompile, .check = testCheck };
    const args = try clone_mod.clone(engine, input);
    defer engine.freeValue(args);
    try normalize(engine, schema, args, validators);
    const ignored = try convertTypeBox(engine, schema, args, validators);
    defer engine.freeValue(ignored);
    return convertJsonSchema(engine, schema, args, validators);
}
test "native durable VM tool coercion distinguishes modern TypeBox values and plain schema conversions" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("typebox.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try vm.put(engine, global, "nativeConvert", try engine.checked(c.JS_NewCFunction(engine.context, testConvert, "nativeConvert", 2)));
    errdefer std.debug.print("Coercion VM failure: {s}\n", .{engine.last_error orelse "none"});
    const output = try engine.evalModule(
        \\import * as T from 'typebox';
        \\const plain={type:'object',properties:{n:{type:'number'},s:{type:'string'},b:{type:'boolean'},optional:{type:'number'}},required:['n','s','b']};
        \\const typed=T.Object({n:T.Number(),s:T.String(),b:T.Boolean(),optional:T.Optional(T.Number())});
        \\const input={n:'TRUE',s:null,b:'FALSE',optional:null};
        \\const results=[nativeConvert(plain,{n:'0x10',s:null,b:'true',optional:null}),nativeConvert(typed,input),input,nativeConvert({anyOf:[{type:'number',minimum:10},{type:'string',minLength:2}]},false),nativeConvert(T.Object({a:T.Array(T.Number())}),{a:['1','2']})];
        \\globalThis.result=JSON.stringify(results);
    , "native-tool-coercion-fixture");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "coercion-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("[{\"n\":16,\"s\":\"\",\"b\":true},{\"n\":1,\"s\":\"null\",\"b\":false},{\"n\":\"TRUE\",\"s\":null,\"b\":\"FALSE\",\"optional\":null},\"false\",{\"a\":[1,2]}]", text);
}

//! Private Node24 filesystem frontend validation. No public module installation.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const utf16 = @import("native_utf16.zig");
const c = js.c;
const Scope = h.Scope;

pub fn prepare(scope: *Scope) !c.JSValue {
    try @import("node_buffer.zig").install(scope.engine);
    const bindings = try scope.object();
    inline for (.{ "TypeError", "RangeError", "String", "BigInt", "Buffer" }) |name| try scope.put(bindings, name, try scope.global(name));
    return bindings;
}
pub fn isView(value: c.JSValue) bool {
    return c.JS_IsDataView(value) or c.JS_GetTypedArrayType(value) >= 0;
}
pub fn number(scope: *Scope, value: c.JSValue) !f64 {
    var result: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &result, value) < 0) return js.capture(scope.engine);
    return result;
}
pub fn binary(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
pub fn relation(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !bool {
    return scope.truthy(try binary(scope, operation, left, right));
}
fn coded(scope: *Scope, bindings: c.JSValue, kind: [*:0]const u8, code: []const u8, message: []const u8) !void {
    const engine = scope.engine;
    const constructor = try scope.get(bindings, kind);
    // Node's dynamic-message error subclass invokes super() without a message,
    // then initializes code before defining its non-enumerable message.
    const value = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    try scope.put(value, "code", try scope.text(code));
    if (c.JS_DefinePropertyValueStr(engine.context, value, "message", c.JS_DupValue(engine.context, try scope.text(message)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return h.throw(scope, value);
}
fn specific(scope: *Scope, bindings: c.JSValue, value: c.JSValue) ![]u8 {
    const engine = scope.engine;
    if (c.JS_IsNull(value)) return engine.gpa.dupe(u8, "null");
    if (c.JS_IsUndefined(value)) return engine.gpa.dupe(u8, "undefined");
    if (c.JS_IsString(value)) {
        const units = try utf16.unitsAlloc(engine, value);
        defer engine.gpa.free(units);
        const text_value = if (units.len > 28) try scope.concat(try scope.own(try utf16.string(engine, units[0..25])), try scope.text("...")) else value;
        const text = try engine.toString(text_value);
        defer engine.gpa.free(text);
        if (std.mem.indexOfScalar(u8, text, '\'') == null) return std.fmt.allocPrint(engine.gpa, "type string ('{s}')", .{text});
        const quoted = try scope.own(try engine.checked(c.JS_JSONStringify(engine.context, text_value, c.pi_js_undefined(), c.pi_js_undefined())));
        const json = try engine.toString(quoted);
        defer engine.gpa.free(json);
        return std.fmt.allocPrint(engine.gpa, "type string ({s})", .{json});
    }
    if (c.JS_IsNumber(value)) {
        const actual = try number(scope, value);
        const text = if (actual == 0 and std.math.signbit(actual)) try engine.gpa.dupe(u8, "-0") else try engine.toString(value);
        defer engine.gpa.free(text);
        return std.fmt.allocPrint(engine.gpa, "type number ({s})", .{text});
    }
    if (c.JS_IsBigInt(value)) {
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        return std.fmt.allocPrint(engine.gpa, "type bigint ({s}n)", .{text});
    }
    if (c.JS_IsBool(value)) return engine.gpa.dupe(u8, if (scope.truthy(value)) "type boolean (true)" else "type boolean (false)");
    if (c.JS_IsSymbol(value)) {
        const text_value = try scope.call(try scope.get(bindings, "String"), c.pi_js_undefined(), &.{value});
        const text = try engine.toString(text_value);
        defer engine.gpa.free(text);
        return std.fmt.allocPrint(engine.gpa, "type symbol ({s})", .{text});
    }
    if (c.JS_IsFunction(engine.context, value)) {
        const name = try engine.toString(try scope.get(value, "name"));
        defer engine.gpa.free(name);
        return std.fmt.allocPrint(engine.gpa, "function {s}", .{name});
    }
    if (scope.truthy(try scope.get(value, "constructor"))) {
        const constructor = try scope.get(value, "constructor");
        if (try js.hasKey(engine, constructor, try scope.text("name"))) {
            const name = try engine.toString(try scope.get(try scope.get(value, "constructor"), "name"));
            defer engine.gpa.free(name);
            return std.fmt.allocPrint(engine.gpa, "an instance of {s}", .{name});
        }
    }
    return @import("node_event_inspect.zig").inspect(engine, value, -1);
}
pub fn invalidType(scope: *Scope, bindings: c.JSValue, name: []const u8, expected: []const u8, value: c.JSValue) !void {
    const received = try specific(scope, bindings, value);
    defer scope.engine.gpa.free(received);
    const message = try std.fmt.allocPrint(scope.engine.gpa, "The \"{s}\" argument must be {s}. Received {s}", .{ name, expected, received });
    defer scope.engine.gpa.free(message);
    return coded(scope, bindings, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn separated(scope: *Scope, text: []const u8) ![]u8 {
    const start: usize = if (text.len > 0 and text[0] == '-') 1 else 0;
    const count = (text.len - start -| 1) / 3;
    const result = try scope.engine.gpa.alloc(u8, text.len + count);
    var out: usize = 0;
    for (text, 0..) |byte, index| {
        if (index > start and (text.len - index) % 3 == 0) {
            result[out] = '_';
            out += 1;
        }
        result[out] = byte;
        out += 1;
    }
    return result;
}
pub fn outOfRange(scope: *Scope, bindings: c.JSValue, name: []const u8, range: []const u8, value: c.JSValue) !void {
    const engine = scope.engine;
    const numeric = if (c.JS_IsNumber(value)) try number(scope, value) else 0;
    const large = if (c.JS_IsBigInt(value)) try relation(scope, 6, value, try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, 4294967296)))) or try relation(scope, 4, value, try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, -4294967296)))) else c.JS_IsNumber(value) and std.math.isFinite(numeric) and @trunc(numeric) == numeric and @abs(numeric) > 4294967296;
    const text = if (large or c.JS_IsBigInt(value)) try engine.toString(value) else try @import("node_event_inspect.zig").inspect(engine, value, 2);
    defer engine.gpa.free(text);
    const digits = if (large) try separated(scope, text) else try engine.gpa.dupe(u8, text);
    defer engine.gpa.free(digits);
    const received = if (c.JS_IsBigInt(value)) try std.fmt.allocPrint(engine.gpa, "{s}n", .{digits}) else try engine.gpa.dupe(u8, digits);
    defer engine.gpa.free(received);
    const message = try std.fmt.allocPrint(engine.gpa, "The value of \"{s}\" is out of range. It must be {s}. Received {s}", .{ name, range, received });
    defer engine.gpa.free(message);
    return coded(scope, bindings, "RangeError", "ERR_OUT_OF_RANGE", message);
}
pub fn integer(scope: *Scope, bindings: c.JSValue, value: c.JSValue, name: []const u8, minimum: i64, maximum: i64) !void {
    if (!c.JS_IsNumber(value)) return invalidType(scope, bindings, name, "of type number", value);
    const actual = try number(scope, value);
    if (!std.math.isFinite(actual) or @trunc(actual) != actual) return outOfRange(scope, bindings, name, "an integer", value);
    if (actual < @as(f64, @floatFromInt(minimum)) or actual > @as(f64, @floatFromInt(maximum))) {
        const range = try std.fmt.allocPrint(scope.engine.gpa, ">= {d} && <= {d}", .{ minimum, maximum });
        defer scope.engine.gpa.free(range);
        return outOfRange(scope, bindings, name, range, value);
    }
}
pub fn readPosition(scope: *Scope, bindings: c.JSValue, value: c.JSValue, length: c.JSValue) !void {
    if (c.JS_IsNumber(value)) return integer(scope, bindings, value, "position", -1, 9007199254740991);
    if (!c.JS_IsBigInt(value)) return invalidType(scope, bindings, "position", "of type bigint or integer", value);
    const engine = scope.engine;
    const big_constructor = try scope.get(bindings, "BigInt");
    const maximum = try binary(scope, 1, try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, std.math.maxInt(i64)))), try scope.call(big_constructor, c.pi_js_undefined(), &.{length}));
    if (!try relation(scope, 7, value, try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, -1)))) or !try relation(scope, 5, value, maximum)) {
        const maximum_text = try engine.toString(maximum);
        defer engine.gpa.free(maximum_text);
        const range = try std.fmt.allocPrint(engine.gpa, ">= -1 && <= {s}", .{maximum_text});
        defer engine.gpa.free(range);
        return outOfRange(scope, bindings, "position", range, value);
    }
}
pub fn bufferArray(scope: *Scope, bindings: c.JSValue, buffers: c.JSValue) !void {
    if (!c.JS_IsArray(buffers)) return invalidType(scope, bindings, "buffers", "an ArrayBufferView[]", buffers);
    var index: u32 = 0;
    while (try relation(scope, 4, c.JS_NewFloat64(scope.engine.context, @floatFromInt(index)), try scope.get(buffers, "length"))) : (index += 1) {
        const item = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, buffers, index)));
        if (!isView(item)) return invalidType(scope, bindings, "buffers", "an ArrayBufferView[]", buffers);
    }
}

// Node's empty-view diagnostic includes intrinsic DataView/ArrayBuffer spans.
// This private formatter is kept separate from public util.inspect installation.
pub fn emptyRead(scope: *Scope, bindings: c.JSValue, buffer: c.JSValue) !void {
    const engine = scope.engine;
    const inspected = if (c.JS_IsDataView(buffer)) data_view: {
        var offset: usize = undefined;
        var length: usize = undefined;
        const backing = try scope.own(try engine.checked(c.JS_PiGetArrayBufferViewBuffer(engine.context, buffer, &offset, &length, null)));
        var total: usize = undefined;
        const bytes = c.JS_GetArrayBuffer(engine.context, &total, backing);
        if (c.JS_HasException(engine.context)) return js.capture(engine);
        var content: std.ArrayList(u8) = .empty;
        defer content.deinit(engine.gpa);
        for (0..@min(total, 100)) |index| {
            if (index != 0) try content.append(engine.gpa, ' ');
            const hex = "0123456789abcdef";
            const pair = [_]u8{ hex[bytes[index] >> 4], hex[bytes[index] & 15] };
            try content.appendSlice(engine.gpa, &pair);
        }
        break :data_view try std.fmt.allocPrint(engine.gpa, "DataView {{\n  [byteLength]: {d},\n  [byteOffset]: {d},\n  [buffer]: ArrayBuffer {{ [Uint8Contents]: <{s}>, [byteLength]: {d} }}\n}}", .{ length, offset, content.items, total });
    } else try @import("node_event_inspect.zig").inspect(engine, buffer, 2);
    defer engine.gpa.free(inspected);
    return invalidValueInspected(scope, bindings, "buffer", "is empty and cannot be written", inspected);
}
fn invalidValueInspected(scope: *Scope, bindings: c.JSValue, name: []const u8, reason: []const u8, inspected: []const u8) !void {
    const engine = scope.engine;
    const units = try utf16.unitsAlloc(engine, try scope.text(inspected));
    defer engine.gpa.free(units);
    const shown_value = if (units.len > 128) try scope.concat(try scope.own(try utf16.string(engine, units[0..128])), try scope.text("...")) else try scope.text(inspected);
    const shown = try engine.toString(shown_value);
    defer engine.gpa.free(shown);
    const message = try std.fmt.allocPrint(engine.gpa, "The argument '{s}' {s}. Received {s}", .{ name, reason, shown });
    defer engine.gpa.free(message);
    return coded(scope, bindings, "TypeError", "ERR_INVALID_ARG_VALUE", message);
}
pub fn invalidValue(scope: *Scope, bindings: c.JSValue, name: []const u8, reason: []const u8, value: c.JSValue) !void {
    const inspected = try @import("node_event_inspect.zig").inspect(scope.engine, value, 2);
    defer scope.engine.gpa.free(inspected);
    return invalidValueInspected(scope, bindings, name, reason, inspected);
}

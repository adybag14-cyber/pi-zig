//! Private Node event diagnostic formatting. No evaluated host implementation.
const std = @import("std");
const js = @import("native_js_values.zig");
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const c = js.c;
const Frame = struct { value: c.JSValue, reference: ?u32 = null };
const Inspector = struct {
    engine: *js.Engine,
    stack: std.ArrayList(Frame) = .empty,
    next_reference: u32 = 1,
    steps: usize = 0,
    fn alloc(self: *Inspector, comptime pattern: []const u8, args: anytype) ![]u8 {
        return std.fmt.allocPrint(self.engine.gpa, pattern, args);
    }
    fn name(self: *Inspector, value: c.JSValue) ![]u8 {
        const engine = self.engine;
        var object = c.JS_DupValue(engine.context, value);
        defer engine.freeValue(object);
        const atom = c.JS_NewAtom(engine.context, "constructor");
        defer c.JS_FreeAtom(engine.context, atom);
        for (0..64) |_| {
            var descriptor: c.JSPropertyDescriptor = undefined;
            const present = c.JS_GetOwnProperty(engine.context, &descriptor, object, atom);
            if (present < 0) return js.capture(engine);
            if (present != 0) {
                defer engine.freeValue(descriptor.value);
                defer engine.freeValue(descriptor.getter);
                defer engine.freeValue(descriptor.setter);
                if (c.JS_IsFunction(engine.context, descriptor.value)) {
                    const text = try js.get(engine, descriptor.value, "name");
                    defer engine.freeValue(text);
                    if (c.JS_IsString(text)) return engine.toString(text);
                }
            }
            const prototype = try engine.checked(c.JS_GetPrototype(engine.context, object));
            engine.freeValue(object);
            object = prototype;
            if (c.JS_IsNull(object)) return engine.gpa.dupe(u8, "Object: null prototype");
        }
        return js.typeError(engine, "Native event inspection prototype limit exceeded");
    }
    fn quote(self: *Inspector, value: c.JSValue) ![]u8 {
        const engine = self.engine;
        const units = try utf16.unitsAlloc(engine, value);
        defer engine.gpa.free(units);
        var has_single = false;
        var has_double = false;
        var has_backtick = false;
        for (units) |unit| switch (unit) {
            '\'' => has_single = true,
            '"' => has_double = true,
            '`', '$' => has_backtick = true,
            else => {},
        };
        const delimiter: u8 = if (!has_single) '\'' else if (!has_double) '"' else if (!has_backtick) '`' else '\'';
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(engine.gpa);
        try output.append(engine.gpa, delimiter);
        var index: usize = 0;
        while (index < units.len) : (index += 1) {
            const unit = units[index];
            if (unit == delimiter or unit == '\\') {
                try output.appendSlice(engine.gpa, &.{ '\\', @intCast(unit) });
            } else if (unit == '\n') try output.appendSlice(engine.gpa, "\\n") else if (unit == '\r') try output.appendSlice(engine.gpa, "\\r") else if (unit == '\t') try output.appendSlice(engine.gpa, "\\t") else if (unit == 8) try output.appendSlice(engine.gpa, "\\b") else if (unit == 12) try output.appendSlice(engine.gpa, "\\f") else if (unit == 11) try output.appendSlice(engine.gpa, "\\v") else if (unit < 32 or unit == 127) {
                const escaped = try self.alloc("\\x{x:0>2}", .{unit});
                defer engine.gpa.free(escaped);
                try output.appendSlice(engine.gpa, escaped);
            } else if (unit >= 0xd800 and unit <= 0xdfff) {
                if (unit <= 0xdbff and index + 1 < units.len and units[index + 1] >= 0xdc00 and units[index + 1] <= 0xdfff) {
                    const point: u21 = @intCast(0x10000 + (@as(u32, unit) - 0xd800) * 0x400 + @as(u32, units[index + 1]) - 0xdc00);
                    var encoded: [4]u8 = undefined;
                    const length = try std.unicode.utf8Encode(point, &encoded);
                    try output.appendSlice(engine.gpa, encoded[0..length]);
                    index += 1;
                } else {
                    const escaped = try self.alloc("\\u{x:0>4}", .{unit});
                    defer engine.gpa.free(escaped);
                    try output.appendSlice(engine.gpa, escaped);
                }
            } else {
                var encoded: [4]u8 = undefined;
                const length = try std.unicode.utf8Encode(@intCast(unit), &encoded);
                try output.appendSlice(engine.gpa, encoded[0..length]);
            }
        }
        try output.append(engine.gpa, delimiter);
        return output.toOwnedSlice(engine.gpa);
    }
    fn format(self: *Inspector, value: c.JSValue, depth: i32) anyerror![]u8 {
        const engine = self.engine;
        self.steps += 1;
        if (self.steps > 4096 or self.stack.items.len >= 64) return js.typeError(engine, "Native event inspection limit exceeded");
        if (c.JS_IsString(value)) return self.quote(value);
        if (c.JS_IsSymbol(value)) {
            const string = try js.global(engine, "String");
            defer engine.freeValue(string);
            const result = try js.call(engine, string, c.pi_js_undefined(), &.{value});
            defer engine.freeValue(result);
            return engine.toString(result);
        }
        if (!c.JS_IsObject(value)) {
            if (c.JS_IsNumber(value)) {
                const number = try v.number(engine, value);
                if (number == 0 and std.math.signbit(number)) return engine.gpa.dupe(u8, "-0");
            }
            const text = try engine.toString(value);
            if (c.JS_IsBigInt(value)) {
                defer engine.gpa.free(text);
                return self.alloc("{s}n", .{text});
            }
            return text;
        }
        const symbol = try js.global(engine, "Symbol");
        defer engine.freeValue(symbol);
        const custom_name = try v.text(engine, "nodejs.util.inspect.custom");
        defer engine.freeValue(custom_name);
        const custom_key = try js.invoke(engine, symbol, "for", &.{custom_name});
        defer engine.freeValue(custom_key);
        const custom = try js.getKey(engine, value, custom_key);
        defer engine.freeValue(custom);
        if (c.JS_IsFunction(engine.context, custom)) {
            const options = try js.object(engine);
            defer engine.freeValue(options);
            try js.define(engine, options, "depth", c.JS_NewInt32(engine.context, depth));
            inline for (.{ "showHidden", "colors", "showProxy", "sorted", "getters", "numericSeparator" }) |key| try js.define(engine, options, key, c.pi_js_bool(engine.context, 0));
            try js.define(engine, options, "customInspect", c.pi_js_bool(engine.context, 1));
            try js.define(engine, options, "maxArrayLength", c.JS_NewInt32(engine.context, 100));
            try js.define(engine, options, "maxStringLength", c.JS_NewInt32(engine.context, 10000));
            try js.define(engine, options, "breakLength", c.JS_NewInt32(engine.context, 80));
            try js.define(engine, options, "compact", c.JS_NewInt32(engine.context, 3));
            const inspect_function = try engine.checked(c.JS_NewCFunction(engine.context, inspectCall, "inspect", 2));
            defer engine.freeValue(inspect_function);
            const result = try js.call(engine, custom, value, &.{ c.JS_NewInt32(engine.context, depth), options, inspect_function });
            defer engine.freeValue(result);
            if (!c.JS_IsStrictEqual(engine.context, result, value)) return if (c.JS_IsString(result)) engine.toString(result) else self.format(result, depth);
        }
        for (self.stack.items) |*frame| if (c.JS_IsStrictEqual(engine.context, value, frame.value)) {
            if (frame.reference == null) {
                frame.reference = self.next_reference;
                self.next_reference += 1;
            }
            return self.alloc("[Circular *{d}]", .{frame.reference.?});
        };
        const class_name = try self.name(value);
        defer engine.gpa.free(class_name);
        if (depth < 0) return self.alloc("[{s}]", .{class_name});
        if (c.JS_IsRegExp(value)) {
            const prototype = try js.get(engine, engine.intrinsic_regexp_constructor, "prototype");
            defer engine.freeValue(prototype);
            const function = try js.get(engine, prototype, "toString");
            defer engine.freeValue(function);
            const result = try js.call(engine, function, value, &.{});
            defer engine.freeValue(result);
            return engine.toString(result);
        }
        if (c.JS_IsDate(value)) {
            const date = try js.global(engine, "Date");
            defer engine.freeValue(date);
            const prototype = try js.get(engine, date, "prototype");
            defer engine.freeValue(prototype);
            const function = try js.get(engine, prototype, "toISOString");
            defer engine.freeValue(function);
            const result = try js.call(engine, function, value, &.{});
            defer engine.freeValue(result);
            return engine.toString(result);
        }
        const frame_index = self.stack.items.len;
        try self.stack.append(engine.gpa, .{ .value = value });
        defer _ = self.stack.pop();
        var parts: std.ArrayList([]u8) = .empty;
        defer {
            for (parts.items) |part| engine.gpa.free(part);
            parts.deinit(engine.gpa);
        }
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, value, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(engine);
        defer c.JS_FreePropertyEnum(engine.context, names, count);
        if (count > 4096) return js.typeError(engine, "Native event inspection property limit exceeded");
        const array = c.JS_IsArray(value);
        for (names[0..count]) |entry| {
            var descriptor: c.JSPropertyDescriptor = undefined;
            const present = c.JS_GetOwnProperty(engine.context, &descriptor, value, entry.atom);
            if (present < 0) return js.capture(engine);
            if (present == 0) continue;
            defer engine.freeValue(descriptor.value);
            defer engine.freeValue(descriptor.getter);
            defer engine.freeValue(descriptor.setter);
            const key = try engine.checked(c.JS_AtomToValue(engine.context, entry.atom));
            defer engine.freeValue(key);
            const key_text = if (c.JS_IsSymbol(key)) try self.format(key, depth) else try engine.toString(key);
            defer engine.gpa.free(key_text);
            const formatted = if (!c.JS_IsUndefined(descriptor.getter) or !c.JS_IsUndefined(descriptor.setter)) try engine.gpa.dupe(u8, if (!c.JS_IsUndefined(descriptor.getter) and !c.JS_IsUndefined(descriptor.setter)) "[Getter/Setter]" else if (!c.JS_IsUndefined(descriptor.getter)) "[Getter]" else "[Setter]") else try self.format(descriptor.value, depth - 1);
            defer engine.gpa.free(formatted);
            const numeric_key = std.fmt.parseInt(u32, key_text, 10) catch null;
            const part = if (array and numeric_key != null) try engine.gpa.dupe(u8, formatted) else blk: {
                const simple = key_text.len > 0 and (std.ascii.isAlphabetic(key_text[0]) or key_text[0] == '_' or key_text[0] == '$') and for (key_text) |char| {
                    if (!std.ascii.isAlphanumeric(char) and char != '_' and char != '$') break false;
                } else true;
                const property_name = if (c.JS_IsSymbol(key)) try self.alloc("[{s}]", .{key_text}) else if (simple) try engine.gpa.dupe(u8, key_text) else try self.quote(key);
                defer engine.gpa.free(property_name);
                break :blk try self.alloc("{s}: {s}", .{ property_name, formatted });
            };
            errdefer engine.gpa.free(part);
            try parts.append(engine.gpa, part);
        }
        const joined = try std.mem.join(engine.gpa, ", ", parts.items);
        defer engine.gpa.free(joined);
        const prefix = if (array or std.mem.eql(u8, class_name, "Object")) try engine.gpa.dupe(u8, "") else if (c.JS_IsFunction(engine.context, value)) blk: {
            const function_name = try js.get(engine, value, "name");
            defer engine.freeValue(function_name);
            const text = try engine.toString(function_name);
            defer engine.gpa.free(text);
            break :blk try self.alloc("[Function: {s}]", .{text});
        } else if (std.mem.eql(u8, class_name, "Object: null prototype")) try engine.gpa.dupe(u8, "[Object: null prototype] ") else try self.alloc("{s} ", .{class_name});
        defer engine.gpa.free(prefix);
        const body = if (c.JS_IsFunction(engine.context, value) and parts.items.len == 0) try engine.gpa.dupe(u8, prefix) else if (parts.items.len == 0) try self.alloc("{s}{s}", .{ prefix, if (array) "[]" else "{}" }) else try self.alloc("{s}{s} {s} {s}", .{ prefix, if (array) "[" else "{", joined, if (array) "]" else "}" });
        if (self.stack.items[frame_index].reference) |reference| {
            defer engine.gpa.free(body);
            return self.alloc("<ref *{d}> {s}", .{ reference, body });
        }
        return body;
    }
};
pub fn inspect(engine: *js.Engine, value: c.JSValue, depth: i32) ![]u8 {
    var inspector: Inspector = .{ .engine = engine };
    defer inspector.stack.deinit(engine.gpa);
    return inspector.format(value, depth);
}
fn inspectCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    const text = inspect(engine, value, 2) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
    defer engine.gpa.free(text);
    return c.JS_NewStringLen(context, text.ptr, text.len);
}

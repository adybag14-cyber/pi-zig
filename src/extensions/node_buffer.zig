//! Buffer values are native Uint8Array views with Zig host operations.
const std = @import("std");
const engine_mod = @import("engine.zig");
pub const encodings = @import("binary_encoding.zig");
const c = engine_mod.c;
const Static = enum(c_int) { from, alloc, allocUnsafe, allocUnsafeSlow, byteLength, isBuffer, isEncoding, concat, compare };
const Method = enum(c_int) {
    toString,
    toJSON,
    slice,
    subarray,
    equals,
    compare,
    copy,
    fill,
    readUInt8,
    readUInt16LE,
    readUInt16BE,
    readUInt32LE,
    readUInt32BE,
    readUIntLE,
    readUIntBE,
    readInt8,
    readInt16LE,
    readInt16BE,
    readInt32LE,
    readInt32BE,
    readIntLE,
    readIntBE,
    readBigUInt64LE,
    readBigUInt64BE,
    readBigInt64LE,
    readBigInt64BE,
    readFloatLE,
    readFloatBE,
    readDoubleLE,
    readDoubleBE,
    writeUInt8,
    writeUInt16LE,
    writeUInt16BE,
    writeUInt32LE,
    writeUInt32BE,
    writeUIntLE,
    writeUIntBE,
    writeInt8,
    writeInt16LE,
    writeInt16BE,
    writeInt32LE,
    writeInt32BE,
    writeIntLE,
    writeIntBE,
    writeBigUInt64LE,
    writeBigUInt64BE,
    writeBigInt64LE,
    writeBigInt64BE,
    writeFloatLE,
    writeFloatBE,
    writeDoubleLE,
    writeDoubleBE,
    swap16,
    swap32,
    swap64,
};

const View = struct { backing: c.JSValue, bytes: []u8, offset: usize };

fn view(engine: *engine_mod.Engine, value: c.JSValue) !View {
    if (c.JS_GetTypedArrayType(value) != c.JS_TYPED_ARRAY_UINT8) return error.InvalidBufferArgument;
    var offset: usize = 0;
    var length: usize = 0;
    var element_size: usize = 0;
    const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element_size));
    errdefer engine.freeValue(backing);
    var total: usize = 0;
    const bytes = c.JS_GetArrayBuffer(engine.context, &total, backing);
    if (c.JS_HasException(engine.context) or offset > total or length > total - offset or (bytes == null and length > 0)) return error.InvalidBufferArgument;
    return .{ .backing = backing, .bytes = if (length == 0) &.{} else bytes[offset .. offset + length], .offset = offset };
}

fn property(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

fn checkedLength(engine: *engine_mod.Engine, value: c.JSValue) !usize {
    if (!c.JS_IsNumber(value)) return error.InvalidBufferArgument;
    var size: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &size, value) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(size) or size < 0 or size > @as(f64, @floatFromInt(engine.options.memory_limit))) return error.BufferRange;
    return @intFromFloat(@trunc(size));
}

fn encoding(engine: *engine_mod.Engine, value: c.JSValue, permissive: bool) !encodings.Encoding {
    if (c.JS_IsUndefined(value) or (permissive and !c.JS_IsString(value))) return .utf8;
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    if (permissive and text.len == 0) return .utf8;
    return encodings.parse(text) orelse error.UnknownBufferEncoding;
}

pub fn fromBytes(engine: *engine_mod.Engine, bytes: []const u8) !c.JSValue {
    if (bytes.len > engine.options.memory_limit) return error.BufferRange;
    const backing = try engine.checked(c.JS_NewArrayBufferCopy(engine.context, bytes.ptr, bytes.len));
    defer engine.freeValue(backing);
    return fromBacking(engine, backing, 0, bytes.len);
}

fn fromBacking(engine: *engine_mod.Engine, backing: c.JSValue, offset: usize, size: usize) !c.JSValue {
    const prototype = engine.buffer_prototype orelse return error.NativeBufferUnavailable;
    var args = [_]c.JSValue{ backing, c.JS_NewInt64(engine.context, @intCast(offset)), c.JS_NewInt64(engine.context, @intCast(size)) };
    defer engine.freeValue(args[1]);
    defer engine.freeValue(args[2]);
    const value = try engine.checked(c.JS_NewTypedArray(engine.context, args.len, &args, c.JS_TYPED_ARRAY_UINT8));
    errdefer engine.freeValue(value);
    if (c.JS_SetPrototype(engine.context, value, prototype) < 0) return error.JavaScriptException;
    return value;
}

fn arrayFrom(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const count_value = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "length"));
    defer engine.freeValue(count_value);
    if (!c.JS_IsNumber(count_value)) return fromBytes(engine, &.{});
    var count_number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &count_number, count_value) < 0) return error.JavaScriptException;
    const count = if (std.math.isNan(count_number) or count_number < 0) 0 else try checkedLength(engine, count_value);
    const bytes = try engine.gpa.alloc(u8, count);
    defer engine.gpa.free(bytes);
    for (bytes, 0..) |*byte, index| {
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
        defer engine.freeValue(item);
        var number: i32 = 0;
        if (c.JS_ToInt32(engine.context, &number, item) < 0) return error.JavaScriptException;
        byte.* = @truncate(@as(u32, @bitCast(number)));
    }
    return fromBytes(engine, bytes);
}

fn from(engine: *engine_mod.Engine, args: []c.JSValue, depth: usize) anyerror!c.JSValue {
    if (args.len == 0 or depth > 16) return error.InvalidBufferArgument;
    if (c.JS_IsString(args[0])) {
        const text = try engine.toString(args[0]);
        defer engine.gpa.free(text);
        const codec = try encoding(engine, if (args.len > 1) args[1] else c.pi_js_undefined(), true);
        const bytes = try encodings.encode(engine.gpa, text, codec);
        defer engine.gpa.free(bytes);
        return fromBytes(engine, bytes);
    }
    if (c.JS_IsArrayBuffer(args[0])) {
        var size: usize = 0;
        _ = c.JS_GetArrayBuffer(engine.context, &size, args[0]);
        if (c.JS_HasException(engine.context)) return error.InvalidBufferArgument;
        const offset = if (args.len > 1 and !c.JS_IsUndefined(args[1])) try checkedLength(engine, args[1]) else 0;
        if (offset > size) return error.BufferRange;
        const count = if (args.len > 2 and !c.JS_IsUndefined(args[2])) try checkedLength(engine, args[2]) else size - offset;
        if (count > size - offset) return error.BufferRange;
        return fromBacking(engine, args[0], offset, count);
    }
    if (!c.JS_IsObject(args[0])) return error.InvalidBufferArgument;
    if (c.JS_GetTypedArrayType(args[0]) == c.JS_TYPED_ARRAY_UINT8) {
        const source = try view(engine, args[0]);
        defer engine.freeValue(source.backing);
        return fromBytes(engine, source.bytes);
    }
    if (c.JS_IsArray(args[0]) or c.JS_GetTypedArrayType(args[0]) >= 0 or c.JS_IsDataView(args[0])) return arrayFrom(engine, args[0]);
    const value_of = try engine.checked(c.JS_GetPropertyStr(engine.context, args[0], "valueOf"));
    defer engine.freeValue(value_of);
    if (c.JS_IsFunction(engine.context, value_of)) {
        const value = try engine.checked(c.JS_Call(engine.context, value_of, args[0], 0, null));
        defer engine.freeValue(value);
        if (!c.JS_IsStrictEqual(engine.context, value, args[0])) {
            var arguments = [_]c.JSValue{ value, if (args.len > 1) args[1] else c.pi_js_undefined(), if (args.len > 2) args[2] else c.pi_js_undefined() };
            return from(engine, &arguments, depth + 1);
        }
    }
    const type_value = try engine.checked(c.JS_GetPropertyStr(engine.context, args[0], "type"));
    defer engine.freeValue(type_value);
    if (c.JS_IsString(type_value)) {
        const type_name = try engine.toString(type_value);
        defer engine.gpa.free(type_name);
        if (std.mem.eql(u8, type_name, "Buffer")) {
            const data = try engine.checked(c.JS_GetPropertyStr(engine.context, args[0], "data"));
            defer engine.freeValue(data);
            if (c.JS_IsArray(data)) return arrayFrom(engine, data);
        }
    }
    const count = try engine.checked(c.JS_GetPropertyStr(engine.context, args[0], "length"));
    defer engine.freeValue(count);
    if (!c.JS_IsUndefined(count)) return arrayFrom(engine, args[0]);
    return error.InvalidBufferArgument;
}

fn failure(context: ?*c.JSContext, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine_mod.Engine.fromContext(context.?).throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
    if (err == error.MixingBigIntTypes) return c.JS_ThrowTypeError(context, "Cannot mix BigInt and other types");
    const range = err == error.BufferRange or err == error.BufferBounds or err == error.InvalidBufferSize;
    const code: [*:0]const u8 = if (err == error.BufferRange) "ERR_OUT_OF_RANGE" else if (err == error.BufferBounds) "ERR_BUFFER_OUT_OF_BOUNDS" else if (err == error.InvalidBufferSize) "ERR_INVALID_BUFFER_SIZE" else if (err == error.UnknownBufferEncoding) "ERR_UNKNOWN_ENCODING" else "ERR_INVALID_ARG_TYPE";
    _ = if (range) c.JS_ThrowRangeError(context, "Native Buffer: %s", @as([*:0]const u8, @errorName(err))) else c.JS_ThrowTypeError(context, "Native Buffer: %s", @as([*:0]const u8, @errorName(err)));
    const exception = c.JS_GetException(context);
    if (c.JS_DefinePropertyValueStr(context, exception, "code", c.JS_NewString(context, code), c.JS_PROP_C_W_E) < 0) {
        c.JS_FreeValue(context, exception);
        return c.JS_Throw(context, c.JS_GetException(context));
    }
    return c.JS_Throw(context, exception);
}

fn construct(context: ?*c.JSContext, new_target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const args = argv[0..@intCast(argc)];
    if (args.len > 1 and c.JS_IsNumber(args[0]) and c.JS_IsString(args[1])) return failure(context, error.InvalidBufferArgument);
    const result = (if (args.len > 0 and c.JS_IsNumber(args[0])) staticCall(engine, .allocUnsafe, args) else from(engine, args, 0)) catch |err| return failure(context, err);
    if (!c.JS_IsUndefined(new_target)) {
        const prototype = c.JS_GetPropertyStr(context, new_target, "prototype");
        if (c.JS_IsException(prototype)) {
            engine.freeValue(result);
            return prototype;
        }
        defer engine.freeValue(prototype);
        if (c.JS_IsObject(prototype) and c.JS_SetPrototype(context, result, prototype) < 0) {
            engine.freeValue(result);
            return c.JS_Throw(context, c.JS_GetException(context));
        }
    }
    return result;
}

fn invokeStatic(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return staticCall(engine, @enumFromInt(magic), argv[0..@intCast(argc)]) catch |err| failure(context, err);
}

fn invokeMethod(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return methodCall(engine, @enumFromInt(magic), this, argv[0..@intCast(argc)]) catch |err| failure(context, err);
}

fn isBuffer(engine: *engine_mod.Engine, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value)) return false;
    const prototype = engine.buffer_prototype orelse return false;
    var current = c.JS_DupValue(engine.context, value);
    defer engine.freeValue(current);
    for (0..128) |_| {
        const next = try engine.checked(c.JS_GetPrototype(engine.context, current));
        engine.freeValue(current);
        current = next;
        if (c.JS_IsStrictEqual(engine.context, current, prototype)) return true;
        if (c.JS_IsNull(current)) return false;
    }
    return error.InvalidBufferArgument;
}

fn staticCall(engine: *engine_mod.Engine, method: Static, args: []c.JSValue) anyerror!c.JSValue {
    if (method == .isBuffer) return c.pi_js_bool(engine.context, @intFromBool(args.len > 0 and try isBuffer(engine, args[0])));
    if (method == .isEncoding) {
        if (args.len == 0 or !c.JS_IsString(args[0])) return c.pi_js_bool(engine.context, 0);
        const name = try engine.toString(args[0]);
        defer engine.gpa.free(name);
        return c.pi_js_bool(engine.context, @intFromBool(encodings.parse(name) != null));
    }
    if (args.len == 0) return error.InvalidBufferArgument;
    switch (method) {
        .from => return from(engine, args, 0),
        .alloc, .allocUnsafe, .allocUnsafeSlow => {
            const size = try checkedLength(engine, args[0]);
            const bytes = try engine.gpa.alloc(u8, size);
            defer engine.gpa.free(bytes);
            @memset(bytes, 0);
            const buffer = try fromBytes(engine, bytes);
            errdefer engine.freeValue(buffer);
            if (method == .alloc and args.len > 1 and size > 0 and !c.JS_IsUndefined(args[1])) {
                var fill_args = [_]c.JSValue{ args[1], c.JS_NewInt32(engine.context, 0), c.JS_NewInt64(engine.context, @intCast(size)), if (args.len > 2) args[2] else c.pi_js_undefined() };
                defer engine.freeValue(fill_args[1]);
                defer engine.freeValue(fill_args[2]);
                const result = try methodCall(engine, .fill, buffer, &fill_args);
                engine.freeValue(result);
            }
            return buffer;
        },
        .byteLength => {
            var size: usize = 0;
            if (c.JS_IsString(args[0])) {
                const text = try engine.toString(args[0]);
                defer engine.gpa.free(text);
                const codec = encoding(engine, if (args.len > 1) args[1] else c.pi_js_undefined(), true) catch |err| switch (err) {
                    error.UnknownBufferEncoding => encodings.Encoding.utf8,
                    else => return err,
                };
                if (codec == .hex) {
                    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
                    var units: usize = 0;
                    while (iterator.nextCodepoint()) |point| units += if (point > 0xffff) @as(usize, 2) else 1;
                    size = units / 2;
                } else {
                    const bytes = try encodings.encode(engine.gpa, text, codec);
                    defer engine.gpa.free(bytes);
                    size = bytes.len;
                }
            } else if (c.JS_IsArrayBuffer(args[0])) {
                _ = c.JS_GetArrayBuffer(engine.context, &size, args[0]);
                if (c.JS_HasException(engine.context)) return error.InvalidBufferArgument;
            } else if (c.JS_IsDataView(args[0])) {
                const byte_length = try engine.checked(c.JS_GetPropertyStr(engine.context, args[0], "byteLength"));
                defer engine.freeValue(byte_length);
                size = try checkedLength(engine, byte_length);
            } else {
                var offset: usize = 0;
                var element: usize = 0;
                const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, args[0], &offset, &size, &element));
                engine.freeValue(backing);
            }
            return engine.checked(c.JS_NewInt64(engine.context, @intCast(size)));
        },
        .compare => {
            if (args.len < 2) return error.InvalidBufferArgument;
            const left = try view(engine, args[0]);
            defer engine.freeValue(left.backing);
            const right = try view(engine, args[1]);
            defer engine.freeValue(right.backing);
            return c.pi_js_int32(engine.context, switch (std.mem.order(u8, left.bytes, right.bytes)) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            });
        },
        .concat => {
            if (!c.JS_IsArray(args[0])) return error.InvalidBufferArgument;
            const count_value = try engine.checked(c.JS_GetPropertyStr(engine.context, args[0], "length"));
            defer engine.freeValue(count_value);
            var count: u32 = 0;
            if (c.JS_ToUint32(engine.context, &count, count_value) < 0) return error.JavaScriptException;
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(engine.gpa);
            const total = if (args.len > 1 and !c.JS_IsUndefined(args[1])) try checkedLength(engine, args[1]) else null;
            for (0..count) |index| {
                const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, args[0], @intCast(index)));
                defer engine.freeValue(item);
                const span = try view(engine, item);
                defer engine.freeValue(span.backing);
                const wanted = if (total) |limit| @min(span.bytes.len, limit - @min(limit, bytes.items.len)) else span.bytes.len;
                if (wanted > engine.options.memory_limit - bytes.items.len) return error.BufferRange;
                try bytes.appendSlice(engine.gpa, span.bytes[0..wanted]);
            }
            if (total) |limit| {
                const previous = bytes.items.len;
                try bytes.resize(engine.gpa, limit);
                @memset(bytes.items[previous..], 0);
            }
            return fromBytes(engine, bytes.items);
        },
        else => unreachable,
    }
}

fn argumentIndex(engine: *engine_mod.Engine, args: []c.JSValue, position: usize, size: usize, default: usize, relative: bool) !usize {
    if (position >= args.len or c.JS_IsUndefined(args[position])) return default;
    var value: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &value, args[position]) < 0) return error.JavaScriptException;
    if (std.math.isNan(value)) return 0;
    if (value < 0) return if (relative) @intFromFloat(@max(0, @as(f64, @floatFromInt(size)) + @trunc(value))) else 0;
    return @intFromFloat(@min(@as(f64, @floatFromInt(size)), @trunc(value)));
}

fn numericArgument(engine: *engine_mod.Engine, args: []c.JSValue, index: usize, default: ?f64) !f64 {
    if (index >= args.len or c.JS_IsUndefined(args[index])) return default orelse error.InvalidBufferArgument;
    if (!c.JS_IsNumber(args[index])) return error.InvalidBufferArgument;
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, args[index]) < 0) return error.JavaScriptException;
    return number;
}

fn numericView(engine: *engine_mod.Engine, value: c.JSValue) !View {
    return view(engine, value) catch |err| {
        // QuickJS rejects detached/OOB views through its intrinsic accessor;
        // Node's numeric methods report buffer bounds. No user accessor runs here.
        if (err == error.JavaScriptException and c.JS_GetTypedArrayType(value) == c.JS_TYPED_ARRAY_UINT8) {
            if (engine.captured_exception) |exception| {
                if (!c.JS_IsUncatchableError(exception)) {
                    engine.freeValue(exception);
                    engine.captured_exception = null;
                    return error.BufferBounds;
                }
            }
        }
        return err;
    };
}

// The BigInt writers in Node's internal/buffer use the original value in four
// separate expressions: > max, < min, & lowMask, and >> 32n. In particular,
// coercion is observable, and the first word is written before coercing the
// second. Keep the intrinsic symbol in C function data instead of consulting
// the mutable global Symbol constructor during each conversion.
fn numberPrimitive(engine: *engine_mod.Engine, value: c.JSValue, symbol: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    const exotic = try engine.checked(c.JS_GetProperty(engine.context, value, atom));
    defer engine.freeValue(exotic);
    if (!c.JS_IsUndefined(exotic) and !c.JS_IsNull(exotic)) {
        var arguments = [_]c.JSValue{try engine.checked(c.JS_NewString(engine.context, "number"))};
        defer engine.freeValue(arguments[0]);
        const primitive = try engine.checked(c.JS_Call(engine.context, exotic, value, 1, &arguments));
        if (!c.JS_IsObject(primitive)) return primitive;
        engine.freeValue(primitive);
        _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot convert object to primitive value"));
        unreachable;
    }
    for ([_][*:0]const u8{ "valueOf", "toString" }) |name| {
        const converter = try engine.checked(c.JS_GetPropertyStr(engine.context, value, name));
        defer engine.freeValue(converter);
        if (!c.JS_IsFunction(engine.context, converter)) continue;
        const primitive = try engine.checked(c.JS_Call(engine.context, converter, value, 0, null));
        if (!c.JS_IsObject(primitive)) return primitive;
        engine.freeValue(primitive);
    }
    _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot convert object to primitive value"));
    unreachable;
}

const ComparedInteger = struct { negative: bool = false, magnitude: u64 = 0, overflow: bool = false };

fn bigintWhitespace(point: u21) bool {
    return switch (point) {
        0x0009...0x000d, 0x0020, 0x00a0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}

// StringToBigInt in relational comparisons returns an undefined comparison
// for invalid syntax; it does not use Number(string) or throw SyntaxError.
// Only the sign and whether the magnitude exceeds u64 are needed here. Still
// scan every digit after overflow so an invalid suffix remains incomparable.
fn comparedInteger(text: []const u8) ?ComparedInteger {
    var iterator = (std.unicode.Wtf8View.init(text) catch return null).iterator();
    var begin: usize = text.len;
    var end: usize = 0;
    var previous: usize = 0;
    while (iterator.nextCodepoint()) |point| {
        if (!bigintWhitespace(point)) {
            begin = @min(begin, previous);
            end = iterator.i;
        }
        previous = iterator.i;
    }
    if (end == 0) return .{};
    var digits = text[begin..end];
    var result: ComparedInteger = .{};
    var has_sign = false;
    if (digits[0] == '+' or digits[0] == '-') {
        has_sign = true;
        result.negative = digits[0] == '-';
        digits = digits[1..];
        if (digits.len == 0) return null;
    }
    var base: u64 = 10;
    if (digits.len >= 2 and digits[0] == '0') {
        base = switch (digits[1]) {
            'x', 'X' => 16,
            'o', 'O' => 8,
            'b', 'B' => 2,
            else => 10,
        };
        if (base != 10) {
            if (has_sign) return null;
            digits = digits[2..];
            if (digits.len == 0) return null;
        }
    }
    for (digits) |byte| {
        const digit: u64 = switch (byte) {
            '0'...'9' => byte - '0',
            'a'...'f' => byte - 'a' + 10,
            'A'...'F' => byte - 'A' + 10,
            else => return null,
        };
        if (digit >= base) return null;
        if (!result.overflow) {
            if (result.magnitude > (std.math.maxInt(u64) - digit) / base) result.overflow = true else result.magnitude = result.magnitude * base + digit;
        }
    }
    if (result.magnitude == 0 and !result.overflow) result.negative = false;
    return result;
}

fn bigintOutside(engine: *engine_mod.Engine, value: c.JSValue, symbol: c.JSValue, signed: bool, upper: bool) !bool {
    const primitive = try numberPrimitive(engine, value, symbol);
    defer engine.freeValue(primitive);
    if (c.JS_IsBigInt(primitive) or c.JS_IsString(primitive)) {
        const text = try engine.toString(primitive);
        defer engine.gpa.free(text);
        const integer = comparedInteger(text) orelse return false;
        if (upper) return !integer.negative and (integer.overflow or integer.magnitude > (if (signed) @as(u64, std.math.maxInt(i64)) else std.math.maxInt(u64)));
        return integer.negative and (!signed or integer.overflow or integer.magnitude > @as(u64, 1) << 63);
    }
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, primitive) < 0) return error.JavaScriptException;
    return if (upper) number >= (if (signed) @as(f64, 9_223_372_036_854_775_808) else @as(f64, 18_446_744_073_709_551_616)) else number < (if (signed) @as(f64, -9_223_372_036_854_775_808) else @as(f64, 0));
}

fn bigintWord(engine: *engine_mod.Engine, value: c.JSValue, symbol: c.JSValue, high: bool) !u32 {
    const primitive = try numberPrimitive(engine, value, symbol);
    defer engine.freeValue(primitive);
    if (!c.JS_IsBigInt(primitive)) {
        // ToNumeric(Symbol) throws before the mixed BigInt/Number check.
        if (c.JS_IsSymbol(primitive)) {
            var number: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &number, primitive) < 0) return error.JavaScriptException;
        }
        return error.MixingBigIntTypes;
    }
    var bits: u64 = 0;
    if (c.JS_ToBigUint64(engine.context, &bits, primitive) < 0) return error.JavaScriptException;
    return @truncate(if (high) bits >> 32 else bits);
}

fn writeBigintWord(engine: *engine_mod.Engine, this: c.JSValue, offset: usize, word: u32, little: bool, high: bool) !void {
    // Bounds were checked before word coercion. Node's subsequent indexed
    // writes are silent if that coercion detaches or shrinks the typed array.
    // Indexed C ABI setters preserve that behavior without retaining a pointer
    // across the next callback (which can transfer the backing store).
    for (0..4) |index| {
        const destination = offset + if (little) (if (high) @as(usize, 4) else 0) + index else (if (high) @as(usize, 3) else 7) - index;
        if (c.JS_SetPropertyInt64(engine.context, this, @intCast(destination), c.JS_NewInt32(engine.context, @intCast((word >> @as(u5, @intCast(index * 8))) & 0xff))) < 0) return error.JavaScriptException;
    }
}

fn bigintWrite(engine: *engine_mod.Engine, method: Method, this: c.JSValue, args: []c.JSValue, symbol: c.JSValue) !c.JSValue {
    const signed = method == .writeBigInt64LE or method == .writeBigInt64BE;
    const little = method == .writeBigUInt64LE or method == .writeBigInt64LE;
    const value = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (try bigintOutside(engine, value, symbol, signed, true) or try bigintOutside(engine, value, symbol, signed, false)) return error.BufferRange;
    const raw_offset = try numericArgument(engine, args, 1, 0);
    if (std.math.isNan(raw_offset) or raw_offset != @trunc(raw_offset)) return error.BufferRange;
    const size = blk: {
        const target = try numericView(engine, this);
        defer engine.freeValue(target.backing);
        break :blk target.bytes.len;
    };
    if (size < 8) return error.BufferBounds;
    if (raw_offset < 0 or raw_offset > @as(f64, @floatFromInt(size - 8))) return error.BufferRange;
    const offset: usize = @intFromFloat(raw_offset);
    const low = try bigintWord(engine, value, symbol, false);
    try writeBigintWord(engine, this, offset, low, little, false);
    const high = try bigintWord(engine, value, symbol, true);
    try writeBigintWord(engine, this, offset, high, little, true);
    return c.JS_NewInt64(engine.context, @intCast(offset + 8));
}

fn invokeBigintWrite(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return bigintWrite(engine, @enumFromInt(magic), this, argv[0..@intCast(argc)], data[0]) catch |err| failure(context, err);
}

fn numericCall(engine: *engine_mod.Engine, method: Method, this: c.JSValue, args: []c.JSValue) !c.JSValue {
    const name = @tagName(method);
    if (std.mem.startsWith(u8, name, "swap")) {
        const width: usize = if (method == .swap16) 2 else if (method == .swap32) 4 else 8;
        const target = try view(engine, this);
        defer engine.freeValue(target.backing);
        if (target.bytes.len % width != 0) return error.InvalidBufferSize;
        var start: usize = 0;
        while (start < target.bytes.len) : (start += width) std.mem.reverse(u8, target.bytes[start .. start + width]);
        return c.JS_DupValue(engine.context, this);
    }
    const write = std.mem.startsWith(u8, name, "write");
    const operation = name[if (write) @as(usize, 5) else 4..];
    const little = !std.mem.endsWith(u8, name, "BE");
    const big = std.mem.startsWith(u8, operation, "Big");
    const floating = std.mem.startsWith(u8, operation, "Float") or std.mem.startsWith(u8, operation, "Double");
    const signed = std.mem.startsWith(u8, operation, "Int") or std.mem.startsWith(u8, operation, "BigInt");
    const variable = std.mem.eql(u8, operation, "UIntLE") or std.mem.eql(u8, operation, "UIntBE") or std.mem.eql(u8, operation, "IntLE") or std.mem.eql(u8, operation, "IntBE");
    // Variable-width reads require an explicit offset even if width is invalid.
    if (variable and !write and (args.len == 0 or c.JS_IsUndefined(args[0]))) return error.InvalidBufferArgument;
    const width: usize = if (variable) blk: {
        const count = try numericArgument(engine, args, if (write) 2 else 1, null);
        if (!std.math.isFinite(count) or count != @trunc(count) or count < 1 or count > 6) return error.BufferRange;
        break :blk @intFromFloat(count);
    } else if (big or std.mem.startsWith(u8, operation, "Double")) 8 else if (std.mem.indexOf(u8, operation, "32") != null or floating) 4 else if (std.mem.indexOf(u8, operation, "16") != null) 2 else 1;
    var bits: u64 = 0;
    if (write) {
        // BigInt writers are registered through invokeBigintWrite so their
        // observable repeated conversions can interleave with word writes.
        std.debug.assert(!big);
        const value = if (args.len > 0) args[0] else c.pi_js_undefined();
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
        // Node's one-byte writer validates offset type before value range.
        if (!floating and width == 1) _ = try numericArgument(engine, args, 1, if (variable) null else 0);
        if (floating) {
            bits = if (width == 4) @as(u32, @bitCast(@as(f32, @floatCast(number)))) else @as(u64, @bitCast(number));
        } else {
            const magnitude = @as(u64, 1) << @as(u6, @intCast(width * 8 - @intFromBool(signed)));
            const maximum: f64 = @floatFromInt(magnitude - 1);
            const minimum: f64 = if (signed) -@as(f64, @floatFromInt(magnitude)) else 0;
            if (number > maximum or number < minimum) return error.BufferRange;
            bits = if (std.math.isNan(number)) 0 else if (signed) @bitCast(@as(i64, @intFromFloat(@trunc(number)))) else @intFromFloat(@trunc(number));
        }
    }
    // All possible user conversions happen before borrowing the backing store.
    const raw_offset = try numericArgument(engine, args, if (write) 1 else 0, if (variable) null else 0);
    if (std.math.isNan(raw_offset) or raw_offset != @trunc(raw_offset)) return error.BufferRange;
    const target = try numericView(engine, this);
    defer engine.freeValue(target.backing);
    if (target.bytes.len < width) return error.BufferBounds;
    if (raw_offset < 0 or raw_offset > @as(f64, @floatFromInt(target.bytes.len - width))) return error.BufferRange;
    const offset: usize = @intFromFloat(raw_offset);
    if (write) {
        for (0..width) |index| target.bytes[offset + index] = @truncate(bits >> @as(u6, @intCast((if (little) index else width - 1 - index) * 8)));
        return c.JS_NewInt64(engine.context, @intCast(offset + width));
    }
    for (0..width) |index| bits |= @as(u64, target.bytes[offset + index]) << @as(u6, @intCast((if (little) index else width - 1 - index) * 8));
    if (floating) return c.JS_NewFloat64(engine.context, if (width == 4) @as(f32, @bitCast(@as(u32, @truncate(bits)))) else @as(f64, @bitCast(bits)));
    if (signed) {
        if (width < 8 and bits & (@as(u64, 1) << @as(u6, @intCast(width * 8 - 1))) != 0) bits |= @as(u64, std.math.maxInt(u64)) << @as(u6, @intCast(width * 8));
        const value: i64 = @bitCast(bits);
        return if (big) c.JS_NewBigInt64(engine.context, value) else c.JS_NewInt64(engine.context, value);
    }
    return if (big) c.JS_NewBigUint64(engine.context, bits) else c.JS_NewFloat64(engine.context, @floatFromInt(bits));
}

fn methodCall(engine: *engine_mod.Engine, method: Method, this: c.JSValue, args: []c.JSValue) anyerror!c.JSValue {
    if (@intFromEnum(method) >= @intFromEnum(Method.readUInt8)) return numericCall(engine, method, this, args);
    if (method == .copy) return copyBuffer(engine, this, args);
    if (method == .fill) return fillBuffer(engine, this, args);
    if (method == .compare) return compareBuffer(engine, this, args);
    // Convert arguments before borrowing array storage that user conversion
    // callbacks could detach. Once borrowed, no user callback is invoked.
    const observed = try view(engine, this);
    const size = observed.bytes.len;
    engine.freeValue(observed.backing);
    const start = if (method == .toString) try argumentIndex(engine, args, 1, size, 0, false) else if (method == .slice or method == .subarray) try argumentIndex(engine, args, 0, size, 0, true) else 0;
    const end = if (method == .toString) try argumentIndex(engine, args, 2, size, size, false) else if (method == .slice or method == .subarray) try argumentIndex(engine, args, 1, size, size, true) else size;
    const codec = if (method == .toString) try encoding(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), false) else encodings.Encoding.utf8;
    const source = try view(engine, this);
    defer engine.freeValue(source.backing);
    if (start > source.bytes.len or end > source.bytes.len) return error.BufferRange;
    switch (method) {
        .toString => {
            const text = try encodings.decode(engine.gpa, source.bytes[start..@max(start, end)], codec);
            defer engine.gpa.free(text);
            return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
        },
        .slice, .subarray => return fromBacking(engine, source.backing, source.offset + start, @max(start, end) - start),
        .toJSON => {
            const object = try engine.checked(c.JS_NewObject(engine.context));
            errdefer engine.freeValue(object);
            const data = try engine.checked(c.JS_NewArray(engine.context));
            var consumed = false;
            errdefer if (!consumed) engine.freeValue(data);
            for (source.bytes, 0..) |byte, position| if (c.JS_SetPropertyUint32(engine.context, data, @intCast(position), c.pi_js_int32(engine.context, byte)) < 0) return error.JavaScriptException;
            try property(engine, object, "type", try engine.checked(c.JS_NewString(engine.context, "Buffer")));
            consumed = true;
            try property(engine, object, "data", data);
            return object;
        },
        .equals => {
            if (args.len == 0) return error.InvalidBufferArgument;
            const other = try view(engine, args[0]);
            defer engine.freeValue(other.backing);
            const order = std.mem.order(u8, source.bytes, other.bytes);
            return c.pi_js_bool(engine.context, @intFromBool(order == .eq));
        },
        else => unreachable,
    }
}

fn sizeOf(engine: *engine_mod.Engine, value: c.JSValue) !usize {
    const observed = try view(engine, value);
    defer engine.freeValue(observed.backing);
    return observed.bytes.len;
}

fn copyBuffer(engine: *engine_mod.Engine, this: c.JSValue, args: []c.JSValue) !c.JSValue {
    if (args.len == 0) return error.InvalidBufferArgument;
    const source_size = try sizeOf(engine, this);
    const target_size = try sizeOf(engine, args[0]);
    const target_start = @min(try copyIndex(engine, args, 1, 0), target_size);
    const source_start = try copyIndex(engine, args, 2, 0);
    const source_end = @min(try copyIndex(engine, args, 3, source_size), source_size);
    if (source_start > source_size) return error.BufferRange;
    const source = try view(engine, this);
    defer engine.freeValue(source.backing);
    const target = try view(engine, args[0]);
    defer engine.freeValue(target.backing);
    if (source_start > source.bytes.len or source_end > source.bytes.len or target_start > target.bytes.len) return error.BufferRange;
    const count = @min(@max(source_start, source_end) - source_start, target.bytes.len - target_start);
    const from_bytes = source.bytes[source_start .. source_start + count];
    const to_bytes = target.bytes[target_start .. target_start + count];
    if (@intFromPtr(to_bytes.ptr) <= @intFromPtr(from_bytes.ptr)) std.mem.copyForwards(u8, to_bytes, from_bytes) else std.mem.copyBackwards(u8, to_bytes, from_bytes);
    return engine.checked(c.JS_NewInt64(engine.context, @intCast(count)));
}

fn copyIndex(engine: *engine_mod.Engine, args: []c.JSValue, position: usize, default: usize) !usize {
    if (position >= args.len or c.JS_IsUndefined(args[position])) return default;
    var value: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &value, args[position]) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(value)) return 0;
    const integer = @floor(value);
    if (integer < 0) return error.BufferRange;
    return @intFromFloat(@min(integer, @as(f64, @floatFromInt(std.math.maxInt(u32)))));
}

fn strictIndex(engine: *engine_mod.Engine, args: []c.JSValue, position: usize, default: usize, maximum: usize) !usize {
    if (position >= args.len or c.JS_IsUndefined(args[position])) return default;
    if (!c.JS_IsNumber(args[position])) return error.InvalidBufferArgument;
    var value: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &value, args[position]) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(value) or value != @trunc(value) or value < 0 or value > @as(f64, @floatFromInt(maximum))) return error.BufferRange;
    return @intFromFloat(value);
}

fn compareBuffer(engine: *engine_mod.Engine, this: c.JSValue, args: []c.JSValue) !c.JSValue {
    if (args.len == 0) return error.InvalidBufferArgument;
    const source_size = try sizeOf(engine, this);
    const target_size = try sizeOf(engine, args[0]);
    const target_start = try strictIndex(engine, args, 1, 0, std.math.maxInt(u32));
    const target_end = try strictIndex(engine, args, 2, target_size, target_size);
    const source_start = try strictIndex(engine, args, 3, 0, std.math.maxInt(u32));
    const source_end = try strictIndex(engine, args, 4, source_size, source_size);
    if (source_start >= source_end) return c.pi_js_int32(engine.context, if (target_start >= target_end) 0 else -1);
    if (target_start >= target_end) return c.pi_js_int32(engine.context, 1);
    const source = try view(engine, this);
    defer engine.freeValue(source.backing);
    const target = try view(engine, args[0]);
    defer engine.freeValue(target.backing);
    return c.pi_js_int32(engine.context, switch (std.mem.order(u8, source.bytes[source_start..source_end], target.bytes[target_start..target_end])) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    });
}

fn fillBuffer(engine: *engine_mod.Engine, this: c.JSValue, args: []c.JSValue) !c.JSValue {
    if (args.len == 0) return error.InvalidBufferArgument;
    const size = try sizeOf(engine, this);
    const encoding_at_offset = args.len < 2 or c.JS_IsUndefined(args[1]) or (c.JS_IsString(args[0]) and c.JS_IsString(args[1]));
    const encoding_at_end = c.JS_IsString(args[0]) and args.len > 2 and c.JS_IsString(args[2]);
    const begin = if (encoding_at_offset) 0 else try strictIndex(engine, args, 1, 0, std.math.maxInt(u32));
    const finish = if (encoding_at_offset or encoding_at_end) size else try strictIndex(engine, args, 2, size, size);
    const codec_value = if (encoding_at_offset) if (args.len > 1) args[1] else c.pi_js_undefined() else if (encoding_at_end) args[2] else if (args.len > 3) args[3] else c.pi_js_undefined();
    const codec = if (c.JS_IsString(args[0])) try encoding(engine, codec_value, true) else encodings.Encoding.utf8;
    if (finish <= begin) return c.JS_DupValue(engine.context, this);
    var pattern: ?[]u8 = null;
    defer if (pattern) |bytes| engine.gpa.free(bytes);
    var numeric: i32 = 0;
    if (c.JS_IsString(args[0])) {
        const text = try engine.toString(args[0]);
        defer engine.gpa.free(text);
        pattern = try encodings.encode(engine.gpa, text, codec);
        if (pattern.?.len == 0 and text.len > 0) return error.InvalidBufferArgument;
    } else if (c.JS_GetTypedArrayType(args[0]) == c.JS_TYPED_ARRAY_UINT8) {
        const source = try view(engine, args[0]);
        defer engine.freeValue(source.backing);
        if (source.bytes.len == 0) return error.InvalidBufferArgument;
        pattern = try engine.gpa.dupe(u8, source.bytes);
    } else if (c.JS_ToInt32(engine.context, &numeric, args[0]) < 0) return error.JavaScriptException;
    const target = try view(engine, this);
    defer engine.freeValue(target.backing);
    if (begin > target.bytes.len or finish > target.bytes.len) return error.BufferRange;
    if (pattern) |bytes| {
        if (bytes.len == 0) {
            @memset(target.bytes[begin..finish], 0);
        } else {
            for (target.bytes[begin..finish], 0..) |*byte, position| byte.* = bytes[position % bytes.len];
        }
    } else @memset(target.bytes[begin..finish], @truncate(@as(u32, @bitCast(numeric))));
    return c.JS_DupValue(engine.context, this);
}

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.buffer_ready) return;
    if (engine.buffer_prototype != null) return error.NativeBufferPartiallyInstalled;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const typed_constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Uint8Array"));
    defer engine.freeValue(typed_constructor);
    const typed_prototype = try engine.checked(c.JS_GetPropertyStr(engine.context, typed_constructor, "prototype"));
    defer engine.freeValue(typed_prototype);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, typed_prototype));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "Buffer", 3, c.JS_CFUNC_constructor_or_func, 0));
    defer engine.freeValue(constructor);
    const symbol_constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "Symbol"));
    defer engine.freeValue(symbol_constructor);
    var bigint_data = [_]c.JSValue{try engine.checked(c.JS_GetPropertyStr(engine.context, symbol_constructor, "toPrimitive"))};
    defer engine.freeValue(bigint_data[0]);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0 or c.JS_SetPrototype(engine.context, constructor, typed_constructor) < 0) return error.JavaScriptException;
    inline for (std.meta.fields(Static)) |operation| {
        const name: [:0]const u8 = operation.name;
        try property(engine, constructor, name, try engine.checked(c.pi_js_function_magic(engine.context, invokeStatic, name.ptr, 2, @intCast(operation.value))));
    }
    inline for (std.meta.fields(Method)) |operation| {
        const name: [:0]const u8 = operation.name;
        const bigint_write = comptime std.mem.startsWith(u8, name, "writeBig");
        const function = try engine.checked(if (bigint_write) c.JS_NewCFunctionData(engine.context, invokeBigintWrite, 2, @intCast(operation.value), bigint_data.len, &bigint_data) else c.pi_js_function_magic(engine.context, invokeMethod, name.ptr, if (std.mem.startsWith(u8, name, "write")) 2 else 1, @intCast(operation.value)));
        if (bigint_write and c.JS_DefinePropertyValueStr(engine.context, function, "name", c.JS_NewString(engine.context, name.ptr), c.JS_PROP_CONFIGURABLE) < 0) {
            engine.freeValue(function);
            return error.JavaScriptException;
        }
        try property(engine, prototype, name, function);
        if (comptime std.mem.indexOf(u8, operation.name, "UInt")) |index| {
            const alias: [:0]const u8 = comptime std.fmt.comptimePrint("{s}Uint{s}", .{ operation.name[0..index], operation.name[index + 4 ..] });
            try property(engine, prototype, alias, c.JS_DupValue(engine.context, function));
        }
    }
    engine.buffer_prototype = c.JS_DupValue(engine.context, prototype);
    try property(engine, global, "Buffer", c.JS_DupValue(engine.context, constructor));
    const module = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(module);
    try property(engine, module, "Buffer", c.JS_DupValue(engine.context, constructor));
    try engine.registerDefaultModule("node:buffer", module);
    try engine.registerDefaultModule("buffer", module);
    engine.buffer_ready = true;
}

test "native Buffer copies arrays shares ArrayBuffers and retains binary encodings" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const namespace = engine.evalModule(
        "import {Buffer as imported} from 'node:buffer'; if(imported!==Buffer)throw Error('identity'); const original=new Uint8Array([1,2,3]);const copied=Buffer.from(original); original[0]=9;if(copied[0]!==1)throw Error('array copy');" ++
            "const shared=Buffer.from(original.buffer,1,2);shared[0]=8;if(original[1]!==8||!(shared instanceof Uint8Array)||!Buffer.isBuffer(shared)||Buffer.isBuffer(original))throw Error('shared view');const sliced=shared.slice(0,1);sliced[0]=7;if(shared[0]!==7||!Buffer.isBuffer(sliced))throw Error('slice');" ++
            "if(Buffer.from('🌍').toString()!=='🌍'||Buffer.from('aG V?sbG8=', 'base64').toString()!=='hello'||Buffer.from('ab12xz','hex').toString('hex')!=='ab12'||Buffer.from('abc').toString('base64url')!=='YWJj')throw Error('encoding');" ++
            "if(Buffer.from([0,216]).toString('utf16le').charCodeAt(0)!==0xd800)throw Error('surrogate');" ++
            "const overlap=Buffer.from([1,2,3,4]);if(overlap.copy(overlap,1,0,3)!==3||overlap.toString('hex')!=='01010203')throw Error('copy');" ++
            "if(Buffer.alloc(4,'ab').toString()!=='abab'||Buffer.concat([Buffer.from('a'),new Uint8Array([98])],4).toString('hex')!=='61620000')throw Error('allocation');" ++
            "if(Buffer.byteLength('🌍')!==4||Buffer.byteLength('zzzz','hex')!==2||Buffer.byteLength(new Uint16Array(2))!==4||Buffer.byteLength(new DataView(new ArrayBuffer(4)))!==4||Buffer.from(new DataView(new ArrayBuffer(4))).length!==0||!Buffer.isEncoding('UTF-16LE'))throw Error('length');" ++
            "export const json=Buffer.from({type:'Buffer',data:[42]}).toJSON(); let failures=0;for(const call of [()=>Buffer.alloc(-1),()=>Buffer.from(4),()=>Buffer.from('x','unknown')]){try{call();}catch(error){if(!error.code)throw error;failures++;}}if(failures!==3)throw Error('errors');",
        "native-buffer-fixture.mjs",
    ) catch |err| {
        std.debug.print("Native Buffer fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
    const json = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "json"));
    defer engine.freeValue(json);
    const encoded = try engine.stringify(json);
    defer engine.gpa.free(encoded);
    try std.testing.expectEqualStrings("{\"type\":\"Buffer\",\"data\":[42]}", encoded);
}

test "native Buffer mutators revalidate storage after user conversion detaches the backing" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const namespace = engine.evalModule(
        "if(typeof ArrayBuffer.prototype.transfer!=='function')throw Error('transfer fixture unavailable'); let failures=0,conversions=0; for(const method of ['toString','copy','fill']) {const buffer=Buffer.from([1,2,3]); const value={valueOf(){buffer.buffer.transfer();conversions++;return 0;}}; try {if(method==='toString')buffer.toString('hex',value);else if(method==='copy')buffer.copy(Buffer.alloc(3),value);else buffer.fill(value);}catch(error){failures++;}if(buffer.buffer.byteLength!==0)throw Error('buffer not detached');} if(failures!==3||conversions!==3)throw Error('detached storage');",
        "native-buffer-detach.mjs",
    ) catch |err| {
        std.debug.print("Native Buffer detachment fixture: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}

test "native Buffer preserves throwing conversion and getter exception identity" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const namespace = try engine.evalModule(
        "const original=new RangeError('owned conversion'); const calls=[()=>Buffer.from({valueOf(){throw original}}),()=>Buffer.from({get length(){throw original}}),()=>Buffer.from([1]).copy(Buffer.alloc(1),{valueOf(){throw original}})]; for(const call of calls){let caught=false;try{call()}catch(error){if(error!==original)throw Error('exception replaced');caught=true;}if(!caught)throw Error('conversion not called');}",
        "native-buffer-exceptions.mjs",
    );
    defer engine.freeValue(namespace);
}

test "native Buffer range coercion empty ranges and numeric view construction match Node contracts" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const namespace = try engine.evalModule(
        "if(Buffer.from(new Uint16Array([257,258])).toString('hex')!=='0102'||Buffer.from({length:'2',0:1,1:2}).length!==0)throw Error('typed/arraylike from');" ++
            "const buffer=Buffer.from([1,2,3]);if(buffer.copy(Buffer.alloc(3),0,Infinity)!==3||buffer.copy(Buffer.alloc(3),99999999999)!==0||buffer.compare(Buffer.from([1,2,3]),0,3,99)!==-1)throw Error('copy/compare ranges');" ++
            "if(Buffer.alloc(3).fill('a',undefined,1).toString()!=='aaa'||Buffer.alloc(3).fill('é','latin1').toString('hex')!=='e9e9e9')throw Error('fill overloads');" ++
            "let failed=0;for(const call of [()=>buffer.copy(Buffer.alloc(3),0,-1),()=>buffer.fill(7,NaN),()=>buffer.fill(7,1.5),()=>buffer.compare(buffer,0,3,-1)]){try{call();}catch(error){if(error.code!=='ERR_OUT_OF_RANGE')throw error;failed++;}}if(failed!==4)throw Error('range errors');",
        "native-buffer-ranges.mjs",
    );
    defer engine.freeValue(namespace);
}

test "native Buffer registration allocation failures cannot make a later retry look installed" {
    var failures: usize = 0;
    for (0..12) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try engine_mod.Engine.init(failing.allocator(), .{});
        defer engine.deinit();
        failing.fail_index = failing.alloc_index + offset;
        install(engine) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            failures += 1;
            failing.fail_index = std.math.maxInt(usize);
            try std.testing.expect(!engine.buffer_ready);
            try std.testing.expectError(error.NativeBufferPartiallyInstalled, install(engine));
            continue;
        };
        break;
    }
    try std.testing.expect(failures >= 4);
}

fn numericFixtureArgument(engine: *engine_mod.Engine, value: std.json.Value) !c.JSValue {
    const object = value.object;
    const kind = object.get("kind").?.string;
    if (std.mem.eql(u8, kind, "undefined")) return c.pi_js_undefined();
    if (std.mem.eql(u8, kind, "json")) return engine.fromJsonValue(object.get("value").?);
    const text = object.get("value").?.string;
    if (std.mem.eql(u8, kind, "number")) {
        return c.JS_NewFloat64(engine.context, if (std.mem.eql(u8, text, "NaN")) std.math.nan(f64) else if (std.mem.eql(u8, text, "Infinity")) std.math.inf(f64) else -std.math.inf(f64));
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "BigInt"));
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{try engine.fromJsonValue(.{ .string = text })};
    defer engine.freeValue(args[0]);
    return engine.checked(c.JS_Call(engine.context, constructor, c.pi_js_undefined(), 1, &args));
}

fn compareNumericFixture(engine: *engine_mod.Engine, row: std.json.ObjectMap) !void {
    var bytes: [16]u8 = undefined;
    const input = row.get("input").?.array.items;
    for (input, 0..) |byte, index| bytes[index] = @intCast(byte.integer);
    const buffer = try fromBytes(engine, bytes[0..input.len]);
    defer engine.freeValue(buffer);
    const method_name = try engine.gpa.dupeZ(u8, row.get("method").?.string);
    defer engine.gpa.free(method_name);
    const function = try engine.checked(c.JS_GetPropertyStr(engine.context, buffer, method_name));
    defer engine.freeValue(function);
    try std.testing.expect(c.JS_IsFunction(engine.context, function));
    const raw_args = row.get("args").?.array.items;
    var arguments: [3]c.JSValue = undefined;
    var count: usize = 0;
    defer for (arguments[0..count]) |argument| engine.freeValue(argument);
    for (raw_args) |argument| {
        arguments[count] = try numericFixtureArgument(engine, argument);
        count += 1;
    }
    const result = c.JS_Call(engine.context, function, buffer, @intCast(count), &arguments);
    defer engine.freeValue(result);
    if (row.get("error")) |expected| {
        try std.testing.expect(c.JS_IsException(result));
        const exception = c.JS_GetException(engine.context);
        defer engine.freeValue(exception);
        const name = try engine.checked(c.JS_GetPropertyStr(engine.context, exception, "name"));
        defer engine.freeValue(name);
        const actual_name = try engine.toString(name);
        defer engine.gpa.free(actual_name);
        try std.testing.expectEqualStrings(expected.object.get("name").?.string, actual_name);
        const code = try engine.checked(c.JS_GetPropertyStr(engine.context, exception, "code"));
        defer engine.freeValue(code);
        const expected_code = expected.object.get("code").?;
        if (expected_code == .null) {
            try std.testing.expect(c.JS_IsUndefined(code));
        } else {
            const actual_code = try engine.toString(code);
            defer engine.gpa.free(actual_code);
            try std.testing.expectEqualStrings(expected_code.string, actual_code);
        }
    } else {
        _ = try engine.checked(result);
        const expected = row.get("result").?.object;
        if (std.mem.eql(u8, expected.get("kind").?.string, "bigint")) {
            try std.testing.expect(c.JS_IsBigInt(result));
            const text = try engine.toString(result);
            defer engine.gpa.free(text);
            try std.testing.expectEqualStrings(expected.get("value").?.string, text);
        } else {
            var actual: f64 = 0;
            try std.testing.expect(c.JS_ToFloat64(engine.context, &actual, result) == 0);
            const text = expected.get("value").?.string;
            if (std.mem.eql(u8, text, "NaN")) {
                try std.testing.expect(std.math.isNan(actual));
            } else {
                const wanted: f64 = if (std.mem.eql(u8, text, "Infinity")) std.math.inf(f64) else if (std.mem.eql(u8, text, "-Infinity")) -std.math.inf(f64) else try std.fmt.parseFloat(f64, text);
                try std.testing.expectEqual(wanted, actual);
                if (wanted == 0) try std.testing.expectEqual(expected.get("negativeZero").?.bool, std.math.signbit(actual));
            }
        }
    }
    const output = try view(engine, buffer);
    defer engine.freeValue(output.backing);
    for (row.get("bytes").?.array.items, 0..) |byte, index| try std.testing.expectEqual(@as(u8, @intCast(byte.integer)), output.bytes[index]);
}

test "native Buffer numeric methods match captured Node 24 offsets values ranges and bytes" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .interrupt_budget = 5_000_000 });
    defer engine.deinit();
    try install(engine);
    var fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/buffer_numeric.json"), .{});
    defer fixture.deinit();
    const cases = fixture.value.object.get("cases").?.array.items;
    try std.testing.expectEqual(@as(usize, 31_352), cases.len);
    for (cases, 0..) |row, index| {
        compareNumericFixture(engine, row.object) catch |err| {
            std.debug.print("Buffer numeric oracle case {d} {s}: {s}\n", .{ index, row.object.get("method").?.string, @errorName(err) });
            const diagnostic = try std.json.Stringify.valueAlloc(engine.gpa, row, .{});
            defer engine.gpa.free(diagnostic);
            std.debug.print("{s}\n", .{diagnostic});
            return err;
        };
    }
    const namespace = try engine.evalModule("if(Buffer.prototype.readUInt32LE!==Buffer.prototype.readUint32LE||Buffer.prototype.writeBigUInt64BE!==Buffer.prototype.writeBigUint64BE)throw Error('alias identity'); const b=Buffer.from([1,2,3,4,5,6,7,8]);if(b.swap16()!==b||b.toString('hex')!=='0201040306050807')throw Error('swap16');b.swap32();if(b.toString('hex')!=='0304010207080506')throw Error('swap32');b.swap64();if(b.toString('hex')!=='0605080702010403')throw Error('swap64');", "native-buffer-numeric-aliases.mjs");
    defer engine.freeValue(namespace);
}

test "native numeric Buffer conversion preserves exceptions and detached storage bounds" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const namespace = try engine.evalModule(
        "if(typeof ArrayBuffer.prototype.transfer!=='function')throw Error('detachment unavailable');let conversions=0;for(const method of ['writeUInt16LE','writeFloatLE']){const storage=new ArrayBuffer(8), b=Buffer.from(storage);let caught=false;try{b[method]({valueOf(){conversions++;storage.transfer();return 1}},0)}catch(error){if(!(error instanceof RangeError)||error.code!=='ERR_BUFFER_OUT_OF_BOUNDS')throw error;caught=true}if(!caught||b.length!==0)throw Error('detached numeric write');}if(conversions!==2)throw Error('conversion count');" ++
            "const original=new Error('original numeric conversion');const b=Buffer.alloc(8);for(const method of ['writeUInt32LE','writeDoubleBE']){let caught=false;try{b[method]({valueOf(){throw original}},0)}catch(error){if(error!==original)throw Error('numeric exception replaced');caught=true}if(!caught||b.toString('hex')!=='0000000000000000')throw Error('throwing write modified bytes');}b.writeDoubleLE(-0);if(!Object.is(b.readDoubleLE(),-0))throw Error('negative zero');b.writeDoubleBE(Infinity);if(b.readDoubleBE()!==Infinity)throw Error('infinity');b.writeFloatLE(NaN);if(!Number.isNaN(b.readFloatLE()))throw Error('nan');",
        "native-buffer-numeric-detachment.mjs",
    );
    defer engine.freeValue(namespace);
}

test "native BigInt Buffer writers preserve Node comparison word coercion and partial writes" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .interrupt_budget = 100_000 });
    defer engine.deinit();
    try install(engine);
    const namespace = engine.evalModule(
        "const methods=['writeBigUInt64LE','writeBigUInt64BE','writeBigInt64LE','writeBigInt64BE'];" ++
            "for(const method of methods){const le=method.endsWith('LE');const b=Buffer.alloc(8);let n=0;const v={valueOf(){n++;return 0x12345678abcdef01n}};if(b[method](v)!==8||n!==4||b.toString('hex')!==(le?'01efcdab78563412':'12345678abcdef01'))throw Error('ordinary bigint '+method);" ++
            "let events=[];const exotic={get [Symbol.toPrimitive](){events.push('get');return function(hint){events.push(hint);return 0x12345678abcdef01n}},valueOf(){throw Error('exotic fallback')}};b[method](exotic);if(events.join(',')!=='get,number,get,number,get,number,get,number')throw Error('exotic calls '+method);" ++
            "let step=0;const changing={valueOf(){return [0n,0n,0xabcdef01n,0x1234567800000000n][step++]}};b.fill(0);b[method](changing);if(step!==4||b.toString('hex')!==(le?'01efcdab78563412':'12345678abcdef01'))throw Error('changing words '+method);" ++
            "const original=new Error('original getter');for(const failAt of [1,2,3,4]){let calls=0;b.fill(0);const bad={get valueOf(){if(++calls===failAt)throw original;return function(){return 0x12345678abcdef01n}}};let caught=false;try{b[method](bad)}catch(error){if(error!==original)throw Error('getter error identity '+method);caught=true}if(!caught||calls!==failAt||b.toString('hex')!==(failAt===4?(le?'01efcdab00000000':'00000000abcdef01'):'0000000000000000'))throw Error('partial write '+method+' '+failAt);}" ++
            "}",
        "native-buffer-bigint-coercion.mjs",
    ) catch |err| {
        std.debug.print("Native BigInt Buffer coercion: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}

test "native BigInt Buffer comparisons use exact StringToBigInt and Node error order" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .interrupt_budget = 100_000 });
    defer engine.deinit();
    try install(engine);
    const namespace = engine.evalModule(
        "function fails(call,name,code){let caught=false;try{call()}catch(error){if(error.name!==name||error.code!==code)throw Error('wrong error '+error.name+' '+error.code);caught=true}if(!caught)throw Error('missing error')}" ++
            "for(const method of ['writeBigUInt64LE','writeBigUInt64BE','writeBigInt64LE','writeBigInt64BE']){const signed=method.includes('BigInt');const b=Buffer.alloc(8);" ++
            "for(const value of ['', '0', '0xff', '0b1', '0o7', '-0', '+0', '1e100', '1.5', '-0x1', '0x', '999999999999999999999z', '\\u200b1', '\\ud800', null,true,undefined,NaN]){fails(()=>b[method](value),'TypeError',undefined);fails(()=>b[method](value,'bad'),'TypeError','ERR_INVALID_ARG_TYPE');}" ++
            "const maximum=signed?'9223372036854775807':'18446744073709551615';for(const value of [maximum,'\\ufeff\\u2000'+maximum+'\\u2029\\u3000',signed?'0x7fffffffffffffff':'0xffffffffffffffff']){fails(()=>b[method](value),'TypeError',undefined);fails(()=>b[method](value,'bad'),'TypeError','ERR_INVALID_ARG_TYPE');}" ++
            "const outside=signed?['9223372036854775808','-9223372036854775809','0x8000000000000000',9223372036854775808]:['18446744073709551616','-1','0x10000000000000000',18446744073709551616];for(const value of outside){fails(()=>b[method](value,'bad'),'RangeError','ERR_OUT_OF_RANGE');fails(()=>Buffer.alloc(0)[method](value),'RangeError','ERR_OUT_OF_RANGE');}" ++
            "if(signed){fails(()=>b[method]('-9223372036854775808'),'TypeError',undefined);b[method]({valueOf(){return -9223372036854775808n}});if(b.toString('hex')!==(method.endsWith('LE')?'0000000000000080':'8000000000000000'))throw Error('signed minimum')}" ++
            "let n=0;fails(()=>b[method]({valueOf(){n++;return signed?9223372036854775808n:18446744073709551616n}},'bad'),'RangeError','ERR_OUT_OF_RANGE');if(n!==1)throw Error('upper short circuit');n=0;fails(()=>b[method]({valueOf(){n++;return 0n}},'bad'),'TypeError','ERR_INVALID_ARG_TYPE');if(n!==2)throw Error('offset order');" ++
            "const original=new Error('exotic getter');fails(()=>b[method]({[Symbol.toPrimitive]:1}),'TypeError',undefined);fails(()=>b[method]({[Symbol.toPrimitive](){return {}}}),'TypeError',undefined);try{b[method]({get [Symbol.toPrimitive](){throw original}})}catch(error){if(error!==original)throw Error('exotic getter identity')}" ++
            "let fallback=[];fails(()=>b[method]({[Symbol.toPrimitive]:null,valueOf(){fallback.push('valueOf');return {}},toString(){fallback.push('toString');return '0'}},'bad'),'TypeError','ERR_INVALID_ARG_TYPE');if(fallback.join(',')!=='valueOf,toString,valueOf,toString')throw Error('ordinary fallback');}" ++
            "const intrinsicSymbol=Symbol.toPrimitive,OldSymbol=Symbol;globalThis.Symbol={toPrimitive:'wrong'};try{let calls=0;Buffer.alloc(8).writeBigUInt64LE({[intrinsicSymbol](hint){if(hint!=='number')throw Error('hint');calls++;return 1n}});if(calls!==4)throw Error('intrinsic symbol')}finally{globalThis.Symbol=OldSymbol}",
        "native-buffer-bigint-comparison.mjs",
    ) catch |err| {
        std.debug.print("Native BigInt Buffer comparisons: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}

test "native BigInt Buffer callbacks never retain detached storage and respect partial mutation" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .interrupt_budget = 100_000 });
    defer engine.deinit();
    try install(engine);
    const namespace = engine.evalModule(
        "for(const method of ['writeBigUInt64LE','writeBigUInt64BE','writeBigInt64LE','writeBigInt64BE'])for(const stage of [1,2,3,4]){const storage=new ArrayBuffer(8),b=Buffer.from(storage);let calls=0,moved;const value={valueOf(){if(++calls===stage)moved=storage.transfer();return 0x12345678abcdef01n}};let caught=false;try{if(b[method](value)!==8)throw Error('return offset')}catch(error){if(stage>2||error.name!=='RangeError'||error.code!=='ERR_BUFFER_OUT_OF_BOUNDS')throw error;caught=true}if(caught!==(stage<3)||calls!==(stage<3?2:4)||b.length!==0)throw Error('detach ordering '+method+' '+stage);if(stage===4){const bytes=Buffer.from(moved).toString('hex');if(bytes!==(method.endsWith('LE')?'01efcdab00000000':'00000000abcdef01'))throw Error('transfer partial word')}}" ++
            "for(const method of ['writeBigUInt64LE','writeBigUInt64BE']){const b=Buffer.alloc(8);let calls=0;const v={valueOf(){calls++;if(calls===4){b.fill(0x55);return 0x1234567800000000n}return 0xabcdef01n}};b[method](v);if(b.toString('hex')!==(method.endsWith('LE')?'5555555578563412':'1234567855555555'))throw Error('interleaved word mutation')}",
        "native-buffer-bigint-detachment.mjs",
    ) catch |err| {
        std.debug.print("Native BigInt Buffer detachment: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}

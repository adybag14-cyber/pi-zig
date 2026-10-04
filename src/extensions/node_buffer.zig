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
    var mixing_bigint_types = false;
    if (write) {
        const value = if (args.len > 0) args[0] else c.pi_js_undefined();
        if (big) {
            if (!c.JS_IsBigInt(value)) {
                mixing_bigint_types = true;
                var number: f64 = 0;
                if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
                const limit: f64 = if (signed) 9_223_372_036_854_775_808 else 18_446_744_073_709_551_616;
                if (number >= limit or number < (if (signed) -limit else @as(f64, 0))) return error.BufferRange;
            } else {
                const text = try engine.toString(value);
                defer engine.gpa.free(text);
                bits = if (signed)
                    @bitCast(std.fmt.parseInt(i64, text, 10) catch return error.BufferRange)
                else
                    std.fmt.parseInt(u64, text, 10) catch return error.BufferRange;
            }
        } else {
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
    }
    // All possible user conversions happen before borrowing the backing store.
    const raw_offset = try numericArgument(engine, args, if (write) 1 else 0, if (variable) null else 0);
    if (std.math.isNan(raw_offset) or raw_offset != @trunc(raw_offset)) return error.BufferRange;
    const target = try numericView(engine, this);
    defer engine.freeValue(target.backing);
    if (target.bytes.len < width) return error.BufferBounds;
    if (raw_offset < 0 or raw_offset > @as(f64, @floatFromInt(target.bytes.len - width))) return error.BufferRange;
    const offset: usize = @intFromFloat(raw_offset);
    if (mixing_bigint_types) return error.MixingBigIntTypes;
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
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0 or c.JS_SetPrototype(engine.context, constructor, typed_constructor) < 0) return error.JavaScriptException;
    inline for (std.meta.fields(Static)) |operation| {
        const name: [:0]const u8 = operation.name;
        try property(engine, constructor, name, try engine.checked(c.pi_js_function_magic(engine.context, invokeStatic, name.ptr, 2, @intCast(operation.value))));
    }
    inline for (std.meta.fields(Method)) |operation| {
        const name: [:0]const u8 = operation.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, invokeMethod, name.ptr, if (std.mem.startsWith(u8, name, "write")) 2 else 1, @intCast(operation.value)));
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

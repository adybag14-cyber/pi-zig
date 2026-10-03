//! UTF-8 TextEncoder host behavior implemented in Zig through the C runtime.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;

fn brand(engine: *engine_mod.Engine, value: c.JSValue) !void {
    if (engine.text_encoder_class == 0 or c.JS_GetOpaque(value, engine.text_encoder_class) != @as(*anyopaque, @ptrCast(engine))) return error.IllegalTextEncoderInvocation;
}

fn input(engine: *engine_mod.Engine, argc: c_int, argv: [*c]c.JSValue) ![]u8 {
    if (argc == 0 or c.JS_IsUndefined(argv[0])) return engine.gpa.dupe(u8, "");
    return engine.toString(argv[0]);
}

fn scalar(codepoint: u21) u21 {
    return if (codepoint >= 0xd800 and codepoint <= 0xdfff) 0xfffd else codepoint;
}

fn utf8(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    var buffer: [4]u8 = undefined;
    while (iterator.nextCodepoint()) |codepoint| {
        const length = try std.unicode.utf8Encode(scalar(codepoint), &buffer);
        try output.appendSlice(gpa, buffer[0..length]);
    }
    return output.toOwnedSlice(gpa);
}

fn construct(context: ?*c.JSContext, new_target: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const prototype = c.JS_GetPropertyStr(context, new_target, "prototype");
    if (c.JS_IsException(prototype)) return prototype;
    defer engine.freeValue(prototype);
    const object = c.JS_NewObjectProtoClass(context, prototype, engine.text_encoder_class);
    if (!c.JS_IsException(object)) _ = c.JS_SetOpaque(object, engine);
    return object;
}

fn encode(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return encodeValue(engine, this, argc, argv) catch |err| c.JS_ThrowTypeError(context, "Native TextEncoder failed: %s", @as([*:0]const u8, @errorName(err)));
}

fn encodeValue(engine: *engine_mod.Engine, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    try brand(engine, this);
    const text = try input(engine, argc, argv);
    defer engine.gpa.free(text);
    const bytes = try utf8(engine.gpa, text);
    defer engine.gpa.free(bytes);
    const buffer = try engine.checked(c.JS_NewArrayBufferCopy(engine.context, bytes.ptr, bytes.len));
    defer engine.freeValue(buffer);
    var arguments = [_]c.JSValue{buffer};
    return engine.checked(c.JS_NewTypedArray(engine.context, arguments.len, &arguments, c.JS_TYPED_ARRAY_UINT8));
}

fn encodeInto(context: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return intoValue(engine, this, argc, argv) catch |err| c.JS_ThrowTypeError(context, "Native TextEncoder.encodeInto failed: %s", @as([*:0]const u8, @errorName(err)));
}

fn intoValue(engine: *engine_mod.Engine, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    try brand(engine, this);
    if (argc < 2 or c.JS_GetTypedArrayType(argv[1]) != c.JS_TYPED_ARRAY_UINT8) return error.InvalidTextEncoderDestination;
    const text = try engine.toString(argv[0]);
    defer engine.gpa.free(text);
    var offset: usize = 0;
    var length: usize = 0;
    var element_bytes: usize = 0;
    const buffer = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, argv[1], &offset, &length, &element_bytes));
    defer engine.freeValue(buffer);
    var total_length: usize = 0;
    const data = c.JS_GetArrayBuffer(engine.context, &total_length, buffer);
    if (c.JS_HasException(engine.context) or offset > total_length or length > total_length - offset or (data == null and length > 0)) return error.InvalidTextEncoderDestination;
    const destination: []u8 = if (length == 0) &.{} else data[offset .. offset + length];
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    var read: usize = 0;
    var written: usize = 0;
    var encoded: [4]u8 = undefined;
    while (iterator.nextCodepoint()) |codepoint| {
        const count = try std.unicode.utf8Encode(scalar(codepoint), &encoded);
        if (count > destination.len - written) break;
        @memcpy(destination[written .. written + count], encoded[0..count]);
        written += count;
        read += if (codepoint > 0xffff) @as(usize, 2) else 1;
    }
    const result = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(result);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "read", c.JS_NewInt64(engine.context, @intCast(read)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, result, "written", c.JS_NewInt64(engine.context, @intCast(written)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return result;
}

fn encoding(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    brand(engine, this) catch return c.JS_ThrowTypeError(context, "Illegal TextEncoder receiver");
    return c.JS_NewString(context, "utf-8");
}

pub fn install(engine: *engine_mod.Engine) !void {
    if (engine.text_encoder_class != 0) return error.TextEncoderAlreadyInstalled;
    _ = c.JS_NewClassID(engine.runtime, &engine.text_encoder_class);
    const definition: c.JSClassDef = .{ .class_name = "TextEncoder", .finalizer = null, .gc_mark = null, .call = null, .exotic = null };
    if (c.JS_NewClass(engine.runtime, engine.text_encoder_class, &definition) < 0) return error.TextEncoderClassFailed;
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "TextEncoder", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    c.JS_SetClassProto(engine.context, engine.text_encoder_class, c.JS_DupValue(engine.context, prototype));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "encode", c.JS_NewCFunction(engine.context, encode, "encode", 0), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "encodeInto", c.JS_NewCFunction(engine.context, encodeInto, "encodeInto", 2), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const atom = c.JS_NewAtom(engine.context, "encoding");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_NewCFunction(engine.context, encoding, "encoding", 0), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, "TextEncoder", c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}

test "native TextEncoder handles Unicode replacement empty input typed views and partial writes" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = try engine.eval("const encoder=new TextEncoder(); const backing=new Uint8Array(7).fill(99); const partial=encoder.encodeInto('🌍a',backing.subarray(1,5)); const short=encoder.encodeInto('🌍',new Uint8Array(3)); JSON.stringify({encoding:encoder.encoding,empty:Array.from(encoder.encode()),replacement:Array.from(encoder.encode('\\ud800')),bytes:Array.from(backing),partial,short});", "encoder-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"encoding\":\"utf-8\",\"empty\":[],\"replacement\":[239,191,189],\"bytes\":[99,240,159,140,141,99,99],\"partial\":{\"read\":2,\"written\":4},\"short\":{\"read\":0,\"written\":0}}", text);
    try std.testing.expectError(error.JavaScriptException, engine.eval("TextEncoder.prototype.encode.call({},'bad receiver')", "encoder-brand.js", c.JS_EVAL_TYPE_GLOBAL));
}

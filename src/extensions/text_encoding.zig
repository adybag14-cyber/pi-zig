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
    return encodeValue(engine, this, argc, argv) catch |err| failure(engine, err);
}

fn failure(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    _ = c.JS_ThrowTypeError(engine.context, "Native TextEncoder failed: %s", @as([*:0]const u8, @errorName(err)));
    const exception = c.JS_GetException(engine.context);
    const code: [*:0]const u8 = if (err == error.IllegalTextEncoderInvocation) "ERR_INVALID_THIS" else "ERR_INVALID_ARG_TYPE";
    if (c.JS_DefinePropertyValueStr(engine.context, exception, "code", c.JS_NewString(engine.context, code), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(exception);
        return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    }
    return c.JS_Throw(engine.context, exception);
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
    return intoValue(engine, this, argc, argv) catch |err| failure(engine, err);
}

fn intoValue(engine: *engine_mod.Engine, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    try brand(engine, this);
    // Node validates src as a primitive string before examining dest. Unlike
    // encode(), encodeInto() does not invoke source conversion callbacks.
    if (argc < 1 or !c.JS_IsString(argv[0])) return error.InvalidTextEncoderSource;
    if (argc < 2 or c.JS_GetTypedArrayType(argv[1]) != c.JS_TYPED_ARRAY_UINT8) return error.InvalidTextEncoderDestination;
    const text = try engine.toString(argv[0]);
    defer engine.gpa.free(text);
    var offset: usize = 0;
    var length: usize = 0;
    var element_bytes: usize = 0;
    const buffer = c.JS_GetTypedArrayBuffer(engine.context, argv[1], &offset, &length, &element_bytes);
    if (c.JS_IsException(buffer)) {
        // The intrinsic accessor rejects detached and resizable OOB views.
        // Node accepts their Uint8Array brand and encodes into zero bytes.
        // Consume only the intrinsic exception, without diagnostic conversion
        // that could invoke a user-defined Error.prototype.toString callback.
        const exception = c.JS_GetException(engine.context);
        if (c.JS_IsUncatchableError(exception)) {
            _ = c.JS_Throw(engine.context, exception);
            return error.JavaScriptException;
        }
        // An allocation failure while constructing the intrinsic TypeError
        // must not be mistaken for a successful zero-length destination.
        if (c.JS_IsNull(exception)) return error.OutOfMemory;
        const message = c.JS_GetPropertyStr(engine.context, exception, "message");
        if (c.JS_IsException(message)) {
            engine.freeValue(exception);
            return error.JavaScriptException;
        }
        defer engine.freeValue(message);
        var message_length: usize = 0;
        const message_text = c.JS_ToCStringLen(engine.context, &message_length, message);
        if (message_text == null) {
            engine.freeValue(exception);
            return error.JavaScriptException;
        }
        defer c.JS_FreeCString(engine.context, message_text);
        if (std.mem.eql(u8, message_text[0..message_length], "out of memory")) {
            engine.freeValue(exception);
            return error.OutOfMemory;
        }
        engine.freeValue(exception);
        return counts(engine, 0, 0);
    }
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
    return counts(engine, read, written);
}

fn counts(engine: *engine_mod.Engine, read: usize, written: usize) !c.JSValue {
    const result = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(result);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "read", c.JS_NewInt64(engine.context, @intCast(read)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    if (c.JS_DefinePropertyValueStr(engine.context, result, "written", c.JS_NewInt64(engine.context, @intCast(written)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return result;
}

fn encoding(context: ?*c.JSContext, this: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    brand(engine, this) catch |err| return failure(engine, err);
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

test "native TextEncoder exact Node UTF16 read counts and scalar capacity boundaries" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .interrupt_budget = 100_000 });
    defer engine.deinit();
    try install(engine);
    // Expected rows captured from the installed Node 24 TextEncoder. Each
    // destination starts filled with 99, including untouched boundary guards.
    const namespace = try engine.evalModule(
        "const e=new TextEncoder(),rows=[" ++
            "['a🌍\\ud800é',0,0,0,[]],['a🌍\\ud800é',4,1,1,[97,99,99,99]],['a🌍\\ud800é',5,3,5,[97,240,159,140,141]],['a🌍\\ud800é',7,3,5,[97,240,159,140,141,99,99]],['a🌍\\ud800é',8,4,8,[97,240,159,140,141,239,191,189]],['a🌍\\ud800é',9,4,8,[97,240,159,140,141,239,191,189,99]],['a🌍\\ud800é',10,5,10,[97,240,159,140,141,239,191,189,195,169]]," ++
            "['\\ud800\\udc00',3,0,0,[99,99,99]],['\\ud800\\udc00',4,2,4,[240,144,128,128]],['\\udc00\\ud800',2,0,0,[99,99]],['\\udc00\\ud800',3,1,3,[239,191,189]],['\\udc00\\ud800',5,1,3,[239,191,189,99,99]],['\\udc00\\ud800',6,2,6,[239,191,189,239,191,189]]," ++
            "['€éa',2,0,0,[99,99]],['€éa',3,1,3,[226,130,172]],['€éa',4,1,3,[226,130,172,99]],['€éa',5,2,5,[226,130,172,195,169]],['€éa',6,3,6,[226,130,172,195,169,97]]];" ++
            "for(const [src,n,read,written,bytes] of rows){const storage=new Uint8Array(n+2).fill(99),r=e.encodeInto(src,storage.subarray(1,n+1));if(r.read!==read||r.written!==written||JSON.stringify(Array.from(storage))!==JSON.stringify([99,...bytes,99]))throw Error('Node scalar oracle '+JSON.stringify([src,n,r]));}" ++
            "if(JSON.stringify(Array.from(e.encode('a🌍\\ud800é')))!=='[97,240,159,140,141,239,191,189,195,169]')throw Error('encode replacement');",
        "native-textencoder-unicode.mjs",
    );
    defer engine.freeValue(namespace);
}

test "native TextEncoder preserves source errors brands and empty detached destinations" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .interrupt_budget = 100_000 });
    defer engine.deinit();
    try install(engine);
    const namespace = engine.evalModule(
        "const e=new TextEncoder();function fails(call,code){let caught=false;try{call()}catch(error){if(error.name!=='TypeError'||error.code!==code)throw error;caught=true}if(!caught)throw Error('missing type error')}" ++
            "const original=new Error('original source');for(const src of [{toString(){throw original}},{get toString(){throw original}},{get [Symbol.toPrimitive](){throw original}}]){let caught=false;try{e.encode(src)}catch(error){if(error!==original)throw Error('source exception replaced');caught=true}if(!caught)throw Error('missing source exception')}" ++
            "let calls=0;const object={get toString(){calls++;throw original}};for(const src of [object,new String('a'),undefined,null,1,true,1n,Symbol('x')]){fails(()=>e.encodeInto(src,new Uint8Array(4)),'ERR_INVALID_ARG_TYPE');fails(()=>e.encodeInto(src,{}),'ERR_INVALID_ARG_TYPE')}if(calls!==0)throw Error('encodeInto converted source');" ++
            "for(const dest of [undefined,null,{},new Uint8ClampedArray(4),new Int8Array(4),new Uint16Array(4),new DataView(new ArrayBuffer(4)),new ArrayBuffer(4),new Proxy(new Uint8Array(4),{})])fails(()=>e.encodeInto('a',dest),'ERR_INVALID_ARG_TYPE');" ++
            "fails(()=>TextEncoder.prototype.encode.call({},object),'ERR_INVALID_THIS');fails(()=>TextEncoder.prototype.encodeInto.call({},object,{}),'ERR_INVALID_THIS');fails(()=>Object.getOwnPropertyDescriptor(TextEncoder.prototype,'encoding').get.call({}),'ERR_INVALID_THIS');fails(()=>e.encode(Symbol('x')),undefined);" ++
            "const a=new ArrayBuffer(4),d=new Uint8Array(a);a.transfer();const saved=Error.prototype.toString;Error.prototype.toString=function(){throw original};try{if(JSON.stringify(e.encodeInto('abc',d))!=='{\"read\":0,\"written\":0}')throw Error('detached destination')}finally{Error.prototype.toString=saved}" ++
            "const resizable=new ArrayBuffer(8,{maxByteLength:16}),oob=new Uint8Array(resizable,4,4);resizable.resize(2);if(JSON.stringify(e.encodeInto('abc',oob))!=='{\"read\":0,\"written\":0}')throw Error('OOB destination');" ++
            "let hints=[];if(Array.from(e.encode({[Symbol.toPrimitive](hint){hints.push(hint);return 'a'}})).join(',')!=='97'||hints.join(',')!=='string')throw Error('encode hint');",
        "native-textencoder-errors.mjs",
    ) catch |err| {
        std.debug.print("Native TextEncoder contracts: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    defer engine.freeValue(namespace);
}

test "native TextEncoder allocation failures release temporary encoding and preserve destination" {
    var failures: usize = 0;
    for (0..20) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        const bytes = utf8(failing.allocator(), "🌍" ** 80) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            failures += 1;
            continue;
        };
        defer failing.allocator().free(bytes);
        try std.testing.expectEqual(@as(usize, 320), bytes.len);
        break;
    }
    try std.testing.expect(failures >= 2);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try engine_mod.Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    try install(engine);
    const encoder = try engine.eval("new TextEncoder()", "encoder-allocation.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(encoder);
    const source = try engine.checked(c.JS_NewString(engine.context, "🌍"));
    defer engine.freeValue(source);
    const backing = try engine.checked(c.JS_NewArrayBufferCopy(engine.context, &[_]u8{ 99, 99, 99, 99 }, 4));
    defer engine.freeValue(backing);
    var backing_args = [_]c.JSValue{backing};
    const destination = try engine.checked(c.JS_NewTypedArray(engine.context, 1, &backing_args, c.JS_TYPED_ARRAY_UINT8));
    defer engine.freeValue(destination);
    var arguments = [_]c.JSValue{ source, destination };
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, intoValue(engine, encoder, 2, &arguments));
    failing.fail_index = std.math.maxInt(usize);
    var size: usize = 0;
    const bytes = c.JS_GetArrayBuffer(engine.context, &size, backing);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 99, 99, 99, 99 }, bytes[0..size]);
    const result = try intoValue(engine, encoder, 2, &arguments);
    defer engine.freeValue(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 240, 159, 140, 141 }, bytes[0..size]);
    failing.fail_index = failing.alloc_index;
    const failed = encode(engine.context, encoder, 1, &arguments);
    try std.testing.expect(c.JS_IsException(failed));
    failing.fail_index = std.math.maxInt(usize);
    const exception = c.JS_GetException(engine.context);
    defer engine.freeValue(exception);
    const name = try engine.checked(c.JS_GetPropertyStr(engine.context, exception, "name"));
    defer engine.freeValue(name);
    const error_name = try engine.toString(name);
    defer engine.gpa.free(error_name);
    try std.testing.expectEqualStrings("InternalError", error_name);
}

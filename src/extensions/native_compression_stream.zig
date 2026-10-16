//! Incremental gzip/zlib/raw-DEFLATE codecs on real native WHATWG stream pairs.
//! zlib1.3.1 is called directly on the VM owner thread, with bounded output chunks
//! and Engine-allocator ownership. No JavaScript body or worker value is evaluated.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const transform = @import("native_transform_stream.zig");
const durable = @import("native_durable.zig");
const c = em.c;
const z = @cImport({
    @cDefine("Z_PREFIX", "1");
    @cInclude("zlib.h");
});
const module_key = "pi-native:whatwg-compression-stream";
const Format = enum { gzip, deflate, raw };
const Op = enum(c_int) { compress_readable, compress_writable, decompress_readable, decompress_writable, chunk, flush, cancel, byte_size };
const State = struct {
    engine: *em.Engine,
    owner: c.JSValue,
    readable: c.JSValue,
    writable: c.JSValue,
    stream: z.z_stream,
    format: Format,
    decompress: bool,
    initialized: bool = false,
    ended: bool = false,
    fn end(self: *State) void {
        if (!self.initialized) return;
        _ = if (self.decompress) z.inflateEnd(&self.stream) else z.deflateEnd(&self.stream);
        self.initialized = false;
    }
};
const AllocationHeader = extern struct { bytes: usize, padding: usize };
fn allocate(opaque_pointer: ?*anyopaque, items: c_uint, size: c_uint) callconv(.c) ?*anyopaque {
    const self: *State = @ptrCast(@alignCast(opaque_pointer orelse return null));
    const count = std.math.mul(usize, items, size) catch return null;
    const total = std.math.add(usize, count, @sizeOf(AllocationHeader)) catch return null;
    const memory = self.engine.gpa.rawAlloc(total, .@"16", @returnAddress()) orelse return null;
    const header: *AllocationHeader = @ptrCast(@alignCast(memory));
    header.* = .{ .bytes = total, .padding = 0 };
    @memset(memory[@sizeOf(AllocationHeader)..total], 0);
    return @ptrCast(memory + @sizeOf(AllocationHeader));
}
fn release(opaque_pointer: ?*anyopaque, address: ?*anyopaque) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(opaque_pointer orelse return));
    const payload: [*]u8 = @ptrCast(address orelse return);
    const memory = payload - @sizeOf(AllocationHeader);
    const header: *const AllocationHeader = @ptrCast(@alignCast(memory));
    self.engine.gpa.rawFree(memory[0..header.bytes], .@"16", @returnAddress());
}
fn state(value: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    self.end();
    c.JS_FreeValueRT(runtime, self.owner);
    c.JS_FreeValueRT(runtime, self.readable);
    c.JS_FreeValueRT(runtime, self.writable);
    self.engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, self.owner, visit);
    c.JS_MarkValue(runtime, self.readable, visit);
    c.JS_MarkValue(runtime, self.writable, visit);
}
fn classId(scope: *Scope, owner: c.JSValue, decompress: bool) !c.JSClassID {
    const value = try scope.get(owner, if (decompress) "decompressClass" else "compressClass");
    var result: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &result, value) < 0) return js.capture(scope.engine);
    return result;
}
fn nativeError(scope: *Scope, owner: c.JSValue, message: []const u8, code: []const u8, errno: ?c_int, type_error: bool) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(message)};
    const result = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(owner, if (type_error) "TypeError" else "Error"), 1, &args)));
    if (errno) |number| try scope.put(result, "errno", c.JS_NewInt32(scope.engine.context, number));
    try scope.put(result, "code", try scope.text(code));
    return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, result)));
}
fn codecError(scope: *Scope, self: *State, result: c_int) !c.JSValue {
    if (result == z.Z_MEM_ERROR) return error.OutOfMemory;
    const code: []const u8 = switch (result) {
        z.Z_NEED_DICT => "Z_NEED_DICT",
        z.Z_DATA_ERROR => "Z_DATA_ERROR",
        z.Z_BUF_ERROR => "Z_BUF_ERROR",
        z.Z_VERSION_ERROR => "Z_VERSION_ERROR",
        else => "Z_STREAM_ERROR",
    };
    const message: []const u8 = if (self.stream.msg != null) std.mem.span(self.stream.msg) else if (result == z.Z_BUF_ERROR) "unexpected end of file" else if (result == z.Z_NEED_DICT) "Missing dictionary" else "zlib stream error";
    var cause_args = [_]c.JSValue{try scope.text(message)};
    const cause = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(self.owner, "Error"), 1, &cause_args)));
    try scope.put(cause, "errno", c.JS_NewInt32(scope.engine.context, result));
    try scope.put(cause, "code", try scope.text(code));
    // Actual Node duplex web adapters wrap every zlib failure in TypeError
    // with a non-enumerable cause and retain the original codec code.
    const options = try scope.object();
    try scope.put(options, "cause", cause);
    var args = [_]c.JSValue{ c.pi_js_undefined(), options };
    const wrapped = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(self.owner, "TypeError"), args.len, &args)));
    try scope.put(wrapped, "code", try scope.text(code));
    return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, wrapped)));
}
fn output(scope: *Scope, controller: c.JSValue, bytes: []const u8) !void {
    if (bytes.len == 0) return;
    const backing = try scope.engine.checked(c.JS_NewArrayBufferCopy(scope.engine.context, bytes.ptr, bytes.len));
    defer scope.engine.freeValue(backing);
    var args = [_]c.JSValue{backing};
    const chunk = try scope.engine.checked(c.JS_NewTypedArray(scope.engine.context, args.len, &args, c.JS_TYPED_ARRAY_UINT8));
    defer scope.engine.freeValue(chunk);
    try transform.enqueueNative(scope.engine, controller, chunk);
}
fn windowBits(format: Format) c_int {
    return switch (format) {
        .gzip => 31,
        .deflate => 15,
        .raw => -15,
    };
}
fn process(scope: *Scope, self: *State, controller: c.JSValue, input: []const u8, finish: bool) !void {
    if (!self.initialized) return error.CompressionStreamClosed;
    // No guest call can invalidate this native copy while zlib retains next_in.
    const copied = try scope.engine.gpa.dupe(u8, input);
    defer scope.engine.gpa.free(copied);
    defer {
        self.stream.next_in = null;
        self.stream.avail_in = 0;
    }
    var position: usize = 0;
    var output_buffer: [16384]u8 = undefined;
    while (true) {
        if (self.decompress and self.ended) {
            if (self.format == .raw) return; // Actual Node InflateRaw ignores bytes after its first end marker.
            if (position < copied.len) {
                if (self.format == .deflate) {
                    _ = try nativeError(scope, self.owner, "Trailing junk found after the end of the compressed stream", "ERR_TRAILING_JUNK_AFTER_STREAM_END", null, true);
                    unreachable;
                }
                if (copied[position] == 0) {
                    _ = try nativeError(scope, self.owner, "Trailing junk found after the end of the compressed stream", "ERR_TRAILING_JUNK_AFTER_STREAM_END", null, true);
                    unreachable;
                }
                const reset = z.inflateReset2(&self.stream, windowBits(self.format));
                if (reset != z.Z_OK) {
                    _ = try codecError(scope, self, reset);
                    unreachable;
                }
                self.ended = false;
            } else return;
        }
        const amount: c_uint = @intCast(@min(copied.len - position, std.math.maxInt(c_uint)));
        self.stream.next_in = if (amount == 0) null else copied.ptr + position;
        self.stream.avail_in = amount;
        self.stream.next_out = &output_buffer;
        self.stream.avail_out = output_buffer.len;
        const result = if (self.decompress) z.inflate(&self.stream, if (finish) z.Z_FINISH else z.Z_NO_FLUSH) else z.deflate(&self.stream, if (finish) z.Z_FINISH else z.Z_NO_FLUSH);
        const consumed = amount - self.stream.avail_in;
        position += consumed;
        const produced = output_buffer.len - self.stream.avail_out;
        if (result != z.Z_OK and result != z.Z_STREAM_END and result != z.Z_BUF_ERROR) {
            _ = try codecError(scope, self, result);
            unreachable;
        }
        try output(scope, controller, output_buffer[0..produced]);
        if (result == z.Z_STREAM_END) {
            self.ended = true;
            if (!self.decompress) return;
            continue;
        }
        if (position < copied.len) {
            if (consumed == 0 and produced == 0) {
                _ = try codecError(scope, self, z.Z_BUF_ERROR);
                unreachable;
            }
            continue;
        }
        if (self.stream.avail_out == 0) continue;
        if (finish) {
            _ = try codecError(scope, self, z.Z_BUF_ERROR);
            unreachable;
        }
        return;
    }
}
const Input = struct { backing: c.JSValue, bytes: []const u8, string: ?[]u8 = null };
fn inputBytes(scope: *Scope, owner: c.JSValue, value: c.JSValue) !Input {
    if (c.JS_IsString(value)) {
        const text = try scope.engine.toString(value);
        return .{ .backing = c.pi_js_undefined(), .bytes = text, .string = text };
    }
    if (!scope.truthy(try scope.call(try scope.get(owner, "isView"), c.pi_js_undefined(), &.{value}))) {
        const received = try transform.receivedDescription(scope.engine, value);
        defer scope.engine.gpa.free(received);
        const message = try std.fmt.allocPrint(scope.engine.gpa, "The \"chunk\" argument must be of type string or an instance of Buffer, TypedArray, or DataView. Received {s}", .{received});
        defer scope.engine.gpa.free(message);
        return nativeError(scope, owner, message, "ERR_INVALID_ARG_TYPE", null, true);
    }
    var actual_view = value;
    var buffer_instance = false;
    if (scope.engine.buffer_prototype) |buffer_prototype| {
        var prototype = try scope.own(try scope.engine.checked(c.JS_GetPrototype(scope.engine.context, value)));
        while (c.JS_IsObject(prototype)) {
            if (scope.equal(prototype, buffer_prototype)) {
                buffer_instance = true;
                break;
            }
            prototype = try scope.own(try scope.engine.checked(c.JS_GetPrototype(scope.engine.context, prototype)));
        }
    }
    if (!buffer_instance) {
        // Node Stream._uint8ArrayToBuffer proves the intrinsic view brand, then
        // reads these three public properties in order to create FastBuffer.
        const public_buffer = try scope.get(value, "buffer");
        const public_offset = try scope.get(value, "byteOffset");
        const public_length = try scope.get(value, "byteLength");
        var args = [_]c.JSValue{ public_buffer, public_offset, public_length };
        actual_view = try scope.own(try scope.engine.checked(c.JS_NewTypedArray(scope.engine.context, args.len, &args, c.JS_TYPED_ARRAY_UINT8)));
    }
    var offset: usize = 0;
    var length: usize = 0;
    var element: usize = 0;
    const backing = try scope.own(try scope.engine.checked(c.JS_GetTypedArrayBuffer(scope.engine.context, actual_view, &offset, &length, &element)));
    var total: usize = 0;
    const pointer = c.JS_GetArrayBuffer(scope.engine.context, &total, backing);
    if (pointer == null and c.JS_HasException(scope.engine.context)) return js.capture(scope.engine);
    if (offset > total or length > total - offset) return error.CompressionViewOutOfBounds;
    return .{ .backing = backing, .bytes = if (length == 0) &.{} else pointer[offset..][0..length] };
}
fn callback(scope: *Scope, root: c.JSValue, op: Op, name: [*:0]const u8, length: c_int) !c.JSValue {
    var roots = [_]c.JSValue{root};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(op), roots.len, &roots)));
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), roots[0]) catch |err| durable.reject(engine, err);
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, op: Op, root: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (op == .byte_size) return js.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), "byteLength");
    if (op == .compress_readable or op == .compress_writable or op == .decompress_readable or op == .decompress_writable) {
        const decompress = op == .decompress_readable or op == .decompress_writable;
        if (c.JS_GetOpaque(receiver, try classId(&scope, root, decompress)) == null) return engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read private member #transform from an object whose class did not declare it"));
        const self = state(receiver);
        return c.JS_DupValue(engine.context, if (op == .compress_readable or op == .decompress_readable) self.readable else self.writable);
    }
    const self = state(root);
    if (op == .cancel) {
        self.end();
        return c.pi_js_undefined();
    }
    if (op == .flush) {
        process(&scope, self, if (args.len > 0) args[0] else c.pi_js_undefined(), &.{}, true) catch |err| {
            self.end();
            return err;
        };
        self.end();
        return c.pi_js_undefined();
    }
    const input = inputBytes(&scope, self.owner, if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| {
        self.end();
        return err;
    };
    defer if (input.string) |memory| engine.gpa.free(memory);
    process(&scope, self, if (args.len > 1) args[1] else c.pi_js_undefined(), input.bytes, false) catch |err| {
        self.end();
        return err;
    };
    return c.pi_js_undefined();
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = roots[0];
    const decompress = c.JS_ToBool(engine.context, roots[1]) == 1;
    const format_value = try scope.call(try scope.get(owner, "String"), c.pi_js_undefined(), &.{if (args.len > 0) args[0] else c.pi_js_undefined()});
    const format_name = try engine.toString(format_value);
    defer engine.gpa.free(format_name);
    const format: Format = if (std.mem.eql(u8, format_name, "gzip")) .gzip else if (std.mem.eql(u8, format_name, "deflate")) .deflate else if (std.mem.eql(u8, format_name, "deflate-raw")) .raw else {
        const message = try std.fmt.allocPrint(engine.gpa, "Failed to construct '{s}': 1st argument value '{s}' is not a valid enum value of type CompressionFormat.", .{ if (decompress) "DecompressionStream" else "CompressionStream", format_name });
        defer engine.gpa.free(message);
        return nativeError(&scope, owner, message, "ERR_INVALID_ARG_VALUE", null, true);
    };
    const prototype = try scope.get(target, "prototype");
    const actual_prototype = if (c.JS_IsObject(prototype)) prototype else try scope.get(owner, if (decompress) "decompressPrototype" else "compressPrototype");
    const instance = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, actual_prototype, try classId(&scope, owner, decompress))));
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner), .readable = c.pi_js_undefined(), .writable = c.pi_js_undefined(), .stream = std.mem.zeroes(z.z_stream), .format = format, .decompress = decompress };
    _ = c.JS_SetOpaque(instance, self);
    self.stream.zalloc = allocate;
    self.stream.zfree = release;
    self.stream.@"opaque" = self;
    const result = if (decompress) z.inflateInit2_(&self.stream, windowBits(format), z.ZLIB_VERSION, @sizeOf(z.z_stream)) else z.deflateInit2_(&self.stream, z.Z_DEFAULT_COMPRESSION, z.Z_DEFLATED, windowBits(format), 8, z.Z_DEFAULT_STRATEGY, z.ZLIB_VERSION, @sizeOf(z.z_stream));
    if (result != z.Z_OK) return codecError(&scope, self, result);
    self.initialized = true;
    const transformer = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(transformer, "transform", try callback(&scope, instance, .chunk, "transform", 2));
    try scope.put(transformer, "flush", try callback(&scope, instance, .flush, "flush", 1));
    try scope.put(transformer, "cancel", try callback(&scope, instance, .cancel, "cancel", 1));
    const writable_strategy = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    const readable_strategy = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    // Node24's duplex-to-web adapters use the native zlib stream's 64KiB HWM;
    // readable accounting is byteLength, writable web accounting is per chunk.
    try scope.put(writable_strategy, "highWaterMark", c.JS_NewInt32(engine.context, 65536));
    try scope.put(readable_strategy, "highWaterMark", c.JS_NewInt32(engine.context, 65536));
    try scope.put(readable_strategy, "size", try callback(&scope, owner, .byte_size, "size", 1));
    const pair = try scope.own(try transform.createNative(engine, transformer, writable_strategy, readable_strategy));
    self.readable = try transform.readableNative(engine, pair);
    self.writable = try transform.writableNative(engine, pair);
    return c.JS_DupValue(engine.context, instance);
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(module_key)) return;
    try transform.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    inline for (.{ "String", "Error", "TypeError" }) |name| try scope.put(owner, name, try scope.global(name));
    try scope.put(owner, "isView", try scope.get(try scope.global("ArrayBuffer"), "isView"));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    inline for (.{ false, true }, .{ "CompressionStream", "DecompressionStream" }, .{ "compressClass", "decompressClass" }, .{ "compressPrototype", "decompressPrototype" }) |decompress, name, class_key, prototype_key| {
        var class_id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class_id);
        const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
        try scope.put(owner, class_key, c.JS_NewUint32(engine.context, class_id));
        const prototype = try scope.object();
        try scope.put(owner, prototype_key, prototype);
        const constructor = try scope.own(try @import("native_class.zig").constructor(engine, name, 1, prototype, construct, &.{ owner, c.pi_js_bool(engine.context, @intFromBool(decompress)) }));
        inline for (.{ "readable", "writable" }, .{ "get readable", "get writable" }, .{ if (decompress) Op.decompress_readable else Op.compress_readable, if (decompress) Op.decompress_writable else Op.compress_writable }) |property, function_name, op| {
            const atom = c.JS_NewAtom(engine.context, property);
            if (atom == c.JS_ATOM_NULL) return js.capture(engine);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, try callback(&scope, owner, op, function_name, 0)), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        }
        const tag_atom = try js.atom(engine, try scope.get(try scope.global("Symbol"), "toStringTag"));
        defer c.JS_FreeAtom(engine.context, tag_atom);
        if (c.JS_DefinePropertyValue(engine.context, prototype, tag_atom, c.JS_DupValue(engine.context, try scope.text(name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        try scope.put(owner, name, constructor);
        if (c.JS_DefinePropertyValueStr(engine.context, global, name, c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try engine.registerValueModule(module_key, owner);
}
/// Owned namespace containing the actual original captured codec constructors.
/// The complete node:stream/web assembler owns its final namespace descriptors.
pub fn exports(engine: *em.Engine) !c.JSValue {
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = engine.native_module_values.get(module_key).?;
    const result = try scope.object();
    inline for (.{ "CompressionStream", "DecompressionStream" }) |name| try scope.put(result, name, try scope.get(owner, name));
    return c.JS_DupValue(engine.context, result);
}

//! Pi's WebCrypto host: genuine native Crypto/SubtleCrypto identity brands,
//! secure random bytes/UUIDs and the SHA digest algorithms used by OAuth PKCE.
//! Other cryptographic operations are intentionally absent, not fake stubs.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
const prefix = "Failed to execute 'digest' on 'SubtleCrypto'";
const Method = enum(c_int) { random, uuid, subtle, digest, global_crypto };

fn getter(scope: *Scope, prototype: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(scope.engine.context, &descriptor, prototype, atom);
    if (found < 0) return js.capture(scope.engine);
    if (found == 0) return error.MissingCryptoIntrinsic;
    defer scope.engine.freeValue(descriptor.value);
    defer scope.engine.freeValue(descriptor.setter);
    return scope.own(descriptor.getter);
}
fn function(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, length: c_int, kind: Method) !c.JSValue {
    var roots = [_]c.JSValue{owner};
    const result = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(kind), 1, &roots)));
    if (kind == .digest) {
        const parent = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, result, parent) < 0) return js.capture(scope.engine);
    }
    return result;
}
fn tag(scope: *Scope, prototype: c.JSValue, name: []const u8) !void {
    const atom = try js.atom(scope.engine, try scope.get(try scope.global("Symbol"), "toStringTag"));
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, try scope.text(name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
}
fn codedError(scope: *Scope, owner: c.JSValue, message: []const u8, code: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(message)};
    const value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(owner, "typeError"), 1, &args)));
    try scope.put(value, "code", try scope.text(code));
    return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value)));
}
fn domError(engine: *em.Engine, name: []const u8, message: []const u8) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, try @import("dom_exception.zig").create(engine, message, name)));
}
fn illegal(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return codedError(&scope, roots[0], "Illegal constructor", "ERR_ILLEGAL_CONSTRUCTOR");
}
fn make(scope: *Scope) !c.JSValue {
    const engine = scope.engine;
    const owner = try scope.object();
    try scope.put(owner, "typeError", try scope.global("TypeError"));
    try scope.put(owner, "rangeError", try scope.global("RangeError"));
    const crypto_prototype = try scope.object();
    const subtle_prototype = try scope.object();
    const crypto = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, crypto_prototype)));
    const subtle = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, subtle_prototype)));
    try scope.put(owner, "crypto", crypto);
    try scope.put(owner, "subtle", subtle);
    const class = @import("native_class.zig");
    const crypto_constructor = try scope.own(try class.constructor(engine, "Crypto", 0, crypto_prototype, illegal, &.{owner}));
    const subtle_constructor = try scope.own(try class.constructor(engine, "SubtleCrypto", 0, subtle_prototype, illegal, &.{owner}));
    try scope.put(owner, "Crypto", crypto_constructor);
    try scope.put(owner, "SubtleCrypto", subtle_constructor);
    try tag(scope, crypto_prototype, "Crypto");
    try tag(scope, subtle_prototype, "SubtleCrypto");
    // Node's random methods are ordinary functions with own prototypes, while
    // digest is an async, nonconstructible function with AsyncFunction lineage.
    const nf = @import("native_node_function.zig");
    try scope.put(crypto_prototype, "getRandomValues", try scope.own(try nf.create(engine, "getRandomValues", 1, random, &.{owner})));
    try scope.put(crypto_prototype, "randomUUID", try scope.own(try nf.create(engine, "randomUUID", 0, uuid, &.{owner})));
    try scope.put(subtle_prototype, "digest", try function(scope, owner, "digest", 2, .digest));
    const subtle_getter = try function(scope, owner, "get subtle", 0, .subtle);
    const atom = c.JS_NewAtom(engine.context, "subtle");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, crypto_prototype, atom, c.JS_DupValue(engine.context, subtle_getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    // Capture BufferSource brands and intrinsic accessors before guest code can
    // replace globals/prototypes. Public data.byteLength stays guest-observable.
    const array_buffer = try scope.global("ArrayBuffer");
    try scope.put(owner, "isView", try scope.get(array_buffer, "isView"));
    const typed_prototype = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, try scope.get(try scope.global("Uint8Array"), "prototype"))));
    const data_prototype = try scope.get(try scope.global("DataView"), "prototype");
    inline for (.{ "buffer", "byteOffset", "byteLength" }, .{ "typedBuffer", "typedOffset", "typedLength" }, .{ "dataBuffer", "dataOffset", "dataLength" }) |name, typed_name, data_name| {
        try scope.put(owner, typed_name, try getter(scope, typed_prototype, name));
        try scope.put(owner, data_name, try getter(scope, data_prototype, name));
    }
    return owner;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    if (engine.dom_exception_class == 0) try @import("dom_exception.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try scope.get(try make(&scope), "crypto"));
}
pub fn install(engine: *em.Engine) !void {
    if (engine.dom_exception_class == 0) try @import("dom_exception.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try make(&scope);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    inline for (.{ "Crypto", "SubtleCrypto" }) |name| {
        if (c.JS_DefinePropertyValueStr(engine.context, global, name, c.JS_DupValue(engine.context, try scope.get(owner, name)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const atom = c.JS_NewAtom(engine.context, "crypto");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, global, atom, c.JS_DupValue(engine.context, try function(&scope, owner, "get crypto", 0, .global_crypto)), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
}
fn brand(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, subtle: bool) !void {
    if (!scope.equal(receiver, try scope.get(owner, if (subtle) "subtle" else "crypto"))) {
        _ = try codedError(scope, owner, if (subtle) "Value of \"this\" must be of type SubtleCrypto" else "Value of \"this\" must be of type Crypto", "ERR_INVALID_THIS");
    }
}
fn random(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return @import("native_crypto_random.zig").fill(engine, receiver, roots[0], args);
}
fn uuid(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try brand(&scope, roots[0], receiver, false);
    var bytes: [16]u8 = undefined;
    try std.Io.randomSecure(engine.native_io orelse return error.NativeCryptoIoRequired, &bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = std.fmt.bytesToHex(bytes, .lower);
    var result: [36]u8 = undefined;
    _ = try std.fmt.bufPrint(&result, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
    return engine.checked(c.JS_NewStringLen(engine.context, &result, result.len));
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const kind: Method = @enumFromInt(magic);
    const value = invoke(engine, roots[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, kind) catch |err| {
        return if (kind == .digest) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
    };
    return value;
}
fn invoke(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, kind: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (kind) {
        .global_crypto => return c.JS_DupValue(engine.context, try scope.get(owner, "crypto")),
        .subtle => {
            try brand(&scope, owner, receiver, false);
            return c.JS_DupValue(engine.context, try scope.get(owner, "subtle"));
        },
        .digest => return digest(&scope, owner, receiver, args),
        else => unreachable,
    }
}
fn domString(scope: *Scope, owner: c.JSValue, value: c.JSValue, normalization: bool) !c.JSValue {
    if (c.JS_IsSymbol(value)) return codedError(scope, owner, if (normalization) "Failed to normalize algorithm: 'name' of 'Algorithm' (passed algorithm) is a Symbol and cannot be converted to a string." else prefix ++ ": 1st argument is a Symbol and cannot be converted to a string.", "ERR_INVALID_ARG_TYPE");
    return scope.stringify(value);
}
fn dataLength(scope: *Scope, owner: c.JSValue, data: c.JSValue) !c.JSValue {
    // Node and QuickJS use different diagnostics for the intrinsic DataView
    // getter. Identify that actual getter by descriptor identity, so an own or
    // inherited guest getter (including one throwing an Error) is untouched.
    const engine = scope.engine;
    const atom = c.JS_NewAtom(engine.context, "byteLength");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    var current = data;
    var intrinsic = false;
    while (c.JS_IsObject(current)) {
        var descriptor: c.JSPropertyDescriptor = undefined;
        const found = c.JS_GetOwnProperty(engine.context, &descriptor, current, atom);
        if (found < 0) return js.capture(engine);
        if (found != 0) {
            defer engine.freeValue(descriptor.value);
            defer engine.freeValue(descriptor.getter);
            defer engine.freeValue(descriptor.setter);
            intrinsic = scope.equal(descriptor.getter, try scope.get(owner, "dataLength"));
            break;
        }
        current = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, current)));
    }
    return scope.get(data, "byteLength") catch |err| {
        if (!intrinsic or err != error.JavaScriptException) return err;
        // Only translate the actual detached backing-store diagnostic. An
        // allocator failure while invoking this intrinsic must remain OOM.
        if (engine.captured_exception) |exception| {
            if (c.pi_js_native_allocation_error_generation(exception) != 0) return err;
        }
        const backing = try scope.call(try scope.get(owner, "dataBuffer"), data, &.{});
        var total: usize = 0;
        _ = c.JS_GetArrayBuffer(engine.context, &total, backing);
        if (!c.JS_HasException(engine.context)) return err;
        engine.freeValue(c.JS_GetException(engine.context));
        return @import("native_js_values.zig").typeError(engine, "Cannot perform get DataView.prototype.byteLength on a detached ArrayBuffer");
    };
}
fn settleDigest(context: ?*c.JSContext, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    // VM jobs retain/mark these genuine values until execution or teardown.
    return c.JS_Call(context, roots[0], c.pi_js_undefined(), 1, &roots[1]);
}
fn digestPromise(scope: *Scope, value: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    var functions: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
    defer for (functions) |function_value| engine.freeValue(function_value);
    var roots = [_]c.JSValue{ functions[0], value };
    if (c.JS_EnqueueJob(engine.context, settleDigest, roots.len, &roots) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, promise);
}
fn digest(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const engine = scope.engine;
    try brand(scope, owner, receiver, true);
    if (args.len < 2) {
        const message = try std.fmt.allocPrint(engine.gpa, prefix ++ ": 2 arguments required, but only {d} present.", .{args.len});
        defer engine.gpa.free(message);
        return codedError(scope, owner, message, "ERR_MISSING_ARGS");
    }
    const algorithm = if (c.JS_IsObject(args[0])) args[0] else try domString(scope, owner, args[0], false);
    const data = args[1];
    const view = scope.truthy(try scope.call(try scope.get(owner, "isView"), c.pi_js_undefined(), &.{data}));
    const typed = c.JS_GetTypedArrayType(data) >= 0;
    const backing = if (view) try scope.call(try scope.get(owner, if (typed) "typedBuffer" else "dataBuffer"), data, &.{}) else data;
    if (!c.JS_IsArrayBuffer(backing)) return codedError(scope, owner, if (view) prefix ++ ": 2nd argument is a view on a SharedArrayBuffer, which is not allowed." else prefix ++ ": 2nd argument is not instance of ArrayBuffer, Buffer, TypedArray, or DataView.", "ERR_INVALID_ARG_TYPE");
    const name_value = if (c.JS_IsString(algorithm)) algorithm else try scope.get(algorithm, "name");
    if (c.JS_IsUndefined(name_value)) return codedError(scope, owner, "Failed to normalize algorithm: passed algorithm can not be converted to 'Algorithm' because 'name' is required in 'Algorithm'.", "ERR_MISSING_OPTION");
    const name = try engine.toString(try domString(scope, owner, name_value, true));
    defer engine.gpa.free(name);
    const Hash = enum { sha1, sha256, sha384, sha512 };
    var hash: ?Hash = null;
    inline for (.{ "SHA-1", "SHA-256", "SHA-384", "SHA-512" }, .{ Hash.sha1, Hash.sha256, Hash.sha384, Hash.sha512 }) |candidate, selected| {
        if (std.ascii.eqlIgnoreCase(name, candidate)) hash = selected;
    }
    if (hash == null) return domError(engine, "NotSupportedError", "Unrecognized algorithm name");
    // The Node asyncDigest body reads the guest's public byteLength before its
    // HashJob obtains the backing store. Getter exceptions retain identity.
    const public_length = if (view and !typed) try dataLength(scope, owner, data) else try scope.get(data, "byteLength");
    if (try @import("native_image_arithmetic.zig").compare(engine, .greater, public_length, c.JS_NewInt64(engine.context, 2147483647))) return domError(engine, "OperationError", "data must be less than 2147483648 bits");
    var offset: usize = 0;
    var length: usize = 0;
    if (view) {
        const offset_value = try scope.call(try scope.get(owner, if (typed) "typedOffset" else "dataOffset"), data, &.{});
        const length_value = try scope.call(try scope.get(owner, if (typed) "typedLength" else "dataLength"), data, &.{});
        var numeric_offset: i64 = 0;
        var numeric_length: i64 = 0;
        if (c.JS_ToInt64(engine.context, &numeric_offset, offset_value) < 0 or c.JS_ToInt64(engine.context, &numeric_length, length_value) < 0) return js.capture(engine);
        offset = @intCast(numeric_offset);
        length = @intCast(numeric_length);
    }
    var total: usize = 0;
    const bytes = c.JS_GetArrayBuffer(engine.context, &total, backing);
    if (bytes == null and c.JS_HasException(engine.context)) {
        // Node's HashJob accepts a genuine detached ArrayBuffer or integer/
        // float typed view as an empty input. DataView's observable length
        // getter has already rejected above. Do not turn an invalid brand into
        // empty bytes: the BufferSource conversion proved this backing brand.
        engine.freeValue(c.JS_GetException(engine.context));
        total = 0;
    }
    if (!view) length = total;
    if (offset > total or length > total - offset) return error.InvalidCryptoByteView;
    // No guest call is permitted between obtaining the byte pointer and hash.
    const input: []const u8 = if (length == 0) &.{} else bytes[offset..][0..length];
    var output: [64]u8 = undefined;
    const output_length: usize = switch (hash.?) {
        .sha1 => blk: {
            std.crypto.hash.Sha1.hash(input, output[0..20], .{});
            break :blk 20;
        },
        .sha256 => blk: {
            std.crypto.hash.sha2.Sha256.hash(input, output[0..32], .{});
            break :blk 32;
        },
        .sha384 => blk: {
            std.crypto.hash.sha2.Sha384.hash(input, output[0..48], .{});
            break :blk 48;
        },
        .sha512 => blk: {
            std.crypto.hash.sha2.Sha512.hash(input, output[0..64], .{});
            break :blk 64;
        },
    };
    const result = try scope.own(try engine.checked(c.JS_NewArrayBufferCopy(engine.context, &output, output_length)));
    return digestPromise(scope, result);
}

//! Stateful SHA256 node:crypto dependency used by actual PackageManager storage.
//! The public namespace is deliberately limited to createHash("sha256") with
//! omitted options. Streams, copy, other algorithms/options and reflective
//! Node-internal symbols are outside this native contract, never fake stubs.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const nf = @import("native_node_function.zig");
const allocation = @import("native_async_body.zig");
const encoding = @import("binary_encoding.zig");
const c = em.c;
const Sha256 = std.crypto.hash.sha2.Sha256;
const State = struct {
    engine: *em.Engine,
    hash: Sha256 = Sha256.init(.{}),
    digest: [Sha256.digest_length]u8 = undefined,
    cached: bool = false,
    finalized: bool = false,
};
const Owner = struct {
    engine: *em.Engine,
    hash_class: c.JSClassID,
    prototype: c.JSValue,
    error_constructor: c.JSValue,
    type_error_constructor: c.JSValue,
    data_getters: [3]c.JSValue,
};
const Operation = enum { create, update, digest };
fn owner(value: c.JSValue) *Owner {
    // Only GC-visible roots installed by this module reach this function.
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn freeHash(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    state.engine.gpa.destroy(state);
}
fn freeOwner(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    c.JS_FreeValueRT(runtime, state.error_constructor);
    c.JS_FreeValueRT(runtime, state.type_error_constructor);
    for (state.data_getters) |value_root| c.JS_FreeValueRT(runtime, value_root);
    state.engine.gpa.destroy(state);
}
fn markOwner(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, marker);
    c.JS_MarkValue(runtime, state.error_constructor, marker);
    c.JS_MarkValue(runtime, state.type_error_constructor, marker);
    for (state.data_getters) |value_root| c.JS_MarkValue(runtime, value_root, marker);
}
fn class(engine: *em.Engine, definition: *const c.JSClassDef) !c.JSClassID {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    if (c.JS_NewClass(engine.runtime, id, definition) < 0) return error.OutOfMemory;
    return id;
}
fn getter(s: *Scope, prototype: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const atom = c.JS_NewAtom(s.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(s.engine.context, &descriptor, prototype, atom);
    if (found < 0) return js.capture(s.engine);
    if (found == 0) return error.RequiredNativeCryptoDataViewIntrinsic;
    defer s.engine.freeValue(descriptor.value);
    defer s.engine.freeValue(descriptor.setter);
    return s.own(descriptor.getter);
}
pub fn create(engine: *em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const hash_class = try class(engine, &.{ .class_name = "Hash", .finalizer = freeHash });
    const owner_class = try class(engine, &.{ .class_name = "Private SHA256 module", .finalizer = freeOwner, .gc_mark = markOwner });
    const prototype = try s.object();
    const error_constructor = try s.global("Error");
    const type_error_constructor = try s.global("TypeError");
    const data_prototype = try s.get(try s.global("DataView"), "prototype");
    var getters: [3]c.JSValue = undefined;
    inline for (.{ "buffer", "byteOffset", "byteLength" }, 0..) |name, index| getters[index] = try getter(&s, data_prototype, name);
    const capture = try s.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, c.pi_js_null(), owner_class)));
    const state = try engine.gpa.create(Owner);
    state.* = .{ .engine = engine, .hash_class = hash_class, .prototype = c.JS_DupValue(engine.context, prototype), .error_constructor = c.JS_DupValue(engine.context, error_constructor), .type_error_constructor = c.JS_DupValue(engine.context, type_error_constructor), .data_getters = undefined };
    for (getters, 0..) |value, index| state.data_getters[index] = c.JS_DupValue(engine.context, value);
    _ = c.JS_SetOpaque(capture, state);
    // The real native constructor returns the same opaque Hash class as the
    // factory. The prototype/constructor/function roots are traced by the VM.
    const constructor = try s.own(try nf.create(engine, "Hash", 2, Adapter(.create).call, &.{capture}));
    if (c.JS_SetPropertyStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype)) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (.{ .{ "update", Operation.update, 2 }, .{ "digest", Operation.digest, 1 } }) |entry| {
        const function = try s.own(try nf.create(engine, entry[0], entry[2], Adapter(entry[1]).call, &.{capture}));
        try js.define(engine, prototype, entry[0], c.JS_DupValue(engine.context, function));
    }
    const result = try s.object();
    try js.define(engine, result, "createHash", try nf.create(engine, "createHash", 2, Adapter(.create).call, &.{capture}));
    return c.JS_DupValue(engine.context, result);
}
fn Adapter(comptime operation: Operation) type {
    return struct {
        fn call(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const generation = engine.native_allocation_generation;
            return invoke(engine, owner(roots[0]), operation, receiver, args) catch |err| {
                // Source has no forgiving catch. A fresh privately tagged
                // reason crosses this leaf unchanged and remains uncatchable.
                if (err == error.JavaScriptException) if (engine.captured_exception) |reason| try allocation.rethrowRecognizedAllocation(engine, reason, generation);
                return err;
            };
        }
    };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn coded(s: *Scope, state: *Owner, type_error: bool, message: []const u8, code: []const u8) !c.JSValue {
    const text = try s.text(message);
    const constructor = if (type_error) state.type_error_constructor else state.error_constructor;
    const reason = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 1, @constCast(&text))));
    try js.define(s.engine, reason, "code", c.JS_DupValue(s.engine.context, try s.text(code)));
    return s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason)));
}
fn unsupported(s: *Scope, state: *Owner, message: []const u8, code: []const u8) !c.JSValue { return coded(s, state, true, message, code); }
fn makeHash(s: *Scope, state: *Owner, args: []const c.JSValue) !c.JSValue {
    if (!c.JS_IsString(arg(args, 0))) return unsupported(s, state, "Native createHash supports the string algorithm sha256 only", "PI_UNSUPPORTED_CRYPTO_ALGORITHM");
    const algorithm = try s.engine.toString(arg(args, 0));
    defer s.engine.gpa.free(algorithm);
    if (!std.mem.eql(u8, algorithm, "sha256")) return unsupported(s, state, "Native createHash supports the string algorithm sha256 only", "PI_UNSUPPORTED_CRYPTO_ALGORITHM");
    if (!c.JS_IsUndefined(arg(args, 1))) return unsupported(s, state, "Native SHA256 createHash requires omitted options", "PI_UNSUPPORTED_CRYPTO_OPTIONS");
    const result = try s.engine.checked(c.JS_NewObjectProtoClass(s.engine.context, state.prototype, state.hash_class));
    errdefer s.engine.freeValue(result);
    const hash = try s.engine.gpa.create(State);
    hash.* = .{ .engine = s.engine };
    _ = c.JS_SetOpaque(result, hash);
    return result;
}
fn inputEncoding(s: *Scope, state: *Owner, value: c.JSValue) !encoding.Encoding {
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return .utf8;
    if (!c.JS_IsString(value)) { _ = try unsupported(s, state, "Native SHA256 update encoding must be a supported string", "PI_UNSUPPORTED_CRYPTO_ENCODING"); unreachable; }
    const name = try s.engine.toString(value);
    defer s.engine.gpa.free(name);
    if (name.len == 0) return .utf8;
    return encoding.parse(name) orelse { _ = try unsupported(s, state, "Native SHA256 update encoding is unsupported", "PI_UNSUPPORTED_CRYPTO_ENCODING"); unreachable; };
}
fn update(s: *Scope, state: *Owner, hash: *State, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const data = arg(args, 0);
    if (c.JS_IsString(data)) {
        const codec = try inputEncoding(s, state, arg(args, 1));
        if (codec == .hex) {
            const length_value = try s.get(data, "length");
            var length: i64 = 0;
            if (c.JS_ToInt64(s.engine.context, &length, length_value) < 0) return js.capture(s.engine);
            if (@mod(length, 2) != 0) {
                const name = try s.engine.toString(arg(args, 1));
                defer s.engine.gpa.free(name);
                const message = try std.fmt.allocPrint(s.engine.gpa, "The argument 'encoding' is invalid for data of length {d}. Received '{s}'", .{ length, name });
                defer s.engine.gpa.free(message);
                return coded(s, state, true, message, "ERR_INVALID_ARG_VALUE");
            }
        }
        const text = try s.engine.toString(data);
        defer s.engine.gpa.free(text);
        const bytes = try encoding.encode(s.engine.gpa, text, codec);
        defer s.engine.gpa.free(bytes);
        hash.hash.update(bytes);
    } else {
        const typed = c.JS_GetTypedArrayType(data) >= 0;
        var offset: usize = 0;
        var length: usize = 0;
        const backing = if (typed) try s.own(try s.engine.checked(c.JS_GetTypedArrayBuffer(s.engine.context, data, &offset, &length, null))) else blk: {
            // A captured intrinsic getter proves a genuine DataView; public
            // buffer/offset/length getters never participate in native update.
            const value = try s.call(state.data_getters[0], data, &.{});
            const offset_value = try s.call(state.data_getters[1], data, &.{});
            const length_value = try s.call(state.data_getters[2], data, &.{});
            var raw_offset: i64 = 0;
            var raw_length: i64 = 0;
            if (c.JS_ToInt64(s.engine.context, &raw_offset, offset_value) < 0 or c.JS_ToInt64(s.engine.context, &raw_length, length_value) < 0) return js.capture(s.engine);
            if (raw_offset < 0 or raw_length < 0) return error.InvalidNativeHashByteView;
            offset = @intCast(raw_offset); length = @intCast(raw_length);
            break :blk value;
        };
        var total: usize = 0;
        const bytes = c.JS_GetArrayBuffer(s.engine.context, &total, backing);
        if (c.JS_HasException(s.engine.context)) return js.capture(s.engine);
        if (offset > total or length > total - offset or (bytes == null and length != 0)) return error.InvalidNativeHashByteView;
        // No guest calls or allocations occur while the backing pointer is used.
        hash.hash.update(if (length == 0) &.{} else bytes[offset..][0..length]);
    }
    return c.JS_DupValue(s.engine.context, receiver);
}
fn digest(s: *Scope, state: *Owner, hash: *State, value: c.JSValue) !c.JSValue {
    var codec: ?encoding.Encoding = null;
    if (s.truthy(value)) {
        // Source checks finalized BEFORE this coercion, then calls the native
        // digest without rechecking. Reentrant update/digest must keep that order.
        const coerced = try s.stringify(value);
        const name = try s.engine.toString(coerced);
        defer s.engine.gpa.free(name);
        if (!std.ascii.eqlIgnoreCase(name, "buffer")) codec = encoding.parse(name) orelse { _ = try unsupported(s, state, "Native SHA256 digest encoding is unsupported", "PI_UNSUPPORTED_CRYPTO_ENCODING"); unreachable; };
    }
    if (!hash.cached) {
        var copy = hash.hash;
        copy.final(&hash.digest);
        hash.cached = true;
    }
    const result = if (codec) |selected| blk: {
        const text = try encoding.decode(s.engine.gpa, &hash.digest, selected);
        defer s.engine.gpa.free(text);
        break :blk try s.engine.checked(c.JS_NewStringLen(s.engine.context, text.ptr, text.len));
    } else @import("node_buffer.zig").fromBytes(s.engine, &hash.digest) catch |err| {
        // The inherited Buffer helper has a bare JSException return on a
        // failed prototype installation. Capture its actual pending reason.
        if (err == error.JavaScriptException and c.JS_HasException(s.engine.context)) return js.capture(s.engine);
        return err;
    };
    // Source publishes the finalized flag only after native output succeeds.
    hash.finalized = true;
    return result;
}
fn invoke(engine: *em.Engine, state: *Owner, operation: Operation, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (operation == .create) return makeHash(&s, state, args);
    const hash: *State = @ptrCast(@alignCast(c.JS_GetOpaque(receiver, state.hash_class) orelse return coded(&s, state, true, "Value of this must be a native SHA256 Hash", "ERR_INVALID_THIS")));
    if (hash.finalized) return coded(&s, state, false, "Digest already called", "ERR_CRYPTO_HASH_FINALIZED");
    return switch (operation) { .create => unreachable, .update => update(&s, state, hash, receiver, args), .digest => digest(&s, state, hash, arg(args, 0)) };
}

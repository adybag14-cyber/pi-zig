//! Narrow native WebCrypto getRandomValues host required by UUIDv7.
//! Secure bytes come exclusively from the admitted Zig Io CSPRNG.
//! This does not implement subtle, randomUUID, or the rest of node:crypto.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const object = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, prototype)));
    const owner = try scope.object();
    try scope.put(owner, "crypto", object);
    try scope.put(owner, "typeError", try scope.global("TypeError"));
    try scope.put(owner, "rangeError", try scope.global("RangeError"));
    const function = try scope.own(try @import("native_node_function.zig").create(engine, "getRandomValues", 1, dispatch, &.{owner}));
    try scope.put(prototype, "getRandomValues", function);
    const tag = c.JS_ValueToAtom(engine.context, try scope.get(try scope.global("Symbol"), "toStringTag"));
    if (tag == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, tag);
    if (c.JS_DefinePropertyValue(engine.context, prototype, tag, try engine.checked(c.JS_NewString(engine.context, "Crypto")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, object);
}
pub fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "crypto", try create(engine));
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return fill(engine, receiver, roots[0], args);
}
fn codedError(engine: *em.Engine, owner: c.JSValue, constructor: [*:0]const u8, message: []const u8, code: []const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var args = [_]c.JSValue{try scope.text(message)};
    const value = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(owner, constructor), args.len, &args)));
    try scope.put(value, "code", try scope.text(code));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
}
fn domError(engine: *em.Engine, name: []const u8, message: []const u8) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, try @import("dom_exception.zig").create(engine, message, name)));
}
fn fill(engine: *em.Engine, receiver: c.JSValue, owner: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.equal(receiver, try scope.get(owner, "crypto"))) return codedError(engine, owner, "typeError", "Value of \"this\" must be of type Crypto", "ERR_INVALID_THIS");
    if (args.len == 0) return codedError(engine, owner, "typeError", "Failed to execute 'getRandomValues' on 'Crypto': 1 argument required, but only 0 present.", "ERR_MISSING_ARGS");
    const value = args[0];
    const kind = c.JS_GetTypedArrayType(value);
    if (kind < c.JS_TYPED_ARRAY_UINT8C or kind > c.JS_TYPED_ARRAY_BIG_UINT64) return domError(engine, "TypeMismatchError", "The data argument must be an integer-type TypedArray");
    // Pinned Node's internal/crypto/random body intentionally uses public
    // properties here: quota byteLength, BYTES_PER_ELEMENT, offset byteLength,
    // and finally fill byteLength. Do not replace them with internal fields.
    if (try arithmetic.compare(engine, .greater, try scope.get(value, "byteLength"), c.JS_NewInt32(engine.context, 65536))) return domError(engine, "QuotaExceededError", "The requested length exceeds 65,536 bytes");
    const supplied_element = try scope.get(value, "BYTES_PER_ELEMENT");
    const element_size = if (scope.truthy(supplied_element)) supplied_element else c.JS_NewInt32(engine.context, 1);
    const bound = try scope.get(value, "byteLength");
    const computed_offset = try scope.own(try arithmetic.binary(engine, .multiply, c.JS_NewInt32(engine.context, 0), element_size));
    var numeric_offset: f64 = 0;
    var numeric_bound: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &numeric_offset, computed_offset) < 0 or c.JS_ToFloat64(engine.context, &numeric_bound, bound) < 0) return js.capture(engine);
    const maximum = if (std.math.isNan(numeric_bound)) numeric_bound else @min(numeric_bound, 2147483647);
    if (std.math.isNan(numeric_offset) or numeric_offset > maximum or numeric_offset < 0) {
        const bound_text = try engine.toString(c.JS_NewFloat64(engine.context, maximum));
        defer engine.gpa.free(bound_text);
        const offset_text = try engine.toString(computed_offset);
        defer engine.gpa.free(offset_text);
        const message = try std.fmt.allocPrint(engine.gpa, "The value of \"offset\" is out of range. It must be >= 0 && <= {s}. Received {s}", .{ bound_text, offset_text });
        defer engine.gpa.free(message);
        return codedError(engine, owner, "rangeError", message, "ERR_OUT_OF_RANGE");
    }
    const size = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(value, "byteLength"), c.JS_NewInt32(engine.context, 0)));
    // Node returns before touching the native backing store for a zero size,
    // including ordinary detached and out-of-bounds resizable integer views.
    if (scope.equal(size, c.JS_NewInt32(engine.context, 0))) return c.JS_DupValue(engine.context, value);
    var requested: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &requested, size) < 0) return js.capture(engine);
    if (!std.math.isFinite(requested) or requested < 0 or @floor(requested) != requested or requested > std.math.maxInt(u32)) return error.InvalidCryptoFillSize;
    var offset: usize = 0;
    var length: usize = 0;
    var element: usize = 0;
    const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, value, &offset, &length, &element));
    defer engine.freeValue(backing);
    var total: usize = 0;
    const bytes = c.JS_GetArrayBuffer(engine.context, &total, backing);
    const fill_length: usize = @intFromFloat(requested);
    if (offset > total or length > total - offset or fill_length > length or (bytes == null and fill_length != 0)) return error.InvalidCryptoByteView;
    try std.Io.randomSecure(engine.native_io orelse return error.NativeCryptoIoRequired, bytes[offset..][0..fill_length]);
    return c.JS_DupValue(engine.context, value);
}

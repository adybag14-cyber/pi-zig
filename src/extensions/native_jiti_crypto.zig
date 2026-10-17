//! Additional real MD5 primitive needed by jiti2.7 utils.hash. This dependency
//! is unselected and separately unqualified; qualified SHA256 remains unchanged.
//! Zig's in-process hash backend has no FIPS mode/provider, reported honestly0.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const functions = @import("native_node_module_callable.zig");
const Md5 = std.crypto.hash.Md5;
pub const runtime_fips_mode = false;
const State = struct { engine: *v.em.Engine, hash: Md5 = Md5.init(.{}), digest: [Md5.digest_length]u8 = undefined, cached: bool = false, finalized: bool = false };
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn define(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
/// Consumed createHash(md5|sha256)/getFips surface, with omitted options and
/// string UTF8 update/hex digest for MD5. No public node:crypto registration.
pub fn create(engine: *v.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native Jiti MD5 Hash", .finalizer = finalize };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const id = c.JS_NewUint32(engine.context, class_id);
    const prototype = try s.object();
    try define(engine, prototype, "update", try s.own(try functions.create(engine, "update", 2, true, update, &.{id})));
    try define(engine, prototype, "digest", try s.own(try functions.create(engine, "digest", 1, true, digest, &.{id})));
    const sha256 = try s.own(try @import("native_node_crypto_hash.zig").create(engine));
    const namespace = try s.object();
    try define(engine, namespace, "createHash", try s.own(try functions.create(engine, "createHash", 2, true, makeHash, &.{ id, prototype, sha256 })));
    try define(engine, namespace, "getFips", try s.own(try functions.create(engine, "getFips", 0, true, getFips, &.{})));
    return c.JS_DupValue(engine.context, namespace);
}
fn getFips(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewInt32(engine.context, @intFromBool(runtime_fips_mode));
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn makeHash(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (!c.JS_IsString(argument(args, 0)) or !c.JS_IsUndefined(argument(args, 1))) return v.js.typeError(engine, "Jiti crypto requires md5/sha256 string algorithm and omitted options");
    const name = try engine.toString(args[0]); defer engine.gpa.free(name);
    if (std.mem.eql(u8, name, "sha256")) return v.js.invoke(engine, roots[2], "createHash", args);
    if (!std.mem.eql(u8, name, "md5")) return v.js.typeError(engine, "Unsupported algorithm outside jiti MD5/SHA256 dependency");
    var class_id: u32 = 0;
    if (c.JS_ToUint32(engine.context, &class_id, roots[0]) < 0) return v.js.capture(engine);
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, roots[1], class_id));
    errdefer engine.freeValue(value);
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    const state = engine.gpa.create(State) catch |err| { c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State)); return err; };
    state.* = .{ .engine = engine };
    _ = c.JS_SetOpaque(value, state);
    return value;
}
fn stateFor(engine: *v.em.Engine, receiver: c.JSValue, roots: []const c.JSValue) !*State {
    var class_id: u32 = 0;
    if (c.JS_ToUint32(engine.context, &class_id, roots[0]) < 0) return v.js.capture(engine);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(receiver, class_id) orelse return v.js.typeError(engine, "MD5 Hash receiver required")));
    if (state.engine != engine) return error.RequiredNativeJitiHashOwner;
    if (state.finalized) return v.js.typeError(engine, "Digest already called");
    return state;
}
fn update(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const state = try stateFor(engine, receiver, roots);
    if (!c.JS_IsString(argument(args, 0)) or !c.JS_IsUndefined(argument(args, 1))) return v.js.typeError(engine, "Jiti MD5 dependency supports string UTF8 update only");
    // Same real JS string conversion/UTF8 codec as the separately qualified
    // SHA256 leaf, including the VM's replacement of lone UTF16 surrogates.
    const text = try engine.toString(args[0]); defer engine.gpa.free(text);
    const bytes = try @import("binary_encoding.zig").encode(engine.gpa, text, .utf8); defer engine.gpa.free(bytes);
    state.hash.update(bytes);
    return c.JS_DupValue(engine.context, receiver);
}
fn digest(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const state = try stateFor(engine, receiver, roots);
    if (!c.JS_IsString(argument(args, 0))) return v.js.typeError(engine, "Jiti MD5 dependency supports hex digest only");
    const name = try engine.toString(args[0]); defer engine.gpa.free(name);
    if (!std.mem.eql(u8, name, "hex")) return v.js.typeError(engine, "Jiti MD5 dependency supports hex digest only");
    if (!state.cached) { var copy = state.hash; copy.final(&state.digest); state.cached = true; }
    const bytes = std.fmt.bytesToHex(state.digest, .lower);
    const value = try engine.checked(c.JS_NewStringLen(engine.context, &bytes, bytes.len));
    state.finalized = true;
    return value;
}

//! Native Node StringDecoder. This is the BOM-preserving Buffer decoder,
//! independent from the WHATWG TextDecoder's BOM and EOF replacement policy.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const buffer = @import("node_buffer.zig");
const encoding = @import("binary_encoding.zig");
const fnc = @import("native_node_function.zig");
const c = em.c;
const key = "pi-native:node-string-decoder";
const State = struct { engine: *em.Engine, encoding: encoding.Encoding, last: c.JSValue, saved: usize = 0, needed: usize = 0 };
const Op = enum(c_int) { write, end, text, last_char, last_need, last_total };
fn finalize(rt: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(rt, state.last);
    state.engine.gpa.destroy(state);
}
fn mark(rt: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(rt, state.last, visit);
}
fn own(scope: *Scope, root: c.JSValue, value: c.JSValue) !void {
    const symbol = try scope.get(scope.engine.native_module_values.get(key).?, "stateSymbol");
    const atom = try js.atom(scope.engine, symbol);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, root, atom, c.JS_DupValue(scope.engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
}
fn stateFor(scope: *Scope, receiver: c.JSValue) !*State {
    const owner = scope.engine.native_module_values.get(key).?;
    const root = try scope.own(try js.getKey(scope.engine, receiver, try scope.get(owner, "stateSymbol")));
    var id: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &id, try scope.get(owner, "stateClass")) < 0) return js.capture(scope.engine);
    return @ptrCast(@alignCast(c.JS_GetOpaque(root, id) orelse return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_THIS", "Value of \"this\" must be of type StringDecoder")));
}
pub fn bytes(scope: *Scope, view: c.JSValue) ![]const u8 {
    if (c.JS_GetTypedArrayType(view) < 0 and !c.JS_IsDataView(view)) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"buf\" argument must be an instance of Buffer, TypedArray, or DataView");
    var offset: usize = 0;
    var count: usize = 0;
    var width: usize = 0;
    const backing = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, view, &offset, &count, &width)));
    var total: usize = 0;
    const data = c.JS_GetArrayBuffer(scope.engine.context, &total, backing);
    if (c.JS_HasException(scope.engine.context)) return js.capture(scope.engine);
    if (offset > total or count > total - offset or (data == null and count != 0)) return error.NativeNodeBufferBounds;
    return if (count == 0) &.{} else data[offset..][0..count];
}
fn utf8Prefix(data: []const u8) usize {
    var index: usize = 0;
    while (index < data.len) {
        const first = data[index];
        // Node StringDecoder groups C0/C1 and F5..F7 by their leading bits
        // before validation. A WHATWG decoder cannot replace this carry rule.
        const expected: usize = if (first >= 0xc0 and first <= 0xdf) 2 else if (first >= 0xe0 and first <= 0xef) 3 else if (first >= 0xf0 and first <= 0xf7) 4 else 1;
        var consumed: usize = 1;
        while (consumed < expected) : (consumed += 1) {
            if (index + consumed == data.len) return index;
            if (data[index + consumed] & 0xc0 != 0x80) break;
        }
        index += consumed;
    }
    return data.len;
}
fn completePrefix(data: []const u8, enc: encoding.Encoding) usize {
    return switch (enc) {
        .utf8 => utf8Prefix(data),
        .utf16le => blk: {
            var length = data.len & ~@as(usize, 1);
            if (length >= 2) {
                const unit = @as(u16, data[length - 2]) | (@as(u16, data[length - 1]) << 8);
                if (unit >= 0xd800 and unit <= 0xdbff) length -= 2;
            }
            break :blk length;
        },
        .base64, .base64url => data.len - data.len % 3,
        else => data.len,
    };
}
fn expectedBytes(enc: encoding.Encoding, suffix: []const u8) usize {
    if (suffix.len == 0) return 0;
    return switch (enc) {
        .utf8 => if (suffix[0] < 0xe0) 2 else if (suffix[0] < 0xf0) 3 else 4,
        .utf16le => if (suffix.len >= 2) 4 else 2,
        .base64, .base64url => 3,
        else => suffix.len,
    };
}
fn writeValue(scope: *Scope, receiver: c.JSValue, value: c.JSValue) !c.JSValue {
    // The original returns strings before consulting receiver state.
    if (c.JS_IsString(value)) return c.JS_DupValue(scope.engine.context, value);
    if (c.JS_GetTypedArrayType(value) < 0 and !c.JS_IsDataView(value)) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"buf\" argument must be an instance of Buffer, TypedArray, or DataView");
    // The public symbol lookup can be a guest accessor. Complete it before
    // borrowing any view pointer; then root/copy without running guest code.
    const state = try stateFor(scope, receiver);
    const input = try bytes(scope, value);
    const previous = try bytes(scope, state.last);
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(scope.engine.gpa);
    try joined.appendSlice(scope.engine.gpa, previous[0..state.saved]);
    try joined.appendSlice(scope.engine.gpa, input);
    const length = completePrefix(joined.items, state.encoding);
    const text = try encoding.decode(scope.engine.gpa, joined.items[0..length], state.encoding);
    defer scope.engine.gpa.free(text);
    const tail = joined.items[length..];
    const destination = try bytes(scope, state.last);
    @memcpy(@constCast(destination[0..tail.len]), tail);
    state.saved = tail.len;
    state.needed = expectedBytes(state.encoding, tail) - tail.len;
    return scope.engine.checked(c.JS_NewStringLen(scope.engine.context, text.ptr, text.len));
}
fn call(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[0]) < 0) return js.capture(engine);
    const op: Op = @enumFromInt(raw);
    const value = if (args.len == 0) c.pi_js_undefined() else args[0];
    if (op == .write) return writeValue(&scope, receiver, value);
    if (op == .end) {
        const prefix = if (c.JS_IsUndefined(value)) try scope.text("") else try scope.own(try js.invoke(engine, receiver, "write", &.{value}));
        const state = try stateFor(&scope, receiver);
        const pending = try bytes(&scope, state.last);
        const text = try encoding.decode(engine.gpa, pending[0..state.saved], state.encoding);
        defer engine.gpa.free(text);
        state.saved = 0;
        state.needed = 0;
        return c.JS_DupValue(engine.context, try scope.concat(prefix, try scope.text(text)));
    }
    const state = try stateFor(&scope, receiver);
    return switch (op) {
        .text => blk: {
            state.saved = 0;
            state.needed = 0;
            const sliced = try scope.invoke(value, "slice", &.{if (args.len > 1) args[1] else c.pi_js_undefined()});
            break :blk js.invoke(engine, receiver, "write", &.{sliced});
        },
        .last_char => blk: {
            var offset: usize = 0;
            var length: usize = 0;
            var width: usize = 0;
            const backing = try scope.own(try engine.checked(c.JS_PiGetArrayBufferViewBuffer(engine.context, state.last, &offset, &length, &width)));
            break :blk buffer.fromBacking(engine, backing, offset, length);
        },
        .last_need => c.JS_NewInt64(engine.context, @intCast(state.needed)),
        .last_total => c.JS_NewInt64(engine.context, @intCast(state.saved + state.needed)),
        else => unreachable,
    };
}
fn construct(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const requested = if (args.len == 0) c.pi_js_undefined() else args[0];
    const name = if (!scope.truthy(requested)) try engine.gpa.dupe(u8, "utf8") else try engine.toString(requested);
    defer engine.gpa.free(name);
    const enc = encoding.parse(if (name.len == 0) "utf8" else name) orelse {
        const message = try std.fmt.allocPrint(engine.gpa, "Unknown encoding: {s}", .{name});
        defer engine.gpa.free(message);
        return @import("node_events.zig").codedError(engine, "TypeError", "ERR_UNKNOWN_ENCODING", message);
    };
    const canonical: []const u8 = switch (enc) { .utf8 => "utf8", .utf16le => "utf16le", .latin1 => "latin1", .ascii => "ascii", .hex => "hex", .base64 => "base64", .base64url => "base64url" };
    try scope.set(receiver, "encoding", try scope.text(canonical));
    const owner = engine.native_module_values.get(key).?;
    var class: u32 = 0;
    if (c.JS_ToUint32(engine.context, &class, try scope.get(owner, "stateClass")) < 0) return js.capture(engine);
    const root = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, class)));
    const last = try scope.own(try buffer.fromBytes(engine, &.{ 0, 0, 0, 0 }));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .encoding = enc, .last = c.JS_DupValue(engine.context, last) };
    _ = c.JS_SetOpaque(root, state);
    try own(&scope, receiver, root);
    return c.pi_js_undefined();
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(key)) return;
    try buffer.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native Node StringDecoder State", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    try scope.put(owner, "stateClass", c.JS_NewUint32(engine.context, class));
    try scope.put(owner, "stateSymbol", try scope.call(try scope.global("Symbol"), c.pi_js_undefined(), &.{try scope.text("kNativeDecoder")}));
    const constructor = try scope.own(try fnc.create(engine, "StringDecoder", 1, construct, &.{}));
    const prototype = try scope.get(constructor, "prototype");
    inline for (.{ "write", "end", "text" }, .{ Op.write, Op.end, Op.text }, .{ 1, 1, 2 }) |name, op, length| try scope.put(prototype, name, try scope.own(try fnc.create(engine, name, length, call, &.{c.JS_NewInt32(engine.context, @intFromEnum(op))})));
    inline for (.{ "lastChar", "lastNeed", "lastTotal" }, .{ Op.last_char, Op.last_need, Op.last_total }) |name, op| {
        const atom = c.JS_NewAtom(engine.context, name);
        if (atom == c.JS_ATOM_NULL) return js.capture(engine);
        defer c.JS_FreeAtom(engine.context, atom);
        const getter = try scope.own(try fnc.createMethod(engine, "get " ++ name, 0, call, &.{c.JS_NewInt32(engine.context, @intFromEnum(op))}));
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    }
    try scope.put(owner, "constructor", constructor);
    try engine.registerValueModule(key, owner);
    const exports = try scope.object();
    try scope.put(exports, "StringDecoder", constructor);
    try engine.registerDefaultModule("node:string_decoder", exports);
    try engine.registerDefaultModule("string_decoder", exports);
}
pub fn create(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    try install(engine);
    const constructor = try js.get(engine, engine.native_module_values.get(key).?, "constructor");
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{value};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
}

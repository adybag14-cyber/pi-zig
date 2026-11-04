//! Node's string base64 functions. Buffer's forgiving byte decoder remains
//! separate: atob validates alphabet/padding and creates branded DOM errors.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = em.c;
const Engine = em.Engine;
const State = struct { engine: *Engine, encode: bool };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    state.engine.gpa.destroy(state);
}
fn typeError(engine: *Engine, message: [*:0]const u8) !c.JSValue {
    _ = c.JS_ThrowTypeError(engine.context, "%s", message);
    return js.capture(engine);
}
fn invalid(engine: *Engine, message: []const u8) !c.JSValue {
    const reason = try @import("dom_exception.zig").create(engine, message, "InvalidCharacterError");
    _ = c.JS_PiThrowExceptionData(engine.context, reason);
    return js.capture(engine);
}
fn primitive(engine: *Engine, input: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(input)) return c.JS_DupValue(engine.context, input);
    const symbol = try engine.checked(c.JS_GetToPrimitiveSymbol(engine.context));
    defer engine.releaseNativeValue(symbol);
    const atom = native_guest_4: { try engine.checkNativeEntry(); break :native_guest_4 c.JS_ValueToAtom(engine.context, symbol); };
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    const exotic = try engine.checked(native_guest_3: { try engine.checkNativeEntry(); break :native_guest_3 c.JS_GetProperty(engine.context, input, atom); });
    defer engine.releaseNativeValue(exotic);
    if (!c.JS_IsUndefined(exotic) and !c.JS_IsNull(exotic)) {
        if (!c.JS_IsFunction(engine.context, exotic)) {
            // V8 includes the primitive number in GetMethod's error. Do not
            // call a user coercion hook while constructing this diagnostic.
            if (c.JS_IsNumber(exotic)) {
                const encoded = (engine.toString(exotic) catch |native_error| { if (native_error == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal(); return native_error; });
                defer engine.gpa.free(encoded);
                const terminated = (engine.gpa.dupeZ(u8, encoded) catch |native_error| { if (native_error == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal(); return native_error; });
                defer engine.gpa.free(terminated);
                _ = c.JS_ThrowTypeError(engine.context, "number %s is not a function", terminated.ptr);
                return js.capture(engine);
            }
            return typeError(engine, "Cannot convert object to primitive value");
        }
        const hint = try engine.checked(c.JS_NewString(engine.context, "string"));
        defer engine.releaseNativeValue(hint);
        var args = [_]c.JSValue{hint};
        const result = try engine.checked(native_guest_2: { try engine.checkNativeEntry(); break :native_guest_2 c.JS_Call(engine.context, exotic, input, 1, &args); });
        if (!c.JS_IsObject(result)) return result;
        engine.releaseNativeValue(result);
        return typeError(engine, "Cannot convert object to primitive value");
    }
    inline for (.{ "toString", "valueOf" }) |name| {
        const method = try engine.checked(native_guest_1: { try engine.checkNativeEntry(); break :native_guest_1 c.JS_GetPropertyStr(engine.context, input, name); });
        defer engine.releaseNativeValue(method);
        if (c.JS_IsFunction(engine.context, method)) {
            const result = try engine.checked(native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_Call(engine.context, method, input, 0, null); });
            if (!c.JS_IsObject(result)) return result;
            engine.releaseNativeValue(result);
        }
    }
    return typeError(engine, "Cannot convert object to primitive value");
}
fn sextet(byte: u8) ?u8 {
    return switch (byte) {
        'A'...'Z' => byte - 'A',
        'a'...'z' => byte - 'a' + 26,
        '0'...'9' => byte - '0' + 52,
        '+' => 62,
        '/' => 63,
        else => null,
    };
}
fn decode(engine: *Engine, bytes: []const u8) !c.JSValue {
    var clean: std.ArrayList(u8) = .empty;
    defer clean.deinit(engine.gpa);
    for (bytes) |byte| {
        if (byte == 9 or byte == 10 or byte == 12 or byte == 13 or byte == 32) continue;
        if (byte != '=' and sextet(byte) == null) return invalid(engine, "Invalid character");
        try clean.append(engine.gpa, byte);
    }
    var count = clean.items.len;
    if (count % 4 == 0 and count != 0 and clean.items[count - 1] == '=') {
        count -= 1;
        if (count != 0 and clean.items[count - 1] == '=') count -= 1;
    }
    for (clean.items[0..count]) |byte| if (byte == '=') return invalid(engine, "Invalid character");
    if (count % 4 == 1) return invalid(engine, "The string to be decoded is not correctly encoded.");
    var units: std.ArrayList(u16) = .empty;
    defer units.deinit(engine.gpa);
    var word: u32 = 0;
    var bits: u5 = 0;
    for (clean.items[0..count]) |byte| {
        word = (word << 6) | sextet(byte).?;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            try units.append(engine.gpa, @intCast((word >> bits) & 255));
        }
    }
    return engine.checked(c.JS_NewStringUTF16(engine.context, units.items.ptr, units.items.len));
}
fn encode(engine: *Engine, bytes: []const u8) !c.JSValue {
    var latin: std.ArrayList(u8) = .empty;
    defer latin.deinit(engine.gpa);
    var points = std.unicode.Wtf8View.initUnchecked(bytes).iterator();
    while (points.nextCodepoint()) |point| {
        if (point > 255) return invalid(engine, "Invalid character");
        try latin.append(engine.gpa, @intCast(point));
    }
    const codec = std.base64.standard.Encoder;
    const encoded = try engine.gpa.alloc(u8, codec.calcSize(latin.items.len));
    defer engine.gpa.free(encoded);
    _ = codec.encode(encoded, latin.items);
    return engine.checked(c.JS_NewStringLen(engine.context, encoded.ptr, encoded.len));
}
fn invoke(engine: *Engine, state: *State, argc: c_int, argv: [*c]c.JSValue) !c.JSValue {
    if (argc == 0) {
        _ = c.JS_ThrowTypeError(engine.context, "The \"input\" argument must be specified");
        try @import("native_pending_owner.zig").checkFatal(engine);
        const reason = c.JS_GetException(engine.context);
        defer engine.releaseNativeValue(reason);
        if (c.JS_DefinePropertyValueStr(engine.context, reason, "code", c.JS_NewString(engine.context, "ERR_MISSING_ARGS"), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        _ = c.JS_PiThrowExceptionData(engine.context, c.JS_DupValue(engine.context, reason));
        return js.capture(engine);
    }
    const value = try primitive(engine, argv[0]);
    defer engine.releaseNativeValue(value);
    if (c.JS_IsSymbol(value)) return typeError(engine, "Cannot convert a Symbol value to a string");
    const text = try engine.checked(native_guest_1: { try engine.checkNativeEntry(); break :native_guest_1 c.JS_ToString(engine.context, value); });
    defer engine.releaseNativeValue(text);
    var length: usize = 0;
    const bytes = native_guest_0: { try engine.checkNativeEntry(); break :native_guest_0 c.JS_ToCStringLen2(engine.context, &length, text, true); } orelse return js.capture(engine);
    defer c.JS_FreeCString(engine.context, bytes);
    return if (state.encode) encode(engine, bytes[0..length]) else decode(engine, bytes[0..length]);
}
fn call(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const pending_engine = @import("engine.zig").Engine.fromContext(context.?);
    var pending_frame = @import("native_pending_owner.zig").Frame.init(pending_engine);
    pending_frame.enter() catch return pending_frame.finishCallback(c.pi_js_exception());
    return pending_frame.finishCallback(callPendingBody(context, function, target, argc, argv, flags));
}
fn callPendingBody(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const result = invoke(engine, state, argc, argv) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.ExecutionTerminated) return engine.throwExecutionTerminated();
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
        return c.JS_ThrowInternalError(context, "Native base64: %s", @as([*:0]const u8, @errorName(err)));
    };
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return result;
    engine.releaseNativeValue(result);
    return @import("native_class.zig").object(engine, target) catch |err| if (err == error.JavaScriptException) engine.throwCaptured() else engine.throwNativeOutOfMemoryFatal();
}
fn createFunction(engine: *Engine, global: c.JSValue, name: [:0]const u8, is_encode: bool) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native base64 Function", .finalizer = finalizer, .call = call };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const constructor = try js.get(engine, global, "Function");
    defer engine.releaseNativeValue(constructor);
    const function_prototype = try js.get(engine, constructor, "prototype");
    defer engine.releaseNativeValue(function_prototype);
    const result = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class));
    errdefer engine.releaseNativeValue(result);
    const state = (engine.gpa.create(State) catch |native_error| { if (native_error == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal(); return native_error; });
    state.* = .{ .engine = engine, .encode = is_encode };
    _ = c.JS_SetOpaque(result, state);
    _ = c.JS_SetConstructorBit(engine.context, result, true);
    const prototype = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.releaseNativeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "name", c.JS_NewString(engine.context, name.ptr), c.JS_PROP_CONFIGURABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, result, "length", c.JS_NewInt32(engine.context, 1), c.JS_PROP_CONFIGURABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, result, "prototype", c.JS_DupValue(engine.context, prototype), c.JS_PROP_WRITABLE) < 0 or
        c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, result), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    return result;
}
pub fn install(engine: *Engine, module: c.JSValue) !void {
    if (engine.dom_exception_class == 0) try @import("dom_exception.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.releaseNativeValue(global);
    inline for (.{ .{ "atob", false }, .{ "btoa", true } }) |entry| {
        const value = try createFunction(engine, global, entry[0], entry[1]);
        defer engine.releaseNativeValue(value);
        try js.define(engine, global, entry[0], c.JS_DupValue(engine.context, value));
        try js.define(engine, module, entry[0], c.JS_DupValue(engine.context, value));
    }
}

//! Actual Chord per-stream path dictionary codec and wire/path validation.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { encoder, decoder, encode, decode, safe_path, valid_wire };
fn declared(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, captures[1]) < 0) return js.capture(engine);
    return invoke(engine, h.arg(args, 0), @enumFromInt(raw), captures[0], c.pi_js_undefined());
}
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic), captures[0], captures[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn array(s: *Scope, value: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try s.builtin("Array", "isArray", &.{value})) != 0;
}
fn natural(s: *Scope, value: c.JSValue) !bool {
    if (c.JS_ToBool(s.engine.context, try s.builtin("Number", "isInteger", &.{value})) == 0) return false;
    var number: f64 = 0;
    if (c.JS_ToFloat64(s.engine.context, &number, value) < 0) return js.capture(s.engine);
    return number >= 0;
}
fn raiseRaw(s: *Scope, value: c.JSValue) anyerror {
    // This is an internal native callback completion, not a host diagnostic
    // boundary. Retain the original value for IteratorClose and the callback's
    // throwCaptured, without formatting an error the guest may immediately catch.
    const retained = c.JS_DupValue(s.engine.context, value);
    if (s.engine.captured_exception) |previous| s.engine.freeValue(previous);
    s.engine.captured_exception = retained;
    return error.JavaScriptException;
}
fn fail(s: *Scope, text: []const u8) anyerror {
    const failure = try s.keep(try js.builtin(s.engine, "TypeError", &.{try s.text(text)}));
    return raiseRaw(s, failure);
}
fn errorFor(s: *Scope, bindings: c.JSValue, path: c.JSValue, unsafe: bool) anyerror {
    const error_value = try h.construct(s, bindings, if (unsafe) "UnsafePathError" else "PathError", &.{path});
    return raiseRaw(s, error_value);
}
pub fn safePath(s: *Scope, bindings: c.JSValue, path: c.JSValue) !void {
    var iterator = try js.Iterator.init(s.engine, path, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |segment| {
        defer s.engine.freeValue(segment);
        const invalid = if (c.JS_IsString(segment)) c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(bindings, "RESERVED_SEGMENTS"), "has", &.{segment})) != 0 else !try natural(s, segment);
        if (invalid) return errorFor(s, bindings, segment, true);
    }
}
fn reference(s: *Scope, bindings: c.JSValue, value: c.JSValue) !void {
    if (c.JS_IsNumber(value)) {
        if (!try natural(s, value)) return fail(s, "bad path id");
        return;
    }
    if (!try array(s, value)) return fail(s, "path is not an array");
    try safePath(s, bindings, value);
}
fn permutation(s: *Scope, value: c.JSValue) !void {
    if (!try array(s, value)) return fail(s, "m permutation is not an array");
    const seen = try s.keep(try js.builtin(s.engine, "Uint8Array", &.{try s.get(value, "length")}));
    var iterator = try js.Iterator.init(s.engine, value, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |index| {
        defer s.engine.freeValue(index);
        if (!try natural(s, index)) return fail(s, "m permutation is not a bijection");
        var number: f64 = 0;
        var count: f64 = 0;
        if (c.JS_ToFloat64(s.engine.context, &number, index) < 0 or c.JS_ToFloat64(s.engine.context, &count, try s.get(value, "length")) < 0) return js.capture(s.engine);
        if (number >= count or !c.JS_IsStrictEqual(s.engine.context, try s.key(seen, index), c.JS_NewInt32(s.engine.context, 0))) return fail(s, "m permutation is not a bijection");
        try js.setKey(s.engine, seen, index, c.JS_NewInt32(s.engine.context, 1));
    }
}
pub fn validWire(s: *Scope, bindings: c.JSValue, op: c.JSValue) !void {
    if (!try array(s, op) or try h.length(s, op) == 0) return fail(s, "op is not a tuple");
    var iterator = try js.Iterator.init(s.engine, op, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const verb = if (try iterator.next()) |value| try s.keep(value) else c.pi_js_undefined();
    try iterator.close();
    const size = try h.length(s, op);
    if (try s.equal(verb, "r")) {
        if (size != 2) return fail(s, "r arity");
    } else if (try s.equal(verb, "s") or try s.equal(verb, "d")) {
        const deletion = try s.equal(verb, "d");
        if (size == (if (deletion) @as(u32, 2) else 3)) try reference(s, bindings, try s.at(op, 1)) else if (size != (if (deletion) @as(u32, 1) else 2)) return fail(s, if (deletion) "d arity" else "s arity");
    } else if (try s.equal(verb, "a") or try s.equal(verb, "t")) {
        const append = try s.equal(verb, "a");
        if (size == 3) try reference(s, bindings, try s.at(op, 1)) else if (size != 2) return fail(s, if (append) "a arity" else "t arity");
        const value = try s.at(op, if (size == 3) 2 else 1);
        if (append) {
            if (!c.JS_IsString(value)) return fail(s, "a value");
        } else if (!try natural(s, value)) return fail(s, "t count");
    } else if (try s.equal(verb, "p")) {
        const offset: usize = if (size == 5) 2 else if (size == 4) 1 else return fail(s, "p arity");
        const index = try s.at(op, offset);
        const removed = try s.at(op, offset + 1);
        const items = try s.at(op, offset + 2);
        if (c.JS_IsUndefined(items)) return fail(s, "p arity");
        if (size == 5) try reference(s, bindings, try s.at(op, 1));
        if (!try natural(s, index)) return fail(s, "p index");
        if (!try natural(s, removed)) return fail(s, "p remove");
        if (!try array(s, items)) return fail(s, "p items");
    } else if (try s.equal(verb, "m")) {
        if (size == 3) try reference(s, bindings, try s.at(op, 1)) else if (size != 2) return fail(s, "m arity");
        try permutation(s, try s.at(op, size - 1));
    } else if (try s.equal(verb, "#")) {
        if (size != 3 or !try natural(s, try s.at(op, 1)) or !try array(s, try s.at(op, 2))) return fail(s, "# shape");
        try safePath(s, bindings, try s.at(op, 2));
    } else {
        const text = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "String")), c.pi_js_undefined(), &.{verb}));
        const message = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("unknown op verb: "), text }));
        return raiseRaw(s, try s.keep(try js.builtin(s.engine, "TypeError", &.{message})));
    }
}
fn tuple(s: *Scope, out: c.JSValue, op: c.JSValue, path: c.JSValue, short: bool, decoding: bool) !void {
    const verb = try s.at(op, 0);
    const deletion = try s.equal(verb, "d");
    const splice = try s.equal(verb, "p");
    const recognized = deletion or splice or try s.equal(verb, "s") or try s.equal(verb, "a") or try s.equal(verb, "t") or try s.equal(verb, "m");
    if (!recognized) return;
    const result = try s.list();
    try js.push(s.engine, result, verb);
    if (decoding or !short) try js.push(s.engine, result, path);
    if (!deletion) {
        const offset: usize = if (decoding and short) 1 else 2;
        try js.push(s.engine, result, try s.at(op, offset));
        if (splice) {
            try js.push(s.engine, result, try s.at(op, offset + 1));
            try js.push(s.engine, result, try s.at(op, offset + 2));
        }
    }
    try js.push(s.engine, out, result);
}
fn encode(s: *Scope, input: c.JSValue, owner: c.JSValue) !c.JSValue {
    try h.field(s, owner, "previous", c.pi_js_undefined());
    const out = try s.list();
    const seen = try s.get(owner, "seen");
    const ids = try s.get(owner, "ids");
    var iterator = try js.Iterator.init(s.engine, input, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |op| {
        defer s.engine.freeValue(op);
        if (try s.equal(try s.at(op, 0), "r")) {
            try js.push(s.engine, out, op);
            _ = try h.invoke(s, seen, "clear", &.{});
            _ = try h.invoke(s, ids, "clear", &.{});
            try h.field(s, owner, "nextId", c.JS_NewInt32(s.engine.context, 0));
            try h.field(s, owner, "previous", c.pi_js_undefined());
            continue;
        }
        const path = try s.at(op, 1);
        const key = try s.builtin("JSON", "stringify", &.{path});
        if (c.JS_IsStrictEqual(s.engine.context, key, try s.get(owner, "previous"))) {
            try tuple(s, out, op, c.pi_js_undefined(), true, false);
            continue;
        }
        var reference_value = path;
        const existing = try h.invoke(s, ids, "get", &.{key});
        if (!c.JS_IsUndefined(existing)) {
            reference_value = existing;
        } else if (c.JS_ToBool(s.engine.context, try h.invoke(s, seen, "has", &.{key})) != 0) {
            const id = try s.get(owner, "nextId");
            var number: f64 = 0;
            if (c.JS_ToFloat64(s.engine.context, &number, id) < 0) return js.capture(s.engine);
            try h.field(s, owner, "nextId", c.JS_NewFloat64(s.engine.context, number + 1));
            _ = try h.invoke(s, ids, "set", &.{ key, id });
            const definition = try s.list();
            try js.push(s.engine, definition, try s.text("#"));
            try js.push(s.engine, definition, id);
            try js.push(s.engine, definition, path);
            try js.push(s.engine, out, definition);
            reference_value = id;
        } else _ = try h.invoke(s, seen, "add", &.{key});
        try tuple(s, out, op, reference_value, false, false);
        try h.field(s, owner, "previous", key);
    }
    return out;
}
fn decode(s: *Scope, bindings: c.JSValue, input: c.JSValue, owner: c.JSValue) !c.JSValue {
    const paths = try s.get(owner, "paths");
    const out = try s.list();
    var previous = c.pi_js_undefined();
    var iterator = try js.Iterator.init(s.engine, input, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |op| {
        defer s.engine.freeValue(op);
        try validWire(s, bindings, op);
        if (try s.equal(try s.at(op, 0), "#")) {
            try safePath(s, bindings, try s.at(op, 2));
            _ = try h.invoke(s, paths, "set", &.{ try s.at(op, 1), try s.at(op, 2) });
            continue;
        }
        if (try s.equal(try s.at(op, 0), "r")) {
            try js.push(s.engine, out, op);
            _ = try h.invoke(s, paths, "clear", &.{});
            previous = c.pi_js_undefined();
            continue;
        }
        const verb = try s.at(op, 0);
        const size = try h.length(s, op);
        const deletion = try s.equal(verb, "d");
        const splice = try s.equal(verb, "p");
        const short = (deletion and size == 1) or (!deletion and !splice and size == 2) or (splice and size == 4);
        var path = previous;
        if (short) {
            if (c.JS_IsUndefined(previous)) return errorFor(s, bindings, try s.list(), false);
        } else {
            const ref = try s.at(op, 1);
            if (c.JS_IsNumber(ref)) {
                path = try h.invoke(s, paths, "get", &.{ref});
                if (c.JS_IsUndefined(path)) return errorFor(s, bindings, ref, false);
            } else path = ref;
            previous = path;
        }
        if (!splice and !try s.equal(verb, "m") and try h.length(s, path) == 0) return errorFor(s, bindings, path, false);
        try tuple(s, out, op, path, short, true);
    }
    return out;
}
fn invoke(engine: *h.Engine, input: c.JSValue, method: Method, bindings: c.JSValue, owner: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .safe_path or method == .valid_wire) {
        if (method == .safe_path) try safePath(&s, bindings, input) else try validWire(&s, bindings, input);
        return c.pi_js_undefined();
    }
    if (method == .encode) return s.result(try encode(&s, input, owner));
    if (method == .decode) return s.result(try decode(&s, bindings, input, owner));
    const state_value = try s.record();
    const encoder = method == .encoder;
    if (encoder) {
        try h.field(&s, state_value, "seen", try h.set(&s));
        try h.field(&s, state_value, "ids", try h.map(&s));
        try h.field(&s, state_value, "nextId", c.JS_NewInt32(engine.context, 0));
        try h.field(&s, state_value, "previous", c.pi_js_undefined());
    } else try h.field(&s, state_value, "paths", try h.map(&s));
    const result = try s.record();
    var captures = [_]c.JSValue{ bindings, state_value };
    const name: [:0]const u8 = if (encoder) "encode" else "decode";
    try js.define(engine, result, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, 1, @intFromEnum(if (encoder) Method.encode else Method.decode), 2, &captures)));
    return s.result(result);
}
fn constructError(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const unsafe = c.JS_ToBool(engine.context, captures[1]) != 0;
    const detail = if (unsafe) try s.keep(try js.call(engine, try s.keep(try js.global(engine, "String")), c.pi_js_undefined(), &.{h.arg(args, 0)})) else try s.builtin("JSON", "stringify", &.{h.arg(args, 0)});
    const text = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.text(if (unsafe) "unsafe path segment: " else "unresolvable path: "), detail }));
    var error_args = [_]c.JSValue{text};
    const result = try s.keep(try engine.checked(c.JS_CallConstructor2(engine.context, captures[0], target, 1, &error_args)));
    try h.field(&s, result, if (unsafe) "segment" else "path", h.arg(args, 0));
    try js.setKey(engine, result, try s.text("name"), try s.text(if (unsafe) "UnsafePathError" else "PathError"));
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const api = try s.record();
    const errors = try s.record();
    const reserved = try h.set(&s);
    inline for (.{ "__proto__", "constructor", "prototype" }) |name| _ = try h.invoke(&s, reserved, "add", &.{try s.text(name)});
    try h.field(&s, errors, "RESERVED_SEGMENTS", reserved);
    try h.field(&s, api, "RESERVED_SEGMENTS", reserved);
    const parent = try s.keep(try js.global(engine, "Error"));
    inline for (.{ "PathError", "UnsafePathError" }, 0..) |name, index| {
        const prototype = try s.keep(try engine.checked(c.JS_NewObjectProto(engine.context, try s.get(parent, "prototype"))));
        const constructor = try s.keep(try @import("native_class.zig").constructor(engine, name, 1, prototype, constructError, &.{ parent, c.pi_js_bool(engine.context, index) }));
        if (c.JS_SetPrototype(engine.context, constructor, parent) < 0) return js.capture(engine);
        try h.field(&s, errors, name, constructor);
        try h.field(&s, api, name, constructor);
    }
    inline for (.{ .{ "encoder", Method.encoder, 0 }, .{ "decoder", Method.decoder, 0 }, .{ "assertSafePath", Method.safe_path, 1 }, .{ "assertValidWireOp", Method.valid_wire, 1 } }) |entry| {
        try js.define(engine, api, entry[0], try @import("native_node_function.zig").create(engine, entry[0], entry[2], declared, &.{ errors, c.JS_NewInt32(engine.context, @intFromEnum(entry[1])) }));
    }
    try h.field(&s, bindings, "DeltaCodec", api);
}

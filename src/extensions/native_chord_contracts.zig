//! Genuine Chord contract tokens, descriptions, fingerprints and version binding.
const std = @import("std");
const scoped = @import("native_chord_values.zig");
const Scope = scoped.Scope;
const js = scoped.js;
const c = js.c;
const Engine = js.Engine;
const canonical = @import("native_chord_canonical.zig");
const strings = @import("native_utf16.zig");
const compatibility = @import("native_chord_fits.zig");
const reserved = [_][]const u8{ "kind", "status", "ready", "shape", "error", "onShape", "onStatus", "release", "then", "contract" };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn count(s: *Scope, object: c.JSValue) !usize {
    var length: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &length, try s.get(object, "length")) < 0) return js.capture(s.engine);
    return length;
}
fn typeError(s: *Scope, parts: []const c.JSValue) !c.JSValue {
    const message = try s.keep(try strings.concat(s.engine, parts));
    const constructor = try s.keep(try js.global(s.engine, "TypeError"));
    var args = [_]c.JSValue{message};
    return s.engine.checked(c.JS_Throw(s.engine.context, try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 1, &args))));
}
fn chordError(s: *Scope, bindings: c.JSValue, code: []const u8, reason: ?[]const u8, parts: []const c.JSValue) !c.JSValue {
    const message = try s.keep(try strings.concat(s.engine, parts));
    const options = try s.record();
    if (reason) |label| try js.define(s.engine, options, "reason", s.result(try s.text(label)));
    const constructor = try s.get(bindings, "ChordError");
    var args = [_]c.JSValue{ try s.text(code), message, options };
    return s.engine.checked(c.JS_Throw(s.engine.context, try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 3, &args))));
}
fn integer(value: c.JSValue, engine: *Engine) bool {
    if (!c.JS_IsNumber(value)) return false;
    var number: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return false;
    return std.math.isFinite(number) and @floor(number) == number;
}
fn member(s: *Scope, bindings: c.JSValue, name: c.JSValue, input: c.JSValue, remote: bool) anyerror!c.JSValue {
    for (reserved) |label| if (try s.equal(name, label)) return typeError(s, &.{ try s.text("member name is reserved: "), name });
    if (c.JS_IsNull(input) or c.JS_IsUndefined(input)) return typeError(s, &.{ try s.text("Cannot read properties of "), try s.text(if (c.JS_IsNull(input)) "null" else "undefined"), try s.text(" (reading 'Symbol(chord.member)')") });
    const brand = try s.key(input, try s.get(bindings, "member"));
    const result = try s.record();
    if (try s.equal(brand, "method")) {
        try js.define(s.engine, result, "kind", s.result(try s.text("method")));
        try js.define(s.engine, result, "args", s.result(try s.get(input, "args")));
        try js.define(s.engine, result, "result", s.result(try s.get(input, "result")));
    } else if (try s.equal(brand, "opaque")) {
        if (remote) return typeError(s, &.{ try s.text("remote contracts cannot expose opaque members: "), name });
        try js.define(s.engine, result, "kind", s.result(try s.text("opaque")));
        try js.define(s.engine, result, "id", s.result(try s.get(input, "id")));
    } else {
        try js.define(s.engine, result, "kind", s.result(try s.text("state")));
        try js.define(s.engine, result, "schema", s.result(input));
    }
    return result;
}
fn finish(s: *Scope, object: c.JSValue, description: c.JSValue) !c.JSValue {
    const encoded = try s.keep(try canonical.canonicalJson(s.engine, description));
    try js.define(s.engine, object, "fingerprint", try canonical.hash64(s.engine, encoded));
    return s.result(object);
}
fn token(s: *Scope, bindings: c.JSValue, name: c.JSValue, definition: c.JSValue, remote: bool) anyerror!c.JSValue {
    if (c.JS_ToBool(s.engine.context, name) <= 0) return typeError(s, &.{try s.text("contract name is empty")});
    const version = try s.get(definition, "version");
    var number: f64 = 0;
    if (c.JS_IsNumber(version)) _ = c.JS_ToFloat64(s.engine.context, &number, version);
    if (!integer(version, s.engine) or number < 1) return typeError(s, &.{try s.text("contract version must be a positive integer")});
    const variants = try s.record();
    if (remote) {
        const raw = try s.get(definition, "variants");
        if (try count(s, try s.keys(raw)) == 0) return typeError(s, &.{ try s.text("remote contract "), name, try s.text(" has no variants") });
        const entries = try s.entries(try s.get(definition, "variants"));
        for (0..try count(s, entries)) |index| {
            const entry = try s.at(entries, index);
            const kind = try s.at(entry, 0);
            const variant = try s.at(entry, 1);
            const members = try s.record();
            const state_raw = try s.get(variant, "state");
            const state_entries = try s.entries(if (c.JS_IsUndefined(state_raw) or c.JS_IsNull(state_raw)) try s.record() else state_raw);
            for (0..try count(s, state_entries)) |at| {
                const state_entry = try s.at(state_entries, at);
                const key = try s.at(state_entry, 0);
                try js.setKey(s.engine, members, key, try member(s, bindings, key, try s.at(state_entry, 1), true));
            }
            const methods_raw = try s.get(variant, "methods");
            const methods = try s.entries(if (c.JS_IsUndefined(methods_raw) or c.JS_IsNull(methods_raw)) try s.record() else methods_raw);
            for (0..try count(s, methods)) |at| {
                const method_entry = try s.at(methods, at);
                const key = try s.at(method_entry, 0);
                if (try js.hasKey(s.engine, members, key)) return typeError(s, &.{ try s.text("member "), key, try s.text(" is both state and method in "), name, try s.text("."), kind });
                const described = try member(s, bindings, key, try s.at(method_entry, 1), true);
                try js.setKey(s.engine, members, key, described);
                if (!try s.equal(try s.get(try s.key(members, key), "kind"), "method")) return typeError(s, &.{ try s.text("methods."), key, try s.text(" is not a method()") });
            }
            try js.setKey(s.engine, variants, kind, members);
        }
    } else {
        const raw = try s.get(definition, "members");
        const entries = try s.entries(if (c.JS_IsUndefined(raw) or c.JS_IsNull(raw)) try s.record() else raw);
        const members = try s.record();
        for (0..try count(s, entries)) |index| {
            const entry = try s.at(entries, index);
            const key = try s.at(entry, 0);
            try js.setKey(s.engine, members, key, try member(s, bindings, key, try s.at(entry, 1), false));
        }
        try js.define(s.engine, variants, "", s.result(members));
    }
    const description = try s.record();
    try js.define(s.engine, description, "name", s.result(name));
    try js.define(s.engine, description, "scope", s.result(try s.text(if (remote) "remote" else "local")));
    try js.define(s.engine, description, "version", s.result(try s.get(definition, "version")));
    try js.define(s.engine, description, "input", s.result(try s.get(definition, "input")));
    try js.define(s.engine, description, "variants", s.result(variants));
    const result = try s.record();
    try js.define(s.engine, result, "scope", s.result(try s.text(if (remote) "remote" else "local")));
    try js.define(s.engine, result, "name", s.result(name));
    try js.define(s.engine, result, "version", s.result(try s.get(definition, "version")));
    try js.define(s.engine, result, "input", s.result(try s.get(definition, "input")));
    try js.define(s.engine, result, "def", s.result(definition));
    try js.define(s.engine, result, "description", s.result(description));
    return finish(s, result, description);
}
pub fn coverage(engine: *Engine, provider: c.JSValue, consumer: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (!c.JS_IsStrictEqual(engine.context, try s.get(provider, "name"), try s.get(consumer, "name")) or !c.JS_IsStrictEqual(engine.context, try s.get(provider, "scope"), try s.get(consumer, "scope"))) return s.result(try s.text("different type"));
    if (!try compatibility.fits(engine, try s.get(consumer, "input"), try s.get(provider, "input"))) return s.result(try s.text("input"));
    const variants = try s.entries(try s.get(consumer, "variants"));
    for (0..try count(&s, variants)) |index| {
        const entry = try s.at(variants, index);
        const kind = try s.at(entry, 0);
        const wanted_members = try s.at(entry, 1);
        const offered_members = try s.key(try s.get(provider, "variants"), kind);
        if (c.JS_IsUndefined(offered_members)) return strings.concat(engine, &.{ try s.text("variant "), kind, try s.text(" missing") });
        const entries = try s.entries(wanted_members);
        for (0..try count(&s, entries)) |at| {
            const wanted_entry = try s.at(entries, at);
            const name = try s.at(wanted_entry, 0);
            const wanted = try s.at(wanted_entry, 1);
            const offered = try s.key(offered_members, name);
            const prefix = try s.keep(try strings.concat(engine, &.{ kind, try s.text("."), name }));
            if (c.JS_IsUndefined(offered) or !c.JS_IsStrictEqual(engine.context, try s.get(offered, "kind"), try s.get(wanted, "kind"))) return strings.concat(engine, &.{ prefix, try s.text(" missing or of another kind") });
            if (try s.equal(try s.get(offered, "kind"), "method") and try s.equal(try s.get(wanted, "kind"), "method")) {
                if (!try compatibility.fits(engine, try s.get(wanted, "args"), try s.get(offered, "args"))) return strings.concat(engine, &.{ prefix, try s.text(" arguments") });
                if (!try compatibility.fits(engine, try s.get(offered, "result"), try s.get(wanted, "result"))) return strings.concat(engine, &.{ prefix, try s.text(" result") });
            } else if (try s.equal(try s.get(offered, "kind"), "state") and try s.equal(try s.get(wanted, "kind"), "state")) {
                if (!try compatibility.fits(engine, try s.get(offered, "schema"), try s.get(wanted, "schema"))) return strings.concat(engine, &.{ prefix, try s.text(" state") });
            } else if (try s.equal(try s.get(offered, "kind"), "opaque") and try s.equal(try s.get(wanted, "kind"), "opaque") and !c.JS_IsStrictEqual(engine.context, try s.get(offered, "id"), try s.get(wanted, "id"))) return strings.concat(engine, &.{ prefix, try s.text(" opaque "), try s.get(offered, "id"), try s.text(" != "), try s.get(wanted, "id") });
        }
    }
    return c.pi_js_undefined();
}
fn opaqueValid(engine: *Engine, input: c.JSValue) !bool {
    const units = try strings.unitsAlloc(engine, input);
    defer engine.gpa.free(units);
    var separator: ?usize = null;
    for (units, 0..) |unit, index| {
        if (unit == '@') {
            if (separator != null or index == 0) return false;
            separator = index;
        } else if ((unit >= 9 and unit <= 13) or unit == 0x20 or unit == 0xa0 or unit == 0x1680 or (unit >= 0x2000 and unit <= 0x200a) or unit == 0x2028 or unit == 0x2029 or unit == 0x202f or unit == 0x205f or unit == 0x3000 or unit == 0xfeff) return false;
    }
    const at = separator orelse return false;
    if (at + 1 == units.len) return false;
    for (units[at + 1 ..]) |unit| if (unit < '0' or unit > '9') return false;
    return true;
}
fn invoke(engine: *Engine, _: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var operation: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &operation, data[1]) < 0) return js.capture(engine);
    if (operation == 2 or operation == 3) return token(&s, data[0], arg(args, 0), arg(args, 1), operation == 3);
    if (operation == 4) return coverage(engine, arg(args, 0), arg(args, 1));
    if (operation == 5) {
        const provider = arg(args, 0);
        const consumer = arg(args, 2);
        if (c.JS_IsStrictEqual(engine.context, try s.get(provider, "fingerprint"), try s.get(consumer, "fingerprint"))) return c.pi_js_undefined();
        if (c.JS_IsStrictEqual(engine.context, try s.get(provider, "version"), try s.get(consumer, "version"))) {
            const reason = try s.keep(try coverage(engine, try s.get(provider, "description"), try s.get(consumer, "description")));
            if (c.JS_IsUndefined(reason)) return c.pi_js_undefined();
            return chordError(&s, data[0], "contract_mismatch", null, &.{ try s.get(provider, "name"), try s.text("@"), try s.get(provider, "version"), try s.text(" does not cover the consumer's description ("), reason, try s.text("); forgotten version bump?") });
        }
        const accepts = arg(args, 1);
        const adapter = if (c.JS_IsNull(accepts) or c.JS_IsUndefined(accepts)) c.pi_js_undefined() else try s.key(accepts, try s.get(consumer, "version"));
        if (c.JS_IsUndefined(adapter)) return chordError(&s, data[0], "contract_mismatch", null, &.{ try s.get(provider, "name"), try s.text(": provider version "), try s.get(provider, "version"), try s.text(", consumer version "), try s.get(consumer, "version"), try s.text(", no accepts adapter") });
        return s.result(adapter);
    }
    const object = try s.record();
    const marker = try s.get(data[0], "member");
    const atom = try js.atom(engine, marker);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, object, atom, s.result(try s.text(if (operation == 0) "method" else "opaque")), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    if (operation == 0) {
        try js.define(engine, object, "args", c.JS_DupValue(engine.context, arg(args, 0)));
        try js.define(engine, object, "result", c.JS_DupValue(engine.context, arg(args, 1)));
    } else {
        if (!try opaqueValid(engine, arg(args, 0))) return typeError(&s, &.{ try s.text("opaque id must be name@version: "), arg(args, 0) });
        try js.define(engine, object, "id", c.JS_DupValue(engine.context, arg(args, 0)));
    }
    return s.result(object);
}
fn arrow(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const captures = [_]c.JSValue{ data[0], c.JS_NewInt32(engine.context, operation) };
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, &captures) catch |err| @import("native_durable.zig").reject(engine, err);
}
/// Concrete token exports stay private until complete Chord Host activation.
pub fn exports(engine: *Engine, chord_error: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.record();
    const bindings = try s.record();
    const symbol = try s.keep(try js.global(engine, "Symbol"));
    const marker = try s.keep(try js.call(engine, symbol, c.pi_js_undefined(), &.{try s.text("chord.member")}));
    try js.define(engine, bindings, "member", s.result(marker));
    try js.define(engine, bindings, "ChordError", c.JS_DupValue(engine.context, chord_error));
    inline for (.{ .{ "method", 2 }, .{ "opaque", 1 }, .{ "local", 2 }, .{ "remote", 2 }, .{ "coverage", 2 }, .{ "bind", 3 } }, 0..) |entry, operation| {
        const function = if (operation < 2) blk: {
            var capture = [_]c.JSValue{bindings};
            break :blk try engine.checked(c.JS_NewCFunctionData2(engine.context, arrow, entry[0], entry[1], @intCast(operation), 1, &capture));
        } else try @import("native_node_function.zig").create(engine, entry[0], entry[1], invoke, &.{ bindings, c.JS_NewInt32(engine.context, @intCast(operation)) });
        try js.define(engine, result, entry[0], function);
    }
    return s.result(result);
}

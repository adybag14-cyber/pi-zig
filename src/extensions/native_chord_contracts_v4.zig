//! Actual b45 Chord placement, token descriptions, fingerprints and binding.
//! Private source-only v4 component; the complete Host graph is not activated.
const scoped = @import("native_chord_values.zig");
const Scope = scoped.Scope;
const js = scoped.js;
const c = js.c;
const Engine = js.Engine;
const canonical = @import("native_chord_canonical.zig");
const strings = @import("native_utf16.zig");
const compatibility = @import("native_chord_fits.zig");
const reserved = [_][]const u8{ "variant", "status", "ready", "shape", "error", "onShape", "onStatus", "release", "then", "contract" };
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
fn integer(value: c.JSValue, engine: *Engine) !bool {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.JS_ToBool(engine.context, try s.builtin("Number", "isInteger", &.{value})) != 0;
}
fn comparison(s: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !bool {
    const result = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, operation, left, right)));
    return c.JS_ToBool(s.engine.context, result) != 0;
}
fn member(s: *Scope, bindings: c.JSValue, name: c.JSValue, input: c.JSValue, remote: bool) anyerror!c.JSValue {
    for (reserved) |label| if (try s.equal(name, label)) return typeError(s, &.{ try s.text("member name is reserved: "), name });
    if (c.JS_IsNull(input) or c.JS_IsUndefined(input)) return typeError(s, &.{ try s.text("Cannot read properties of "), try s.text(if (c.JS_IsNull(input)) "null" else "undefined"), try s.text(" (reading 'Symbol(chord.member)')") });
    const brand = try s.key(input, try s.get(bindings, "member"));
    const result = try s.record();
    if (try s.equal(brand, "method")) {
        try js.define(s.engine, result, "kind", s.result(try s.text("method")));
        if (!c.JS_IsUndefined(try s.get(input, "args"))) try js.define(s.engine, result, "args", s.result(try s.get(input, "args")));
        if (!c.JS_IsUndefined(try s.get(input, "result"))) try js.define(s.engine, result, "result", s.result(try s.get(input, "result")));
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
fn hasName(s: *Scope, placement: c.JSValue) !bool {
    const atom = try js.atom(s.engine, try s.text("name"));
    defer c.JS_FreeAtom(s.engine.context, atom);
    const present = c.JS_HasProperty(s.engine.context, placement, atom);
    if (present < 0) return js.capture(s.engine);
    return present != 0;
}
fn samePlacement(s: *Scope, a: c.JSValue, b: c.JSValue) !bool {
    const left = try s.get(a, "host");
    const left_json = try s.keep(try canonical.canonicalJson(s.engine, if (c.JS_IsNull(left) or c.JS_IsUndefined(left)) c.pi_js_null() else left));
    const right = try s.get(b, "host");
    const right_json = try s.keep(try canonical.canonicalJson(s.engine, if (c.JS_IsNull(right) or c.JS_IsUndefined(right)) c.pi_js_null() else right));
    return c.JS_IsStrictEqual(s.engine.context, left_json, right_json);
}
pub fn placementText(engine: *Engine, placement: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try hasName(&s, placement)) return s.result(try s.get(placement, "name"));
    const prefix = try s.keep(try engine.checked(c.JS_ToString(engine.context, try s.get(placement, "prefix"))));
    const key = try s.keep(try engine.checked(c.JS_ToString(engine.context, try s.get(placement, "key"))));
    return strings.concat(engine, &.{ prefix, try s.text("<"), key, try s.text(">") });
}
fn placementOf(s: *Scope, description: c.JSValue) !c.JSValue {
    const host = try s.get(description, "host");
    return if (c.JS_IsUndefined(host)) s.text("(local)") else s.keep(try placementText(s.engine, host));
}
pub fn resolveHost(engine: *Engine, chord_error: c.JSValue, type_name: c.JSValue, placement: c.JSValue, input: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try hasName(&s, placement)) return s.result(try s.get(placement, "name"));
    const key = try s.get(placement, "key");
    const value = if (c.JS_IsObject(input) and !c.JS_IsFunction(engine.context, input)) try s.key(input, key) else c.pi_js_undefined();
    if (!c.JS_IsString(value) or try s.equal(value, "")) {
        const bindings = try s.record();
        try js.define(engine, bindings, "ChordError", c.JS_DupValue(engine.context, chord_error));
        return chordError(&s, bindings, "invalid", "placement", &.{ type_name, try s.text(": input field "), key, try s.text(" names no host") });
    }
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 0, try s.get(placement, "prefix"), value));
}
pub fn placedOn(engine: *Engine, placement: c.JSValue, host_name: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try hasName(&s, placement)) return c.JS_IsStrictEqual(engine.context, try s.get(placement, "name"), host_name);
    const starts_with = try s.get(host_name, "startsWith");
    const starts = try s.keep(try js.call(engine, starts_with, host_name, &.{try s.get(placement, "prefix")}));
    if (c.JS_ToBool(engine.context, starts) <= 0) return false;
    const name_length = try s.get(host_name, "length");
    const prefix_length = try s.get(try s.get(placement, "prefix"), "length");
    return comparison(&s, 6, name_length, prefix_length);
}
pub fn contractFromDescription(engine: *Engine, chord_error: c.JSValue, description: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const name = try s.get(description, "name");
    const scope = try s.get(description, "scope");
    const version = try s.get(description, "version");
    const input = try s.get(description, "input");
    const host = try s.get(description, "host");
    const remote = try s.equal(scope, "remote");
    if (!c.JS_IsString(name) or (!remote and !try s.equal(scope, "local")) or !(try integer(version, engine)) or remote != !c.JS_IsUndefined(host)) {
        const bindings = try s.record();
        try js.define(engine, bindings, "ChordError", c.JS_DupValue(engine.context, chord_error));
        return chordError(&s, bindings, "invalid", "token", &.{try s.text("malformed contract token")});
    }
    const result = try s.record();
    inline for (.{ "name", "scope", "version", "input", "description" }, .{ name, scope, version, input, description }) |key, value| try js.define(engine, result, key, s.result(value));
    const definition = try s.record();
    try js.define(engine, definition, "version", s.result(version));
    try js.define(engine, definition, "input", s.result(input));
    if (remote) {
        try js.define(engine, definition, "host", s.result(host));
        try js.define(engine, definition, "variants", s.result(try s.record()));
    }
    try js.define(engine, result, "def", s.result(definition));
    return finish(&s, result, description);
}
fn token(s: *Scope, bindings: c.JSValue, name: c.JSValue, definition: c.JSValue, remote: bool) anyerror!c.JSValue {
    const version = try s.get(definition, "version");
    if (c.JS_ToBool(s.engine.context, name) <= 0) return typeError(s, &.{try s.text("contract name is empty")});
    if (!(try integer(version, s.engine)) or try comparison(s, 4, version, c.JS_NewInt32(s.engine.context, 1))) return typeError(s, &.{try s.text("contract version must be a positive integer")});
    var host = c.pi_js_undefined();
    if (remote) {
        const placement = try s.get(definition, "host");
        const schema = try s.get(bindings, "placementSchema");
        if (c.JS_IsUndefined(placement) or !try @import("native_tool_validation.zig").checkWithContext(s.engine, try s.record(), schema, placement)) return typeError(s, &.{ try s.text("remote contract "), name, try s.text(" needs `host`: hostNamed(…) or hostFamily(…)") });
        host = try s.record();
        if (try hasName(s, placement)) {
            try js.define(s.engine, host, "name", s.result(try s.get(placement, "name")));
        } else {
            try js.define(s.engine, host, "prefix", s.result(try s.get(placement, "prefix")));
            try js.define(s.engine, host, "key", s.result(try s.get(placement, "key")));
        }
    }
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
    if (remote) try js.define(s.engine, description, "host", s.result(host));
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
    if (!try samePlacement(&s, provider, consumer)) return s.result(try s.text("host"));
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
                const wanted_args = try s.get(wanted, "args");
                const offered_args = try s.get(offered, "args");
                if (c.JS_IsUndefined(wanted_args) != c.JS_IsUndefined(offered_args)) return strings.concat(engine, &.{ prefix, try s.text(" arguments") });
                if (!c.JS_IsUndefined(wanted_args) and !c.JS_IsUndefined(offered_args) and !try compatibility.fits(engine, wanted_args, offered_args)) return strings.concat(engine, &.{ prefix, try s.text(" arguments") });
                const wanted_result = try s.get(wanted, "result");
                const offered_result = try s.get(offered, "result");
                if (!c.JS_IsUndefined(wanted_result) and (c.JS_IsUndefined(offered_result) or !try compatibility.fits(engine, offered_result, wanted_result))) return strings.concat(engine, &.{ prefix, try s.text(" result") });
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
        const provider_description = try s.get(provider, "description");
        const consumer_description = try s.get(consumer, "description");
        if (!try samePlacement(&s, provider_description, consumer_description)) return chordError(&s, data[0], "contract_mismatch", null, &.{ try s.get(provider, "name"), try s.text(" lives on "), try placementOf(&s, provider_description), try s.text(", the consumer expects "), try placementOf(&s, consumer_description) });
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
    if (operation == 6 or operation == 7) {
        const first = arg(args, 0);
        if (!c.JS_IsString(first) or try s.equal(first, "")) return typeError(&s, &.{try s.text(if (operation == 6) "hostNamed needs a host name" else "hostFamily needs a host-name prefix")});
        const placement = try s.record();
        try js.define(engine, placement, if (operation == 6) "name" else "prefix", c.JS_DupValue(engine.context, first));
        if (operation == 7) {
            const key = arg(args, 1);
            if (!c.JS_IsString(key) or try s.equal(key, "")) return typeError(&s, &.{try s.text("hostFamily needs an input field name")});
            try js.define(engine, placement, "key", c.JS_DupValue(engine.context, key));
        }
        return s.result(placement);
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
    const placement_schema = "{\"anyOf\":[{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"minLength\":1}},\"required\":[\"name\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"prefix\":{\"type\":\"string\",\"minLength\":1},\"key\":{\"type\":\"string\",\"minLength\":1}},\"required\":[\"prefix\",\"key\"],\"additionalProperties\":false}]}";
    try js.define(engine, bindings, "placementSchema", try engine.checked(c.JS_ParseJSON(engine.context, placement_schema.ptr, placement_schema.len, "chord-v4-placement-schema.json")));
    inline for (.{ .{ "method", 2 }, .{ "opaque", 1 }, .{ "local", 2 }, .{ "remote", 2 }, .{ "coverage", 2 }, .{ "bind", 3 }, .{ "hostNamed", 1 }, .{ "hostFamily", 2 } }, 0..) |entry, operation| {
        const function = if (operation == 1) blk: {
            var capture = [_]c.JSValue{bindings};
            break :blk try engine.checked(c.JS_NewCFunctionData2(engine.context, arrow, entry[0], entry[1], @intCast(operation), 1, &capture));
        } else try @import("native_node_function.zig").create(engine, entry[0], entry[1], invoke, &.{ bindings, c.JS_NewInt32(engine.context, @intCast(operation)) });
        try js.define(engine, result, entry[0], function);
    }
    return s.result(result);
}

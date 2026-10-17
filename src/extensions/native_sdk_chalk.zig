//! Private actual consumed Chalk6 default: callable factory, yellow builders and
//! root/builder level accessors. MIT Sindre Sorhus; see verification/sdk-chalk6.
//! No global/module 'chalk' shadow; no plain-text renderer substitution.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const functions = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const budget = @import("native_jiti_budget.zig");
const c = em.c;
const private_key = "\x00sdk-actual-chalk6-consumed-default";
const Symbol = enum { GENERATOR, STYLER, IS_EMPTY, LEVEL };
fn symbol(s: *Scope, state: c.JSValue, which: Symbol) !c.JSValue { return s.get(state, @tagName(which)); }
fn slot(s: *Scope, state: c.JSValue, object: c.JSValue, which: Symbol) !c.JSValue { return s.own(try js.getKey(s.engine, object, try symbol(s, state, which))); }
fn setSlot(s: *Scope, state: c.JSValue, object: c.JSValue, which: Symbol, value: c.JSValue) !void { try js.setKey(s.engine, object, try symbol(s, state, which), value); }
fn dup(engine: *em.Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
fn arg(args: []const c.JSValue, n: usize) c.JSValue { return if (n < args.len) args[n] else c.pi_js_undefined(); }
fn index(s: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue { return s.own(try js.getKey(s.engine, object, key)); }
fn bin(s: *Scope, op: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue { return s.own(try arithmetic.binary(s.engine, op, left, right)); }
fn objectCall(s: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.invoke(try s.global("Object"), name, args); }
fn rest(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const array = try s.array();
    for (args, 0..) |value, i| try s.index(array, @intCast(i), value);
    return array;
}
fn cacheStyle(s: *Scope, receiver: c.JSValue, builder: c.JSValue) !void {
    const descriptor = try s.object(); try s.put(descriptor, "value", builder);
    _ = try objectCall(s, "defineProperty", &.{ receiver, try s.text("yellow"), descriptor });
}
fn accessor(s: *Scope, target: c.JSValue, name: [*:0]const u8, get: c.JSValue, set: c.JSValue, enumerable: bool) !void {
    const descriptor = try s.object();
    try s.put(descriptor, "get", get);
    if (!c.JS_IsUndefined(set)) try s.put(descriptor, "set", set);
    if (enumerable) try s.put(descriptor, "enumerable", c.pi_js_bool(s.engine.context, 1));
    _ = try objectCall(s, "defineProperty", &.{ target, try s.text(name), descriptor });
}
fn makeMethod(s: *Scope, name: [*:0]const u8, length: c_int, callback: functions.Callback, roots: []const c.JSValue) !c.JSValue { return s.own(try functions.createMethod(s.engine, name, length, callback, roots)); }
fn validLevel(s: *Scope, value: c.JSValue) !void {
    const safe = try s.invoke(try s.global("Number"), "isSafeInteger", &.{value});
    if (!s.truthy(safe) or try arithmetic.compare(s.engine, .less, value, c.JS_NewInt32(s.engine.context, 0)) or try arithmetic.compare(s.engine, .greater, value, c.JS_NewInt32(s.engine.context, 3))) {
        const ctor = try s.global("Error"); var args = [_]c.JSValue{try s.text("The `level` should be an integer from 0 to 3")};
        const reason = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, ctor, args.len, &args)));
        _ = c.JS_Throw(s.engine.context, dup(s.engine, reason)); return js.capture(s.engine);
    }
}
fn rootLevelGet(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return dup(engine, try slot(&s, roots[0], receiver, .LEVEL));
}
fn rootLevelSet(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const value = arg(args, 0); try validLevel(&s, value); try setSlot(&s, roots[0], receiver, .LEVEL, value); return c.pi_js_undefined();
}
fn builderLevelGet(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return dup(engine, try s.get(try slot(&s, roots[0], receiver, .GENERATOR), "level"));
}
fn builderLevelSet(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); try s.set(try slot(&s, roots[0], receiver, .GENERATOR), "level", arg(args, 0)); return c.pi_js_undefined();
}
fn rootCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return dup(engine, try s.invoke(try rest(&s, args), "join", &.{try s.text(" ")}));
}
fn emptyProtoCall(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
fn factory(s: *Scope, state: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const options = if (c.JS_IsUndefined(supplied)) try s.object() else supplied;
    const chalk = try s.own(try functions.createArrow(s.engine, "chalk", 0, rootCall, &.{}));
    // Source reads options.level independently: 4 reads when explicitly set.
    if (!c.JS_IsUndefined(try s.get(options, "level"))) try validLevel(s, try s.get(options, "level"));
    const stdout = try s.get(state, "stdoutColor"); const detected = if (s.truthy(stdout)) try s.get(stdout, "level") else c.JS_NewInt32(s.engine.context, 0);
    const selected = if (c.JS_IsUndefined(try s.get(options, "level"))) detected else try s.get(options, "level");
    try setSlot(s, state, chalk, .LEVEL, selected);
    _ = try objectCall(s, "setPrototypeOf", &.{ chalk, try s.get(state, "rootPrototype") });
    return chalk;
}
fn createChalk(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); return dup(engine, try factory(&s, roots[0], arg(args, 0)));
}
fn styler(s: *Scope, parent: c.JSValue) !c.JSValue {
    const open = try s.text("\x1b[33m"); const close = try s.text("\x1b[39m");
    const all_open = if (c.JS_IsUndefined(parent)) open else try s.concat(try s.get(parent, "openAll"), open);
    const all_close = if (c.JS_IsUndefined(parent)) close else try s.concat(close, try s.get(parent, "closeAll"));
    const out = try s.object(); try s.put(out, "open", open); try s.put(out, "close", close); try s.put(out, "openAll", all_open); try s.put(out, "closeAll", all_close); try s.put(out, "parent", parent); return out;
}
fn yellowGet(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const state = roots[0];
    const paint = try styler(&s, try slot(&s, state, receiver, .STYLER));
    const is_empty = try slot(&s, state, receiver, .IS_EMPTY);
    const cell = try s.object();
    const builder = try s.own(try functions.createArrow(engine, "builder", 0, builderCall, &.{ state, cell }));
    try s.put(cell, "builder", builder);
    _ = try objectCall(&s, "setPrototypeOf", &.{ builder, try s.get(state, "builderPrototype") });
    const inherited = try slot(&s, state, receiver, .GENERATOR);
    try setSlot(&s, state, builder, .GENERATOR, if (c.JS_IsUndefined(inherited) or c.JS_IsNull(inherited)) receiver else inherited);
    try setSlot(&s, state, builder, .STYLER, paint); try setSlot(&s, state, builder, .IS_EMPTY, is_empty);
    try cacheStyle(&s, receiver, builder); return dup(engine, builder);
}
fn replaceAll(s: *Scope, string: c.JSValue, substring: c.JSValue, postfix: c.JSValue) !c.JSValue {
    var at = try s.invoke(string, "indexOf", &.{substring}); const minus = c.JS_NewInt32(s.engine.context, -1);
    if (s.equal(at, minus)) return string;
    const size = try s.get(substring, "length"); var end = c.JS_NewInt32(s.engine.context, 0); var out = try s.text(""); var count: usize = 0;
    while (true) {
        count +|= 1; try budget.check(s.engine, count);
        const piece = try s.concat(try s.concat(try s.invoke(string, "slice", &.{ end, at }), substring), postfix);
        out = try s.concat(out, piece);
        end = try bin(s, .add, at, size); at = try s.invoke(string, "indexOf", &.{ substring, end }); if (s.equal(at, minus)) break;
    }
    return s.concat(out, try s.invoke(string, "slice", &.{end}));
}
fn newline(s: *Scope, string: c.JSValue, prefix: c.JSValue, postfix: c.JSValue, first: c.JSValue) !c.JSValue {
    var at = first; var end = c.JS_NewInt32(s.engine.context, 0); var out = try s.text(""); var count: usize = 0;
    while (true) {
        count +|= 1; try budget.check(s.engine, count);
        const cr = s.equal(try index(s, string, try bin(s, .subtract, at, c.JS_NewInt32(s.engine.context, 1))), try s.text("\r"));
        const stop = if (cr) try bin(s, .subtract, at, c.JS_NewInt32(s.engine.context, 1)) else at;
        const piece = try s.concat(try s.concat(try s.concat(try s.invoke(string, "slice", &.{ end, stop }), prefix), if (cr) try s.text("\r\n") else try s.text("\n")), postfix);
        out = try s.concat(out, piece); end = try bin(s, .add, at, c.JS_NewInt32(s.engine.context, 1));
        at = try s.invoke(string, "indexOf", &.{ try s.text("\n"), end }); if (s.equal(at, c.JS_NewInt32(s.engine.context, -1))) break;
    }
    return s.concat(out, try s.invoke(string, "slice", &.{end}));
}
fn applyStyle(s: *Scope, state: c.JSValue, self: c.JSValue, input: c.JSValue) !c.JSValue {
    if (try arithmetic.compare(s.engine, .less_equal, try slot(s, state, try slot(s, state, self, .GENERATOR), .LEVEL), c.JS_NewInt32(s.engine.context, 0)) or !s.truthy(input)) return if (s.truthy(try slot(s, state, self, .IS_EMPTY))) s.text("") else input;
    var paint = try slot(s, state, self, .STYLER); if (c.JS_IsUndefined(paint)) return input;
    const open = try s.get(paint, "openAll"); const close = try s.get(paint, "closeAll"); var string = input;
    if (s.truthy(try s.invoke(string, "includes", &.{try s.text("\x1b")}))) {
        var count: usize = 0;
        while (!c.JS_IsUndefined(paint)) { count +|= 1; try budget.check(s.engine, count); const closer = try s.get(paint, "close"); const opener = try s.get(paint, "open"); string = try replaceAll(s, string, closer, opener); paint = try s.get(paint, "parent"); }
    }
    const lf = try s.invoke(string, "indexOf", &.{try s.text("\n")}); if (!s.equal(lf, c.JS_NewInt32(s.engine.context, -1))) string = try newline(s, string, close, open, lf);
    return s.concat(try s.concat(open, string), close);
}
fn builderCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const text = if (args.len == 1) try s.concat(try s.text(""), args[0]) else if (args.len == 2) try s.concat(try s.concat(args[0], try s.text(" ")), args[1]) else try s.invoke(try rest(&s, args), "join", &.{try s.text(" ")});
    return dup(engine, try applyStyle(&s, roots[0], try s.get(roots[1], "builder"), text));
}
/// The returned private supplier is the same default callable throughout one
/// Engine. Process/os are the real installed platform namespaces. No public
/// 'chalk' registration or global replacement occurs.
pub fn createDefault(engine: *em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry(); if (c.JS_HasException(engine.context)) return js.capture(engine);
    if (engine.native_module_values.get(private_key)) |cached| return dup(engine, cached);
    const process_module = engine.native_module_values.get("node:process") orelse return error.NativeChalkRequiresActualProcess;
    const os_module = engine.native_module_values.get("node:os") orelse return error.NativeChalkRequiresActualOs;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const process = try s.get(process_module, "default"); const os = try s.get(os_module, "default");
    const colors = try s.own(try @import("native_sdk_chalk_supports_color.zig").create(engine, process, os));
    const state = try s.object(); try s.put(state, "stdoutColor", try s.get(colors, "stdout"));
    inline for (std.meta.tags(Symbol)) |which| try s.put(state, @tagName(which), try s.call(try s.global("Symbol"), c.pi_js_undefined(), &.{try s.text(@tagName(which))}));
    const constructor = try s.own(try functions.create(engine, "createChalk", 1, createChalk, &.{state}));
    const root_proto = try s.get(constructor, "prototype"); try s.put(state, "rootPrototype", root_proto);
    _ = try objectCall(&s, "setPrototypeOf", &.{ root_proto, try s.get(try s.global("Function"), "prototype") });
    const builder_proto = try s.own(try functions.createArrow(engine, "", 0, emptyProtoCall, &.{})); try s.put(state, "builderPrototype", builder_proto);
    const yellow = try makeMethod(&s, "get", 0, yellowGet, &.{state});
    try accessor(&s, root_proto, "yellow", yellow, c.pi_js_undefined(), false); try accessor(&s, builder_proto, "yellow", yellow, c.pi_js_undefined(), false);
    try accessor(&s, root_proto, "level", try makeMethod(&s, "get", 0, rootLevelGet, &.{state}), try makeMethod(&s, "set", 1, rootLevelSet, &.{state}), true);
    try accessor(&s, builder_proto, "level", try makeMethod(&s, "get", 0, builderLevelGet, &.{state}), try makeMethod(&s, "set", 1, builderLevelSet, &.{state}), true);
    const value = try factory(&s, state, c.pi_js_undefined()); const retained = dup(engine, value);
    engine.native_module_values.put(engine.gpa, private_key, retained) catch |err| { engine.freeValue(retained); return err; };
    return dup(engine, value);
}

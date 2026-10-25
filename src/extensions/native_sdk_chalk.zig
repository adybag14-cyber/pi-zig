//! Private actual consumed Chalk6 default: callable factory, red/yellow/cyan builders and
//! root/builder level accessors. MIT Sindre Sorhus; see verification/sdk-chalk6.
//! No global/module 'chalk' shadow; no plain-text renderer substitution.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_chalk_scope.zig").Scope;
const owned = @import("native_sdk_owned_completion.zig");
const functions = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const private_key = "\x00sdk-actual-chalk6-consumed-default";
const initializing_key = "\x00sdk-actual-chalk6-initializing";
const Body = *const fn (*Scope, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
fn adapt(comptime body: Body) functions.Callback {
    return struct {
        fn invoke(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
            var s: Scope = .{ .engine = engine };
            return owned.finishValue(&s, body(&s, receiver, args, roots));
        }
    }.invoke;
}
const Symbol = enum { GENERATOR, STYLER, IS_EMPTY, LEVEL };
const Foreground = enum { red, yellow, cyan };
fn symbol(s: *Scope, state: c.JSValue, which: Symbol) !c.JSValue { return s.get(state, @tagName(which)); }
fn slot(s: *Scope, state: c.JSValue, object: c.JSValue, which: Symbol) !c.JSValue { return s.getKey(object, try symbol(s, state, which)); }
fn setSlot(s: *Scope, state: c.JSValue, object: c.JSValue, which: Symbol, value: c.JSValue) !void { try s.setKey(object, try symbol(s, state, which), value); }
fn dup(engine: *em.Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
fn arg(args: []const c.JSValue, n: usize) c.JSValue { return if (n < args.len) args[n] else c.pi_js_undefined(); }
fn index(s: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue { return s.getKey(object, key); }
fn bin(s: *Scope, op: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue { return s.binary(op, left, right); }
fn objectCall(s: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.invoke(try s.global("Object"), name, args); }
fn rest(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const array = try s.array();
    for (args, 0..) |value, i| try s.index(array, @intCast(i), value);
    return array;
}
fn cacheStyle(comptime color: Foreground, s: *Scope, receiver: c.JSValue, builder: c.JSValue) !void {
    const descriptor = try s.object(); try s.put(descriptor, "value", builder);
    _ = try objectCall(s, "defineProperty", &.{ receiver, try s.text(@tagName(color)), descriptor });
}
fn accessor(s: *Scope, target: c.JSValue, name: [*:0]const u8, get: c.JSValue, set: c.JSValue, enumerable: bool) !void {
    const descriptor = try s.object();
    try s.put(descriptor, "get", get);
    if (!c.JS_IsUndefined(set)) try s.put(descriptor, "set", set);
    if (enumerable) try s.put(descriptor, "enumerable", c.pi_js_bool(s.engine.context, 1));
    _ = try objectCall(s, "defineProperty", &.{ target, try s.text(std.mem.span(name)), descriptor });
}
fn makeMethod(s: *Scope, name: [*:0]const u8, length: c_int, comptime callback: Body, roots: []const c.JSValue) !c.JSValue { return s.own(try functions.createMethod(s.engine, name, length, adapt(callback), roots)); }
fn validLevel(s: *Scope, value: c.JSValue) !void {
    const safe = try s.invoke(try s.global("Number"), "isSafeInteger", &.{value});
    if (!s.truthy(safe) or try s.compare(.less, value, c.JS_NewInt32(s.engine.context, 0)) or try s.compare(.greater, value, c.JS_NewInt32(s.engine.context, 3))) {
        const ctor = try s.global("Error"); const args = [_]c.JSValue{try s.text("The `level` should be an integer from 0 to 3")};
        const reason = try s.construct(ctor, &args);
        return try s.raise(reason);
    }
}
fn rootLevelGet(s: *Scope, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return dup(s.engine, try slot(s, roots[0], receiver, .LEVEL));
}
fn rootLevelSet(s: *Scope, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const value = arg(args, 0); try validLevel(s, value); try setSlot(s, roots[0], receiver, .LEVEL, value); return c.pi_js_undefined();
}
fn builderLevelGet(s: *Scope, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return dup(s.engine, try s.get(try slot(s, roots[0], receiver, .GENERATOR), "level"));
}
fn builderLevelSet(s: *Scope, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try s.set(try slot(s, roots[0], receiver, .GENERATOR), "level", arg(args, 0)); return c.pi_js_undefined();
}
fn rootCall(s: *Scope, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return dup(s.engine, try s.invoke(try rest(s, args), "join", &.{try s.text(" ")}));
}
fn emptyProtoCall(_: *Scope, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
fn factory(s: *Scope, state: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const options = if (c.JS_IsUndefined(supplied)) try s.object() else supplied;
    const chalk = try s.own(try functions.createArrow(s.engine, "chalk", 0, adapt(rootCall), &.{}));
    // Source reads options.level independently: 4 reads when explicitly set.
    if (!c.JS_IsUndefined(try s.get(options, "level"))) try validLevel(s, try s.get(options, "level"));
    const stdout = try s.get(state, "stdoutColor"); const detected = if (s.truthy(stdout)) try s.get(stdout, "level") else c.JS_NewInt32(s.engine.context, 0);
    const selected = if (c.JS_IsUndefined(try s.get(options, "level"))) detected else try s.get(options, "level");
    try setSlot(s, state, chalk, .LEVEL, selected);
    _ = try objectCall(s, "setPrototypeOf", &.{ chalk, try s.get(state, "rootPrototype") });
    return chalk;
}
fn createChalk(s: *Scope, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return dup(s.engine, try factory(s, roots[0], arg(args, 0)));
}
fn styler(comptime color: Foreground, s: *Scope, parent: c.JSValue) !c.JSValue {
    const open = try s.text(switch (color) {
        .red => "\x1b[31m", .yellow => "\x1b[33m", .cyan => "\x1b[36m",
    });
    const close = try s.text("\x1b[39m");
    const all_open = if (c.JS_IsUndefined(parent)) open else try s.concat(try s.get(parent, "openAll"), open);
    const all_close = if (c.JS_IsUndefined(parent)) close else try s.concat(close, try s.get(parent, "closeAll"));
    const out = try s.object(); try s.put(out, "open", open); try s.put(out, "close", close); try s.put(out, "openAll", all_open); try s.put(out, "closeAll", all_close); try s.put(out, "parent", parent); return out;
}
fn styleGetter(comptime color: Foreground) Body {
    return struct {
        fn get(s: *Scope, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return styleGet(color, s, receiver, roots);
        }
    }.get;
}
fn styleGet(comptime color: Foreground, s: *Scope, receiver: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = s.engine; const state = roots[0];
    const paint = try styler(color, s, try slot(s, state, receiver, .STYLER));
    const is_empty = try slot(s, state, receiver, .IS_EMPTY);
    const cell = try s.object();
    const builder = try s.own(try functions.createArrow(engine, "builder", 0, adapt(builderCall), &.{ state, cell }));
    try s.put(cell, "builder", builder);
    _ = try objectCall(s, "setPrototypeOf", &.{ builder, try s.get(state, "builderPrototype") });
    const inherited = try slot(s, state, receiver, .GENERATOR);
    try setSlot(s, state, builder, .GENERATOR, if (c.JS_IsUndefined(inherited) or c.JS_IsNull(inherited)) receiver else inherited);
    try setSlot(s, state, builder, .STYLER, paint); try setSlot(s, state, builder, .IS_EMPTY, is_empty);
    try cacheStyle(color, s, receiver, builder); return dup(engine, builder);
}
fn replaceAll(s: *Scope, string: c.JSValue, substring: c.JSValue, postfix: c.JSValue) !c.JSValue {
    var at = try s.invoke(string, "indexOf", &.{substring}); const minus = c.JS_NewInt32(s.engine.context, -1);
    if (s.equal(at, minus)) return string;
    const size = try s.get(substring, "length"); var end = c.JS_NewInt32(s.engine.context, 0); var out = try s.text(""); var count: usize = 0;
    while (true) {
        count +|= 1; try s.check(count);
        const piece = try s.concat(try s.concat(try s.invoke(string, "slice", &.{ end, at }), substring), postfix);
        out = try s.concat(out, piece);
        end = try bin(s, .add, at, size); at = try s.invoke(string, "indexOf", &.{ substring, end }); if (s.equal(at, minus)) break;
    }
    return s.concat(out, try s.invoke(string, "slice", &.{end}));
}
fn newline(s: *Scope, string: c.JSValue, prefix: c.JSValue, postfix: c.JSValue, first: c.JSValue) !c.JSValue {
    var at = first; var end = c.JS_NewInt32(s.engine.context, 0); var out = try s.text(""); var count: usize = 0;
    while (true) {
        count +|= 1; try s.check(count);
        const cr = s.equal(try index(s, string, try bin(s, .subtract, at, c.JS_NewInt32(s.engine.context, 1))), try s.text("\r"));
        const stop = if (cr) try bin(s, .subtract, at, c.JS_NewInt32(s.engine.context, 1)) else at;
        const piece = try s.concat(try s.concat(try s.concat(try s.invoke(string, "slice", &.{ end, stop }), prefix), if (cr) try s.text("\r\n") else try s.text("\n")), postfix);
        out = try s.concat(out, piece); end = try bin(s, .add, at, c.JS_NewInt32(s.engine.context, 1));
        at = try s.invoke(string, "indexOf", &.{ try s.text("\n"), end }); if (s.equal(at, c.JS_NewInt32(s.engine.context, -1))) break;
    }
    return s.concat(out, try s.invoke(string, "slice", &.{end}));
}
fn applyStyle(s: *Scope, state: c.JSValue, self: c.JSValue, input: c.JSValue) !c.JSValue {
    if (try s.compare(.less_equal, try slot(s, state, try slot(s, state, self, .GENERATOR), .LEVEL), c.JS_NewInt32(s.engine.context, 0)) or !s.truthy(input)) return if (s.truthy(try slot(s, state, self, .IS_EMPTY))) s.text("") else input;
    var paint = try slot(s, state, self, .STYLER); if (c.JS_IsUndefined(paint)) return input;
    const open = try s.get(paint, "openAll"); const close = try s.get(paint, "closeAll"); var string = input;
    if (s.truthy(try s.invoke(string, "includes", &.{try s.text("\x1b")}))) {
        var count: usize = 0;
        while (!c.JS_IsUndefined(paint)) { count +|= 1; try s.check(count); const closer = try s.get(paint, "close"); const opener = try s.get(paint, "open"); string = try replaceAll(s, string, closer, opener); paint = try s.get(paint, "parent"); }
    }
    const lf = try s.invoke(string, "indexOf", &.{try s.text("\n")}); if (!s.equal(lf, c.JS_NewInt32(s.engine.context, -1))) string = try newline(s, string, close, open, lf);
    return s.concat(try s.concat(open, string), close);
}
fn builderCall(s: *Scope, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const text = if (args.len == 1) try s.concat(try s.text(""), args[0]) else if (args.len == 2) try s.concat(try s.concat(args[0], try s.text(" ")), args[1]) else try s.invoke(try rest(s, args), "join", &.{try s.text(" ")});
    return dup(s.engine, try applyStyle(s, roots[0], try s.get(roots[1], "builder"), text));
}
/// The returned private supplier is the same default callable throughout one
/// Engine. Process/os are the real installed platform namespaces. No public
/// 'chalk' registration or global replacement occurs.
pub fn createDefault(engine: *em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var claimed = false;
    defer if (claimed) { _ = engine.native_module_values.remove(initializing_key); };
    var boundary: Scope = .{ .engine = engine };
    const result = createManaged(engine, &claimed) catch |err| {
        const failure = @import("native_sdk.zig").fail(engine, err);
        return boundary.raw(engine.leaveNativeInvocation(&invocation, failure), engine.native_allocation_generation);
    };
    // The initializer guard remains held through the final invocation-holder
    // retirement. Publish no cached callable until every owned root is settled.
    const value = try boundary.raw(engine.leaveNativeInvocation(&invocation, result), engine.native_allocation_generation);
    if (claimed) {
        const retained = dup(engine, value);
        engine.native_module_values.put(engine.gpa, private_key, retained) catch |err| {
            var completion = owned.Completion.initValue(engine, err);
            completion.release(value);
            completion.release(retained);
            return completion.finishValue();
        };
    }
    return value;
}
fn createManaged(engine: *em.Engine, claimed: *bool) !c.JSValue {
    var entry: Scope = .{ .engine = engine };
    _ = try entry.raw(c.pi_js_undefined(), engine.native_allocation_generation);
    if (engine.native_module_values.get(private_key)) |cached| return dup(engine, cached);
    if (engine.native_module_values.contains(initializing_key)) return error.NativeChalkInitializationInProgress;
    const process_module = engine.native_module_values.get("node:process") orelse return error.NativeChalkRequiresActualProcess;
    const os_module = engine.native_module_values.get("node:os") orelse return error.NativeChalkRequiresActualOs;
    try engine.native_module_values.put(engine.gpa, initializing_key, c.pi_js_bool(engine.context, 1));
    claimed.* = true;
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, initialize(&s, process_module, os_module));
}
fn initialize(s: *Scope, process_module: c.JSValue, os_module: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const process = try s.get(process_module, "default"); const os = try s.get(os_module, "default");
    const colors = try s.own(try @import("native_sdk_chalk_supports_color.zig").create(engine, process, os));
    const state = try s.object(); try s.put(state, "stdoutColor", try s.get(colors, "stdout"));
    inline for (std.meta.tags(Symbol)) |which| try s.put(state, @tagName(which), try s.call(try s.global("Symbol"), c.pi_js_undefined(), &.{try s.text(@tagName(which))}));
    const constructor = try s.own(try functions.create(engine, "createChalk", 1, adapt(createChalk), &.{state}));
    const root_proto = try s.get(constructor, "prototype"); try s.put(state, "rootPrototype", root_proto);
    _ = try objectCall(s, "setPrototypeOf", &.{ root_proto, try s.get(try s.global("Function"), "prototype") });
    const builder_proto = try s.own(try functions.createArrow(engine, "", 0, adapt(emptyProtoCall), &.{})); try s.put(state, "builderPrototype", builder_proto);
    // The consumed foreground styles retain the primary enumeration order.
    // Each getter creates and caches the same genuine builder algorithm.
    inline for (.{ Foreground.red, Foreground.yellow, Foreground.cyan }) |color| {
        const getter = try makeMethod(s, "get", 0, styleGetter(color), &.{state});
        try accessor(s, root_proto, @tagName(color), getter, c.pi_js_undefined(), false);
        try accessor(s, builder_proto, @tagName(color), getter, c.pi_js_undefined(), false);
    }
    try accessor(s, root_proto, "level", try makeMethod(s, "get", 0, rootLevelGet, &.{state}), try makeMethod(s, "set", 1, rootLevelSet, &.{state}), true);
    try accessor(s, builder_proto, "level", try makeMethod(s, "get", 0, builderLevelGet, &.{state}), try makeMethod(s, "set", 1, builderLevelSet, &.{state}), true);
    return dup(engine, try factory(s, state, c.pi_js_undefined()));
}

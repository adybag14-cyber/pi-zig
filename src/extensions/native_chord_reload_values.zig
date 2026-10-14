//! Shared owner-thread operations for the actual Source Reload/cluster graph.
pub const h = @import("native_chord_host_values.zig");
pub const js = h.js;
pub const c = h.c;
pub const Scope = h.Scope;
pub fn iterate(s: *Scope, iterable: c.JSValue) !js.Iterator {
    return js.Iterator.init(s.engine, iterable, try h.iteratorSymbol(s));
}
pub fn mapIterator(s: *Scope, map: c.JSValue, method: [*:0]const u8) !js.Iterator {
    return iterate(s, try h.invoke(s, map, method, &.{}));
}
pub fn has(s: *Scope, map: c.JSValue, key: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try h.invoke(s, map, "has", &.{key})) != 0;
}
pub fn greater(s: *Scope, a: c.JSValue, b: c.JSValue) !bool {
    const result = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 6, a, b)));
    return c.JS_ToBool(s.engine.context, result) != 0;
}
pub fn optional(s: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (h.nullish(value)) c.pi_js_undefined() else s.get(value, key);
}
pub fn default(s: *Scope, value: c.JSValue, replacement: c.JSValue) c.JSValue {
    _ = s;
    return if (h.nullish(value)) replacement else value;
}
pub fn reason(s: *Scope, value: []const u8) !c.JSValue {
    const options = try s.record();
    try h.field(s, options, "reason", try s.text(value));
    return options;
}
pub fn concat(s: *Scope, parts: []const c.JSValue) !c.JSValue {
    return s.keep(try @import("native_utf16.zig").concat(s.engine, parts));
}
pub fn reloadError(s: *Scope, bindings: c.JSValue, value: c.JSValue) !c.JSValue {
    const cause = try h.invoke(s, try s.get(bindings, "errors"), "asChordError", &.{ value, try s.text("reload") });
    const strip = try s.keep(try js.builtin(s.engine, "RegExp", &.{try s.text("^[^:]*: ")}));
    const message = try h.invoke(s, try s.get(cause, "message"), "replace", &.{ strip, try s.text("") });
    const prefix = try s.keep(try js.builtin(s.engine, "RegExp", &.{try s.text("^reload aborted")}));
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, prefix, "test", &.{message})) != 0) return cause;
    const options = try s.record();
    try h.field(s, options, "cause", cause);
    try h.field(s, options, "reason", try s.get(cause, "reason"));
    try h.field(s, options, "details", try s.get(cause, "details"));
    const constructor = try s.get(try s.get(bindings, "errors"), "ChordError");
    var args = [_]c.JSValue{ try s.get(cause, "code"), try concat(s, &.{ try s.text("reload aborted: "), try s.get(cause, "message") }), options };
    return s.keep(try s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 3, &args)));
}
pub fn alive(s: *Scope, bindings: c.JSValue, reload: c.JSValue) !void {
    _ = try h.actor(s, reload, bindings, .Reload);
    if (try h.flag(s, reload, "rolledBack")) _ = try h.throwValue(s, try h.errorValue(s, bindings, "aborted", &.{try s.text("reload aborted while preparing")}, try reason(s, "aborted")));
}
pub fn pair(s: *Scope, a: c.JSValue, b: c.JSValue) !c.JSValue {
    const result = try s.list();
    try js.push(s.engine, result, a);
    try js.push(s.engine, result, b);
    return result;
}
pub fn copyMap(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.keep(try js.builtin(s.engine, "Map", &.{value}));
}
pub fn copySet(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.keep(try js.builtin(s.engine, "Set", &.{value}));
}
pub fn put(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try js.setKey(s.engine, target, try s.text(@import("std").mem.span(name)), value);
}
pub fn index(s: *Scope, work: c.JSValue, name: [*:0]const u8) !u32 {
    var result: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &result, try s.get(work, name)) < 0) return js.capture(s.engine);
    return result;
}
pub fn advance(s: *Scope, work: c.JSValue, name: [*:0]const u8) !u32 {
    const value = try index(s, work, name);
    try put(s, work, name, c.JS_NewUint32(s.engine.context, value + 1));
    return value;
}
pub fn promise(s: *Scope, name: [*:0]const u8, values: c.JSValue) !c.JSValue {
    return h.invoke(s, try s.keep(try js.global(s.engine, "Promise")), name, &.{values});
}
pub fn next(s: *Scope, iterator: c.JSValue) !?c.JSValue {
    const result = try h.invoke(s, iterator, "next", &.{});
    if (try h.flag(s, result, "done")) return null;
    return try s.get(result, "value");
}
pub fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn reporter(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn reportFunction(s: *Scope, host: c.JSValue) !c.JSValue {
    var captures = [_]c.JSValue{host};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, reporter, "", 1, 0, 1, &captures)));
}
pub fn reportPending(s: *Scope, host: c.JSValue, pending: c.JSValue) !c.JSValue {
    return h.invoke(s, pending, "catch", &.{try reportFunction(s, host)});
}
pub fn endReload(s: *Scope, host: c.JSValue) !void {
    _ = try h.invoke(s, host, "reloadEnded", &.{});
}

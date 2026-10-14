//! Actual b45 deferred-initialization Cell, backed by the real native tracker.
const h = @import("native_chord_host_values.zig");
const base = @import("native_chord_cells_v4.zig");
const graph = @import("native_chord_cells_graph.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { value, schemas, change, replace, reset, initialize };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn what(s: *Scope, receiver: c.JSValue, initial: bool) !c.JSValue {
    return s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text(if (initial) "initial value of state " else "state "), try s.get(receiver, "key") }));
}
fn initialized(s: *Scope, receiver: c.JSValue, data: c.JSValue, bindings: c.JSValue) !void {
    if (try h.flag(s, data, "initialized")) return;
    const label = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("state "), try s.get(receiver, "key"), try s.text(" (its init has not run)") }));
    _ = try h.throwValue(s, try h.invoke(s, bindings, "notReady", &.{label}));
}
fn box(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "v", value);
    return result;
}
fn unbox(s: *Scope, operations: c.JSValue, value: c.JSValue) !c.JSValue {
    const result = try s.list();
    const symbol = try h.iteratorSymbol(s);
    var iterator = try js.Iterator.init(s.engine, operations, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |op| {
        defer s.engine.freeValue(op);
        const kind = try s.at(op, 0);
        const replace_root = try s.equal(kind, "r");
        const path = if (replace_root) c.pi_js_undefined() else try s.at(op, 1);
        if (replace_root or try h.length(s, path) == 0) return replacement(s, value);
        const next_path = try h.invoke(s, path, "slice", &.{c.JS_NewInt32(s.engine.context, 1)});
        const next = try s.list();
        if (!try s.equal(kind, "p") and !try s.equal(kind, "m") and try h.length(s, next_path) == 0) return replacement(s, value);
        try js.push(s.engine, next, kind);
        try js.push(s.engine, next, next_path);
        if (try s.equal(kind, "p")) {
            inline for (2..5) |index| try js.push(s.engine, next, try s.at(op, index));
        } else if (!try s.equal(kind, "d")) try js.push(s.engine, next, try s.at(op, 2));
        try js.push(s.engine, result, next);
    }
    return result;
}
fn replacement(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try s.list();
    const op = try s.list();
    try js.push(s.engine, op, try s.text("r"));
    try js.push(s.engine, op, value);
    try js.push(s.engine, result, op);
    return result;
}
fn sameStructure(s: *Scope, left: c.JSValue, right: c.JSValue) !bool {
    if (!c.JS_IsObject(left) or !c.JS_IsObject(right) or c.JS_IsFunction(s.engine.context, left) or c.JS_IsFunction(s.engine.context, right) or c.JS_IsStrictEqual(s.engine.context, left, right)) return false;
    const a = try s.builtin("Array", "isArray", &.{left});
    const b = try s.builtin("Array", "isArray", &.{right});
    if (c.JS_ToBool(s.engine.context, a) != c.JS_ToBool(s.engine.context, b)) return false;
    const entries = try s.entries(right);
    for (0..try h.length(s, entries)) |index| {
        const pair = try s.at(entries, index);
        const child = try s.at(pair, 1);
        if (c.JS_IsObject(child) and !c.JS_IsFunction(s.engine.context, child) and c.JS_IsStrictEqual(s.engine.context, try s.key(left, try s.at(pair, 0)), child)) return true;
    }
    return false;
}
fn publishHeld(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return held(engine, captures) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn held(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const receiver = captures[0];
    const bindings = captures[1];
    const prepared = captures[2];
    const data = (try h.actor(&s, receiver, bindings, .Cell)).data;
    _ = try h.invoke(&s, try s.get(data, "tracker"), "adopt", &.{prepared});
    const supplied_ops = captures[5];
    const operations = if (!c.JS_IsUndefined(supplied_ops) and try h.length(&s, supplied_ops) > 0) supplied_ops else try unbox(&s, try s.get(prepared, "ops"), captures[3]);
    const event = try s.record();
    try h.field(&s, event, "type", captures[6]);
    if (!try s.equal(captures[6], "reset")) try h.field(&s, event, "ops", operations);
    try h.field(&s, event, "value", captures[3]);
    _ = try h.invoke(&s, try s.get(receiver, "fanout"), "emit", &.{event});
    try graph.install(&s, captures[4]);
    return c.pi_js_undefined();
}
pub fn publish(s: *Scope, receiver: c.JSValue, bindings: c.JSValue, prepared: c.JSValue, reset: bool, validate: bool, operations: c.JSValue) !void {
    const data = (try h.actor(s, receiver, bindings, .Cell)).data;
    if (!reset and try h.length(s, try s.get(prepared, "ops")) == 0) {
        _ = try h.invoke(s, try s.get(data, "tracker"), "adopt", &.{prepared});
        return;
    }
    const value = try s.get(try s.get(prepared, "value"), "v");
    const candidates = candidates: {
        if (validate) {
            _ = h.invoke(s, receiver, "validate", &.{value}) catch |err| {
                _ = h.invoke(s, prepared, "abort", &.{}) catch {};
                return err;
            };
        }
        break :candidates graph.compute(s, receiver, value, validate) catch |err| {
            _ = h.invoke(s, prepared, "abort", &.{}) catch {};
            return err;
        };
    };
    var captures = [_]c.JSValue{ receiver, bindings, prepared, value, candidates, operations, try s.text(if (reset) "reset" else "ops") };
    const task = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, publishHeld, "", 0, 0, 7, &captures)));
    const ignored = try s.keep(try @import("native_chord_publish.zig").hold(s.engine, bindings, task));
    _ = ignored;
}
fn prepareChange(s: *Scope, receiver: c.JSValue, bindings: c.JSValue, change: c.JSValue, function: c.JSValue) !c.JSValue {
    const draft = try s.get(change, "state");
    const result = try s.keep(try js.call(s.engine, function, c.pi_js_undefined(), &.{try s.get(draft, "v")}));
    const promise = c.JS_IsInstanceOf(s.engine.context, result, try s.keep(try js.global(s.engine, "Promise")));
    if (promise < 0) return js.capture(s.engine);
    if (promise != 0) return h.typeError(s, &.{try s.text("cell.change callbacks must be synchronous")});
    if (!c.JS_IsUndefined(result)) {
        if (!c.JS_IsStrictEqual(s.engine.context, result, try s.get(draft, "v"))) try @import("native_chord_host_record_schema.zig").assertValid(s, bindings, "state", try what(s, receiver, false), try s.get(receiver, "schema"), result);
        try js.setKey(s.engine, draft, try s.text("v"), result);
    }
    return h.invoke(s, change, "prepare", &.{});
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .schemas) {
        const schemas = try s.list();
        try js.push(engine, schemas, try s.get(receiver, "schema"));
        return s.result(schemas);
    }
    const data = (try h.actor(&s, receiver, bindings, .Cell)).data;
    const tracker = try s.get(data, "tracker");
    if (method == .initialize) {
        if (try h.flag(&s, data, "initialized")) return h.ordinaryError(&s, &.{ try s.text("state "), try s.get(receiver, "key"), try s.text(" is already initialized") });
        try @import("native_chord_host_record_schema.zig").assertValid(&s, bindings, "state", try what(&s, receiver, true), try s.get(receiver, "schema"), h.arg(args, 0));
        const next = try s.keep(try @import("native_chord_delta_tracker.zig").track(engine, try box(&s, h.arg(args, 0))));
        try h.field(&s, data, "tracker", next);
        try h.field(&s, data, "initialized", c.pi_js_bool(engine.context, 1));
        return c.pi_js_undefined();
    }
    if (method == .value) {
        try initialized(&s, receiver, data, bindings);
        return js.get(engine, try s.get(tracker, "value"), "v");
    }
    if (method == .change) {
        _ = try s.keep(try js.call(engine, try s.get(data, "guard"), receiver, &.{h.arg(args, 0)}));
        try initialized(&s, receiver, data, bindings);
        const change = try h.invoke(&s, tracker, "beginChange", &.{});
        const prepared = prepareChange(&s, receiver, bindings, change, h.arg(args, 1)) catch |err| {
            _ = h.invoke(&s, change, "abort", &.{}) catch {};
            return err;
        };
        try publish(&s, receiver, bindings, prepared, false, true, c.pi_js_undefined());
        return c.pi_js_undefined();
    }
    if (method == .reset) {
        try js.setKey(engine, receiver, try s.text("schema"), h.arg(args, 1));
        try publish(&s, receiver, bindings, try h.invoke(&s, tracker, "prepareReplace", &.{try box(&s, h.arg(args, 0))}), true, false, c.pi_js_undefined());
        return c.pi_js_undefined();
    }
    _ = try s.keep(try js.call(engine, try s.get(data, "guard"), receiver, &.{h.arg(args, 0)}));
    const before = try s.get(receiver, "value");
    const options = if (c.JS_IsUndefined(h.arg(args, 2))) try s.record() else args[2];
    const chosen = try s.get(options, "diff");
    const diff = if (h.nullish(chosen)) try sameStructure(&s, before, h.arg(args, 1)) else c.JS_ToBool(engine.context, chosen) != 0;
    const operations = if (diff) try s.keep(try @import("native_chord_delta_diff.zig").diffRevisions(engine, before, h.arg(args, 1))) else c.pi_js_undefined();
    const prepared = try h.invoke(&s, tracker, "prepareReplace", &.{try box(&s, h.arg(args, 1))});
    try publish(&s, receiver, bindings, prepared, false, true, operations);
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .Cell));
    try base.initialize(&s, bindings, result, h.arg(args, 0), h.arg(args, 4));
    const initial = h.arg(args, 2);
    if (!c.JS_IsUndefined(initial)) try @import("native_chord_host_record_schema.zig").assertValid(&s, bindings, "state", try what(&s, result, true), h.arg(args, 1), try s.get(initial, "value"));
    try h.field(&s, result, "schema", h.arg(args, 1));
    const data = (try h.actor(&s, result, bindings, .Cell)).data;
    // Source reads the box's value again after validation, and uses null for a
    // nullish constructor value even when its initialized flag is true.
    const value = if (h.nullish(initial)) c.pi_js_undefined() else try s.get(initial, "value");
    const tracker = try s.keep(try @import("native_chord_delta_tracker.zig").track(engine, try box(&s, if (h.nullish(value)) c.pi_js_null() else value)));
    try h.field(&s, data, "tracker", tracker);
    try h.field(&s, data, "guard", h.arg(args, 3));
    try h.field(&s, data, "initialized", c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(initial))));
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .Cell);
    const source = try s.get(bindings, "Source");
    const prototype = try s.keep(try engine.checked(c.JS_NewObjectProto(engine.context, try s.get(source, "prototype"))));
    const constructor = try s.keep(try @import("native_class.zig").constructor(engine, "Cell", 5, prototype, construct, &.{bindings}));
    if (c.JS_SetPrototype(engine.context, constructor, source) < 0) return js.capture(engine);
    try h.field(&s, bindings, "Cell", constructor);
    inline for (.{ .{ "ownSchemas", Method.schemas, 0, false }, .{ "value", Method.value, 0, true }, .{ "initialize", Method.initialize, 1, false }, .{ "change", Method.change, 2, false }, .{ "replace", Method.replace, 2, false }, .{ "reset", Method.reset, 2, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}

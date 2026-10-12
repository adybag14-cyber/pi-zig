//! Real private Chord normalization pipeline and TypeBox evaluator bindings.
//! Unported action/inference/settings surfaces remain activation blockers.
const v = @import("native_chord_type_values.zig");
const Scope = v.Scope;
const js = v.js;
const c = v.c;
const workers = @import("native_chord_normalization_workers.zig");
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn defaults(engine: *js.Engine, context: c.JSValue, schema: c.JSValue, value: c.JSValue) !c.JSValue {
    return workers.visit(engine, .defaults, context, schema, value);
}
pub fn clean(engine: *js.Engine, context: c.JSValue, schema: c.JSValue, value: c.JSValue) !c.JSValue {
    const sorted = try @import("native_chord_type_priority.zig").sort(engine, schema);
    defer engine.freeValue(sorted);
    return workers.visit(engine, .clean, context, sorted, value);
}
pub fn normalize(engine: *js.Engine, errors: c.JSValue, schema: c.JSValue, value: c.JSValue, what: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const context = try s.record();
    const input = if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) try s.record() else value;
    const copy = try s.keep(try @import("native_chord_clone.zig").clone(engine, input));
    const defaulted = try s.keep(try defaults(engine, context, schema, copy));
    const normalized = try s.keep(try clean(engine, context, schema, defaulted));
    if (try @import("native_tool_validation.zig").checkWithContext(engine, context, schema, normalized)) return s.result(normalized);
    const validator = try s.keep(try @import("native_tool_validator_cache.zig").compileFresh(engine, schema));
    const all_errors = try s.keep(try js.invoke(engine, validator, "Errors", &.{normalized}));
    const details = try s.keep(try js.invoke(engine, all_errors, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 3) }));
    const summaries = try s.list();
    const count = try v.length(&s, details);
    for (0..count) |index| {
        const item = try s.at(details, index);
        const path = try s.get(item, "instancePath");
        const location = if (c.JS_ToBool(engine.context, path) != 0) path else try s.text("/");
        const summary = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ location, try s.text(" "), try s.get(item, "message") }));
        try js.push(engine, summaries, summary);
    }
    const summary = try s.keep(try js.invoke(engine, summaries, "join", &.{try s.text("; ")}));
    const message = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ what, try s.text(": "), summary }));
    const failure = try js.invoke(engine, errors, "invalid", &.{ try s.text("input"), message, details });
    return engine.checked(c.JS_Throw(engine.context, failure));
}
fn invoke(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    var operation: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &operation, values[0]) < 0) return js.capture(engine);
    if (operation < 2) {
        if (args.len != 2 and args.len != 3) {
            const message = try engine.checked(c.JS_NewString(engine.context, "Invalid Arguments"));
            defer engine.freeValue(message);
            return engine.checked(c.JS_Throw(engine.context, try js.builtin(engine, "Error", &.{message})));
        }
        const context = if (args.len == 3) c.JS_DupValue(engine.context, args[0]) else try js.object(engine);
        defer engine.freeValue(context);
        return if (operation == 0) defaults(engine, context, args[args.len - 2], args[args.len - 1]) else clean(engine, context, args[args.len - 2], args[args.len - 1]);
    }
    return switch (operation) {
        2 => normalize(engine, values[1], arg(args, 0), arg(args, 1), arg(args, 2)),
        3 => c.JS_NewInt32(engine.context, try @import("native_chord_type_extends.zig").compare(engine, arg(args, 0), arg(args, 1))),
        4 => @import("native_chord_type_evaluate.zig").narrow(engine, arg(args, 0), arg(args, 1)),
        else => @import("native_chord_canonical.zig").canonicalJson(engine, arg(args, 0)),
    };
}
fn construct(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const name = try engine.toString(values[0]);
    defer engine.gpa.free(name);
    inline for (.{ .{ "PickDeferred", "Pick", 2 }, .{ "PartialDeferred", "Partial", 1 }, .{ "RequiredDeferred", "Required", 1 }, .{ "RecordDeferred", "Record", 2 } }) |item| {
        if (@import("std").mem.eql(u8, name, item[0])) {
            const parameters = try s.list();
            for (0..item[2]) |index| try js.push(engine, parameters, arg(args, index));
            const options = if (c.JS_IsUndefined(arg(args, item[2]))) try s.record() else args[item[2]];
            return s.result(try @import("native_chord_type_instantiate.zig").deferred(&s, item[1], parameters, options));
        }
    }
    return s.result(try v.constructor(&s, name, args));
}
/// Internal exports for original-source qualification only. No package install.
pub fn exports(engine: *js.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const api = try s.record();
    const errors = try s.keep(try @import("native_chord_errors.zig").exports(engine));
    inline for (.{ .{ "Default", 0 }, .{ "Clean", 0 }, .{ "normalize", 3 }, .{ "Compare", 2 }, .{ "Narrow", 2 }, .{ "canonicalJson", 1 } }, 0..) |item, operation| {
        try js.define(engine, api, item[0], try @import("native_node_function.zig").create(engine, item[0], item[1], invoke, &.{ c.JS_NewInt32(engine.context, @intCast(operation)), errors }));
    }
    const types = try s.keep(try @import("typebox.zig").create(engine));
    inline for (.{ .{ "Never", 1 }, .{ "Undefined", 1 }, .{ "Void", 1 }, .{ "BigInt", 1 }, .{ "Symbol", 1 }, .{ "Tuple", 1 }, .{ "Readonly", 1 }, .{ "Immutable", 1 }, .{ "Ref", 1 }, .{ "PickDeferred", 2 }, .{ "PartialDeferred", 1 }, .{ "RequiredDeferred", 1 }, .{ "RecordDeferred", 2 } }) |item| {
        try js.define(engine, types, item[0], try @import("native_node_function.zig").create(engine, item[0], item[1], construct, &.{try s.text(item[0])}));
    }
    try js.define(engine, api, "Type", s.result(types));
    return s.result(api);
}

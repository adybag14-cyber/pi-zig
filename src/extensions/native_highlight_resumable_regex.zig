//! Original highlight.js10.7.3 ResumableMultiRegex compiler support.
//! Native methods and traced closures; private until differential qualification.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const classes = @import("native_class.zig");
const multi = @import("native_highlight_multi_regex.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum(c_int) { getMatcher, resumingScanAtSamePosition, considerAll, addRule, exec };

pub fn constructor(engine: *em.Engine, language: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const matcher_constructor = try scope.own(try multi.constructor(engine, language));
    const prototype = try scope.object();
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    var roots = [_]c.JSValue{matcher_constructor};
    inline for (@import("std").meta.fields(Method)) |field| {
        const arity: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .getMatcher, .exec => 1,
            .addRule => 2,
            else => 0,
        };
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, field.name, arity, @intCast(field.value), roots.len, &roots)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return classes.constructor(engine, "ResumableMultiRegex", 0, prototype, create, &.{});
}
fn create(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.own(try classes.object(engine, target));
    try scope.put(owner, "rules", try scope.array());
    try scope.put(owner, "multiRegexes", try scope.array());
    try scope.put(owner, "count", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "lastIndex", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "regexIndex", c.JS_NewInt32(engine.context, 0));
    return c.JS_DupValue(engine.context, owner);
}
fn methodCall(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, receiver, roots[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn invoke(engine: *em.Engine, owner: c.JSValue, matcher_constructor: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    switch (method) {
        .getMatcher => {
            const candidate = try scope.own(try js.getKey(engine, try scope.get(owner, "multiRegexes"), first));
            if (scope.truthy(candidate)) return js.getKey(engine, try scope.get(owner, "multiRegexes"), first);
            const matcher = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, matcher_constructor, 0, null)));
            const rules = try scope.get(owner, "rules");
            const remaining = try scope.invoke(rules, "slice", &.{first});
            const for_each = try scope.get(remaining, "forEach");
            var roots = [_]c.JSValue{matcher};
            const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, addEach, "", 1, 0, roots.len, &roots)));
            _ = try scope.call(for_each, remaining, &.{callback});
            _ = try scope.invoke(matcher, "compile", &.{});
            try js.setKey(engine, try scope.get(owner, "multiRegexes"), first, matcher);
            return c.JS_DupValue(engine.context, matcher);
        },
        .resumingScanAtSamePosition => return c.pi_js_bool(engine.context, @intFromBool(!scope.equal(try scope.get(owner, "regexIndex"), c.JS_NewInt32(engine.context, 0)))),
        .considerAll => try scope.set(owner, "regexIndex", c.JS_NewInt32(engine.context, 0)),
        .addRule => {
            const rules = try scope.get(owner, "rules");
            const push = try scope.get(rules, "push");
            const pair = try scope.array();
            try scope.index(pair, 0, first);
            const options = if (args.len > 1) args[1] else c.pi_js_undefined();
            try scope.index(pair, 1, options);
            _ = try scope.call(push, rules, &.{pair});
            if (scope.equal(try scope.get(options, "type"), try scope.text("begin"))) {
                const count = try scope.get(owner, "count");
                const next = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, count)));
                try scope.set(owner, "count", next);
            }
        },
        .exec => {
            const get_matcher = try scope.get(owner, "getMatcher");
            const matcher = try scope.call(get_matcher, owner, &.{try scope.get(owner, "regexIndex")});
            try scope.set(matcher, "lastIndex", try scope.get(owner, "lastIndex"));
            var result = try scope.invoke(matcher, "exec", &.{first});
            if (scope.truthy(try scope.invoke(owner, "resumingScanAtSamePosition", &.{}))) {
                const same_position = scope.truthy(result) and scope.equal(try scope.get(result, "index"), try scope.get(owner, "lastIndex"));
                if (!same_position) {
                    const all = try scope.invoke(owner, "getMatcher", &.{c.JS_NewInt32(engine.context, 0)});
                    try scope.set(all, "lastIndex", try scope.concat(try scope.get(owner, "lastIndex"), c.JS_NewInt32(engine.context, 1)));
                    result = try scope.invoke(all, "exec", &.{first});
                }
            }
            if (scope.truthy(result)) {
                const index = try scope.get(owner, "regexIndex");
                const advance = try scope.concat(try scope.get(result, "position"), c.JS_NewInt32(engine.context, 1));
                try scope.set(owner, "regexIndex", try scope.concat(index, advance));
                if (scope.equal(try scope.get(owner, "regexIndex"), try scope.get(owner, "count"))) _ = try scope.invoke(owner, "considerAll", &.{});
            }
            return c.JS_DupValue(engine.context, result);
        },
    }
    return c.pi_js_undefined();
}
fn addEach(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return addEntry(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn addEntry(engine: *em.Engine, matcher: c.JSValue, pair: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, pair, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const expression = if (try iterator.next()) |value| try scope.own(value) else c.pi_js_undefined();
    const options = if (!iterator.closed) blk: {
        break :blk if (try iterator.next()) |value| try scope.own(value) else c.pi_js_undefined();
    } else c.pi_js_undefined();
    try iterator.close();
    return c.JS_DupValue(engine.context, try scope.invoke(matcher, "addRule", &.{ expression, options }));
}

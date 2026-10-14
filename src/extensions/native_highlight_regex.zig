//! Original highlight.js10.7.3 regex-source, grouping and backreference helpers.
//! Private compiler support; not a grammar implementation or fallback.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

fn op(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn key(scope: *Scope, object: c.JSValue, name: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, object, name));
}
fn integer(scope: *Scope, value: i32) c.JSValue {
    return c.JS_NewInt32(scope.engine.context, value);
}
pub fn source(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    if (c.JS_ToBool(engine.context, value) != 1) return c.pi_js_null();
    return if (c.JS_IsString(value)) c.JS_DupValue(engine.context, value) else sdk.get(engine, value, "source");
}
fn backref(scope: *Scope) !c.JSValue {
    const name = "pi-native:highlight-backreference-regex";
    if (!scope.engine.native_module_values.contains(name)) {
        const exports = try scope.object();
        var arguments = [_]c.JSValue{try scope.text("\\[(?:[^\\\\\\]]|\\\\.)*\\]|\\(\\??|\\\\([1-9][0-9]*)|\\\\.")};
        const expression = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, arguments.len, &arguments)));
        try scope.put(exports, "expression", expression);
        try scope.engine.registerValueModule(name, exports);
    }
    return scope.get(scope.engine.native_module_values.get(name).?, "expression");
}
pub fn countMatchGroups(engine: *em.Engine, expression: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.global("RegExp");
    const text = try scope.concat(try scope.invoke(expression, "toString", &.{}), try scope.text("|"));
    var arguments = [_]c.JSValue{text};
    const regexp = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments)));
    const matched = try scope.invoke(regexp, "exec", &.{try scope.text("")});
    const count = try op(&scope, 1, try scope.get(matched, "length"), integer(&scope, 1));
    return c.JS_DupValue(engine.context, count);
}
pub fn startsWith(engine: *em.Engine, expression: c.JSValue, lexeme: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const matched = if (scope.truthy(expression)) try scope.invoke(expression, "exec", &.{lexeme}) else expression;
    const result = if (scope.truthy(matched)) c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(matched, "index"), integer(&scope, 0)))) else matched;
    return c.JS_DupValue(engine.context, result);
}
const Mapper = enum(c_int) { source, adjust_backrefs, wrap };
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return mapped(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn mapped(engine: *em.Engine, kind: Mapper, input: c.JSValue, state: c.JSValue) !c.JSValue {
    if (kind == .source) return source(engine, input);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (kind == .wrap) return c.JS_DupValue(engine.context, try scope.concat(try scope.concat(try scope.text("("), try scope.stringify(input)), try scope.text(")")));
    try scope.set(state, "numCaptures", try op(&scope, 0, try scope.get(state, "numCaptures"), integer(&scope, 1)));
    const offset = try scope.get(state, "numCaptures");
    var expression = try scope.own(try source(engine, input));
    var output = try scope.text("");
    var steps: usize = 0;
    while (scope.truthy(try op(&scope, 6, try scope.get(expression, "length"), integer(&scope, 0)))) {
        steps +|= 1;
        if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and interrupted: {
            engine.interrupts +|= 1;
            break :interrupted engine.interrupts > engine.options.interrupt_budget;
        })) {
            _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
            unreachable;
        }
        const matched = try scope.invoke(try backref(&scope), "exec", &.{expression});
        if (!scope.truthy(matched)) {
            output = try scope.concat(output, expression);
            break;
        }
        const prefix_method = try scope.get(expression, "substring");
        const prefix = try scope.call(prefix_method, expression, &.{ integer(&scope, 0), try scope.get(matched, "index") });
        output = try scope.concat(output, prefix);
        const tail_method = try scope.get(expression, "substring");
        const start = try scope.get(matched, "index");
        const matched_length = try scope.get(try key(&scope, matched, integer(&scope, 0)), "length");
        expression = try scope.call(tail_method, expression, &.{try op(&scope, 0, start, matched_length)});
        const first = try key(&scope, try key(&scope, matched, integer(&scope, 0)), integer(&scope, 0));
        if (scope.equal(first, try scope.text("\\")) and scope.truthy(try key(&scope, matched, integer(&scope, 1)))) {
            const string = try scope.global("String");
            const number = try scope.global("Number");
            const numeric = try scope.call(number, c.pi_js_undefined(), &.{try key(&scope, matched, integer(&scope, 1))});
            const adjusted = try scope.call(string, c.pi_js_undefined(), &.{try op(&scope, 0, numeric, offset)});
            output = try scope.concat(output, try scope.concat(try scope.text("\\"), adjusted));
        } else {
            output = try scope.concat(output, try key(&scope, matched, integer(&scope, 0)));
            if (scope.equal(try key(&scope, matched, integer(&scope, 0)), try scope.text("("))) {
                const value = try scope.get(state, "numCaptures");
                const next = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, value)));
                try scope.set(state, "numCaptures", next);
            }
        }
    }
    return c.JS_DupValue(engine.context, output);
}
fn map(scope: *Scope, array: c.JSValue, kind: Mapper, state: c.JSValue) !c.JSValue {
    const method = try scope.get(array, "map");
    var roots = [_]c.JSValue{state};
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), roots.len, &roots)));
    return scope.call(method, array, &.{function});
}
pub fn concat(engine: *em.Engine, args: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try scope.invoke(try map(&scope, args, .source, c.pi_js_undefined()), "join", &.{try scope.text("")}));
}
pub fn either(engine: *em.Engine, args: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const joined = try scope.invoke(try map(&scope, args, .source, c.pi_js_undefined()), "join", &.{try scope.text("|")});
    const result = try scope.concat(try scope.concat(try scope.text("("), joined), try scope.text(")"));
    return c.JS_DupValue(engine.context, result);
}
pub fn join(engine: *em.Engine, expressions: c.JSValue, supplied_separator: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const separator = if (c.JS_IsUndefined(supplied_separator)) try scope.text("|") else supplied_separator;
    const state = try scope.object();
    try scope.put(state, "numCaptures", integer(&scope, 0));
    const adjusted = try map(&scope, expressions, .adjust_backrefs, state);
    const wrapped = try map(&scope, adjusted, .wrap, c.pi_js_undefined());
    return c.JS_DupValue(engine.context, try scope.invoke(wrapped, "join", &.{separator}));
}

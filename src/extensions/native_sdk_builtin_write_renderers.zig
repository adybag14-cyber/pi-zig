//! Private actual write renderer bodies; requires the complete native highlighter.
//! No module/default-tool activation occurs here.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const utils = @import("native_sdk_builtin_render_utils.zig");
const cache_api = @import("native_sdk_write_highlight_cache.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
const Scope = temporary.Scope;
const c = em.c;
pub const Highlighter = cache_api.Highlighter;

fn integer(scope: *Scope, number: i32) c.JSValue {
    return c.JS_NewInt32(scope.engine.context, number);
}
fn op(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn key(scope: *Scope, object: c.JSValue, index: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, object, index));
}
fn rawPath(scope: *Scope, args: c.JSValue) !c.JSValue {
    const preferred = try utils.optional(scope, args, "file_path");
    return utils.str(scope, if (temporary.nullish(preferred)) try utils.optional(scope, args, "path") else preferred);
}
fn construct(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var arguments = [_]c.JSValue{ try scope.text(""), integer(&scope, 0), integer(&scope, 0) };
    const object = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, roots[0], target, arguments.len, &arguments)));
    try scope.put(object, "cache", c.pi_js_undefined());
    return c.JS_DupValue(engine.context, object);
}
pub fn constructor(engine: *em.Engine) !c.JSValue {
    const name = "pi-native:write-call-render-component";
    if (!engine.native_module_values.contains(name)) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const base = try scope.get(try utils.tui(&scope), "Text");
        const prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, try scope.get(base, "prototype"))));
        const type_value = try scope.own(try @import("native_class.zig").constructor(engine, "WriteCallRenderComponent", 0, prototype, construct, &.{base}));
        if (c.JS_SetPrototype(engine.context, type_value, base) < 0) return js.capture(engine);
        const exports = try scope.object();
        try scope.put(exports, "WriteCallRenderComponent", type_value);
        try engine.registerValueModule(name, exports);
    }
    return sdk.get(engine, engine.native_module_values.get(name).?, "WriteCallRenderComponent");
}
fn create(scope: *Scope, name: [*:0]const u8) !c.JSValue {
    const selected = if (@import("std").mem.eql(u8, name, "WriteCallRenderComponent")) try scope.own(try constructor(scope.engine)) else try scope.get(try utils.tui(scope), name);
    if (@import("std").mem.eql(u8, name, "Text")) {
        var arguments = [_]c.JSValue{ try scope.text(""), integer(scope, 0), integer(scope, 0) };
        return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, selected, arguments.len, &arguments)));
    }
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, selected, 0, null)));
}
const Mapper = enum(c_int) { display_line, text_block, raw_text };
fn mapper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return mapped(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
fn mapped(engine: *em.Engine, kind: Mapper, value: c.JSValue, theme: c.JSValue, language: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (kind) {
        .display_line => if (scope.truthy(language)) value else try utils.fg(&scope, theme, "toolOutput", try utils.replaceTabs(&scope, value)),
        .text_block => c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(value, "type"), try scope.text("text")))),
        .raw_text => raw: {
            const text = try scope.get(value, "text");
            break :raw if (scope.truthy(text)) text else try scope.text("");
        },
    };
    return c.JS_DupValue(engine.context, result);
}
fn map(scope: *Scope, array: c.JSValue, method_name: [*:0]const u8, kind: Mapper, theme: c.JSValue, language: c.JSValue) !c.JSValue {
    const method = try scope.get(array, method_name);
    var roots = [_]c.JSValue{ theme, language };
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, mapper, "", 1, @intFromEnum(kind), roots.len, &roots)));
    return scope.call(method, array, &.{function});
}
fn trimLines(scope: *Scope, lines: c.JSValue) !c.JSValue {
    var end = try scope.get(lines, "length");
    while (try scope.positive(end)) {
        if (!scope.equal(try key(scope, lines, try op(scope, 1, end, integer(scope, 1))), try scope.text(""))) break;
        end = try scope.own(try scope.engine.checked(c.JS_PiDecrement(scope.engine.context, end)));
    }
    return scope.invoke(lines, "slice", &.{ integer(scope, 0), end });
}
fn formatCall(scope: *Scope, api: Highlighter, args: c.JSValue, options: c.JSValue, theme: c.JSValue, cache: c.JSValue, cwd: c.JSValue) !c.JSValue {
    const path = try rawPath(scope, args);
    const content = try utils.str(scope, try utils.optional(scope, args, "content"));
    const path_display = try utils.renderToolPath(scope, path, theme, cwd, c.pi_js_undefined());
    var text = try scope.concat(try scope.concat(try scope.stringify(try utils.title(scope, theme, "write")), try scope.text(" ")), try scope.stringify(path_display));
    if (c.JS_IsNull(content)) {
        return scope.concat(text, try scope.concat(try scope.text("\n\n"), try scope.stringify(try utils.fg(scope, theme, "error", try scope.text("[invalid content arg - expected string]")))));
    }
    if (!scope.truthy(content)) return text;
    const language = if (scope.truthy(path)) try scope.own(try api.language(scope.engine, path)) else c.pi_js_undefined();
    const rendered = if (scope.truthy(language)) highlighted: {
        const stored = try utils.optional(scope, cache, "highlightedLines");
        break :highlighted if (!temporary.nullish(stored)) stored else try scope.own(try api.highlight(scope.engine, try utils.replaceTabs(scope, try utils.normalizeDisplayText(scope, content)), language));
    } else try scope.invoke(try utils.normalizeDisplayText(scope, content), "split", &.{try scope.text("\n")});
    const lines = try trimLines(scope, rendered);
    const total = try scope.get(lines, "length");
    const maximum = if (scope.truthy(try scope.get(options, "expanded"))) try scope.get(lines, "length") else integer(scope, 10);
    const display = try scope.invoke(lines, "slice", &.{ integer(scope, 0), maximum });
    const remaining = try op(scope, 1, try scope.get(lines, "length"), maximum);
    text = try scope.concat(text, try scope.concat(try scope.text("\n\n"), try scope.stringify(try scope.invoke(try map(scope, display, "map", .display_line, theme, language), "join", &.{try scope.text("\n")}))));
    if (try scope.positive(remaining)) {
        const message = try scope.concat(try utils.surround(scope, "\n... (", remaining, " more lines, "), try utils.surround(scope, "", total, " total,"));
        text = try scope.concat(text, try scope.stringify(try utils.fg(scope, theme, "muted", message)));
        text = try scope.concat(text, try scope.concat(try scope.text(" "), try scope.stringify(try utils.keyHint(scope, "app.tools.expand", "to expand"))));
        text = try scope.concat(text, try scope.stringify(try utils.fg(scope, theme, "muted", try scope.text(")"))));
    }
    return text;
}
fn formatResult(scope: *Scope, result: c.JSValue, theme: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(result, "isError"))) return c.pi_js_undefined();
    const texts = try map(scope, try scope.get(result, "content"), "filter", .text_block, c.pi_js_undefined(), c.pi_js_undefined());
    const output = try scope.invoke(try map(scope, texts, "map", .raw_text, c.pi_js_undefined(), c.pi_js_undefined()), "join", &.{try scope.text("\n")});
    if (!scope.truthy(output)) return c.pi_js_undefined();
    return scope.concat(try scope.text("\n"), try scope.stringify(try utils.fg(scope, theme, "error", output)));
}
pub fn renderCall(engine: *em.Engine, api: Highlighter, args: c.JSValue, theme: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = try rawPath(&scope, args);
    const content = try utils.str(&scope, try utils.optional(&scope, args, "content"));
    const last = try scope.get(context, "lastComponent");
    const component = if (temporary.nullish(last)) try create(&scope, "WriteCallRenderComponent") else last;
    const value = if (!c.JS_IsNull(content)) cache: {
        if (scope.truthy(try scope.get(context, "argsComplete"))) break :cache try scope.own(try cache_api.rebuild(engine, api, path, content));
        break :cache try scope.own(try cache_api.update(engine, api, try scope.get(component, "cache"), path, content));
    } else c.pi_js_undefined();
    try scope.set(component, "cache", value);
    const setter = try scope.get(component, "setText");
    const options = try scope.object();
    try scope.put(options, "expanded", try scope.get(context, "expanded"));
    try scope.put(options, "isPartial", try scope.get(context, "isPartial"));
    const cached = try scope.get(component, "cache");
    const cwd = try scope.get(context, "cwd");
    _ = try scope.call(setter, component, &.{try formatCall(&scope, api, args, options, theme, cached, cwd)});
    return c.JS_DupValue(engine.context, component);
}
pub fn renderResult(engine: *em.Engine, result: c.JSValue, theme: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = try scope.own(try js.spread(engine, result));
    try scope.put(input, "isError", try scope.get(context, "isError"));
    const output = try formatResult(&scope, input, theme);
    const last = try scope.get(context, "lastComponent");
    const component = if (!temporary.nullish(last)) last else try create(&scope, if (scope.truthy(output)) "Text" else "Container");
    if (scope.truthy(output)) {
        _ = try scope.invoke(component, "setText", &.{output});
    } else {
        _ = try scope.invoke(component, "clear", &.{});
    }
    return c.JS_DupValue(engine.context, component);
}

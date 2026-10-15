//! Actual createToolHtmlRenderer: caller renderers execute on the owner VM;
//! retained components, args and state remain ordinary per-renderer Maps.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const temp = @import("native_sdk_prompt_scope.zig");
const ansi = @import("native_export_ansi_html.zig");
const c = em.c;
const Method = enum(c_int) { renderCall, renderResult };

pub fn createFactory(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const regexp = try scope.own(try js.builtin(engine, "RegExp", &.{ try scope.text("\x1b\\[[\\d;]*m"), try scope.text("g") }));
    var roots = [_]c.JSValue{regexp};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, factory, "createToolHtmlRenderer", 1, 0, roots.len, &roots));
}
fn factory(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return create(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn create(engine: *em.Engine, deps: c.JSValue, regexp: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    inline for (.{ "getToolRenderers", "theme", "cwd" }) |name| try scope.put(owner, name, try scope.get(deps, name));
    const width = try scope.get(deps, "width");
    try scope.put(owner, "width", if (c.JS_IsUndefined(width)) c.JS_NewInt32(engine.context, 100) else width);
    try scope.put(owner, "blankRegex", regexp);
    inline for (.{ "calls", "results", "states", "args" }) |name| try scope.put(owner, name, try scope.own(try js.builtin(engine, "Map", &.{})));
    const result = try scope.object();
    inline for (@import("std").meta.fields(Method)) |field| {
        var roots = [_]c.JSValue{owner};
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, method, field.name, if (field.value == 0) 3 else 5, field.value, roots.len, &roots)));
        try scope.put(result, field.name, function);
    }
    return c.JS_DupValue(engine.context, result);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn method(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return render(engine, roots[0], @enumFromInt(magic), args) catch |err| {
        if (err == error.OutOfMemory) return sdk.fail(engine, err);
        // Source catches ordinary renderer failures without inspecting them.
        if (engine.captured_exception) |value| engine.freeValue(value);
        engine.captured_exception = null;
        return c.pi_js_undefined();
    };
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn contextValue(scope: *Scope, owner: c.JSValue, id: c.JSValue, last: c.JSValue, expanded: bool, partial: bool, failed: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "args", try scope.invoke(try scope.get(owner, "args"), "get", &.{id}));
    try scope.put(result, "toolCallId", id);
    try scope.put(result, "invalidate", try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, noop, "invalidate", 0))));
    try scope.put(result, "lastComponent", last);
    const states = try scope.get(owner, "states");
    var state = try scope.invoke(states, "get", &.{id});
    if (!scope.truthy(state)) {
        state = try scope.object();
        _ = try scope.invoke(states, "set", &.{ id, state });
    }
    try scope.put(result, "state", state);
    try scope.put(result, "cwd", try scope.get(owner, "cwd"));
    try scope.put(result, "executionStarted", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(result, "argsComplete", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(result, "isPartial", c.pi_js_bool(scope.engine.context, @intFromBool(partial)));
    try scope.put(result, "expanded", c.pi_js_bool(scope.engine.context, @intFromBool(expanded)));
    try scope.put(result, "showImages", c.pi_js_bool(scope.engine.context, 0));
    try scope.put(result, "isError", failed);
    try scope.put(result, "durationMs", c.pi_js_undefined());
    try scope.put(result, "outputPad", c.JS_NewInt32(scope.engine.context, 1));
    return result;
}
fn blank(scope: *Scope, value: c.JSValue, regexp: c.JSValue) !bool {
    const stripped = try scope.invoke(value, "replace", &.{ regexp, try scope.text("") });
    const trimmed = try scope.invoke(stripped, "trim", &.{});
    return scope.equal(try scope.get(trimmed, "length"), c.JS_NewInt32(scope.engine.context, 0));
}
fn trim(scope: *Scope, lines: c.JSValue, regexp: c.JSValue) !c.JSValue {
    var start: u32 = 0;
    var end = try sdk.length(scope.engine, lines);
    while (start < end) {
        const value = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, lines, start)));
        if (!try blank(scope, value, regexp)) break;
        start += 1;
    }
    while (end > start) {
        const value = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, lines, end - 1)));
        if (!try blank(scope, value, regexp)) break;
        end -= 1;
    }
    return scope.invoke(lines, "slice", &.{ c.JS_NewInt64(scope.engine.context, start), c.JS_NewInt64(scope.engine.context, end) });
}
fn render(engine: *em.Engine, owner: c.JSValue, kind: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = argument(args, 0);
    if (kind == .renderCall) _ = try scope.invoke(try scope.get(owner, "args"), "set", &.{ id, argument(args, 2) });
    const definition = try scope.call(try scope.get(owner, "getToolRenderers"), c.pi_js_undefined(), &.{argument(args, 1)});
    const first_method = if (temp.nullish(definition)) c.pi_js_undefined() else try scope.get(definition, @tagName(kind));
    if (!scope.truthy(first_method)) return c.pi_js_undefined();
    const theme = try scope.get(owner, "theme");
    const width = try scope.get(owner, "width");
    if (kind == .renderCall) {
        const callback = try scope.get(definition, "renderCall");
        const previous = try scope.invoke(try scope.get(owner, "calls"), "get", &.{id});
        const context = try contextValue(&scope, owner, id, previous, false, true, c.pi_js_bool(engine.context, 0));
        const component = try scope.call(callback, definition, &.{ argument(args, 2), theme, context });
        _ = try scope.invoke(try scope.get(owner, "calls"), "set", &.{ id, component });
        return ansi.ansiLinesToHtml(engine, try scope.invoke(component, "render", &.{width}));
    }
    const result = try scope.object();
    try scope.put(result, "content", argument(args, 2));
    try scope.put(result, "details", argument(args, 3));
    try scope.put(result, "isError", argument(args, 4));
    var rendered: [2]c.JSValue = undefined;
    for (0..2) |index| {
        const callback = try scope.get(definition, "renderResult");
        const options = try scope.object();
        try scope.put(options, "expanded", c.pi_js_bool(engine.context, @intFromBool(index == 1)));
        try scope.put(options, "isPartial", c.pi_js_bool(engine.context, 0));
        const previous = try scope.invoke(try scope.get(owner, "results"), "get", &.{id});
        const context = try contextValue(&scope, owner, id, previous, index == 1, false, argument(args, 4));
        const component = try scope.call(callback, definition, &.{ result, options, theme, context });
        _ = try scope.invoke(try scope.get(owner, "results"), "set", &.{ id, component });
        const lines = try trim(&scope, try scope.invoke(component, "render", &.{width}), try scope.get(owner, "blankRegex"));
        rendered[index] = try scope.own(try ansi.ansiLinesToHtml(engine, lines));
    }
    const output = try scope.object();
    if (scope.truthy(rendered[0]) and !scope.equal(rendered[0], rendered[1])) try scope.put(output, "collapsed", rendered[0]);
    try scope.put(output, "expanded", rendered[1]);
    return c.JS_DupValue(engine.context, output);
}

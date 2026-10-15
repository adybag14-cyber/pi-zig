//! Original shell presentation; real native Text/Container, timer and visual preview.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const utils = @import("native_sdk_builtin_render_utils.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
const Scope = utils.Scope;
const c = em.c;

fn theme(scope: *Scope) !c.JSValue {
    const exports = scope.engine.native_module_values.get("pi-coding-agent") orelse return error.NativeThemeModuleUnavailable;
    return scope.get(exports, "theme");
}
fn colorTemplate(scope: *Scope, token: []const u8, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    const current = try theme(scope);
    const function = try scope.get(current, "fg");
    const name = try scope.text(token);
    return scope.call(function, current, &.{ name, try utils.surround(scope, prefix, value, suffix) });
}
fn construct(scope: *Scope, name: [*:0]const u8, arguments: []const c.JSValue) !c.JSValue {
    const constructor = try scope.get(try utils.tui(scope), name);
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, @intCast(arguments.len), @constCast(arguments.ptr))));
}
fn textComponent(scope: *Scope, text: c.JSValue) !c.JSValue {
    return construct(scope, "Text", &.{ text, c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 0) });
}
fn formatCall(scope: *Scope, args: c.JSValue, prompt: c.JSValue) !c.JSValue {
    const command = try utils.str(scope, try utils.optional(scope, args, "command"));
    const timeout = try utils.optional(scope, args, "timeout");
    const timeout_suffix = if (scope.truthy(timeout)) try colorTemplate(scope, "muted", " (timeout ", timeout, "s)") else try scope.text("");
    const current = try theme(scope);
    const display = if (c.JS_IsNull(command)) try utils.invalidArg(scope, current) else if (scope.truthy(command)) command else try utils.fg(scope, current, "toolOutput", try scope.text("..."));
    const color = try scope.get(current, "fg");
    const title = try scope.text("toolTitle");
    const bold = try scope.get(current, "bold");
    const line = try scope.concat(try scope.concat(try scope.stringify(prompt), try scope.text(" ")), try scope.stringify(display));
    return scope.concat(try scope.call(color, current, &.{ title, try scope.call(bold, current, &.{line}) }), timeout_suffix);
}
fn hint(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return hintValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn hintValue(engine: *em.Engine, hidden: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = try colorTemplate(&scope, "muted", "... (", hidden, " earlier lines,");
    var suffix = try scope.concat(try scope.text(" "), try scope.stringify(try utils.keyHint(&scope, "app.tools.expand", "to expand")));
    suffix = try scope.concat(suffix, try scope.stringify(try utils.fg(&scope, try theme(&scope), "muted", try scope.text(")"))));
    return c.JS_DupValue(engine.context, try scope.concat(first, suffix));
}
fn detail(scope: *Scope, result: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return utils.optional(scope, try scope.get(result, "details"), key);
}
fn warningPush(scope: *Scope, warnings: c.JSValue, prefix: []const u8, value: c.JSValue) !void {
    const push = try scope.get(warnings, "push");
    _ = try scope.call(push, warnings, &.{try utils.surround(scope, prefix, value, "")});
}
fn rebuild(scope: *Scope, component: c.JSValue, result: c.JSValue, options: c.JSValue, show_images: c.JSValue, timer_text: c.JSValue) !void {
    const engine = scope.engine;
    _ = try scope.invoke(component, "clear", &.{});
    var output = try scope.invoke(try utils.textOutput(scope, result, show_images), "trim", &.{});
    const truncation = try detail(scope, result, "truncation");
    const full_path = try detail(scope, result, "fullOutputPath");
    if (!scope.truthy(try scope.get(options, "isPartial")) and scope.truthy(try utils.optional(scope, truncation, "truncated")) and scope.truthy(full_path) and scope.truthy(try scope.invoke(output, "endsWith", &.{try scope.text("]")}))) {
        const footer = try scope.invoke(output, "lastIndexOf", &.{try scope.text("\n\n[")});
        if (!scope.equal(footer, c.JS_NewInt32(engine.context, -1)) and scope.truthy(try scope.invoke(try scope.invoke(output, "slice", &.{footer}), "includes", &.{full_path}))) {
            output = try scope.invoke(try scope.invoke(output, "slice", &.{ c.JS_NewInt32(engine.context, 0), footer }), "trimEnd", &.{});
        }
    }
    if (scope.truthy(output)) {
        const styled = try scope.invoke(try utils.map(scope, try scope.invoke(output, "split", &.{try scope.text("\n")}), "map", .styled_line, try theme(scope)), "join", &.{try scope.text("\n")});
        if (scope.truthy(try scope.get(options, "expanded"))) {
            const add = try scope.get(component, "addChild");
            _ = try scope.call(add, component, &.{try textComponent(scope, try scope.concat(try scope.text("\n"), try scope.stringify(styled)))});
        } else {
            const add_spacer = try scope.get(component, "addChild");
            _ = try scope.call(add_spacer, component, &.{try construct(scope, "Spacer", &.{c.JS_NewInt32(engine.context, 1)})});
            const add_preview = try scope.get(component, "addChild");
            const preview_options = try scope.object();
            try scope.put(preview_options, "text", styled);
            try scope.put(preview_options, "maxVisualLines", c.JS_NewInt32(engine.context, 5));
            try scope.put(preview_options, "keep", try scope.text("end"));
            try scope.put(preview_options, "formatHint", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, hint, "formatHint", 1))));
            const preview = try scope.own(try @import("native_sdk_visual_line_preview.zig").create(engine, preview_options));
            _ = try scope.call(add_preview, component, &.{preview});
        }
    }
    if (scope.truthy(try utils.optional(scope, truncation, "truncated")) or scope.truthy(full_path)) {
        const warnings = try scope.array();
        if (scope.truthy(full_path)) try warningPush(scope, warnings, "Full output: ", full_path);
        if (scope.truthy(try utils.optional(scope, truncation, "truncated"))) {
            if (scope.equal(try scope.get(truncation, "truncatedBy"), try scope.text("lines"))) {
                const push = try scope.get(warnings, "push");
                var line = try utils.surround(scope, "Truncated: showing ", try scope.get(truncation, "outputLines"), " of ");
                line = try scope.concat(line, try utils.surround(scope, "", try scope.get(truncation, "totalLines"), " lines"));
                _ = try scope.call(push, warnings, &.{line});
            } else {
                const push = try scope.get(warnings, "push");
                const first = try utils.surround(scope, "Truncated: ", try scope.get(truncation, "outputLines"), " lines shown (");
                const bytes = try scope.get(truncation, "maxBytes");
                const size = try utils.formatSize(scope, if (temporary.nullish(bytes)) c.JS_NewInt32(engine.context, 50 * 1024) else bytes);
                _ = try scope.call(push, warnings, &.{try scope.concat(first, try utils.surround(scope, "", size, " limit)"))});
            }
        }
        const add = try scope.get(component, "addChild");
        const current = try theme(scope);
        const color = try scope.get(current, "fg");
        const token = try scope.text("warning");
        const joined = try scope.invoke(warnings, "join", &.{try scope.text(". ")});
        const colored = try scope.call(color, current, &.{ token, try utils.surround(scope, "[", joined, "]") });
        _ = try scope.call(add, component, &.{try textComponent(scope, try utils.surround(scope, "\n", colored, ""))});
    }
    if (scope.truthy(timer_text)) {
        const add = try scope.get(component, "addChild");
        const colored = try utils.fg(scope, try theme(scope), "muted", timer_text);
        _ = try scope.call(add, component, &.{try textComponent(scope, try utils.surround(scope, "\n", colored, ""))});
    }
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return render(engine, magic == 1, if (magic == 0) roots[0] else c.pi_js_undefined(), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn render(engine: *em.Engine, result: bool, prompt: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const context = argument(args, if (result) 3 else 2);
    if (!result) {
        try utils.startTimer(&scope, context);
        const last = try scope.get(context, "lastComponent");
        const component = if (temporary.nullish(last)) try textComponent(&scope, try scope.text("")) else last;
        const setter = try scope.get(component, "setText");
        _ = try scope.call(setter, component, &.{try formatCall(&scope, argument(args, 0), prompt)});
        return c.JS_DupValue(engine.context, component);
    }
    const options = argument(args, 1);
    const timer_text = try utils.timerText(&scope, context, try scope.get(options, "isPartial"));
    const last = try scope.get(context, "lastComponent");
    const component = if (temporary.nullish(last)) try construct(&scope, "Container", &.{}) else last;
    try rebuild(&scope, component, argument(args, 0), options, try scope.get(context, "showImages"), timer_text);
    _ = try scope.invoke(component, "invalidate", &.{});
    return c.JS_DupValue(engine.context, component);
}
pub fn create(engine: *em.Engine, prompt: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    var roots = [_]c.JSValue{prompt};
    try sdk.put(engine, result, "renderCall", try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "renderCall", 3, 0, roots.len, &roots)));
    try sdk.put(engine, result, "renderResult", try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "renderResult", 4, 1, 0, null)));
    return result;
}

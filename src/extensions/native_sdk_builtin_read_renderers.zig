//! Source b45e0eb read renderer draft. Private; full highlighter/config required.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const utils = @import("native_sdk_builtin_render_utils.zig");
const source_paths = @import("native_sdk_source_paths.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
const Scope = temporary.Scope;
const c = em.c;
pub const Runtime = struct {
    highlighter: @import("native_sdk_write_highlight_cache.zig").Highlighter,
    get_readme: *const fn (*em.Engine) anyerror!c.JSValue,
};
fn integer(scope: *Scope, value: i32) c.JSValue {
    return c.JS_NewInt32(scope.engine.context, value);
}
fn op(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn path(scope: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    if (!scope.engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(scope.engine, scope.engine.native_io orelse return error.NativeReadRendererRequiresIo);
    return scope.call(try scope.get(scope.engine.native_module_values.get("node:path").?, name), c.pi_js_undefined(), args);
}
fn separator(scope: *Scope) !c.JSValue {
    return scope.get(scope.engine.native_module_values.get("node:path").?, "sep");
}
fn rawPath(scope: *Scope, args: c.JSValue) !c.JSValue {
    const preferred = try utils.optional(scope, args, "file_path");
    return utils.str(scope, if (temporary.nullish(preferred)) try utils.optional(scope, args, "path") else preferred);
}
fn lineRange(scope: *Scope, args: c.JSValue, theme: c.JSValue) !c.JSValue {
    const offset = try utils.optional(scope, args, "offset");
    const limit = try utils.optional(scope, args, "limit");
    const range = try @import("native_sdk_read_line_range.zig").format(scope, offset, limit);
    return if (scope.truthy(range)) utils.fg(scope, theme, "warning", range) else scope.text("");
}
fn classification(scope: *Scope, kind: []const u8, label: c.JSValue) !c.JSValue {
    const value = try scope.object();
    try scope.put(value, "kind", try scope.text(kind));
    try scope.put(value, "label", label);
    return value;
}
fn docs(scope: *Scope, api: Runtime, absolute: c.JSValue) !c.JSValue {
    const package_root = try path(scope, "dirname", &.{try scope.own(try api.get_readme(scope.engine))});
    const resolved_package = try path(scope, "resolve", &.{package_root});
    const resolved_file = try path(scope, "resolve", &.{absolute});
    const relative = try path(scope, "relative", &.{ resolved_package, resolved_file });
    if (scope.equal(relative, try scope.text("")) or scope.equal(relative, try scope.text("..")) or scope.truthy(try scope.invoke(relative, "startsWith", &.{try scope.concat(try scope.text(".."), try scope.stringify(try separator(scope)))})) or scope.truthy(try path(scope, "isAbsolute", &.{relative}))) return c.pi_js_undefined();
    const label = try scope.invoke(try scope.invoke(relative, "split", &.{try separator(scope)}), "join", &.{try scope.text("/")});
    if (scope.equal(label, try scope.text("README.md")) or scope.truthy(try scope.invoke(label, "startsWith", &.{try scope.text("docs/")})) or scope.truthy(try scope.invoke(label, "startsWith", &.{try scope.text("examples/")}))) return classification(scope, "docs", label);
    return c.pi_js_undefined();
}
fn resourceNames(scope: *Scope) !c.JSValue {
    const name = "pi-native:read-compact-resource-file-names";
    if (!scope.engine.native_module_values.contains(name)) {
        const values = try scope.array();
        inline for (.{ "AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD" }, 0..) |value, index| try scope.index(values, index, try scope.text(value));
        const constructor = try scope.global("Set");
        var args = [_]c.JSValue{values};
        const set = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
        const exports = try scope.object();
        try scope.put(exports, "names", set);
        try scope.engine.registerValueModule(name, exports);
    }
    return scope.get(scope.engine.native_module_values.get(name).?, "names");
}
fn compactClassification(scope: *Scope, api: Runtime, args: c.JSValue, cwd: c.JSValue) !c.JSValue {
    const raw = try rawPath(scope, args);
    if (!scope.truthy(raw)) return c.pi_js_undefined();
    const options = try scope.object();
    try scope.put(options, "normalizeUnicodeSpaces", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(options, "stripAtPrefix", c.pi_js_bool(scope.engine.context, 1));
    const absolute = try scope.own(try source_paths.resolve(scope.engine, raw, cwd, options));
    const file_name = try path(scope, "basename", &.{absolute});
    if (scope.equal(file_name, try scope.text("SKILL.md"))) {
        const parent = try path(scope, "basename", &.{try path(scope, "dirname", &.{absolute})});
        return classification(scope, "skill", if (scope.truthy(parent)) parent else file_name);
    }
    const documented = try docs(scope, api, absolute);
    if (scope.truthy(documented)) return documented;
    if (scope.truthy(try scope.invoke(try resourceNames(scope), "has", &.{file_name}))) return classification(scope, "resource", try scope.own(try source_paths.display(scope.engine, absolute, cwd)));
    return c.pi_js_undefined();
}
fn formatCall(scope: *Scope, args: c.JSValue, theme: c.JSValue, cwd: c.JSValue) !c.JSValue {
    const display = try utils.renderToolPath(scope, try rawPath(scope, args), theme, cwd, c.pi_js_undefined());
    var text = try scope.concat(try scope.concat(try scope.stringify(try utils.title(scope, theme, "read")), try scope.text(" ")), try scope.stringify(display));
    text = try scope.concat(text, try scope.stringify(try lineRange(scope, args, theme)));
    return text;
}
fn compactCall(scope: *Scope, classified: c.JSValue, args: c.JSValue, theme: c.JSValue) !c.JSValue {
    const color = try scope.get(theme, "fg");
    const token = try scope.text("dim");
    const hint = try scope.call(color, theme, &.{ token, try utils.surround(scope, " (", try utils.keyText(scope, "app.tools.expand"), " to expand)") });
    if (scope.equal(try scope.get(classified, "kind"), try scope.text("skill"))) {
        var text = try utils.fg(scope, theme, "customMessageLabel", try scope.text("\x1b[1m[skill]\x1b[22m "));
        text = try scope.concat(text, try utils.fg(scope, theme, "customMessageText", try scope.get(classified, "label")));
        text = try scope.concat(text, try lineRange(scope, args, theme));
        return scope.concat(text, hint);
    }
    const title_color = try scope.get(theme, "fg");
    const title_token = try scope.text("toolTitle");
    const bold = try scope.get(theme, "bold");
    const title = try scope.call(title_color, theme, &.{ title_token, try scope.call(bold, theme, &.{try utils.surround(scope, "read ", try scope.get(classified, "kind"), "")}) });
    var text = try scope.concat(title, try scope.text(" "));
    text = try scope.concat(text, try utils.fg(scope, theme, "accent", try scope.get(classified, "label")));
    text = try scope.concat(text, try lineRange(scope, args, theme));
    return scope.concat(text, hint);
}
fn trimLines(scope: *Scope, lines: c.JSValue) !c.JSValue {
    var end = try scope.get(lines, "length");
    while (try scope.positive(end)) {
        const last = try op(scope, 1, end, integer(scope, 1));
        if (!scope.equal(try scope.own(try js.getKey(scope.engine, lines, last)), try scope.text(""))) break;
        end = try scope.own(try scope.engine.checked(c.JS_PiDecrement(scope.engine.context, end)));
    }
    return scope.invoke(lines, "slice", &.{ integer(scope, 0), end });
}
fn lineCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return line(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
fn line(engine: *em.Engine, value: c.JSValue, theme: c.JSValue, language: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(language)) return c.JS_DupValue(engine.context, try utils.replaceTabs(&scope, value));
    const color = try scope.get(theme, "fg");
    const token = try scope.text("toolOutput");
    return c.JS_DupValue(engine.context, try scope.call(color, theme, &.{ token, try utils.replaceTabs(&scope, value) }));
}
fn formatResult(scope: *Scope, api: Runtime, args: c.JSValue, result: c.JSValue, options: c.JSValue, theme: c.JSValue, show_images: c.JSValue, is_error: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(options, "expanded")) and !scope.truthy(is_error)) return scope.text("");
    const raw = try rawPath(scope, args);
    const output = try utils.textOutput(scope, result, show_images);
    const language = if (!scope.truthy(is_error) and scope.truthy(raw)) try scope.own(try api.highlighter.language(scope.engine, raw)) else c.pi_js_undefined();
    const rendered = if (scope.truthy(language)) try scope.own(try api.highlighter.highlight(scope.engine, try utils.replaceTabs(scope, output), language)) else try scope.invoke(output, "split", &.{try scope.text("\n")});
    const lines = try trimLines(scope, rendered);
    const maximum = if (scope.truthy(try scope.get(options, "expanded"))) try scope.get(lines, "length") else integer(scope, 10);
    const display = try scope.invoke(lines, "slice", &.{ integer(scope, 0), maximum });
    const remaining = try op(scope, 1, try scope.get(lines, "length"), maximum);
    const map = try scope.get(display, "map");
    var roots = [_]c.JSValue{ theme, language };
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, lineCall, "", 1, 0, roots.len, &roots)));
    const mapped = try scope.call(map, display, &.{callback});
    var text = try scope.concat(try scope.text("\n"), try scope.stringify(try scope.invoke(mapped, "join", &.{try scope.text("\n")})));
    if (try scope.positive(remaining)) {
        const color = try scope.get(theme, "fg");
        const token = try scope.text("muted");
        const first = try scope.call(color, theme, &.{ token, try utils.surround(scope, "\n... (", remaining, " more lines,") });
        text = try scope.concat(text, try scope.concat(try scope.stringify(first), try scope.text(" ")));
        text = try scope.concat(text, try scope.stringify(try utils.keyHint(scope, "app.tools.expand", "to expand")));
        text = try scope.concat(text, try scope.stringify(try utils.fg(scope, theme, "muted", try scope.text(")"))));
    }
    const truncation = try utils.optional(scope, try scope.get(result, "details"), "truncation");
    if (scope.truthy(try utils.optional(scope, truncation, "truncated"))) {
        const first_exceeds = scope.truthy(try scope.get(truncation, "firstLineExceedsLimit"));
        const by_lines = if (!first_exceeds) scope.equal(try scope.get(truncation, "truncatedBy"), try scope.text("lines")) else false;
        const color = try scope.get(theme, "fg");
        const token = try scope.text("warning");
        var warning: c.JSValue = undefined;
        if (by_lines) {
            warning = try utils.surround(scope, "[Truncated: showing ", try scope.get(truncation, "outputLines"), " of ");
            warning = try scope.concat(warning, try utils.surround(scope, "", try scope.get(truncation, "totalLines"), " lines ("));
            const limit = try scope.get(truncation, "maxLines");
            warning = try scope.concat(warning, try utils.surround(scope, "", if (temporary.nullish(limit)) integer(scope, 2000) else limit, " line limit)]"));
        } else {
            if (!first_exceeds) warning = try utils.surround(scope, "[Truncated: ", try scope.get(truncation, "outputLines"), " lines shown (");
            const bytes = try scope.get(truncation, "maxBytes");
            const size = try utils.formatSize(scope, if (temporary.nullish(bytes)) integer(scope, 50 * 1024) else bytes);
            warning = if (first_exceeds) try utils.surround(scope, "[First line exceeds ", size, " limit]") else try scope.concat(warning, try utils.surround(scope, "", size, " limit)]"));
        }
        text = try scope.concat(text, try scope.concat(try scope.text("\n"), try scope.stringify(try scope.call(color, theme, &.{ token, warning }))));
    }
    return text;
}
fn component(scope: *Scope, context: c.JSValue) !c.JSValue {
    const last = try scope.get(context, "lastComponent");
    if (!temporary.nullish(last)) return last;
    const constructor = try scope.get(try utils.tui(scope), "Text");
    var args = [_]c.JSValue{ try scope.text(""), integer(scope, 0), integer(scope, 0) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
pub fn renderCall(engine: *em.Engine, api: Runtime, args: c.JSValue, theme: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = try component(&scope, context);
    const classified = if (!scope.truthy(try scope.get(context, "expanded"))) try compactClassification(&scope, api, args, try scope.get(context, "cwd")) else c.pi_js_undefined();
    const setter = try scope.get(text, "setText");
    const content = if (scope.truthy(classified)) try compactCall(&scope, classified, args, theme) else try formatCall(&scope, args, theme, try scope.get(context, "cwd"));
    _ = try scope.call(setter, text, &.{content});
    return c.JS_DupValue(engine.context, text);
}
pub fn renderResult(engine: *em.Engine, api: Runtime, result: c.JSValue, options: c.JSValue, theme: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = try component(&scope, context);
    const setter = try scope.get(text, "setText");
    const args = try scope.get(context, "args");
    const show_images = try scope.get(context, "showImages");
    _ = try scope.get(context, "cwd");
    const is_error = try scope.get(context, "isError");
    _ = try scope.call(setter, text, &.{try formatResult(&scope, api, args, result, options, theme, show_images, is_error)});
    return c.JS_DupValue(engine.context, text);
}

//! Actual Source find/ls/grep presentation bodies. Private renderer composition.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const utils = @import("native_sdk_builtin_render_utils.zig");
const Scope = utils.Scope;
const temporary = @import("native_sdk_prompt_scope.zig");
const c = em.c;
const Kind = enum(c_int) { find, ls, grep };

fn colorTemplate(scope: *Scope, theme: c.JSValue, token: []const u8, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    const function = try scope.get(theme, "fg");
    const name = try scope.text(token);
    return scope.call(function, theme, &.{ name, try utils.surround(scope, prefix, value, suffix) });
}
fn formatCall(scope: *Scope, kind: Kind, args: c.JSValue, theme: c.JSValue, cwd: c.JSValue) !c.JSValue {
    if (kind == .ls) {
        const limit = try utils.optional(scope, args, "limit");
        const path = try utils.renderToolPath(scope, try utils.str(scope, try utils.optional(scope, args, "path")), theme, cwd, try scope.text("."));
        var text = try scope.concat(try scope.concat(try scope.stringify(try utils.title(scope, theme, "ls")), try scope.text(" ")), try scope.stringify(path));
        if (!c.JS_IsUndefined(limit)) text = try scope.concat(text, try colorTemplate(scope, theme, "toolOutput", " (limit ", limit, ")"));
        return text;
    }
    const pattern = try utils.str(scope, try utils.optional(scope, args, "pattern"));
    const raw_path = try utils.str(scope, try utils.optional(scope, args, "path"));
    const path = if (!c.JS_IsNull(raw_path)) try utils.shortenPath(scope, if (scope.truthy(raw_path)) raw_path else try scope.text(".")) else c.pi_js_null();
    const glob = if (kind == .grep) try utils.str(scope, try utils.optional(scope, args, "glob")) else c.pi_js_undefined();
    const limit = try utils.optional(scope, args, "limit");
    const invalid = try utils.invalidArg(scope, theme);
    var text = try scope.concat(try utils.title(scope, theme, @tagName(kind)), try scope.text(" "));
    const highlighted = if (c.JS_IsNull(pattern)) invalid else if (kind == .grep)
        try colorTemplate(scope, theme, "accent", "/", if (scope.truthy(pattern)) pattern else try scope.text(""), "/")
    else
        try utils.fg(scope, theme, "accent", if (scope.truthy(pattern)) pattern else try scope.text(""));
    text = try scope.concat(text, highlighted);
    text = try scope.concat(text, try colorTemplate(scope, theme, "toolOutput", " in ", if (c.JS_IsNull(path)) invalid else path, ""));
    if (kind == .grep and scope.truthy(glob)) text = try scope.concat(text, try colorTemplate(scope, theme, "toolOutput", " (", glob, ")"));
    if (!c.JS_IsUndefined(limit)) text = try scope.concat(text, try colorTemplate(scope, theme, "toolOutput", if (kind == .grep) " limit " else " (limit ", limit, if (kind == .grep) "" else ")"));
    return text;
}
fn detail(scope: *Scope, result: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return utils.optional(scope, try scope.get(result, "details"), key);
}
fn appendWarning(scope: *Scope, warnings: c.JSValue, value: c.JSValue, suffix: []const u8) !void {
    const push = try scope.get(warnings, "push");
    _ = try scope.call(push, warnings, &.{try utils.surround(scope, "", value, suffix)});
}
fn formatResult(scope: *Scope, kind: Kind, result: c.JSValue, options: c.JSValue, theme: c.JSValue, show_images: c.JSValue) !c.JSValue {
    const output = try scope.invoke(try utils.textOutput(scope, result, show_images), "trim", &.{});
    var text = try scope.text("");
    if (scope.truthy(output)) {
        const lines = try scope.invoke(output, "split", &.{try scope.text("\n")});
        const maximum = if (scope.truthy(try scope.get(options, "expanded"))) try scope.get(lines, "length") else c.JS_NewInt32(scope.engine.context, if (kind == .grep) 15 else 20);
        const display = try scope.invoke(lines, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), maximum });
        const remaining = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, try scope.get(lines, "length"), maximum)));
        text = try scope.concat(text, try scope.concat(try scope.text("\n"), try scope.stringify(try scope.invoke(try utils.map(scope, display, "map", .styled_line, theme), "join", &.{try scope.text("\n")}))));
        if (try scope.positive(remaining)) {
            const first = try colorTemplate(scope, theme, "muted", "\n... (", remaining, " more lines,");
            var suffix = try scope.concat(try scope.concat(try scope.stringify(first), try scope.text(" ")), try scope.stringify(try utils.keyHint(scope, "app.tools.expand", "to expand")));
            suffix = try scope.concat(suffix, try scope.stringify(try utils.fg(scope, theme, "muted", try scope.text(")"))));
            text = try scope.concat(text, suffix);
        }
    }
    const limit = try detail(scope, result, switch (kind) {
        .find => "resultLimitReached",
        .ls => "entryLimitReached",
        .grep => "matchLimitReached",
    });
    const truncation = try detail(scope, result, "truncation");
    const lines_truncated = if (kind == .grep) try detail(scope, result, "linesTruncated") else c.pi_js_undefined();
    if (scope.truthy(limit) or scope.truthy(try utils.optional(scope, truncation, "truncated")) or (kind == .grep and scope.truthy(lines_truncated))) {
        const warnings = try scope.array();
        if (scope.truthy(limit)) try appendWarning(scope, warnings, limit, switch (kind) {
            .find => " results limit",
            .ls => " entries limit",
            .grep => " matches limit",
        });
        if (scope.truthy(try utils.optional(scope, truncation, "truncated"))) {
            const push = try scope.get(warnings, "push");
            const bytes = try scope.get(truncation, "maxBytes");
            const formatted = try utils.formatSize(scope, if (temporary.nullish(bytes)) c.JS_NewInt32(scope.engine.context, 50 * 1024) else bytes);
            _ = try scope.call(push, warnings, &.{try utils.surround(scope, "", formatted, " limit")});
        }
        if (kind == .grep and scope.truthy(lines_truncated)) _ = try scope.invoke(warnings, "push", &.{try scope.text("some lines truncated")});
        const color = try scope.get(theme, "fg");
        const token = try scope.text("warning");
        const warning_text = try utils.surround(scope, "[Truncated: ", try scope.invoke(warnings, "join", &.{try scope.text(", ")}), "]");
        const colored = try scope.call(color, theme, &.{ token, warning_text });
        text = try scope.concat(text, try scope.concat(try scope.text("\n"), try scope.stringify(colored)));
    }
    return text;
}
fn component(scope: *Scope, context: c.JSValue) !c.JSValue {
    const last = try scope.get(context, "lastComponent");
    if (!temporary.nullish(last)) return last;
    const constructor = try scope.get(try utils.tui(scope), "Text");
    var args = [_]c.JSValue{ try scope.text(""), c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 0) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return render(engine, @enumFromInt(@divTrunc(magic, 2)), @mod(magic, 2) == 1, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn render(engine: *em.Engine, kind: Kind, result: bool, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const theme = argument(args, if (result) 2 else 1);
    const context = argument(args, if (result) 3 else 2);
    const text = try component(&scope, context);
    const setter = try scope.get(text, "setText");
    const content = if (result)
        try formatResult(&scope, kind, argument(args, 0), argument(args, 1), theme, try scope.get(context, "showImages"))
    else
        try formatCall(&scope, kind, argument(args, 0), theme, if (kind == .ls) try scope.get(context, "cwd") else c.pi_js_undefined());
    _ = try scope.call(setter, text, &.{content});
    return c.JS_DupValue(engine.context, text);
}
pub fn get(engine: *em.Engine, name: []const u8) !c.JSValue {
    const kind: Kind = if (std.mem.eql(u8, name, "find")) .find else if (std.mem.eql(u8, name, "ls")) .ls else if (std.mem.eql(u8, name, "grep")) .grep else return error.UnknownListingRenderer;
    const module_name = "pi-native:tool-listing-renderers";
    if (!engine.native_module_values.contains(module_name)) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const exports = try scope.object();
        inline for (std.meta.fields(Kind)) |field| {
            const renderers = try scope.object();
            inline for (.{ "renderCall", "renderResult" }, 0..) |method, offset| {
                const function = try engine.checked(c.pi_js_function_magic(engine.context, callback, method, if (offset == 0) 3 else 4, @intCast(field.value * 2 + offset)));
                try sdk.put(engine, renderers, method, function);
            }
            try scope.put(exports, field.name, renderers);
        }
        try engine.registerValueModule(module_name, exports);
    }
    return sdk.get(engine, engine.native_module_values.get(module_name).?, @tagName(kind));
}

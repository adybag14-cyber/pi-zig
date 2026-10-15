//! Source export-html/index.ts, emitting original browser assets as data.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const theme = @import("native_export_theme.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
fn iter(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
}
fn templateTool(scope: *Scope, name: c.JSValue) !bool {
    inline for (.{ "bash", "read", "write", "edit", "ls" }) |known| if (scope.equal(name, try scope.text(known))) return true;
    return false;
}
fn preRender(engine: *em.Engine, entries: c.JSValue, renderer: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const rendered = try scope.object();
    var items = try iter(&scope, entries);
    defer items.deinit();
    errdefer items.closePreserving();
    while (try items.next()) |entry| {
        defer engine.freeValue(entry);
        var item: Scope = .{ .engine = engine };
        defer item.deinit();
        if (!item.equal(try item.get(entry, "type"), try item.text("message"))) continue;
        const message = try item.get(entry, "message");
        if (item.equal(try item.get(message, "role"), try item.text("assistant")) and item.truthy(try item.invoke(try item.global("Array"), "isArray", &.{try item.get(message, "content")}))) {
            var blocks = try iter(&item, try item.get(message, "content"));
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            while (try blocks.next()) |block| {
                defer engine.freeValue(block);
                var part: Scope = .{ .engine = engine };
                defer part.deinit();
                if (!part.equal(try part.get(block, "type"), try part.text("toolCall")) or try templateTool(&part, try part.get(block, "name"))) continue;
                const html = try part.invoke(renderer, "renderCall", &.{ try part.get(block, "id"), try part.get(block, "name"), try part.get(block, "arguments") });
                if (part.truthy(html)) {
                    const value = try part.object();
                    try part.put(value, "callHtml", html);
                    try js.setKey(engine, rendered, try part.get(block, "id"), value);
                }
            }
        }
        if (item.equal(try item.get(message, "role"), try item.text("toolResult")) and item.truthy(try item.get(message, "toolCallId"))) {
            const name = try item.get(message, "toolName");
            const tool_name = if (item.truthy(name)) name else try item.text("");
            const existing = try item.own(try js.getKey(engine, rendered, try item.get(message, "toolCallId")));
            if (item.truthy(existing) or !try templateTool(&item, tool_name)) {
                const is_error = try item.get(message, "isError");
                const result = try item.invoke(renderer, "renderResult", &.{ try item.get(message, "toolCallId"), tool_name, try item.get(message, "content"), try item.get(message, "details"), if (item.truthy(is_error)) is_error else c.pi_js_bool(engine.context, 0) });
                if (item.truthy(result)) {
                    const value = try item.own(try js.spread(engine, existing));
                    try item.put(value, "resultHtmlCollapsed", try item.get(result, "collapsed"));
                    try item.put(value, "resultHtmlExpanded", try item.get(result, "expanded"));
                    try js.setKey(engine, rendered, try item.get(message, "toolCallId"), value);
                }
            }
        }
    }
    return c.JS_DupValue(engine.context, rendered);
}
fn background(scope: *Scope, colors: c.JSValue, explicit: c.JSValue) !c.JSValue {
    const base = try scope.get(colors, "userMessageBg");
    const derived = try scope.own(try theme.derived(scope.engine, if (scope.truthy(base)) base else try scope.text("#343541")));
    const result = try scope.object();
    inline for (.{ "pageBg", "cardBg", "infoBg" }) |key| {
        const selected = try scope.get(explicit, key);
        try scope.put(result, key, if (temp.nullish(selected)) try scope.get(derived, key) else selected);
    }
    return result;
}
fn vars(engine: *em.Engine, name: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const colors = try scope.own(try theme.resolved(engine, name));
    const lines = try scope.array();
    var entries = try iter(&scope, try scope.invoke(try scope.global("Object"), "entries", &.{colors}));
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer engine.freeValue(entry);
        var part: Scope = .{ .engine = engine };
        defer part.deinit();
        const key = try part.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 0)));
        const value = try part.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, entry, 1)));
        const line = try part.concat(try part.concat(try part.concat(try part.text("--"), key), try part.text(": ")), try part.concat(value, try part.text(";")));
        _ = try part.invoke(lines, "push", &.{line});
    }
    const explicit = try scope.own(try theme.explicit(engine, name));
    const backgrounds = try background(&scope, colors, explicit);
    inline for (.{ "exportPageBg", "exportCardBg", "exportInfoBg" }, .{ "pageBg", "cardBg", "infoBg" }) |key, source| {
        const line = try scope.concat(try scope.text("--" ++ key ++ ": "), try scope.concat(try scope.get(backgrounds, source), try scope.text(";")));
        _ = try scope.invoke(lines, "push", &.{line});
    }
    return js.invoke(engine, lines, "join", &.{try scope.text("\n      ")});
}
pub fn generateHtml(engine: *em.Engine, data: c.JSValue, name: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const theme_vars = try scope.own(try vars(engine, name));
    const colors = try scope.own(try theme.resolved(engine, name));
    const explicit = try scope.own(try theme.explicit(engine, name));
    const backgrounds = try background(&scope, colors, explicit);
    const json = try scope.invoke(try scope.global("JSON"), "stringify", &.{data});
    // Buffer UTF8 conversion replaces isolated surrogates; JSON has already escaped them.
    const bytes = try engine.toString(json);
    defer engine.gpa.free(bytes);
    const encoded = try engine.gpa.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    defer engine.gpa.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    var css = try scope.text(@embedFile("../coding_agent/assets/export-html/template.css"));
    css = try scope.invoke(css, "replace", &.{ try scope.text("{{THEME_VARS}}"), theme_vars });
    inline for (.{ "BODY_BG", "CONTAINER_BG", "INFO_BG" }, .{ "pageBg", "cardBg", "infoBg" }) |placeholder, key| css = try scope.invoke(css, "replace", &.{ try scope.text("{{" ++ placeholder ++ "}}"), try scope.get(backgrounds, key) });
    var html = try scope.text(@embedFile("../coding_agent/assets/export-html/template.html"));
    html = try scope.invoke(html, "replace", &.{ try scope.text("{{CSS}}"), css });
    html = try scope.invoke(html, "replace", &.{ try scope.text("{{JS}}"), try scope.text(@embedFile("../coding_agent/assets/export-html/template-client.js.txt")) });
    html = try scope.invoke(html, "replace", &.{ try scope.text("{{SESSION_DATA}}"), try scope.text(encoded) });
    html = try scope.invoke(html, "replace", &.{ try scope.text("{{MARKED_JS}}"), try scope.text(@embedFile("../coding_agent/assets/export-html/marked-client.js.txt")) });
    html = try scope.invoke(html, "replace", &.{ try scope.text("{{HIGHLIGHT_JS}}"), try scope.text(@embedFile("../coding_agent/assets/export-html/highlight-client.js.txt")) });
    return c.JS_DupValue(engine.context, html);
}
fn toolDescriptor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return descriptor(&scope, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn descriptor(scope: *Scope, tool: c.JSValue) !c.JSValue {
    const result = try scope.object();
    inline for (.{ "name", "description", "parameters" }) |key| try scope.put(result, key, try scope.get(tool, key));
    return c.JS_DupValue(scope.engine.context, result);
}
pub fn exportSession(engine: *em.Engine, manager: c.JSValue, state: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const opts = if (c.JS_IsString(options)) blk: {
        const result = try scope.object();
        try scope.put(result, "outputPath", options);
        break :blk result;
    } else if (scope.truthy(options)) options else try scope.object();
    const session_file = try scope.invoke(manager, "getSessionFile", &.{});
    if (!scope.truthy(session_file)) {
        try @import("native_durable_errors.zig").throwMessage(engine, "Cannot export in-memory session to HTML");
        return error.JavaScriptException;
    }
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, engine.native_io orelse return error.NativeSDKRequiresIO);
    const fs = engine.native_module_values.get("node:fs").?;
    if (!scope.truthy(try scope.invoke(fs, "existsSync", &.{session_file}))) {
        try @import("native_durable_errors.zig").throwMessage(engine, "Nothing to export yet - start a conversation first");
        return error.JavaScriptException;
    }
    const entries = try scope.invoke(manager, "getEntries", &.{});
    var rendered = c.pi_js_undefined();
    if (scope.truthy(try scope.get(opts, "toolRenderer"))) {
        rendered = try scope.own(try preRender(engine, entries, try scope.get(opts, "toolRenderer")));
        const keys = try scope.invoke(try scope.global("Object"), "keys", &.{rendered});
        if (try sdk.length(engine, keys) == 0) rendered = c.pi_js_undefined();
    }
    const data = try scope.object();
    try scope.put(data, "header", try scope.invoke(manager, "getHeader", &.{}));
    try scope.put(data, "entries", entries);
    try scope.put(data, "leafId", try scope.invoke(manager, "getLeafId", &.{}));
    try scope.put(data, "systemPrompt", if (temp.nullish(state)) c.pi_js_undefined() else try scope.get(state, "systemPrompt"));
    const tools = if (temp.nullish(state)) c.pi_js_undefined() else try scope.get(state, "tools");
    const mapper = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, toolDescriptor, "", 1)));
    try scope.put(data, "tools", if (temp.nullish(tools)) c.pi_js_undefined() else try scope.invoke(tools, "map", &.{mapper}));
    try scope.put(data, "renderedTools", rendered);
    const html = try scope.own(try generateHtml(engine, data, try scope.get(opts, "themeName")));
    var path = c.pi_js_undefined();
    if (scope.truthy(try scope.get(opts, "outputPath"))) path = try scope.own(try @import("native_sdk_settings.zig").normalizePath(engine, try scope.get(opts, "outputPath")));
    if (!scope.truthy(path)) {
        const raw_file = try engine.toString(session_file);
        defer engine.gpa.free(raw_file);
        const basename = @import("node_path.zig").basename(raw_file, if (builtin.os.tag == .windows) .win32 else .posix);
        const file = if (std.mem.endsWith(u8, basename, ".jsonl")) basename[0 .. basename.len - 6] else basename;
        path = try scope.concat(try scope.concat(try scope.text("pi-session-"), try scope.text(file)), try scope.text(".html"));
    }
    _ = try scope.invoke(fs, "writeFileSync", &.{ path, html, try scope.text("utf8") });
    return c.JS_DupValue(engine.context, path);
}
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const renderer = try @import("native_export_tool_html.zig").createFactory(engine);
    defer engine.freeValue(renderer);
    var roots = [_]c.JSValue{renderer};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, ordinary, "exportToHtml", 1, 0, roots.len, &roots));
    defer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "exportToHtml", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn ordinary(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const pending = flow.create(engine, session) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(pending.owner);
    const result = ordinaryValue(engine, session, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots[0]) catch |err| {
        flow.rejectError(engine, pending.owner, err) catch |failure| {
            engine.freeValue(pending.promise);
            return sdk.fail(engine, failure);
        };
        return pending.promise;
    };
    defer engine.freeValue(result);
    flow.settle(engine, pending.owner, false, result) catch |err| {
        engine.freeValue(pending.promise);
        return sdk.fail(engine, err);
    };
    return pending.promise;
}
fn ordinaryValue(engine: *em.Engine, session: c.JSValue, output: c.JSValue, supplied_options: c.JSValue, renderer_factory: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (c.JS_IsUndefined(supplied_options)) try scope.object() else supplied_options;
    const candidates = [_]c.JSValue{ try scope.get(options, "themeName"), try scope.invoke(try scope.get(session, "settingsManager"), "getTheme", &.{}) };
    var name = c.pi_js_undefined();
    for (candidates) |candidate| {
        if (c.JS_IsUndefined(candidate)) continue;
        const found = @import("native_theme.zig").loadByValue(engine, candidate, null) catch |err| {
            if (err == error.OutOfMemory) return err;
            if (engine.captured_exception) |exception| engine.freeValue(exception);
            engine.captured_exception = null;
            continue;
        };
        engine.freeValue(found);
        name = candidate;
        break;
    }
    const deps = try scope.object();
    var roots = [_]c.JSValue{session};
    try scope.put(deps, "getToolRenderers", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, resolveRenderers, "getToolRenderers", 1, 0, roots.len, &roots))));
    try scope.put(deps, "theme", try scope.own(try @import("native_theme.zig").current(engine)));
    try scope.put(deps, "cwd", try scope.invoke(try scope.get(session, "sessionManager"), "getCwd", &.{}));
    const renderer = try scope.call(renderer_factory, c.pi_js_undefined(), &.{deps});
    const opts = try scope.object();
    try scope.put(opts, "outputPath", output);
    try scope.put(opts, "themeName", name);
    try scope.put(opts, "toolRenderer", renderer);
    return exportSession(engine, try scope.get(session, "sessionManager"), try scope.get(session, "state"), opts);
}
fn resolveRenderers(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return resolveValue(&scope, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn resolveValue(scope: *Scope, session: c.JSValue, name: c.JSValue) !c.JSValue {
    var roots = [_]c.JSValue{ session, name };
    const fallback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, getTool, "", 0, 0, roots.len, &roots)));
    return js.invoke(scope.engine, try scope.get(session, "_extensionRunner"), "resolveToolRenderers", &.{ name, fallback });
}
fn getTool(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "getToolDefinition", &.{roots[1]}) catch |err| sdk.fail(engine, err);
}

//! Actual c268 utils/oauth-page.ts. Ordinary functions retain live replaceAll
//! and template coercion semantics; literals are the exact Source page bytes.
const v = @import("native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const cache_key = "\x00ai-oauth-page";

fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    const candidate = try expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var completed = v.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, cached));
        completed.release(candidate);
        return completed.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate); return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return c.JS_DupValue(engine.context, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "oauthSuccessHtml", try v.ordinary(s, "oauthSuccessHtml", 1, successCall, &.{}));
    try v.put(s, result, "oauthErrorHtml", try v.ordinary(s, "oauthErrorHtml", 2, errorCall, &.{}));
    return v.duplicate(s, result);
}
fn successCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, pageCallBody, .{ v.arg(args, 0), c.pi_js_undefined(), false });
}
fn errorCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, pageCallBody, .{ v.arg(args, 0), v.arg(args, 1), true });
}
fn pageCallBody(s: *Scope, message: c.JSValue, details: c.JSValue, failed: bool) !c.JSValue {
    const options = try v.object(s);
    const title: []const u8 = if (failed) "Authentication failed" else "Authentication successful";
    try v.put(s, options, "title", try v.text(s, title));
    try v.put(s, options, "heading", try v.text(s, title));
    try v.put(s, options, "message", message);
    if (failed) try v.put(s, options, "details", details);
    return render(s.engine, options);
}
fn replaceOwned(s: *Scope, incoming: c.JSValue, needle: []const u8, replacement: []const u8) !c.JSValue {
    const receiver = try v.own(s, incoming);
    const method = try v.get(s, receiver, "replaceAll");
    return v.duplicate(s, try v.call(s, method, receiver, &.{ try v.text(s, needle), try v.text(s, replacement) }));
}
fn escapeHtml(engine: *Engine, input: c.JSValue) !c.JSValue {
    var current = c.JS_DupValue(engine.context, input);
    inline for (.{ .{ "&", "&amp;" }, .{ "<", "&lt;" }, .{ ">", "&gt;" }, .{ "\"", "&quot;" }, .{ "'", "&#39;" } }) |pair| {
        // Each completed method expression owns and retires its receiver
        // before the next live replaceAll getter is selected.
        current = try expression(engine, replaceOwned, .{ current, @as([]const u8, pair[0]), @as([]const u8, pair[1]) });
    }
    return current;
}
fn escapedField(s: *Scope, options: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const input = try v.get(s, options, name);
    return escapeHtml(s.engine, input);
}
fn detailsPresent(s: *Scope, options: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.get(s, options, "details")));
}
const Locals = struct {
    engine: *Engine,
    title: c.JSValue = c.pi_js_undefined(),
    heading: c.JSValue = c.pi_js_undefined(),
    message: c.JSValue = c.pi_js_undefined(),
    details: c.JSValue = c.pi_js_undefined(),
    fn finish(self: *Locals, result: anyerror!c.JSValue) !c.JSValue {
        var completion = v.owned.Completion.initValue(self.engine, result);
        completion.release(self.title); completion.release(self.heading);
        completion.release(self.message); completion.release(self.details);
        return completion.finishValue();
    }
};
fn render(engine: *Engine, options: c.JSValue) !c.JSValue {
    var locals: Locals = .{ .engine = engine };
    return locals.finish(renderBody(&locals, options));
}
fn renderBody(locals: *Locals, options: c.JSValue) !c.JSValue {
    const engine = locals.engine;
    locals.title = try expression(engine, escapedField, .{options, @as([*:0]const u8, "title")});
    locals.heading = try expression(engine, escapedField, .{options, @as([*:0]const u8, "heading")});
    locals.message = try expression(engine, escapedField, .{options, @as([*:0]const u8, "message")});
    if (c.JS_ToBool(engine.context, try expression(engine, detailsPresent, .{options})) == 1)
        locals.details = try expression(engine, escapedField, .{options, @as([*:0]const u8, "details")});
    return expression(engine, templateBody, .{locals});
}
fn append(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue { return v.binary(s, 0, left, right); }
fn converted(s: *Scope, input: c.JSValue) !c.JSValue { return v.duplicate(s, try v.stringify(s, input)); }
fn interpolation(s: *Scope, current: c.JSValue, input: c.JSValue) !c.JSValue {
    const string = try v.own(s, try expression(s.engine, converted, .{input}));
    return append(s, current, string);
}
fn detailsPart(s: *Scope, details: c.JSValue) !c.JSValue {
    if (!v.truthy(s, details)) return v.duplicate(s, try v.text(s, ""));
    const prefix = try interpolation(s, try v.text(s, "<div class=\"details\">"), details);
    return v.duplicate(s, try append(s, prefix, try v.text(s, "</div>")));
}
fn templateBody(s: *Scope, locals: *Locals) !c.JSValue {
    var result = try interpolation(s, try v.text(s, prefix), locals.title);
    result = try append(s, result, try v.text(s, after_title));
    result = try append(s, result, try v.text(s, logo));
    result = try append(s, result, try v.text(s, after_logo));
    result = try interpolation(s, result, locals.heading);
    result = try append(s, result, try v.text(s, after_heading));
    result = try interpolation(s, result, locals.message);
    result = try append(s, result, try v.text(s, after_message));
    const details = try v.own(s, try expression(s.engine, detailsPart, .{locals.details}));
    result = try append(s, result, details);
    result = try append(s, result, try v.text(s, suffix));
    return v.duplicate(s, result);
}
const logo = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 800 800\" aria-hidden=\"true\"><path fill=\"#F09082\" d=\"M165.29 165.29H517.36V400H400V282.65H165.29Z\"/><path fill=\"#4D9ABF\" d=\"M165.29 282.65H282.65V400H400V517.36H282.65V634.72H165.29Z\"/><path fill=\"#F1BE58\" d=\"M517.36 400H634.72V634.72H517.36Z\"/></svg>";
const prefix = "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n  <title>";
const after_title = "</title>\n  <style>\n    :root {\n      --text: #fafafa;\n      --text-dim: #a1a1aa;\n      --page-bg: #09090b;\n      --font-sans: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, \"Noto Sans\", sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\", \"Segoe UI Symbol\", \"Noto Color Emoji\";\n      --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace;\n    }\n    * { box-sizing: border-box; }\n    html { color-scheme: dark; }\n    body {\n      margin: 0;\n      min-height: 100vh;\n      display: flex;\n      align-items: center;\n      justify-content: center;\n      padding: 24px;\n      background: var(--page-bg);\n      color: var(--text);\n      font-family: var(--font-sans);\n      text-align: center;\n    }\n    main {\n      width: 100%;\n      max-width: 560px;\n      display: flex;\n      flex-direction: column;\n      align-items: center;\n      justify-content: center;\n    }\n    .logo {\n      width: 72px;\n      height: 72px;\n      display: block;\n      margin-bottom: 24px;\n    }\n    h1 {\n      margin: 0 0 10px;\n      font-size: 28px;\n      line-height: 1.15;\n      font-weight: 650;\n      color: var(--text);\n    }\n    p {\n      margin: 0;\n      line-height: 1.7;\n      color: var(--text-dim);\n      font-size: 15px;\n    }\n    .details {\n      margin-top: 16px;\n      font-family: var(--font-mono);\n      font-size: 13px;\n      color: var(--text-dim);\n      white-space: pre-wrap;\n      word-break: break-word;\n    }\n  </style>\n</head>\n<body>\n  <main>\n    <div class=\"logo\">";
const after_logo = "</div>\n    <h1>";
const after_heading = "</h1>\n    <p>";
const after_message = "</p>\n    ";
const suffix = "\n  </main>\n</body>\n</html>";

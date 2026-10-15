//! Exact b45 edit presentation/state/async-preview control flow.
//! Private uncompiled draft. Runtime dependencies require real edit-diff/jsdiff
//! and interactive renderDiff bodies; no empty diff or component substitutes.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const utils = @import("native_sdk_builtin_render_utils.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
pub const Runtime = struct { compute_edits_diff: c.JSValue, render_diff: c.JSValue };
fn has(s: *Scope, object: c.JSValue, name: []const u8) !bool {
    return js.hasKey(s.engine, object, try s.text(name));
}
fn new(s: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, try s.get(try utils.tui(s), name), @intCast(args.len), @constCast(args.ptr))));
}
fn identityCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return if (argc > 0) c.JS_DupValue(context, argv[0]) else c.pi_js_undefined();
}
fn component(s: *Scope, context: c.JSValue) !c.JSValue {
    const state = try s.get(context, "state");
    const last = try s.get(context, "lastComponent");
    const is_box = c.JS_IsInstanceOf(s.engine.context, last, try s.get(try utils.tui(s), "Box"));
    if (is_box < 0) return js.capture(s.engine);
    if (is_box != 0) {
        try s.set(state, "callComponent", last);
        return last;
    }
    const cached = try s.get(state, "callComponent");
    if (s.truthy(cached)) return cached;
    const id = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, identityCall, "", 1, 0, 0, null)));
    const box = try new(s, "Box", &.{ c.JS_NewInt32(s.engine.context, 1), c.JS_NewInt32(s.engine.context, 1), id });
    const extra = try s.object();
    try s.put(extra, "preview", c.pi_js_undefined());
    try s.put(extra, "previewArgsKey", c.pi_js_undefined());
    try s.put(extra, "previewPending", c.pi_js_bool(s.engine.context, 0));
    try s.put(extra, "settledError", c.pi_js_bool(s.engine.context, 0));
    _ = try s.invoke(try s.global("Object"), "assign", &.{ box, extra });
    try s.set(state, "callComponent", box);
    return box;
}
fn validEdit(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return validateEdit(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn validateEdit(engine: *em.Engine, edit: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const valid = c.JS_IsString(try utils.optional(&s, edit, "oldText")) and c.JS_IsString(try utils.optional(&s, edit, "newText"));
    return c.pi_js_bool(engine.context, @intFromBool(valid));
}
fn previewInput(s: *Scope, args: c.JSValue) !c.JSValue {
    if (!s.truthy(args)) return c.pi_js_null();
    const path = if (c.JS_IsString(try s.get(args, "path"))) try s.get(args, "path") else if (c.JS_IsString(try s.get(args, "file_path"))) try s.get(args, "file_path") else c.pi_js_null();
    if (!s.truthy(path)) return c.pi_js_null();
    const array_class = try s.global("Array");
    const array_test = try s.get(array_class, "isArray");
    const is_array = try s.call(array_test, array_class, &.{try s.get(args, "edits")});
    if (s.truthy(is_array) and try s.positive(try s.get(try s.get(args, "edits"), "length"))) {
        const every_receiver = try s.get(args, "edits");
        const cb = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, validEdit, "", 1, 0, 0, null)));
        if (s.truthy(try s.invoke(every_receiver, "every", &.{cb}))) {
            const input = try s.object();
            try s.put(input, "path", path);
            try s.put(input, "edits", try s.get(args, "edits"));
            return input;
        }
    }
    if (c.JS_IsString(try s.get(args, "oldText")) and c.JS_IsString(try s.get(args, "newText"))) {
        const input = try s.object();
        try s.put(input, "path", path);
        const array = try s.array();
        const edit = try s.object();
        try s.put(edit, "oldText", try s.get(args, "oldText"));
        try s.put(edit, "newText", try s.get(args, "newText"));
        try s.index(array, 0, edit);
        try s.put(input, "edits", array);
        return input;
    }
    return c.pi_js_null();
}
fn inputKey(s: *Scope, input: c.JSValue) !c.JSValue {
    if (!s.truthy(input)) return c.pi_js_undefined();
    const json = try s.global("JSON");
    const stringify = try s.get(json, "stringify");
    const value = try s.object();
    try s.put(value, "path", try s.get(input, "path"));
    try s.put(value, "edits", try s.get(input, "edits"));
    return s.call(stringify, json, &.{value});
}
fn setPreview(s: *Scope, box: c.JSValue, value: c.JSValue, key: c.JSValue) !bool {
    const current = try s.get(box, "preview");
    const changed = c.JS_IsUndefined(current) or
        (if (try has(s, current, "error") and try has(s, value, "error")) !s.equal(try s.get(current, "error"), try s.get(value, "error")) else (try has(s, current, "error")) != (try has(s, value, "error"))) or
        (!(try has(s, current, "error")) and !(try has(s, value, "error")) and (!s.equal(try s.get(current, "diff"), try s.get(value, "diff")) or !s.equal(try s.get(current, "firstChangedLine"), try s.get(value, "firstChangedLine"))));
    try s.set(box, "preview", value);
    try s.set(box, "previewArgsKey", key);
    try s.set(box, "previewPending", c.pi_js_bool(s.engine.context, 0));
    return changed;
}
fn previewReady(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return settle(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn settle(engine: *em.Engine, value: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (s.equal(try s.get(roots[0], "previewArgsKey"), roots[1])) {
        _ = try setPreview(&s, roots[0], value, roots[1]);
        _ = try s.invoke(roots[2], "invalidate", &.{});
    }
    return c.pi_js_undefined();
}
fn background(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "bg", &.{ roots[1], if (argc > 0) argv[0] else c.pi_js_undefined() }) catch |err| sdk.fail(engine, err);
}
fn rawPath(s: *Scope, args: c.JSValue) !c.JSValue {
    const preferred = try utils.optional(s, args, "file_path");
    return utils.str(s, if (temp.nullish(preferred)) try utils.optional(s, args, "path") else preferred);
}
fn rebuild(s: *Scope, api: Runtime, box: c.JSValue, args: c.JSValue, theme: c.JSValue, cwd: c.JSValue, padding: c.JSValue) !c.JSValue {
    const set_bg = try s.get(box, "setBgFn");
    const preview = try s.get(box, "preview");
    const settled_error = try s.get(box, "settledError");
    const token = if (s.truthy(preview)) (if (try has(s, preview, "error")) "toolErrorBg" else "toolSuccessBg") else if (s.truthy(settled_error)) "toolErrorBg" else "toolPendingBg";
    var roots = [_]c.JSValue{ theme, try s.text(token) };
    const bg = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, background, "", 1, 0, roots.len, &roots)));
    _ = try s.call(set_bg, box, &.{bg});
    _ = try s.invoke(box, "setPaddingX", &.{padding});
    _ = try s.invoke(box, "clear", &.{});
    const add_header = try s.get(box, "addChild");
    const path = try utils.renderToolPath(s, try rawPath(s, args), theme, cwd, c.pi_js_undefined());
    const title = try s.concat(try s.concat(try utils.title(s, theme, "edit"), try s.text(" ")), path);
    const zero = c.JS_NewInt32(s.engine.context, 0);
    _ = try s.call(add_header, box, &.{try new(s, "Text", &.{ title, zero, zero })});
    if (!s.truthy(try s.get(box, "preview"))) return box;
    const body = if (try has(s, try s.get(box, "preview"), "error")) error_body: {
        const color = try s.get(theme, "fg");
        break :error_body try s.call(color, theme, &.{ try s.text("error"), try s.get(try s.get(box, "preview"), "error") });
    } else try s.call(api.render_diff, c.pi_js_undefined(), &.{try s.get(try s.get(box, "preview"), "diff")});
    const add_spacer = try s.get(box, "addChild");
    _ = try s.call(add_spacer, box, &.{try new(s, "Spacer", &.{c.JS_NewInt32(s.engine.context, 1)})});
    const add_body = try s.get(box, "addChild");
    _ = try s.call(add_body, box, &.{try new(s, "Text", &.{ body, zero, zero })});
    return box;
}
pub fn renderCall(engine: *em.Engine, api: Runtime, args: c.JSValue, theme: c.JSValue, context: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const box = try component(&s, context);
    const input = try previewInput(&s, args);
    const key = try inputKey(&s, input);
    if (!s.equal(try s.get(box, "previewArgsKey"), key)) {
        try s.set(box, "preview", c.pi_js_undefined());
        try s.set(box, "previewArgsKey", key);
        try s.set(box, "previewPending", c.pi_js_bool(engine.context, 0));
        try s.set(box, "settledError", c.pi_js_bool(engine.context, 0));
    }
    if (s.truthy(try s.get(context, "argsComplete")) and s.truthy(input) and !s.truthy(try s.get(box, "preview")) and !s.truthy(try s.get(box, "previewPending"))) {
        try s.set(box, "previewPending", c.pi_js_bool(engine.context, 1));
        const promise = try s.call(api.compute_edits_diff, c.pi_js_undefined(), &.{ try s.get(input, "path"), try s.get(input, "edits"), try s.get(context, "cwd") });
        var roots = [_]c.JSValue{ box, key, context };
        const callback = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, previewReady, "", 1, 0, roots.len, &roots)));
        _ = try s.invoke(promise, "then", &.{callback});
    }
    return c.JS_DupValue(engine.context, try rebuild(&s, api, box, args, theme, try s.get(context, "cwd"), try s.get(context, "outputPad")));
}
fn textFilter(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return textBlock(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| sdk.fail(engine, err);
}
fn textBlock(engine: *em.Engine, value: c.JSValue, magic: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (magic == 0) return c.pi_js_bool(engine.context, @intFromBool(s.equal(try s.get(value, "type"), try s.text("text"))));
    const text = try s.get(value, "text");
    return c.JS_DupValue(engine.context, if (s.truthy(text)) text else try s.text(""));
}
fn formatResult(s: *Scope, api: Runtime, args: c.JSValue, preview: c.JSValue, result: c.JSValue, theme: c.JSValue, is_error: c.JSValue) !c.JSValue {
    const path = try rawPath(s, args);
    const preview_diff = if (s.truthy(preview) and !(try has(s, preview, "error"))) try s.get(preview, "diff") else c.pi_js_undefined();
    const preview_error = if (s.truthy(preview) and try has(s, preview, "error")) try s.get(preview, "error") else c.pi_js_undefined();
    if (s.truthy(is_error)) {
        const content = try s.get(result, "content");
        const filter = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, textFilter, "", 1, 0, 0, null)));
        const blocks = try s.invoke(content, "filter", &.{filter});
        const mapper = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, textFilter, "", 1, 1, 0, null)));
        const text = try s.invoke(try s.invoke(blocks, "map", &.{mapper}), "join", &.{try s.text("\n")});
        if (!s.truthy(text) or s.equal(text, preview_error)) return c.pi_js_undefined();
        return utils.fg(s, theme, "error", text);
    }
    const diff = try utils.optional(s, try s.get(result, "details"), "diff");
    if (s.truthy(diff) and !s.equal(diff, preview_diff)) {
        const options = try s.object();
        try s.put(options, "filePath", if (temp.nullish(path)) c.pi_js_undefined() else path);
        return s.call(api.render_diff, c.pi_js_undefined(), &.{ diff, options });
    }
    return c.pi_js_undefined();
}
pub fn renderResult(engine: *em.Engine, api: Runtime, result: c.JSValue, theme: c.JSValue, context: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const call = try s.get(try s.get(context, "state"), "callComponent");
    const key = try inputKey(&s, try previewInput(&s, try s.get(context, "args")));
    const diff = if (!s.truthy(try s.get(context, "isError"))) try utils.optional(&s, try s.get(result, "details"), "diff") else c.pi_js_undefined();
    var changed = false;
    if (s.truthy(call)) {
        if (c.JS_IsString(diff)) {
            const value = try s.object();
            try s.put(value, "diff", diff);
            try s.put(value, "firstChangedLine", try utils.optional(&s, try s.get(result, "details"), "firstChangedLine"));
            changed = (try setPreview(&s, call, value, key)) or changed;
        }
        if (!s.equal(try s.get(call, "settledError"), try s.get(context, "isError"))) {
            try s.set(call, "settledError", try s.get(context, "isError"));
            changed = true;
        }
        if (changed) _ = try rebuild(&s, api, call, try s.get(context, "args"), theme, try s.get(context, "cwd"), try s.get(context, "outputPad"));
    }
    const output = try formatResult(&s, api, try s.get(context, "args"), try utils.optional(&s, call, "preview"), result, theme, try s.get(context, "isError"));
    const last = try s.get(context, "lastComponent");
    const target = if (temp.nullish(last)) try new(&s, "Container", &.{}) else last;
    _ = try s.invoke(target, "clear", &.{});
    if (s.truthy(output)) {
        _ = try s.invoke(target, "addChild", &.{try new(&s, "Spacer", &.{c.JS_NewInt32(engine.context, 1)})});
        _ = try s.invoke(target, "addChild", &.{try new(&s, "Text", &.{ output, try s.get(context, "outputPad"), c.JS_NewInt32(engine.context, 0) })});
    }
    return c.JS_DupValue(engine.context, target);
}

//! Actual SDK UI services remain attached to their original session.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Prompt = enum(c_int) { select, confirm, input, editor, custom };
pub fn bind(engine: *engine_mod.Engine, session: c.JSValue, bindings: c.JSValue) !void {
    const state = try sdk.state(engine, session);
    inline for (.{ "uiContext", "mode", "commandContextActions", "abortHandler", "shutdownHandler", "onError" }) |field| {
        const value = try sdk.get(engine, bindings, field);
        defer engine.freeValue(value);
        if (!c.JS_IsUndefined(value)) try sdk.put(engine, state.data, "extension_" ++ field, c.JS_DupValue(engine.context, value));
    }
    const raw = try sdk.get(engine, state.data, "extension_uiContext");
    defer engine.freeValue(raw);
    const wrapped = if (c.JS_ToBool(engine.context, raw) == 1) try wrap(engine, session, raw) else try noop(engine);
    errdefer engine.freeValue(wrapped);
    try sdk.put(engine, state.data, "extension_wrappedUI", wrapped);
}
pub fn mode(engine: *engine_mod.Engine, session: c.JSValue) !c.JSValue {
    const value = try sdk.get(engine, (try sdk.state(engine, session)).data, "extension_mode");
    if (!c.JS_IsUndefined(value)) return value;
    engine.freeValue(value);
    return sdk.text(engine, "print");
}
pub fn hasUI(engine: *engine_mod.Engine, session: c.JSValue) !bool {
    const value = try sdk.get(engine, (try sdk.state(engine, session)).data, "extension_uiContext");
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) == 1;
}
pub fn current(engine: *engine_mod.Engine, session: c.JSValue) !c.JSValue {
    const state = try sdk.state(engine, session);
    const value = try sdk.get(engine, state.data, "extension_wrappedUI");
    if (!c.JS_IsUndefined(value)) return value;
    engine.freeValue(value);
    const result = try noop(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, state.data, "extension_wrappedUI", c.JS_DupValue(engine.context, result));
    return result;
}
fn wrap(engine: *engine_mod.Engine, session: c.JSValue, raw: c.JSValue) !c.JSValue {
    const value = try sdk.object(engine);
    errdefer engine.freeValue(value);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, raw, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| if (c.JS_DefinePropertyValue(engine.context, value, entry.atom, try engine.checked(c.JS_GetProperty(engine.context, raw, entry.atom)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    var data = [_]c.JSValue{ session, raw };
    inline for (std.meta.fields(Prompt)) |field| {
        const arity: c_int = switch (@as(Prompt, @enumFromInt(field.value))) {
            .select, .confirm, .input => 3,
            .editor, .custom => 2,
        };
        try sdk.put(engine, value, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, prompt, field.name, arity, field.value, data.len, &data)));
    }
    return value;
}
fn depth(engine: *engine_mod.Engine, session: c.JSValue) !u32 {
    const value = try sdk.get(engine, (try sdk.state(engine, session)).data, "extension_uiPromptDepth");
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) return 0;
    var number: u32 = 0;
    if (c.JS_ToUint32(engine.context, &number, value) < 0) return error.JavaScriptException;
    return number;
}
fn setDepth(engine: *engine_mod.Engine, session: c.JSValue, value: u32) !void {
    try sdk.put(engine, (try sdk.state(engine, session)).data, "extension_uiPromptDepth", c.JS_NewInt64(engine.context, value));
}
fn enqueuePrompt(engine: *engine_mod.Engine, session: c.JSValue, kind: Prompt, title: c.JSValue, start: bool) !void {
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, if (start) "ui_prompt_start" else "ui_prompt_end"));
    try sdk.put(engine, event, "reason", try sdk.text(engine, "ui_prompt"));
    try sdk.put(engine, event, "kind", try sdk.text(engine, @tagName(kind)));
    if (kind != .custom and c.JS_ToBool(engine.context, title) == 1) try sdk.put(engine, event, "title", c.JS_DupValue(engine.context, title));
    var args = [_]c.JSValue{ session, event };
    if (c.JS_EnqueueJob(engine.context, emitPromptJob, args.len, &args) < 0) return error.OutOfMemory;
}
fn emitPromptJob(context: ?*c.JSContext, _: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return emitPrompt(engine, args[0], args[1]) catch |err| sdk.fail(engine, err);
}
fn emitPrompt(engine: *engine_mod.Engine, session: c.JSValue, event: c.JSValue) !c.JSValue {
    const state = try sdk.state(engine, session);
    const loader = try sdk.get(engine, state.data, "resourceLoader");
    defer engine.freeValue(loader);
    const name = try sdk.get(engine, event, "type");
    defer engine.freeValue(name);
    const text = try engine.toString(name);
    defer engine.gpa.free(text);
    const payload = try engine.stringify(event);
    defer engine.gpa.free(payload);
    return @import("native_sdk_resources.zig").emitAsync(engine, loader, state.data, text, payload);
}
fn finish(engine: *engine_mod.Engine, session: c.JSValue, kind: Prompt, title: c.JSValue) !void {
    const current_depth = try depth(engine, session);
    if (current_depth > 1) return setDepth(engine, session, current_depth - 1);
    try setDepth(engine, session, 0);
    const state = try sdk.state(engine, session);
    const active = try sdk.get(engine, state.data, "extension_activeUiPrompt");
    defer engine.freeValue(active);
    const actual_title = if (c.JS_IsObject(active)) try sdk.get(engine, active, "title") else c.JS_DupValue(engine.context, title);
    defer engine.freeValue(actual_title);
    var actual_kind = kind;
    if (c.JS_IsObject(active)) {
        const value = try sdk.get(engine, active, "kind");
        defer engine.freeValue(value);
        const name = try engine.toString(value);
        defer engine.gpa.free(name);
        actual_kind = std.meta.stringToEnum(Prompt, name) orelse kind;
    }
    try sdk.put(engine, state.data, "extension_activeUiPrompt", c.pi_js_undefined());
    try enqueuePrompt(engine, session, actual_kind, actual_title, false);
}
fn finally(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    finish(engine, data[0], @enumFromInt(magic), data[1]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn prompt(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return invokePrompt(engine, data[0], data[1], @enumFromInt(magic), args) catch |err| sdk.fail(engine, err);
}
fn invokePrompt(engine: *engine_mod.Engine, session: c.JSValue, raw: c.JSValue, kind: Prompt, args: []const c.JSValue) !c.JSValue {
    const title = if (kind != .custom and args.len > 0) args[0] else c.pi_js_undefined();
    const old_depth = try depth(engine, session);
    if (old_depth >= 65_536) return error.NativeSDKUiPromptLimit;
    try setDepth(engine, session, old_depth + 1);
    if (old_depth == 0) {
        const state = try sdk.state(engine, session);
        const active = try sdk.object(engine);
        defer engine.freeValue(active);
        try sdk.put(engine, active, "kind", try sdk.text(engine, @tagName(kind)));
        try sdk.put(engine, active, "title", c.JS_DupValue(engine.context, title));
        try sdk.put(engine, state.data, "extension_activeUiPrompt", c.JS_DupValue(engine.context, active));
        try enqueuePrompt(engine, session, kind, title, true);
    }
    const result = sdk.invoke(engine, raw, @tagName(kind), args) catch |err| {
        try finish(engine, session, kind, title);
        return err;
    };
    defer engine.freeValue(result);
    var data = [_]c.JSValue{ session, title };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, finally, "finishSdkUiPrompt", 0, @intFromEnum(kind), data.len, &data));
    defer engine.freeValue(callback);
    return sdk.invoke(engine, result, "finally", &.{callback}) catch |err| {
        try finish(engine, session, kind, title);
        return err;
    };
}
const Noop = enum(c_int) { select, confirm, input, notify, onTerminalInput, setStatus, setWorkingMessage, setWorkingVisible, setWorkingIndicator, setHiddenThinkingLabel, setWidget, setFooter, setHeader, setTitle, custom, pasteToEditor, setEditorText, getEditorText, editor, addAutocompleteProvider, setEditorComponent, getEditorComponent, theme, getAllThemes, getTheme, setTheme, getToolsExpanded, setToolsExpanded };
fn noopCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return noopValue(engine, @enumFromInt(magic)) catch |err| sdk.fail(engine, err);
}
fn noopValue(engine: *engine_mod.Engine, operation: Noop) !c.JSValue {
    return switch (operation) {
        .select, .input, .custom, .editor => sdk.promise(engine, c.pi_js_undefined()),
        .confirm => sdk.promise(engine, c.pi_js_bool(engine.context, 0)),
        .onTerminalInput => engine.checked(c.JS_NewCFunction(engine.context, unsubscribe, "unsubscribe", 0)),
        .getEditorText => sdk.text(engine, ""),
        .getAllThemes => sdk.array(engine),
        .getToolsExpanded => c.pi_js_bool(engine.context, 0),
        .setTheme => result: {
            const value = try sdk.object(engine);
            errdefer engine.freeValue(value);
            try sdk.put(engine, value, "success", c.pi_js_bool(engine.context, 0));
            try sdk.put(engine, value, "error", try sdk.text(engine, "UI not available"));
            break :result value;
        },
        .theme => @import("native_theme.zig").current(engine),
        else => c.pi_js_undefined(),
    };
}
fn unsubscribe(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn noop(engine: *engine_mod.Engine) !c.JSValue {
    if (engine.native_sdk_noop_ui) |value| return c.JS_DupValue(engine.context, value);
    const value = try sdk.object(engine);
    errdefer engine.freeValue(value);
    inline for (std.meta.fields(Noop)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, noopCallback, field.name, 0, field.value));
        if (field.value == @intFromEnum(Noop.theme)) {
            const atom = c.JS_NewAtom(engine.context, field.name);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, value, atom, function, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
        } else try sdk.put(engine, value, field.name, function);
    }
    engine.native_sdk_noop_ui = c.JS_DupValue(engine.context, value);
    return value;
}

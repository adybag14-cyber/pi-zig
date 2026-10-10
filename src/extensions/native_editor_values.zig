//! Ordinary extension-language fields shared by Source Editor algorithms.
const std = @import("std");
pub const js = @import("native_js_values.zig");
pub const c = js.c;
pub const Engine = js.Engine;
pub const v = @import("native_select_list.zig");
pub const utf16 = @import("native_utf16.zig");
const completion_separator = "(?:\\s|(?:(?=\\p{Punctuation})[\\p{Script_Extensions=Han}\\p{Script_Extensions=Hiragana}\\p{Script_Extensions=Katakana}\\p{Script_Extensions=Hangul}\\p{Script_Extensions=Bopomofo}]|[，．：；！？（）［］｛｝“”‘’…—]))";
pub const token_start = "(?:^|" ++ completion_separator ++ ")[([{<`]*";
pub const suffix = "(?:(?!" ++ completion_separator ++ ").)*";
pub fn pattern(engine: *Engine, source: []const u8, flags: []const u8) !c.JSValue {
    const body = try v.text(engine, source);
    defer engine.freeValue(body);
    const mode = try v.text(engine, flags);
    defer engine.freeValue(mode);
    return js.builtin(engine, "RegExp", &.{ body, mode });
}
pub fn literalPattern(engine: *Engine, source: []const u8, flags: []const u8) !c.JSValue {
    const body = try v.text(engine, source);
    defer engine.freeValue(body);
    const mode = try v.text(engine, flags);
    defer engine.freeValue(mode);
    var args = [_]c.JSValue{ body, mode };
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, args.len, &args));
}
pub fn set(engine: *Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, object, name, value) < 0) return js.capture(engine);
}
pub fn number(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !f64 {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return v.number(engine, value);
}
pub fn length(engine: *Engine, object: c.JSValue) !usize {
    const count = try number(engine, object, "length");
    if (!std.math.isFinite(count) or count < 0 or count > 1_000_000) return error.NativeEditorStateLimit;
    return @intFromFloat(count);
}
pub fn state(engine: *Engine, object: c.JSValue) !c.JSValue {
    return js.get(engine, object, "state");
}
pub fn lines(engine: *Engine, object: c.JSValue) !c.JSValue {
    const current = try state(engine, object);
    defer engine.freeValue(current);
    return js.get(engine, current, "lines");
}
pub fn cursor(engine: *Engine, object: c.JSValue, field: [*:0]const u8) !f64 {
    const current = try state(engine, object);
    defer engine.freeValue(current);
    return number(engine, current, field);
}
pub fn setState(engine: *Engine, object: c.JSValue, field: [*:0]const u8, value: c.JSValue) !void {
    const current = try state(engine, object);
    defer engine.freeValue(current);
    try set(engine, current, field, value);
}
pub fn line(engine: *Engine, object: c.JSValue) !c.JSValue {
    const list = try lines(engine, object);
    defer engine.freeValue(list);
    const current = try state(engine, object);
    defer engine.freeValue(current);
    const index = try js.get(engine, current, "cursorLine");
    defer engine.freeValue(index);
    const value = try js.getKey(engine, list, index);
    if (v.truthy(engine, value)) return value;
    engine.freeValue(value);
    return v.text(engine, "");
}
pub fn replaceLine(engine: *Engine, object: c.JSValue, value: c.JSValue) !void {
    defer engine.freeValue(value);
    const list = try lines(engine, object);
    defer engine.freeValue(list);
    const current = try state(engine, object);
    defer engine.freeValue(current);
    const index = try js.get(engine, current, "cursorLine");
    defer engine.freeValue(index);
    try js.setKey(engine, list, index, value);
}
pub fn text(engine: *Engine, object: c.JSValue) !c.JSValue {
    const list = try lines(engine, object);
    defer engine.freeValue(list);
    const separator = try v.text(engine, "\n");
    defer engine.freeValue(separator);
    return js.invoke(engine, list, "join", &.{separator});
}
pub fn invokeVoid(engine: *Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const ignored = try js.invoke(engine, object, name, args);
    engine.freeValue(ignored);
}
pub fn notify(engine: *Engine, object: c.JSValue) !void {
    const callback = try js.get(engine, object, "onChange");
    defer engine.freeValue(callback);
    if (!v.truthy(engine, callback)) return;
    const value = try js.invoke(engine, object, "getText", &.{});
    defer engine.freeValue(value);
    const ignored = try js.call(engine, callback, object, &.{value});
    engine.freeValue(ignored);
}
pub fn renderRequest(engine: *Engine, object: c.JSValue) !void {
    const tui = try js.get(engine, object, "tui");
    defer engine.freeValue(tui);
    try invokeVoid(engine, tui, "requestRender", &.{});
}
pub fn equalText(engine: *Engine, value: c.JSValue, expected: []const u8) !bool {
    const wanted = try v.text(engine, expected);
    defer engine.freeValue(wanted);
    return c.JS_IsStrictEqual(engine.context, value, wanted);
}
pub fn setLast(engine: *Engine, object: c.JSValue, value: ?[]const u8) !void {
    try set(engine, object, "lastAction", if (value) |bytes| try v.text(engine, bytes) else c.pi_js_null());
}
pub fn snapshot(engine: *Engine, object: c.JSValue) !void {
    const undo = try js.get(engine, object, "undoStack");
    defer engine.freeValue(undo);
    const item = try js.object(engine);
    defer engine.freeValue(item);
    inline for (.{ "state", "pastes", "pasteCounter" }) |name| try js.define(engine, item, name, try js.get(engine, object, name));
    try invokeVoid(engine, undo, "push", &.{item});
}
pub fn initialize(engine: *Engine, object: c.JSValue, tui: c.JSValue, theme: c.JSValue, options: c.JSValue, input_constructor: c.JSValue) !void {
    const current = try js.object(engine);
    var transferred = false;
    defer if (!transferred) engine.freeValue(current);
    const list = try js.array(engine);
    var list_transferred = false;
    defer if (!list_transferred) engine.freeValue(list);
    const empty = try v.text(engine, "");
    defer engine.freeValue(empty);
    try js.push(engine, list, empty);
    list_transferred = true;
    try js.define(engine, current, "lines", list);
    try js.define(engine, current, "cursorLine", v.numeric(engine, 0));
    try js.define(engine, current, "cursorCol", v.numeric(engine, 0));
    transferred = true;
    try js.define(engine, object, "state", current);
    try js.define(engine, object, "focused", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "tui", c.pi_js_undefined());
    try js.define(engine, object, "theme", c.pi_js_undefined());
    try js.define(engine, object, "paddingX", v.numeric(engine, 0));
    try js.define(engine, object, "lastWidth", v.numeric(engine, 80));
    try js.define(engine, object, "renderedVisibleLineCount", v.numeric(engine, 1));
    try js.define(engine, object, "renderedAutocompleteHeight", v.numeric(engine, 0));
    try js.define(engine, object, "scrollOffset", v.numeric(engine, 0));
    try js.define(engine, object, "borderColor", c.pi_js_undefined());
    try js.define(engine, object, "autocompleteProvider", c.pi_js_undefined());
    const triggers = try js.array(engine);
    defer engine.freeValue(triggers);
    inline for (.{ "@", "#" }) |trigger| {
        const value = try v.text(engine, trigger);
        defer engine.freeValue(value);
        try js.push(engine, triggers, value);
    }
    try js.define(engine, object, "autocompleteTriggerCharacters", c.JS_DupValue(engine.context, triggers));
    try js.define(engine, object, "autocompleteTriggerPattern", try pattern(engine, token_start ++ "(?:@\"[^\"]*|[@#]" ++ suffix ++ ")$", "u"));
    try js.define(engine, object, "autocompleteDebouncePattern", try pattern(engine, token_start ++ "(?:@(?:\"[^\"]*|" ++ suffix ++ ")|[#]" ++ suffix ++ ")$", "u"));
    try js.define(engine, object, "autocompleteList", c.pi_js_undefined());
    try js.define(engine, object, "autocompleteState", c.pi_js_null());
    try js.define(engine, object, "autocompletePrefix", try v.text(engine, ""));
    try js.define(engine, object, "autocompleteMaxVisible", v.numeric(engine, 5));
    try js.define(engine, object, "autocompleteAbort", c.pi_js_undefined());
    try js.define(engine, object, "autocompleteDebounceTimer", c.pi_js_undefined());
    const promise = try js.global(engine, "Promise");
    defer engine.freeValue(promise);
    try js.define(engine, object, "autocompleteRequestTask", try js.invoke(engine, promise, "resolve", &.{}));
    try js.define(engine, object, "autocompleteStartToken", v.numeric(engine, 0));
    try js.define(engine, object, "autocompleteRequestId", v.numeric(engine, 0));
    try js.define(engine, object, "pastes", try js.builtin(engine, "Map", &.{}));
    try js.define(engine, object, "pasteCounter", v.numeric(engine, 0));
    try js.define(engine, object, "pasteBuffer", try v.text(engine, ""));
    try js.define(engine, object, "isInPaste", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "history", try js.array(engine));
    try js.define(engine, object, "historyIndex", v.numeric(engine, -1));
    try js.define(engine, object, "historyDraft", c.pi_js_null());
    try js.define(engine, object, "killRing", try @import("native_input.zig").createAuxiliary(engine, input_constructor, false));
    inline for (.{ "lastAction", "jumpMode", "preferredVisualCol", "snappedFromCursorCol" }) |name| try js.define(engine, object, name, c.pi_js_null());
    try js.define(engine, object, "undoStack", try @import("native_input.zig").createAuxiliary(engine, input_constructor, true));
    try js.define(engine, object, "onSubmit", c.pi_js_undefined());
    try js.define(engine, object, "onChange", c.pi_js_undefined());
    try js.define(engine, object, "disableSubmit", c.pi_js_bool(engine.context, 0));
    try set(engine, object, "tui", c.JS_DupValue(engine.context, tui));
    try set(engine, object, "theme", c.JS_DupValue(engine.context, theme));
    try set(engine, object, "borderColor", try js.get(engine, theme, "borderColor"));
    const selected_options = if (c.JS_IsUndefined(options)) try js.object(engine) else c.JS_DupValue(engine.context, options);
    defer engine.freeValue(selected_options);
    inline for (.{ "paddingX", "autocompleteMaxVisible" }) |name| {
        const raw = try js.get(engine, selected_options, name);
        defer engine.freeValue(raw);
        const default: f64 = if (std.mem.eql(u8, name, "paddingX")) 0 else 5;
        const value = if (c.JS_IsUndefined(raw) or c.JS_IsNull(raw)) v.numeric(engine, default) else raw;
        var result = default;
        if (c.JS_IsNumber(value)) {
            const number_value = try v.number(engine, value);
            if (std.math.isFinite(number_value)) result = if (default == 0) @max(0, @floor(number_value)) else @max(3, @min(20, @floor(number_value)));
        }
        try set(engine, object, name, v.numeric(engine, result));
    }
}

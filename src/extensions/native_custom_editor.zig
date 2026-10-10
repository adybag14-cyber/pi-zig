//! Source coding-agent CustomEditor: app-first input and working-status borders.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const visual = @import("native_editor_visual.zig");
const Method = enum(c_int) { setWorkingStatusIndicator, renderTopBorder, onAction, handleInput };
pub fn initialize(engine: *Engine, object: c.JSValue, keybindings: c.JSValue, options: c.JSValue) !void {
    inline for (.{ "keybindings", "workingStatusIndicator", "embedWorkingStatus" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    try js.define(engine, object, "actionHandlers", try js.builtin(engine, "Map", &.{}));
    inline for (.{ "onEscape", "onCtrlD", "onPasteImage", "onExtensionShortcut" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    try e.set(engine, object, "keybindings", c.JS_DupValue(engine.context, keybindings));
    const raw = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try js.get(engine, options, "embedWorkingStatus");
    defer engine.freeValue(raw);
    try e.set(engine, object, "embedWorkingStatus", if (c.JS_IsNull(raw) or c.JS_IsUndefined(raw)) c.pi_js_bool(engine.context, 0) else c.JS_DupValue(engine.context, raw));
}
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native CustomEditor: %s", @as([*:0]const u8, @errorName(err)));
}
fn callback(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return operation(engine, data[0], object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
pub fn install(engine: *Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        var data = [_]c.JSValue{prototype};
        const arity: c_int = if (field.value == @intFromEnum(Method.renderTopBorder) or field.value == @intFromEnum(Method.onAction)) 2 else 1;
        const value = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, arity, @intCast(field.value), 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
}
fn superCall(engine: *Engine, home: c.JSValue, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const parent = try engine.checked(c.JS_GetPrototype(engine.context, home));
    defer engine.freeValue(parent);
    const method = try js.get(engine, parent, name);
    defer engine.freeValue(method);
    return js.call(engine, method, object, args);
}
fn appMatches(engine: *Engine, object: c.JSValue, data: c.JSValue, action: c.JSValue) !bool {
    const kb = try js.get(engine, object, "keybindings");
    defer engine.freeValue(kb);
    const value = try js.invoke(engine, kb, "matches", &.{ data, action });
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn matches(engine: *Engine, object: c.JSValue, data: c.JSValue, name: []const u8) !bool {
    const action = try v.text(engine, name);
    defer engine.freeValue(action);
    return appMatches(engine, object, data, action);
}
fn handler(engine: *Engine, object: c.JSValue, name: [*:0]const u8, action: []const u8) !c.JSValue {
    const dynamic = try js.get(engine, object, name);
    if (!c.JS_IsNull(dynamic) and !c.JS_IsUndefined(dynamic)) return dynamic;
    engine.freeValue(dynamic);
    const handlers = try js.get(engine, object, "actionHandlers");
    defer engine.freeValue(handlers);
    const key = try v.text(engine, action);
    defer engine.freeValue(key);
    return js.invoke(engine, handlers, "get", &.{key});
}
fn invokeHandler(engine: *Engine, callback_value: c.JSValue) !void {
    const ignored = try js.call(engine, callback_value, c.pi_js_undefined(), &.{});
    engine.freeValue(ignored);
}
fn input(engine: *Engine, home: c.JSValue, object: c.JSValue, data: c.JSValue) !c.JSValue {
    const shortcut = try js.get(engine, object, "onExtensionShortcut");
    defer engine.freeValue(shortcut);
    if (!c.JS_IsNull(shortcut) and !c.JS_IsUndefined(shortcut)) {
        const handled = try js.call(engine, shortcut, object, &.{data});
        defer engine.freeValue(handled);
        if (v.truthy(engine, handled)) return c.pi_js_undefined();
    }
    if (try matches(engine, object, data, "app.clipboard.pasteImage")) {
        const paste = try js.get(engine, object, "onPasteImage");
        defer engine.freeValue(paste);
        if (!c.JS_IsNull(paste) and !c.JS_IsUndefined(paste)) {
            const ignored = try js.call(engine, paste, object, &.{});
            engine.freeValue(ignored);
        }
        return c.pi_js_undefined();
    }
    if (try matches(engine, object, data, "app.interrupt")) {
        const showing = try js.invoke(engine, object, "isShowingAutocomplete", &.{});
        defer engine.freeValue(showing);
        if (!v.truthy(engine, showing)) {
            const action = try handler(engine, object, "onEscape", "app.interrupt");
            defer engine.freeValue(action);
            if (v.truthy(engine, action)) {
                try invokeHandler(engine, action);
                return c.pi_js_undefined();
            }
        }
        return superCall(engine, home, object, "handleInput", &.{data});
    }
    if (try matches(engine, object, data, "app.exit")) {
        const text = try js.invoke(engine, object, "getText", &.{});
        defer engine.freeValue(text);
        if (try e.length(engine, text) == 0) {
            const action = try handler(engine, object, "onCtrlD", "app.exit");
            defer engine.freeValue(action);
            if (v.truthy(engine, action)) try invokeHandler(engine, action);
            return c.pi_js_undefined();
        }
    }
    if (try matches(engine, object, data, "tui.editor.historyPrevious") or try matches(engine, object, data, "tui.editor.historyNext")) return superCall(engine, home, object, "handleInput", &.{data});
    const handlers = try js.get(engine, object, "actionHandlers");
    defer engine.freeValue(handlers);
    const symbol_type = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol_type);
    const symbol = try js.get(engine, symbol_type, "iterator");
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, handlers, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        var pair = try js.Iterator.init(engine, entry, symbol);
        defer pair.deinit();
        errdefer pair.closePreserving();
        const action = (try pair.next()) orelse c.pi_js_undefined();
        defer engine.freeValue(action);
        const value = if (pair.closed) c.pi_js_undefined() else (try pair.next()) orelse c.pi_js_undefined();
        defer engine.freeValue(value);
        try pair.close();
        if (!try e.equalText(engine, action, "app.interrupt") and !try e.equalText(engine, action, "app.exit") and try appMatches(engine, object, data, action)) {
            try invokeHandler(engine, value);
            try iterator.close();
            return c.pi_js_undefined();
        }
    }
    return superCall(engine, home, object, "handleInput", &.{data});
}
fn repeat(engine: *Engine, count: f64) !c.JSValue {
    const dash = try v.text(engine, "─");
    defer engine.freeValue(dash);
    return js.invoke(engine, dash, "repeat", &.{v.numeric(engine, count)});
}
fn color(engine: *Engine, object: c.JSValue, text: c.JSValue) !c.JSValue {
    return js.invoke(engine, object, "borderColor", &.{text});
}
fn fits(overflow: bool, overflow_width: f64, requested: f64, start: f64, status_width: f64) bool {
    return overflow and overflow_width + 2 <= requested and start - (3 + status_width + 1) >= 1;
}
fn border(engine: *Engine, home: c.JSValue, object: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const requested = try v.number(engine, v.arg(args, 0));
    const embed = try js.get(engine, object, "embedWorkingStatus");
    defer engine.freeValue(embed);
    if (!v.truthy(engine, embed)) return superCall(engine, home, object, "renderTopBorder", args);
    const indicator = try js.get(engine, object, "workingStatusIndicator");
    defer engine.freeValue(indicator);
    if (!v.truthy(engine, indicator) or requested <= 0) return superCall(engine, home, object, "renderTopBorder", args);
    var status = try js.invoke(engine, indicator, "renderInBorder", &.{v.numeric(engine, @max(1, requested - 5))});
    defer engine.freeValue(status);
    var status_width = try visual.width(engine, status);
    if (status_width == 0) return superCall(engine, home, object, "renderTopBorder", args);
    const hidden = try v.number(engine, v.arg(args, 1));
    const arrow = try v.text(engine, " ↑ ");
    defer engine.freeValue(arrow);
    const tail = try v.text(engine, " more ");
    defer engine.freeValue(tail);
    const overflow = if (hidden > 0) try v.concat(engine, &.{ arrow, v.arg(args, 1), tail }) else c.pi_js_undefined();
    defer engine.freeValue(overflow);
    const overflow_width = if (hidden > 0) try visual.width(engine, overflow) else 0;
    const start = @floor((requested - overflow_width) / 2);
    if (hidden > 0 and !fits(true, overflow_width, requested, start, status_width)) {
        const next = try js.invoke(engine, indicator, "renderSpinnerInBorder", &.{v.arg(args, 0)});
        engine.freeValue(status);
        status = next;
        status_width = try visual.width(engine, status);
    }
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    if (fits(hidden > 0, overflow_width, requested, start, status_width)) {
        const left = try v.text(engine, "── ");
        defer engine.freeValue(left);
        const painted = try color(engine, object, left);
        defer engine.freeValue(painted);
        const middle = try repeat(engine, start - (3 + status_width + 1));
        defer engine.freeValue(middle);
        const end = try repeat(engine, requested - start - overflow_width);
        defer engine.freeValue(end);
        const suffix = try v.concat(engine, &.{ space, middle, overflow, end });
        defer engine.freeValue(suffix);
        const right = try color(engine, object, suffix);
        defer engine.freeValue(right);
        return v.concat(engine, &.{ painted, status, right });
    }
    if (requested >= status_width + 5) {
        const left = try v.text(engine, "── ");
        defer engine.freeValue(left);
        const painted = try color(engine, object, left);
        defer engine.freeValue(painted);
        const end = try repeat(engine, requested - status_width - 4);
        defer engine.freeValue(end);
        const suffix = try v.concat(engine, &.{ space, end });
        defer engine.freeValue(suffix);
        const right = try color(engine, object, suffix);
        defer engine.freeValue(right);
        return v.concat(engine, &.{ painted, status, right });
    }
    const next = try js.invoke(engine, indicator, "renderSpinnerInBorder", &.{v.arg(args, 0)});
    engine.freeValue(status);
    status = next;
    status_width = try visual.width(engine, status);
    const prefix_width = @min(3, @max(0, requested - status_width));
    const left = try repeat(engine, prefix_width);
    defer engine.freeValue(left);
    const painted = try color(engine, object, left);
    defer engine.freeValue(painted);
    const end = try repeat(engine, @max(0, requested - prefix_width - status_width));
    defer engine.freeValue(end);
    const right = try color(engine, object, end);
    defer engine.freeValue(right);
    return v.concat(engine, &.{ painted, status, right });
}
fn operation(engine: *Engine, home: c.JSValue, object: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .setWorkingStatusIndicator => try e.set(engine, object, "workingStatusIndicator", c.JS_DupValue(engine.context, v.arg(args, 0))),
        .renderTopBorder => return border(engine, home, object, args),
        .handleInput => return input(engine, home, object, v.arg(args, 0)),
        .onAction => {
            const handlers = try js.get(engine, object, "actionHandlers");
            defer engine.freeValue(handlers);
            try e.invokeVoid(engine, handlers, "set", &.{ v.arg(args, 0), v.arg(args, 1) });
        },
    }
    return c.pi_js_undefined();
}

//! Source SettingsList implemented with native algorithms and observable JS fields.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const Method = enum(c_int) { updateValue, selectItem, invalidate, render, renderMainList, handleMouse, handleInput, getDisplayItems, getVisibleRange, activateItem, closeSubmenu, applyFilter, addHintLine };
const Class = struct { engine: *Engine, prototype: c.JSValue, input: c.JSValue };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native SettingsList: %s", @as([*:0]const u8, @errorName(err)));
}
fn fieldTruthy(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn optionalCall(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    if (c.JS_IsNull(receiver) or c.JS_IsUndefined(receiver)) return c.pi_js_undefined();
    const callback = try js.get(engine, receiver, name);
    defer engine.freeValue(callback);
    if (c.JS_IsNull(callback) or c.JS_IsUndefined(callback)) return c.pi_js_undefined();
    return js.call(engine, callback, receiver, args);
}
fn truncate(engine: *Engine, value: c.JSValue, width: f64, empty_ellipsis: bool) !c.JSValue {
    const units = try utf16.unitsAlloc(engine, value);
    defer engine.gpa.free(units);
    const output = try @import("../tui/utf16_terminal.zig").truncateOptionsAlloc(engine.gpa, units, width, if (empty_ellipsis) &.{} else std.unicode.utf8ToUtf16LeStringLiteral("..."), false);
    defer engine.gpa.free(output);
    return utf16.string(engine, output);
}
fn theme(engine: *Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const value = try js.get(engine, object, "theme");
    defer engine.freeValue(value);
    return js.invoke(engine, value, name, args);
}
fn push(engine: *Engine, lines: c.JSValue, value: c.JSValue) !void {
    defer engine.freeValue(value);
    try js.push(engine, lines, value);
}
fn display(engine: *Engine, object: c.JSValue) !c.JSValue {
    return js.get(engine, object, if (try fieldTruthy(engine, object, "searchEnabled")) "filteredItems" else "items");
}
fn range(engine: *Engine, object: c.JSValue, items: c.JSValue) !c.JSValue {
    const count = try v.numberField(engine, items, "length");
    const max_visible = try v.numberField(engine, object, "maxVisible");
    const selected = try v.numberField(engine, object, "selectedIndex");
    const start = v.maximum(0, v.minimum(selected - @floor(max_visible / 2), count - max_visible));
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "startIndex", v.numeric(engine, start));
    try js.define(engine, result, "endIndex", v.numeric(engine, v.minimum(start + max_visible, count)));
    return result;
}
fn itemCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const item = if (argc == 0) c.pi_js_undefined() else argv[0];
    const value = js.get(engine, item, if (magic == 0) "id" else "label") catch |err| return fail(engine, err);
    if (magic == 1) return value;
    defer engine.freeValue(value);
    if (magic == 0) return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, value, data[0])));
    return v.numeric(engine, v.width(engine, value) catch |err| return fail(engine, err));
}
fn itemFunction(engine: *Engine, operation: c_int, id: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{id};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, itemCallback, "", 1, operation, 1, &data));
}
fn addHint(engine: *Engine, object: c.JSValue, lines: c.JSValue, width: f64) !void {
    try push(engine, lines, try v.text(engine, ""));
    const label = try v.text(engine, if (try fieldTruthy(engine, object, "searchEnabled")) "  Type to search · Enter/Space to change · Esc to cancel" else "  Enter/Space to change · Esc to cancel");
    defer engine.freeValue(label);
    const hint = try theme(engine, object, "hint", &.{label});
    defer engine.freeValue(hint);
    try push(engine, lines, try truncate(engine, hint, width, false));
}
fn renderMain(engine: *Engine, object: c.JSValue, terminal_width: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    const width = try v.number(engine, terminal_width);
    const lines = try js.array(engine);
    errdefer engine.freeValue(lines);
    const search = try fieldTruthy(engine, object, "searchEnabled");
    const search_input = try js.get(engine, object, "searchInput");
    defer engine.freeValue(search_input);
    if (search and v.truthy(engine, search_input)) {
        const rendered = try js.invoke(engine, search_input, "render", &.{terminal_width});
        defer engine.freeValue(rendered);
        var iterator = try js.Iterator.init(engine, rendered, iterator_symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |line| try push(engine, lines, line);
        try push(engine, lines, try v.text(engine, ""));
    }
    const original = try js.get(engine, object, "items");
    defer engine.freeValue(original);
    if (try v.numberField(engine, original, "length") == 0) {
        const label = try v.text(engine, "  No settings available");
        defer engine.freeValue(label);
        try push(engine, lines, try theme(engine, object, "hint", &.{label}));
        if (search) try v.invokeVoid(engine, object, "addHintLine", &.{ lines, terminal_width });
        return lines;
    }
    const items = try js.invoke(engine, object, "getDisplayItems", &.{});
    defer engine.freeValue(items);
    const count = try v.numberField(engine, items, "length");
    if (count == 0) {
        const label = try v.text(engine, "  No matching settings");
        defer engine.freeValue(label);
        const styled = try theme(engine, object, "hint", &.{label});
        defer engine.freeValue(styled);
        try push(engine, lines, try truncate(engine, styled, width, false));
        try v.invokeVoid(engine, object, "addHintLine", &.{ lines, terminal_width });
        return lines;
    }
    const bounds = try js.invoke(engine, object, "getVisibleRange", &.{items});
    defer engine.freeValue(bounds);
    const start = try v.numberField(engine, bounds, "startIndex");
    const end = try v.numberField(engine, bounds, "endIndex");
    const callback = try itemFunction(engine, 2, c.pi_js_undefined());
    defer engine.freeValue(callback);
    const widths = try js.invoke(engine, original, "map", &.{callback});
    defer engine.freeValue(widths);
    var max_label: f64 = -std.math.inf(f64);
    var iterator = try js.Iterator.init(engine, widths, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer engine.freeValue(value);
        max_label = v.maximum(max_label, try v.number(engine, value));
    }
    max_label = v.minimum(36, max_label);
    const selected = try v.numberField(engine, object, "selectedIndex");
    const theme_object = try js.get(engine, object, "theme");
    defer engine.freeValue(theme_object);
    var index = start;
    while (index < end) : (index += 1) {
        const item = try v.fieldAt(engine, items, index);
        defer engine.freeValue(item);
        if (!v.truthy(engine, item)) continue;
        const is_selected = c.pi_js_bool(engine.context, @intFromBool(index == selected));
        const prefix = if (index == selected) try js.get(engine, theme_object, "cursor") else try v.text(engine, "  ");
        defer engine.freeValue(prefix);
        const prefix_width = try v.width(engine, prefix);
        const label = try js.get(engine, item, "label");
        defer engine.freeValue(label);
        const spacing = try v.spaces(engine, v.maximum(0, max_label - try v.width(engine, label)));
        defer engine.freeValue(spacing);
        const padded = try v.concat(engine, &.{ label, spacing });
        defer engine.freeValue(padded);
        const label_text = try theme(engine, object, "label", &.{ padded, is_selected });
        defer engine.freeValue(label_text);
        const separator = try v.text(engine, "  ");
        defer engine.freeValue(separator);
        const value = try js.get(engine, item, "currentValue");
        defer engine.freeValue(value);
        const clipped = try truncate(engine, value, width - prefix_width - max_label - 4, true);
        defer engine.freeValue(clipped);
        const value_text = try theme(engine, object, "value", &.{ clipped, is_selected });
        defer engine.freeValue(value_text);
        const row = try v.concat(engine, &.{ prefix, label_text, separator, value_text });
        defer engine.freeValue(row);
        try push(engine, lines, try truncate(engine, row, width, false));
    }
    if (start > 0 or end < count) {
        const raw = try std.fmt.allocPrint(engine.gpa, "  ({d}/{d})", .{ selected + 1, count });
        defer engine.gpa.free(raw);
        const label = try v.text(engine, raw);
        defer engine.freeValue(label);
        const clipped = try truncate(engine, label, width - 2, true);
        defer engine.freeValue(clipped);
        try push(engine, lines, try theme(engine, object, "hint", &.{clipped}));
    }
    const item = try v.fieldAt(engine, items, selected);
    defer engine.freeValue(item);
    const description = if (c.JS_IsNull(item) or c.JS_IsUndefined(item)) c.pi_js_undefined() else try js.get(engine, item, "description");
    defer engine.freeValue(description);
    if (v.truthy(engine, description)) {
        try push(engine, lines, try v.text(engine, ""));
        const units = try utf16.unitsAlloc(engine, description);
        defer engine.gpa.free(units);
        const wrapped = try @import("native_utf16_wrap.zig").wrap(engine, units, width - 4);
        defer {
            for (wrapped) |line| engine.gpa.free(line);
            engine.gpa.free(wrapped);
        }
        const prefix = try v.text(engine, "  ");
        defer engine.freeValue(prefix);
        for (wrapped) |line| {
            const text = try utf16.string(engine, line);
            defer engine.freeValue(text);
            const prefixed = try v.concat(engine, &.{ prefix, text });
            defer engine.freeValue(prefixed);
            try push(engine, lines, try theme(engine, object, "description", &.{prefixed}));
        }
    }
    try v.invokeVoid(engine, object, "addHintLine", &.{ lines, terminal_width });
    return lines;
}
fn doneCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    done(engine, data[0], data[1], if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn changed(engine: *Engine, object: c.JSValue, item: c.JSValue, value: c.JSValue) !void {
    try v.set(engine, item, "currentValue", c.JS_DupValue(engine.context, value));
    const id = try js.get(engine, item, "id");
    defer engine.freeValue(id);
    try v.invokeVoid(engine, object, "onChange", &.{ id, value });
}
fn done(engine: *Engine, object: c.JSValue, item: c.JSValue, args: []const c.JSValue) !void {
    if (!c.JS_IsUndefined(v.arg(args, 0))) try changed(engine, object, item, v.arg(args, 0));
    const options = v.arg(args, 1);
    if (!c.JS_IsNull(options) and !c.JS_IsUndefined(options)) {
        const navigate = try js.get(engine, options, "navigateTo");
        defer engine.freeValue(navigate);
        if (v.truthy(engine, navigate)) try v.set(engine, object, "navigateAfterClose", c.JS_DupValue(engine.context, navigate));
    }
    try v.invokeVoid(engine, object, "closeSubmenu", &.{});
}
fn activate(engine: *Engine, object: c.JSValue) !void {
    const items = try js.invoke(engine, object, "getDisplayItems", &.{});
    defer engine.freeValue(items);
    const index = try js.get(engine, object, "selectedIndex");
    defer engine.freeValue(index);
    const item = try js.getKey(engine, items, index);
    defer engine.freeValue(item);
    if (!v.truthy(engine, item)) return;
    const submenu = try js.get(engine, item, "submenu");
    defer engine.freeValue(submenu);
    if (v.truthy(engine, submenu)) {
        try v.set(engine, object, "submenuItemIndex", c.JS_DupValue(engine.context, index));
        const value = try js.get(engine, item, "currentValue");
        defer engine.freeValue(value);
        var data = [_]c.JSValue{ object, item };
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, doneCall, "", 2, 0, 2, &data));
        defer engine.freeValue(callback);
        try v.set(engine, object, "submenuComponent", try js.call(engine, submenu, item, &.{ value, callback }));
    } else {
        const values = try js.get(engine, item, "values");
        defer engine.freeValue(values);
        if (!v.truthy(engine, values)) return;
        const count = try v.numberField(engine, values, "length");
        if (count <= 0) return;
        const current = try js.get(engine, item, "currentValue");
        defer engine.freeValue(current);
        const current_index = try js.invoke(engine, values, "indexOf", &.{current});
        defer engine.freeValue(current_index);
        const next = try v.fieldAt(engine, values, @mod(try v.number(engine, current_index) + 1, count));
        defer engine.freeValue(next);
        try changed(engine, object, item, next);
    }
}
fn close(engine: *Engine, object: c.JSValue) !void {
    try v.set(engine, object, "submenuComponent", c.pi_js_null());
    const navigate = try js.get(engine, object, "navigateAfterClose");
    defer engine.freeValue(navigate);
    if (!c.JS_IsNull(navigate)) {
        try v.set(engine, object, "navigateAfterClose", c.pi_js_null());
        try v.set(engine, object, "submenuItemIndex", c.pi_js_null());
        try v.invokeVoid(engine, object, "selectItem", &.{navigate});
        try v.invokeVoid(engine, object, "activateItem", &.{});
    } else {
        const index = try js.get(engine, object, "submenuItemIndex");
        defer engine.freeValue(index);
        if (!c.JS_IsNull(index)) {
            try v.set(engine, object, "selectedIndex", c.JS_DupValue(engine.context, index));
            try v.set(engine, object, "submenuItemIndex", c.pi_js_null());
        }
    }
}
fn input(engine: *Engine, object: c.JSValue, key: c.JSValue) !void {
    const submenu = try js.get(engine, object, "submenuComponent");
    defer engine.freeValue(submenu);
    if (v.truthy(engine, submenu)) {
        const value = try optionalCall(engine, submenu, "handleInput", &.{key});
        engine.freeValue(value);
        return;
    }
    const manager = try @import("native_keybindings.zig").getGlobal(engine);
    defer engine.freeValue(manager);
    const items = try js.invoke(engine, object, "getDisplayItems", &.{});
    defer engine.freeValue(items);
    if (try v.matched(engine, manager, key, "tui.select.up")) {
        const count = try v.numberField(engine, items, "length");
        if (count == 0) return;
        const current = try v.numberField(engine, object, "selectedIndex");
        try v.set(engine, object, "selectedIndex", v.numeric(engine, if (current == 0) count - 1 else current - 1));
        return;
    }
    if (try v.matched(engine, manager, key, "tui.select.down")) {
        const count = try v.numberField(engine, items, "length");
        if (count == 0) return;
        const current = try v.numberField(engine, object, "selectedIndex");
        try v.set(engine, object, "selectedIndex", v.numeric(engine, if (current == count - 1) 0 else current + 1));
        return;
    }
    var confirm = try v.matched(engine, manager, key, "tui.select.confirm");
    if (!confirm) {
        const space = try v.text(engine, " ");
        defer engine.freeValue(space);
        if (c.JS_IsStrictEqual(engine.context, key, space)) {
            confirm = !try fieldTruthy(engine, object, "searchEnabled");
            if (!confirm) {
                const search_input = try js.get(engine, object, "searchInput");
                defer engine.freeValue(search_input);
                if (!c.JS_IsNull(search_input) and !c.JS_IsUndefined(search_input)) {
                    const query = try js.invoke(engine, search_input, "getValue", &.{});
                    defer engine.freeValue(query);
                    confirm = try v.numberField(engine, query, "length") == 0;
                }
            }
        }
    }
    if (confirm) return v.invokeVoid(engine, object, "activateItem", &.{});
    if (try v.matched(engine, manager, key, "tui.select.cancel")) return v.invokeVoid(engine, object, "onCancel", &.{});
    if (try fieldTruthy(engine, object, "searchEnabled")) {
        const search_input = try js.get(engine, object, "searchInput");
        defer engine.freeValue(search_input);
        if (v.truthy(engine, search_input)) {
            try v.invokeVoid(engine, search_input, "handleInput", &.{key});
            const query = try js.invoke(engine, search_input, "getValue", &.{});
            defer engine.freeValue(query);
            try v.invokeVoid(engine, object, "applyFilter", &.{query});
        }
    }
}
fn mouseDelegate(engine: *Engine, component: c.JSValue, event: c.JSValue) !c.JSValue {
    const value = try optionalCall(engine, component, "handleMouse", &.{event});
    defer engine.freeValue(value);
    if (!v.truthy(engine, value)) return c.pi_js_undefined();
    const result = try js.spread(engine, value);
    errdefer engine.freeValue(result);
    try v.set(engine, result, "focus", c.pi_js_bool(engine.context, 1));
    return result;
}
fn mouse(engine: *Engine, object: c.JSValue, event: c.JSValue) !c.JSValue {
    const submenu = try js.get(engine, object, "submenuComponent");
    defer engine.freeValue(submenu);
    if (v.truthy(engine, submenu)) return mouseDelegate(engine, submenu, event);
    const search = try fieldTruthy(engine, object, "searchEnabled");
    const search_input = try js.get(engine, object, "searchInput");
    defer engine.freeValue(search_input);
    if (search and v.truthy(engine, search_input)) {
        const y = try js.get(engine, event, "y");
        defer engine.freeValue(y);
        if (c.JS_IsStrictEqual(engine.context, y, v.numeric(engine, 0))) return mouseDelegate(engine, search_input, event);
        if (c.JS_IsStrictEqual(engine.context, y, v.numeric(engine, 1))) return c.pi_js_undefined();
    }
    const items = try js.invoke(engine, object, "getDisplayItems", &.{});
    defer engine.freeValue(items);
    const count = try v.numberField(engine, items, "length");
    if (count == 0) return c.pi_js_undefined();
    if (try v.stringEquals(engine, event, "type", "wheel")) {
        const delta = try js.get(engine, event, "wheelDelta");
        defer engine.freeValue(delta);
        if (v.truthy(engine, delta)) {
            const old = try v.numberField(engine, object, "selectedIndex");
            const next = v.maximum(0, v.minimum(count - 1, old + if (try v.number(engine, delta) < 0) @as(f64, -1) else 1));
            try v.set(engine, object, "selectedIndex", v.numeric(engine, next));
            return v.resultObject(engine, false, next != old);
        }
    }
    if (!try v.stringEquals(engine, event, "button", "left")) return c.pi_js_undefined();
    const press = try v.stringEquals(engine, event, "type", "press");
    const click = try v.stringEquals(engine, event, "type", "click");
    if (!press and !click) return c.pi_js_undefined();
    const bounds = try js.invoke(engine, object, "getVisibleRange", &.{items});
    defer engine.freeValue(bounds);
    const start = try v.numberField(engine, bounds, "startIndex");
    const end = try v.numberField(engine, bounds, "endIndex");
    const index = start + try v.numberField(engine, event, "y") - @as(f64, if (search) 2 else 0);
    if (index < start or index >= end) return c.pi_js_undefined();
    if (press) {
        try v.set(engine, object, "mousePressedIndex", v.numeric(engine, index));
        try v.set(engine, object, "selectedIndex", v.numeric(engine, index));
        return v.resultObject(engine, true, null);
    }
    const pressed = try js.get(engine, object, "mousePressedIndex");
    defer engine.freeValue(pressed);
    try v.set(engine, object, "selectedIndex", if (c.JS_IsNull(pressed) or c.JS_IsUndefined(pressed)) v.numeric(engine, index) else c.JS_DupValue(engine.context, pressed));
    try v.set(engine, object, "mousePressedIndex", c.pi_js_undefined());
    try v.invokeVoid(engine, object, "activateItem", &.{});
    return v.resultObject(engine, false, null);
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)], data[0]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    switch (operation) {
        .updateValue, .selectItem => {
            const items = if (operation == .updateValue) try js.get(engine, object, "items") else try display(engine, object);
            defer engine.freeValue(items);
            const callback = try itemFunction(engine, 0, v.arg(args, 0));
            defer engine.freeValue(callback);
            const found = try js.invoke(engine, items, if (operation == .updateValue) "find" else "findIndex", &.{callback});
            defer engine.freeValue(found);
            if (operation == .updateValue) {
                if (v.truthy(engine, found)) try v.set(engine, found, "currentValue", c.JS_DupValue(engine.context, v.arg(args, 1)));
            } else if (try v.number(engine, found) != -1) try v.set(engine, object, "selectedIndex", c.JS_DupValue(engine.context, found));
        },
        .invalidate => {
            const component = try js.get(engine, object, "submenuComponent");
            defer engine.freeValue(component);
            const result = try optionalCall(engine, component, "invalidate", &.{});
            engine.freeValue(result);
        },
        .render => {
            const component = try js.get(engine, object, "submenuComponent");
            defer engine.freeValue(component);
            if (v.truthy(engine, component)) return js.invoke(engine, component, "render", &.{v.arg(args, 0)});
            return js.invoke(engine, object, "renderMainList", &.{v.arg(args, 0)});
        },
        .renderMainList => return renderMain(engine, object, v.arg(args, 0), iterator_symbol),
        .handleMouse => return mouse(engine, object, v.arg(args, 0)),
        .handleInput => try input(engine, object, v.arg(args, 0)),
        .getDisplayItems => return display(engine, object),
        .getVisibleRange => return range(engine, object, v.arg(args, 0)),
        .activateItem => try activate(engine, object),
        .closeSubmenu => try close(engine, object),
        .applyFilter => {
            const items = try js.get(engine, object, "items");
            defer engine.freeValue(items);
            const callback = try itemFunction(engine, 1, c.pi_js_undefined());
            defer engine.freeValue(callback);
            try v.set(engine, object, "filteredItems", try @import("native_fuzzy.zig").filter(engine, items, v.arg(args, 0), callback, iterator_symbol));
            try v.set(engine, object, "selectedIndex", v.numeric(engine, 0));
        },
        .addHintLine => try addHint(engine, object, v.arg(args, 0), try v.number(engine, v.arg(args, 1))),
    }
    return c.pi_js_undefined();
}
fn constructorMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, visit);
    c.JS_MarkValue(runtime, state.input, visit);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    c.JS_FreeValueRT(runtime, state.input);
    state.engine.gpa.destroy(state);
}
fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Class constructor SettingsList cannot be invoked without 'new'");
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)) orelse return c.JS_ThrowTypeError(context, "Invalid SettingsList constructor")));
    return construct(engine, target, if (argc == 0) &.{} else argv[0..@intCast(argc)], state.input) catch |err| fail(engine, err);
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, input_class: c.JSValue) !c.JSValue {
    const prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    const object = try engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    // TypeScript field initialization precedes constructor-body assignments.
    inline for (.{ "items", "filteredItems", "theme" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    try js.define(engine, object, "selectedIndex", v.numeric(engine, 0));
    inline for (.{ "mousePressedIndex", "maxVisible", "onChange", "onCancel", "searchInput", "searchEnabled" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    inline for (.{ "submenuComponent", "submenuItemIndex", "navigateAfterClose" }) |name| try js.define(engine, object, name, c.pi_js_null());
    try v.set(engine, object, "items", c.JS_DupValue(engine.context, v.arg(args, 0)));
    try v.set(engine, object, "filteredItems", c.JS_DupValue(engine.context, v.arg(args, 0)));
    try v.set(engine, object, "maxVisible", c.JS_DupValue(engine.context, v.arg(args, 1)));
    try v.set(engine, object, "theme", c.JS_DupValue(engine.context, v.arg(args, 2)));
    try v.set(engine, object, "onChange", c.JS_DupValue(engine.context, v.arg(args, 3)));
    try v.set(engine, object, "onCancel", c.JS_DupValue(engine.context, v.arg(args, 4)));
    const options = if (c.JS_IsUndefined(v.arg(args, 5))) try js.object(engine) else c.JS_DupValue(engine.context, v.arg(args, 5));
    defer engine.freeValue(options);
    const search = try js.get(engine, options, "enableSearch");
    defer engine.freeValue(search);
    try v.set(engine, object, "searchEnabled", if (c.JS_IsNull(search) or c.JS_IsUndefined(search)) c.pi_js_bool(engine.context, 0) else c.JS_DupValue(engine.context, search));
    if (try fieldTruthy(engine, object, "searchEnabled")) try v.set(engine, object, "searchInput", try engine.checked(c.JS_CallConstructor(engine.context, input_class, 0, null)));
    return object;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native SettingsList Constructor", .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = constructorCall };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .updateValue, .addHintLine => 2,
            .selectItem, .render, .renderMainList, .handleMouse, .handleInput, .getVisibleRange, .applyFilter => 1,
            else => 0,
        };
        var data = [_]c.JSValue{iterator};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, length, @intCast(field.value), 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, callback, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const function_type = try js.global(engine, "Function");
    defer engine.freeValue(function_type);
    const function_prototype = try js.get(engine, function_type, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class));
    defer engine.freeValue(constructor);
    const input_class = try js.get(engine, exports, "Input");
    defer engine.freeValue(input_class);
    const state = try engine.gpa.create(Class);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .input = c.JS_DupValue(engine.context, input_class) };
    _ = c.JS_SetOpaque(constructor, state);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 5), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", try v.text(engine, "SettingsList"), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try js.define(engine, exports, "SettingsList", c.JS_DupValue(engine.context, constructor));
}
fn fixtureEngine(gpa: std.mem.Allocator) !*Engine {
    const engine = try Engine.init(gpa, .{});
    errdefer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const fixture = @embedFile("fixtures/settings-list-original-6fb.json");
    try js.define(engine, root, "settingsFixture", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "settings-list-original-6fb.json")));
    return engine;
}
test "Source6fb public SelectList SettingsList original layouts search descriptions callbacks and shape" {
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    const result = engine.evalModule(
        \\import{SettingsList}from'pi-tui';for(const[index,item]of settingsFixture.cases.entries()){const calls=[],theme=Object.fromEntries(['label','value','description','hint'].map(name=>[name,function(text,selected){if(item.plainTheme)return text;calls.push({name,text,...(selected===undefined?{}:{selected}),receiver:this===theme});return '\x1b[35m'+text+'\x1b[0m'}]));theme.cursor='→ ';const list=new SettingsList(item.items,item.maxVisible,theme,()=>{},()=>{},{enableSearch:item.search});if(item.search){list.searchInput.setValue(item.query);list.applyFilter(item.query)}list.selectedIndex=item.selected;const actual={lines:list.render(item.width),calls,filtered:list.filteredItems.map(i=>i.id)},expected={lines:item.lines,calls:item.calls,filtered:item.filtered};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}));}
        \\const shape={name:SettingsList.name,length:SettingsList.length,own:Object.keys(new SettingsList([],3,{},()=>{},()=>{})),methods:Object.fromEntries(Object.getOwnPropertyNames(SettingsList.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:SettingsList.prototype[k].name,length:SettingsList.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(SettingsList.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(settingsFixture.shape))throw Error(JSON.stringify({shape,expected:settingsFixture.shape}));
    , "settings-list-layout.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("SettingsList layout: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public SelectList SettingsList original input mouse filtering submenus navigation and error identity" {
    defer @import("../tui/keys.zig").setKittyProtocolActive(false);
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    const result = engine.evalModule(
        \\import{SettingsList,setKittyProtocolActive,getKeybindings,setKeybindings,KeybindingsManager,TUI_KEYBINDINGS}from'pi-tui';for(const[index,trace]of settingsFixture.traces.entries()){setKittyProtocolActive(trace.kitty);const items=JSON.parse(JSON.stringify(settingsFixture.originalItems)),calls=[],theme={cursor:'→ ',label:x=>x,value:x=>x,description:x=>x,hint:x=>x},list=new SettingsList(items,3,theme,function(id,value){calls.push({kind:'change',id,value,receiver:this===list})},function(){calls.push({kind:'cancel',receiver:this===list})},{enableSearch:trace.search});for(const step of trace.steps){const op=step.operation;let actual;if('data'in op){list.handleInput(op.data);actual={operation:op,index:list.selectedIndex,filtered:list.filteredItems.map(i=>i.id),values:items.map(i=>i.currentValue),query:list.searchInput?.getValue()??null,calls:[...calls]}}else{const result=list.handleMouse(op.event)??null;actual={operation:op,result,index:list.selectedIndex,pressed:list.mousePressedIndex??null,values:items.map(i=>i.currentValue),query:list.searchInput?.getValue()??null,calls:[...calls]}}if(JSON.stringify(actual)!==JSON.stringify(step))throw Error(JSON.stringify({index,actual,expected:step}));}}
        \\for(const[index,item]of settingsFixture.structural.entries()){let actual;try{actual=new Function('SettingsList','getKeybindings','setKeybindings','KeybindingsManager','TUI_KEYBINDINGS','"use strict";'+item.script)(SettingsList,getKeybindings,setKeybindings,KeybindingsManager,TUI_KEYBINDINGS)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}
    , "settings-list-events.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("SettingsList events: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn allocationError(engine: *Engine, err: anyerror) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |exception| {
        const message = c.JS_GetPropertyStr(engine.context, exception, "message");
        defer engine.freeValue(message);
        const value = c.JS_ToCString(engine.context, message);
        if (value != null) {
            defer c.JS_FreeCString(engine.context, value);
            if (std.mem.indexOf(u8, std.mem.span(value), "out of memory") != null) return error.OutOfMemory;
        }
    };
    return err;
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    @import("native_tui.zig").install(engine) catch |err| return allocationError(engine, err);
    const value = engine.evalModule(
        \\import{SettingsList,wrapTextWithAnsi,truncateToWidth}from'pi-tui';const items=[{id:'a',label:'Alpha界',description:'\x1b[4munderlined words\x1b[24m tail',currentValue:'one',values:['one','two']},{id:'b',label:'Beta',description:'\x1b]8;;https://example.invalid\x07link words here\x1b]8;;\x07',currentValue:'old',submenu(value,done){globalThis.pendingSettingsDone=done;return{render(width){return ['SUB'+width]},handleMouse(){return{handled:true}}}}}],theme={cursor:'→ ',label:text=>text,value:text=>text,description:text=>text,hint:text=>text},list=new SettingsList(items,1,theme,()=>{},()=>{},{enableSearch:true});list.render(54);list.render(8);list.handleInput('al');list.render(4);list.applyFilter('');list.selectItem('b');list.activateItem();list.render(20);list.handleMouse({type:'click'});globalThis.retainedSettings=list;wrapTextWithAnsi('\x1b[38;2;1;2;3mvery long words\nnext line',3);truncateToWidth('界😀',2.5,'…',true);
    , "settings-list-allocation.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
    const retained = engine.eval("pendingSettingsDone('new',{navigateTo:'a'});retainedSettings.render(30);delete globalThis.pendingSettingsDone;delete globalThis.retainedSettings", "settings-list-retained.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return allocationError(engine, err);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb public SelectList SettingsList all allocation failures release search wrapping and retained submenu closure graphs" {
    @import("../tui/keys.zig").setKittyProtocolActive(false);
    defer @import("../tui/keys.zig").setKittyProtocolActive(false);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

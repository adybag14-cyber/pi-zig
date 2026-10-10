//! Native Source SelectList with observable JS fields, callbacks and item identity.
const std = @import("std");
const engine_mod = @import("engine.zig");
const js = @import("native_js_values.zig");
const utf16 = @import("native_utf16.zig");
const layout_text = @import("../tui/utf16_terminal.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Method = enum(c_int) { setFilter, setSelectedIndex, invalidate, render, handleMouse, handleInput, getVisibleRange, renderItem, getPrimaryColumnWidth, getPrimaryColumnBounds, truncatePrimary, getDisplayValue, notifySelectionChange, getSelectedItem };
const Class = struct { engine: *Engine, prototype: c.JSValue };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native SelectList: %s", @as([*:0]const u8, @errorName(err)));
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn set(engine: *Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, object, name, value) < 0) return js.capture(engine);
}
pub fn number(engine: *Engine, value: c.JSValue) !f64 {
    var output: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &output, value) < 0) return js.capture(engine);
    return output;
}
pub fn numberField(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !f64 {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return number(engine, value);
}
pub fn numeric(engine: *Engine, value: f64) c.JSValue {
    return c.JS_NewFloat64(engine.context, value);
}
pub fn minimum(a: f64, b: f64) f64 {
    return if (std.math.isNan(a) or std.math.isNan(b)) std.math.nan(f64) else @min(a, b);
}
pub fn maximum(a: f64, b: f64) f64 {
    return if (std.math.isNan(a) or std.math.isNan(b)) std.math.nan(f64) else @max(a, b);
}
pub fn truthy(engine: *Engine, value: c.JSValue) bool {
    return c.JS_ToBool(engine.context, value) != 0;
}
pub fn fieldAt(engine: *Engine, object: c.JSValue, index: f64) !c.JSValue {
    return js.getKey(engine, object, numeric(engine, index));
}
pub fn invokeVoid(engine: *Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const value = try js.invoke(engine, object, name, args);
    engine.freeValue(value);
}
pub fn concat(engine: *Engine, parts: []const c.JSValue) !c.JSValue {
    var output: std.ArrayList(u16) = .empty;
    defer output.deinit(engine.gpa);
    for (parts) |part| {
        const units = try utf16.unitsAlloc(engine, part);
        defer engine.gpa.free(units);
        try output.appendSlice(engine.gpa, units);
    }
    return utf16.string(engine, output.items);
}
pub fn text(engine: *Engine, value: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
}
pub fn spaces(engine: *Engine, count: f64) !c.JSValue {
    if (!std.math.isFinite(count) or count > 1_000_000 or count < 0) return error.InvalidSelectSpacing;
    const output = try engine.gpa.alloc(u16, @intFromFloat(count));
    defer engine.gpa.free(output);
    @memset(output, ' ');
    return utf16.string(engine, output);
}
pub fn width(engine: *Engine, value: c.JSValue) !f64 {
    const units = try utf16.unitsAlloc(engine, value);
    defer engine.gpa.free(units);
    return @floatFromInt(try layout_text.visibleWidth(engine.gpa, units));
}
fn truncate(engine: *Engine, value: c.JSValue, max_width: f64) !c.JSValue {
    if (std.math.isNan(max_width)) return error.InvalidSelectWidth;
    const units = try utf16.unitsAlloc(engine, value);
    defer engine.gpa.free(units);
    const output = try layout_text.truncateOptionsAlloc(engine.gpa, units, max_width, &.{}, false);
    defer engine.gpa.free(output);
    return utf16.string(engine, output);
}
fn themed(engine: *Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const theme = try js.get(engine, object, "theme");
    defer engine.freeValue(theme);
    return js.invoke(engine, theme, name, &.{value});
}
fn selected(engine: *Engine, object: c.JSValue) !c.JSValue {
    const items = try js.get(engine, object, "filteredItems");
    defer engine.freeValue(items);
    const index = try js.get(engine, object, "selectedIndex");
    defer engine.freeValue(index);
    return js.getKey(engine, items, index);
}
fn notify(engine: *Engine, object: c.JSValue) !void {
    const item = try selected(engine, object);
    defer engine.freeValue(item);
    if (!truthy(engine, item)) return;
    const callback = try js.get(engine, object, "onSelectionChange");
    defer engine.freeValue(callback);
    if (truthy(engine, callback)) {
        const value = try js.call(engine, callback, object, &.{item});
        engine.freeValue(value);
    }
}
fn visibleRange(engine: *Engine, object: c.JSValue) !c.JSValue {
    const items = try js.get(engine, object, "filteredItems");
    defer engine.freeValue(items);
    const count = try numberField(engine, items, "length");
    const max_visible = try numberField(engine, object, "maxVisible");
    const selected_index = try numberField(engine, object, "selectedIndex");
    const start = maximum(0, minimum(selected_index - @floor(max_visible / 2), count - max_visible));
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "startIndex", numeric(engine, start));
    try js.define(engine, result, "endIndex", numeric(engine, minimum(start + max_visible, count)));
    return result;
}
fn displayValue(engine: *Engine, item: c.JSValue) !c.JSValue {
    const label = try js.get(engine, item, "label");
    if (truthy(engine, label)) return label;
    engine.freeValue(label);
    return js.get(engine, item, "value");
}
fn columnBounds(engine: *Engine, object: c.JSValue) !c.JSValue {
    const layout = try js.get(engine, object, "layout");
    defer engine.freeValue(layout);
    const min = try js.get(engine, layout, "minPrimaryColumnWidth");
    defer engine.freeValue(min);
    const max = try js.get(engine, layout, "maxPrimaryColumnWidth");
    defer engine.freeValue(max);
    const min_missing = c.JS_IsUndefined(min) or c.JS_IsNull(min);
    const max_missing = c.JS_IsUndefined(max) or c.JS_IsNull(max);
    const raw_min = if (!min_missing) try number(engine, min) else if (!max_missing) try number(engine, max) else 32;
    const raw_max = if (!max_missing) try number(engine, max) else if (!min_missing) try number(engine, min) else 32;
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "min", numeric(engine, maximum(1, minimum(raw_min, raw_max))));
    try js.define(engine, result, "max", numeric(engine, maximum(1, maximum(raw_min, raw_max))));
    return result;
}
fn reduceCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const args: []const c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    return reduce(engine, data[0], args) catch |err| fail(engine, err);
}
fn reduce(engine: *Engine, object: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const display = try js.invoke(engine, object, "getDisplayValue", &.{arg(args, 1)});
    defer engine.freeValue(display);
    return numeric(engine, maximum(try number(engine, arg(args, 0)), try width(engine, display) + 2));
}
fn columnWidth(engine: *Engine, object: c.JSValue) !c.JSValue {
    const bounds = try js.invoke(engine, object, "getPrimaryColumnBounds", &.{});
    defer engine.freeValue(bounds);
    const items = try js.get(engine, object, "filteredItems");
    defer engine.freeValue(items);
    var data = [_]c.JSValue{object};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, reduceCall, "", 2, 0, 1, &data));
    defer engine.freeValue(callback);
    const widest = try js.invoke(engine, items, "reduce", &.{ callback, numeric(engine, 0) });
    defer engine.freeValue(widest);
    return numeric(engine, maximum(try numberField(engine, bounds, "min"), minimum(try numberField(engine, bounds, "max"), try number(engine, widest))));
}
fn truncatePrimary(engine: *Engine, object: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const display = try js.invoke(engine, object, "getDisplayValue", &.{arg(args, 0)});
    defer engine.freeValue(display);
    const layout = try js.get(engine, object, "layout");
    defer engine.freeValue(layout);
    const callback = try js.get(engine, layout, "truncatePrimary");
    defer engine.freeValue(callback);
    const max_width = try number(engine, arg(args, 2));
    const truncated = if (truthy(engine, callback)) block: {
        const context = try js.object(engine);
        defer engine.freeValue(context);
        try js.define(engine, context, "text", c.JS_DupValue(engine.context, display));
        try js.define(engine, context, "maxWidth", c.JS_DupValue(engine.context, arg(args, 2)));
        try js.define(engine, context, "columnWidth", c.JS_DupValue(engine.context, arg(args, 3)));
        try js.define(engine, context, "item", c.JS_DupValue(engine.context, arg(args, 0)));
        try js.define(engine, context, "isSelected", c.JS_DupValue(engine.context, arg(args, 1)));
        break :block try js.call(engine, callback, layout, &.{context});
    } else try truncate(engine, display, max_width);
    defer engine.freeValue(truncated);
    return truncate(engine, truncated, max_width);
}
fn renderItem(engine: *Engine, object: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const is_selected = truthy(engine, arg(args, 1));
    const prefix = try text(engine, if (is_selected) "→ " else "  ");
    defer engine.freeValue(prefix);
    const terminal_width = try number(engine, arg(args, 2));
    const prefix_width = try width(engine, prefix);
    if (truthy(engine, arg(args, 3)) and terminal_width > 40) {
        const effective_column = maximum(1, minimum(try number(engine, arg(args, 4)), terminal_width - prefix_width - 4));
        const max_primary = maximum(1, effective_column - 2);
        const value = try js.invoke(engine, object, "truncatePrimary", &.{ arg(args, 0), arg(args, 1), numeric(engine, max_primary), numeric(engine, effective_column) });
        defer engine.freeValue(value);
        const value_width = try width(engine, value);
        const spacing = try spaces(engine, maximum(1, effective_column - value_width));
        defer engine.freeValue(spacing);
        const description_start = prefix_width + value_width + try numberField(engine, spacing, "length");
        const remaining = terminal_width - description_start - 2;
        if (remaining > 10) {
            const description = try truncate(engine, arg(args, 3), remaining);
            defer engine.freeValue(description);
            if (is_selected) {
                const whole = try concat(engine, &.{ prefix, value, spacing, description });
                defer engine.freeValue(whole);
                return themed(engine, object, "selectedText", whole);
            }
            const spaced = try concat(engine, &.{ spacing, description });
            defer engine.freeValue(spaced);
            const styled = try themed(engine, object, "description", spaced);
            defer engine.freeValue(styled);
            return concat(engine, &.{ prefix, value, styled });
        }
    }
    const max_width = terminal_width - prefix_width - 2;
    const value = try js.invoke(engine, object, "truncatePrimary", &.{ arg(args, 0), arg(args, 1), numeric(engine, max_width), numeric(engine, max_width) });
    defer engine.freeValue(value);
    const whole = try concat(engine, &.{ prefix, value });
    if (is_selected) {
        defer engine.freeValue(whole);
        return themed(engine, object, "selectedText", whole);
    }
    return whole;
}
fn render(engine: *Engine, object: c.JSValue, terminal_width: c.JSValue, newline_regex: c.JSValue) !c.JSValue {
    const lines = try js.array(engine);
    errdefer engine.freeValue(lines);
    const original = try js.get(engine, object, "filteredItems");
    defer engine.freeValue(original);
    if (try numberField(engine, original, "length") == 0) {
        const message = try text(engine, "  No matching commands");
        defer engine.freeValue(message);
        const styled = try themed(engine, object, "noMatch", message);
        defer engine.freeValue(styled);
        try js.push(engine, lines, styled);
        return lines;
    }
    const primary = try js.invoke(engine, object, "getPrimaryColumnWidth", &.{});
    defer engine.freeValue(primary);
    const range = try js.invoke(engine, object, "getVisibleRange", &.{});
    defer engine.freeValue(range);
    const start = try numberField(engine, range, "startIndex");
    const end = try numberField(engine, range, "endIndex");
    var index = start;
    while (index < end) : (index += 1) {
        const items = try js.get(engine, object, "filteredItems");
        defer engine.freeValue(items);
        const item = try fieldAt(engine, items, index);
        defer engine.freeValue(item);
        if (!truthy(engine, item)) continue;
        const is_selected = index == try numberField(engine, object, "selectedIndex");
        const description = try js.get(engine, item, "description");
        defer engine.freeValue(description);
        const normalized = if (truthy(engine, description)) block: {
            const space = try text(engine, " ");
            defer engine.freeValue(space);
            const replaced = try js.invoke(engine, description, "replace", &.{ newline_regex, space });
            defer engine.freeValue(replaced);
            break :block try js.invoke(engine, replaced, "trim", &.{});
        } else c.pi_js_undefined();
        defer engine.freeValue(normalized);
        const line = try js.invoke(engine, object, "renderItem", &.{ item, c.pi_js_bool(engine.context, @intFromBool(is_selected)), terminal_width, normalized, primary });
        defer engine.freeValue(line);
        try js.push(engine, lines, line);
    }
    const items = try js.get(engine, object, "filteredItems");
    defer engine.freeValue(items);
    const count = try numberField(engine, items, "length");
    if (start > 0 or end < count) {
        const current = try numberField(engine, object, "selectedIndex");
        const encoded = try std.fmt.allocPrint(engine.gpa, "  ({d}/{d})", .{ current + 1, count });
        defer engine.gpa.free(encoded);
        const label = try text(engine, encoded);
        defer engine.freeValue(label);
        const clipped = try truncate(engine, label, try number(engine, terminal_width) - 2);
        defer engine.freeValue(clipped);
        const styled = try themed(engine, object, "scrollInfo", clipped);
        defer engine.freeValue(styled);
        try js.push(engine, lines, styled);
    }
    return lines;
}
pub fn matched(engine: *Engine, manager: c.JSValue, key: c.JSValue, action: [*:0]const u8) !bool {
    const name = try engine.checked(c.JS_NewString(engine.context, action));
    defer engine.freeValue(name);
    const result = try js.invoke(engine, manager, "matches", &.{ key, name });
    defer engine.freeValue(result);
    return truthy(engine, result);
}
fn input(engine: *Engine, object: c.JSValue, key: c.JSValue) !void {
    const manager = try @import("native_keybindings.zig").getGlobal(engine);
    defer engine.freeValue(manager);
    if (try matched(engine, manager, key, "tui.select.up")) {
        const current = try numberField(engine, object, "selectedIndex");
        const items = try js.get(engine, object, "filteredItems");
        defer engine.freeValue(items);
        try set(engine, object, "selectedIndex", numeric(engine, if (current == 0) try numberField(engine, items, "length") - 1 else current - 1));
        try invokeVoid(engine, object, "notifySelectionChange", &.{});
    } else if (try matched(engine, manager, key, "tui.select.down")) {
        const current = try numberField(engine, object, "selectedIndex");
        const items = try js.get(engine, object, "filteredItems");
        defer engine.freeValue(items);
        try set(engine, object, "selectedIndex", numeric(engine, if (current == try numberField(engine, items, "length") - 1) 0 else current + 1));
        try invokeVoid(engine, object, "notifySelectionChange", &.{});
    } else if (try matched(engine, manager, key, "tui.select.confirm")) {
        const item = try selected(engine, object);
        defer engine.freeValue(item);
        if (truthy(engine, item)) {
            const callback = try js.get(engine, object, "onSelect");
            defer engine.freeValue(callback);
            if (truthy(engine, callback)) {
                const value = try js.call(engine, callback, object, &.{item});
                engine.freeValue(value);
            }
        }
    } else if (try matched(engine, manager, key, "tui.select.cancel")) {
        const callback = try js.get(engine, object, "onCancel");
        defer engine.freeValue(callback);
        if (truthy(engine, callback)) {
            const value = try js.call(engine, callback, object, &.{});
            engine.freeValue(value);
        }
    }
}
pub fn resultObject(engine: *Engine, focus: bool, changed: ?bool) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "handled", c.pi_js_bool(engine.context, 1));
    if (focus) try js.define(engine, result, "focus", c.pi_js_bool(engine.context, 1));
    if (changed) |value| try js.define(engine, result, "render", c.pi_js_bool(engine.context, @intFromBool(value)));
    return result;
}
pub fn stringEquals(engine: *Engine, object: c.JSValue, name: [*:0]const u8, expected: [*:0]const u8) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    const wanted = try engine.checked(c.JS_NewString(engine.context, expected));
    defer engine.freeValue(wanted);
    return c.JS_IsStrictEqual(engine.context, value, wanted);
}
fn mouse(engine: *Engine, object: c.JSValue, event: c.JSValue) !c.JSValue {
    const items = try js.get(engine, object, "filteredItems");
    defer engine.freeValue(items);
    const count = try numberField(engine, items, "length");
    if (count == 0) return c.pi_js_undefined();
    if (try stringEquals(engine, event, "type", "wheel")) {
        const delta = try js.get(engine, event, "wheelDelta");
        defer engine.freeValue(delta);
        if (truthy(engine, delta)) {
            const old = try numberField(engine, object, "selectedIndex");
            const next = maximum(0, minimum(count - 1, old + if (try number(engine, delta) < 0) @as(f64, -1) else 1));
            try set(engine, object, "selectedIndex", numeric(engine, next));
            if (next != old) try invokeVoid(engine, object, "notifySelectionChange", &.{});
            return resultObject(engine, false, next != old);
        }
    }
    if (!try stringEquals(engine, event, "button", "left")) return c.pi_js_undefined();
    const press = try stringEquals(engine, event, "type", "press");
    const click = try stringEquals(engine, event, "type", "click");
    if (!press and !click) return c.pi_js_undefined();
    const range = try js.invoke(engine, object, "getVisibleRange", &.{});
    defer engine.freeValue(range);
    const start = try numberField(engine, range, "startIndex");
    const end = try numberField(engine, range, "endIndex");
    const item_index = start + try numberField(engine, event, "y");
    if (item_index < start or item_index >= end) return c.pi_js_undefined();
    if (press) {
        try set(engine, object, "mousePressedIndex", numeric(engine, item_index));
        if (try numberField(engine, object, "selectedIndex") != item_index) {
            try set(engine, object, "selectedIndex", numeric(engine, item_index));
            try invokeVoid(engine, object, "notifySelectionChange", &.{});
        }
        return resultObject(engine, true, null);
    }
    const pressed = try js.get(engine, object, "mousePressedIndex");
    defer engine.freeValue(pressed);
    const clicked = if (c.JS_IsNull(pressed) or c.JS_IsUndefined(pressed)) item_index else try number(engine, pressed);
    try set(engine, object, "mousePressedIndex", c.pi_js_undefined());
    const changed = try numberField(engine, object, "selectedIndex") != clicked;
    try set(engine, object, "selectedIndex", numeric(engine, clicked));
    if (changed) try invokeVoid(engine, object, "notifySelectionChange", &.{});
    const item = try selected(engine, object);
    defer engine.freeValue(item);
    if (truthy(engine, item)) {
        const callback = try js.get(engine, object, "onSelect");
        defer engine.freeValue(callback);
        if (!c.JS_IsNull(callback) and !c.JS_IsUndefined(callback)) {
            const value = try js.call(engine, callback, object, &.{item});
            engine.freeValue(value);
        }
    }
    return resultObject(engine, false, null);
}
fn filterCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return filterItem(engine, if (argc == 0) c.pi_js_undefined() else argv[0], data[0]) catch |err| fail(engine, err);
}
fn filterItem(engine: *Engine, item: c.JSValue, query: c.JSValue) !c.JSValue {
    const value = try js.get(engine, item, "value");
    defer engine.freeValue(value);
    const lower = try js.invoke(engine, value, "toLowerCase", &.{});
    defer engine.freeValue(lower);
    const starts = try js.get(engine, lower, "startsWith");
    defer engine.freeValue(starts);
    const filter = try js.invoke(engine, query, "toLowerCase", &.{});
    defer engine.freeValue(filter);
    return js.call(engine, starts, lower, &.{filter});
}
fn methodCall(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, receiver, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)], data[0]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue, regex: c.JSValue) !c.JSValue {
    switch (operation) {
        .setFilter => {
            const items = try js.get(engine, object, "items");
            defer engine.freeValue(items);
            var data = [_]c.JSValue{arg(args, 0)};
            const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, filterCall, "", 1, 0, 1, &data));
            defer engine.freeValue(callback);
            try set(engine, object, "filteredItems", try js.invoke(engine, items, "filter", &.{callback}));
            try set(engine, object, "selectedIndex", numeric(engine, 0));
        },
        .setSelectedIndex => {
            const items = try js.get(engine, object, "filteredItems");
            defer engine.freeValue(items);
            try set(engine, object, "selectedIndex", numeric(engine, maximum(0, minimum(try number(engine, arg(args, 0)), try numberField(engine, items, "length") - 1))));
        },
        .invalidate => {},
        .render => return render(engine, object, arg(args, 0), regex),
        .handleInput => try input(engine, object, arg(args, 0)),
        .handleMouse => return mouse(engine, object, arg(args, 0)),
        .getVisibleRange => return visibleRange(engine, object),
        .getPrimaryColumnWidth => return columnWidth(engine, object),
        .getPrimaryColumnBounds => return columnBounds(engine, object),
        .getDisplayValue => return displayValue(engine, arg(args, 0)),
        .truncatePrimary => return truncatePrimary(engine, object, args),
        .renderItem => return renderItem(engine, object, args),
        .notifySelectionChange => try notify(engine, object),
        .getSelectedItem => {
            const item = try selected(engine, object);
            if (truthy(engine, item)) return item;
            engine.freeValue(item);
            return c.pi_js_null();
        },
    }
    return c.pi_js_undefined();
}
fn constructorMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, visit);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    state.engine.gpa.destroy(state);
}
fn constructorCall(context: ?*c.JSContext, _: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Class constructor SelectList cannot be invoked without 'new'");
    return construct(engine, target, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    const object = try engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    try js.define(engine, object, "items", c.JS_DupValue(engine.context, arg(args, 0)));
    try js.define(engine, object, "filteredItems", c.JS_DupValue(engine.context, arg(args, 0)));
    try js.define(engine, object, "selectedIndex", numeric(engine, 0));
    try js.define(engine, object, "mousePressedIndex", c.pi_js_undefined());
    try js.define(engine, object, "maxVisible", c.JS_DupValue(engine.context, arg(args, 1)));
    try js.define(engine, object, "theme", c.JS_DupValue(engine.context, arg(args, 2)));
    try js.define(engine, object, "layout", if (c.JS_IsUndefined(arg(args, 3))) try js.object(engine) else c.JS_DupValue(engine.context, arg(args, 3)));
    try js.define(engine, object, "onSelect", c.pi_js_undefined());
    try js.define(engine, object, "onCancel", c.pi_js_undefined());
    try js.define(engine, object, "onSelectionChange", c.pi_js_undefined());
    return object;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native SelectList Constructor", .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = constructorCall };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const pattern = try text(engine, "[\r\n]+");
    defer engine.freeValue(pattern);
    const flags = try text(engine, "g");
    defer engine.freeValue(flags);
    const regex = try js.builtin(engine, "RegExp", &.{ pattern, flags });
    defer engine.freeValue(regex);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .setFilter, .setSelectedIndex, .render, .handleMouse, .handleInput, .getDisplayValue => 1,
            .renderItem => 5,
            .truncatePrimary => 4,
            else => 0,
        };
        var data = [_]c.JSValue{regex};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, length, @intCast(field.value), 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, callback, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const function_type = try js.global(engine, "Function");
    defer engine.freeValue(function_type);
    const function_prototype = try js.get(engine, function_type, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class));
    defer engine.freeValue(constructor);
    const state = try engine.gpa.create(Class);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype) };
    _ = c.JS_SetOpaque(constructor, state);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 3), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", try text(engine, "SelectList"), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try js.define(engine, exports, "SelectList", c.JS_DupValue(engine.context, constructor));
}
fn fixtureEngine(gpa: std.mem.Allocator) !*Engine {
    const engine = try Engine.init(gpa, .{});
    errdefer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const fixture = @embedFile("fixtures/select-list-original-6fb.json");
    try js.define(engine, root, "selectListFixture", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "select-list-original-6fb.json")));
    return engine;
}
test "Source6fb public SelectList original layouts dynamic column widths and theme callback receivers" {
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    const result = engine.evalModule(
        \\import{SelectList}from'pi-tui';for(const[index,item]of selectListFixture.cases.entries()){const calls=[],theme=Object.fromEntries(['selectedPrefix','selectedText','description','scrollInfo','noMatch'].map(name=>[name,function(text){calls.push({name,text,receiver:this===theme});return '\x1b[35m'+text+'\x1b[0m'}]));const list=new SelectList(item.items,item.maxVisible,theme,item.layout);list.setSelectedIndex(item.selected);const actual={lines:list.render(item.width),calls,selectedIndex:list.selectedIndex,visible:list.getVisibleRange(),primary:list.getPrimaryColumnWidth()};const expected={lines:item.lines,calls:item.calls,selectedIndex:item.selectedIndex,visible:item.visible,primary:item.primary};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}));}
    , "select-list-layout.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("SelectList layout: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public SelectList original keys filtering mouse callbacks subclass references and shape" {
    defer @import("../tui/keys.zig").setKittyProtocolActive(false);
    const engine = try fixtureEngine(std.testing.allocator);
    defer engine.deinit();
    const result = engine.evalModule(
        \\import{SelectList,setKittyProtocolActive}from'pi-tui';for(const[index,trace]of selectListFixture.traces.entries()){setKittyProtocolActive(trace.kitty);const calls=[],theme=Object.fromEntries(['selectedPrefix','selectedText','description','scrollInfo','noMatch'].map(name=>[name,text=>text])),list=new SelectList(trace.empty?[]:selectListFixture.cases[0].items,3,theme);list.onSelect=function(item){calls.push({kind:'select',value:item.value,receiver:this===list})};list.onCancel=function(){calls.push({kind:'cancel',receiver:this===list})};list.onSelectionChange=function(item){calls.push({kind:'change',value:item.value,receiver:this===list})};for(const step of trace.steps){const op=step.operation;let actual;if('data'in op){list.handleInput(op.data);actual={operation:op,index:list.selectedIndex,selected:list.getSelectedItem()?.value??null,calls:[...calls]}}else if('filter'in op){list.setFilter(op.filter);actual={operation:op,index:list.selectedIndex,filtered:list.filteredItems.map(i=>i.value),selected:list.getSelectedItem()?.value??null,calls:[...calls]}}else{const result=list.handleMouse(op.event)??null;actual={operation:op,result,index:list.selectedIndex,pressed:list.mousePressedIndex??null,selected:list.getSelectedItem()?.value??null,calls:[...calls]}}if(JSON.stringify(actual)!==JSON.stringify(step))throw Error(JSON.stringify({index,actual,expected:step}));}}
        \\for(const[index,item]of selectListFixture.structural.entries()){let actual;try{actual=new Function('SelectList','"use strict";'+item.script)(SelectList)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item}));}
        \\const shape={name:SelectList.name,length:SelectList.length,own:Object.keys(new SelectList([],3,{})),methods:Object.fromEntries(Object.getOwnPropertyNames(SelectList.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:SelectList.prototype[k].name,length:SelectList.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(SelectList.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(selectListFixture.shape))throw Error(JSON.stringify({shape,expected:selectListFixture.shape}));
    , "select-list-events.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("SelectList events: {s}\n", .{message});
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
        \\import{SelectList,fuzzyFilter,fuzzyMatch}from'pi-tui';const items=[{value:'alpha',label:'Alpha界',description:'first\r\ndescription'},{value:'beta',label:'Beta',description:'second'}],theme={selectedText:text=>text,description:text=>text,scrollInfo:text=>text,noMatch:text=>text};const list=new SelectList(items,1,theme,{minPrimaryColumnWidth:12,maxPrimaryColumnWidth:24,truncatePrimary(context){return context.text+'-label'}});list.render(60);list.setFilter('a');list.render(8);list.setFilter('');list.handleInput('\x1b[B');list.handleMouse({type:'press',button:'left',x:0,y:0});list.handleMouse({type:'click',button:'left',x:0,y:0});const matches=fuzzyFilter(items,'al',item=>item.label);if(matches[0]!==items[0]||!fuzzyMatch('al','Alpha').matches)throw Error('fuzzy');globalThis.retainedSelectList=list;
    , "select-list-allocation.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(value);
    c.JS_RunGC(engine.runtime);
    const retained = engine.eval("retainedSelectList.render(50);delete globalThis.retainedSelectList", "select-list-retained.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return allocationError(engine, err);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb public SelectList all allocation failures release filters callbacks layout and retained graphs" {
    @import("../tui/keys.zig").setKittyProtocolActive(false);
    defer @import("../tui/keys.zig").setKittyProtocolActive(false);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

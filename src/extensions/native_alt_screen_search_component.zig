//! Genuine Source alternate-screen search input, focus and navigation component.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { focusedGet, focusedSet, setResult, getNavigationDirectionAt, setHoveredNavigationDirection, handleInput, invalidate, render };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native alternate-screen search component: %s", @as([*:0]const u8, @errorName(err)));
}
fn styled(engine: *js.Engine, value: c.JSValue) !c.JSValue {
    const begin = try v.text(engine, "\x1b[2m");
    defer engine.freeValue(begin);
    const end = try v.text(engine, "\x1b[22m");
    defer engine.freeValue(end);
    return v.concat(engine, &.{ begin, value, end });
}
fn placeholder(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return styled(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn identity(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, if (argc > 0) argv[0] else c.pi_js_undefined());
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    const input_constructor = try js.get(engine, data[0], "Input");
    defer engine.freeValue(input_constructor);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "prompt", try v.text(engine, " "));
    try js.define(engine, options, "placeholder", try v.text(engine, "Find in transcript"));
    try js.define(engine, options, "placeholderStyle", try engine.checked(c.JS_NewCFunction(engine.context, placeholder, "placeholderStyle", 1)));
    var input_args = [_]c.JSValue{options};
    try js.define(engine, object, "input", try engine.checked(c.JS_CallConstructor(engine.context, input_constructor, input_args.len, &input_args)));
    try js.define(engine, object, "onQueryChange", c.pi_js_undefined());
    try js.define(engine, object, "navigationButtonStyle", c.pi_js_undefined());
    try js.define(engine, object, "resultCount", c.JS_NewInt32(engine.context, 0));
    inline for (.{ "resultIndex", "previousButtonStart", "previousButtonEnd", "nextButtonStart", "nextButtonEnd" }) |name| try js.define(engine, object, name, c.JS_NewInt32(engine.context, -1));
    try js.define(engine, object, "hoveredNavigationDirection", c.pi_js_undefined());
    try js.define(engine, object, "_focused", c.pi_js_bool(engine.context, 0));
    const button_style = if (c.JS_IsUndefined(v.arg(args, 1))) try engine.checked(c.JS_NewCFunction(engine.context, identity, "navigationButtonStyle", 1)) else c.JS_DupValue(engine.context, v.arg(args, 1));
    defer engine.freeValue(button_style);
    try v.set(engine, object, "onQueryChange", c.JS_DupValue(engine.context, v.arg(args, 0)));
    try v.set(engine, object, "navigationButtonStyle", c.JS_DupValue(engine.context, button_style));
    return object;
}
fn imported(engine: *js.Engine, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try js.get(engine, bindings, name);
    defer engine.freeValue(function);
    return js.call(engine, function, c.pi_js_undefined(), args);
}
fn width(engine: *js.Engine, bindings: c.JSValue, text: c.JSValue) !f64 {
    const result = try imported(engine, bindings, "visibleWidth", &.{text});
    defer engine.freeValue(result);
    return v.number(engine, result);
}
fn math(engine: *js.Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    return js.invoke(engine, object, name, args);
}
fn maximum(engine: *js.Engine, a: f64, b: f64) !f64 {
    const result = try math(engine, "max", &.{ v.numeric(engine, a), v.numeric(engine, b) });
    defer engine.freeValue(result);
    return v.number(engine, result);
}
fn partCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return formatPart(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn formatPart(engine: *js.Engine, part: c.JSValue) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const platform = try js.get(engine, process, "platform");
    defer engine.freeValue(platform);
    const darwin = try v.text(engine, "darwin");
    defer engine.freeValue(darwin);
    if (c.JS_IsStrictEqual(engine.context, platform, darwin)) {
        const lower = try js.invoke(engine, part, "toLowerCase", &.{});
        defer engine.freeValue(lower);
        const alt = try v.text(engine, "alt");
        defer engine.freeValue(alt);
        if (c.JS_IsStrictEqual(engine.context, lower, alt)) return v.text(engine, "Option");
    }
    const first = try js.invoke(engine, part, "charAt", &.{c.JS_NewInt32(engine.context, 0)});
    defer engine.freeValue(first);
    const upper = try js.invoke(engine, first, "toUpperCase", &.{});
    defer engine.freeValue(upper);
    const rest = try js.invoke(engine, part, "slice", &.{c.JS_NewInt32(engine.context, 1)});
    defer engine.freeValue(rest);
    return v.concat(engine, &.{ upper, rest });
}
fn formatKey(engine: *js.Engine, key_value: c.JSValue) !c.JSValue {
    if (!v.truthy(engine, key_value)) return v.text(engine, "Unbound");
    const plus = try v.text(engine, "+");
    defer engine.freeValue(plus);
    const parts = try js.invoke(engine, key_value, "split", &.{plus});
    defer engine.freeValue(parts);
    const map = try js.get(engine, parts, "map");
    defer engine.freeValue(map);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, partCall, "", 1));
    defer engine.freeValue(callback);
    const formatted = try js.call(engine, map, parts, &.{callback});
    defer engine.freeValue(formatted);
    return js.invoke(engine, formatted, "join", &.{plus});
}
fn key(engine: *js.Engine, keybindings: c.JSValue, action: []const u8) !c.JSValue {
    const name = try v.text(engine, action);
    defer engine.freeValue(name);
    const keys = try js.invoke(engine, keybindings, "getKeys", &.{name});
    defer engine.freeValue(keys);
    const first = try js.getKey(engine, keys, c.JS_NewInt32(engine.context, 0));
    defer engine.freeValue(first);
    return formatKey(engine, first);
}
fn repeat(engine: *js.Engine, text: []const u8, count: f64) !c.JSValue {
    const string = try v.text(engine, text);
    defer engine.freeValue(string);
    return js.invoke(engine, string, "repeat", &.{v.numeric(engine, count)});
}
fn render(engine: *js.Engine, object: c.JSValue, bindings: c.JSValue, input_width: c.JSValue) !c.JSValue {
    const safe_width = try math(engine, "max", &.{ c.JS_NewInt32(engine.context, 1), input_width });
    defer engine.freeValue(safe_width);
    const inner_width = try maximum(engine, 0, try v.number(engine, safe_width) - 2);
    const keybindings = try imported(engine, bindings, "getKeybindings", &.{});
    defer engine.freeValue(keybindings);
    const previous_key = try key(engine, keybindings, "tui.altScreen.searchPrevious");
    defer engine.freeValue(previous_key);
    const next_key = try key(engine, keybindings, "tui.altScreen.searchNext");
    defer engine.freeValue(next_key);
    const input = try js.get(engine, object, "input");
    defer engine.freeValue(input);
    const query = try js.invoke(engine, input, "getValue", &.{});
    defer engine.freeValue(query);
    const result = blk: {
        if (!v.truthy(engine, query)) break :blk try v.text(engine, "");
        const count = try js.get(engine, object, "resultCount");
        defer engine.freeValue(count);
        if (c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0))) break :blk try v.text(engine, "No matches");
        const index = try js.get(engine, object, "resultIndex");
        defer engine.freeValue(index);
        const symbol = try js.get(engine, bindings, "primitiveSymbol");
        defer engine.freeValue(symbol);
        const incremented = try @import("native_tui_value_arithmetic.zig").add(engine, index, c.JS_NewInt32(engine.context, 1), symbol);
        defer engine.freeValue(incremented);
        const index_string = try engine.checked(c.JS_ToString(engine.context, incremented));
        defer engine.freeValue(index_string);
        const slash = try v.text(engine, "/");
        defer engine.freeValue(slash);
        const current_count = try js.get(engine, object, "resultCount");
        defer engine.freeValue(current_count);
        break :blk try v.concat(engine, &.{ index_string, slash, current_count });
    };
    defer engine.freeValue(result);
    const result_space = try maximum(engine, 0, inner_width - 3);
    const empty = try v.text(engine, "");
    defer engine.freeValue(empty);
    const visible_result = try imported(engine, bindings, "truncateToWidth", &.{ result, v.numeric(engine, result_space), empty });
    defer engine.freeValue(visible_result);
    const result_text = blk: {
        if (!v.truthy(engine, visible_result)) break :blk try v.text(engine, "");
        const begin = try v.text(engine, "\x1b[2m ");
        defer engine.freeValue(begin);
        const end = try v.text(engine, " \x1b[22m");
        defer engine.freeValue(end);
        break :blk try v.concat(engine, &.{ begin, visible_result, end });
    };
    defer engine.freeValue(result_text);
    const available_input = try maximum(engine, 0, inner_width - try width(engine, bindings, result_text));
    const current_input = try js.get(engine, object, "input");
    defer engine.freeValue(current_input);
    const rendered_input = try js.invoke(engine, current_input, "render", &.{v.numeric(engine, try maximum(engine, 1, available_input))});
    defer engine.freeValue(rendered_input);
    const first_line = try js.getKey(engine, rendered_input, c.JS_NewInt32(engine.context, 0));
    defer engine.freeValue(first_line);
    const present_line = if (c.JS_IsNull(first_line) or c.JS_IsUndefined(first_line)) c.JS_DupValue(engine.context, empty) else c.JS_DupValue(engine.context, first_line);
    defer engine.freeValue(present_line);
    const input_line = try imported(engine, bindings, "truncateToWidth", &.{ present_line, v.numeric(engine, available_input), empty });
    defer engine.freeValue(input_line);
    const padding = try repeat(engine, " ", try maximum(engine, 0, available_input - try width(engine, bindings, input_line)));
    defer engine.freeValue(padding);
    const content = try v.concat(engine, &.{ input_line, padding, result_text });
    defer engine.freeValue(content);
    const up = try v.text(engine, "↑ ");
    defer engine.freeValue(up);
    var previous_button = try v.concat(engine, &.{ up, previous_key });
    defer engine.freeValue(previous_button);
    const down = try v.text(engine, "↓ ");
    defer engine.freeValue(down);
    var next_button = try v.concat(engine, &.{ down, next_key });
    defer engine.freeValue(next_button);
    var separator = try v.text(engine, " · ");
    defer engine.freeValue(separator);
    const available_controls = try maximum(engine, 0, inner_width - 3);
    var controls_width = try width(engine, bindings, previous_button) + try width(engine, bindings, separator) + try width(engine, bindings, next_button);
    if (controls_width > available_controls) {
        const short_previous = try v.text(engine, "↑");
        engine.freeValue(previous_button);
        previous_button = short_previous;
        const short_next = try v.text(engine, "↓");
        engine.freeValue(next_button);
        next_button = short_next;
        const short_separator = try v.text(engine, " ");
        engine.freeValue(separator);
        separator = short_separator;
        controls_width = try width(engine, bindings, previous_button) + try width(engine, bindings, separator) + try width(engine, bindings, next_button);
    }
    const show_buttons = controls_width <= available_controls;
    const rendered_buttons = blk: {
        if (!show_buttons) break :blk try v.text(engine, "");
        const first_style = try js.get(engine, object, "navigationButtonStyle");
        defer engine.freeValue(first_style);
        const first_hover = try js.get(engine, object, "hoveredNavigationDirection");
        defer engine.freeValue(first_hover);
        const previous = try js.call(engine, first_style, object, &.{ previous_button, c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, first_hover, c.JS_NewInt32(engine.context, -1)))) });
        defer engine.freeValue(previous);
        const symbol = try js.get(engine, bindings, "primitiveSymbol");
        defer engine.freeValue(symbol);
        const prefix = try @import("native_tui_value_arithmetic.zig").add(engine, previous, separator, symbol);
        defer engine.freeValue(prefix);
        const second_style = try js.get(engine, object, "navigationButtonStyle");
        defer engine.freeValue(second_style);
        const second_hover = try js.get(engine, object, "hoveredNavigationDirection");
        defer engine.freeValue(second_hover);
        const next = try js.call(engine, second_style, object, &.{ next_button, c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, second_hover, c.JS_NewInt32(engine.context, 1)))) });
        defer engine.freeValue(next);
        break :blk try @import("native_tui_value_arithmetic.zig").add(engine, prefix, next, symbol);
    };
    defer engine.freeValue(rendered_buttons);
    const outer_gaps: f64 = if (show_buttons) 2 else 0;
    const right_rule: f64 = if (v.truthy(engine, rendered_buttons) and inner_width > controls_width + outer_gaps) 1 else 0;
    const left_rule = try maximum(engine, 0, inner_width - (if (show_buttons) controls_width else 0) - outer_gaps - right_rule);
    const previous_start = 2 + left_rule;
    try v.set(engine, object, "previousButtonStart", v.numeric(engine, if (show_buttons) previous_start else -1));
    try v.set(engine, object, "previousButtonEnd", v.numeric(engine, if (show_buttons) previous_start + try width(engine, bindings, previous_button) else -1));
    try v.set(engine, object, "nextButtonStart", v.numeric(engine, if (show_buttons) try v.numberField(engine, object, "previousButtonEnd") + try width(engine, bindings, separator) else -1));
    try v.set(engine, object, "nextButtonEnd", v.numeric(engine, if (show_buttons) try v.numberField(engine, object, "nextButtonStart") + try width(engine, bindings, next_button) else -1));
    const output = try js.array(engine);
    errdefer engine.freeValue(output);
    if (c.JS_IsStrictEqual(engine.context, safe_width, c.JS_NewInt32(engine.context, 1))) {
        inline for (.{ "┌", "│", "└" }) |line| {
            const text = try v.text(engine, line);
            defer engine.freeValue(text);
            try js.push(engine, output, text);
        }
        return output;
    }
    const top_left = try v.text(engine, "┌");
    defer engine.freeValue(top_left);
    const horizontal = try repeat(engine, "─", inner_width);
    defer engine.freeValue(horizontal);
    const top_right = try v.text(engine, "┐");
    defer engine.freeValue(top_right);
    const top = try v.concat(engine, &.{ top_left, horizontal, top_right });
    defer engine.freeValue(top);
    try js.push(engine, output, top);
    const side = try v.text(engine, "│");
    defer engine.freeValue(side);
    const middle = try v.concat(engine, &.{ side, content, side });
    defer engine.freeValue(middle);
    try js.push(engine, output, middle);
    const bottom_left = try v.text(engine, "└");
    defer engine.freeValue(bottom_left);
    const left = try repeat(engine, "─", left_rule);
    defer engine.freeValue(left);
    const gap = try v.text(engine, if (v.truthy(engine, rendered_buttons)) " " else "");
    defer engine.freeValue(gap);
    const right = try repeat(engine, "─", right_rule);
    defer engine.freeValue(right);
    const bottom_right = try v.text(engine, "┘");
    defer engine.freeValue(bottom_right);
    const bottom = try v.concat(engine, &.{ bottom_left, left, gap, rendered_buttons, gap, right, bottom_right });
    defer engine.freeValue(bottom);
    try js.push(engine, output, bottom);
    return output;
}
fn invoke(engine: *js.Engine, object: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .focusedGet => return js.get(engine, object, "_focused"),
        .focusedSet => {
            try v.set(engine, object, "_focused", c.JS_DupValue(engine.context, v.arg(args, 0)));
            const input = try js.get(engine, object, "input");
            defer engine.freeValue(input);
            try v.set(engine, input, "focused", c.JS_DupValue(engine.context, v.arg(args, 0)));
        },
        .setResult => {
            try v.set(engine, object, "resultIndex", c.JS_DupValue(engine.context, v.arg(args, 0)));
            try v.set(engine, object, "resultCount", c.JS_DupValue(engine.context, v.arg(args, 1)));
        },
        .getNavigationDirectionAt => {
            if (!c.JS_IsStrictEqual(engine.context, v.arg(args, 0), c.JS_NewInt32(engine.context, 2))) return c.pi_js_undefined();
            const column = v.arg(args, 1);
            if (try v.number(engine, column) >= try v.numberField(engine, object, "previousButtonStart") and try v.number(engine, column) < try v.numberField(engine, object, "previousButtonEnd")) return c.JS_NewInt32(engine.context, -1);
            if (try v.number(engine, column) >= try v.numberField(engine, object, "nextButtonStart") and try v.number(engine, column) < try v.numberField(engine, object, "nextButtonEnd")) return c.JS_NewInt32(engine.context, 1);
            return c.pi_js_undefined();
        },
        .setHoveredNavigationDirection => {
            const previous = try js.get(engine, object, "hoveredNavigationDirection");
            defer engine.freeValue(previous);
            if (c.JS_IsStrictEqual(engine.context, v.arg(args, 0), previous)) return c.pi_js_bool(engine.context, 0);
            try v.set(engine, object, "hoveredNavigationDirection", c.JS_DupValue(engine.context, v.arg(args, 0)));
            return c.pi_js_bool(engine.context, 1);
        },
        .handleInput => {
            const input = try js.get(engine, object, "input");
            defer engine.freeValue(input);
            const previous = try js.invoke(engine, input, "getValue", &.{});
            defer engine.freeValue(previous);
            const current = try js.get(engine, object, "input");
            defer engine.freeValue(current);
            try v.invokeVoid(engine, current, "handleInput", &.{v.arg(args, 0)});
            const afterward = try js.get(engine, object, "input");
            defer engine.freeValue(afterward);
            const query = try js.invoke(engine, afterward, "getValue", &.{});
            defer engine.freeValue(query);
            if (!c.JS_IsStrictEqual(engine.context, query, previous)) try v.invokeVoid(engine, object, "onQueryChange", &.{query});
        },
        .invalidate => {
            const input = try js.get(engine, object, "input");
            defer engine.freeValue(input);
            try v.invokeVoid(engine, input, "invalidate", &.{});
        },
        .render => return render(engine, object, bindings, v.arg(args, 0)),
    }
    return c.pi_js_undefined();
}
fn call(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, object, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
pub fn create(engine: *js.Engine, exports: c.JSValue) !c.JSValue {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    inline for (.{ "Input", "getKeybindings", "truncateToWidth", "visibleWidth" }) |name| try js.define(engine, bindings, name, try js.get(engine, exports, name));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, bindings, "primitiveSymbol", try js.get(engine, symbol, "toPrimitive"));
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const focus_atom = c.JS_NewAtom(engine.context, "focused");
    if (focus_atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, focus_atom);
    var data = [_]c.JSValue{bindings};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, "get focused", 0, @intFromEnum(Method.focusedGet), 1, &data));
    const setter = engine.checked(c.JS_NewCFunctionData2(engine.context, call, "set focused", 1, @intFromEnum(Method.focusedSet), 1, &data)) catch |err| {
        engine.freeValue(getter);
        return err;
    };
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, focus_atom, getter, setter, c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        if (method != .focusedGet and method != .focusedSet) {
            const length: c_int = switch (method) {
                .setResult, .getNavigationDirectionAt => 2,
                .setHoveredNavigationDirection, .handleInput, .render => 1,
                else => 0,
            };
            const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, field.name, length, field.value, 1, &data));
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        }
    }
    return @import("native_class.zig").constructor(engine, "AltScreenSearchComponent", 1, prototype, construct, &.{bindings});
}

//! Source overlay layout over the supplied options and current virtual anchors.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn defaultField(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, fallback: f64) !c.JSValue {
    const value = try js.get(engine, object, name);
    if (!nullish(value)) return value;
    engine.freeValue(value);
    return v.numeric(engine, fallback);
}
fn math(engine: *js.Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    return js.invoke(engine, object, name, args);
}
fn pattern(engine: *js.Engine) !c.JSValue {
    const source = try v.text(engine, "^(\\d+(?:\\.\\d+)?)%$");
    defer engine.freeValue(source);
    var args = [_]c.JSValue{source};
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 1, &args));
}
fn percentage(engine: *js.Engine, value: c.JSValue) !c.JSValue {
    const match_method = try js.get(engine, value, "match");
    defer engine.freeValue(match_method);
    const regexp = try pattern(engine);
    defer engine.freeValue(regexp);
    return js.call(engine, match_method, value, &.{regexp});
}
fn parsePercent(engine: *js.Engine, match: c.JSValue) !f64 {
    const parse = try js.global(engine, "parseFloat");
    defer engine.freeValue(parse);
    const digits = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 1));
    defer engine.freeValue(digits);
    const value = try js.call(engine, parse, c.pi_js_undefined(), &.{digits});
    defer engine.freeValue(value);
    return v.number(engine, value);
}
fn size(engine: *js.Engine, value: c.JSValue, reference: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value) or c.JS_IsNumber(value)) return c.JS_DupValue(engine.context, value);
    const match = try percentage(engine, value);
    defer engine.freeValue(match);
    if (!v.truthy(engine, match)) return c.pi_js_undefined();
    return math(engine, "floor", &.{v.numeric(engine, try v.number(engine, reference) * try parsePercent(engine, match) / 100)});
}
fn add(engine: *js.Engine, bindings: c.JSValue, a: c.JSValue, b: c.JSValue) !c.JSValue {
    const symbol = try js.get(engine, bindings, "primitiveSymbol");
    defer engine.freeValue(symbol);
    return @import("native_tui_value_arithmetic.zig").add(engine, a, b, symbol);
}
fn marginValue(engine: *js.Engine, margin: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    const maximum = try js.get(engine, object, "max");
    defer engine.freeValue(maximum);
    const value = try defaultField(engine, margin, name, 0);
    defer engine.freeValue(value);
    return js.call(engine, maximum, object, &.{ c.JS_NewInt32(engine.context, 0), value });
}
fn anchor(engine: *js.Engine, screen: c.JSValue, name: [*:0]const u8, options: c.JSValue, extent: c.JSValue, available: c.JSValue, margin: c.JSValue, forced_center: bool) !c.JSValue {
    const function = try js.get(engine, screen, name);
    defer engine.freeValue(function);
    var selected = if (forced_center) try v.text(engine, "center") else try js.get(engine, options, "anchor");
    defer engine.freeValue(selected);
    if (nullish(selected)) {
        const center = try v.text(engine, "center");
        engine.freeValue(selected);
        selected = center;
    }
    return js.call(engine, function, screen, &.{ selected, extent, available, margin });
}
fn position(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, options: c.JSValue, field: [*:0]const u8, anchor_name: [*:0]const u8, extent: c.JSValue, available: c.JSValue, margin: c.JSValue) !c.JSValue {
    const initial = try js.get(engine, options, field);
    defer engine.freeValue(initial);
    if (c.JS_IsUndefined(initial)) return anchor(engine, screen, anchor_name, options, extent, available, margin, false);
    const typed = try js.get(engine, options, field);
    defer engine.freeValue(typed);
    if (!c.JS_IsString(typed)) return js.get(engine, options, field);
    const current = try js.get(engine, options, field);
    defer engine.freeValue(current);
    const match = try percentage(engine, current);
    defer engine.freeValue(match);
    if (!v.truthy(engine, match)) return anchor(engine, screen, anchor_name, options, extent, available, margin, true);
    const maximum = try math(engine, "max", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try v.number(engine, available) - try v.number(engine, extent)) });
    defer engine.freeValue(maximum);
    const percent = try parsePercent(engine, match) / 100;
    const rounded = try math(engine, "floor", &.{v.numeric(engine, try v.number(engine, maximum) * percent)});
    defer engine.freeValue(rounded);
    return add(engine, bindings, margin, rounded);
}
pub fn resolve(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const options = if (nullish(v.arg(args, 0))) try js.object(engine) else c.JS_DupValue(engine.context, args[0]);
    defer engine.freeValue(options);
    const overlay_height = v.arg(args, 1);
    const term_width = v.arg(args, 2);
    const term_height = v.arg(args, 3);
    const initial_margin = try js.get(engine, options, "margin");
    defer engine.freeValue(initial_margin);
    const margin = blk: {
        if (c.JS_IsNumber(initial_margin)) {
            const object = try js.object(engine);
            errdefer engine.freeValue(object);
            inline for (.{ "top", "right", "bottom", "left" }) |name| try js.define(engine, object, name, try js.get(engine, options, "margin"));
            break :blk object;
        }
        const value = try js.get(engine, options, "margin");
        if (!nullish(value)) break :blk value;
        engine.freeValue(value);
        break :blk try js.object(engine);
    };
    defer engine.freeValue(margin);
    const top = try marginValue(engine, margin, "top");
    defer engine.freeValue(top);
    const right = try marginValue(engine, margin, "right");
    defer engine.freeValue(right);
    const bottom = try marginValue(engine, margin, "bottom");
    defer engine.freeValue(bottom);
    const left = try marginValue(engine, margin, "left");
    defer engine.freeValue(left);
    const available_width = try math(engine, "max", &.{ c.JS_NewInt32(engine.context, 1), v.numeric(engine, try v.number(engine, term_width) - try v.number(engine, left) - try v.number(engine, right)) });
    defer engine.freeValue(available_width);
    const available_height = try math(engine, "max", &.{ c.JS_NewInt32(engine.context, 1), v.numeric(engine, try v.number(engine, term_height) - try v.number(engine, top) - try v.number(engine, bottom)) });
    defer engine.freeValue(available_height);
    const width_value = try js.get(engine, options, "width");
    defer engine.freeValue(width_value);
    var width = try size(engine, width_value, term_width);
    defer engine.freeValue(width);
    if (nullish(width)) {
        const fallback = try math(engine, "min", &.{ c.JS_NewInt32(engine.context, 80), available_width });
        engine.freeValue(width);
        width = fallback;
    }
    const has_minimum = try js.get(engine, options, "minWidth");
    defer engine.freeValue(has_minimum);
    if (!c.JS_IsUndefined(has_minimum)) {
        const object = try js.global(engine, "Math");
        defer engine.freeValue(object);
        const maximum = try js.get(engine, object, "max");
        defer engine.freeValue(maximum);
        const minimum = try js.get(engine, options, "minWidth");
        defer engine.freeValue(minimum);
        const next = try js.call(engine, maximum, object, &.{ width, minimum });
        engine.freeValue(width);
        width = next;
    }
    const clamped_width = try clamp(engine, width, available_width);
    engine.freeValue(width);
    width = clamped_width;
    const maximum_value = try js.get(engine, options, "maxHeight");
    defer engine.freeValue(maximum_value);
    var maximum_height = try size(engine, maximum_value, term_height);
    defer engine.freeValue(maximum_height);
    if (!c.JS_IsUndefined(maximum_height)) {
        const next = try clamp(engine, maximum_height, available_height);
        engine.freeValue(maximum_height);
        maximum_height = next;
    }
    const effective_height = if (!c.JS_IsUndefined(maximum_height)) try math(engine, "min", &.{ overlay_height, maximum_height }) else c.JS_DupValue(engine.context, overlay_height);
    defer engine.freeValue(effective_height);
    var row = try position(engine, screen, bindings, options, "row", "resolveAnchorRow", effective_height, available_height, top);
    defer engine.freeValue(row);
    var col = try position(engine, screen, bindings, options, "col", "resolveAnchorCol", width, available_width, left);
    defer engine.freeValue(col);
    inline for (.{ .{ "offsetY", &row }, .{ "offsetX", &col } }) |item| {
        const check = try js.get(engine, options, item[0]);
        defer engine.freeValue(check);
        if (!c.JS_IsUndefined(check)) {
            const offset = try js.get(engine, options, item[0]);
            defer engine.freeValue(offset);
            const next = try add(engine, bindings, item[1].*, offset);
            engine.freeValue(item[1].*);
            item[1].* = next;
        }
    }
    const final_row = try bounds(engine, row, top, v.numeric(engine, try v.number(engine, term_height) - try v.number(engine, bottom) - try v.number(engine, effective_height)));
    defer engine.freeValue(final_row);
    const final_col = try bounds(engine, col, left, v.numeric(engine, try v.number(engine, term_width) - try v.number(engine, right) - try v.number(engine, width)));
    defer engine.freeValue(final_col);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "width", c.JS_DupValue(engine.context, width));
    try js.define(engine, result, "row", c.JS_DupValue(engine.context, final_row));
    try js.define(engine, result, "col", c.JS_DupValue(engine.context, final_col));
    try js.define(engine, result, "maxHeight", c.JS_DupValue(engine.context, maximum_height));
    return result;
}
fn bounds(engine: *js.Engine, value: c.JSValue, minimum: c.JSValue, maximum: c.JSValue) !c.JSValue {
    const outer = try js.global(engine, "Math");
    defer engine.freeValue(outer);
    const max_function = try js.get(engine, outer, "max");
    defer engine.freeValue(max_function);
    const inner = try math(engine, "min", &.{ value, maximum });
    defer engine.freeValue(inner);
    return js.call(engine, max_function, outer, &.{ minimum, inner });
}
fn clamp(engine: *js.Engine, value: c.JSValue, maximum: c.JSValue) !c.JSValue {
    return bounds(engine, value, c.JS_NewInt32(engine.context, 1), maximum);
}

//! Source Kitty image header/row tracking for regular-screen differential output.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum { collectKittyImageIds, deleteKittyImages, getKittyImageReservedRows, expandChangedRangeForKittyImages, deleteChangedKittyImages };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn iterator(engine: *js.Engine, value: c.JSValue, bindings: c.JSValue) !js.Iterator {
    const symbol = try js.get(engine, bindings, "iteratorSymbol");
    defer engine.freeValue(symbol);
    return js.Iterator.init(engine, value, symbol);
}
fn add(engine: *js.Engine, bindings: c.JSValue, first: c.JSValue, second: c.JSValue) !c.JSValue {
    const symbol = try js.get(engine, bindings, "primitiveSymbol");
    defer engine.freeValue(symbol);
    return @import("native_tui_value_arithmetic.zig").add(engine, first, second, symbol);
}
fn math(engine: *js.Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    return js.invoke(engine, object, name, args);
}
fn header(engine: *js.Engine, line: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const prefix = try v.text(engine, "\x1b_G");
    defer engine.freeValue(prefix);
    const start = try js.invoke(engine, line, "indexOf", &.{prefix});
    defer engine.freeValue(start);
    if (c.JS_IsStrictEqual(engine.context, start, c.JS_NewInt32(engine.context, -1))) return c.pi_js_undefined();
    const params_start = try add(engine, bindings, start, c.JS_NewInt32(engine.context, 3));
    defer engine.freeValue(params_start);
    const index_of = try js.get(engine, line, "indexOf");
    defer engine.freeValue(index_of);
    const semicolon = try v.text(engine, ";");
    defer engine.freeValue(semicolon);
    const end = try js.call(engine, index_of, line, &.{ semicolon, params_start });
    defer engine.freeValue(end);
    if (c.JS_IsStrictEqual(engine.context, end, c.JS_NewInt32(engine.context, -1))) return c.pi_js_undefined();
    const ids = try js.array(engine);
    defer engine.freeValue(ids);
    var rows = c.JS_NewInt32(engine.context, 1);
    defer engine.freeValue(rows);
    const sliced = try js.invoke(engine, line, "slice", &.{ params_start, end });
    defer engine.freeValue(sliced);
    const comma = try v.text(engine, ",");
    defer engine.freeValue(comma);
    const params = try js.invoke(engine, sliced, "split", &.{comma});
    defer engine.freeValue(params);
    var items = try iterator(engine, params, bindings);
    defer items.deinit();
    errdefer items.closePreserving();
    while (try items.next()) |param| {
        defer engine.freeValue(param);
        const split = try js.get(engine, param, "split");
        defer engine.freeValue(split);
        const equals = try v.text(engine, "=");
        defer engine.freeValue(equals);
        const pieces = try js.call(engine, split, param, &.{ equals, c.JS_NewInt32(engine.context, 2) });
        defer engine.freeValue(pieces);
        const symbol = try js.get(engine, bindings, "iteratorSymbol");
        defer engine.freeValue(symbol);
        const pair = try js.pair(engine, pieces, symbol);
        defer engine.freeValue(pair[0]);
        defer engine.freeValue(pair[1]);
        if (c.JS_IsUndefined(pair[1])) continue;
        const constructor = try js.global(engine, "Number");
        defer engine.freeValue(constructor);
        const number = try js.call(engine, constructor, c.pi_js_undefined(), &.{pair[1]});
        defer engine.freeValue(number);
        const current_number = try js.global(engine, "Number");
        defer engine.freeValue(current_number);
        const integer = try js.invoke(engine, current_number, "isInteger", &.{number});
        defer engine.freeValue(integer);
        if (!v.truthy(engine, integer) or try v.number(engine, number) <= 0 or try v.number(engine, number) > 0xffffffff) continue;
        const image_key = try v.text(engine, "i");
        defer engine.freeValue(image_key);
        if (c.JS_IsStrictEqual(engine.context, pair[0], image_key)) {
            try js.push(engine, ids, number);
        } else {
            const row_key = try v.text(engine, "r");
            defer engine.freeValue(row_key);
            if (c.JS_IsStrictEqual(engine.context, pair[0], row_key)) {
                engine.freeValue(rows);
                rows = c.JS_DupValue(engine.context, number);
            }
        }
    }
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "ids", c.JS_DupValue(engine.context, ids));
    try js.define(engine, result, "rows", c.JS_DupValue(engine.context, rows));
    return result;
}
fn imageIds(engine: *js.Engine, line: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const parsed = try header(engine, line, bindings);
    defer engine.freeValue(parsed);
    if (nullish(parsed)) return js.array(engine);
    const ids = try js.get(engine, parsed, "ids");
    if (!nullish(ids)) return ids;
    engine.freeValue(ids);
    return js.array(engine);
}
fn imageRows(engine: *js.Engine, line: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const parsed = try header(engine, line, bindings);
    defer engine.freeValue(parsed);
    if (nullish(parsed)) return c.JS_NewInt32(engine.context, 1);
    const rows = try js.get(engine, parsed, "rows");
    if (!nullish(rows)) return rows;
    engine.freeValue(rows);
    return c.JS_NewInt32(engine.context, 1);
}
fn lineAt(engine: *js.Engine, lines: c.JSValue, index: c.JSValue) !c.JSValue {
    const line = try js.getKey(engine, lines, index);
    if (!nullish(line)) return line;
    engine.freeValue(line);
    return v.text(engine, "");
}
fn addLineIds(engine: *js.Engine, ids: c.JSValue, line: c.JSValue, bindings: c.JSValue) !void {
    const values = try imageIds(engine, line, bindings);
    defer engine.freeValue(values);
    var items = try iterator(engine, values, bindings);
    defer items.deinit();
    errdefer items.closePreserving();
    while (try items.next()) |id| {
        defer engine.freeValue(id);
        try v.invokeVoid(engine, ids, "add", &.{id});
    }
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .collectKittyImageIds => {
            const ids = try js.builtin(engine, "Set", &.{});
            errdefer engine.freeValue(ids);
            var lines = try iterator(engine, v.arg(args, 0), bindings);
            defer lines.deinit();
            errdefer lines.closePreserving();
            while (try lines.next()) |line| {
                defer engine.freeValue(line);
                try addLineIds(engine, ids, line, bindings);
            }
            return ids;
        },
        .deleteKittyImages => {
            var buffer = try v.text(engine, "");
            errdefer engine.freeValue(buffer);
            var ids = try iterator(engine, v.arg(args, 0), bindings);
            defer ids.deinit();
            errdefer ids.closePreserving();
            while (try ids.next()) |id| {
                defer engine.freeValue(id);
                const delete = try js.get(engine, bindings, "deleteKittyImage");
                defer engine.freeValue(delete);
                const output = try js.call(engine, delete, c.pi_js_undefined(), &.{id});
                defer engine.freeValue(output);
                const next = try add(engine, bindings, buffer, output);
                engine.freeValue(buffer);
                buffer = next;
            }
            return buffer;
        },
        .getKittyImageReservedRows => return reserved(engine, bindings, args),
        .expandChangedRangeForKittyImages => return expanded(engine, screen, bindings, args),
        .deleteChangedKittyImages => {
            const first = v.arg(args, 0);
            const last = v.arg(args, 1);
            if (try v.number(engine, first) < 0 or try v.number(engine, last) < try v.number(engine, first)) return v.text(engine, "");
            const ids = try js.builtin(engine, "Set", &.{});
            defer engine.freeValue(ids);
            const math_object = try js.global(engine, "Math");
            defer engine.freeValue(math_object);
            const minimum = try js.get(engine, math_object, "min");
            defer engine.freeValue(minimum);
            const previous = try js.get(engine, screen, "previousLines");
            defer engine.freeValue(previous);
            const maximum = try js.call(engine, minimum, math_object, &.{ last, v.numeric(engine, try v.numberField(engine, previous, "length") - 1) });
            defer engine.freeValue(maximum);
            var index = try v.number(engine, first);
            while (index <= try v.number(engine, maximum)) : (index += 1) {
                const current = try js.get(engine, screen, "previousLines");
                defer engine.freeValue(current);
                const line = try lineAt(engine, current, v.numeric(engine, index));
                defer engine.freeValue(line);
                try addLineIds(engine, ids, line, bindings);
            }
            return js.invoke(engine, screen, "deleteKittyImages", &.{ids});
        },
    }
}
fn reserved(engine: *js.Engine, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const lines = v.arg(args, 0);
    const index = v.arg(args, 1);
    const maximum = if (c.JS_IsUndefined(v.arg(args, 2))) v.numeric(engine, try v.numberField(engine, lines, "length") - 1) else c.JS_DupValue(engine.context, args[2]);
    defer engine.freeValue(maximum);
    const line = try lineAt(engine, lines, index);
    defer engine.freeValue(line);
    const rows = try imageRows(engine, line, bindings);
    defer engine.freeValue(rows);
    if (try v.number(engine, rows) <= 1) return c.JS_NewInt32(engine.context, 1);
    const math_object = try js.global(engine, "Math");
    defer engine.freeValue(math_object);
    const minimum = try js.get(engine, math_object, "min");
    defer engine.freeValue(minimum);
    const max_rows = try js.call(engine, minimum, math_object, &.{ rows, v.numeric(engine, try v.number(engine, maximum) - try v.number(engine, index) + 1), v.numeric(engine, try v.numberField(engine, lines, "length") - try v.number(engine, index)) });
    defer engine.freeValue(max_rows);
    var count: f64 = 1;
    while (count < try v.number(engine, max_rows)) : (count += 1) {
        const next_index = try add(engine, bindings, index, v.numeric(engine, count));
        defer engine.freeValue(next_index);
        const current = try lineAt(engine, lines, next_index);
        defer engine.freeValue(current);
        const is_image = try js.get(engine, bindings, "isImageLine");
        defer engine.freeValue(is_image);
        const image = try js.call(engine, is_image, c.pi_js_undefined(), &.{current});
        defer engine.freeValue(image);
        if (v.truthy(engine, image)) break;
        const visible_width = try js.get(engine, bindings, "visibleWidth");
        defer engine.freeValue(visible_width);
        const width = try js.call(engine, visible_width, c.pi_js_undefined(), &.{current});
        defer engine.freeValue(width);
        if (try v.number(engine, width) > 0) break;
    }
    return v.numeric(engine, count);
}
fn expandFor(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, lines: c.JSValue, first: f64, last: f64, expanded_first: *f64, expanded_last: *f64) !void {
    var index: f64 = 0;
    while (index < try v.numberField(engine, lines, "length")) : (index += 1) {
        const line = try js.getKey(engine, lines, v.numeric(engine, index));
        defer engine.freeValue(line);
        const ids = try imageIds(engine, line, bindings);
        defer engine.freeValue(ids);
        const length = try js.get(engine, ids, "length");
        defer engine.freeValue(length);
        if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) continue;
        const reserved_rows = try js.invoke(engine, screen, "getKittyImageReservedRows", &.{ lines, v.numeric(engine, index) });
        defer engine.freeValue(reserved_rows);
        const sum = try add(engine, bindings, v.numeric(engine, index), reserved_rows);
        defer engine.freeValue(sum);
        const block_end = try v.number(engine, sum) - 1;
        if (index >= first or (index <= last and block_end >= first)) {
            const minimum = try math(engine, "min", &.{ v.numeric(engine, expanded_first.*), v.numeric(engine, index) });
            defer engine.freeValue(minimum);
            expanded_first.* = try v.number(engine, minimum);
            const maximum = try math(engine, "max", &.{ v.numeric(engine, expanded_last.*), v.numeric(engine, block_end) });
            defer engine.freeValue(maximum);
            expanded_last.* = try v.number(engine, maximum);
        }
    }
}
fn expanded(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const first = try v.number(engine, v.arg(args, 0));
    const last = try v.number(engine, v.arg(args, 1));
    var expanded_first = first;
    var expanded_last = last;
    const previous = try js.get(engine, screen, "previousLines");
    defer engine.freeValue(previous);
    try expandFor(engine, screen, bindings, previous, first, last, &expanded_first, &expanded_last);
    try expandFor(engine, screen, bindings, v.arg(args, 2), first, last, &expanded_first, &expanded_last);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "firstChanged", v.numeric(engine, expanded_first));
    try js.define(engine, result, "lastChanged", v.numeric(engine, expanded_last));
    return result;
}

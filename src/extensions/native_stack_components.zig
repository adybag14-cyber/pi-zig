//! Source Stack/HStack/VStack with ordinary entries and genuine virtual array operations.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const arithmetic = @import("native_tui_value_arithmetic.zig");
const maximum_safe_integer: f64 = 9007199254740991;
const Callback = enum(c_int) { visible, intrinsicH, maxWidth, renderH, height, maxHeight, renderV, size, sum, pair, eligible, weight, findChild, empty };
const Method = enum(c_int) { addChild, removeChild, clear, layout, renderH, renderV };
threadlocal var render_depth: usize = 0;
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Stack: %s", @as([*:0]const u8, @errorName(err)));
}
fn fieldDefault(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, fallback: f64) !c.JSValue {
    const value = try js.get(engine, object, name);
    if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) return value;
    engine.freeValue(value);
    return v.numeric(engine, fallback);
}
fn normalize(engine: *js.Engine, value: c.JSValue, fallback: f64) !f64 {
    if (!c.JS_IsNumber(value)) return fallback;
    const number = try v.number(engine, value);
    if (!std.math.isFinite(number)) return fallback;
    return v.maximum(0, @floor(number));
}
fn equalText(engine: *js.Engine, value: c.JSValue, text: []const u8) !bool {
    const expected = try v.text(engine, text);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn defineContext(engine: *js.Engine, context: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try js.define(engine, context, name, c.JS_DupValue(engine.context, value));
}
fn callback(engine: *js.Engine, kind: Callback, context: c.JSValue) !c.JSValue {
    const length: c_int = switch (kind) {
        .empty => 0,
        .maxWidth, .maxHeight, .renderH, .size, .sum, .pair, .weight => 2,
        else => 1,
    };
    var values = [_]c.JSValue{context};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callbackCall, "", length, @intFromEnum(kind), values.len, &values));
}
fn map(engine: *js.Engine, array: c.JSValue, kind: Callback, context: c.JSValue) !c.JSValue {
    const function = try callback(engine, kind, context);
    defer engine.freeValue(function);
    return js.invoke(engine, array, "map", &.{function});
}
fn reduce(engine: *js.Engine, array: c.JSValue, kind: Callback, context: c.JSValue) !c.JSValue {
    const function = try callback(engine, kind, context);
    defer engine.freeValue(function);
    return js.invoke(engine, array, "reduce", &.{ function, c.JS_NewInt32(engine.context, 0) });
}
fn clamp(engine: *js.Engine, value: c.JSValue, entry: c.JSValue) !f64 {
    const minimum = try fieldDefault(engine, entry, "minSize", 0);
    defer engine.freeValue(minimum);
    const low = v.maximum(0, @floor(try v.number(engine, minimum)));
    const maximum = try fieldDefault(engine, entry, "maxSize", maximum_safe_integer);
    defer engine.freeValue(maximum);
    const high = v.maximum(low, @floor(try v.number(engine, maximum)));
    return v.maximum(low, v.minimum(high, v.maximum(0, @floor(try v.number(engine, value)))));
}
fn growing(engine: *js.Engine, context: c.JSValue) !bool {
    const value = try js.get(engine, context, "growing");
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn weight(engine: *js.Engine, pair: c.JSValue, context: c.JSValue) !c.JSValue {
    const entry = try js.get(engine, pair, "entry");
    defer engine.freeValue(entry);
    if (try growing(engine, context)) return fieldDefault(engine, entry, "grow", 0);
    const shrink = try fieldDefault(engine, entry, "shrink", 1);
    defer engine.freeValue(shrink);
    const index = try js.get(engine, pair, "index");
    defer engine.freeValue(index);
    const sizes = try js.get(engine, context, "sizes");
    defer engine.freeValue(sizes);
    const size = try js.getKey(engine, sizes, index);
    defer engine.freeValue(size);
    return v.numeric(engine, try v.number(engine, shrink) * v.maximum(1, try v.number(engine, size)));
}
fn callbackOperation(engine: *js.Engine, kind: Callback, args: []const c.JSValue, context: c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (kind) {
        .visible => {
            const function = try js.get(engine, first, "visible");
            defer engine.freeValue(function);
            if (c.JS_IsNull(function) or c.JS_IsUndefined(function)) return c.pi_js_bool(engine.context, 1);
            const viewport = try js.get(engine, context, "viewport");
            defer engine.freeValue(viewport);
            const result = try js.call(engine, function, first, &.{viewport});
            if (!c.JS_IsNull(result) and !c.JS_IsUndefined(result)) return result;
            engine.freeValue(result);
            return c.pi_js_bool(engine.context, 1);
        },
        .intrinsicH => {
            const component = try js.get(engine, first, "component");
            defer engine.freeValue(component);
            const function = try js.get(engine, component, "render");
            defer engine.freeValue(function);
            const width = try js.get(engine, context, "safeWidth");
            defer engine.freeValue(width);
            const lines = try js.call(engine, function, component, &.{width});
            defer engine.freeValue(lines);
            return reduce(engine, lines, .maxWidth, context);
        },
        .maxWidth => return v.numeric(engine, v.maximum(try v.number(engine, first), try v.width(engine, v.arg(args, 1)))),
        .height => return js.get(engine, first, "length"),
        .maxHeight => return v.numeric(engine, v.maximum(try v.number(engine, first), try v.numberField(engine, v.arg(args, 1), "length"))),
        .renderH => {
            const sizes = try js.get(engine, context, "sizes");
            defer engine.freeValue(sizes);
            const current = try js.getKey(engine, sizes, v.arg(args, 1));
            defer engine.freeValue(current);
            if (c.JS_IsStrictEqual(engine.context, current, c.JS_NewInt32(engine.context, 0))) return js.array(engine);
            const component = try js.get(engine, first, "component");
            defer engine.freeValue(component);
            const function = try js.get(engine, component, "render");
            defer engine.freeValue(function);
            const width = try js.getKey(engine, sizes, v.arg(args, 1));
            defer engine.freeValue(width);
            return js.call(engine, function, component, &.{width});
        },
        .renderV => {
            const component = try js.get(engine, first, "component");
            defer engine.freeValue(component);
            const function = try js.get(engine, component, "render");
            defer engine.freeValue(function);
            const viewport = try js.get(engine, context, "viewport");
            defer engine.freeValue(viewport);
            const width = try js.get(engine, viewport, "width");
            defer engine.freeValue(width);
            return js.call(engine, function, component, &.{width});
        },
        .size => {
            const first_basis = try js.get(engine, first, "basis");
            defer engine.freeValue(first_basis);
            var intrinsic = c.JS_IsUndefined(first_basis);
            if (!intrinsic) {
                const second = try js.get(engine, first, "basis");
                defer engine.freeValue(second);
                intrinsic = try equalText(engine, second, "auto");
            }
            const size = if (intrinsic) blk: {
                const sizes = try js.get(engine, context, "intrinsic");
                defer engine.freeValue(sizes);
                const raw = try js.getKey(engine, sizes, v.arg(args, 1));
                if (!c.JS_IsNull(raw) and !c.JS_IsUndefined(raw)) break :blk raw;
                engine.freeValue(raw);
                break :blk c.JS_NewInt32(engine.context, 0);
            } else try js.get(engine, first, "basis");
            defer engine.freeValue(size);
            return v.numeric(engine, try clamp(engine, size, first));
        },
        .sum => {
            const symbol = try js.get(engine, context, "primitiveSymbol");
            defer engine.freeValue(symbol);
            return arithmetic.add(engine, first, v.arg(args, 1), symbol);
        },
        .pair => {
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            try defineContext(engine, result, "entry", first);
            try defineContext(engine, result, "index", v.arg(args, 1));
            return result;
        },
        .eligible => {
            const entry = try js.get(engine, first, "entry");
            defer engine.freeValue(entry);
            const index = try js.get(engine, first, "index");
            defer engine.freeValue(index);
            const is_growing = try growing(engine, context);
            const strength = try fieldDefault(engine, entry, if (is_growing) "grow" else "shrink", if (is_growing) 0 else 1);
            defer engine.freeValue(strength);
            if (!(try v.number(engine, strength) > 0)) return c.pi_js_bool(engine.context, 0);
            const sizes = try js.get(engine, context, "sizes");
            defer engine.freeValue(sizes);
            const size = try js.getKey(engine, sizes, index);
            defer engine.freeValue(size);
            const limit = try fieldDefault(engine, entry, if (is_growing) "maxSize" else "minSize", if (is_growing) maximum_safe_integer else 0);
            defer engine.freeValue(limit);
            const a = try v.number(engine, size);
            const b = try v.number(engine, limit);
            return c.pi_js_bool(engine.context, @intFromBool(if (is_growing) a < b else a > b));
        },
        .weight => {
            const current = try weight(engine, v.arg(args, 1), context);
            defer engine.freeValue(current);
            const symbol = try js.get(engine, context, "primitiveSymbol");
            defer engine.freeValue(symbol);
            return arithmetic.add(engine, first, current, symbol);
        },
        .findChild => {
            const component = try js.get(engine, first, "component");
            defer engine.freeValue(component);
            const selected = try js.get(engine, context, "component");
            defer engine.freeValue(selected);
            return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, component, selected)));
        },
        .empty => return v.text(engine, ""),
    }
}
fn callbackCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return callbackOperation(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0]) catch |err| fail(engine, err);
}
fn distribute(engine: *js.Engine, sizes: c.JSValue, entries: c.JSValue, amount: f64, is_growing: bool, context: c.JSValue) !void {
    try defineContext(engine, context, "sizes", sizes);
    try js.define(engine, context, "growing", c.pi_js_bool(engine.context, @intFromBool(is_growing)));
    const iterator_symbol = try js.get(engine, context, "iteratorSymbol");
    defer engine.freeValue(iterator_symbol);
    var remaining = amount;
    var rounds: usize = 0;
    while (remaining > 0) {
        rounds += 1;
        if (rounds > 16384) {
            _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum layout distribution iterations exceeded"));
            unreachable;
        }
        const pairs = try map(engine, entries, .pair, context);
        defer engine.freeValue(pairs);
        const predicate = try callback(engine, .eligible, context);
        defer engine.freeValue(predicate);
        const candidates = try js.invoke(engine, pairs, "filter", &.{predicate});
        defer engine.freeValue(candidates);
        const length = try js.get(engine, candidates, "length");
        defer engine.freeValue(length);
        if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) return;
        const total = try reduce(engine, candidates, .weight, context);
        defer engine.freeValue(total);
        var distributed: f64 = 0;
        var iterator = try js.Iterator.init(engine, candidates, iterator_symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |candidate| {
            defer engine.freeValue(candidate);
            const entry = try js.get(engine, candidate, "entry");
            defer engine.freeValue(entry);
            const index = try js.get(engine, candidate, "index");
            defer engine.freeValue(index);
            if (remaining <= 0) {
                try iterator.close();
                break;
            }
            const strength = try weight(engine, candidate, context);
            defer engine.freeValue(strength);
            const proposed = v.maximum(1, @floor(remaining * try v.number(engine, strength) / try v.number(engine, total)));
            const boundary = try fieldDefault(engine, entry, if (is_growing) "maxSize" else "minSize", if (is_growing) maximum_safe_integer else 0);
            defer engine.freeValue(boundary);
            const old_size = try js.getKey(engine, sizes, index);
            defer engine.freeValue(old_size);
            const capacity = if (is_growing) try v.number(engine, boundary) - try v.number(engine, old_size) else try v.number(engine, old_size) - try v.number(engine, boundary);
            const delta = v.minimum(remaining, v.minimum(proposed, capacity));
            if (delta <= 0) continue;
            const current = try js.getKey(engine, sizes, index);
            defer engine.freeValue(current);
            const symbol = try js.get(engine, context, "primitiveSymbol");
            defer engine.freeValue(symbol);
            const next = try arithmetic.add(engine, current, v.numeric(engine, if (is_growing) delta else -delta), symbol);
            defer engine.freeValue(next);
            try js.setKey(engine, sizes, index, next);
            remaining -= delta;
            distributed += delta;
        }
        if (distributed == 0) return;
    }
}
fn allocate(engine: *js.Engine, entries: c.JSValue, intrinsic: c.JSValue, available: c.JSValue, gap: c.JSValue, context: c.JSValue) !c.JSValue {
    try defineContext(engine, context, "intrinsic", intrinsic);
    const sizes = try map(engine, entries, .size, context);
    errdefer engine.freeValue(sizes);
    if (c.JS_IsUndefined(available)) return sizes;
    const available_size = @floor(try v.number(engine, available));
    const gaps = v.maximum(0, try v.numberField(engine, entries, "length") - 1);
    const content = v.maximum(0, available_size - gaps * try v.number(engine, gap));
    const total = try reduce(engine, sizes, .sum, context);
    defer engine.freeValue(total);
    const numeric_total = try v.number(engine, total);
    if (numeric_total < content) try distribute(engine, sizes, entries, content - numeric_total, true, context) else if (numeric_total > content) try distribute(engine, sizes, entries, numeric_total - content, false, context);
    return sizes;
}
fn invokeVoid(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const result = try js.invoke(engine, object, name, args);
    engine.freeValue(result);
}
fn superCall(engine: *js.Engine, home: c.JSValue, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const prototype = try engine.checked(c.JS_GetPrototype(engine.context, home));
    defer engine.freeValue(prototype);
    const function = try js.get(engine, prototype, name);
    defer engine.freeValue(function);
    const result = try js.call(engine, function, object, args);
    engine.freeValue(result);
}
fn spreadPush(engine: *js.Engine, target: c.JSValue, iterable: c.JSValue, symbol: c.JSValue) !void {
    const function = try js.get(engine, target, "push");
    defer engine.freeValue(function);
    var arguments: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (arguments.items) |value| engine.freeValue(value);
        arguments.deinit(engine.gpa);
    }
    var iterator = try js.Iterator.init(engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        var transferred = false;
        errdefer if (!transferred) engine.freeValue(value);
        if (arguments.items.len >= 4096) {
            _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Invalid array length"));
            unreachable;
        }
        try arguments.append(engine.gpa, value);
        transferred = true;
    }
    const result = try js.call(engine, function, target, arguments.items);
    engine.freeValue(result);
}
fn render(engine: *js.Engine, object: c.JSValue, width: c.JSValue, horizontal: bool, data: [*c]c.JSValue) !c.JSValue {
    if (render_depth >= 64) {
        _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
        unreachable;
    }
    render_depth += 1;
    defer render_depth -= 1;
    const safe_width = v.numeric(engine, v.maximum(1, try v.number(engine, width)));
    const viewport = try js.object(engine);
    defer engine.freeValue(viewport);
    try defineContext(engine, viewport, "width", safe_width);
    try js.define(engine, viewport, "height", v.numeric(engine, maximum_safe_integer));
    const context = try js.object(engine);
    defer engine.freeValue(context);
    try defineContext(engine, context, "viewport", viewport);
    try defineContext(engine, context, "safeWidth", safe_width);
    try defineContext(engine, context, "primitiveSymbol", data[4]);
    try defineContext(engine, context, "iteratorSymbol", data[2]);
    const raw_entries = try js.get(engine, object, "entries");
    defer engine.freeValue(raw_entries);
    const visible = try callback(engine, .visible, context);
    defer engine.freeValue(visible);
    const entries = try js.invoke(engine, raw_entries, "filter", &.{visible});
    defer engine.freeValue(entries);
    if (horizontal) {
        const length = try js.get(engine, entries, "length");
        defer engine.freeValue(length);
        if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) return js.array(engine);
    }
    const first = try map(engine, entries, if (horizontal) .intrinsicH else .renderV, context);
    defer engine.freeValue(first);
    const intrinsic = if (horizontal) c.JS_DupValue(engine.context, first) else try map(engine, first, .height, context);
    defer engine.freeValue(intrinsic);
    const gap = try js.get(engine, object, "gap");
    defer engine.freeValue(gap);
    const sizes = try allocate(engine, entries, intrinsic, if (horizontal) safe_width else c.pi_js_undefined(), gap, context);
    defer engine.freeValue(sizes);
    try defineContext(engine, context, "sizes", sizes);
    const rendered = if (horizontal) try map(engine, entries, .renderH, context) else c.JS_DupValue(engine.context, first);
    defer engine.freeValue(rendered);
    if (!horizontal) {
        const result = try js.array(engine);
        errdefer engine.freeValue(result);
        const empty = try v.text(engine, "");
        defer engine.freeValue(empty);
        var index: f64 = 0;
        while (index < try v.numberField(engine, entries, "length")) : (index += 1) {
            if (index > 0) {
                var padding: f64 = 0;
                while (padding < try v.numberField(engine, object, "gap")) : (padding += 1) {
                    if (padding >= 4096) {
                        _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Invalid array length"));
                        unreachable;
                    }
                    try js.push(engine, result, empty);
                }
            }
            const lines = try js.getKey(engine, rendered, v.numeric(engine, index));
            defer engine.freeValue(lines);
            const slicer = try js.get(engine, lines, "slice");
            defer engine.freeValue(slicer);
            const size = try js.getKey(engine, sizes, v.numeric(engine, index));
            defer engine.freeValue(size);
            const child_lines = try js.call(engine, slicer, lines, &.{ c.JS_NewInt32(engine.context, 0), size });
            defer engine.freeValue(child_lines);
            try spreadPush(engine, result, child_lines, data[2]);
            var padding = try v.numberField(engine, child_lines, "length");
            while (padding < blk: {
                const current = try js.getKey(engine, sizes, v.numeric(engine, index));
                defer engine.freeValue(current);
                break :blk try v.number(engine, current);
            }) : (padding += 1) {
                if (padding >= 4096) {
                    _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Invalid array length"));
                    unreachable;
                }
                try js.push(engine, result, empty);
            }
        }
        return result;
    }
    const height = try reduce(engine, rendered, .maxHeight, context);
    defer engine.freeValue(height);
    const array = try js.global(engine, "Array");
    defer engine.freeValue(array);
    const from = try js.get(engine, array, "from");
    defer engine.freeValue(from);
    const length_record = try js.object(engine);
    defer engine.freeValue(length_record);
    try defineContext(engine, length_record, "length", height);
    const empty = try callback(engine, .empty, context);
    defer engine.freeValue(empty);
    const result = try js.call(engine, from, array, &.{ length_record, empty });
    errdefer engine.freeValue(result);
    var x = c.JS_NewInt32(engine.context, 0);
    defer engine.freeValue(x);
    var index: f64 = 0;
    while (index < try v.numberField(engine, rendered, "length")) : (index += 1) {
        const lines = try js.getKey(engine, rendered, v.numeric(engine, index));
        defer engine.freeValue(lines);
        const child_width = try js.getKey(engine, sizes, v.numeric(engine, index));
        defer engine.freeValue(child_width);
        var offset: f64 = 0;
        const alignment = try js.get(engine, object, "align");
        defer engine.freeValue(alignment);
        if (try equalText(engine, alignment, "center")) offset = @floor((try v.number(engine, height) - try v.numberField(engine, lines, "length")) / 2) else {
            const current_align = try js.get(engine, object, "align");
            defer engine.freeValue(current_align);
            if (try equalText(engine, current_align, "end")) offset = try v.number(engine, height) - try v.numberField(engine, lines, "length");
        }
        var row: f64 = 0;
        while (row < try v.numberField(engine, lines, "length")) : (row += 1) {
            const target = row + offset;
            if (target < 0 or target >= try v.numberField(engine, result, "length")) continue;
            const function = try js.get(engine, data[3], "compositeTuiLine");
            defer engine.freeValue(function);
            const base = try js.getKey(engine, result, v.numeric(engine, target));
            defer engine.freeValue(base);
            const overlay = try js.getKey(engine, lines, v.numeric(engine, row));
            defer engine.freeValue(overlay);
            const composed = try js.call(engine, function, c.pi_js_undefined(), &.{ base, overlay, x, child_width, safe_width });
            defer engine.freeValue(composed);
            try js.setKey(engine, result, v.numeric(engine, target), composed);
        }
        const current_gap = try js.get(engine, object, "gap");
        defer engine.freeValue(current_gap);
        const increment = try arithmetic.add(engine, child_width, current_gap, data[4]);
        defer engine.freeValue(increment);
        const next = try arithmetic.add(engine, x, increment, data[4]);
        engine.freeValue(x);
        x = next;
    }
    return result;
}
fn operation(engine: *js.Engine, object: c.JSValue, method: Method, args: []const c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (method) {
        .addChild => {
            const supplied = v.arg(args, 1);
            const options = if (c.JS_IsUndefined(supplied)) try js.object(engine) else c.JS_DupValue(engine.context, supplied);
            defer engine.freeValue(options);
            try superCall(engine, data[0], object, "addChild", &.{first});
            const entries = try js.get(engine, object, "entries");
            defer engine.freeValue(entries);
            const push = try js.get(engine, entries, "push");
            defer engine.freeValue(push);
            const entry = try js.object(engine);
            defer engine.freeValue(entry);
            try defineContext(engine, entry, "component", first);
            inline for (.{ "basis", "grow", "shrink", "minSize", "maxSize", "visible" }) |name| {
                const tested = try js.get(engine, options, name);
                defer engine.freeValue(tested);
                if (!c.JS_IsUndefined(tested)) {
                    const value = try js.get(engine, options, name);
                    defer engine.freeValue(value);
                    if (comptime std.mem.eql(u8, name, "basis") or std.mem.eql(u8, name, "visible")) try defineContext(engine, entry, name, value) else try js.define(engine, entry, name, v.numeric(engine, try normalize(engine, value, if (comptime std.mem.eql(u8, name, "shrink")) 1 else if (comptime std.mem.eql(u8, name, "maxSize")) maximum_safe_integer else 0)));
                }
            }
            const result = try js.call(engine, push, entries, &.{entry});
            engine.freeValue(result);
        },
        .removeChild => {
            try superCall(engine, data[0], object, "removeChild", &.{first});
            const entries = try js.get(engine, object, "entries");
            defer engine.freeValue(entries);
            const context = try js.object(engine);
            defer engine.freeValue(context);
            try defineContext(engine, context, "component", first);
            const predicate = try callback(engine, .findChild, context);
            defer engine.freeValue(predicate);
            const index = try js.invoke(engine, entries, "findIndex", &.{predicate});
            defer engine.freeValue(index);
            if (!c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1))) {
                const current = try js.get(engine, object, "entries");
                defer engine.freeValue(current);
                try invokeVoid(engine, current, "splice", &.{ index, c.JS_NewInt32(engine.context, 1) });
            }
        },
        .clear => {
            try superCall(engine, data[0], object, "clear", &.{});
            const entries = try js.get(engine, object, "entries");
            defer engine.freeValue(entries);
            try v.set(engine, entries, "length", c.JS_NewInt32(engine.context, 0));
        },
        .layout => {
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            inline for (.{ .{ "type", "layoutType" }, .{ "entries", "entries" }, .{ "gap", "gap" }, .{ "align", "align" } }) |field| try js.define(engine, result, field[0], try js.get(engine, object, field[1]));
            return result;
        },
        .renderH, .renderV => return render(engine, object, first, method == .renderH, data),
    }
    return c.pi_js_undefined();
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return operation(engine, object, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, data) catch |err| fail(engine, err);
}
fn constructStack(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const self = try js.get(engine, data[0], "Stack");
    defer engine.freeValue(self);
    const base = try engine.checked(c.JS_GetPrototype(engine.context, self));
    defer engine.freeValue(base);
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, base, target, 0, null));
    errdefer engine.freeValue(object);
    try js.define(engine, object, "entries", try js.array(engine));
    try js.define(engine, object, "gap", c.pi_js_undefined());
    try js.define(engine, object, "align", c.pi_js_undefined());
    const supplied_children = v.arg(args, 0);
    const children = if (c.JS_IsUndefined(supplied_children)) try js.array(engine) else c.JS_DupValue(engine.context, supplied_children);
    defer engine.freeValue(children);
    const supplied_options = v.arg(args, 1);
    const options = if (c.JS_IsUndefined(supplied_options)) try js.object(engine) else c.JS_DupValue(engine.context, supplied_options);
    defer engine.freeValue(options);
    const gap = try js.get(engine, options, "gap");
    defer engine.freeValue(gap);
    try v.set(engine, object, "gap", v.numeric(engine, try normalize(engine, gap, 0)));
    const raw_align = try js.get(engine, options, "align");
    defer engine.freeValue(raw_align);
    try v.set(engine, object, "align", if (c.JS_IsNull(raw_align) or c.JS_IsUndefined(raw_align)) try v.text(engine, "stretch") else c.JS_DupValue(engine.context, raw_align));
    var iterator = try js.Iterator.init(engine, children, data[1]);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const render_key = try v.text(engine, "render");
    defer engine.freeValue(render_key);
    while (try iterator.next()) |child| {
        defer engine.freeValue(child);
        const entry = !(try js.hasKey(engine, child, render_key));
        const function = try js.get(engine, object, "addChild");
        defer engine.freeValue(function);
        const component = if (entry) try js.get(engine, child, "component") else c.JS_DupValue(engine.context, child);
        defer engine.freeValue(component);
        const result = try js.call(engine, function, object, if (entry) &.{ component, child } else &.{component});
        engine.freeValue(result);
    }
    return object;
}
fn constructDerived(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const horizontal = v.truthy(engine, data[1]);
    const self = try js.get(engine, data[0], if (horizontal) "HStack" else "VStack");
    defer engine.freeValue(self);
    const base = try engine.checked(c.JS_GetPrototype(engine.context, self));
    defer engine.freeValue(base);
    const supplied_children = v.arg(args, 0);
    const children = if (c.JS_IsUndefined(supplied_children)) try js.array(engine) else c.JS_DupValue(engine.context, supplied_children);
    defer engine.freeValue(children);
    const supplied_options = v.arg(args, 1);
    const options = if (c.JS_IsUndefined(supplied_options)) try js.object(engine) else c.JS_DupValue(engine.context, supplied_options);
    defer engine.freeValue(options);
    var arguments = [_]c.JSValue{ children, options };
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, base, target, arguments.len, &arguments));
    errdefer engine.freeValue(object);
    try js.define(engine, object, "layoutType", try v.text(engine, if (horizontal) "hstack" else "vstack"));
    return object;
}
fn placeholder(engine: *js.Engine, prototype: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const container = try js.get(engine, exports, "Container");
    defer engine.freeValue(container);
    const container_prototype = try js.get(engine, container, "prototype");
    defer engine.freeValue(container_prototype);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const key = try v.text(engine, "@earendil-works/pi-tui/layout-node");
    defer engine.freeValue(key);
    const layout_symbol = try js.invoke(engine, symbol, "for", &.{key});
    defer engine.freeValue(layout_symbol);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    const primitive_symbol = try js.get(engine, symbol, "toPrimitive");
    defer engine.freeValue(primitive_symbol);
    const record = try js.object(engine);
    defer engine.freeValue(record);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, container_prototype));
    defer engine.freeValue(prototype);
    try placeholder(engine, prototype);
    var data = [_]c.JSValue{ prototype, layout_symbol, iterator, exports, primitive_symbol };
    inline for (.{ .{ "addChild", Method.addChild, 1 }, .{ "removeChild", Method.removeChild, 1 }, .{ "clear", Method.clear, 0 } }) |method| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, method[0], method[2], @intFromEnum(method[1]), data.len, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, method[0], function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const atom = try js.atom(engine, layout_symbol);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, prototype, atom, try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, "[@earendil-works/pi-tui/layout-node]", 0, @intFromEnum(Method.layout), data.len, &data)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const base = try @import("native_class.zig").constructor(engine, "Stack", 0, prototype, constructStack, &.{ record, iterator });
    defer engine.freeValue(base);
    if (c.JS_SetPrototype(engine.context, base, container) < 0) return js.capture(engine);
    try defineContext(engine, record, "Stack", base);
    inline for (.{ .{ "HStack", true, Method.renderH }, .{ "VStack", false, Method.renderV } }) |kind| {
        const derived_prototype = try engine.checked(c.JS_NewObjectProto(engine.context, prototype));
        defer engine.freeValue(derived_prototype);
        try placeholder(engine, derived_prototype);
        const renderer = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, "render", 1, @intFromEnum(kind[2]), data.len, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, derived_prototype, "render", renderer, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        const constructor = try @import("native_class.zig").constructor(engine, kind[0], 0, derived_prototype, constructDerived, &.{ record, c.pi_js_bool(engine.context, @intFromBool(kind[1])) });
        defer engine.freeValue(constructor);
        if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
        try defineContext(engine, record, kind[0], constructor);
        try defineContext(engine, exports, kind[0], constructor);
    }
}

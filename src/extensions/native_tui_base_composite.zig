//! Source overlay pre-render, bounds publication and viewport compositing.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Callback = enum(c_int) { visible, order, layout };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase composite: %s", @as([*:0]const u8, @errorName(err)));
}
fn callback(engine: *js.Engine, kind: Callback, screen: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{screen};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callbackCall, "", if (kind == .order) 2 else 1, @intFromEnum(kind), 1, &data));
}
fn callbackCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return callbackBody(engine, @enumFromInt(magic), data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn callbackBody(engine: *js.Engine, kind: Callback, screen: c.JSValue, first: c.JSValue, second: c.JSValue) !c.JSValue {
    if (kind == .visible) return js.invoke(engine, screen, "isOverlayVisible", &.{first});
    if (kind == .order) return v.numeric(engine, try v.numberField(engine, first, "focusOrder") - try v.numberField(engine, second, "focusOrder"));
    const entry = try js.get(engine, first, "entry");
    defer engine.freeValue(entry);
    const row = try js.get(engine, first, "row");
    defer engine.freeValue(row);
    const col = try js.get(engine, first, "col");
    defer engine.freeValue(col);
    const width = try js.get(engine, first, "w");
    defer engine.freeValue(width);
    const lines = try js.get(engine, first, "overlayLines");
    defer engine.freeValue(lines);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "entry", c.JS_DupValue(engine.context, entry));
    try js.define(engine, result, "row", c.JS_DupValue(engine.context, row));
    try js.define(engine, result, "col", c.JS_DupValue(engine.context, col));
    try js.define(engine, result, "width", c.JS_DupValue(engine.context, width));
    try js.define(engine, result, "height", try js.get(engine, lines, "length"));
    return result;
}
fn iterate(engine: *js.Engine, bindings: c.JSValue, value: c.JSValue) !js.Iterator {
    const symbol = try js.get(engine, bindings, "iteratorSymbol");
    defer engine.freeValue(symbol);
    return js.Iterator.init(engine, value, symbol);
}
fn copiedLines(engine: *js.Engine, bindings: c.JSValue, lines: c.JSValue) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    var iterator = try iterate(engine, bindings, lines);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |line| {
        if (c.JS_DefinePropertyValueUint32(engine.context, result, index, line, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        index += 1;
    }
    return result;
}
fn add(engine: *js.Engine, bindings: c.JSValue, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const symbol = try js.get(engine, bindings, "primitiveSymbol");
    defer engine.freeValue(symbol);
    return @import("native_tui_value_arithmetic.zig").add(engine, left, right, symbol);
}
fn math(engine: *js.Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    return js.invoke(engine, object, name, args);
}
pub fn composite(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const lines = v.arg(args, 0);
    const term_width = v.arg(args, 1);
    const term_height = v.arg(args, 2);
    const first_stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(first_stack);
    const stack_length = try js.get(engine, first_stack, "length");
    defer engine.freeValue(stack_length);
    if (c.JS_IsStrictEqual(engine.context, stack_length, c.JS_NewInt32(engine.context, 0))) {
        try v.set(engine, screen, "renderedOverlayLayouts", try js.array(engine));
        return c.JS_DupValue(engine.context, lines);
    }
    const result = try copiedLines(engine, bindings, lines);
    errdefer engine.freeValue(result);
    const clear_stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(clear_stack);
    {
        var iterator = try iterate(engine, bindings, clear_stack);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer engine.freeValue(entry);
            try v.set(engine, entry, "bounds", c.pi_js_undefined());
        }
    }
    const rendered = try js.array(engine);
    defer engine.freeValue(rendered);
    var minimum_lines = try js.get(engine, result, "length");
    defer engine.freeValue(minimum_lines);
    const stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(stack);
    const filter = try js.get(engine, stack, "filter");
    defer engine.freeValue(filter);
    const filter_callback = try callback(engine, .visible, screen);
    defer engine.freeValue(filter_callback);
    const visible = try js.call(engine, filter, stack, &.{filter_callback});
    defer engine.freeValue(visible);
    const sort = try js.get(engine, visible, "sort");
    defer engine.freeValue(sort);
    const comparator = try callback(engine, .order, screen);
    defer engine.freeValue(comparator);
    const sorted = try js.call(engine, sort, visible, &.{comparator});
    engine.freeValue(sorted);
    {
        var iterator = try iterate(engine, bindings, visible);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer engine.freeValue(entry);
            const component = try js.get(engine, entry, "component");
            defer engine.freeValue(component);
            const options = try js.get(engine, entry, "options");
            defer engine.freeValue(options);
            const initial_layout = try js.invoke(engine, screen, "resolveOverlayLayout", &.{ options, c.JS_NewInt32(engine.context, 0), term_width, term_height });
            defer engine.freeValue(initial_layout);
            const width = try js.get(engine, initial_layout, "width");
            defer engine.freeValue(width);
            const maximum_height = try js.get(engine, initial_layout, "maxHeight");
            defer engine.freeValue(maximum_height);
            const resolve_cursors = try js.get(engine, screen, "resolveFakeCursors");
            defer engine.freeValue(resolve_cursors);
            const component_lines = try js.invoke(engine, component, "render", &.{width});
            defer engine.freeValue(component_lines);
            var overlay_lines = try js.call(engine, resolve_cursors, screen, &.{component_lines});
            defer engine.freeValue(overlay_lines);
            if (!c.JS_IsUndefined(maximum_height) and try v.numberField(engine, overlay_lines, "length") > try v.number(engine, maximum_height)) {
                const limited = try js.invoke(engine, overlay_lines, "slice", &.{ c.JS_NewInt32(engine.context, 0), maximum_height });
                engine.freeValue(overlay_lines);
                overlay_lines = limited;
            }
            const resolve_layout = try js.get(engine, screen, "resolveOverlayLayout");
            defer engine.freeValue(resolve_layout);
            const height = try js.get(engine, overlay_lines, "length");
            defer engine.freeValue(height);
            const final_layout = try js.call(engine, resolve_layout, screen, &.{ options, height, term_width, term_height });
            defer engine.freeValue(final_layout);
            const row = try js.get(engine, final_layout, "row");
            defer engine.freeValue(row);
            const col = try js.get(engine, final_layout, "col");
            defer engine.freeValue(col);
            const bounds = blk: {
                const object = try js.object(engine);
                errdefer engine.freeValue(object);
                try js.define(engine, object, "row", c.JS_DupValue(engine.context, row));
                try js.define(engine, object, "col", c.JS_DupValue(engine.context, col));
                try js.define(engine, object, "width", c.JS_DupValue(engine.context, width));
                try js.define(engine, object, "height", try js.get(engine, overlay_lines, "length"));
                break :blk object;
            };
            try v.set(engine, entry, "bounds", bounds);
            const push = try js.get(engine, rendered, "push");
            defer engine.freeValue(push);
            const frame = try js.object(engine);
            defer engine.freeValue(frame);
            try js.define(engine, frame, "entry", c.JS_DupValue(engine.context, entry));
            try js.define(engine, frame, "overlayLines", c.JS_DupValue(engine.context, overlay_lines));
            try js.define(engine, frame, "row", c.JS_DupValue(engine.context, row));
            try js.define(engine, frame, "col", c.JS_DupValue(engine.context, col));
            try js.define(engine, frame, "w", c.JS_DupValue(engine.context, width));
            const pushed = try js.call(engine, push, rendered, &.{frame});
            engine.freeValue(pushed);
            const math_object = try js.global(engine, "Math");
            defer engine.freeValue(math_object);
            const maximum = try js.get(engine, math_object, "max");
            defer engine.freeValue(maximum);
            const current_height = try js.get(engine, overlay_lines, "length");
            defer engine.freeValue(current_height);
            const required = try add(engine, bindings, row, current_height);
            defer engine.freeValue(required);
            const next_minimum = try js.call(engine, maximum, math_object, &.{ minimum_lines, required });
            engine.freeValue(minimum_lines);
            minimum_lines = next_minimum;
        }
    }
    const map = try js.get(engine, rendered, "map");
    defer engine.freeValue(map);
    const map_callback = try callback(engine, .layout, screen);
    defer engine.freeValue(map_callback);
    try v.set(engine, screen, "renderedOverlayLayouts", try js.call(engine, map, rendered, &.{map_callback}));
    const math_object = try js.global(engine, "Math");
    defer engine.freeValue(math_object);
    const maximum = try js.get(engine, math_object, "max");
    defer engine.freeValue(maximum);
    const length = try js.get(engine, result, "length");
    defer engine.freeValue(length);
    const working_height = try js.call(engine, maximum, math_object, &.{ length, term_height, minimum_lines });
    defer engine.freeValue(working_height);
    while (try v.numberField(engine, result, "length") < try v.number(engine, working_height)) {
        const push = try js.get(engine, result, "push");
        defer engine.freeValue(push);
        const empty = try v.text(engine, "");
        defer engine.freeValue(empty);
        const pushed = try js.call(engine, push, result, &.{empty});
        engine.freeValue(pushed);
    }
    const viewport_start = try math(engine, "max", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try v.number(engine, working_height) - try v.number(engine, term_height)) });
    defer engine.freeValue(viewport_start);
    try renderFrames(engine, screen, bindings, rendered, result, viewport_start, term_width);
    return result;
}
fn renderFrames(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, rendered: c.JSValue, result: c.JSValue, viewport_start: c.JSValue, term_width: c.JSValue) !void {
    var iterator = try iterate(engine, bindings, rendered);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |frame| {
        defer engine.freeValue(frame);
        const lines = try js.get(engine, frame, "overlayLines");
        defer engine.freeValue(lines);
        const row = try js.get(engine, frame, "row");
        defer engine.freeValue(row);
        const col = try js.get(engine, frame, "col");
        defer engine.freeValue(col);
        const width = try js.get(engine, frame, "w");
        defer engine.freeValue(width);
        var index: f64 = 0;
        while (index < try v.numberField(engine, lines, "length")) : (index += 1) {
            const base = try add(engine, bindings, viewport_start, row);
            defer engine.freeValue(base);
            const destination = try add(engine, bindings, base, v.numeric(engine, index));
            defer engine.freeValue(destination);
            if (!(try v.number(engine, destination) >= 0) or !(try v.number(engine, destination) < try v.numberField(engine, result, "length"))) continue;
            const visible_width = try js.get(engine, bindings, "visibleWidth");
            defer engine.freeValue(visible_width);
            const line = try js.getKey(engine, lines, v.numeric(engine, index));
            defer engine.freeValue(line);
            const length = try js.call(engine, visible_width, c.pi_js_undefined(), &.{line});
            defer engine.freeValue(length);
            const overlay_line = blk: {
                if (!(try v.number(engine, length) > try v.number(engine, width))) break :blk try js.getKey(engine, lines, v.numeric(engine, index));
                const slice = try js.get(engine, bindings, "sliceByColumn");
                defer engine.freeValue(slice);
                const current = try js.getKey(engine, lines, v.numeric(engine, index));
                defer engine.freeValue(current);
                break :blk try js.call(engine, slice, c.pi_js_undefined(), &.{ current, c.JS_NewInt32(engine.context, 0), width, c.pi_js_bool(engine.context, 1) });
            };
            defer engine.freeValue(overlay_line);
            const composite_line = try js.get(engine, screen, "compositeLineAt");
            defer engine.freeValue(composite_line);
            const current_base = try js.getKey(engine, result, destination);
            defer engine.freeValue(current_base);
            const composed = try js.call(engine, composite_line, screen, &.{ current_base, overlay_line, col, width, term_width });
            defer engine.freeValue(composed);
            try js.setKey(engine, result, destination, composed);
        }
    }
}

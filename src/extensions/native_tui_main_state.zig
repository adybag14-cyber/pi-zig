//! Source regular-screen field initialization and render-state/cursor methods.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum { captureRenderState, restoreRenderState, resetRenderState, beforeTerminalStop, positionHardwareCursor };
pub fn initialize(engine: *js.Engine, object: c.JSValue) !void {
    try js.define(engine, object, "mode", try v.text(engine, "regular"));
    try js.define(engine, object, "previousLines", try js.array(engine));
    try js.define(engine, object, "previousKittyImageIds", try js.builtin(engine, "Set", &.{}));
    inline for (.{ "previousWidth", "previousHeight", "cursorRow", "hardwareCursorRow", "maxLinesRendered", "previousViewportTop" }) |field| try js.define(engine, object, field, c.JS_NewInt32(engine.context, 0));
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiMainScreen state: %s", @as([*:0]const u8, @errorName(err)));
}
fn withoutImage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return withoutImageBody(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| fail(engine, err);
}
fn withoutImageBody(engine: *js.Engine, line: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const image_function = try js.get(engine, bindings, "isImageLine");
    defer engine.freeValue(image_function);
    const image = try js.call(engine, image_function, c.pi_js_undefined(), &.{line});
    defer engine.freeValue(image);
    return if (v.truthy(engine, image)) try v.text(engine, "") else c.JS_DupValue(engine.context, line);
}
fn write(engine: *js.Engine, screen: c.JSValue, data: c.JSValue) !void {
    const terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(terminal);
    try v.invokeVoid(engine, terminal, "write", &.{data});
}
fn writeText(engine: *js.Engine, screen: c.JSValue, text: []const u8) !void {
    const terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(terminal);
    const function = try js.get(engine, terminal, "write");
    defer engine.freeValue(function);
    const value = try v.text(engine, text);
    defer engine.freeValue(value);
    const written = try js.call(engine, function, terminal, &.{value});
    engine.freeValue(written);
}
fn terminalCall(engine: *js.Engine, screen: c.JSValue, name: [*:0]const u8) !void {
    const terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(terminal);
    try v.invokeVoid(engine, terminal, name, &.{});
}
fn sequence(engine: *js.Engine, count: f64, suffix: []const u8) !c.JSValue {
    const start = try v.text(engine, "\x1b[");
    defer engine.freeValue(start);
    const end = try v.text(engine, suffix);
    defer engine.freeValue(end);
    return v.concat(engine, &.{ start, v.numeric(engine, count), end });
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .captureRenderState => {
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            const previous = try js.get(engine, screen, "previousLines");
            defer engine.freeValue(previous);
            const symbol = try js.get(engine, bindings, "iteratorSymbol");
            defer engine.freeValue(symbol);
            var iterator = try js.Iterator.init(engine, previous, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            const lines = blk: {
                const array = try js.array(engine);
                errdefer engine.freeValue(array);
                var index: u32 = 0;
                while (try iterator.next()) |line| {
                    if (c.JS_DefinePropertyValueUint32(engine.context, array, index, line, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
                    index += 1;
                }
                break :blk array;
            };
            try js.define(engine, result, "previousLines", lines);
            inline for (.{ "previousWidth", "previousHeight", "cursorRow", "hardwareCursorRow", "maxLinesRendered", "previousViewportTop" }) |field| try js.define(engine, result, field, try js.get(engine, screen, field));
            return result;
        },
        .restoreRenderState => {
            const state = v.arg(args, 0);
            const lines = try js.get(engine, state, "previousLines");
            defer engine.freeValue(lines);
            const map = try js.get(engine, lines, "map");
            defer engine.freeValue(map);
            var data = [_]c.JSValue{bindings};
            const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, withoutImage, "", 1, 0, 1, &data));
            defer engine.freeValue(callback);
            try v.set(engine, screen, "previousLines", try js.call(engine, map, lines, &.{callback}));
            try v.set(engine, screen, "previousKittyImageIds", try js.builtin(engine, "Set", &.{}));
            inline for (.{ "previousWidth", "previousHeight", "cursorRow", "hardwareCursorRow", "maxLinesRendered", "previousViewportTop" }) |field| try v.set(engine, screen, field, try js.get(engine, state, field));
        },
        .resetRenderState => {
            try v.set(engine, screen, "previousLines", try js.array(engine));
            try v.set(engine, screen, "previousWidth", c.JS_NewInt32(engine.context, -1));
            try v.set(engine, screen, "previousHeight", c.JS_NewInt32(engine.context, -1));
            inline for (.{ "cursorRow", "hardwareCursorRow", "maxLinesRendered", "previousViewportTop" }) |field| try v.set(engine, screen, field, c.JS_NewInt32(engine.context, 0));
        },
        .beforeTerminalStop => {
            const preserve = try js.get(engine, v.arg(args, 0), "preserveScreen");
            defer engine.freeValue(preserve);
            if (v.truthy(engine, preserve)) return c.pi_js_undefined();
            const lines = try js.get(engine, screen, "previousLines");
            defer engine.freeValue(lines);
            const length = try js.get(engine, lines, "length");
            defer engine.freeValue(length);
            if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
            try writeText(engine, screen, " ");
            const current_lines = try js.get(engine, screen, "previousLines");
            defer engine.freeValue(current_lines);
            const target = try js.get(engine, current_lines, "length");
            defer engine.freeValue(target);
            const hardware = try js.get(engine, screen, "hardwareCursorRow");
            defer engine.freeValue(hardware);
            const delta = try v.number(engine, target) - try v.number(engine, hardware);
            if (delta > 0 or delta < 0) {
                const data = try sequence(engine, if (delta > 0) delta else -delta, if (delta > 0) "B" else "A");
                defer engine.freeValue(data);
                if (delta > 0 or delta < 0) try write(engine, screen, data);
            }
            try writeText(engine, screen, "\r\n");
        },
        .positionHardwareCursor => return position(engine, screen, args),
    }
    return c.pi_js_undefined();
}
fn position(engine: *js.Engine, screen: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const cursor = v.arg(args, 0);
    const total = v.arg(args, 1);
    if (!v.truthy(engine, cursor) or try v.number(engine, total) <= 0) {
        try terminalCall(engine, screen, "hideCursor");
        return c.pi_js_undefined();
    }
    const outer_math = try js.global(engine, "Math");
    defer engine.freeValue(outer_math);
    const maximum = try js.get(engine, outer_math, "max");
    defer engine.freeValue(maximum);
    const inner_math = try js.global(engine, "Math");
    defer engine.freeValue(inner_math);
    const minimum = try js.get(engine, inner_math, "min");
    defer engine.freeValue(minimum);
    const row = try js.get(engine, cursor, "row");
    defer engine.freeValue(row);
    const inner = try js.call(engine, minimum, inner_math, &.{ row, v.numeric(engine, try v.number(engine, total) - 1) });
    defer engine.freeValue(inner);
    const target_row = try js.call(engine, maximum, outer_math, &.{ c.JS_NewInt32(engine.context, 0), inner });
    defer engine.freeValue(target_row);
    const col_math = try js.global(engine, "Math");
    defer engine.freeValue(col_math);
    const col_maximum = try js.get(engine, col_math, "max");
    defer engine.freeValue(col_maximum);
    const col = try js.get(engine, cursor, "col");
    defer engine.freeValue(col);
    const target_col = try js.call(engine, col_maximum, col_math, &.{ c.JS_NewInt32(engine.context, 0), col });
    defer engine.freeValue(target_col);
    const hardware = try js.get(engine, screen, "hardwareCursorRow");
    defer engine.freeValue(hardware);
    const delta = try v.number(engine, target_row) - try v.number(engine, hardware);
    const movement = if (delta > 0 or delta < 0) try sequence(engine, if (delta > 0) delta else -delta, if (delta > 0) "B" else "A") else try v.text(engine, "");
    defer engine.freeValue(movement);
    const absolute = try sequence(engine, try v.number(engine, target_col) + 1, "G");
    defer engine.freeValue(absolute);
    const output = try v.concat(engine, &.{ movement, absolute });
    defer engine.freeValue(output);
    if (v.truthy(engine, output)) try write(engine, screen, output);
    try v.set(engine, screen, "hardwareCursorRow", c.JS_DupValue(engine.context, target_row));
    const hardware_cursor = try js.invoke(engine, screen, "getShowHardwareCursor", &.{});
    defer engine.freeValue(hardware_cursor);
    try terminalCall(engine, screen, if (v.truthy(engine, hardware_cursor)) "showCursor" else "hideCursor");
    return c.pi_js_undefined();
}

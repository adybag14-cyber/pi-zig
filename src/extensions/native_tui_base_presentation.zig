//! Source TuiBase presentation helpers, over live fields and imported functions.
//! Screen installation remains separate until all method bodies are complete.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum { hasOverlayEntries, fullRedraws, getShowHardwareCursor, setShowHardwareCursor, getClearOnShrink, setClearOnShrink, hideTerminalCursor, queryCellSize, invalidate, resolveAnchorRow, resolveAnchorCol, compositeLineAt, extractCursorPosition, resolveFakeCursors, applyLineResets };
fn equalText(engine: *js.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn imported(engine: *js.Engine, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try js.get(engine, bindings, name);
    defer engine.freeValue(function);
    return js.call(engine, function, c.pi_js_undefined(), args);
}
fn terminalCall(engine: *js.Engine, screen: c.JSValue, method: [*:0]const u8, args: []const c.JSValue) !void {
    const terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(terminal);
    try v.invokeVoid(engine, terminal, method, args);
}
fn add(engine: *js.Engine, bindings: c.JSValue, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const symbol = try js.get(engine, bindings, "primitiveSymbol");
    defer engine.freeValue(symbol);
    return @import("native_tui_value_arithmetic.zig").add(engine, left, right, symbol);
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .fullRedraws => return js.get(engine, screen, "fullRedrawCount"),
        .getShowHardwareCursor => return js.get(engine, screen, "showHardwareCursor"),
        .getClearOnShrink => return js.get(engine, screen, "clearOnShrink"),
        .hasOverlayEntries => {
            const stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(stack);
            return c.pi_js_bool(engine.context, @intFromBool(try v.numberField(engine, stack, "length") > 0));
        },
        .setShowHardwareCursor => {
            const enabled = v.arg(args, 0);
            const current = try js.get(engine, screen, "showHardwareCursor");
            defer engine.freeValue(current);
            if (c.JS_IsStrictEqual(engine.context, current, enabled)) return c.pi_js_undefined();
            try v.set(engine, screen, "showHardwareCursor", c.JS_DupValue(engine.context, enabled));
            if (!v.truthy(engine, enabled)) try v.invokeVoid(engine, screen, "hideTerminalCursor", &.{});
            try v.invokeVoid(engine, screen, "requestRender", &.{});
            return c.pi_js_undefined();
        },
        .setClearOnShrink => {
            try v.set(engine, screen, "clearOnShrink", c.JS_DupValue(engine.context, v.arg(args, 0)));
            return c.pi_js_undefined();
        },
        .hideTerminalCursor => {
            const stopped = try js.get(engine, screen, "stopped");
            defer engine.freeValue(stopped);
            if (!v.truthy(engine, stopped)) try terminalCall(engine, screen, "hideCursor", &.{});
            return c.pi_js_undefined();
        },
        .queryCellSize => {
            const capabilities = try imported(engine, bindings, "getCapabilities", &.{});
            defer engine.freeValue(capabilities);
            const images = try js.get(engine, capabilities, "images");
            defer engine.freeValue(images);
            if (v.truthy(engine, images)) {
                const query = try v.text(engine, "\x1b[16t");
                defer engine.freeValue(query);
                try terminalCall(engine, screen, "write", &.{query});
            }
            return c.pi_js_undefined();
        },
        .invalidate => return invalidate(engine, screen, bindings),
        .resolveAnchorRow, .resolveAnchorCol => return anchor(engine, bindings, method == .resolveAnchorRow, args),
        .compositeLineAt => return imported(engine, bindings, "compositeTuiLine", args),
        .extractCursorPosition => return extractCursor(engine, bindings, v.arg(args, 0), v.arg(args, 1)),
        .resolveFakeCursors => {
            var data = [_]c.JSValue{ screen, bindings };
            const mapper = try engine.checked(c.JS_NewCFunctionData2(engine.context, fakeCursorCall, "", 1, 0, 2, &data));
            defer engine.freeValue(mapper);
            return js.invoke(engine, v.arg(args, 0), "map", &.{mapper});
        },
        .applyLineResets => return applyLineResets(engine, bindings, v.arg(args, 0)),
    }
}
fn invalidate(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const symbol = try js.get(engine, bindings, "iteratorSymbol");
    defer engine.freeValue(symbol);
    const roots = try js.invoke(engine, screen, "getMountedRoots", &.{});
    defer engine.freeValue(roots);
    {
        var iterator = try js.Iterator.init(engine, roots, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |root| {
            defer engine.freeValue(root);
            try v.invokeVoid(engine, root, "invalidate", &.{});
        }
    }
    const overlays = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(overlays);
    var iterator = try js.Iterator.init(engine, overlays, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |overlay| {
        defer engine.freeValue(overlay);
        const component = try js.get(engine, overlay, "component");
        defer engine.freeValue(component);
        try v.invokeVoid(engine, component, "invalidate", &.{});
    }
    return c.pi_js_undefined();
}
fn anchor(engine: *js.Engine, bindings: c.JSValue, row: bool, args: []const c.JSValue) !c.JSValue {
    const name = v.arg(args, 0);
    const first = if (row) try equalText(engine, name, "top-left") or try equalText(engine, name, "top-center") or try equalText(engine, name, "top-right") else try equalText(engine, name, "top-left") or try equalText(engine, name, "left-center") or try equalText(engine, name, "bottom-left");
    if (first) return c.JS_DupValue(engine.context, v.arg(args, 3));
    const last = if (row) try equalText(engine, name, "bottom-left") or try equalText(engine, name, "bottom-center") or try equalText(engine, name, "bottom-right") else try equalText(engine, name, "top-right") or try equalText(engine, name, "right-center") or try equalText(engine, name, "bottom-right");
    if (last) {
        const sum = try add(engine, bindings, v.arg(args, 3), v.arg(args, 2));
        defer engine.freeValue(sum);
        return v.numeric(engine, try v.number(engine, sum) - try v.number(engine, v.arg(args, 1)));
    }
    const middle = if (row) try equalText(engine, name, "left-center") or try equalText(engine, name, "center") or try equalText(engine, name, "right-center") else try equalText(engine, name, "top-center") or try equalText(engine, name, "center") or try equalText(engine, name, "bottom-center");
    if (!middle) return c.pi_js_undefined();
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    const floor = try js.get(engine, math, "floor");
    defer engine.freeValue(floor);
    const space = (try v.number(engine, v.arg(args, 2)) - try v.number(engine, v.arg(args, 1))) / 2;
    const offset = try js.call(engine, floor, math, &.{v.numeric(engine, space)});
    defer engine.freeValue(offset);
    return add(engine, bindings, v.arg(args, 3), offset);
}
fn extractCursor(engine: *js.Engine, bindings: c.JSValue, lines: c.JSValue, height: c.JSValue) !c.JSValue {
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    const maximum = try js.get(engine, math, "max");
    defer engine.freeValue(maximum);
    const length = try js.get(engine, lines, "length");
    defer engine.freeValue(length);
    const top = try js.call(engine, maximum, math, &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try v.number(engine, length) - try v.number(engine, height)) });
    defer engine.freeValue(top);
    var row = try v.numberField(engine, lines, "length") - 1;
    const marker = try v.text(engine, @import("../tui/cursor_markers.zig").cursor);
    defer engine.freeValue(marker);
    while (row >= try v.number(engine, top)) : (row -= 1) {
        const line = try js.getKey(engine, lines, v.numeric(engine, row));
        defer engine.freeValue(line);
        const index = try js.invoke(engine, line, "indexOf", &.{marker});
        defer engine.freeValue(index);
        if (c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1))) continue;
        const before = try js.invoke(engine, line, "slice", &.{ c.JS_NewInt32(engine.context, 0), index });
        defer engine.freeValue(before);
        const column = try imported(engine, bindings, "visibleWidth", &.{before});
        defer engine.freeValue(column);
        const left = try js.invoke(engine, line, "slice", &.{ c.JS_NewInt32(engine.context, 0), index });
        defer engine.freeValue(left);
        const slicing = try js.get(engine, line, "slice");
        defer engine.freeValue(slicing);
        const offset = try add(engine, bindings, index, c.JS_NewInt32(engine.context, @import("../tui/cursor_markers.zig").cursor.len));
        defer engine.freeValue(offset);
        const right = try js.call(engine, slicing, line, &.{offset});
        defer engine.freeValue(right);
        const joined = try add(engine, bindings, left, right);
        defer engine.freeValue(joined);
        try js.setKey(engine, lines, v.numeric(engine, row), joined);
        const result = try js.object(engine);
        errdefer engine.freeValue(result);
        try js.define(engine, result, "row", v.numeric(engine, row));
        try js.define(engine, result, "col", c.JS_DupValue(engine.context, column));
        return result;
    }
    return c.pi_js_null();
}
fn fakeCursorCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return fakeCursor(engine, data[0], data[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native TuiBase cursor: %s", @as([*:0]const u8, @errorName(err)));
    };
}
fn fakeCursor(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, line: c.JSValue) !c.JSValue {
    const start = try v.text(engine, @import("../tui/cursor_markers.zig").fake_start);
    defer engine.freeValue(start);
    const includes = try js.invoke(engine, line, "includes", &.{start});
    defer engine.freeValue(includes);
    if (!v.truthy(engine, includes)) return c.JS_DupValue(engine.context, line);
    const hardware = try js.get(engine, screen, "showHardwareCursor");
    defer engine.freeValue(hardware);
    const resolved = if (v.truthy(engine, hardware)) blk: {
        const replacing = try js.get(engine, line, "replace");
        defer engine.freeValue(replacing);
        const expression = try js.get(engine, bindings, "focusedFakeRegex");
        defer engine.freeValue(expression);
        const replacement = try v.text(engine, "$1$2");
        defer engine.freeValue(replacement);
        break :blk try js.call(engine, replacing, line, &.{ expression, replacement });
    } else c.JS_DupValue(engine.context, line);
    defer engine.freeValue(resolved);
    const begin = try v.text(engine, "\x1b[7m");
    defer engine.freeValue(begin);
    const opened = try js.invoke(engine, resolved, "replaceAll", &.{ start, begin });
    defer engine.freeValue(opened);
    const end = try v.text(engine, @import("../tui/cursor_markers.zig").fake_end);
    defer engine.freeValue(end);
    const close = try v.text(engine, "\x1b[27m");
    defer engine.freeValue(close);
    return js.invoke(engine, opened, "replaceAll", &.{ end, close });
}
fn applyLineResets(engine: *js.Engine, bindings: c.JSValue, lines: c.JSValue) !c.JSValue {
    const reset = try v.text(engine, "\x1b[0m\x1b]8;;\x07");
    defer engine.freeValue(reset);
    var index: f64 = 0;
    while (index < try v.numberField(engine, lines, "length")) : (index += 1) {
        const line = try js.getKey(engine, lines, v.numeric(engine, index));
        defer engine.freeValue(line);
        const image = try imported(engine, bindings, "isImageLine", &.{line});
        defer engine.freeValue(image);
        if (v.truthy(engine, image)) continue;
        const normalized = try imported(engine, bindings, "normalizeTerminalOutput", &.{line});
        defer engine.freeValue(normalized);
        const result = try add(engine, bindings, normalized, reset);
        defer engine.freeValue(result);
        try js.setKey(engine, lines, v.numeric(engine, index), result);
    }
    return c.JS_DupValue(engine.context, lines);
}

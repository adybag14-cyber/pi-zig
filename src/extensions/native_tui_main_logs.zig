//! Source regular-screen crash/debug files through the actual Node IO bindings.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Debug = struct { first: f64, viewport_top: f64, height: c.JSValue, line_diff: f64, hardware_row: f64, render_end: f64, final_row: f64, cursor: c.JSValue, written_chars: f64 };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiMainScreen logs: %s", @as([*:0]const u8, @errorName(err)));
}
fn text(engine: *js.Engine, value: []const u8) !c.JSValue {
    return v.text(engine, value);
}
fn label(engine: *js.Engine, name: []const u8, value: c.JSValue) !c.JSValue {
    const prefix = try text(engine, name);
    defer engine.freeValue(prefix);
    return v.concat(engine, &.{ prefix, value });
}
fn literal(engine: *js.Engine, values: []const c.JSValue) !c.JSValue {
    const array = try js.array(engine);
    errdefer engine.freeValue(array);
    for (values, 0..) |value, index| if (c.JS_DefinePropertyValueUint32(engine.context, array, @intCast(index), c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    return array;
}
fn joined(engine: *js.Engine, values: []const c.JSValue) !c.JSValue {
    const array = try literal(engine, values);
    defer engine.freeValue(array);
    const newline = try text(engine, "\n");
    defer engine.freeValue(newline);
    return js.invoke(engine, array, "join", &.{newline});
}
fn width(engine: *js.Engine, bindings: c.JSValue, line: c.JSValue) !c.JSValue {
    const function = try js.get(engine, bindings, "visibleWidth");
    defer engine.freeValue(function);
    return js.call(engine, function, c.pi_js_undefined(), &.{line});
}
fn mapLine(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return mapLineBody(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn mapLineBody(engine: *js.Engine, bindings: c.JSValue, line: c.JSValue, index: c.JSValue) !c.JSValue {
    const opening = try text(engine, "[");
    defer engine.freeValue(opening);
    const middle = try text(engine, "] (w=");
    defer engine.freeValue(middle);
    const measured = try width(engine, bindings, line);
    defer engine.freeValue(measured);
    const ending = try text(engine, ") ");
    defer engine.freeValue(ending);
    return v.concat(engine, &.{ opening, index, middle, measured, ending, line });
}
fn mkdir(engine: *js.Engine, fs: c.JSValue, path: c.JSValue, filename: c.JSValue) !void {
    const function = try js.get(engine, fs, "mkdirSync");
    defer engine.freeValue(function);
    const directory = try js.invoke(engine, path, "dirname", &.{filename});
    defer engine.freeValue(directory);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "recursive", c.pi_js_bool(engine.context, 1));
    const result = try js.call(engine, function, fs, &.{ directory, options });
    engine.freeValue(result);
}
pub fn crash(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, lines: c.JSValue, terminal_width: c.JSValue, index: f64, line: c.JSValue) !void {
    const path = try js.get(engine, bindings, "path");
    defer engine.freeValue(path);
    const join = try js.get(engine, path, "join");
    defer engine.freeValue(join);
    var directory = try js.get(engine, screen, "logDirectory");
    defer engine.freeValue(directory);
    if (c.JS_IsNull(directory) or c.JS_IsUndefined(directory)) {
        const os = try js.get(engine, bindings, "os");
        defer engine.freeValue(os);
        const temporary = try js.invoke(engine, os, "tmpdir", &.{});
        engine.freeValue(directory);
        directory = temporary;
    }
    const filename = try text(engine, "pi-tui-crash.log");
    defer engine.freeValue(filename);
    const crash_path = try js.call(engine, join, path, &.{ directory, filename });
    defer engine.freeValue(crash_path);
    const date = try js.builtin(engine, "Date", &.{});
    defer engine.freeValue(date);
    const iso = try js.invoke(engine, date, "toISOString", &.{});
    defer engine.freeValue(iso);
    const date_line = try label(engine, "Crash at ", iso);
    defer engine.freeValue(date_line);
    const width_line = try label(engine, "Terminal width: ", terminal_width);
    defer engine.freeValue(width_line);
    const line_prefix = try text(engine, "Line ");
    defer engine.freeValue(line_prefix);
    const line_middle = try text(engine, " visible width: ");
    defer engine.freeValue(line_middle);
    const measured = try width(engine, bindings, line);
    defer engine.freeValue(measured);
    const line_description = try v.concat(engine, &.{ line_prefix, v.numeric(engine, index), line_middle, measured });
    defer engine.freeValue(line_description);
    const empty = try text(engine, "");
    defer engine.freeValue(empty);
    const heading = try text(engine, "=== All rendered lines ===");
    defer engine.freeValue(heading);
    const array = try literal(engine, &.{ date_line, width_line, line_description, empty, heading });
    defer engine.freeValue(array);
    const map = try js.get(engine, lines, "map");
    defer engine.freeValue(map);
    var data = [_]c.JSValue{bindings};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, mapLine, "", 2, 0, 1, &data));
    defer engine.freeValue(callback);
    const mapped = try js.call(engine, map, lines, &.{callback});
    defer engine.freeValue(mapped);
    const symbol = try js.get(engine, bindings, "iteratorSymbol");
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, mapped, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var slot: u32 = 5;
    while (try iterator.next()) |entry| {
        if (c.JS_DefinePropertyValueUint32(engine.context, array, slot, entry, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        slot += 1;
    }
    if (c.JS_DefinePropertyValueUint32(engine.context, array, slot, c.JS_DupValue(engine.context, empty), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const newline = try text(engine, "\n");
    defer engine.freeValue(newline);
    const crash_data = try js.invoke(engine, array, "join", &.{newline});
    defer engine.freeValue(crash_data);
    const fs = try js.get(engine, bindings, "fs");
    defer engine.freeValue(fs);
    try mkdir(engine, fs, path, crash_path);
    try v.invokeVoid(engine, fs, "writeFileSync", &.{ crash_path, crash_data });
    try v.invokeVoid(engine, screen, "stop", &.{});
    const error_begin = try text(engine, "Rendered line ");
    defer engine.freeValue(error_begin);
    const error_width = try text(engine, " exceeds terminal width (");
    defer engine.freeValue(error_width);
    const new_measurement = try width(engine, bindings, line);
    defer engine.freeValue(new_measurement);
    const compare = try text(engine, " > ");
    defer engine.freeValue(compare);
    const close = try text(engine, ").");
    defer engine.freeValue(close);
    const error_line = try v.concat(engine, &.{ error_begin, v.numeric(engine, index), error_width, new_measurement, compare, terminal_width, close });
    defer engine.freeValue(error_line);
    const explanation = try text(engine, "This is likely caused by a custom TUI component not truncating its output.");
    defer engine.freeValue(explanation);
    const instruction = try text(engine, "Use visibleWidth() to measure and truncateToWidth() to truncate lines.");
    defer engine.freeValue(instruction);
    const debug_path = try label(engine, "Debug log written to: ", crash_path);
    defer engine.freeValue(debug_path);
    const message = try joined(engine, &.{ error_line, empty, explanation, instruction, empty, debug_path });
    defer engine.freeValue(message);
    const exception = try js.builtin(engine, "Error", &.{message});
    _ = try engine.checked(c.JS_Throw(engine.context, exception));
    unreachable;
}
fn json(engine: *js.Engine, value: c.JSValue, pretty: bool) !c.JSValue {
    const object = try js.global(engine, "JSON");
    defer engine.freeValue(object);
    return js.invoke(engine, object, "stringify", if (pretty) &.{ value, c.pi_js_null(), c.JS_NewInt32(engine.context, 2) } else &.{value});
}
pub fn debug(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, lines: c.JSValue, state: Debug) !void {
    const fs = try js.get(engine, bindings, "fs");
    defer engine.freeValue(fs);
    const mkdir_fn = try js.get(engine, fs, "mkdirSync");
    defer engine.freeValue(mkdir_fn);
    const directory = try text(engine, "/tmp/tui");
    defer engine.freeValue(directory);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "recursive", c.pi_js_bool(engine.context, 1));
    const created = try js.call(engine, mkdir_fn, fs, &.{ directory, options });
    engine.freeValue(created);
    const path = try js.get(engine, bindings, "path");
    defer engine.freeValue(path);
    const join = try js.get(engine, path, "join");
    defer engine.freeValue(join);
    const date = try js.global(engine, "Date");
    defer engine.freeValue(date);
    const now = try js.invoke(engine, date, "now", &.{});
    defer engine.freeValue(now);
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    const random = try js.invoke(engine, math, "random", &.{});
    defer engine.freeValue(random);
    const radix = try js.invoke(engine, random, "toString", &.{c.JS_NewInt32(engine.context, 36)});
    defer engine.freeValue(radix);
    const suffix = try js.invoke(engine, radix, "slice", &.{c.JS_NewInt32(engine.context, 2)});
    defer engine.freeValue(suffix);
    const prefix = try text(engine, "render-");
    defer engine.freeValue(prefix);
    const dash = try text(engine, "-");
    defer engine.freeValue(dash);
    const extension = try text(engine, ".log");
    defer engine.freeValue(extension);
    const filename = try v.concat(engine, &.{ prefix, now, dash, suffix, extension });
    defer engine.freeValue(filename);
    const debug_path = try js.call(engine, join, path, &.{ directory, filename });
    defer engine.freeValue(debug_path);
    const array = try js.array(engine);
    defer engine.freeValue(array);
    var entries: u32 = 0;
    inline for (.{ .{ "firstChanged: ", v.numeric(engine, state.first) }, .{ "viewportTop: ", v.numeric(engine, state.viewport_top) } }) |item| try pushOwned(engine, array, &entries, try label(engine, item[0], item[1]));
    const cursor_row = try js.get(engine, screen, "cursorRow");
    defer engine.freeValue(cursor_row);
    try pushOwned(engine, array, &entries, try label(engine, "cursorRow: ", cursor_row));
    inline for (.{ .{ "height: ", state.height }, .{ "lineDiff: ", v.numeric(engine, state.line_diff) }, .{ "hardwareCursorRow: ", v.numeric(engine, state.hardware_row) }, .{ "renderEnd: ", v.numeric(engine, state.render_end) }, .{ "finalCursorRow: ", v.numeric(engine, state.final_row) } }) |item| try pushOwned(engine, array, &entries, try label(engine, item[0], item[1]));
    const cursor_json = try json(engine, state.cursor, false);
    defer engine.freeValue(cursor_json);
    try pushOwned(engine, array, &entries, try label(engine, "cursorPos: ", cursor_json));
    const length = try js.get(engine, lines, "length");
    defer engine.freeValue(length);
    try pushOwned(engine, array, &entries, try label(engine, "newLines.length: ", length));
    const previous = try js.get(engine, screen, "previousLines");
    defer engine.freeValue(previous);
    const previous_length = try js.get(engine, previous, "length");
    defer engine.freeValue(previous_length);
    try pushOwned(engine, array, &entries, try label(engine, "previousLines.length: ", previous_length));
    try pushOwned(engine, array, &entries, try text(engine, ""));
    try pushOwned(engine, array, &entries, try text(engine, "=== newLines ==="));
    try pushOwned(engine, array, &entries, try json(engine, lines, true));
    try pushOwned(engine, array, &entries, try text(engine, ""));
    try pushOwned(engine, array, &entries, try text(engine, "=== previousLines ==="));
    const current_previous = try js.get(engine, screen, "previousLines");
    defer engine.freeValue(current_previous);
    try pushOwned(engine, array, &entries, try json(engine, current_previous, true));
    try pushOwned(engine, array, &entries, try text(engine, ""));
    try pushOwned(engine, array, &entries, try text(engine, "=== buffer ==="));
    const opening = try text(engine, "[");
    defer engine.freeValue(opening);
    const ending = try text(engine, " chars written in bounded chunks]");
    defer engine.freeValue(ending);
    try pushOwned(engine, array, &entries, try v.concat(engine, &.{ opening, v.numeric(engine, state.written_chars), ending }));
    const newline = try text(engine, "\n");
    defer engine.freeValue(newline);
    const debug_data = try js.invoke(engine, array, "join", &.{newline});
    defer engine.freeValue(debug_data);
    try v.invokeVoid(engine, fs, "writeFileSync", &.{ debug_path, debug_data });
}
fn pushOwned(engine: *js.Engine, array: c.JSValue, index: *u32, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueUint32(engine.context, array, index.*, value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    index.* += 1;
}

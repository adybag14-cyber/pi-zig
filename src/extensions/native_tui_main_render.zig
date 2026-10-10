//! Source regular-screen renderer frame. Differential branches are authored
//! in this isolated continuation before the public class can be installed.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Writer = @import("native_tui_bounded_writer.zig").Writer;
const Frame = struct {
    engine: *js.Engine,
    screen: c.JSValue,
    bindings: c.JSValue,
    width: c.JSValue,
    height: c.JSValue,
    width_changed: bool,
    height_changed: bool,
    previous_viewport_top: f64,
    viewport_top: f64,
    hardware_cursor_row: f64,
    lines: c.JSValue,
    cursor: c.JSValue,
    redraw_directory: c.JSValue,
    fn deinit(self: *Frame) void {
        inline for (.{ self.width, self.height, self.lines, self.cursor, self.redraw_directory }) |value| self.engine.freeValue(value);
    }
    fn lineDiff(self: *Frame, target: f64) f64 {
        return (target - self.viewport_top) - (self.hardware_cursor_row - self.previous_viewport_top);
    }
    fn imported(self: *Frame, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        const function = try js.get(self.engine, self.bindings, name);
        defer self.engine.freeValue(function);
        return js.call(self.engine, function, c.pi_js_undefined(), args);
    }
    fn invoke(self: *Frame, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return js.invoke(self.engine, self.screen, name, args);
    }
    fn math(self: *Frame, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        const object = try js.global(self.engine, "Math");
        defer self.engine.freeValue(object);
        return js.invoke(self.engine, object, name, args);
    }
    fn lineCount(self: *Frame) !f64 {
        return v.numberField(self.engine, self.lines, "length");
    }
    fn previousCount(self: *Frame) !f64 {
        const lines = try js.get(self.engine, self.screen, "previousLines");
        defer self.engine.freeValue(lines);
        return v.numberField(self.engine, lines, "length");
    }
    fn setNumber(self: *Frame, field: [*:0]const u8, number: f64) !void {
        try v.set(self.engine, self.screen, field, v.numeric(self.engine, number));
    }
    fn updatePrevious(self: *Frame) !void {
        const engine = self.engine;
        try v.set(engine, self.screen, "previousLines", c.JS_DupValue(engine.context, self.lines));
        try v.set(engine, self.screen, "previousKittyImageIds", try self.invoke("collectKittyImageIds", &.{self.lines}));
        try v.set(engine, self.screen, "previousWidth", c.JS_DupValue(engine.context, self.width));
        try v.set(engine, self.screen, "previousHeight", c.JS_DupValue(engine.context, self.height));
    }
    fn positionCursor(self: *Frame) !void {
        const position = try js.get(self.engine, self.screen, "positionHardwareCursor");
        defer self.engine.freeValue(position);
        const length = try js.get(self.engine, self.lines, "length");
        defer self.engine.freeValue(length);
        const result = try js.call(self.engine, position, self.screen, &.{ self.cursor, length });
        self.engine.freeValue(result);
    }
    fn fullRender(self: *Frame, clear: bool) !void {
        const engine = self.engine;
        const previous_redraws = try js.get(engine, self.screen, "fullRedrawCount");
        defer engine.freeValue(previous_redraws);
        const primitive_symbol = try js.get(engine, self.bindings, "primitiveSymbol");
        defer engine.freeValue(primitive_symbol);
        try v.set(engine, self.screen, "fullRedrawCount", try @import("native_tui_value_arithmetic.zig").add(engine, previous_redraws, c.JS_NewInt32(engine.context, 1), primitive_symbol));
        var output = try Writer.init(engine, self.screen, self.bindings);
        defer output.deinit();
        try output.text("\x1b[?2026h");
        if (clear) {
            const delete = try js.get(engine, self.screen, "deleteKittyImages");
            defer engine.freeValue(delete);
            const previous_ids = try js.get(engine, self.screen, "previousKittyImageIds");
            defer engine.freeValue(previous_ids);
            const deletion = try js.call(engine, delete, self.screen, &.{previous_ids});
            defer engine.freeValue(deletion);
            try output.append(deletion);
            try output.text("\x1b[2J\x1b[H\x1b[3J");
        }
        var index: f64 = 0;
        while (index < try self.lineCount()) : (index += 1) {
            if (index > 0) try output.text("\r\n");
            const line = try js.getKey(engine, self.lines, v.numeric(engine, index));
            defer engine.freeValue(line);
            const is_image = try self.imported("isImageLine", &.{line});
            defer engine.freeValue(is_image);
            const reserved = if (v.truthy(engine, is_image)) try self.invoke("getKittyImageReservedRows", &.{ self.lines, v.numeric(engine, index) }) else c.JS_NewInt32(engine.context, 1);
            defer engine.freeValue(reserved);
            const rows = try v.number(engine, reserved);
            if (rows > 1 and rows <= try v.number(engine, self.height)) {
                var row: f64 = 1;
                while (row < rows) : (row += 1) try output.text("\r\n");
                try output.sequence(rows - 1, "A");
                try output.append(line);
                try output.sequence(rows - 1, "B");
                index += rows - 1;
                continue;
            }
            try output.append(line);
        }
        try output.text("\x1b[?2026l");
        try output.flush();
        const cursor = try self.math("max", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try self.lineCount() - 1) });
        defer engine.freeValue(cursor);
        try v.set(engine, self.screen, "cursorRow", c.JS_DupValue(engine.context, cursor));
        try v.set(engine, self.screen, "hardwareCursorRow", try js.get(engine, self.screen, "cursorRow"));
        if (clear) {
            try v.set(engine, self.screen, "maxLinesRendered", try js.get(engine, self.lines, "length"));
        } else {
            const math_object = try js.global(engine, "Math");
            defer engine.freeValue(math_object);
            const maximum = try js.get(engine, math_object, "max");
            defer engine.freeValue(maximum);
            const previous = try js.get(engine, self.screen, "maxLinesRendered");
            defer engine.freeValue(previous);
            const length = try js.get(engine, self.lines, "length");
            defer engine.freeValue(length);
            try v.set(engine, self.screen, "maxLinesRendered", try js.call(engine, maximum, math_object, &.{ previous, length }));
        }
        const buffer_length = try self.math("max", &.{ self.height, v.numeric(engine, try self.lineCount()) });
        defer engine.freeValue(buffer_length);
        try v.set(engine, self.screen, "previousViewportTop", try self.math("max", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try v.number(engine, buffer_length) - try v.number(engine, self.height)) }));
        try self.positionCursor();
        try self.updatePrevious();
    }
    fn logRedraw(self: *Frame, redraw_reason: c.JSValue) !void {
        if (c.JS_IsUndefined(self.redraw_directory)) return;
        const engine = self.engine;
        const path = try js.get(engine, self.bindings, "path");
        defer engine.freeValue(path);
        const join = try js.get(engine, path, "join");
        defer engine.freeValue(join);
        const filename = try v.text(engine, "pi-tui-debug.log");
        defer engine.freeValue(filename);
        const log_path = try js.call(engine, join, path, &.{ self.redraw_directory, filename });
        defer engine.freeValue(log_path);
        const date = try js.builtin(engine, "Date", &.{});
        defer engine.freeValue(date);
        const iso = try js.invoke(engine, date, "toISOString", &.{});
        defer engine.freeValue(iso);
        const opening = try v.text(engine, "[");
        defer engine.freeValue(opening);
        const intro = try v.text(engine, "] fullRender: ");
        defer engine.freeValue(intro);
        const previous_label = try v.text(engine, " (prev=");
        defer engine.freeValue(previous_label);
        const previous_lines = try js.get(engine, self.screen, "previousLines");
        defer engine.freeValue(previous_lines);
        const previous_length = try js.get(engine, previous_lines, "length");
        defer engine.freeValue(previous_length);
        const new_label = try v.text(engine, ", new=");
        defer engine.freeValue(new_label);
        const new_length = try js.get(engine, self.lines, "length");
        defer engine.freeValue(new_length);
        const height_label = try v.text(engine, ", height=");
        defer engine.freeValue(height_label);
        const ending = try v.text(engine, ")\n");
        defer engine.freeValue(ending);
        const message = try v.concat(engine, &.{ opening, iso, intro, redraw_reason, previous_label, previous_length, new_label, new_length, height_label, self.height, ending });
        defer engine.freeValue(message);
        const fs = try js.get(engine, self.bindings, "fs");
        defer engine.freeValue(fs);
        const mkdir = try js.get(engine, fs, "mkdirSync");
        defer engine.freeValue(mkdir);
        const directory = try js.invoke(engine, path, "dirname", &.{log_path});
        defer engine.freeValue(directory);
        const options = try js.object(engine);
        defer engine.freeValue(options);
        try js.define(engine, options, "recursive", c.pi_js_bool(engine.context, 1));
        const created = try js.call(engine, mkdir, fs, &.{ directory, options });
        engine.freeValue(created);
        try v.invokeVoid(engine, fs, "appendFileSync", &.{ log_path, message });
    }
    fn redraw(self: *Frame, redraw_reason: []const u8) !void {
        const text = try v.text(self.engine, redraw_reason);
        defer self.engine.freeValue(text);
        try self.logRedraw(text);
        try self.fullRender(true);
    }
};
fn fieldChanged(engine: *js.Engine, screen: c.JSValue, name: [*:0]const u8, value: c.JSValue) !bool {
    const first = try js.get(engine, screen, name);
    defer engine.freeValue(first);
    if (c.JS_IsStrictEqual(engine.context, first, c.JS_NewInt32(engine.context, 0))) return false;
    const second = try js.get(engine, screen, name);
    defer engine.freeValue(second);
    return !c.JS_IsStrictEqual(engine.context, second, value);
}
fn environment(engine: *js.Engine, name: [*:0]const u8) !c.JSValue {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const env = try js.get(engine, process, "env");
    defer engine.freeValue(env);
    return js.get(engine, env, name);
}
fn init(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue) !Frame {
    const width_terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(width_terminal);
    const width = try js.get(engine, width_terminal, "columns");
    errdefer engine.freeValue(width);
    const height_terminal = try js.get(engine, screen, "terminal");
    defer engine.freeValue(height_terminal);
    const height = try js.get(engine, height_terminal, "rows");
    errdefer engine.freeValue(height);
    const width_changed = try fieldChanged(engine, screen, "previousWidth", width);
    const height_changed = try fieldChanged(engine, screen, "previousHeight", height);
    const previous_height = try js.get(engine, screen, "previousHeight");
    defer engine.freeValue(previous_height);
    const previous_buffer_length = blk: {
        if (!(try v.number(engine, previous_height) > 0)) break :blk c.JS_DupValue(engine.context, height);
        const top = try js.get(engine, screen, "previousViewportTop");
        defer engine.freeValue(top);
        const rows = try js.get(engine, screen, "previousHeight");
        defer engine.freeValue(rows);
        const symbol = try js.get(engine, bindings, "primitiveSymbol");
        defer engine.freeValue(symbol);
        break :blk try @import("native_tui_value_arithmetic.zig").add(engine, top, rows, symbol);
    };
    defer engine.freeValue(previous_buffer_length);
    const viewport_top = blk: {
        if (!height_changed) break :blk try v.numberField(engine, screen, "previousViewportTop");
        const math = try js.global(engine, "Math");
        defer engine.freeValue(math);
        const maximum = try js.get(engine, math, "max");
        defer engine.freeValue(maximum);
        const result = try js.call(engine, maximum, math, &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try v.number(engine, previous_buffer_length) - try v.number(engine, height)) });
        defer engine.freeValue(result);
        break :blk try v.number(engine, result);
    };
    const hardware = try v.numberField(engine, screen, "hardwareCursorRow");
    const resolve = try js.get(engine, screen, "resolveFakeCursors");
    defer engine.freeValue(resolve);
    const rendered = try js.invoke(engine, screen, "render", &.{width});
    defer engine.freeValue(rendered);
    var lines = try js.call(engine, resolve, screen, &.{rendered});
    errdefer engine.freeValue(lines);
    const overlays = try js.get(engine, screen, "hasOverlayEntries");
    defer engine.freeValue(overlays);
    if (v.truthy(engine, overlays)) {
        const composed = try js.invoke(engine, screen, "compositeOverlays", &.{ lines, width, height });
        engine.freeValue(lines);
        lines = composed;
    }
    const cursor = try js.invoke(engine, screen, "extractCursorPosition", &.{ lines, height });
    errdefer engine.freeValue(cursor);
    const reset = try js.invoke(engine, screen, "applyLineResets", &.{lines});
    engine.freeValue(lines);
    lines = reset;
    const flag = try environment(engine, "PI_TUI_DEBUG_REDRAW");
    defer engine.freeValue(flag);
    const one = try v.text(engine, "1");
    defer engine.freeValue(one);
    const log_directory = if (c.JS_IsStrictEqual(engine.context, flag, one)) try js.get(engine, screen, "logDirectory") else c.pi_js_undefined();
    return .{ .engine = engine, .screen = screen, .bindings = bindings, .width = width, .height = height, .width_changed = width_changed, .height_changed = height_changed, .previous_viewport_top = viewport_top, .viewport_top = viewport_top, .hardware_cursor_row = hardware, .lines = lines, .cursor = cursor, .redraw_directory = log_directory };
}
fn reason(engine: *js.Engine, pieces: []const c.JSValue) !c.JSValue {
    return v.concat(engine, pieces);
}
fn changedReason(frame: *Frame, field: [*:0]const u8, current: c.JSValue, description: []const u8) !void {
    const engine = frame.engine;
    const label = try v.text(engine, description);
    defer engine.freeValue(label);
    const previous = try js.get(engine, frame.screen, field);
    defer engine.freeValue(previous);
    const arrow = try v.text(engine, " -> ");
    defer engine.freeValue(arrow);
    const close = try v.text(engine, ")");
    defer engine.freeValue(close);
    const message = try reason(engine, &.{ label, previous, arrow, current, close });
    defer engine.freeValue(message);
    try frame.logRedraw(message);
    try frame.fullRender(true);
}
fn isTermux(engine: *js.Engine) !bool {
    const constructor = try js.global(engine, "Boolean");
    defer engine.freeValue(constructor);
    const version = try environment(engine, "TERMUX_VERSION");
    defer engine.freeValue(version);
    const result = try js.call(engine, constructor, c.pi_js_undefined(), &.{version});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
pub fn render(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const stopped = try js.get(engine, screen, "stopped");
    defer engine.freeValue(stopped);
    if (v.truthy(engine, stopped)) return c.pi_js_undefined();
    var frame = try init(engine, screen, bindings);
    defer frame.deinit();
    if (try frame.previousCount() == 0 and !frame.width_changed and !frame.height_changed) {
        const first = try v.text(engine, "first render");
        defer engine.freeValue(first);
        try frame.logRedraw(first);
        try frame.fullRender(false);
        return c.pi_js_undefined();
    }
    if (frame.width_changed) {
        try changedReason(&frame, "previousWidth", frame.width, "terminal width changed (");
        return c.pi_js_undefined();
    }
    if (frame.height_changed and !try isTermux(engine)) {
        try changedReason(&frame, "previousHeight", frame.height, "terminal height changed (");
        return c.pi_js_undefined();
    }
    const clear_on_shrink = try frame.invoke("getClearOnShrink", &.{});
    defer engine.freeValue(clear_on_shrink);
    if (v.truthy(engine, clear_on_shrink)) {
        const new_length = try js.get(engine, frame.lines, "length");
        defer engine.freeValue(new_length);
        const maximum = try js.get(engine, screen, "maxLinesRendered");
        defer engine.freeValue(maximum);
        if (try v.number(engine, new_length) < try v.number(engine, maximum)) {
            const overlays = try js.get(engine, screen, "hasOverlayEntries");
            defer engine.freeValue(overlays);
            if (!v.truthy(engine, overlays)) {
                const begin = try v.text(engine, "clearOnShrink (maxLinesRendered=");
                defer engine.freeValue(begin);
                const current = try js.get(engine, screen, "maxLinesRendered");
                defer engine.freeValue(current);
                const end = try v.text(engine, ")");
                defer engine.freeValue(end);
                const message = try reason(engine, &.{ begin, current, end });
                defer engine.freeValue(message);
                try frame.logRedraw(message);
                try frame.fullRender(true);
                return c.pi_js_undefined();
            }
        }
    }
    var first_changed: f64 = -1;
    var last_changed: f64 = -1;
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    const maximum = try js.get(engine, math, "max");
    defer engine.freeValue(maximum);
    const new_length = try js.get(engine, frame.lines, "length");
    defer engine.freeValue(new_length);
    const previous = try js.get(engine, screen, "previousLines");
    defer engine.freeValue(previous);
    const old_length = try js.get(engine, previous, "length");
    defer engine.freeValue(old_length);
    const maximum_lines = try js.call(engine, maximum, math, &.{ new_length, old_length });
    defer engine.freeValue(maximum_lines);
    var index: f64 = 0;
    while (index < try v.number(engine, maximum_lines)) : (index += 1) {
        const old_line = blk: {
            if (!(index < try frame.previousCount())) break :blk try v.text(engine, "");
            const lines = try js.get(engine, screen, "previousLines");
            defer engine.freeValue(lines);
            break :blk try js.getKey(engine, lines, v.numeric(engine, index));
        };
        defer engine.freeValue(old_line);
        const new_line = if (index < try frame.lineCount()) try js.getKey(engine, frame.lines, v.numeric(engine, index)) else try v.text(engine, "");
        defer engine.freeValue(new_line);
        if (!c.JS_IsStrictEqual(engine.context, old_line, new_line)) {
            if (first_changed == -1) first_changed = index;
            last_changed = index;
        }
    }
    const current_length = try js.get(engine, frame.lines, "length");
    defer engine.freeValue(current_length);
    const old_lines = try js.get(engine, screen, "previousLines");
    defer engine.freeValue(old_lines);
    const previous_length = try js.get(engine, old_lines, "length");
    defer engine.freeValue(previous_length);
    const appended = try v.number(engine, current_length) > try v.number(engine, previous_length);
    if (appended) {
        if (first_changed == -1) first_changed = try frame.previousCount();
        last_changed = try frame.lineCount() - 1;
    }
    if (first_changed != -1) {
        const expanded = try frame.invoke("expandChangedRangeForKittyImages", &.{ v.numeric(engine, first_changed), v.numeric(engine, last_changed), frame.lines });
        defer engine.freeValue(expanded);
        first_changed = try v.numberField(engine, expanded, "firstChanged");
        last_changed = try v.numberField(engine, expanded, "lastChanged");
    }
    const append_start = appended and first_changed == try frame.previousCount() and first_changed > 0;
    if (first_changed == -1) {
        try frame.positionCursor();
        try frame.setNumber("previousViewportTop", frame.previous_viewport_top);
        try v.set(engine, screen, "previousHeight", c.JS_DupValue(engine.context, frame.height));
        return c.pi_js_undefined();
    }
    if (first_changed >= try frame.lineCount()) {
        try deleteOnly(&frame, first_changed, last_changed);
        return c.pi_js_undefined();
    }
    if (first_changed < frame.previous_viewport_top) {
        try relationRedraw(&frame, "firstChanged < viewportTop (", first_changed, " < ", frame.previous_viewport_top);
        return c.pi_js_undefined();
    }
    try differential(&frame, first_changed, last_changed, append_start);
    return c.pi_js_undefined();
}
fn relationRedraw(frame: *Frame, label: []const u8, left: f64, relation: []const u8, right: f64) !void {
    const engine = frame.engine;
    const intro = try v.text(engine, label);
    defer engine.freeValue(intro);
    const middle = try v.text(engine, relation);
    defer engine.freeValue(middle);
    const end = try v.text(engine, ")");
    defer engine.freeValue(end);
    const message = try reason(engine, &.{ intro, v.numeric(engine, left), middle, v.numeric(engine, right), end });
    defer engine.freeValue(message);
    try frame.logRedraw(message);
    try frame.fullRender(true);
}
fn deleteOnly(frame: *Frame, first: f64, last: f64) !void {
    const engine = frame.engine;
    if (try frame.previousCount() > try frame.lineCount()) {
        var output = try Writer.init(engine, frame.screen, frame.bindings);
        defer output.deinit();
        try output.text("\x1b[?2026h");
        const deletions = try frame.invoke("deleteChangedKittyImages", &.{ v.numeric(engine, first), v.numeric(engine, last) });
        defer engine.freeValue(deletions);
        try output.append(deletions);
        const target_value = try frame.math("max", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try frame.lineCount() - 1) });
        defer engine.freeValue(target_value);
        const target = try v.number(engine, target_value);
        if (target < frame.previous_viewport_top) {
            try relationRedraw(frame, "deleted lines moved viewport up (", target, " < ", frame.previous_viewport_top);
            return;
        }
        const delta = frame.lineDiff(target);
        if (delta > 0) try output.sequence(delta, "B") else if (delta < 0) try output.sequence(-delta, "A");
        try output.text("\r");
        const extra = try frame.previousCount() - try frame.lineCount();
        if (extra > try v.number(engine, frame.height)) {
            try relationRedraw(frame, "extraLines > height (", extra, " > ", try v.number(engine, frame.height));
            return;
        }
        const start: f64 = if (try frame.lineCount() == 0) 0 else 1;
        if (extra > 0 and start > 0) try output.sequence(start, "B");
        var index: f64 = 0;
        while (index < extra) : (index += 1) {
            try output.text("\r\x1b[2K");
            if (index < extra - 1) try output.text("\x1b[1B");
        }
        const back = try frame.math("max", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, extra - 1 + start) });
        defer engine.freeValue(back);
        if (try v.number(engine, back) > 0) try output.sequence(try v.number(engine, back), "A");
        try output.text("\x1b[?2026l");
        try output.flush();
        try v.set(engine, frame.screen, "cursorRow", c.JS_DupValue(engine.context, target_value));
        try v.set(engine, frame.screen, "hardwareCursorRow", c.JS_DupValue(engine.context, target_value));
    }
    try frame.positionCursor();
    try frame.updatePrevious();
    try frame.setNumber("previousViewportTop", frame.previous_viewport_top);
}
fn differential(frame: *Frame, first: f64, last: f64, append_start: bool) !void {
    const engine = frame.engine;
    var output = try Writer.init(engine, frame.screen, frame.bindings);
    defer output.deinit();
    try output.text("\x1b[?2026h");
    const deleted_images = try frame.invoke("deleteChangedKittyImages", &.{ v.numeric(engine, first), v.numeric(engine, last) });
    defer engine.freeValue(deleted_images);
    try output.append(deleted_images);
    const previous_bottom = frame.previous_viewport_top + try v.number(engine, frame.height) - 1;
    const move_target = if (append_start) first - 1 else first;
    if (move_target > previous_bottom) {
        const outer_math = try js.global(engine, "Math");
        defer engine.freeValue(outer_math);
        const maximum = try js.get(engine, outer_math, "max");
        defer engine.freeValue(maximum);
        const inside = try frame.math("min", &.{ v.numeric(engine, try v.number(engine, frame.height) - 1), v.numeric(engine, frame.hardware_cursor_row - frame.previous_viewport_top) });
        defer engine.freeValue(inside);
        const current = try js.call(engine, maximum, outer_math, &.{ c.JS_NewInt32(engine.context, 0), inside });
        defer engine.freeValue(current);
        const to_bottom = try v.number(engine, frame.height) - 1 - try v.number(engine, current);
        if (to_bottom > 0) try output.sequence(to_bottom, "B");
        const scroll = move_target - previous_bottom;
        const newline = try v.text(engine, "\r\n");
        defer engine.freeValue(newline);
        const scrolled = try js.invoke(engine, newline, "repeat", &.{v.numeric(engine, scroll)});
        defer engine.freeValue(scrolled);
        try output.append(scrolled);
        frame.previous_viewport_top += scroll;
        frame.viewport_top += scroll;
        frame.hardware_cursor_row = move_target;
    }
    const delta = frame.lineDiff(move_target);
    if (delta > 0) try output.sequence(delta, "B") else if (delta < 0) try output.sequence(-delta, "A");
    try output.text(if (append_start) "\r\n" else "\r");
    const end_value = try frame.math("min", &.{ v.numeric(engine, last), v.numeric(engine, try frame.lineCount() - 1) });
    defer engine.freeValue(end_value);
    const render_end = try v.number(engine, end_value);
    var index = first;
    while (index <= render_end) : (index += 1) {
        if (index > first) try output.text("\r\n");
        const line = try js.getKey(engine, frame.lines, v.numeric(engine, index));
        defer engine.freeValue(line);
        const is_image = try frame.imported("isImageLine", &.{line});
        defer engine.freeValue(is_image);
        const reserved = if (v.truthy(engine, is_image)) try frame.invoke("getKittyImageReservedRows", &.{ frame.lines, v.numeric(engine, index), end_value }) else c.JS_NewInt32(engine.context, 1);
        defer engine.freeValue(reserved);
        const rows = try v.number(engine, reserved);
        if (rows > 1) {
            const image_start = index - frame.viewport_top;
            if (image_start < 0 or image_start + rows > try v.number(engine, frame.height)) {
                const label = try v.text(engine, "kitty image pre-clear would scroll (");
                defer engine.freeValue(label);
                const plus = try v.text(engine, " + ");
                defer engine.freeValue(plus);
                const greater = try v.text(engine, " > ");
                defer engine.freeValue(greater);
                const end = try v.text(engine, ")");
                defer engine.freeValue(end);
                const message = try reason(engine, &.{ label, v.numeric(engine, image_start), plus, reserved, greater, frame.height, end });
                defer engine.freeValue(message);
                try frame.logRedraw(message);
                try frame.fullRender(true);
                return;
            }
            try output.text("\x1b[2K");
            var row: f64 = 1;
            while (row < rows) : (row += 1) try output.text("\r\n\x1b[2K");
            try output.sequence(rows - 1, "A");
            try output.append(line);
            try output.sequence(rows - 1, "B");
            index += rows - 1;
            continue;
        }
        try output.text("\x1b[2K");
        if (!v.truthy(engine, is_image)) {
            const visible_width = try frame.imported("visibleWidth", &.{line});
            defer engine.freeValue(visible_width);
            if (try v.number(engine, visible_width) > try v.number(engine, frame.width)) try @import("native_tui_main_logs.zig").crash(engine, frame.screen, frame.bindings, frame.lines, frame.width, index, line);
        }
        try output.append(line);
    }
    var final_cursor_row = render_end;
    if (try frame.previousCount() > try frame.lineCount()) {
        if (render_end < try frame.lineCount() - 1) {
            const down = try frame.lineCount() - 1 - render_end;
            try output.sequence(down, "B");
            final_cursor_row = try frame.lineCount() - 1;
        }
        const extra = try frame.previousCount() - try frame.lineCount();
        var clear_row = try frame.lineCount();
        while (clear_row < try frame.previousCount()) : (clear_row += 1) try output.text("\r\n\x1b[2K");
        try output.sequence(extra, "A");
    }
    try output.text("\x1b[?2026l");
    const debug_flag = try environment(engine, "PI_TUI_DEBUG");
    defer engine.freeValue(debug_flag);
    const one = try v.text(engine, "1");
    defer engine.freeValue(one);
    if (c.JS_IsStrictEqual(engine.context, debug_flag, one)) try @import("native_tui_main_logs.zig").debug(engine, frame.screen, frame.bindings, frame.lines, .{ .first = first, .viewport_top = frame.viewport_top, .height = frame.height, .line_diff = delta, .hardware_row = frame.hardware_cursor_row, .render_end = render_end, .final_row = final_cursor_row, .cursor = frame.cursor, .written_chars = try output.length() });
    try output.flush();
    try v.set(engine, frame.screen, "cursorRow", try frame.math("max", &.{ c.JS_NewInt32(engine.context, 0), v.numeric(engine, try frame.lineCount() - 1) }));
    try frame.setNumber("hardwareCursorRow", final_cursor_row);
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    const maximum = try js.get(engine, math, "max");
    defer engine.freeValue(maximum);
    const previous_maximum = try js.get(engine, frame.screen, "maxLinesRendered");
    defer engine.freeValue(previous_maximum);
    const current_length = try js.get(engine, frame.lines, "length");
    defer engine.freeValue(current_length);
    try v.set(engine, frame.screen, "maxLinesRendered", try js.call(engine, maximum, math, &.{ previous_maximum, current_length }));
    try v.set(engine, frame.screen, "previousViewportTop", try frame.math("max", &.{ v.numeric(engine, frame.previous_viewport_top), v.numeric(engine, final_cursor_row - try v.number(engine, frame.height) + 1) }));
    try frame.positionCursor();
    try frame.updatePrevious();
}

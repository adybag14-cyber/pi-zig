//! Native Source Input class. Strings and cursors retain JavaScript UTF16 units.
const std = @import("std");
const engine_mod = @import("engine.zig");
const js = @import("native_js_values.zig");
const utf16 = @import("native_utf16.zig");
const input_mod = @import("../tui/utf16_input.zig");
const graphemes = @import("../tui/utf16_graphemes.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const markers = @import("../tui/cursor_markers.zig");
const layout = @import("../tui/utf16_terminal.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Method = enum(c_int) { getValue, setValue, handleInput, handleMouse, insertCharacter, handleBackspace, handleForwardDelete, deleteToLineStart, deleteToLineEnd, deleteWordBackwards, deleteWordForward, yank, yankPop, pushUndo, undo, moveWordBackwards, moveWordForwards, handlePaste, invalidate, render };
const Kind = enum { input, undo, kill };
const Class = struct { engine: *Engine, prototype: c.JSValue, kind: Kind = .input, undo: ?c.JSValue = null, kill: ?c.JSValue = null };
const AuxMethod = enum(c_int) { undo_push, undo_pop, undo_clear, undo_length, kill_push, kill_peek, kill_rotate, kill_length };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Input: %s", @as([*:0]const u8, @errorName(err)));
}
fn set(engine: *Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, object, name, value) < 0) return js.capture(engine);
}
fn integer(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !i64 {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    var result: i64 = 0;
    if (c.JS_ToInt64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn unitsField(engine: *Engine, object: c.JSValue, name: [*:0]const u8) ![]u16 {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return utf16.unitsAlloc(engine, value);
}
fn arrayLength(engine: *Engine, array: c.JSValue) !usize {
    const length = try integer(engine, array, "length");
    if (length < 0 or length > 1_000_000) return error.NativeInputStateLimit;
    return @intCast(length);
}
fn sliceIndex(length: usize, offset: i64) usize {
    const count: i64 = @intCast(length);
    return @intCast(if (offset < 0) @max(0, count + offset) else @min(count, offset));
}
fn appendAscii(gpa: std.mem.Allocator, output: *std.ArrayList(u16), text: []const u8) !void {
    for (text) |unit| try output.append(gpa, unit);
}
fn render(engine: *Engine, object: c.JSValue, width_value: c.JSValue) !c.JSValue {
    var raw_width: i64 = 0;
    if (c.JS_ToInt64(engine.context, &raw_width, width_value) < 0) return js.capture(engine);
    if (raw_width > 1_000_000) return error.NativeInputStateLimit;
    const prompt = try unitsField(engine, object, "prompt");
    defer engine.gpa.free(prompt);
    const available = raw_width - @as(i64, @intCast(try layout.visibleWidth(engine.gpa, prompt)));
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    if (available <= 0) {
        const clipped = try layout.truncateAlloc(engine.gpa, prompt, @intCast(@max(0, raw_width)));
        defer engine.gpa.free(clipped);
        const value = try utf16.string(engine, clipped);
        defer engine.freeValue(value);
        try js.push(engine, result, value);
        return result;
    }
    const area: usize = @intCast(available);
    const text = try unitsField(engine, object, "value");
    defer engine.gpa.free(text);
    const focused_value = try js.get(engine, object, "focused");
    defer engine.freeValue(focused_value);
    const focused = c.JS_ToBool(engine.context, focused_value) != 0;
    var output: std.ArrayList(u16) = .empty;
    defer output.deinit(engine.gpa);
    const placeholder = try unitsField(engine, object, "placeholder");
    defer engine.gpa.free(placeholder);
    if (text.len == 0 and placeholder.len != 0) {
        const visible = try layout.truncateAlloc(engine.gpa, placeholder, area);
        defer engine.gpa.free(visible);
        var iterator: graphemes.Iterator = .{ .text = visible };
        const at_cursor: []const u16 = if (iterator.next()) |segment| visible[segment.start..segment.end] else &.{' '};
        const after = visible[@min(at_cursor.len, visible.len)..];
        const at_value = try utf16.string(engine, at_cursor);
        defer engine.freeValue(at_value);
        const styled_at = try js.invoke(engine, object, "placeholderStyle", &.{at_value});
        defer engine.freeValue(styled_at);
        const at_units = try utf16.unitsAlloc(engine, styled_at);
        defer engine.gpa.free(at_units);
        if (focused) try appendAscii(engine.gpa, &output, markers.cursor);
        try appendAscii(engine.gpa, &output, markers.fake_start);
        try output.appendSlice(engine.gpa, at_units);
        try appendAscii(engine.gpa, &output, markers.fake_end);
        const after_value = try utf16.string(engine, after);
        defer engine.freeValue(after_value);
        const styled_after = try js.invoke(engine, object, "placeholderStyle", &.{after_value});
        defer engine.freeValue(styled_after);
        const after_units = try utf16.unitsAlloc(engine, styled_after);
        defer engine.gpa.free(after_units);
        try output.appendSlice(engine.gpa, after_units);
    } else {
        const cursor = try integer(engine, object, "cursor");
        var display = cursor;
        try set(engine, object, "renderedStartColumn", c.JS_NewInt32(engine.context, 0));
        const total = try layout.visibleWidth(engine.gpa, text);
        var owned: ?[]u16 = null;
        defer if (owned) |value| engine.gpa.free(value);
        var visible: []const u16 = text;
        if (total >= area) {
            const scroll_width = if (cursor == text.len) area - 1 else area;
            const cursor_column = try layout.visibleWidth(engine.gpa, text[0..sliceIndex(text.len, cursor)]);
            if (scroll_width > 0) {
                const half = scroll_width / 2;
                const start = if (cursor_column < half) 0 else if (cursor_column > total - half) total - scroll_width else cursor_column - half;
                try set(engine, object, "renderedStartColumn", c.JS_NewFloat64(engine.context, @floatFromInt(start)));
                owned = try layout.sliceAlloc(engine.gpa, text, start, scroll_width);
                visible = owned.?;
                const before = try layout.sliceAlloc(engine.gpa, text, start, cursor_column -| start);
                defer engine.gpa.free(before);
                display = @intCast(before.len);
            } else {
                visible = &.{};
                display = 0;
            }
        }
        const index = sliceIndex(visible.len, display);
        var iterator: graphemes.Iterator = .{ .text = visible[index..] };
        const at_cursor: []const u16 = if (iterator.next()) |segment| visible[index + segment.start .. index + segment.end] else &.{' '};
        try output.appendSlice(engine.gpa, visible[0..index]);
        if (focused) try appendAscii(engine.gpa, &output, markers.cursor);
        try appendAscii(engine.gpa, &output, markers.fake_start);
        try output.appendSlice(engine.gpa, at_cursor);
        try appendAscii(engine.gpa, &output, markers.fake_end);
        try output.appendSlice(engine.gpa, visible[sliceIndex(visible.len, display + @as(i64, @intCast(at_cursor.len)))..]);
    }
    const visible_width = try layout.visibleWidth(engine.gpa, output.items);
    try output.appendNTimes(engine.gpa, ' ', area -| visible_width);
    var line: std.ArrayList(u16) = .empty;
    defer line.deinit(engine.gpa);
    try line.appendSlice(engine.gpa, prompt);
    try line.appendSlice(engine.gpa, output.items);
    const value = try utf16.string(engine, line.items);
    defer engine.freeValue(value);
    try js.push(engine, result, value);
    return result;
}
fn handleMouse(engine: *Engine, object: c.JSValue, event: c.JSValue) !c.JSValue {
    inline for (.{ .{ "type", "press" }, .{ "button", "left" } }) |entry| {
        const value = try js.get(engine, event, entry[0]);
        defer engine.freeValue(value);
        if (!c.JS_IsString(value)) return c.pi_js_undefined();
        const string = try engine.toString(value);
        defer engine.gpa.free(string);
        if (!std.mem.eql(u8, string, entry[1])) return c.pi_js_undefined();
    }
    const y = try js.get(engine, event, "y");
    defer engine.freeValue(y);
    if (!c.JS_IsStrictEqual(engine.context, y, c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    const x = try js.get(engine, event, "x");
    defer engine.freeValue(x);
    var raw_x: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &raw_x, x) < 0) return js.capture(engine);
    const target = @as(f64, @floatFromInt(try integer(engine, object, "renderedStartColumn"))) + if (std.math.isNan(raw_x)) raw_x else @max(0, raw_x - 2);
    const text = try unitsField(engine, object, "value");
    defer engine.gpa.free(text);
    var cursor = text.len;
    var column: usize = 0;
    var iterator: graphemes.Iterator = .{ .text = text };
    while (iterator.next()) |segment| {
        const next_column = column + try layout.visibleWidth(engine.gpa, text[segment.start..segment.end]);
        if (target < @as(f64, @floatFromInt(next_column))) {
            cursor = segment.start;
            break;
        }
        column = next_column;
    }
    try set(engine, object, "cursor", c.JS_NewFloat64(engine.context, @floatFromInt(cursor)));
    try set(engine, object, "lastAction", c.pi_js_null());
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "handled", c.pi_js_bool(engine.context, 1));
    try js.define(engine, result, "focus", c.pi_js_bool(engine.context, 1));
    return result;
}
fn methodCall(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, receiver, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue) !c.JSValue {
    const arg = if (args.len != 0) args[0] else c.pi_js_undefined();
    switch (operation) {
        .getValue => return js.get(engine, object, "value"),
        .setValue => {
            try set(engine, object, "value", c.JS_DupValue(engine.context, arg));
            const length = try integer(engine, arg, "length");
            try set(engine, object, "cursor", c.JS_NewFloat64(engine.context, @floatFromInt(@min(try integer(engine, object, "cursor"), length))));
        },
        .handleInput => try handleInput(engine, object, arg),
        .invalidate => {},
        .handleMouse => return handleMouse(engine, object, arg),
        .render => return render(engine, object, arg),
        else => try primitive(engine, object, operation, arg),
    }
    return c.pi_js_undefined();
}
fn lastIs(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try js.get(engine, object, "lastAction");
    defer engine.freeValue(value);
    const wanted = try engine.checked(c.JS_NewString(engine.context, name));
    defer engine.freeValue(wanted);
    return c.JS_IsStrictEqual(engine.context, value, wanted);
}
fn setLast(engine: *Engine, object: c.JSValue, name: ?[*:0]const u8) !void {
    try set(engine, object, "lastAction", if (name) |text| try engine.checked(c.JS_NewString(engine.context, text)) else c.pi_js_null());
}
fn sliceValue(engine: *Engine, text: c.JSValue, start: i64, end: ?i64) !c.JSValue {
    const first = c.JS_NewFloat64(engine.context, @floatFromInt(start));
    if (end) |last| return js.invoke(engine, text, "slice", &.{ first, c.JS_NewFloat64(engine.context, @floatFromInt(last)) });
    return js.invoke(engine, text, "slice", &.{first});
}
fn replaceValue(engine: *Engine, object: c.JSValue, start: i64, end: i64, middle: c.JSValue) !void {
    const text = try js.get(engine, object, "value");
    defer engine.freeValue(text);
    const prefix = try sliceValue(engine, text, 0, start);
    defer engine.freeValue(prefix);
    const suffix = try sliceValue(engine, text, end, null);
    defer engine.freeValue(suffix);
    try set(engine, object, "value", try concatValues(engine, &.{ prefix, middle, suffix }));
}
fn setCursor(engine: *Engine, object: c.JSValue, cursor: i64) !void {
    try set(engine, object, "cursor", c.JS_NewFloat64(engine.context, @floatFromInt(cursor)));
}
fn invokeKill(engine: *Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const ring = try js.get(engine, object, "killRing");
    defer engine.freeValue(ring);
    return js.invoke(engine, ring, name, args);
}
fn pushKill(engine: *Engine, object: c.JSValue, text: c.JSValue, prepend: bool, accumulate: bool) !void {
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "prepend", c.pi_js_bool(engine.context, @intFromBool(prepend)));
    try js.define(engine, options, "accumulate", c.pi_js_bool(engine.context, @intFromBool(accumulate)));
    const result = try invokeKill(engine, object, "push", &.{ text, options });
    engine.freeValue(result);
}
fn primitive(engine: *Engine, object: c.JSValue, operation: Method, arg: c.JSValue) !void {
    switch (operation) {
        .pushUndo => {
            const state = try js.object(engine);
            defer engine.freeValue(state);
            try js.define(engine, state, "value", try js.get(engine, object, "value"));
            try js.define(engine, state, "cursor", try js.get(engine, object, "cursor"));
            const stack = try js.get(engine, object, "undoStack");
            defer engine.freeValue(stack);
            try invokeVoid(engine, stack, "push", &.{state});
        },
        .undo => {
            const stack = try js.get(engine, object, "undoStack");
            defer engine.freeValue(stack);
            const snapshot = try js.invoke(engine, stack, "pop", &.{});
            defer engine.freeValue(snapshot);
            if (c.JS_ToBool(engine.context, snapshot) != 0) {
                try set(engine, object, "value", try js.get(engine, snapshot, "value"));
                try set(engine, object, "cursor", try js.get(engine, snapshot, "cursor"));
                try setLast(engine, object, null);
            }
        },
        .insertCharacter => {
            const units = try utf16.unitsAlloc(engine, arg);
            defer engine.gpa.free(units);
            var whitespace = false;
            for (units) |unit| if (input_mod.State.whitespace(unit)) {
                whitespace = true;
                break;
            };
            if (whitespace or !try lastIs(engine, object, "type-word")) try invokeVoid(engine, object, "pushUndo", &.{});
            try setLast(engine, object, "type-word");
            const cursor = try integer(engine, object, "cursor");
            try replaceValue(engine, object, cursor, cursor, arg);
            try setCursor(engine, object, cursor + @as(i64, @intCast(units.len)));
        },
        .handlePaste => {
            try setLast(engine, object, null);
            try invokeVoid(engine, object, "pushUndo", &.{});
            const units = try utf16.unitsAlloc(engine, arg);
            defer engine.gpa.free(units);
            var clean: std.ArrayList(u16) = .empty;
            defer clean.deinit(engine.gpa);
            for (units) |unit| switch (unit) {
                '\r', '\n' => {},
                '\t' => try clean.appendSlice(engine.gpa, &.{ ' ', ' ', ' ', ' ' }),
                else => try clean.append(engine.gpa, unit),
            };
            const value = try utf16.string(engine, clean.items);
            defer engine.freeValue(value);
            const cursor = try integer(engine, object, "cursor");
            try replaceValue(engine, object, cursor, cursor, value);
            try setCursor(engine, object, cursor + @as(i64, @intCast(clean.items.len)));
        },
        .handleBackspace, .handleForwardDelete => {
            try setLast(engine, object, null);
            const initial = try integer(engine, object, "cursor");
            const value = try js.get(engine, object, "value");
            defer engine.freeValue(value);
            if ((operation == .handleBackspace and initial <= 0) or (operation == .handleForwardDelete and initial >= try integer(engine, value, "length"))) return;
            try invokeVoid(engine, object, "pushUndo", &.{});
            const cursor = try integer(engine, object, "cursor");
            const current = try js.get(engine, object, "value");
            defer engine.freeValue(current);
            const fragment = try sliceValue(engine, current, if (operation == .handleBackspace) 0 else cursor, if (operation == .handleBackspace) cursor else null);
            defer engine.freeValue(fragment);
            const units = try utf16.unitsAlloc(engine, fragment);
            defer engine.gpa.free(units);
            const count: i64 = @intCast(if (units.len == 0) 1 else if (operation == .handleBackspace) units.len - graphemes.previous(units, units.len) else graphemes.next(units, 0));
            const empty = try utf16.string(engine, &.{});
            defer engine.freeValue(empty);
            try replaceValue(engine, object, if (operation == .handleBackspace) cursor - count else cursor, if (operation == .handleBackspace) cursor else cursor + count, empty);
            if (operation == .handleBackspace) try setCursor(engine, object, cursor - count);
        },
        .deleteToLineStart, .deleteToLineEnd => {
            const initial = try integer(engine, object, "cursor");
            const value = try js.get(engine, object, "value");
            defer engine.freeValue(value);
            const backwards = operation == .deleteToLineStart;
            if ((backwards and initial == 0) or (!backwards and initial >= try integer(engine, value, "length"))) return;
            try invokeVoid(engine, object, "pushUndo", &.{});
            const cursor = try integer(engine, object, "cursor");
            const current = try js.get(engine, object, "value");
            defer engine.freeValue(current);
            const deleted = try sliceValue(engine, current, if (backwards) 0 else cursor, if (backwards) cursor else null);
            defer engine.freeValue(deleted);
            try pushKill(engine, object, deleted, backwards, try lastIs(engine, object, "kill"));
            try setLast(engine, object, "kill");
            try set(engine, object, "value", try sliceValue(engine, current, if (backwards) cursor else 0, if (backwards) null else cursor));
            if (backwards) try setCursor(engine, object, 0);
        },
        .moveWordBackwards, .moveWordForwards => {
            const cursor = try integer(engine, object, "cursor");
            const value = try js.get(engine, object, "value");
            defer engine.freeValue(value);
            if ((operation == .moveWordBackwards and cursor == 0) or (operation == .moveWordForwards and cursor >= try integer(engine, value, "length"))) return;
            try setLast(engine, object, null);
            return error.WordSegmentationUnavailable;
        },
        .deleteWordBackwards, .deleteWordForward => {
            const left = operation == .deleteWordBackwards;
            const initial = try integer(engine, object, "cursor");
            const value = try js.get(engine, object, "value");
            defer engine.freeValue(value);
            if ((left and initial == 0) or (!left and initial >= try integer(engine, value, "length"))) return;
            const was_kill = try lastIs(engine, object, "kill");
            try invokeVoid(engine, object, "pushUndo", &.{});
            const old = try integer(engine, object, "cursor");
            try invokeVoid(engine, object, if (left) "moveWordBackwards" else "moveWordForwards", &.{});
            const target = try integer(engine, object, "cursor");
            try setCursor(engine, object, old);
            const current = try js.get(engine, object, "value");
            defer engine.freeValue(current);
            const deleted = try sliceValue(engine, current, if (left) target else old, if (left) old else target);
            defer engine.freeValue(deleted);
            try pushKill(engine, object, deleted, left, was_kill);
            try setLast(engine, object, "kill");
            const empty = try utf16.string(engine, &.{});
            defer engine.freeValue(empty);
            try replaceValue(engine, object, if (left) target else old, if (left) old else target, empty);
            if (left) try setCursor(engine, object, target);
        },
        .yank => {
            const text = try invokeKill(engine, object, "peek", &.{});
            defer engine.freeValue(text);
            if (c.JS_ToBool(engine.context, text) == 0) return;
            try invokeVoid(engine, object, "pushUndo", &.{});
            const cursor = try integer(engine, object, "cursor");
            try replaceValue(engine, object, cursor, cursor, text);
            try setCursor(engine, object, cursor + try integer(engine, text, "length"));
            try setLast(engine, object, "yank");
        },
        .yankPop => {
            if (!try lastIs(engine, object, "yank")) return;
            const ring = try js.get(engine, object, "killRing");
            defer engine.freeValue(ring);
            if (try integer(engine, ring, "length") <= 1) return;
            try invokeVoid(engine, object, "pushUndo", &.{});
            const previous = try invokeKill(engine, object, "peek", &.{});
            defer engine.freeValue(previous);
            const count = if (c.JS_ToBool(engine.context, previous) == 0) 0 else try integer(engine, previous, "length");
            const cursor = try integer(engine, object, "cursor");
            const empty = try utf16.string(engine, &.{});
            defer engine.freeValue(empty);
            try replaceValue(engine, object, cursor - count, cursor, empty);
            try setCursor(engine, object, cursor - count);
            const ignored = try invokeKill(engine, object, "rotate", &.{});
            engine.freeValue(ignored);
            const next = try invokeKill(engine, object, "peek", &.{});
            defer engine.freeValue(next);
            const text = if (c.JS_ToBool(engine.context, next) == 0) empty else next;
            const at = try integer(engine, object, "cursor");
            try replaceValue(engine, object, at, at, text);
            try setCursor(engine, object, at + try integer(engine, text, "length"));
            try setLast(engine, object, "yank");
        },
        else => unreachable,
    }
}
fn constructorMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, visit);
    if (state.undo) |child| c.JS_MarkValue(runtime, child, visit);
    if (state.kill) |child| c.JS_MarkValue(runtime, child, visit);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    if (state.undo) |child| c.JS_FreeValueRT(runtime, child);
    if (state.kill) |child| c.JS_FreeValueRT(runtime, child);
    state.engine.gpa.destroy(state);
}
fn identity(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return if (argc == 0) c.pi_js_undefined() else c.JS_DupValue(context, argv[0]);
}
fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Input requires new");
    const state: *Class = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return construct(engine, state, target, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn construct(engine: *Engine, state: *Class, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    const object = try engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    if (state.kind != .input) {
        try js.define(engine, object, if (state.kind == .undo) "stack" else "ring", try js.array(engine));
        return object;
    }
    const options = if (args.len == 0 or c.JS_IsUndefined(args[0])) try js.object(engine) else c.JS_DupValue(engine.context, args[0]);
    defer engine.freeValue(options);
    try js.define(engine, object, "value", try utf16.string(engine, &.{}));
    try js.define(engine, object, "cursor", c.JS_NewInt32(engine.context, 0));
    inline for (.{ .{ "prompt", "> " }, .{ "placeholder", "" } }) |entry| {
        const value = try js.get(engine, options, entry[0]);
        defer engine.freeValue(value);
        try js.define(engine, object, entry[0], if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) try engine.checked(c.JS_NewString(engine.context, entry[1])) else c.JS_DupValue(engine.context, value));
    }
    const style = try js.get(engine, options, "placeholderStyle");
    defer engine.freeValue(style);
    try js.define(engine, object, "placeholderStyle", if (c.JS_IsNull(style) or c.JS_IsUndefined(style)) try engine.checked(c.JS_NewCFunction(engine.context, identity, "", 1)) else c.JS_DupValue(engine.context, style));
    try js.define(engine, object, "renderedStartColumn", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, object, "onSubmit", c.pi_js_undefined());
    try js.define(engine, object, "onEscape", c.pi_js_undefined());
    try js.define(engine, object, "focused", c.pi_js_bool(engine.context, 0));
    try js.define(engine, object, "pasteBuffer", try utf16.string(engine, &.{}));
    try js.define(engine, object, "isInPaste", c.pi_js_bool(engine.context, 0));
    const ring = try engine.checked(c.JS_CallConstructor(engine.context, state.kill.?, 0, null));
    defer engine.freeValue(ring);
    try js.define(engine, object, "killRing", c.JS_DupValue(engine.context, ring));
    try js.define(engine, object, "lastAction", c.pi_js_null());
    const undo = try engine.checked(c.JS_CallConstructor(engine.context, state.undo.?, 0, null));
    defer engine.freeValue(undo);
    try js.define(engine, object, "undoStack", c.JS_DupValue(engine.context, undo));
    return object;
}
fn concatValues(engine: *Engine, parts: []const c.JSValue) !c.JSValue {
    var units: std.ArrayList(u16) = .empty;
    defer units.deinit(engine.gpa);
    for (parts) |part| {
        const text = try utf16.unitsAlloc(engine, part);
        defer engine.gpa.free(text);
        try units.appendSlice(engine.gpa, text);
    }
    return utf16.string(engine, units.items);
}
fn cloneSnapshot(engine: *Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const function = try js.get(engine, global, "structuredClone");
    defer engine.freeValue(function);
    if (!c.JS_IsUndefined(function)) return js.call(engine, function, c.pi_js_undefined(), &.{value});
    return @import("native_structured_clone.zig").clone(engine, value);
}
fn auxCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return auxiliary(engine, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn auxiliary(engine: *Engine, object: c.JSValue, operation: AuxMethod, args: []const c.JSValue) !c.JSValue {
    const value = if (args.len == 0) c.pi_js_undefined() else args[0];
    if (operation == .kill_push and c.JS_ToBool(engine.context, value) == 0) return c.pi_js_undefined();
    const undo = @intFromEnum(operation) <= @intFromEnum(AuxMethod.undo_length);
    const array = try js.get(engine, object, if (undo) "stack" else "ring");
    defer engine.freeValue(array);
    switch (operation) {
        .undo_length, .kill_length => return js.get(engine, array, "length"),
        .undo_pop => return js.invoke(engine, array, "pop", &.{}),
        .undo_clear => try set(engine, array, "length", c.JS_NewInt32(engine.context, 0)),
        .undo_push => {
            const push = try js.get(engine, array, "push");
            defer engine.freeValue(push);
            const snapshot = try cloneSnapshot(engine, value);
            defer engine.freeValue(snapshot);
            const result = try js.call(engine, push, array, &.{snapshot});
            engine.freeValue(result);
        },
        .kill_peek => {
            const count = try arrayLength(engine, array);
            return if (count == 0) c.pi_js_undefined() else engine.checked(c.JS_GetPropertyUint32(engine.context, array, @intCast(count - 1)));
        },
        .kill_rotate => if (try arrayLength(engine, array) > 1) {
            const last = try js.invoke(engine, array, "pop", &.{});
            defer engine.freeValue(last);
            try invokeVoid(engine, array, "unshift", &.{last});
        },
        .kill_push => {
            const options = if (args.len > 1) args[1] else c.pi_js_undefined();
            const accumulate = try js.get(engine, options, "accumulate");
            defer engine.freeValue(accumulate);
            if (c.JS_ToBool(engine.context, accumulate) != 0 and try arrayLength(engine, array) > 0) {
                const last = try js.invoke(engine, array, "pop", &.{});
                defer engine.freeValue(last);
                const prepend = try js.get(engine, options, "prepend");
                defer engine.freeValue(prepend);
                const joined = try concatValues(engine, if (c.JS_ToBool(engine.context, prepend) != 0) &.{ value, last } else &.{ last, value });
                defer engine.freeValue(joined);
                try js.push(engine, array, joined);
            } else try js.push(engine, array, value);
        },
    }
    return c.pi_js_undefined();
}
fn makeAuxConstructor(engine: *Engine, class: c.JSClassID, kind: Kind) !c.JSValue {
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(AuxMethod)) |field| {
        const operation: AuxMethod = @enumFromInt(field.value);
        const undo = field.value <= @intFromEnum(AuxMethod.undo_length);
        if (undo == (kind == .undo)) {
            const name: [*:0]const u8 = switch (operation) {
                .undo_push, .kill_push => "push",
                .undo_pop => "pop",
                .undo_clear => "clear",
                .undo_length, .kill_length => "length",
                .kill_peek => "peek",
                .kill_rotate => "rotate",
            };
            const getter = operation == .undo_length or operation == .kill_length;
            const function = try engine.checked(c.pi_js_function_magic(engine.context, auxCall, if (getter) "get length" else name, if (operation == .undo_push) 1 else if (operation == .kill_push) 2 else 0, @intCast(field.value)));
            if (getter) {
                const atom = c.JS_NewAtom(engine.context, name);
                defer c.JS_FreeAtom(engine.context, atom);
                if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, function, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
            } else if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        }
    }
    const function_type = try js.global(engine, "Function");
    defer engine.freeValue(function_type);
    const function_prototype = try js.get(engine, function_type, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class));
    errdefer engine.freeValue(constructor);
    const state = try engine.gpa.create(Class);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .kind = kind };
    _ = c.JS_SetOpaque(constructor, state);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", try engine.checked(c.JS_NewString(engine.context, if (kind == .undo) "UndoStack" else "KillRing")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 0), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return constructor;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native Input Constructor", .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = constructorCall };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .setValue, .handleInput, .handleMouse, .insertCharacter, .handlePaste, .render => 1,
            else => 0,
        };
        const callback_value = try engine.checked(c.pi_js_function_magic(engine.context, methodCall, name.ptr, length, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, callback_value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
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
    state.undo = try makeAuxConstructor(engine, class, .undo);
    state.kill = try makeAuxConstructor(engine, class, .kill);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", try engine.checked(c.JS_NewString(engine.context, "Input")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 0), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try js.define(engine, exports, "Input", c.JS_DupValue(engine.context, constructor));
}
test "Source6fb public Input native class replays actual UTF16 editing snapshots" {
    @import("../tui/keys.zig").setKittyProtocolActive(false);
    defer @import("../tui/keys.zig").setKittyProtocolActive(false);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const fixture = @embedFile("../tui/fixtures/input-state-original-6fb.json");
    try js.define(engine, root, "inputStateFixture", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "input-state-original-6fb.json")));
    const result = try engine.evalModule(
        \\import{Input}from'pi-tui';
        \\const fromUnits=units=>String.fromCharCode(...units),units=text=>Array.from({length:text.length},(_,i)=>text.charCodeAt(i));
        \\const data={left:'\x1b[D',right:'\x1b[C',start:'\x01',end:'\x05',backspace:'\x7f',delete:'\x1b[3~',kill_start:'\x15',kill_end:'\x0b',yank:'\x19',yank_pop:'\x1by',undo:'\x1f'};
        \\for(const trace of inputStateFixture.cases){const input=new Input();for(const step of trace){const op=step.operation;if('value'in op)input.setValue(fromUnits(op.value));else if('cursor'in op)input.cursor=op.cursor;else if('text'in op)input.handleInput(fromUnits(op.text));else if('paste'in op)input.handleInput('\x1b[200~'+fromUnits(op.paste)+'\x1b[201~');else input.handleInput(data[op.action]);const actual={value:units(input.getValue()),cursor:input.cursor,last:input.lastAction,undo:input.undoStack.stack.map(s=>({value:units(s.value),cursor:s.cursor})),kill:input.killRing.ring.map(units)};if(JSON.stringify(actual)!==JSON.stringify(step.expected))throw Error(JSON.stringify({op,actual,expected:step.expected}));}}
    , "input-state-replay.mjs");
    engine.freeValue(result);
}
test "Source6fb public Input original placeholder scroll cursor and mouse presentation" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const fixture = @embedFile("fixtures/input-presentation-original-6fb.json");
    try js.define(engine, root, "inputPresentationFixture", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "input-presentation-original-6fb.json")));
    const result = engine.evalModule(
        \\import{Input}from'pi-tui';
        \\const fromUnits=units=>String.fromCharCode(...units),units=text=>Array.from({length:text.length},(_,i)=>text.charCodeAt(i));
        \\for(const [index,item]of inputPresentationFixture.cases.entries()){let input;const calls=[],options={};for(const [key,value]of Object.entries(item.options))if(key!=='style')options[key]=fromUnits(value);if(item.options.style)options.placeholderStyle=function(text){calls.push({text:units(text),receiver:this===input});return item.options.style==='ansi'?'\x1b[35m'+text+'\x1b[0m':'['+text+']'};input=new Input(options);input.setValue(fromUnits(item.value));input.cursor=item.cursor;input.focused=item.focused;const lines=input.render(item.width).map(units);if(JSON.stringify(lines)!==JSON.stringify(item.lines))throw Error(JSON.stringify({index,width:item.width,cursor:item.cursor,actual:lines,expected:item.lines}));if(input.renderedStartColumn!==item.start)throw Error(JSON.stringify({index,start:input.renderedStartColumn,wanted:item.start,value:item.value,width:item.width,cursor:item.cursor}));if(JSON.stringify(calls)!==JSON.stringify(item.calls))throw Error('style '+index);for(const mouse of item.mouse){const result=input.handleMouse(mouse.event)??null;if(JSON.stringify(result)!==JSON.stringify(mouse.result)||input.cursor!==mouse.cursor)throw Error(JSON.stringify({index,mouse,result,cursor:input.cursor}));}}
    , "input-presentation-replay.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Input presentation: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Source6fb public Input callbacks private helper dispatch subclasses and class shape" {
    @import("../tui/keys.zig").setKittyProtocolActive(false);
    defer @import("../tui/keys.zig").setKittyProtocolActive(false);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const fixture = @embedFile("fixtures/input-callbacks-original-6fb.json");
    try js.define(engine, root, "inputCallbackFixture", try engine.checked(c.JS_ParseJSON(engine.context, fixture.ptr, fixture.len, "input-callbacks-original-6fb.json")));
    const result = engine.evalModule(
        \\import{Input,getKeybindings,setKeybindings}from'pi-tui';
        \\for(const [index,item]of inputCallbackFixture.structural.entries()){const invoke=new Function('Input','getKeybindings','setKeybindings','"use strict";'+item.script);let actual;try{actual=invoke(Input,getKeybindings,setKeybindings)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw Error(JSON.stringify({index,error:e.name,message:e.message,expected:item}))}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({index,actual,expected:item.result}));}
        \\const shape={name:Input.name,length:Input.length,own:Object.keys(new Input()),methods:Object.fromEntries(Object.getOwnPropertyNames(Input.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:Input.prototype[k].name,length:Input.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(Input.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(inputCallbackFixture.shape))throw Error(JSON.stringify({shape,expected:inputCallbackFixture.shape}));
    , "input-callback-replay.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Input callback: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn allocationError(engine: *Engine, err: anyerror) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |exception| {
        const message = c.JS_GetPropertyStr(engine.context, exception, "message");
        defer engine.freeValue(message);
        const text = c.JS_ToCString(engine.context, message);
        if (text != null) {
            defer c.JS_FreeCString(engine.context, text);
            if (std.mem.indexOf(u8, std.mem.span(text), "out of memory") != null) return error.OutOfMemory;
        }
    };
    return err;
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    @import("native_tui.zig").install(engine) catch |err| return allocationError(engine, err);
    const result = engine.evalModule(
        \\import{Input}from'pi-tui';const input=new Input({placeholder:'a界',placeholderStyle(text){return '['+text+']'}});input.focused=true;input.render(5);input.setValue('😀abc');input.handleInput('\x05');input.handleInput('\x7f');input.deleteToLineStart();input.yank();input.handleInput('\x01');input.deleteToLineEnd();input.yank();input.setValue('x');input.yankPop();input.undo();input.handleInput('\x1b[200~a\t');input.handleInput('b\r\n\x1b[201~');input.render(9);input.handleMouse({type:'press',button:'left',x:4,y:0});globalThis.retainedInput=input;
    , "input-allocation.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = engine.eval("retainedInput.render(7);delete globalThis.retainedInput", "input-retained.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return allocationError(engine, err);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb public Input callbacks rendering clone undo paste and retained state release every allocation failure" {
    @import("../tui/keys.zig").setKittyProtocolActive(false);
    defer @import("../tui/keys.zig").setKittyProtocolActive(false);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
test "Source6fb public Input exported CSI-u and visible width helpers use original UTF16 values" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const decoder = @embedFile("../tui/fixtures/kitty-printable-original-6fb.json");
    try js.define(engine, root, "inputDecoderFixture", try engine.checked(c.JS_ParseJSON(engine.context, decoder.ptr, decoder.len, "kitty-printable-original-6fb.json")));
    const widths = @embedFile("../tui/fixtures/input-width-original-6fb.json");
    try js.define(engine, root, "inputWidthFixture", try engine.checked(c.JS_ParseJSON(engine.context, widths.ptr, widths.len, "input-width-original-6fb.json")));
    const result = try engine.evalModule(
        \\import{decodeKittyPrintable,visibleWidth}from'pi-tui';if(decodeKittyPrintable.length!==1||visibleWidth.length!==1)throw Error('helper arity');for(const item of inputDecoderFixture.cases){const actual=decodeKittyPrintable(item.data);if((actual===undefined?null:actual.codePointAt(0))!==item.codepoint)throw Error('decoder '+JSON.stringify(item))}for(const item of inputWidthFixture.cases){const text=String.fromCharCode(...item.units);if(visibleWidth(text)!==item.visibleWidth)throw Error('visible width '+JSON.stringify(item));}
    , "input-public-helpers.mjs");
    engine.freeValue(result);
}
fn invokeVoid(engine: *Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const result = try js.invoke(engine, object, name, args);
    engine.freeValue(result);
}
fn matched(engine: *Engine, manager: c.JSValue, data: c.JSValue, action: [*:0]const u8) !bool {
    const name = try engine.checked(c.JS_NewString(engine.context, action));
    defer engine.freeValue(name);
    const result = try js.invoke(engine, manager, "matches", &.{ data, name });
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn callback(engine: *Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const function = try js.get(engine, object, name);
    defer engine.freeValue(function);
    if (c.JS_ToBool(engine.context, function) != 0) {
        const result = try js.call(engine, function, object, args);
        engine.freeValue(result);
    }
}
fn handleInput(engine: *Engine, object: c.JSValue, value: c.JSValue) anyerror!void {
    const original = try utf16.unitsAlloc(engine, value);
    defer engine.gpa.free(original);
    var data = original;
    const start = std.unicode.utf8ToUtf16LeStringLiteral("\x1b[200~");
    const end = std.unicode.utf8ToUtf16LeStringLiteral("\x1b[201~");
    var stripped: ?[]u16 = null;
    defer if (stripped) |text| engine.gpa.free(text);
    if (std.mem.indexOf(u16, data, start)) |at| {
        try set(engine, object, "isInPaste", c.pi_js_bool(engine.context, 1));
        try set(engine, object, "pasteBuffer", try utf16.string(engine, &.{}));
        const cleaned = try engine.gpa.alloc(u16, data.len - start.len);
        stripped = cleaned;
        @memcpy(cleaned[0..at], data[0..at]);
        @memcpy(cleaned[at..], data[at + start.len ..]);
        data = cleaned;
    }
    const in_paste = try js.get(engine, object, "isInPaste");
    defer engine.freeValue(in_paste);
    if (c.JS_ToBool(engine.context, in_paste) != 0) {
        const old = try unitsField(engine, object, "pasteBuffer");
        defer engine.gpa.free(old);
        const buffer = try engine.gpa.alloc(u16, old.len + data.len);
        defer engine.gpa.free(buffer);
        @memcpy(buffer[0..old.len], old);
        @memcpy(buffer[old.len..], data);
        try set(engine, object, "pasteBuffer", try utf16.string(engine, buffer));
        if (std.mem.indexOf(u16, buffer, end)) |at| {
            const pasted = try utf16.string(engine, buffer[0..at]);
            defer engine.freeValue(pasted);
            try invokeVoid(engine, object, "handlePaste", &.{pasted});
            try set(engine, object, "isInPaste", c.pi_js_bool(engine.context, 0));
            const remainder = try utf16.string(engine, buffer[at + end.len ..]);
            defer engine.freeValue(remainder);
            try set(engine, object, "pasteBuffer", try utf16.string(engine, &.{}));
            if (at + end.len < buffer.len) try invokeVoid(engine, object, "handleInput", &.{remainder});
        }
        return;
    }
    const current = try utf16.string(engine, data);
    defer engine.freeValue(current);
    const manager = try @import("native_keybindings.zig").getGlobal(engine);
    defer engine.freeValue(manager);
    if (try matched(engine, manager, current, "tui.select.cancel")) return callback(engine, object, "onEscape", &.{});
    if (try matched(engine, manager, current, "tui.editor.undo")) return invokeVoid(engine, object, "undo", &.{});
    if (try matched(engine, manager, current, "tui.input.submit") or std.mem.eql(u16, data, &.{'\n'})) {
        const text = try js.get(engine, object, "value");
        defer engine.freeValue(text);
        return callback(engine, object, "onSubmit", &.{text});
    }
    inline for (.{
        .{ "tui.editor.deleteCharBackward", "handleBackspace" },     .{ "tui.editor.deleteCharForward", "handleForwardDelete" },
        .{ "tui.editor.deleteWordBackward", "deleteWordBackwards" }, .{ "tui.editor.deleteWordForward", "deleteWordForward" },
        .{ "tui.editor.deleteToLineStart", "deleteToLineStart" },    .{ "tui.editor.deleteToLineEnd", "deleteToLineEnd" },
        .{ "tui.editor.yank", "yank" },                              .{ "tui.editor.yankPop", "yankPop" },
    }) |entry| if (try matched(engine, manager, current, entry[0])) return invokeVoid(engine, object, entry[1], &.{});
    inline for (.{ .{ "tui.editor.cursorLeft", input_mod.Action.left }, .{ "tui.editor.cursorRight", input_mod.Action.right }, .{ "tui.editor.cursorLineStart", input_mod.Action.start }, .{ "tui.editor.cursorLineEnd", input_mod.Action.end } }) |entry| {
        if (try matched(engine, manager, current, entry[0])) {
            return moveCursor(engine, object, entry[1]);
        }
    }
    inline for (.{ .{ "tui.editor.cursorWordLeft", "moveWordBackwards" }, .{ "tui.editor.cursorWordRight", "moveWordForwards" } }) |entry| {
        if (try matched(engine, manager, current, entry[0])) return invokeVoid(engine, object, entry[1], &.{});
    }
    // CSI-u-only decoding is supplied separately from the generic public
    // decoder, which also accepts modifyOtherKeys sequences.
    const encoded = try engine.toString(current);
    defer engine.gpa.free(encoded);
    const printable = try decodeKittyPrintable(engine, encoded);
    defer engine.freeValue(printable);
    if (!c.JS_IsUndefined(printable)) return invokeVoid(engine, object, "insertCharacter", &.{printable});
    for (data) |unit| if (unit < 32 or (unit >= 0x7f and unit <= 0x9f)) return;
    return invokeVoid(engine, object, "insertCharacter", &.{current});
}
pub fn decodeKittyPrintable(engine: *Engine, text: []const u8) !c.JSValue {
    const cp = @import("../tui/kitty_printable.zig").decode(text) orelse return c.pi_js_undefined();
    if (cp <= 0xffff) return utf16.string(engine, &.{@intCast(cp)});
    return utf16.string(engine, &.{ @as(u16, @intCast(0xd800 + ((cp - 0x10000) >> 10))), @as(u16, @intCast(0xdc00 + ((cp - 0x10000) & 0x3ff))) });
}
fn moveCursor(engine: *Engine, object: c.JSValue, action: input_mod.Action) !void {
    try setLast(engine, object, null);
    if (action == .start) return setCursor(engine, object, 0);
    const cursor = try integer(engine, object, "cursor");
    if (action == .left and cursor <= 0) return;
    const value = try js.get(engine, object, "value");
    defer engine.freeValue(value);
    if (action == .end) return set(engine, object, "cursor", try js.get(engine, value, "length"));
    if (action == .right and cursor >= try integer(engine, value, "length")) return;
    const fragment = try sliceValue(engine, value, if (action == .left) 0 else cursor, if (action == .left) cursor else null);
    defer engine.freeValue(fragment);
    const units = try utf16.unitsAlloc(engine, fragment);
    defer engine.gpa.free(units);
    const count: i64 = @intCast(if (units.len == 0) 1 else if (action == .left) units.len - graphemes.previous(units, units.len) else graphemes.next(units, 0));
    try setCursor(engine, object, if (action == .left) cursor - count else cursor + count);
}

//! Source Editor text, history and undo operations over ordinary JS fields.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const Method = @import("native_editor_methods.zig").Method;
pub fn supports(method: Method) bool {
    return switch (method) {
        .getText, .getExpandedText, .getCursor, .getLines, .getPaddingX, .getAutocompleteMaxVisible, .setPaddingX, .setAutocompleteMaxVisible, .normalizeText, .setCursorCol, .exitHistoryBrowsing, .navigateHistory, .setTextInternal, .pushUndoSnapshot, .undo, .setText, .insertTextAtCursor, .insertTextAtCursorInternal, .addToHistory, .isEditorEmpty, .isSlashMenuAllowed, .isAtStartOfMessage, .isInSlashCommandContext, .invalidate, .expandPasteMarkers, .cancelAutocompleteRequest, .clearAutocompleteUi, .cancelAutocomplete, .isShowingAutocomplete, .handlePaste, .addNewLine, .submitValue, .shouldSubmitOnBackslashEnter, .validPasteIds, .updateAutocomplete => true,
        else => false,
    };
}
fn clearHistory(engine: *Engine, object: c.JSValue) !void {
    try e.set(engine, object, "historyIndex", v.numeric(engine, -1));
    try e.set(engine, object, "historyDraft", c.pi_js_null());
}
fn setColumn(engine: *Engine, object: c.JSValue, column: c.JSValue) !void {
    try e.setState(engine, object, "cursorCol", c.JS_DupValue(engine.context, column));
    try e.set(engine, object, "preferredVisualCol", c.pi_js_null());
    try e.set(engine, object, "snappedFromCursorCol", c.pi_js_null());
}
fn normalize(engine: *Engine, text: c.JSValue) !c.JSValue {
    var current = c.JS_DupValue(engine.context, text);
    errdefer engine.freeValue(current);
    inline for (.{ .{ "\\r\\n", "\n" }, .{ "\\r", "\n" }, .{ "\\t", "    " } }) |entry| {
        const regex = try e.literalPattern(engine, entry[0], "g");
        defer engine.freeValue(regex);
        const replacement = try v.text(engine, entry[1]);
        defer engine.freeValue(replacement);
        const next = try js.invoke(engine, current, "replace", &.{ regex, replacement });
        engine.freeValue(current);
        current = next;
    }
    return current;
}
fn callbackFailure(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Editor: %s", @as([*:0]const u8, @errorName(err)));
}
fn decodePaste(engine: *Engine, args: []const c.JSValue) !c.JSValue {
    const numeric = try js.global(engine, "Number");
    defer engine.freeValue(numeric);
    const value = try js.call(engine, numeric, c.pi_js_undefined(), &.{v.arg(args, 1)});
    defer engine.freeValue(value);
    const cp = try v.number(engine, value);
    if ((cp >= 97 and cp <= 122) or (cp >= 65 and cp <= 90)) {
        const string_type = try js.global(engine, "String");
        defer engine.freeValue(string_type);
        return js.invoke(engine, string_type, "fromCharCode", &.{v.numeric(engine, cp - @as(f64, if (cp >= 97) 96 else 64))});
    }
    return c.JS_DupValue(engine.context, v.arg(args, 0));
}
fn decodePasteCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return decodePaste(engine, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| callbackFailure(engine, err);
}
fn printable(engine: *Engine, value: c.JSValue) !c.JSValue {
    if (try e.equalText(engine, value, "\n")) return c.pi_js_bool(engine.context, 1);
    const code = try js.invoke(engine, value, "charCodeAt", &.{v.numeric(engine, 0)});
    defer engine.freeValue(code);
    return c.pi_js_bool(engine.context, @intFromBool(try v.number(engine, code) >= 32));
}
fn printableCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return printable(engine, if (argc == 0) c.pi_js_undefined() else argv[0]) catch |err| callbackFailure(engine, err);
}
fn paste(engine: *Engine, object: c.JSValue, input: c.JSValue) !void {
    try e.invokeVoid(engine, object, "cancelAutocomplete", &.{});
    try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
    try e.setLast(engine, object, null);
    try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
    const regex = try e.literalPattern(engine, "\x1b\\[(\\d+);5u", "g");
    defer engine.freeValue(regex);
    const decode = try engine.checked(c.pi_js_function_magic(engine.context, decodePasteCallback, "", 2, 0));
    defer engine.freeValue(decode);
    const decoded = try js.invoke(engine, input, "replace", &.{ regex, decode });
    defer engine.freeValue(decoded);
    const clean = try js.invoke(engine, object, "normalizeText", &.{decoded});
    defer engine.freeValue(clean);
    const empty = try v.text(engine, "");
    defer engine.freeValue(empty);
    const split = try js.invoke(engine, clean, "split", &.{empty});
    defer engine.freeValue(split);
    const filter = try engine.checked(c.pi_js_function_magic(engine.context, printableCallback, "", 1, 0));
    defer engine.freeValue(filter);
    const accepted = try js.invoke(engine, split, "filter", &.{filter});
    defer engine.freeValue(accepted);
    var filtered = try js.invoke(engine, accepted, "join", &.{empty});
    defer engine.freeValue(filtered);
    const path_pattern = try e.literalPattern(engine, "^[/~.]", "");
    defer engine.freeValue(path_pattern);
    const is_path = try js.invoke(engine, path_pattern, "test", &.{filtered});
    defer engine.freeValue(is_path);
    if (v.truthy(engine, is_path)) {
        const current = try e.line(engine, object);
        defer engine.freeValue(current);
        const col = try e.cursor(engine, object, "cursorCol");
        const previous = if (col > 0) try js.getKey(engine, current, v.numeric(engine, col - 1)) else c.JS_DupValue(engine.context, empty);
        defer engine.freeValue(previous);
        if (v.truthy(engine, previous)) {
            const word_pattern = try e.literalPattern(engine, "\\w", "");
            defer engine.freeValue(word_pattern);
            const word = try js.invoke(engine, word_pattern, "test", &.{previous});
            defer engine.freeValue(word);
            if (v.truthy(engine, word)) {
                const space = try v.text(engine, " ");
                defer engine.freeValue(space);
                const next = try v.concat(engine, &.{ space, filtered });
                engine.freeValue(filtered);
                filtered = next;
            }
        }
    }
    const newline = try v.text(engine, "\n");
    defer engine.freeValue(newline);
    const list = try js.invoke(engine, filtered, "split", &.{newline});
    defer engine.freeValue(list);
    const line_count = try e.length(engine, list);
    const chars = try e.length(engine, filtered);
    if (line_count > 10 or chars > 1000) {
        const id = (try e.number(engine, object, "pasteCounter")) + 1;
        try e.set(engine, object, "pasteCounter", v.numeric(engine, id));
        const registry = try js.get(engine, object, "pastes");
        defer engine.freeValue(registry);
        try e.invokeVoid(engine, registry, "set", &.{ v.numeric(engine, id), filtered });
        const prefix = try v.text(engine, "[paste #");
        defer engine.freeValue(prefix);
        const middle = try v.text(engine, if (line_count > 10) " +" else " ");
        defer engine.freeValue(middle);
        const end = try v.text(engine, if (line_count > 10) " lines]" else " chars]");
        defer engine.freeValue(end);
        const marker = try v.concat(engine, &.{ prefix, v.numeric(engine, id), middle, v.numeric(engine, @floatFromInt(if (line_count > 10) line_count else chars)), end });
        defer engine.freeValue(marker);
        try e.invokeVoid(engine, object, "insertTextAtCursorInternal", &.{marker});
    } else try e.invokeVoid(engine, object, "insertTextAtCursorInternal", &.{filtered});
}
fn pasteReplacement(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, data[0]);
}
fn expand(engine: *Engine, object: c.JSValue, text: c.JSValue) !c.JSValue {
    const pastes = try js.get(engine, object, "pastes");
    defer engine.freeValue(pastes);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator_symbol = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator_symbol);
    var iterator = try js.Iterator.init(engine, pastes, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var result = c.JS_DupValue(engine.context, text);
    errdefer engine.freeValue(result);
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        var pair = try js.Iterator.init(engine, entry, iterator_symbol);
        defer pair.deinit();
        errdefer pair.closePreserving();
        const id = (try pair.next()) orelse c.pi_js_undefined();
        defer engine.freeValue(id);
        const content = if (pair.closed) c.pi_js_undefined() else (try pair.next()) orelse c.pi_js_undefined();
        defer engine.freeValue(content);
        try pair.close();
        const prefix = try v.text(engine, "\\[paste #");
        defer engine.freeValue(prefix);
        const pattern_end = try v.text(engine, "( (\\+\\d+ lines|\\d+ chars))?\\]");
        defer engine.freeValue(pattern_end);
        const source = try v.concat(engine, &.{ prefix, id, pattern_end });
        defer engine.freeValue(source);
        const flags = try v.text(engine, "g");
        defer engine.freeValue(flags);
        const regex = try js.builtin(engine, "RegExp", &.{ source, flags });
        defer engine.freeValue(regex);
        var data = [_]c.JSValue{content};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, pasteReplacement, "", 0, 0, 1, &data));
        defer engine.freeValue(callback);
        const next = try js.invoke(engine, result, "replace", &.{ regex, callback });
        engine.freeValue(result);
        result = next;
    }
    return result;
}
fn internalText(engine: *Engine, object: c.JSValue, text: c.JSValue, placement: c.JSValue) !void {
    const separator = try v.text(engine, "\n");
    defer engine.freeValue(separator);
    const list = try js.invoke(engine, text, "split", &.{separator});
    defer engine.freeValue(list);
    const count = try e.length(engine, list);
    if (count == 0) {
        const empty = try v.text(engine, "");
        defer engine.freeValue(empty);
        try js.push(engine, list, empty);
    }
    try e.setState(engine, object, "lines", c.JS_DupValue(engine.context, list));
    const start = try e.equalText(engine, placement, "start");
    const line_state = try e.state(engine, object);
    defer engine.freeValue(line_state);
    const index: usize = if (start) 0 else index: {
        const current_lines = try e.lines(engine, object);
        defer engine.freeValue(current_lines);
        break :index (try e.length(engine, current_lines)) - 1;
    };
    try e.set(engine, line_state, "cursorLine", v.numeric(engine, @floatFromInt(index)));
    const column: usize = if (start) 0 else col: {
        const last = try e.line(engine, object);
        defer engine.freeValue(last);
        break :col if (!v.truthy(engine, last)) 0 else try e.length(engine, last);
    };
    try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, @floatFromInt(column))});
    try e.set(engine, object, "scrollOffset", v.numeric(engine, 0));
    try e.notify(engine, object);
}
fn appendIterable(engine: *Engine, target: c.JSValue, value: c.JSValue) !void {
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator_symbol = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator_symbol);
    var iterator = try js.Iterator.init(engine, value, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        try js.push(engine, target, item);
    }
}
fn insert(engine: *Engine, object: c.JSValue, value: c.JSValue) !void {
    if (!v.truthy(engine, value)) return;
    const normalized = try js.invoke(engine, object, "normalizeText", &.{value});
    defer engine.freeValue(normalized);
    const separator = try v.text(engine, "\n");
    defer engine.freeValue(separator);
    const inserted = try js.invoke(engine, normalized, "split", &.{separator});
    defer engine.freeValue(inserted);
    const inserted_count = try e.length(engine, inserted);
    const current_line = try e.line(engine, object);
    defer engine.freeValue(current_line);
    const column = try e.cursor(engine, object, "cursorCol");
    const before = try js.invoke(engine, current_line, "slice", &.{ v.numeric(engine, 0), v.numeric(engine, column) });
    defer engine.freeValue(before);
    const after = try js.invoke(engine, current_line, "slice", &.{v.numeric(engine, column)});
    defer engine.freeValue(after);
    const first = try v.fieldAt(engine, inserted, 0);
    defer engine.freeValue(first);
    if (inserted_count == 1) {
        try e.replaceLine(engine, object, try v.concat(engine, &.{ before, first, after }));
        try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, column + @as(f64, @floatFromInt(try e.length(engine, first))))});
    } else {
        const replacement = try js.array(engine);
        defer engine.freeValue(replacement);
        const list = try e.lines(engine, object);
        defer engine.freeValue(list);
        const line_index = try e.cursor(engine, object, "cursorLine");
        const preceding = try js.invoke(engine, list, "slice", &.{ v.numeric(engine, 0), v.numeric(engine, line_index) });
        defer engine.freeValue(preceding);
        try appendIterable(engine, replacement, preceding);
        const first_line = try v.concat(engine, &.{ before, first });
        defer engine.freeValue(first_line);
        try js.push(engine, replacement, first_line);
        const middle = try js.invoke(engine, inserted, "slice", &.{ v.numeric(engine, 1), v.numeric(engine, -1) });
        defer engine.freeValue(middle);
        try appendIterable(engine, replacement, middle);
        const last = try v.fieldAt(engine, inserted, @floatFromInt(inserted_count - 1));
        defer engine.freeValue(last);
        const last_line = try v.concat(engine, &.{ last, after });
        defer engine.freeValue(last_line);
        try js.push(engine, replacement, last_line);
        const following = try js.invoke(engine, list, "slice", &.{v.numeric(engine, line_index + 1)});
        defer engine.freeValue(following);
        try appendIterable(engine, replacement, following);
        try e.setState(engine, object, "lines", c.JS_DupValue(engine.context, replacement));
        try e.setState(engine, object, "cursorLine", v.numeric(engine, line_index + @as(f64, @floatFromInt(inserted_count - 1))));
        try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, @floatFromInt(try e.length(engine, last)))});
    }
    try e.notify(engine, object);
}
pub fn operation(engine: *Engine, object: c.JSValue, method: Method, args: []const c.JSValue) !?c.JSValue {
    const first = v.arg(args, 0);
    switch (method) {
        .updateAutocomplete => {
            const state = try js.get(engine, object, "autocompleteState");
            defer engine.freeValue(state);
            if (!v.truthy(engine, state)) return c.pi_js_undefined();
            const provider = try js.get(engine, object, "autocompleteProvider");
            defer engine.freeValue(provider);
            if (!v.truthy(engine, provider)) return c.pi_js_undefined();
            const options = try js.object(engine);
            defer engine.freeValue(options);
            const current = try js.get(engine, object, "autocompleteState");
            defer engine.freeValue(current);
            try js.define(engine, options, "force", c.pi_js_bool(engine.context, @intFromBool(try e.equalText(engine, current, "force"))));
            try js.define(engine, options, "explicitTab", c.pi_js_bool(engine.context, 0));
            try e.invokeVoid(engine, object, "requestAutocomplete", &.{options});
        },
        .validPasteIds => {
            const registry = try js.get(engine, object, "pastes");
            defer engine.freeValue(registry);
            const keys = try js.invoke(engine, registry, "keys", &.{});
            defer engine.freeValue(keys);
            return try js.builtin(engine, "Set", &.{keys});
        },
        .handlePaste => try paste(engine, object, first),
        .addNewLine => {
            try e.invokeVoid(engine, object, "cancelAutocomplete", &.{});
            try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
            try e.setLast(engine, object, null);
            try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
            const current = try e.line(engine, object);
            defer engine.freeValue(current);
            const col = try e.cursor(engine, object, "cursorCol");
            const before = try js.invoke(engine, current, "slice", &.{ v.numeric(engine, 0), v.numeric(engine, col) });
            defer engine.freeValue(before);
            const after = try js.invoke(engine, current, "slice", &.{v.numeric(engine, col)});
            defer engine.freeValue(after);
            try e.replaceLine(engine, object, c.JS_DupValue(engine.context, before));
            const list = try e.lines(engine, object);
            defer engine.freeValue(list);
            const row = try e.cursor(engine, object, "cursorLine");
            try e.invokeVoid(engine, list, "splice", &.{ v.numeric(engine, row + 1), v.numeric(engine, 0), after });
            try e.setState(engine, object, "cursorLine", v.numeric(engine, (try e.cursor(engine, object, "cursorLine")) + 1));
            try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, 0)});
            try e.notify(engine, object);
        },
        .shouldSubmitOnBackslashEnter => {
            const disabled = try js.get(engine, object, "disableSubmit");
            defer engine.freeValue(disabled);
            if (v.truthy(engine, disabled)) return c.pi_js_bool(engine.context, 0);
            const input = try engine.toString(first);
            defer engine.gpa.free(input);
            if (!@import("../tui/keys.zig").matchesKey(input, "enter")) return c.pi_js_bool(engine.context, 0);
            const submit = try v.text(engine, "tui.input.submit");
            defer engine.freeValue(submit);
            const keys = try js.invoke(engine, v.arg(args, 1), "getKeys", &.{submit});
            defer engine.freeValue(keys);
            var has_shift = false;
            inline for (.{ "shift+enter", "shift+return" }) |name| {
                if (!has_shift) {
                    const key = try v.text(engine, name);
                    defer engine.freeValue(key);
                    const found = try js.invoke(engine, keys, "includes", &.{key});
                    defer engine.freeValue(found);
                    has_shift = v.truthy(engine, found);
                }
            }
            if (!has_shift) return c.pi_js_bool(engine.context, 0);
            const current = try e.line(engine, object);
            defer engine.freeValue(current);
            const col = try e.cursor(engine, object, "cursorCol");
            if (col <= 0) return c.pi_js_bool(engine.context, 0);
            const previous = try js.getKey(engine, current, v.numeric(engine, col - 1));
            defer engine.freeValue(previous);
            return c.pi_js_bool(engine.context, @intFromBool(try e.equalText(engine, previous, "\\")));
        },
        .submitValue => {
            try e.invokeVoid(engine, object, "cancelAutocomplete", &.{});
            const text = try e.text(engine, object);
            defer engine.freeValue(text);
            const expanded = try js.invoke(engine, object, "expandPasteMarkers", &.{text});
            defer engine.freeValue(expanded);
            const result = try js.invoke(engine, expanded, "trim", &.{});
            defer engine.freeValue(result);
            const next = try js.object(engine);
            var transferred = false;
            defer if (!transferred) engine.freeValue(next);
            const list = try js.array(engine);
            defer engine.freeValue(list);
            const empty = try v.text(engine, "");
            defer engine.freeValue(empty);
            try js.push(engine, list, empty);
            try js.define(engine, next, "lines", c.JS_DupValue(engine.context, list));
            try js.define(engine, next, "cursorLine", v.numeric(engine, 0));
            try js.define(engine, next, "cursorCol", v.numeric(engine, 0));
            transferred = true;
            try e.set(engine, object, "state", next);
            const registry = try js.get(engine, object, "pastes");
            defer engine.freeValue(registry);
            try e.invokeVoid(engine, registry, "clear", &.{});
            try e.set(engine, object, "pasteCounter", v.numeric(engine, 0));
            try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
            try e.set(engine, object, "scrollOffset", v.numeric(engine, 0));
            const undo = try js.get(engine, object, "undoStack");
            defer engine.freeValue(undo);
            try e.invokeVoid(engine, undo, "clear", &.{});
            try e.setLast(engine, object, null);
            inline for (.{ "onChange", "onSubmit" }) |name| {
                const callback = try js.get(engine, object, name);
                defer engine.freeValue(callback);
                if (v.truthy(engine, callback)) {
                    const ignored = try js.call(engine, callback, object, &.{if (comptime std.mem.eql(u8, name, "onChange")) empty else result});
                    engine.freeValue(ignored);
                }
            }
        },
        .navigateHistory => {
            try e.setLast(engine, object, null);
            const history = try js.get(engine, object, "history");
            defer engine.freeValue(history);
            if (try e.length(engine, history) == 0) return c.pi_js_undefined();
            const current = try e.number(engine, object, "historyIndex");
            const next = current - try v.number(engine, first);
            if (next < -1 or next >= @as(f64, @floatFromInt(try e.length(engine, history)))) return c.pi_js_undefined();
            if (current == -1 and next >= 0) {
                try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
                const clone = try js.global(engine, "structuredClone");
                defer engine.freeValue(clone);
                const current_state = try e.state(engine, object);
                defer engine.freeValue(current_state);
                try e.set(engine, object, "historyDraft", if (c.JS_IsUndefined(clone)) try @import("native_structured_clone.zig").clone(engine, current_state) else try js.call(engine, clone, c.pi_js_undefined(), &.{current_state}));
            }
            try e.set(engine, object, "historyIndex", v.numeric(engine, next));
            if (next == -1) {
                const draft = try js.get(engine, object, "historyDraft");
                defer engine.freeValue(draft);
                try e.set(engine, object, "historyDraft", c.pi_js_null());
                if (v.truthy(engine, draft)) {
                    try e.set(engine, object, "state", c.JS_DupValue(engine.context, draft));
                    try e.set(engine, object, "preferredVisualCol", c.pi_js_null());
                    try e.set(engine, object, "snappedFromCursorCol", c.pi_js_null());
                    try e.set(engine, object, "scrollOffset", v.numeric(engine, 0));
                    try e.notify(engine, object);
                } else {
                    const empty = try v.text(engine, "");
                    defer engine.freeValue(empty);
                    try e.invokeVoid(engine, object, "setTextInternal", &.{empty});
                }
            } else {
                const item = try v.fieldAt(engine, history, next);
                defer engine.freeValue(item);
                const text = if (v.truthy(engine, item)) c.JS_DupValue(engine.context, item) else try v.text(engine, "");
                defer engine.freeValue(text);
                const placement = try v.text(engine, if (c.JS_IsStrictEqual(engine.context, first, v.numeric(engine, -1))) "start" else "end");
                defer engine.freeValue(placement);
                try e.invokeVoid(engine, object, "setTextInternal", &.{ text, placement });
            }
        },
        .expandPasteMarkers => return try expand(engine, object, first),
        .cancelAutocompleteRequest => {
            try e.set(engine, object, "autocompleteStartToken", v.numeric(engine, (try e.number(engine, object, "autocompleteStartToken")) + 1));
            const timer = try js.get(engine, object, "autocompleteDebounceTimer");
            defer engine.freeValue(timer);
            if (v.truthy(engine, timer)) {
                const clear = try js.global(engine, "clearTimeout");
                defer engine.freeValue(clear);
                const ignored = try js.call(engine, clear, c.pi_js_undefined(), &.{timer});
                engine.freeValue(ignored);
                try e.set(engine, object, "autocompleteDebounceTimer", c.pi_js_undefined());
            }
            const controller = try js.get(engine, object, "autocompleteAbort");
            defer engine.freeValue(controller);
            if (!c.JS_IsNull(controller) and !c.JS_IsUndefined(controller)) try e.invokeVoid(engine, controller, "abort", &.{});
            try e.set(engine, object, "autocompleteAbort", c.pi_js_undefined());
        },
        .clearAutocompleteUi => {
            try e.set(engine, object, "autocompleteState", c.pi_js_null());
            try e.set(engine, object, "autocompleteList", c.pi_js_undefined());
            try e.set(engine, object, "autocompletePrefix", try v.text(engine, ""));
        },
        .cancelAutocomplete => {
            try e.invokeVoid(engine, object, "cancelAutocompleteRequest", &.{});
            try e.invokeVoid(engine, object, "clearAutocompleteUi", &.{});
        },
        .isShowingAutocomplete => {
            const active = try js.get(engine, object, "autocompleteState");
            defer engine.freeValue(active);
            return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsNull(active)));
        },
        .getText => return try e.text(engine, object),
        .getExpandedText => {
            const text = try e.text(engine, object);
            defer engine.freeValue(text);
            return try js.invoke(engine, object, "expandPasteMarkers", &.{text});
        },
        .getCursor => {
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            const current_line = try e.state(engine, object);
            defer engine.freeValue(current_line);
            try js.define(engine, result, "line", try js.get(engine, current_line, "cursorLine"));
            const current_col = try e.state(engine, object);
            defer engine.freeValue(current_col);
            try js.define(engine, result, "col", try js.get(engine, current_col, "cursorCol"));
            return result;
        },
        .getLines => {
            const list = try e.lines(engine, object);
            defer engine.freeValue(list);
            const symbol = try js.global(engine, "Symbol");
            defer engine.freeValue(symbol);
            const iterator = try js.get(engine, symbol, "iterator");
            defer engine.freeValue(iterator);
            return try js.collect(engine, list, iterator);
        },
        .getPaddingX => return try js.get(engine, object, "paddingX"),
        .getAutocompleteMaxVisible => return try js.get(engine, object, "autocompleteMaxVisible"),
        .setPaddingX, .setAutocompleteMaxVisible => {
            var value: f64 = if (method == .setPaddingX) 0 else 5;
            if (c.JS_IsNumber(first)) {
                const incoming = try v.number(engine, first);
                if (std.math.isFinite(incoming)) value = if (method == .setPaddingX) @max(0, @floor(incoming)) else @max(3, @min(20, @floor(incoming)));
            }
            const name: [*:0]const u8 = if (method == .setPaddingX) "paddingX" else "autocompleteMaxVisible";
            const previous = try js.get(engine, object, name);
            defer engine.freeValue(previous);
            const next = v.numeric(engine, value);
            if (!c.JS_IsStrictEqual(engine.context, previous, next)) {
                try e.set(engine, object, name, next);
                try e.renderRequest(engine, object);
            }
        },
        .normalizeText => return try normalize(engine, first),
        .setCursorCol => try setColumn(engine, object, first),
        .exitHistoryBrowsing => try clearHistory(engine, object),
        .setTextInternal => try internalText(engine, object, first, v.arg(args, 1)),
        .pushUndoSnapshot => try e.snapshot(engine, object),
        .undo => {
            try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
            const undo = try js.get(engine, object, "undoStack");
            defer engine.freeValue(undo);
            const item = try js.invoke(engine, undo, "pop", &.{});
            defer engine.freeValue(item);
            if (!v.truthy(engine, item)) return c.pi_js_undefined();
            const current = try e.state(engine, object);
            defer engine.freeValue(current);
            const saved = try js.get(engine, item, "state");
            defer engine.freeValue(saved);
            const object_constructor = try js.global(engine, "Object");
            defer engine.freeValue(object_constructor);
            try e.invokeVoid(engine, object_constructor, "assign", &.{ current, saved });
            inline for (.{ "pastes", "pasteCounter" }) |name| try e.set(engine, object, name, try js.get(engine, item, name));
            try e.setLast(engine, object, null);
            try e.set(engine, object, "preferredVisualCol", c.pi_js_null());
            try e.notify(engine, object);
        },
        .setText => {
            try e.invokeVoid(engine, object, "cancelAutocomplete", &.{});
            try e.setLast(engine, object, null);
            try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
            const normalized = try js.invoke(engine, object, "normalizeText", &.{first});
            defer engine.freeValue(normalized);
            const previous = try js.invoke(engine, object, "getText", &.{});
            defer engine.freeValue(previous);
            if (!c.JS_IsStrictEqual(engine.context, previous, normalized)) try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
            const pastes = try js.get(engine, object, "pastes");
            defer engine.freeValue(pastes);
            try e.invokeVoid(engine, pastes, "clear", &.{});
            try e.set(engine, object, "pasteCounter", v.numeric(engine, 0));
            try e.invokeVoid(engine, object, "setTextInternal", &.{normalized});
        },
        .insertTextAtCursor => {
            if (!v.truthy(engine, first)) return c.pi_js_undefined();
            try e.invokeVoid(engine, object, "cancelAutocomplete", &.{});
            try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
            try e.setLast(engine, object, null);
            try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
            try e.invokeVoid(engine, object, "insertTextAtCursorInternal", &.{first});
        },
        .insertTextAtCursorInternal => try insert(engine, object, first),
        .addToHistory => {
            const trimmed = try js.invoke(engine, first, "trim", &.{});
            defer engine.freeValue(trimmed);
            if (!v.truthy(engine, trimmed)) return c.pi_js_undefined();
            const history = try js.get(engine, object, "history");
            defer engine.freeValue(history);
            const count = try e.length(engine, history);
            if (count > 0) {
                const recent = try v.fieldAt(engine, history, 0);
                defer engine.freeValue(recent);
                if (c.JS_IsStrictEqual(engine.context, recent, trimmed)) return c.pi_js_undefined();
            }
            try e.invokeVoid(engine, history, "unshift", &.{trimmed});
            if (try e.length(engine, history) > 100) try e.invokeVoid(engine, history, "pop", &.{});
        },
        .isEditorEmpty => {
            const list = try e.lines(engine, object);
            defer engine.freeValue(list);
            if (try e.length(engine, list) != 1) return c.pi_js_bool(engine.context, 0);
            const current = try e.lines(engine, object);
            defer engine.freeValue(current);
            const head = try v.fieldAt(engine, current, 0);
            defer engine.freeValue(head);
            return c.pi_js_bool(engine.context, @intFromBool(try e.equalText(engine, head, "")));
        },
        .isSlashMenuAllowed => {
            const current = try e.state(engine, object);
            defer engine.freeValue(current);
            const index = try js.get(engine, current, "cursorLine");
            defer engine.freeValue(index);
            return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, index, v.numeric(engine, 0))));
        },
        .isAtStartOfMessage, .isInSlashCommandContext => {
            const allowed = try js.invoke(engine, object, "isSlashMenuAllowed", &.{});
            defer engine.freeValue(allowed);
            if (!v.truthy(engine, allowed)) return c.pi_js_bool(engine.context, 0);
            const before = if (method == .isInSlashCommandContext) c.JS_DupValue(engine.context, first) else blk: {
                const current_line = try e.line(engine, object);
                defer engine.freeValue(current_line);
                break :blk try js.invoke(engine, current_line, "slice", &.{ v.numeric(engine, 0), v.numeric(engine, try e.cursor(engine, object, "cursorCol")) });
            };
            defer engine.freeValue(before);
            const trimmed = try js.invoke(engine, before, if (method == .isInSlashCommandContext) "trimStart" else "trim", &.{});
            defer engine.freeValue(trimmed);
            if (method == .isAtStartOfMessage) {
                if (try e.equalText(engine, trimmed, "")) return c.pi_js_bool(engine.context, 1);
                const second_trim = try js.invoke(engine, before, "trim", &.{});
                defer engine.freeValue(second_trim);
                return c.pi_js_bool(engine.context, @intFromBool(try e.equalText(engine, second_trim, "/")));
            }
            const slash = try v.text(engine, "/");
            defer engine.freeValue(slash);
            return try js.invoke(engine, trimmed, "startsWith", &.{slash});
        },
        .invalidate => {},
        else => return null,
    }
    return c.pi_js_undefined();
}

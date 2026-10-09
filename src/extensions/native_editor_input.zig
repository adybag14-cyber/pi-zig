//! Source Editor input dispatch. Keybindings and text are ordinary JS authority.
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const keys = @import("../tui/keys.zig");
threadlocal var input_depth: usize = 0;
fn matches(engine: *Engine, kb: c.JSValue, data: c.JSValue, name: []const u8) !bool {
    const action = try v.text(engine, name);
    defer engine.freeValue(action);
    const result = try js.invoke(engine, kb, "matches", &.{ data, action });
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn equal(engine: *Engine, data: c.JSValue, bytes: []const u8) !bool {
    return e.equalText(engine, data, bytes);
}
fn includes(engine: *Engine, data: c.JSValue, bytes: []const u8) !bool {
    const needle = try v.text(engine, bytes);
    defer engine.freeValue(needle);
    const result = try js.invoke(engine, data, "includes", &.{needle});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn call0(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !void {
    try e.invokeVoid(engine, object, name, &.{});
}
fn call1(engine: *Engine, object: c.JSValue, name: [*:0]const u8, arg: c.JSValue) !void {
    try e.invokeVoid(engine, object, name, &.{arg});
}
fn boolMethod(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const result = try js.invoke(engine, object, name, &.{});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn decoded(engine: *Engine, data: c.JSValue) !c.JSValue {
    const text = try engine.toString(data);
    defer engine.gpa.free(text);
    const value = try keys.decodePrintableKey(engine.gpa, text) orelse return c.pi_js_undefined();
    defer engine.gpa.free(value);
    return v.text(engine, value);
}
fn key(engine: *Engine, data: c.JSValue, name: []const u8) !bool {
    const text = try engine.toString(data);
    defer engine.gpa.free(text);
    return keys.matchesKey(text, name);
}
fn firstCode(engine: *Engine, data: c.JSValue) !f64 {
    const value = try js.invoke(engine, data, "charCodeAt", &.{v.numeric(engine, 0)});
    defer engine.freeValue(value);
    return v.number(engine, value);
}
fn applySelected(engine: *Engine, object: c.JSValue, list: c.JSValue) !bool {
    const selected = try js.invoke(engine, list, "getSelectedItem", &.{});
    defer engine.freeValue(selected);
    if (!v.truthy(engine, selected)) return false;
    const provider = try js.get(engine, object, "autocompleteProvider");
    defer engine.freeValue(provider);
    if (!v.truthy(engine, provider)) return false;
    try call0(engine, object, "pushUndoSnapshot");
    try e.setLast(engine, object, null);
    const lines = try e.lines(engine, object);
    defer engine.freeValue(lines);
    const state1 = try e.state(engine, object);
    defer engine.freeValue(state1);
    const row = try js.get(engine, state1, "cursorLine");
    defer engine.freeValue(row);
    const state2 = try e.state(engine, object);
    defer engine.freeValue(state2);
    const col = try js.get(engine, state2, "cursorCol");
    defer engine.freeValue(col);
    const prefix = try js.get(engine, object, "autocompletePrefix");
    defer engine.freeValue(prefix);
    const result = try js.invoke(engine, provider, "applyCompletion", &.{ lines, row, col, selected, prefix });
    defer engine.freeValue(result);
    try e.setState(engine, object, "lines", try js.get(engine, result, "lines"));
    try e.setState(engine, object, "cursorLine", try js.get(engine, result, "cursorLine"));
    const new_col = try js.get(engine, result, "cursorCol");
    defer engine.freeValue(new_col);
    try call1(engine, object, "setCursorCol", new_col);
    return true;
}
pub fn input(engine: *Engine, object: c.JSValue, original: c.JSValue) !c.JSValue {
    if (input_depth >= 64) return engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
    input_depth += 1;
    defer input_depth -= 1;
    const kb = try @import("native_keybindings.zig").getGlobal(engine);
    defer engine.freeValue(kb);
    var data = c.JS_DupValue(engine.context, original);
    defer engine.freeValue(data);
    const jump = try js.get(engine, object, "jumpMode");
    defer engine.freeValue(jump);
    if (!c.JS_IsNull(jump)) {
        if (try matches(engine, kb, data, "tui.editor.jumpForward") or try matches(engine, kb, data, "tui.editor.jumpBackward")) {
            try e.set(engine, object, "jumpMode", c.pi_js_null());
            return c.pi_js_undefined();
        }
        const printable = try decoded(engine, data);
        defer engine.freeValue(printable);
        const value = if (!c.JS_IsUndefined(printable)) c.JS_DupValue(engine.context, printable) else if (try firstCode(engine, data) >= 32) c.JS_DupValue(engine.context, data) else c.pi_js_undefined();
        defer engine.freeValue(value);
        const direction = try js.get(engine, object, "jumpMode");
        defer engine.freeValue(direction);
        try e.set(engine, object, "jumpMode", c.pi_js_null());
        if (!c.JS_IsUndefined(value)) {
            try e.invokeVoid(engine, object, "jumpToChar", &.{ value, direction });
            return c.pi_js_undefined();
        }
    }
    if (try includes(engine, data, "\x1b[200~")) {
        try e.set(engine, object, "isInPaste", c.pi_js_bool(engine.context, 1));
        try e.set(engine, object, "pasteBuffer", try v.text(engine, ""));
        const start = try v.text(engine, "\x1b[200~");
        defer engine.freeValue(start);
        const empty = try v.text(engine, "");
        defer engine.freeValue(empty);
        const next = try js.invoke(engine, data, "replace", &.{ start, empty });
        engine.freeValue(data);
        data = next;
    }
    const pasting = try js.get(engine, object, "isInPaste");
    defer engine.freeValue(pasting);
    if (v.truthy(engine, pasting)) {
        const previous = try js.get(engine, object, "pasteBuffer");
        defer engine.freeValue(previous);
        try e.set(engine, object, "pasteBuffer", try v.concat(engine, &.{ previous, data }));
        const buffer = try js.get(engine, object, "pasteBuffer");
        defer engine.freeValue(buffer);
        const end_marker = try v.text(engine, "\x1b[201~");
        defer engine.freeValue(end_marker);
        const found = try js.invoke(engine, buffer, "indexOf", &.{end_marker});
        defer engine.freeValue(found);
        if (!c.JS_IsStrictEqual(engine.context, found, v.numeric(engine, -1))) {
            const content = try js.invoke(engine, buffer, "substring", &.{ v.numeric(engine, 0), found });
            defer engine.freeValue(content);
            if (try e.length(engine, content) > 0) try call1(engine, object, "handlePaste", content);
            try e.set(engine, object, "isInPaste", c.pi_js_bool(engine.context, 0));
            const live_buffer = try js.get(engine, object, "pasteBuffer");
            defer engine.freeValue(live_buffer);
            const remaining = try js.invoke(engine, live_buffer, "substring", &.{v.numeric(engine, (try v.number(engine, found)) + 6)});
            defer engine.freeValue(remaining);
            try e.set(engine, object, "pasteBuffer", try v.text(engine, ""));
            if (try e.length(engine, remaining) > 0) try call1(engine, object, "handleInput", remaining);
        }
        return c.pi_js_undefined();
    }
    if (try matches(engine, kb, data, "tui.input.copy")) return c.pi_js_undefined();
    if (try matches(engine, kb, data, "tui.editor.undo")) {
        try call0(engine, object, "undo");
        return c.pi_js_undefined();
    }
    const active = try js.get(engine, object, "autocompleteState");
    defer engine.freeValue(active);
    if (v.truthy(engine, active)) {
        const list = try js.get(engine, object, "autocompleteList");
        defer engine.freeValue(list);
        if (v.truthy(engine, list)) {
            if (try matches(engine, kb, data, "tui.select.cancel")) {
                try call0(engine, object, "cancelAutocomplete");
                return c.pi_js_undefined();
            }
            if (try matches(engine, kb, data, "tui.select.up") or try matches(engine, kb, data, "tui.select.down")) {
                try call1(engine, list, "handleInput", data);
                return c.pi_js_undefined();
            }
            if (try matches(engine, kb, data, "tui.input.tab")) {
                if (try applySelected(engine, object, list)) {
                    try call0(engine, object, "cancelAutocomplete");
                    try e.notify(engine, object);
                }
                return c.pi_js_undefined();
            }
            if (try matches(engine, kb, data, "tui.select.confirm")) {
                if (try applySelected(engine, object, list)) {
                    const prefix = try js.get(engine, object, "autocompletePrefix");
                    defer engine.freeValue(prefix);
                    const slash = try v.text(engine, "/");
                    defer engine.freeValue(slash);
                    const command = try js.invoke(engine, prefix, "startsWith", &.{slash});
                    defer engine.freeValue(command);
                    try call0(engine, object, "cancelAutocomplete");
                    if (!v.truthy(engine, command)) {
                        try e.notify(engine, object);
                        return c.pi_js_undefined();
                    }
                }
            }
        }
    }
    if (try matches(engine, kb, data, "tui.input.tab")) {
        const current = try js.get(engine, object, "autocompleteState");
        defer engine.freeValue(current);
        if (!v.truthy(engine, current)) {
            try call0(engine, object, "handleTabCompletion");
            return c.pi_js_undefined();
        }
    }
    inline for (.{
        .{ "tui.editor.deleteToLineEnd", "deleteToEndOfLine" },      .{ "tui.editor.deleteToLineStart", "deleteToStartOfLine" },
        .{ "tui.editor.deleteWordBackward", "deleteWordBackwards" }, .{ "tui.editor.deleteWordForward", "deleteWordForward" },
    }) |entry| if (try matches(engine, kb, data, entry[0])) {
        try call0(engine, object, entry[1]);
        return c.pi_js_undefined();
    };
    if (try matches(engine, kb, data, "tui.editor.deleteCharBackward") or try key(engine, data, "shift+backspace")) {
        try call0(engine, object, "handleBackspace");
        return c.pi_js_undefined();
    }
    if (try matches(engine, kb, data, "tui.editor.deleteCharForward") or try key(engine, data, "shift+delete")) {
        try call0(engine, object, "handleForwardDelete");
        return c.pi_js_undefined();
    }
    inline for (.{ .{ "tui.editor.yank", "yank" }, .{ "tui.editor.yankPop", "yankPop" } }) |entry| if (try matches(engine, kb, data, entry[0])) {
        try call0(engine, object, entry[1]);
        return c.pi_js_undefined();
    };
    inline for (.{ .{ "tui.editor.historyPrevious", -1 }, .{ "tui.editor.historyNext", 1 } }) |entry| if (try matches(engine, kb, data, entry[0])) {
        try call0(engine, object, "cancelAutocomplete");
        try call1(engine, object, "navigateHistory", v.numeric(engine, entry[1]));
        return c.pi_js_undefined();
    };
    inline for (.{
        .{ "tui.editor.cursorLineStart", "moveToLineStart" },  .{ "tui.editor.cursorLineEnd", "moveToLineEnd" },
        .{ "tui.editor.cursorWordLeft", "moveWordBackwards" }, .{ "tui.editor.cursorWordRight", "moveWordForwards" },
    }) |entry| if (try matches(engine, kb, data, entry[0])) {
        try call0(engine, object, entry[1]);
        return c.pi_js_undefined();
    };
    const length = try e.length(engine, data);
    if (try matches(engine, kb, data, "tui.input.newLine") or (try firstCode(engine, data) == 10 and length > 1) or try equal(engine, data, "\x1b\r") or try equal(engine, data, "\x1b[13;2~") or (length > 1 and try includes(engine, data, "\x1b") and try includes(engine, data, "\r")) or (try equal(engine, data, "\n") and length == 1)) {
        const backslash = try js.invoke(engine, object, "shouldSubmitOnBackslashEnter", &.{ data, kb });
        defer engine.freeValue(backslash);
        if (v.truthy(engine, backslash)) {
            try call0(engine, object, "handleBackspace");
            try call0(engine, object, "submitValue");
        } else try call0(engine, object, "addNewLine");
        return c.pi_js_undefined();
    }
    if (try matches(engine, kb, data, "tui.input.submit")) {
        const disabled = try js.get(engine, object, "disableSubmit");
        defer engine.freeValue(disabled);
        if (v.truthy(engine, disabled)) return c.pi_js_undefined();
        const line = try e.line(engine, object);
        defer engine.freeValue(line);
        const col = try e.cursor(engine, object, "cursorCol");
        const previous = if (col > 0) try js.getKey(engine, line, v.numeric(engine, col - 1)) else c.pi_js_undefined();
        defer engine.freeValue(previous);
        if (col > 0 and try equal(engine, previous, "\\")) {
            try call0(engine, object, "handleBackspace");
            try call0(engine, object, "addNewLine");
        } else try call0(engine, object, "submitValue");
        return c.pi_js_undefined();
    }
    if (try matches(engine, kb, data, "tui.editor.cursorUp")) {
        const first = try boolMethod(engine, object, "isOnFirstVisualLine");
        const col_state = try e.state(engine, object);
        defer engine.freeValue(col_state);
        const col = try js.get(engine, col_state, "cursorCol");
        defer engine.freeValue(col);
        if (first and (try boolMethod(engine, object, "isEditorEmpty") or try e.number(engine, object, "historyIndex") > -1 or c.JS_IsStrictEqual(engine.context, col, v.numeric(engine, 0)))) try call1(engine, object, "navigateHistory", v.numeric(engine, -1)) else if (try boolMethod(engine, object, "isOnFirstVisualLine")) try call0(engine, object, "moveToLineStart") else try e.invokeVoid(engine, object, "moveCursor", &.{ v.numeric(engine, -1), v.numeric(engine, 0) });
        return c.pi_js_undefined();
    }
    if (try matches(engine, kb, data, "tui.editor.cursorDown")) {
        if (try e.number(engine, object, "historyIndex") > -1 and try boolMethod(engine, object, "isOnLastVisualLine")) try call1(engine, object, "navigateHistory", v.numeric(engine, 1)) else if (try boolMethod(engine, object, "isOnLastVisualLine")) try call0(engine, object, "moveToLineEnd") else try e.invokeVoid(engine, object, "moveCursor", &.{ v.numeric(engine, 1), v.numeric(engine, 0) });
        return c.pi_js_undefined();
    }
    inline for (.{ .{ "tui.editor.cursorRight", 1 }, .{ "tui.editor.cursorLeft", -1 } }) |entry| if (try matches(engine, kb, data, entry[0])) {
        try e.invokeVoid(engine, object, "moveCursor", &.{ v.numeric(engine, 0), v.numeric(engine, entry[1]) });
        return c.pi_js_undefined();
    };
    inline for (.{ .{ "tui.editor.pageUp", -1 }, .{ "tui.editor.pageDown", 1 } }) |entry| if (try matches(engine, kb, data, entry[0])) {
        try call1(engine, object, "pageScroll", v.numeric(engine, entry[1]));
        return c.pi_js_undefined();
    };
    inline for (.{ .{ "tui.editor.jumpForward", "forward" }, .{ "tui.editor.jumpBackward", "backward" } }) |entry| if (try matches(engine, kb, data, entry[0])) {
        try e.set(engine, object, "jumpMode", try v.text(engine, entry[1]));
        return c.pi_js_undefined();
    };
    if (try key(engine, data, "shift+space")) {
        const space = try v.text(engine, " ");
        defer engine.freeValue(space);
        try call1(engine, object, "insertCharacter", space);
        return c.pi_js_undefined();
    }
    const printable = try decoded(engine, data);
    defer engine.freeValue(printable);
    if (!c.JS_IsUndefined(printable)) try call1(engine, object, "insertCharacter", printable) else if (try firstCode(engine, data) >= 32) try call1(engine, object, "insertCharacter", data);
    return c.pi_js_undefined();
}

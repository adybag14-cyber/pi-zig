//! Source Editor insertion, grapheme/word deletion and paste-registry renumbering.
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const visual = @import("native_editor_visual.zig");
const Method = @import("native_editor_methods.zig").Method;
const Callback = enum(c_int) { higher, compare, renumber, line };
pub fn supports(method: Method) bool {
    return switch (method) {
        .insertCharacter, .handleBackspace, .handleForwardDelete, .deleteWordBackwards, .deleteWordForward => true,
        else => false,
    };
}
fn slice(engine: *Engine, text: c.JSValue, start: f64, end: ?f64) !c.JSValue {
    return js.invoke(engine, text, "slice", if (end) |last| &.{ v.numeric(engine, start), v.numeric(engine, last) } else &.{v.numeric(engine, start)});
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return callbackOperation(engine, data[0], data[1], @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native Editor deletion: %s", @as([*:0]const u8, @errorName(err)));
    };
}
fn function(engine: *Engine, constants: c.JSValue, target: c.JSValue, kind: Callback, arity: c_int) !c.JSValue {
    var data = [_]c.JSValue{ constants, target };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", arity, @intFromEnum(kind), data.len, &data));
}
fn callbackOperation(engine: *Engine, constants: c.JSValue, target: c.JSValue, kind: Callback, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (kind) {
        .higher => return c.pi_js_bool(engine.context, @intFromBool((try v.number(engine, first)) > try v.number(engine, target))),
        .compare => return v.numeric(engine, (try v.number(engine, first)) - try v.number(engine, v.arg(args, 1))),
        .renumber => {
            const id = try v.number(engine, v.arg(args, 1));
            if (id <= try v.number(engine, target)) return c.JS_DupValue(engine.context, first);
            const head = try v.text(engine, "[paste #");
            defer engine.freeValue(head);
            const end = try v.text(engine, "]");
            defer engine.freeValue(end);
            return v.concat(engine, &.{ head, v.numeric(engine, id - 1), v.arg(args, 2), end });
        },
        .line => {
            const regex = try js.get(engine, constants, "paste");
            defer engine.freeValue(regex);
            const replacement = try function(engine, constants, target, .renumber, 3);
            defer engine.freeValue(replacement);
            return js.invoke(engine, first, "replace", &.{ regex, replacement });
        },
    }
}
fn removePaste(engine: *Engine, constants: c.JSValue, object: c.JSValue, matched: c.JSValue) !void {
    const number = try js.global(engine, "Number");
    defer engine.freeValue(number);
    const raw_id = try v.fieldAt(engine, matched, 1);
    defer engine.freeValue(raw_id);
    const id = try js.call(engine, number, c.pi_js_undefined(), &.{raw_id});
    defer engine.freeValue(id);
    const registry = try js.get(engine, object, "pastes");
    defer engine.freeValue(registry);
    try e.invokeVoid(engine, registry, "delete", &.{id});
    try e.set(engine, object, "pasteCounter", v.numeric(engine, (try e.number(engine, object, "pasteCounter")) - 1));
    const keys = try js.invoke(engine, registry, "keys", &.{});
    defer engine.freeValue(keys);
    const symbol = try js.get(engine, constants, "iterator");
    defer engine.freeValue(symbol);
    const all = try js.collect(engine, keys, symbol);
    defer engine.freeValue(all);
    const predicate = try function(engine, constants, id, .higher, 1);
    defer engine.freeValue(predicate);
    const higher = try js.invoke(engine, all, "filter", &.{predicate});
    defer engine.freeValue(higher);
    const compare = try function(engine, constants, id, .compare, 2);
    defer engine.freeValue(compare);
    const sorted = try js.invoke(engine, higher, "sort", &.{compare});
    defer engine.freeValue(sorted);
    var iterator = try js.Iterator.init(engine, sorted, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |key| {
        defer engine.freeValue(key);
        const live_registry = try js.get(engine, object, "pastes");
        defer engine.freeValue(live_registry);
        const value = try js.invoke(engine, live_registry, "get", &.{key});
        defer engine.freeValue(value);
        try e.invokeVoid(engine, live_registry, "set", &.{ v.numeric(engine, (try v.number(engine, key)) - 1), value });
        try e.invokeVoid(engine, live_registry, "delete", &.{key});
    }
    const lines = try e.lines(engine, object);
    defer engine.freeValue(lines);
    const mapper = try function(engine, constants, id, .line, 1);
    defer engine.freeValue(mapper);
    try e.setState(engine, object, "lines", try js.invoke(engine, lines, "map", &.{mapper}));
}
fn retrigger(engine: *Engine, object: c.JSValue) !void {
    const state = try js.get(engine, object, "autocompleteState");
    defer engine.freeValue(state);
    if (v.truthy(engine, state)) {
        try e.invokeVoid(engine, object, "updateAutocomplete", &.{});
        return;
    }
    const line = try e.line(engine, object);
    defer engine.freeValue(line);
    const before = try slice(engine, line, 0, try e.cursor(engine, object, "cursorCol"));
    defer engine.freeValue(before);
    const slash = try js.invoke(engine, object, "isInSlashCommandContext", &.{before});
    defer engine.freeValue(slash);
    var trigger = v.truthy(engine, slash);
    if (!trigger) {
        const pattern = try js.get(engine, object, "autocompleteTriggerPattern");
        defer engine.freeValue(pattern);
        const matched = try js.invoke(engine, pattern, "test", &.{before});
        defer engine.freeValue(matched);
        trigger = v.truthy(engine, matched);
    }
    if (trigger) try e.invokeVoid(engine, object, "tryTriggerAutocomplete", &.{});
}
fn insert(engine: *Engine, constants: c.JSValue, object: c.JSValue, text: c.JSValue, skip: c.JSValue) !void {
    try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
    if (!v.truthy(engine, skip)) {
        const action = try js.get(engine, object, "lastAction");
        defer engine.freeValue(action);
        if (try visual.whitespace(engine, text) or !try e.equalText(engine, action, "type-word")) try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
        try e.setLast(engine, object, "type-word");
    }
    const line = try e.line(engine, object);
    defer engine.freeValue(line);
    const before = try slice(engine, line, 0, try e.cursor(engine, object, "cursorCol"));
    defer engine.freeValue(before);
    const after = try slice(engine, line, try e.cursor(engine, object, "cursorCol"), null);
    defer engine.freeValue(after);
    try e.replaceLine(engine, object, try v.concat(engine, &.{ before, text, after }));
    try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, (try e.cursor(engine, object, "cursorCol")) + @as(f64, @floatFromInt(try e.length(engine, text))))});
    try e.notify(engine, object);
    const state = try js.get(engine, object, "autocompleteState");
    defer engine.freeValue(state);
    if (v.truthy(engine, state)) {
        try e.invokeVoid(engine, object, "updateAutocomplete", &.{});
        return;
    }
    if (try e.equalText(engine, text, "/")) {
        const start = try js.invoke(engine, object, "isAtStartOfMessage", &.{});
        defer engine.freeValue(start);
        if (v.truthy(engine, start)) {
            try e.invokeVoid(engine, object, "tryTriggerAutocomplete", &.{});
            return;
        }
    }
    const triggers = try js.get(engine, object, "autocompleteTriggerCharacters");
    defer engine.freeValue(triggers);
    const includes = try js.invoke(engine, triggers, "includes", &.{text});
    defer engine.freeValue(includes);
    if (v.truthy(engine, includes)) {
        const current = try e.line(engine, object);
        defer engine.freeValue(current);
        const prefix = try slice(engine, current, 0, try e.cursor(engine, object, "cursorCol"));
        defer engine.freeValue(prefix);
        const pattern = try js.get(engine, object, "autocompleteTriggerPattern");
        defer engine.freeValue(pattern);
        const matched = try js.invoke(engine, pattern, "test", &.{prefix});
        defer engine.freeValue(matched);
        if (v.truthy(engine, matched)) try e.invokeVoid(engine, object, "tryTriggerAutocomplete", &.{});
        return;
    }
    const ascii = try e.literalPattern(engine, "[a-zA-Z0-9.\\-_]", "");
    defer engine.freeValue(ascii);
    const matched = try js.invoke(engine, ascii, "test", &.{text});
    defer engine.freeValue(matched);
    if (v.truthy(engine, matched) or try visual.testPattern(engine, constants, "cjk", text)) try retrigger(engine, object);
}
fn merge(engine: *Engine, object: c.JSValue, current: c.JSValue, backward: bool) !void {
    const lines = try e.lines(engine, object);
    defer engine.freeValue(lines);
    const row = try e.cursor(engine, object, "cursorLine");
    const other_raw = try v.fieldAt(engine, lines, row + if (backward) @as(f64, -1) else @as(f64, 1));
    defer engine.freeValue(other_raw);
    const other = if (v.truthy(engine, other_raw)) c.JS_DupValue(engine.context, other_raw) else try v.text(engine, "");
    defer engine.freeValue(other);
    const merged = try v.concat(engine, if (backward) &.{ other, current } else &.{ current, other });
    defer engine.freeValue(merged);
    try js.setKey(engine, lines, v.numeric(engine, if (backward) row - 1 else row), merged);
    try e.invokeVoid(engine, lines, "splice", &.{ v.numeric(engine, if (backward) row else row + 1), v.numeric(engine, 1) });
    if (backward) {
        try e.setState(engine, object, "cursorLine", v.numeric(engine, (try e.cursor(engine, object, "cursorLine")) - 1));
        try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, @floatFromInt(try e.length(engine, other)))});
    }
}
fn erase(engine: *Engine, constants: c.JSValue, object: c.JSValue, backward: bool) !void {
    try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
    try e.setLast(engine, object, null);
    const col = try e.cursor(engine, object, "cursorCol");
    const current = try e.line(engine, object);
    defer engine.freeValue(current);
    if (if (backward) col > 0 else col < @as(f64, @floatFromInt(try e.length(engine, current)))) {
        try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
        const portion = try slice(engine, current, if (backward) 0 else try e.cursor(engine, object, "cursorCol"), if (backward) try e.cursor(engine, object, "cursorCol") else null);
        defer engine.freeValue(portion);
        const segments = try visual.collectSegments(engine, constants, object, portion);
        defer engine.freeValue(segments);
        const count = try e.length(engine, segments);
        const segment = if (count > 0) try v.fieldAt(engine, segments, if (backward) @as(f64, @floatFromInt(count - 1)) else 0) else c.pi_js_undefined();
        defer engine.freeValue(segment);
        const text = if (v.truthy(engine, segment)) try js.get(engine, segment, "segment") else c.pi_js_undefined();
        defer engine.freeValue(text);
        const amount: f64 = if (v.truthy(engine, segment)) @floatFromInt(try e.length(engine, text)) else 1;
        if (backward) {
            const last_text = try js.get(engine, segment, "segment");
            defer engine.freeValue(last_text);
            const regex = try js.get(engine, constants, "marker");
            defer engine.freeValue(regex);
            const matched = try js.invoke(engine, regex, "exec", &.{last_text});
            defer engine.freeValue(matched);
            if (v.truthy(engine, matched)) try removePaste(engine, constants, object, matched);
        }
        const live = if (backward) try e.line(engine, object) else c.JS_DupValue(engine.context, current);
        defer engine.freeValue(live);
        const live_col = try e.cursor(engine, object, "cursorCol");
        const before = try slice(engine, live, 0, if (backward) live_col - amount else live_col);
        defer engine.freeValue(before);
        const after = try slice(engine, live, if (backward) live_col else live_col + amount, null);
        defer engine.freeValue(after);
        try e.replaceLine(engine, object, try v.concat(engine, &.{ before, after }));
        if (backward) try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, (try e.cursor(engine, object, "cursorCol")) - amount)});
    } else {
        const row = try e.cursor(engine, object, "cursorLine");
        const lines = try e.lines(engine, object);
        defer engine.freeValue(lines);
        if (if (backward) row > 0 else row < @as(f64, @floatFromInt(try e.length(engine, lines))) - 1) {
            try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
            try merge(engine, object, current, backward);
        }
    }
    try e.notify(engine, object);
    try retrigger(engine, object);
}
fn pushKill(engine: *Engine, object: c.JSValue, text: c.JSValue, backward: bool, accumulate: bool) !void {
    const ring = try js.get(engine, object, "killRing");
    defer engine.freeValue(ring);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "prepend", c.pi_js_bool(engine.context, @intFromBool(backward)));
    try js.define(engine, options, "accumulate", c.pi_js_bool(engine.context, @intFromBool(accumulate)));
    try e.invokeVoid(engine, ring, "push", &.{ text, options });
    try e.setLast(engine, object, "kill");
}
fn eraseWord(engine: *Engine, object: c.JSValue, backward: bool) !void {
    try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
    const current = try e.line(engine, object);
    defer engine.freeValue(current);
    const col = try e.cursor(engine, object, "cursorCol");
    if (if (backward) col == 0 else col >= @as(f64, @floatFromInt(try e.length(engine, current)))) {
        const row = try e.cursor(engine, object, "cursorLine");
        const lines = try e.lines(engine, object);
        defer engine.freeValue(lines);
        if (if (backward) row > 0 else row < @as(f64, @floatFromInt(try e.length(engine, lines))) - 1) {
            try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
            const action = try js.get(engine, object, "lastAction");
            defer engine.freeValue(action);
            const newline = try v.text(engine, "\n");
            defer engine.freeValue(newline);
            try pushKill(engine, object, newline, backward, try e.equalText(engine, action, "kill"));
            try merge(engine, object, current, backward);
        }
    } else {
        try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
        const action = try js.get(engine, object, "lastAction");
        defer engine.freeValue(action);
        const was_kill = try e.equalText(engine, action, "kill");
        const old = try e.cursor(engine, object, "cursorCol");
        try e.invokeVoid(engine, object, if (backward) "moveWordBackwards" else "moveWordForwards", &.{});
        const moved = try e.cursor(engine, object, "cursorCol");
        try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, old)});
        const deleted = try slice(engine, current, if (backward) moved else try e.cursor(engine, object, "cursorCol"), if (backward) try e.cursor(engine, object, "cursorCol") else moved);
        defer engine.freeValue(deleted);
        try pushKill(engine, object, deleted, backward, was_kill);
        const before = try slice(engine, current, 0, if (backward) moved else try e.cursor(engine, object, "cursorCol"));
        defer engine.freeValue(before);
        const after = try slice(engine, current, if (backward) try e.cursor(engine, object, "cursorCol") else moved, null);
        defer engine.freeValue(after);
        try e.replaceLine(engine, object, try v.concat(engine, &.{ before, after }));
        if (backward) try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, moved)});
    }
    try e.notify(engine, object);
}
pub fn operation(engine: *Engine, constants: c.JSValue, object: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .insertCharacter => try insert(engine, constants, object, v.arg(args, 0), v.arg(args, 1)),
        .handleBackspace => try erase(engine, constants, object, true),
        .handleForwardDelete => try erase(engine, constants, object, false),
        .deleteWordBackwards => try eraseWord(engine, object, true),
        .deleteWordForward => try eraseWord(engine, object, false),
        else => unreachable,
    }
    return c.pi_js_undefined();
}

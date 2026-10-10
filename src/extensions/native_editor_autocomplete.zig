//! Source Editor provider lifecycle. Intrinsic C promises retain JS async semantics.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const Method = @import("native_editor_methods.zig").Method;
const Callback = enum(c_int) { begin, ready, timer, selected, settled, fulfilled };
pub fn supports(method: Method) bool {
    return switch (method) {
        .setAutocompleteProvider, .getBestAutocompleteMatchIndex, .createAutocompleteList, .tryTriggerAutocomplete, .handleTabCompletion, .handleSlashCommandCompletion, .forceFileAutocomplete, .requestAutocomplete, .startAutocompleteRequest, .setAutocompleteTriggerCharacters, .getAutocompleteDebounceMs, .runAutocompleteRequest, .isAutocompleteRequestCurrent, .applyAutocompleteSuggestions => true,
        else => false,
    };
}
pub fn install(engine: *Engine, exports: c.JSValue) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "SelectList", try js.get(engine, exports, "SelectList"));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, result, "iterator", try js.get(engine, symbol, "iterator"));
    return result;
}
fn rawCursor(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const state = try e.state(engine, object);
    defer engine.freeValue(state);
    return js.get(engine, state, name);
}
fn capture(engine: *Engine, args: []const c.JSValue) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    for (args, 0..) |value, index| if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), c.JS_DupValue(engine.context, value)) < 0) return js.capture(engine);
    return result;
}
fn function(engine: *Engine, constants: c.JSValue, editor: c.JSValue, packet: c.JSValue, kind: Callback, arity: c_int) !c.JSValue {
    var data = [_]c.JSValue{ constants, editor, packet };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", arity, @intFromEnum(kind), data.len, &data));
}
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Editor provider: %s", @as([*:0]const u8, @errorName(err)));
}
fn errorValue(engine: *Engine, err: anyerror) c.JSValue {
    const raw = if (err == error.JavaScriptException and engine.captured_exception != null) c.JS_DupValue(engine.context, engine.captured_exception.?) else raw: {
        _ = fail(engine, err);
        break :raw c.JS_GetException(engine.context);
    };
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = null;
    if (engine.last_error) |value| engine.gpa.free(value);
    engine.last_error = null;
    return raw;
}
fn rejected(engine: *Engine, err: anyerror) !c.JSValue {
    const raw = errorValue(engine, err);
    defer engine.freeValue(raw);
    return engine.checked(c.JS_NewSettledPromise(engine.context, true, raw));
}
fn resolved(engine: *Engine, value: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_NewSettledPromise(engine.context, false, value));
}
fn then(engine: *Engine, promise: c.JSValue, on_value: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PromiseThen(engine.context, promise, on_value, c.pi_js_undefined()));
}
fn applyCompletion(engine: *Engine, editor: c.JSValue, item: c.JSValue, prefix: c.JSValue) !void {
    const provider = try js.get(engine, editor, "autocompleteProvider");
    defer engine.freeValue(provider);
    const lines = try e.lines(engine, editor);
    defer engine.freeValue(lines);
    const row = try rawCursor(engine, editor, "cursorLine");
    defer engine.freeValue(row);
    const col = try rawCursor(engine, editor, "cursorCol");
    defer engine.freeValue(col);
    const result = try js.invoke(engine, provider, "applyCompletion", &.{ lines, row, col, item, prefix });
    defer engine.freeValue(result);
    try e.setState(engine, editor, "lines", try js.get(engine, result, "lines"));
    try e.setState(engine, editor, "cursorLine", try js.get(engine, result, "cursorLine"));
    const position = try js.get(engine, result, "cursorCol");
    defer engine.freeValue(position);
    try e.invokeVoid(engine, editor, "setCursorCol", &.{position});
}
fn ready(engine: *Engine, editor: c.JSValue, packet: c.JSValue, suggestions: c.JSValue) !c.JSValue {
    var args: [6]c.JSValue = undefined;
    var owned: usize = 0;
    defer for (args[0..owned]) |value| engine.freeValue(value);
    for (&args, 0..) |*value, index| {
        value.* = try v.fieldAt(engine, packet, @floatFromInt(index));
        owned += 1;
    }
    const current = try js.invoke(engine, editor, "isAutocompleteRequestCurrent", args[0..5]);
    defer engine.freeValue(current);
    if (!v.truthy(engine, current)) return c.pi_js_undefined();
    try e.set(engine, editor, "autocompleteAbort", c.pi_js_undefined());
    var valid = v.truthy(engine, suggestions);
    if (valid) {
        const items = try js.get(engine, suggestions, "items");
        defer engine.freeValue(items);
        const array = try js.global(engine, "Array");
        defer engine.freeValue(array);
        const is_array = try js.invoke(engine, array, "isArray", &.{items});
        defer engine.freeValue(is_array);
        valid = v.truthy(engine, is_array) and try e.length(engine, items) != 0;
    }
    if (!valid) {
        try e.invokeVoid(engine, editor, "cancelAutocomplete", &.{});
        try e.renderRequest(engine, editor);
        return c.pi_js_undefined();
    }
    const force = try js.get(engine, args[5], "force");
    defer engine.freeValue(force);
    var direct = false;
    if (v.truthy(engine, force)) {
        const explicit = try js.get(engine, args[5], "explicitTab");
        defer engine.freeValue(explicit);
        if (v.truthy(engine, explicit)) {
            const items = try js.get(engine, suggestions, "items");
            defer engine.freeValue(items);
            direct = try e.length(engine, items) == 1;
        }
    }
    if (direct) {
        const items = try js.get(engine, suggestions, "items");
        defer engine.freeValue(items);
        const item = try v.fieldAt(engine, items, 0);
        defer engine.freeValue(item);
        try e.invokeVoid(engine, editor, "pushUndoSnapshot", &.{});
        try e.setLast(engine, editor, null);
        const prefix = try js.get(engine, suggestions, "prefix");
        defer engine.freeValue(prefix);
        try applyCompletion(engine, editor, item, prefix);
        try e.notify(engine, editor);
        try e.renderRequest(engine, editor);
        return c.pi_js_undefined();
    }
    const state = try v.text(engine, if (v.truthy(engine, force)) "force" else "regular");
    defer engine.freeValue(state);
    try e.invokeVoid(engine, editor, "applyAutocompleteSuggestions", &.{ suggestions, state });
    try e.renderRequest(engine, editor);
    return c.pi_js_undefined();
}
fn begin(engine: *Engine, constants: c.JSValue, editor: c.JSValue, packet: c.JSValue) !?c.JSValue {
    const token = try v.fieldAt(engine, packet, 0);
    defer engine.freeValue(token);
    const current = try js.get(engine, editor, "autocompleteStartToken");
    defer engine.freeValue(current);
    if (!c.JS_IsStrictEqual(engine.context, token, current)) return null;
    const provider = try js.get(engine, editor, "autocompleteProvider");
    defer engine.freeValue(provider);
    if (!v.truthy(engine, provider)) return null;
    const controller = try js.builtin(engine, "AbortController", &.{});
    defer engine.freeValue(controller);
    try e.set(engine, editor, "autocompleteAbort", c.JS_DupValue(engine.context, controller));
    const id = (try e.number(engine, editor, "autocompleteRequestId")) + 1;
    try e.set(engine, editor, "autocompleteRequestId", v.numeric(engine, id));
    const text = try js.invoke(engine, editor, "getText", &.{});
    defer engine.freeValue(text);
    const row = try rawCursor(engine, editor, "cursorLine");
    defer engine.freeValue(row);
    const col = try rawCursor(engine, editor, "cursorCol");
    defer engine.freeValue(col);
    const options = try v.fieldAt(engine, packet, 1);
    defer engine.freeValue(options);
    _ = constants;
    return try js.invoke(engine, editor, "runAutocompleteRequest", &.{ v.numeric(engine, id), controller, text, row, col, options });
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const kind: Callback = @enumFromInt(magic);
    return callbackOperation(engine, data[0], data[1], data[2], kind, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (kind == .begin) {
            const raw = errorValue(engine, err);
            defer engine.freeValue(raw);
            const reject = v.fieldAt(engine, data[2], 3) catch |failure| return fail(engine, failure);
            defer engine.freeValue(reject);
            const ignored = js.call(engine, reject, c.pi_js_undefined(), &.{raw}) catch |failure| return fail(engine, failure);
            engine.freeValue(ignored);
            return c.pi_js_undefined();
        }
        return fail(engine, err);
    };
}
fn callbackOperation(engine: *Engine, constants: c.JSValue, editor: c.JSValue, packet: c.JSValue, kind: Callback, first: c.JSValue) !c.JSValue {
    switch (kind) {
        .begin => {
            const returned = try begin(engine, constants, editor, packet);
            if (returned) |value| {
                defer engine.freeValue(value);
                const promise = try resolved(engine, value);
                defer engine.freeValue(promise);
                const fulfilled = try function(engine, constants, editor, packet, .fulfilled, 0);
                defer engine.freeValue(fulfilled);
                const reject = try v.fieldAt(engine, packet, 3);
                defer engine.freeValue(reject);
                const ignored = try engine.checked(c.JS_PromiseThen(engine.context, promise, fulfilled, reject));
                engine.freeValue(ignored);
            } else {
                const resolve = try v.fieldAt(engine, packet, 2);
                defer engine.freeValue(resolve);
                const ignored = try js.call(engine, resolve, c.pi_js_undefined(), &.{c.pi_js_undefined()});
                engine.freeValue(ignored);
            }
        },
        .fulfilled => {
            const resolve = try v.fieldAt(engine, packet, 2);
            defer engine.freeValue(resolve);
            const ignored = try js.call(engine, resolve, c.pi_js_undefined(), &.{c.pi_js_undefined()});
            engine.freeValue(ignored);
        },
        .ready => return ready(engine, editor, packet, first),
        .settled => return c.pi_js_undefined(),
        .timer => {
            try e.set(engine, editor, "autocompleteDebounceTimer", c.pi_js_undefined());
            const token = try v.fieldAt(engine, packet, 0);
            defer engine.freeValue(token);
            const options = try v.fieldAt(engine, packet, 1);
            defer engine.freeValue(options);
            try e.invokeVoid(engine, editor, "startAutocompleteRequest", &.{ token, options });
        },
        .selected => {
            const provider = try js.get(engine, editor, "autocompleteProvider");
            defer engine.freeValue(provider);
            if (!v.truthy(engine, provider)) return c.pi_js_undefined();
            try e.invokeVoid(engine, editor, "pushUndoSnapshot", &.{});
            try e.setLast(engine, editor, null);
            const prefix = try js.get(engine, editor, "autocompletePrefix");
            defer engine.freeValue(prefix);
            try applyCompletion(engine, editor, first, prefix);
            try e.invokeVoid(engine, editor, "cancelAutocomplete", &.{});
            const on_change = try js.get(engine, editor, "onChange");
            defer engine.freeValue(on_change);
            if (!c.JS_IsNull(on_change) and !c.JS_IsUndefined(on_change)) {
                const text = try js.invoke(engine, editor, "getText", &.{});
                defer engine.freeValue(text);
                const ignored = try js.call(engine, on_change, editor, &.{text});
                engine.freeValue(ignored);
            }
        },
    }
    return c.pi_js_undefined();
}
fn start(engine: *Engine, constants: c.JSValue, editor: c.JSValue, token: c.JSValue, options: c.JSValue) !c.JSValue {
    const previous = try js.get(engine, editor, "autocompleteRequestTask");
    defer engine.freeValue(previous);
    const adopted = try resolved(engine, previous);
    defer engine.freeValue(adopted);
    var capabilities: [2]c.JSValue = undefined;
    const task = try engine.checked(c.JS_NewPromiseCapability(engine.context, &capabilities));
    defer engine.freeValue(task);
    defer for (capabilities) |value| engine.freeValue(value);
    const packet = try capture(engine, &.{ token, options, capabilities[0], capabilities[1] });
    defer engine.freeValue(packet);
    const handler = try function(engine, constants, editor, packet, .begin, 0);
    defer engine.freeValue(handler);
    const ignored = try engine.checked(c.JS_PromiseThen(engine.context, adopted, handler, capabilities[1]));
    engine.freeValue(ignored);
    try e.set(engine, editor, "autocompleteRequestTask", c.JS_DupValue(engine.context, task));
    const current = try js.get(engine, editor, "autocompleteRequestTask");
    defer engine.freeValue(current);
    const current_task = try resolved(engine, current);
    defer engine.freeValue(current_task);
    const settled = try function(engine, constants, editor, c.pi_js_undefined(), .settled, 0);
    defer engine.freeValue(settled);
    return then(engine, current_task, settled);
}
fn run(engine: *Engine, constants: c.JSValue, editor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const provider = try js.get(engine, editor, "autocompleteProvider");
    defer engine.freeValue(provider);
    if (!v.truthy(engine, provider)) return resolved(engine, c.pi_js_undefined());
    const lines = try e.lines(engine, editor);
    defer engine.freeValue(lines);
    const row = try rawCursor(engine, editor, "cursorLine");
    defer engine.freeValue(row);
    const col = try rawCursor(engine, editor, "cursorCol");
    defer engine.freeValue(col);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "signal", try js.get(engine, v.arg(args, 1), "signal"));
    try js.define(engine, options, "force", try js.get(engine, v.arg(args, 5), "force"));
    const returned = try js.invoke(engine, provider, "getSuggestions", &.{ lines, row, col, options });
    defer engine.freeValue(returned);
    const promise = try resolved(engine, returned);
    defer engine.freeValue(promise);
    const packet = try capture(engine, args);
    defer engine.freeValue(packet);
    const handler = try function(engine, constants, editor, packet, .ready, 1);
    defer engine.freeValue(handler);
    return then(engine, promise, handler);
}
fn currentRequest(engine: *Engine, editor: c.JSValue, args: []const c.JSValue) !bool {
    const signal = try js.get(engine, v.arg(args, 1), "signal");
    defer engine.freeValue(signal);
    const aborted = try js.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (v.truthy(engine, aborted)) return false;
    const id = try js.get(engine, editor, "autocompleteRequestId");
    defer engine.freeValue(id);
    if (!c.JS_IsStrictEqual(engine.context, v.arg(args, 0), id)) return false;
    const text = try js.invoke(engine, editor, "getText", &.{});
    defer engine.freeValue(text);
    if (!c.JS_IsStrictEqual(engine.context, text, v.arg(args, 2))) return false;
    const row = try rawCursor(engine, editor, "cursorLine");
    defer engine.freeValue(row);
    if (!c.JS_IsStrictEqual(engine.context, row, v.arg(args, 3))) return false;
    const col = try rawCursor(engine, editor, "cursorCol");
    defer engine.freeValue(col);
    return c.JS_IsStrictEqual(engine.context, col, v.arg(args, 4));
}
fn request(engine: *Engine, constants: c.JSValue, editor: c.JSValue, options: c.JSValue) !void {
    const provider = try js.get(engine, editor, "autocompleteProvider");
    defer engine.freeValue(provider);
    if (!v.truthy(engine, provider)) return;
    const force = try js.get(engine, options, "force");
    defer engine.freeValue(force);
    if (v.truthy(engine, force)) {
        const predicate = try js.get(engine, provider, "shouldTriggerFileCompletion");
        defer engine.freeValue(predicate);
        if (v.truthy(engine, predicate)) {
            const lines = try e.lines(engine, editor);
            defer engine.freeValue(lines);
            const row = try rawCursor(engine, editor, "cursorLine");
            defer engine.freeValue(row);
            const col = try rawCursor(engine, editor, "cursorCol");
            defer engine.freeValue(col);
            const accepted = try js.call(engine, predicate, provider, &.{ lines, row, col });
            defer engine.freeValue(accepted);
            if (!v.truthy(engine, accepted)) return;
        }
    }
    try e.invokeVoid(engine, editor, "cancelAutocompleteRequest", &.{});
    const token = (try e.number(engine, editor, "autocompleteStartToken")) + 1;
    try e.set(engine, editor, "autocompleteStartToken", v.numeric(engine, token));
    const debounce = try js.invoke(engine, editor, "getAutocompleteDebounceMs", &.{options});
    defer engine.freeValue(debounce);
    if (try v.number(engine, debounce) > 0) {
        const packet = try capture(engine, &.{ v.numeric(engine, token), options });
        defer engine.freeValue(packet);
        const timer = try function(engine, constants, editor, packet, .timer, 0);
        defer engine.freeValue(timer);
        const set_timeout = try js.global(engine, "setTimeout");
        defer engine.freeValue(set_timeout);
        try e.set(engine, editor, "autocompleteDebounceTimer", try js.call(engine, set_timeout, c.pi_js_undefined(), &.{ timer, debounce }));
    } else try e.invokeVoid(engine, editor, "startAutocompleteRequest", &.{ v.numeric(engine, token), options });
}
fn triggerPatterns(engine: *Engine, editor: c.JSValue, characters: c.JSValue) !void {
    const escaped = try js.array(engine);
    defer engine.freeValue(escaped);
    const without_at = try js.array(engine);
    defer engine.freeValue(without_at);
    const escape_regex = try e.literalPattern(engine, "[\\\\^$.*+?()[\\]{}|-]", "g");
    defer engine.freeValue(escape_regex);
    const replacement = try v.text(engine, "\\$&");
    defer engine.freeValue(replacement);
    for (0..try e.length(engine, characters)) |index| {
        const character = try v.fieldAt(engine, characters, @floatFromInt(index));
        defer engine.freeValue(character);
        const text = try js.invoke(engine, character, "replace", &.{ escape_regex, replacement });
        defer engine.freeValue(text);
        try js.push(engine, escaped, text);
        if (!try e.equalText(engine, character, "@")) try js.push(engine, without_at, text);
    }
    const empty = try v.text(engine, "");
    defer engine.freeValue(empty);
    const joined = try js.invoke(engine, escaped, "join", &.{empty});
    defer engine.freeValue(joined);
    const joined_without = try js.invoke(engine, without_at, "join", &.{empty});
    defer engine.freeValue(joined_without);
    const trigger_head = try v.text(engine, e.token_start ++ "(?:@\"[^\"]*|[");
    defer engine.freeValue(trigger_head);
    const trigger_tail = try v.text(engine, "]" ++ e.suffix ++ ")$");
    defer engine.freeValue(trigger_tail);
    const body = try v.concat(engine, &.{ trigger_head, joined, trigger_tail });
    defer engine.freeValue(body);
    const debounce_head = try v.text(engine, e.token_start ++ "(?:@(?:\"[^\"]*|" ++ e.suffix ++ ")|[");
    defer engine.freeValue(debounce_head);
    const debounce_body = try v.concat(engine, &.{ debounce_head, joined_without, trigger_tail });
    defer engine.freeValue(debounce_body);
    const flags = try v.text(engine, "u");
    defer engine.freeValue(flags);
    try e.set(engine, editor, "autocompleteTriggerPattern", try js.builtin(engine, "RegExp", &.{ body, flags }));
    try e.set(engine, editor, "autocompleteDebouncePattern", try js.builtin(engine, "RegExp", &.{ debounce_body, flags }));
}
pub fn operation(engine: *Engine, constants: c.JSValue, editor: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (method) {
        .startAutocompleteRequest => return start(engine, constants, editor, first, v.arg(args, 1)) catch |err| rejected(engine, err),
        .runAutocompleteRequest => return run(engine, constants, editor, args) catch |err| rejected(engine, err),
        .requestAutocomplete => try request(engine, constants, editor, first),
        .setAutocompleteProvider => {
            try e.invokeVoid(engine, editor, "cancelAutocomplete", &.{});
            try e.set(engine, editor, "autocompleteProvider", c.JS_DupValue(engine.context, first));
            const triggers = try js.get(engine, first, "triggerCharacters");
            defer engine.freeValue(triggers);
            const value = if (c.JS_IsNull(triggers) or c.JS_IsUndefined(triggers)) try js.array(engine) else c.JS_DupValue(engine.context, triggers);
            defer engine.freeValue(value);
            try e.invokeVoid(engine, editor, "setAutocompleteTriggerCharacters", &.{value});
        },
        .setAutocompleteTriggerCharacters => {
            const next = try js.array(engine);
            defer engine.freeValue(next);
            inline for (.{ "@", "#" }, 0..) |text, index| if (c.JS_SetPropertyUint32(engine.context, next, index, try v.text(engine, text)) < 0) return js.capture(engine);
            const iterator_symbol = try js.get(engine, constants, "iterator");
            defer engine.freeValue(iterator_symbol);
            var iterator = try js.Iterator.init(engine, first, iterator_symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |character| {
                defer engine.freeValue(character);
                const length = try js.get(engine, character, "length");
                defer engine.freeValue(length);
                if (!c.JS_IsStrictEqual(engine.context, length, v.numeric(engine, 1)) or try e.equalText(engine, character, "/")) continue;
                const whitespace = try e.literalPattern(engine, "\\s", "");
                defer engine.freeValue(whitespace);
                const is_space = try js.invoke(engine, whitespace, "test", &.{character});
                defer engine.freeValue(is_space);
                if (v.truthy(engine, is_space)) continue;
                const includes = try js.invoke(engine, next, "includes", &.{character});
                defer engine.freeValue(includes);
                if (!v.truthy(engine, includes)) try js.push(engine, next, character);
            }
            try e.set(engine, editor, "autocompleteTriggerCharacters", c.JS_DupValue(engine.context, next));
            try triggerPatterns(engine, editor, next);
        },
        .getAutocompleteDebounceMs => {
            const explicit = try js.get(engine, first, "explicitTab");
            defer engine.freeValue(explicit);
            if (v.truthy(engine, explicit)) return v.numeric(engine, 0);
            const force = try js.get(engine, first, "force");
            defer engine.freeValue(force);
            if (v.truthy(engine, force)) return v.numeric(engine, 0);
            const line = try e.line(engine, editor);
            defer engine.freeValue(line);
            const col = try rawCursor(engine, editor, "cursorCol");
            defer engine.freeValue(col);
            const before = try js.invoke(engine, line, "slice", &.{ v.numeric(engine, 0), col });
            defer engine.freeValue(before);
            const pattern = try js.get(engine, editor, "autocompleteDebouncePattern");
            defer engine.freeValue(pattern);
            const matched = try js.invoke(engine, pattern, "test", &.{before});
            defer engine.freeValue(matched);
            return v.numeric(engine, if (v.truthy(engine, matched)) 20 else 0);
        },
        .isAutocompleteRequestCurrent => return c.pi_js_bool(engine.context, @intFromBool(try currentRequest(engine, editor, args))),
        .getBestAutocompleteMatchIndex => {
            const prefix = v.arg(args, 1);
            if (!v.truthy(engine, prefix)) return v.numeric(engine, -1);
            var best: f64 = -1;
            var index: usize = 0;
            while (index < try e.length(engine, first)) : (index += 1) {
                const item = try v.fieldAt(engine, first, @floatFromInt(index));
                defer engine.freeValue(item);
                const value = try js.get(engine, item, "value");
                defer engine.freeValue(value);
                if (c.JS_IsStrictEqual(engine.context, value, prefix)) return v.numeric(engine, @floatFromInt(index));
                if (best == -1) {
                    const begins = try js.invoke(engine, value, "startsWith", &.{prefix});
                    defer engine.freeValue(begins);
                    if (v.truthy(engine, begins)) best = @floatFromInt(index);
                }
            }
            return v.numeric(engine, best);
        },
        .createAutocompleteList => {
            const slash = try v.text(engine, "/");
            defer engine.freeValue(slash);
            const begins = try js.invoke(engine, first, "startsWith", &.{slash});
            defer engine.freeValue(begins);
            const layout = if (v.truthy(engine, begins)) try js.object(engine) else c.pi_js_undefined();
            defer engine.freeValue(layout);
            if (v.truthy(engine, begins)) {
                try js.define(engine, layout, "minPrimaryColumnWidth", v.numeric(engine, 12));
                try js.define(engine, layout, "maxPrimaryColumnWidth", v.numeric(engine, 32));
            }
            const maximum = try js.get(engine, editor, "autocompleteMaxVisible");
            defer engine.freeValue(maximum);
            const theme = try js.get(engine, editor, "theme");
            defer engine.freeValue(theme);
            const list_theme = try js.get(engine, theme, "selectList");
            defer engine.freeValue(list_theme);
            const constructor = try js.get(engine, constants, "SelectList");
            defer engine.freeValue(constructor);
            var parameters = [_]c.JSValue{ v.arg(args, 1), maximum, list_theme, layout };
            const list = try engine.checked(c.JS_CallConstructor(engine.context, constructor, parameters.len, &parameters));
            errdefer engine.freeValue(list);
            try e.set(engine, list, "onSelect", try function(engine, constants, editor, c.pi_js_undefined(), .selected, 1));
            return list;
        },
        .applyAutocompleteSuggestions => {
            try e.set(engine, editor, "autocompletePrefix", try js.get(engine, first, "prefix"));
            const prefix = try js.get(engine, first, "prefix");
            defer engine.freeValue(prefix);
            const items = try js.get(engine, first, "items");
            defer engine.freeValue(items);
            try e.set(engine, editor, "autocompleteList", try js.invoke(engine, editor, "createAutocompleteList", &.{ prefix, items }));
            const best = try js.invoke(engine, editor, "getBestAutocompleteMatchIndex", &.{ items, prefix });
            defer engine.freeValue(best);
            if (try v.number(engine, best) >= 0) {
                const list = try js.get(engine, editor, "autocompleteList");
                defer engine.freeValue(list);
                try e.invokeVoid(engine, list, "setSelectedIndex", &.{best});
            }
            try e.set(engine, editor, "autocompleteState", c.JS_DupValue(engine.context, v.arg(args, 1)));
        },
        .tryTriggerAutocomplete, .handleSlashCommandCompletion, .forceFileAutocomplete => {
            const options = try js.object(engine);
            defer engine.freeValue(options);
            try js.define(engine, options, "force", c.pi_js_bool(engine.context, @intFromBool(method == .forceFileAutocomplete)));
            try js.define(engine, options, "explicitTab", if (method == .handleSlashCommandCompletion) c.pi_js_bool(engine.context, 1) else if (c.JS_IsUndefined(first)) c.pi_js_bool(engine.context, 0) else c.JS_DupValue(engine.context, first));
            try e.invokeVoid(engine, editor, "requestAutocomplete", &.{options});
        },
        .handleTabCompletion => {
            const provider = try js.get(engine, editor, "autocompleteProvider");
            defer engine.freeValue(provider);
            if (!v.truthy(engine, provider)) return c.pi_js_undefined();
            const line = try e.line(engine, editor);
            defer engine.freeValue(line);
            const before = try js.invoke(engine, line, "slice", &.{ v.numeric(engine, 0), v.numeric(engine, try e.cursor(engine, editor, "cursorCol")) });
            defer engine.freeValue(before);
            const slash = try js.invoke(engine, editor, "isInSlashCommandContext", &.{before});
            defer engine.freeValue(slash);
            var command = false;
            if (v.truthy(engine, slash)) {
                const trimmed = try js.invoke(engine, before, "trimStart", &.{});
                defer engine.freeValue(trimmed);
                const space = try v.text(engine, " ");
                defer engine.freeValue(space);
                const includes = try js.invoke(engine, trimmed, "includes", &.{space});
                defer engine.freeValue(includes);
                command = !v.truthy(engine, includes);
            }
            if (command) try e.invokeVoid(engine, editor, "handleSlashCommandCompletion", &.{}) else try e.invokeVoid(engine, editor, "forceFileAutocomplete", &.{c.pi_js_bool(engine.context, 1)});
        },
        else => unreachable,
    }
    return c.pi_js_undefined();
}

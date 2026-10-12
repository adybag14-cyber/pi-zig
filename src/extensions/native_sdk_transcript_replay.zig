//! Original transcript/text helper algorithms over actual owner-local JS refs.
//! Dynamic Map/Object/array operations and iterators retain Source semantics.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn positive(engine: *em.Engine, value: c.JSValue) !bool {
    const result = try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, value, c.JS_NewInt32(engine.context, 0)));
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 1;
}
fn system(engine: *em.Engine, message: c.JSValue) !bool {
    const role = try sdk.get(engine, message, "role");
    defer engine.freeValue(role);
    const expected = try sdk.text(engine, "system");
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, role, expected);
}
pub fn arraySpread(engine: *em.Engine, source: c.JSValue, head: ?c.JSValue) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    var index: u32 = 0;
    if (head) |value| {
        if (c.JS_DefinePropertyValueUint32(engine.context, result, index, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        index += 1;
    }
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, source, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        if (c.JS_DefinePropertyValueUint32(engine.context, result, index, value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        index += 1;
    }
    return result;
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return callbackValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| sdk.fail(engine, err);
}
fn callbackValue(engine: *em.Engine, value: c.JSValue, magic: c_int) !c.JSValue {
    if (magic == 1) return sdk.get(engine, value, "text");
    if (magic == 2) return c.pi_js_bool(engine.context, @intFromBool(!try system(engine, value)));
    const kind = try sdk.get(engine, value, "type");
    defer engine.freeValue(kind);
    const expected = try sdk.text(engine, "text");
    defer engine.freeValue(expected);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, kind, expected)));
}
pub fn conversation(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    const filter = try sdk.get(engine, messages, "filter");
    defer engine.freeValue(filter);
    const predicate = try engine.checked(c.pi_js_function_magic(engine.context, callback, "", 1, 2));
    defer engine.freeValue(predicate);
    return js.call(engine, filter, messages, &.{predicate});
}
pub fn contentText(engine: *em.Engine, content: c.JSValue) !c.JSValue {
    const separator = try sdk.text(engine, "\n");
    defer engine.freeValue(separator);
    return contentTextWithSeparator(engine, content, separator);
}
pub fn contentTextWithSeparator(engine: *em.Engine, content: c.JSValue, separator: c.JSValue) !c.JSValue {
    if (c.JS_IsString(content)) return c.JS_DupValue(engine.context, content);
    const filter = try sdk.get(engine, content, "filter");
    defer engine.freeValue(filter);
    const predicate = try engine.checked(c.pi_js_function_magic(engine.context, callback, "", 1, 0));
    defer engine.freeValue(predicate);
    const selected = try js.call(engine, filter, content, &.{predicate});
    defer engine.freeValue(selected);
    const map = try sdk.get(engine, selected, "map");
    defer engine.freeValue(map);
    const mapper = try engine.checked(c.pi_js_function_magic(engine.context, callback, "", 1, 1));
    defer engine.freeValue(mapper);
    const parts = try js.call(engine, map, selected, &.{mapper});
    defer engine.freeValue(parts);
    return js.invoke(engine, parts, "join", &.{separator});
}
fn toolsDelta(engine: *em.Engine, message: c.JSValue, name: [*:0]const u8, tools: c.JSValue, remove: bool, symbol: c.JSValue) !void {
    const raw = try sdk.get(engine, message, name);
    defer engine.freeValue(raw);
    const rows = if (nullish(raw)) try sdk.array(engine) else c.JS_DupValue(engine.context, raw);
    defer engine.freeValue(rows);
    var iterator = try js.Iterator.init(engine, rows, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |tool| {
        defer engine.freeValue(tool);
        // Evaluate the callee before the argument getter in tools.set/delete.
        const method = try sdk.get(engine, tools, if (remove) "delete" else "set");
        defer engine.freeValue(method);
        const key = try sdk.get(engine, tool, "name");
        defer engine.freeValue(key);
        const ignored = if (remove) try js.call(engine, method, tools, &.{key}) else try js.call(engine, method, tools, &.{ key, tool });
        engine.freeValue(ignored);
    }
}
fn currentTools(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    const tools = try js.builtin(engine, "Map", &.{});
    defer engine.freeValue(tools);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, messages, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |message| {
        defer engine.freeValue(message);
        if (!try system(engine, message)) continue;
        try toolsDelta(engine, message, "toolsRemoved", tools, true, symbol);
        try toolsDelta(engine, message, "toolsAdded", tools, false, symbol);
    }
    const values = try js.invoke(engine, tools, "values", &.{});
    defer engine.freeValue(values);
    return arraySpread(engine, values, null);
}
fn patchSections(engine: *em.Engine, message: c.JSValue, sections: c.JSValue, symbol: c.JSValue) !void {
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const entries = try sdk.get(engine, object, "entries");
    defer engine.freeValue(entries);
    const raw = try sdk.get(engine, message, "sections");
    defer engine.freeValue(raw);
    const source = if (nullish(raw)) try sdk.object(engine) else c.JS_DupValue(engine.context, raw);
    defer engine.freeValue(source);
    const rows = try js.call(engine, entries, object, &.{source});
    defer engine.freeValue(rows);
    var iterator = try js.Iterator.init(engine, rows, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer for (pair) |value| engine.freeValue(value);
        const ignored = if (c.JS_IsNull(pair[1])) try js.invoke(engine, sections, "delete", &.{pair[0]}) else try js.invoke(engine, sections, "set", &.{ pair[0], pair[1] });
        engine.freeValue(ignored);
    }
}
pub fn currentSystemMessage(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    const content = try sdk.array(engine);
    defer engine.freeValue(content);
    const sections = try js.builtin(engine, "Map", &.{});
    defer engine.freeValue(sections);
    var timestamp = c.pi_js_undefined();
    defer engine.freeValue(timestamp);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, messages, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |message| {
        defer engine.freeValue(message);
        if (!try system(engine, message)) continue;
        if (nullish(timestamp)) {
            const next = try sdk.get(engine, message, "timestamp");
            engine.freeValue(timestamp);
            timestamp = next;
        }
        const raw = try sdk.get(engine, message, "content");
        defer engine.freeValue(raw);
        const text = try contentText(engine, raw);
        defer engine.freeValue(text);
        const length = try sdk.get(engine, text, "length");
        defer engine.freeValue(length);
        if (try positive(engine, length)) try js.push(engine, content, text);
        try patchSections(engine, message, sections, symbol);
    }
    const tools = try currentTools(engine, messages);
    defer engine.freeValue(tools);
    if (c.JS_IsUndefined(timestamp)) {
        const length = try sdk.get(engine, tools, "length");
        defer engine.freeValue(length);
        if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    }
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "role", try sdk.text(engine, "system"));
    const separator = try sdk.text(engine, "\n\n");
    defer engine.freeValue(separator);
    try sdk.put(engine, result, "content", try js.invoke(engine, content, "join", &.{separator}));
    const size = try sdk.get(engine, sections, "size");
    defer engine.freeValue(size);
    if (try positive(engine, size)) try sdk.put(engine, result, "sections", try js.objectMethod(engine, "fromEntries", sections));
    const length = try sdk.get(engine, tools, "length");
    defer engine.freeValue(length);
    if (try positive(engine, length)) try sdk.put(engine, result, "toolsAdded", c.JS_DupValue(engine.context, tools));
    try sdk.put(engine, result, "timestamp", if (nullish(timestamp)) c.JS_NewInt32(engine.context, 0) else c.JS_DupValue(engine.context, timestamp));
    return result;
}

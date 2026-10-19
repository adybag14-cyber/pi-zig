//! The actual c268 tokenizer and schema/document traversal for tool discovery.
//! Live methods, literal RegExp objects, JS recursion and iterator records are
//! retained; this does not substitute the typed durable search implementation.
const t = @import("native_sdk_tool_search_values.zig");
const h = t.h;
const v = t.v;
const c = t.c;
const Engine = t.Engine;
const Scope = t.Scope;
const Arguments = t.Arguments;
const SchemaFrame = t.Frame(enum { name, property, key, variants, variant });
const DocumentFrame = t.Frame(enum { parts });

/// One module-local record, owned by the complete tool-search factory.
pub fn create(s: *Scope) !c.JSValue {
    const module = try v.object(s);
    const stop_words = try v.own(s, try h.expression(s.engine, stopWords, .{}));
    try v.put(s, module, "stopWords", stop_words);
    try v.put(s, module, "stem", try t.function(s, "stem", 1, .{ .formal_count = 1, .callback = stemCall }, &.{}));
    try v.put(s, module, "tokenize", try t.function(s, "tokenize", 1, .{ .formal_count = 1, .callback = tokenizeCall }, &.{module}));
    try v.put(s, module, "isObject", try t.function(s, "isObject", 1, .{ .formal_count = 1, .callback = objectCall }, &.{}));
    try v.put(s, module, "schemaText", try t.function(s, "schemaText", 2,
        .{ .formal_count = 2, .callback = schemaCall, .hooks = t.sync.frameHooks(SchemaFrame) }, &.{module}));
    try v.put(s, module, "createToolSearchDocument", try t.function(s, "createToolSearchDocument", 2,
        .{ .formal_count = 2, .callback = documentCall, .hooks = t.sync.frameHooks(DocumentFrame) }, &.{module}));
    return v.duplicate(s, module);
}
fn stopWords(s: *Scope) !c.JSValue {
    const constructor = try v.global(s, "Set");
    const words = try v.array(s);
    inline for (.{"a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "with"}, 0..) |word, index| {
        try v.index(s, words, index, try v.text(s, word));
    }
    return v.duplicate(s, try v.construct(s, constructor, &.{words}));
}
fn lengthGreater(engine: *Engine, value: c.JSValue, minimum: f64) !bool {
    return h.truthy(engine, try h.expression(engine, t.fieldCompare,
        .{ value, @as([*:0]const u8, "length"), @as(h.math.Operation, .greater), h.number(engine, minimum) }));
}
fn endsWith(s: *Scope, term: c.JSValue, suffix: []const u8) !c.JSValue {
    const callee = try v.get(s, term, "endsWith");
    return v.boolean(s, v.truthy(s, try v.call(s, callee, term, &.{try v.text(s, suffix)})));
}
fn slice(s: *Scope, term: c.JSValue, end: f64) !c.JSValue {
    const callee = try v.get(s, term, "slice");
    return v.duplicate(s, try v.call(s, callee, term, &.{v.number(s, 0), v.number(s, end)}));
}
fn sliceString(s: *Scope, term: c.JSValue) !c.JSValue {
    const value = try v.own(s, try h.expression(s.engine, slice, .{term, @as(f64, -3)}));
    return v.duplicate(s, try v.stringify(s, value));
}
fn singularY(s: *Scope, term: c.JSValue) !c.JSValue {
    const prefix = try v.own(s, try h.expression(s.engine, sliceString, .{term}));
    return v.duplicate(s, try h.binary(s, .add, prefix, try v.text(s, "y")));
}
fn pluralRegex(s: *Scope, term: c.JSValue) !c.JSValue {
    const receiver = try t.literalRegex(s, "(ches|shes|sses|xes|zes)$", "");
    const callee = try v.get(s, receiver, "test");
    return v.boolean(s, v.truthy(s, try v.call(s, callee, receiver, &.{term})));
}
fn stemCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    if (try lengthGreater(engine, args.get(0), 4) and
        h.truthy(engine, try h.expression(engine, endsWith, .{args.get(0), @as([]const u8, "ies")})))
        return h.expression(engine, singularY, .{args.get(0)});
    if (try lengthGreater(engine, args.get(0), 4) and
        h.truthy(engine, try h.expression(engine, pluralRegex, .{args.get(0)})))
        return h.expression(engine, slice, .{args.get(0), @as(f64, -2)});
    if (try lengthGreater(engine, args.get(0), 3) and
        h.truthy(engine, try h.expression(engine, endsWith, .{args.get(0), @as([]const u8, "s")})) and
        !h.truthy(engine, try h.expression(engine, endsWith, .{args.get(0), @as([]const u8, "ss")})))
        return h.expression(engine, slice, .{args.get(0), @as(f64, -1)});
    return h.duplicate(engine, args.get(0));
}
fn replace(s: *Scope, receiver: c.JSValue, pattern: []const u8) !c.JSValue {
    const callee = try v.get(s, receiver, "replace");
    const regex = try t.literalRegex(s, pattern, "g");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{regex, try v.text(s, "$1 $2")}));
}
fn firstReplace(s: *Scope, text: c.JSValue) !c.JSValue {
    return replace(s, text, "([a-z0-9])([A-Z])");
}
fn secondReplace(s: *Scope, text: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, firstReplace, .{text}));
    return replace(s, receiver, "([A-Z]+)([A-Z][a-z])");
}
fn lowerCase(s: *Scope, text: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, secondReplace, .{text}));
    return v.duplicate(s, try t.invoke(s, receiver, "toLowerCase", &.{}));
}
fn split(s: *Scope, text: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, lowerCase, .{text}));
    const callee = try v.get(s, receiver, "split");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{try t.literalRegex(s, "[^a-z0-9]+", "")}));
}
fn acceptedTerm(s: *Scope, term: c.JSValue, module: c.JSValue) !c.JSValue {
    const stop_words = try v.get(s, module, "stopWords");
    return v.boolean(s, !v.truthy(s, try t.invoke(s, stop_words, "has", &.{term})));
}
fn filterTerm(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    if (!try lengthGreater(engine, args.get(0), 0)) return c.JS_NewBool(engine.context, false);
    return h.expression(engine, acceptedTerm, .{args.get(0), roots[0]});
}
fn filter(s: *Scope, text: c.JSValue, module: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, split, .{text}));
    const callee = try v.get(s, receiver, "filter");
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = filterTerm }, &.{module});
    return v.duplicate(s, try v.call(s, callee, receiver, &.{callback}));
}
fn tokenizeBody(s: *Scope, text: c.JSValue, module: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, filter, .{text, module}));
    const callee = try v.get(s, receiver, "map");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{try v.get(s, module, "stem")}));
}
fn tokenizeCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, tokenizeBody, .{args.get(0), roots[0]});
}
fn notArray(s: *Scope, value: c.JSValue) !c.JSValue {
    const array = try v.global(s, "Array");
    const method_value = try v.get(s, array, "isArray");
    return v.boolean(s, !v.truthy(s, try v.call(s, method_value, array, &.{value})));
}
fn objectCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    // typeof functions is "function", and null is excluded before Array lookup.
    const value = args.get(0);
    if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value))
        return c.JS_NewBool(engine.context, false);
    return h.expression(engine, notArray, .{value});
}
fn objectTest(s: *Scope, module: c.JSValue, value: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try t.importCall(s, module, "isObject", &.{value})));
}
fn objectFieldTest(s: *Scope, module: c.JSValue, schema: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const callable = try v.get(s, module, "isObject");
    return v.boolean(s, v.truthy(s, try v.call(s, callable, c.pi_js_undefined(), &.{try v.get(s, schema, name)})));
}
fn pushField(s: *Scope, parts: c.JSValue, schema: c.JSValue, name: [*:0]const u8) !void {
    const callee = try v.get(s, parts, "push");
    _ = try v.call(s, callee, parts, &.{try v.get(s, schema, name)});
}
fn entries(s: *Scope, schema: c.JSValue) !c.JSValue {
    const object = try v.global(s, "Object");
    const callee = try v.get(s, object, "entries");
    return v.duplicate(s, try v.call(s, callee, object, &.{try v.get(s, schema, "properties")}));
}
fn pairNext(iterator: *v.Iterator) !c.JSValue {
    if (iterator.closed) return c.pi_js_undefined();
    if (try iterator.next()) |value| return value;
    // The actual iterator opcode drops its done receiver before the binding
    // store, while its cached next method remains until the final close opcode.
    const receiver = iterator.receiver;
    iterator.receiver = c.pi_js_undefined();
    var completion = v.owned.Completion.initValue(iterator.engine, c.pi_js_undefined());
    completion.release(receiver);
    return completion.finishValue();
}
fn bindPair(frame: *SchemaFrame, iterator: *v.Iterator) !void {
    try frame.take(.name, pairNext(iterator));
    try frame.take(.property, pairNext(iterator));
    const was_closed = iterator.closed;
    iterator.closed = true;
    const next_function = iterator.next_function;
    iterator.next_function = c.pi_js_undefined();
    var completion = v.owned.Completion.initVoid(iterator.engine, {});
    completion.release(next_function);
    try completion.finishVoid();
    if (!was_closed) try h.statement(frame.engine, t.closePair, .{iterator.receiver});
}
fn properties(frame: *SchemaFrame, iterator: *v.Iterator, module: c.JSValue, parts: c.JSValue) !void {
    while (try iterator.next()) |pair| {
        // Destructuring consumes its iteration-result value after binding/close.
        var pair_iterator = try v.Iterator.initOwned(frame.engine, pair);
        try pair_iterator.finish(bindPair(frame, &pair_iterator));
        try h.discard(frame.engine, parts, "push", &.{frame.get(.name)});
        try h.statement(frame.engine, recurse, .{module, frame.get(.property), parts});
    }
}
fn recurse(s: *Scope, module: c.JSValue, schema: c.JSValue, parts: c.JSValue) !void {
    _ = try t.importCall(s, module, "schemaText", &.{schema, parts});
}
fn recurseItems(s: *Scope, module: c.JSValue, schema: c.JSValue, parts: c.JSValue) !void {
    const callee = try v.get(s, module, "schemaText");
    _ = try v.call(s, callee, c.pi_js_undefined(), &.{try v.get(s, schema, "items"), parts});
}
fn variantKeys(s: *Scope) !c.JSValue {
    const result = try v.array(s);
    inline for (.{ "anyOf", "oneOf", "allOf" }, 0..) |name, index| try v.index(s, result, index, try v.text(s, name));
    return v.duplicate(s, result);
}
fn arrayTest(s: *Scope, value: c.JSValue) !c.JSValue {
    const array = try v.global(s, "Array");
    const callee = try v.get(s, array, "isArray");
    return v.boolean(s, v.truthy(s, try v.call(s, callee, array, &.{value})));
}
fn variants(frame: *SchemaFrame, iterator: *v.Iterator, module: c.JSValue, parts: c.JSValue) !void {
    while (try iterator.next()) |value| {
        try frame.take(.variant, value);
        try h.statement(frame.engine, recurse, .{module, frame.get(.variant), parts});
    }
}
fn schemaKeys(frame: *SchemaFrame, iterator: *v.Iterator, module: c.JSValue, schema: c.JSValue, parts: c.JSValue) !void {
    while (try iterator.next()) |key| {
        try frame.take(.key, key);
        try frame.clear(.variants);
        try frame.take(.variants, h.key(frame.engine, schema, frame.get(.key)));
        if (h.truthy(frame.engine, try h.expression(frame.engine, arrayTest, .{frame.get(.variants)}))) {
            // The nested for-of head is reset when this declaration is entered.
            try frame.clear(.variant);
            var nested = try v.Iterator.init(frame.engine, frame.get(.variants));
            try nested.finish(variants(frame, &nested, module, parts));
        }
    }
}
fn schemaBody(s: *Scope, args: *Arguments, module: c.JSValue) !c.JSValue {
    const frame = try args.createFrame(s, SchemaFrame);
    if (!h.truthy(s.engine, try h.expression(s.engine, objectTest, .{module, args.get(0)})))
        return c.pi_js_undefined();
    if (try h.fieldTest(s.engine, args.get(0), "description", .string))
        try h.statement(s.engine, pushField, .{args.get(1), args.get(0), @as([*:0]const u8, "description")});
    if (h.truthy(s.engine, try h.expression(s.engine, objectFieldTest, .{module, args.get(0), @as([*:0]const u8, "properties")}))) {
        var iterator = try v.Iterator.initOwned(s.engine, try h.expression(s.engine, entries, .{args.get(0)}));
        try iterator.finish(properties(frame, &iterator, module, args.get(1)));
    }
    try h.statement(s.engine, recurseItems, .{module, args.get(0), args.get(1)});
    var keys = try v.Iterator.initOwned(s.engine, try h.expression(s.engine, variantKeys, .{}));
    try keys.finish(schemaKeys(frame, &keys, module, args.get(0), args.get(1)));
    return c.pi_js_undefined();
}
fn schemaCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, schemaBody, .{args, roots[0]});
}
fn spacedName(s: *Scope, tool: c.JSValue) !c.JSValue {
    const receiver = try v.get(s, tool, "name");
    const callee = try v.get(s, receiver, "replaceAll");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{try v.text(s, "_"), try v.text(s, " ")}));
}
fn initialParts(s: *Scope, tool: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    try v.index(s, result, 0, try v.get(s, tool, "name"));
    try v.index(s, result, 1, try v.own(s, try h.expression(s.engine, spacedName, .{tool})));
    try v.index(s, result, 2, try v.get(s, tool, "description"));
    return v.duplicate(s, result);
}
fn addSchema(s: *Scope, module: c.JSValue, tool: c.JSValue, parts: c.JSValue) !void {
    const callee = try v.get(s, module, "schemaText");
    _ = try v.call(s, callee, c.pi_js_undefined(), &.{try v.get(s, tool, "parameters"), parts});
}
fn namespaceParts(s: *Scope, parts: c.JSValue, namespace: c.JSValue) !void {
    const callee = try v.get(s, parts, "push");
    const name = try v.get(s, namespace, "name");
    const description = try v.get(s, namespace, "description");
    const selected_description = if (v.nullish(description)) try v.text(s, "") else description;
    const instructions = try v.get(s, namespace, "instructions");
    _ = try v.call(s, callee, parts, &.{name, selected_description, if (v.nullish(instructions)) try v.text(s, "") else instructions});
}
fn trimPart(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return v.invokeOwned(engine, args.get(0), "trim", &.{});
}
fn filteredParts(s: *Scope, parts: c.JSValue) !c.JSValue {
    const callee = try v.get(s, parts, "filter");
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = trimPart }, &.{});
    return v.duplicate(s, try v.call(s, callee, parts, &.{callback}));
}
fn joinedParts(s: *Scope, parts: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, filteredParts, .{parts}));
    const callee = try v.get(s, receiver, "join");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{try v.text(s, " ")}));
}
fn documentRecord(s: *Scope, tool: c.JSValue, parts: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "name", try v.get(s, tool, "name"));
    try v.put(s, result, "text", try v.own(s, try h.expression(s.engine, joinedParts, .{parts})));
    return v.duplicate(s, result);
}
fn documentBody(s: *Scope, args: *Arguments, module: c.JSValue) !c.JSValue {
    const frame = try args.createFrame(s, DocumentFrame);
    try frame.take(.parts, h.expression(s.engine, initialParts, .{args.get(0)}));
    try h.statement(s.engine, addSchema, .{module, args.get(0), frame.get(.parts)});
    if (h.truthy(s.engine, args.get(1)))
        try h.statement(s.engine, namespaceParts, .{frame.get(.parts), args.get(1)});
    return h.expression(s.engine, documentRecord, .{args.get(0), frame.get(.parts)});
}
fn documentCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, documentBody, .{args, roots[0]});
}

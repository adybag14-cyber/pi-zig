//! Original transcript tool replay, declaration comparison and AgentLoop deltas.
//! Ordinary guest methods and iterators remain observable; no durable-planner
//! reorder policy is applied to these Source algorithms.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;

pub fn currentTools(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = try scope.own(try js.builtin(engine, "Map", &.{}));
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, messages, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |message| {
        defer engine.freeValue(message);
        if (!scope.equal(try scope.get(message, "role"), try scope.text("system"))) continue;
        const removed = try scope.get(message, "toolsRemoved");
        try applyTools(&scope, tools, if (temp.nullish(removed)) try scope.array() else removed, symbol, false);
        const added = try scope.get(message, "toolsAdded");
        try applyTools(&scope, tools, if (temp.nullish(added)) try scope.array() else added, symbol, true);
    }
    const values = try scope.invoke(tools, "values", &.{});
    return c.JS_DupValue(engine.context, try arraySpread(&scope, &.{values}));
}

fn applyTools(scope: *Scope, tools: c.JSValue, deltas: c.JSValue, symbol: c.JSValue, adding: bool) !void {
    var iterator = try js.Iterator.init(scope.engine, deltas, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |tool| {
        defer scope.engine.freeValue(tool);
        const method = try scope.get(tools, if (adding) "set" else "delete");
        const name = try scope.get(tool, "name");
        _ = try scope.call(method, tools, if (adding) &.{ name, tool } else &.{name});
    }
}

fn declarationCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("native_agent_state.zig").declaration(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

pub fn declarationsEqual(engine: *em.Engine, left: c.JSValue, right: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const left_json = try scope.global("JSON");
    const left_stringify = try scope.get(left_json, "stringify");
    const left_declaration = try scope.own(try @import("native_agent_state.zig").declaration(engine, left));
    const left_text = try scope.call(left_stringify, left_json, &.{left_declaration});
    const right_json = try scope.global("JSON");
    const right_stringify = try scope.get(right_json, "stringify");
    const right_declaration = try scope.own(try @import("native_agent_state.zig").declaration(engine, right));
    return scope.equal(left_text, try scope.call(right_stringify, right_json, &.{right_declaration}));
}

fn pairCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return pair(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn pair(engine: *em.Engine, tool: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.array();
    try scope.index(result, 0, try scope.get(tool, "name"));
    try scope.index(result, 1, tool);
    return c.JS_DupValue(engine.context, result);
}

fn filterCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, removed: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return filter(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), removed != 0) catch |err| sdk.fail(engine, err);
}
fn filter(engine: *em.Engine, map: c.JSValue, tool: c.JSValue, removed: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const get = try scope.get(map, "get");
    const found = try scope.call(get, map, &.{try scope.get(tool, "name")});
    const changed = c.JS_IsUndefined(found) or !(if (removed) try declarationsEqual(engine, tool, found) else try declarationsEqual(engine, found, tool));
    return c.pi_js_bool(engine.context, @intFromBool(changed));
}
fn referenceCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return reference(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn reference(engine: *em.Engine, tool: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "name", try sdk.get(engine, tool, "name"));
    return result;
}
fn toolMap(scope: *Scope, values: c.JSValue) !c.JSValue {
    // Resolve the new-expression constructor before its map argument.
    const constructor = try scope.global("Map");
    const map = try scope.get(values, "map");
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, pairCall, "", 1)));
    const entries = try scope.call(map, values, &.{callback});
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&entries))));
}
fn changedList(scope: *Scope, values: c.JSValue, map: c.JSValue, removed: bool) !c.JSValue {
    const method = try scope.get(values, "filter");
    var roots = [_]c.JSValue{map};
    const predicate = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, filterCall, "", 1, @intFromBool(removed), roots.len, &roots)));
    const selected = try scope.call(method, values, &.{predicate});
    const mapper = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, if (removed) referenceCall else declarationCall, if (removed) "" else "toToolDeclaration", 1)));
    return scope.invoke(selected, "map", &.{mapper});
}
pub fn changes(engine: *em.Engine, previous: c.JSValue, current: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const previous_map = try toolMap(&scope, previous);
    const current_map = try toolMap(&scope, current);
    const result = try scope.object();
    try scope.put(result, "toolsAdded", try changedList(&scope, current, previous_map, false));
    try scope.put(result, "toolsRemoved", try changedList(&scope, previous, current_map, true));
    return c.JS_DupValue(engine.context, result);
}

pub fn withChanges(engine: *em.Engine, message: c.JSValue, delta: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const added = try scope.get(delta, "toolsAdded");
    const removed = try scope.get(delta, "toolsRemoved");
    _ = try scope.get(message, "toolsAdded");
    _ = try scope.get(message, "toolsRemoved");
    const result = try scope.object();
    const boxed = try scope.own(try engine.checked(c.JS_ToObject(engine.context, message)));
    const added_atom = c.JS_NewAtom(engine.context, "toolsAdded");
    if (added_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, added_atom);
    const removed_atom = c.JS_NewAtom(engine.context, "toolsRemoved");
    if (removed_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, removed_atom);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        if (entry.atom == added_atom or entry.atom == removed_atom) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return js.capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    if (try scope.positive(try scope.get(added, "length"))) try scope.put(result, "toolsAdded", added);
    if (try scope.positive(try scope.get(removed, "length"))) try scope.put(result, "toolsRemoved", removed);
    return c.JS_DupValue(engine.context, result);
}

fn replaceCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const index = if (argc > 1) argv[1] else c.pi_js_undefined();
    const message = if (argc > 0) argv[0] else c.pi_js_undefined();
    if (!c.JS_IsStrictEqual(engine.context, index, roots[0])) return c.JS_DupValue(engine.context, message);
    return withChanges(engine, roots[1], roots[2]) catch |err| sdk.fail(engine, err);
}
fn replace(scope: *Scope, values: c.JSValue, index: c.JSValue, message: c.JSValue, delta: c.JSValue) !c.JSValue {
    const map = try scope.get(values, "map");
    var roots = [_]c.JSValue{ index, message, delta };
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, replaceCall, "", 2, 0, roots.len, &roots)));
    return scope.call(map, values, &.{callback});
}
fn firstNonSystem(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const role = sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "role") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(role);
    const system = sdk.text(engine, "system") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(system);
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsStrictEqual(engine.context, role, system)));
}
pub fn arraySpread(scope: *Scope, sources: []const c.JSValue) !c.JSValue {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    const result = try scope.array();
    var index: u32 = 0;
    for (sources) |source| {
        var iterator = try js.Iterator.init(scope.engine, source, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |item| {
            defer scope.engine.freeValue(item);
            try scope.index(result, index, item);
            index += 1;
        }
    }
    return result;
}
fn concatenate(scope: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return arraySpread(scope, &.{ left, right });
}
pub fn declare(engine: *em.Engine, context: c.JSValue, pending: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var system_index: c.JSValue = c.JS_NewInt32(engine.context, -1);
    var index = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try scope.get(pending, "length"), c.JS_NewInt32(engine.context, 1))));
    while (scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 7, index, c.JS_NewInt32(engine.context, 0)))))) {
        const message = try scope.own(try js.getKey(engine, pending, index));
        if (scope.equal(try scope.get(message, "role"), try scope.text("system"))) {
            system_index = index;
            break;
        }
        index = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, index, c.JS_NewInt32(engine.context, 1))));
    }
    const system = try scope.own(try js.getKey(engine, pending, system_index));
    const empty = try scope.object();
    try scope.put(empty, "toolsAdded", try scope.array());
    try scope.put(empty, "toolsRemoved", try scope.array());
    const baseline = if (scope.truthy(system)) try replace(&scope, pending, system_index, system, empty) else pending;
    const history = try concatenate(&scope, try scope.get(context, "messages"), baseline);
    const previous = try scope.own(try currentTools(engine, history));
    const executable = try scope.get(context, "tools");
    const tool_list = if (temp.nullish(executable)) try scope.array() else executable;
    const map = try scope.get(tool_list, "map");
    const declaration = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, declarationCall, "toToolDeclaration", 1)));
    const current = try scope.call(map, tool_list, &.{declaration});
    const delta = try scope.own(try changes(engine, previous, current));
    const unchanged = scope.equal(try scope.get(try scope.get(delta, "toolsAdded"), "length"), c.JS_NewInt32(engine.context, 0)) and scope.equal(try scope.get(try scope.get(delta, "toolsRemoved"), "length"), c.JS_NewInt32(engine.context, 0));
    if (scope.truthy(system)) {
        if (unchanged) {
            const added = try scope.get(system, "toolsAdded");
            if (temp.nullish(added) or !scope.truthy(try scope.get(added, "length"))) {
                const removed = try scope.get(system, "toolsRemoved");
                if (temp.nullish(removed) or !scope.truthy(try scope.get(removed, "length"))) return c.JS_DupValue(engine.context, pending);
            }
        }
        return c.JS_DupValue(engine.context, try replace(&scope, baseline, system_index, system, delta));
    }
    if (unchanged) return c.JS_DupValue(engine.context, pending);
    const inserted = try scope.object();
    try scope.put(inserted, "role", try scope.text("system"));
    try scope.put(inserted, "content", try scope.text(""));
    try scope.put(inserted, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    const update = try scope.own(try withChanges(engine, inserted, delta));
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, firstNonSystem, "", 1)));
    const found = try scope.invoke(pending, "findIndex", &.{predicate});
    const position = if (scope.equal(found, c.JS_NewInt32(engine.context, -1))) try scope.get(pending, "length") else found;
    const before = try scope.invoke(pending, "slice", &.{ c.JS_NewInt32(engine.context, 0), position });
    const one = try scope.array();
    try scope.index(one, 0, update);
    const first = try concatenate(&scope, before, one);
    const after = try scope.invoke(pending, "slice", &.{position});
    return c.JS_DupValue(engine.context, try concatenate(&scope, first, after));
}

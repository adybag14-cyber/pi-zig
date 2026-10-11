//! Source ExtensionRunner.resolveRegisteredCommands over actual exposed JS Maps.
//! Arithmetic uses the exact interpreter operator ABI with borrowed operands.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const value = @import("native_select_list.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;

fn increment(engine: *em.Engine, current: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 0, if (c.JS_IsNull(current) or c.JS_IsUndefined(current)) c.JS_NewInt32(engine.context, 0) else current, c.JS_NewInt32(engine.context, 1)));
}

pub fn resolve(engine: *em.Engine, extensions: c.JSValue) !c.JSValue {
    const commands = try js.array(engine);
    defer engine.freeValue(commands);
    const counts = try js.builtin(engine, "Map", &.{});
    defer engine.freeValue(counts);
    const iterator_symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(iterator_symbol);
    var outer = try js.Iterator.init(engine, extensions, iterator_symbol);
    defer outer.deinit();
    errdefer outer.closePreserving();
    while (try outer.next()) |extension| {
        defer engine.freeValue(extension);
        const map = try js.get(engine, extension, "commands");
        defer engine.freeValue(map);
        const iterable = try js.invoke(engine, map, "values", &.{});
        defer engine.freeValue(iterable);
        var inner = try js.Iterator.init(engine, iterable, iterator_symbol);
        defer inner.deinit();
        errdefer inner.closePreserving();
        while (try inner.next()) |command| {
            defer engine.freeValue(command);
            try js.push(engine, commands, command);
            // counts.set is resolved before either command.name getter and
            // counts.get is resolved before the second command.name getter.
            const setter = try js.get(engine, counts, "set");
            defer engine.freeValue(setter);
            const first_name = try js.get(engine, command, "name");
            defer engine.freeValue(first_name);
            const getter = try js.get(engine, counts, "get");
            defer engine.freeValue(getter);
            const second_name = try js.get(engine, command, "name");
            defer engine.freeValue(second_name);
            const previous = try js.call(engine, getter, counts, &.{second_name});
            defer engine.freeValue(previous);
            const next = try increment(engine, previous);
            defer engine.freeValue(next);
            const ignored = try js.call(engine, setter, counts, &.{ first_name, next });
            engine.freeValue(ignored);
        }
    }
    const seen = try js.builtin(engine, "Map", &.{});
    defer engine.freeValue(seen);
    const taken = try js.builtin(engine, "Set", &.{});
    defer engine.freeValue(taken);
    const map = try js.get(engine, commands, "map");
    defer engine.freeValue(map);
    var roots = [_]c.JSValue{ counts, seen, taken };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, project, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(callback);
    return js.call(engine, map, commands, &.{callback});
}

fn suffixed(engine: *em.Engine, command: c.JSValue, occurrence: c.JSValue) !c.JSValue {
    const name = try js.get(engine, command, "name");
    defer engine.freeValue(name);
    const colon = try sdk.text(engine, ":");
    defer engine.freeValue(colon);
    return value.concat(engine, &.{ name, colon, occurrence });
}

fn project(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return projectCommand(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0], roots[1], roots[2]) catch |err| sdk.fail(engine, err);
}

fn projectCommand(engine: *em.Engine, command: c.JSValue, counts: c.JSValue, seen: c.JSValue, taken: c.JSValue) !c.JSValue {
    const getter = try js.get(engine, seen, "get");
    defer engine.freeValue(getter);
    const first_name = try js.get(engine, command, "name");
    defer engine.freeValue(first_name);
    const previous = try js.call(engine, getter, seen, &.{first_name});
    defer engine.freeValue(previous);
    const occurrence = try increment(engine, previous);
    defer engine.freeValue(occurrence);
    const setter = try js.get(engine, seen, "set");
    defer engine.freeValue(setter);
    const second_name = try js.get(engine, command, "name");
    defer engine.freeValue(second_name);
    const saved = try js.call(engine, setter, seen, &.{ second_name, occurrence });
    engine.freeValue(saved);
    const counter = try js.get(engine, counts, "get");
    defer engine.freeValue(counter);
    const third_name = try js.get(engine, command, "name");
    defer engine.freeValue(third_name);
    const counted = try js.call(engine, counter, counts, &.{third_name});
    defer engine.freeValue(counted);
    const duplicate = try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, if (c.JS_IsNull(counted) or c.JS_IsUndefined(counted)) c.JS_NewInt32(engine.context, 0) else counted, c.JS_NewInt32(engine.context, 1)));
    defer engine.freeValue(duplicate);
    var invocation = if (c.JS_ToBool(engine.context, duplicate) == 1) try suffixed(engine, command, occurrence) else try js.get(engine, command, "name");
    defer engine.freeValue(invocation);
    var suffix = c.JS_DupValue(engine.context, occurrence);
    defer engine.freeValue(suffix);
    while (true) {
        const exists = try js.invoke(engine, taken, "has", &.{invocation});
        defer engine.freeValue(exists);
        if (c.JS_ToBool(engine.context, exists) != 1) break;
        const incremented = try engine.checked(c.JS_PiIncrement(engine.context, suffix));
        engine.freeValue(suffix);
        suffix = incremented;
        const next = try suffixed(engine, command, suffix);
        engine.freeValue(invocation);
        invocation = next;
    }
    const added = try js.invoke(engine, taken, "add", &.{invocation});
    engine.freeValue(added);
    const result = try js.spread(engine, command);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "invocationName", c.JS_DupValue(engine.context, invocation));
    return result;
}

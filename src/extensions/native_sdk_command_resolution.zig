//! Source ExtensionRunner.resolveRegisteredCommands over actual exposed JS Maps.
//! Source-only prerequisite: not wired until resource rows and registration
//! snapshots share the actual owned runtime graph. Keep the qualified500 path.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const value = @import("native_select_list.zig");
const arithmetic = @import("native_tui_value_arithmetic.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
extern "c" fn JS_GetToPrimitiveSymbol(context: ?*c.JSContext) c.JSValue;

fn increment(engine: *em.Engine, current: c.JSValue, symbol: c.JSValue) !c.JSValue {
    return arithmetic.add(engine, if (c.JS_IsNull(current) or c.JS_IsUndefined(current)) c.JS_NewInt32(engine.context, 0) else current, c.JS_NewInt32(engine.context, 1), symbol);
}

pub fn resolve(engine: *em.Engine, extensions: c.JSValue) !c.JSValue {
    const commands = try js.array(engine);
    defer engine.freeValue(commands);
    const counts = try js.builtin(engine, "Map", &.{});
    defer engine.freeValue(counts);
    const iterator_symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(iterator_symbol);
    const primitive_symbol = try engine.checked(JS_GetToPrimitiveSymbol(engine.context));
    defer engine.freeValue(primitive_symbol);
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
            const next = try increment(engine, previous, primitive_symbol);
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
    var roots = [_]c.JSValue{ counts, seen, taken, primitive_symbol };
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
    return projectCommand(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0], roots[1], roots[2], roots[3]) catch |err| sdk.fail(engine, err);
}

fn projectCommand(engine: *em.Engine, command: c.JSValue, counts: c.JSValue, seen: c.JSValue, taken: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const getter = try js.get(engine, seen, "get");
    defer engine.freeValue(getter);
    const first_name = try js.get(engine, command, "name");
    defer engine.freeValue(first_name);
    const previous = try js.call(engine, getter, seen, &.{first_name});
    defer engine.freeValue(previous);
    const occurrence = try increment(engine, previous, symbol);
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
    // The actual Source501 callbacks retain numeric counts. General mutated
    // BigInt count/addition semantics require a separate operator prerequisite.
    const count = if (c.JS_IsNull(counted) or c.JS_IsUndefined(counted)) 0 else try value.number(engine, counted);
    var invocation = if (count > 1) try suffixed(engine, command, occurrence) else try js.get(engine, command, "name");
    defer engine.freeValue(invocation);
    var suffix = c.JS_DupValue(engine.context, occurrence);
    defer engine.freeValue(suffix);
    while (true) {
        const exists = try js.invoke(engine, taken, "has", &.{invocation});
        defer engine.freeValue(exists);
        if (c.JS_ToBool(engine.context, exists) != 1) break;
        const numeric = try value.number(engine, suffix);
        engine.freeValue(suffix);
        suffix = value.numeric(engine, numeric + 1);
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

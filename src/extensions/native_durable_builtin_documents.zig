//! Executable built-in document definitions used by native workflows.
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const json = @import("../durable/backend/json.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    inline for (.{ "LiveDoc", "InboxDoc", "UsageDoc", "ProviderDoc" }, .{ "pi.live", "pi.inbox", "pi.usage", "pi.provider" }, 0..) |name, kind, operation| {
        const definition = try sdk.object(engine);
        defer engine.freeValue(definition);
        try sdk.put(engine, definition, "kind", try sdk.text(engine, kind));
        try sdk.put(engine, definition, "version", c.JS_NewInt64(engine.context, 1));
        try sdk.put(engine, definition, "scope", try sdk.text(engine, "conversation"));
        try sdk.put(engine, definition, "history", try sdk.text(engine, "latest"));
        try sdk.put(engine, definition, "fork", try sdk.text(engine, "initial"));
        try sdk.put(engine, definition, "initial", try engine.checked(c.pi_js_function_magic(engine.context, initial, "initial", 0, @intCast(operation))));
        try sdk.put(engine, definition, "checkpointWhen", try engine.checked(c.pi_js_function_magic(engine.context, checkpoint, "checkpointWhen", 1, @intCast(operation))));
        const token = try sdk.object(engine);
        errdefer engine.freeValue(token);
        try sdk.put(engine, token, "definition", c.JS_DupValue(engine.context, definition));
        try sdk.put(engine, exports, name, token);
    }
    const nested = try sdk.object(engine);
    defer engine.freeValue(nested);
    try sdk.put(engine, nested, "kind", try sdk.text(engine, "pi.tool.nested-call"));
    try sdk.put(engine, nested, "version", c.JS_NewInt64(engine.context, 1));
    try sdk.put(engine, nested, "scope", try sdk.text(engine, "task"));
    try sdk.put(engine, nested, "family", c.pi_js_bool(engine.context, 1));
    try sdk.put(engine, nested, "initial", try engine.checked(c.JS_NewCFunction(engine.context, nestedInitial, "initial", 0)));
    const nested_token = try sdk.object(engine);
    errdefer engine.freeValue(nested_token);
    try sdk.put(engine, nested_token, "definition", c.JS_DupValue(engine.context, nested));
    try sdk.put(engine, exports, "NestedCallDoc", nested_token);
}
fn nestedInitial(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return sdk.object(engine) catch |err| durable.reject(engine, err);
}
fn initial(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return initialOwned(engine, operation) catch |err| durable.reject(engine, err);
}
fn initialOwned(engine: *Engine, operation: c_int) !c.JSValue {
    var data = try json.Owned.parse(engine.gpa, switch (operation) {
        1 => "{\"items\":[]}",
        2 => "{\"models\":{},\"tools\":{}}",
        else => "{}",
    });
    defer data.deinit();
    if (operation == 3) try data.value.object.put(data.arena.allocator(), "sessionId", .{ .string = try @import("native_durable_harness.zig").uuid(engine, data.arena.allocator()) });
    return durable.jsValue(engine, data.value);
}
fn checkpoint(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return checkpointOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), operation) catch |err| durable.reject(engine, err);
}
fn checkpointOwned(engine: *Engine, value: c.JSValue, operation: c_int) !c.JSValue {
    if (operation >= 2) return c.pi_js_bool(engine.context, 1);
    if (operation == 1) {
        const items = try sdk.get(engine, value, "items");
        defer engine.freeValue(items);
        return c.pi_js_bool(engine.context, @intFromBool(try sdk.length(engine, items) == 0));
    }
    const generation = try sdk.get(engine, value, "generation");
    defer engine.freeValue(generation);
    if (!c.JS_IsUndefined(generation)) return c.pi_js_bool(engine.context, 0);
    inline for (.{ "tools", "nestedTools" }) |property| {
        const slots = try sdk.get(engine, value, property);
        defer engine.freeValue(slots);
        const array = if (c.JS_IsUndefined(slots) or c.JS_IsNull(slots)) try sdk.array(engine) else c.JS_DupValue(engine.context, slots);
        defer engine.freeValue(array);
        const predicate = try engine.checked(c.JS_NewCFunction(engine.context, slotRunning, "", 1));
        defer engine.freeValue(predicate);
        const found = try sdk.invoke(engine, array, "some", &.{predicate});
        defer engine.freeValue(found);
        if (c.JS_ToBool(engine.context, found) != 0) return c.pi_js_bool(engine.context, 0);
    }
    return c.pi_js_bool(engine.context, 1);
}
fn slotRunning(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return slotRunningOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn slotRunningOwned(engine: *Engine, slot: c.JSValue) !c.JSValue {
    const status = try sdk.get(engine, slot, "status");
    defer engine.freeValue(status);
    if (!c.JS_IsString(status)) return c.pi_js_bool(engine.context, 0);
    const text = try engine.toString(status);
    defer engine.gpa.free(text);
    return c.pi_js_bool(engine.context, @intFromBool(@import("std").mem.eql(u8, text, "running")));
}

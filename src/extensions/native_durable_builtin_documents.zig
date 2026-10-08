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
    const tools = try sdk.get(engine, value, "tools");
    defer engine.freeValue(tools);
    if (!c.JS_IsUndefined(tools) and !c.JS_IsNull(tools)) for (0..try sdk.length(engine, tools)) |index| {
        const slot = try engine.checked(c.JS_GetPropertyUint32(engine.context, tools, @intCast(index)));
        defer engine.freeValue(slot);
        const status = try sdk.get(engine, slot, "status");
        defer engine.freeValue(status);
        if (c.JS_IsString(status)) {
            const label = try engine.toString(status);
            defer engine.gpa.free(label);
            if (@import("std").mem.eql(u8, label, "running")) return c.pi_js_bool(engine.context, 0);
        }
    };
    return c.pi_js_bool(engine.context, 1);
}

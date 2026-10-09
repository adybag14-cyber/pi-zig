//! Actual SDK AgentSession state access and Source shallow array assignment.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
pub fn view(engine: *em.Engine, initial: c.JSValue) !c.JSValue {
    const backing = try sdk.object(engine);
    defer engine.freeValue(backing);
    inline for (.{ "messages", "tools" }, 0..) |key, index| {
        const value = try sdk.get(engine, initial, key);
        defer engine.freeValue(value);
        const copied = try sdk.invoke(engine, value, "slice", &.{});
        try sdk.put(engine, backing, key, copied);
        const atom = c.JS_NewAtom(engine.context, key);
        defer c.JS_FreeAtom(engine.context, atom);
        var data = [_]c.JSValue{backing};
        const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, arrayField, key, 0, @intCast(index * 2), 1, &data));
        var consumed = false;
        errdefer if (!consumed) engine.freeValue(getter);
        const setter = try engine.checked(c.JS_NewCFunctionData2(engine.context, arrayField, key, 1, @intCast(index * 2 + 1), 1, &data));
        consumed = true;
        if (c.JS_DefinePropertyGetSet(engine.context, initial, atom, getter, setter, c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return error.JavaScriptException;
    }
    return c.JS_DupValue(engine.context, initial);
}
fn arrayField(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const key: [*:0]const u8 = if (magic < 2) "messages" else "tools";
    if (@mod(magic, 2) == 0) return sdk.get(engine, data[0], key) catch |err| sdk.fail(engine, err);
    const copied = sdk.invoke(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "slice", &.{}) catch |err| return sdk.fail(engine, err);
    sdk.put(engine, data[0], key, copied) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
pub fn lastAssistantText(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    const messages = try sdk.agentField(owner, "messages");
    defer engine.freeValue(messages);
    var index = try sdk.length(engine, messages);
    while (index > 0) {
        index -= 1;
        const message = try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, index));
        defer engine.freeValue(message);
        const role = try sdk.get(engine, message, "role");
        defer engine.freeValue(role);
        const name = try engine.toString(role);
        defer engine.gpa.free(name);
        if (!std.mem.eql(u8, name, "assistant")) continue;
        const content = try sdk.get(engine, message, "content");
        defer engine.freeValue(content);
        const stop = try sdk.get(engine, message, "stopReason");
        defer engine.freeValue(stop);
        const stopped = try engine.toString(stop);
        defer engine.gpa.free(stopped);
        const count = try sdk.length(engine, content);
        if (std.mem.eql(u8, stopped, "aborted") and count == 0) continue;
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(engine.gpa);
        for (0..count) |part_index| {
            const part = try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(part_index)));
            defer engine.freeValue(part);
            const typ = try sdk.get(engine, part, "type");
            defer engine.freeValue(typ);
            const kind = try engine.toString(typ);
            defer engine.gpa.free(kind);
            if (!std.mem.eql(u8, kind, "text")) continue;
            const value = try sdk.get(engine, part, "text");
            defer engine.freeValue(value);
            const raw = try engine.toString(value);
            defer engine.gpa.free(raw);
            try text.appendSlice(engine.gpa, raw);
        }
        const value = try sdk.text(engine, text.items);
        defer engine.freeValue(value);
        const trimmed = try sdk.invoke(engine, value, "trim", &.{});
        if (c.JS_ToBool(engine.context, trimmed) == 1) return trimmed;
        engine.freeValue(trimmed);
        return c.pi_js_undefined();
    }
    return c.pi_js_undefined();
}

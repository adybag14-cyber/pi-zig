//! Live AgentSession registry and transcript queries through the owner C VM.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const catalog = @import("native_sdk_tool_catalog.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Operation = enum(c_int) { callable_names, callable_tools, exposure, fork_messages };

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (.{
        .{ "getCallableToolNames", Operation.callable_names, 0 },
        .{ "_getCallableTools", Operation.callable_tools, 0 },
        .{ "_getToolExposure", Operation.exposure, 1 },
        .{ "getUserMessagesForForking", Operation.fork_messages, 0 },
    }) |entry| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, callback, entry[0], entry[2], @intFromEnum(entry[1])));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}

fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return dispatch(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

fn nameOf(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "name") catch |err| sdk.fail(engine, err);
}

fn dispatch(engine: *em.Engine, receiver: c.JSValue, operation: Operation, argument: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (operation) {
        .callable_names => {
            // Source calls the live private method, then the returned value's
            // live map. User overrides and getter errors retain their identity.
            const tools = try scope.invoke(receiver, "_getCallableTools", &.{});
            const map = try scope.get(tools, "map");
            const mapper = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, nameOf, "", 1)));
            return js.call(engine, map, tools, &.{mapper});
        },
        .callable_tools => {
            const owner = try sdk.state(engine, receiver);
            const active = if (c.JS_IsUndefined(argument)) try scope.own(try js.builtin(engine, "Set", &.{try scope.invoke(receiver, "getActiveToolNames", &.{})})) else argument;
            return catalog.callableDefinitionsWithActive(owner, receiver, active);
        },
        .exposure => {
            const owner = try sdk.state(engine, receiver);
            const definition = try scope.own(try catalog.getDefinition(owner, argument));
            const exposure = if (c.JS_IsUndefined(definition)) c.pi_js_undefined() else try scope.get(definition, "exposure");
            return if (c.JS_IsNull(exposure) or c.JS_IsUndefined(exposure)) sdk.text(engine, "direct") else c.JS_DupValue(engine.context, exposure);
        },
        .fork_messages => return forkMessages(&scope, receiver),
    }
}

pub fn forkMessages(scope: *Scope, receiver: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const entries = try scope.invoke(try scope.get(receiver, "sessionManager"), "getEntries", &.{});
    const result = try scope.array();
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, entries, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const message_type = try scope.text("message");
    const user_role = try scope.text("user");
    const separator = try scope.text("");
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        if (!scope.equal(try scope.get(entry, "type"), message_type)) continue;
        if (!scope.equal(try scope.get(try scope.get(entry, "message"), "role"), user_role)) continue;
        // These are two separate entry.message evaluations in Source.
        const content = try scope.get(try scope.get(entry, "message"), "content");
        const text = try scope.own(try @import("native_sdk_transcript_replay.zig").contentTextWithSeparator(engine, content, separator));
        if (!scope.truthy(text)) continue;
        const push = try scope.get(result, "push");
        const row = try scope.object();
        try scope.put(row, "entryId", try scope.get(entry, "id"));
        try scope.put(row, "text", text);
        _ = try scope.call(push, result, &.{row});
    }
    return c.JS_DupValue(engine.context, result);
}

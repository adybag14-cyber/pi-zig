//! Original AgentSession._prepareRun over explicit live receiver dependencies.
//! This private component never activates an incomplete AgentSession factory.
const em = @import("engine.zig");
const std = @import("std");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Stage = enum(c_int) { compacted, handlers, images };

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const method = try engine.checked(c.JS_NewCFunction(engine.context, start, "_prepareRun", 1));
    defer engine.freeValue(method);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, method, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "_prepareRun", c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    const last = try engine.checked(c.JS_NewCFunction(engine.context, lastAssistant, "_findLastAssistantMessage", 0));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "_findLastAssistantMessage", last, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try sdk.put(engine, prototype, "getActiveToolNames", try engine.checked(c.JS_NewCFunction(engine.context, activeTools, "getActiveToolNames", 0)));
}
fn start(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, receiver: c.JSValue, trigger: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, trigger) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, trigger: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "trigger", trigger);
    const receiver = try scope.get(owner, "agent");
    const last = try scope.invoke(receiver, "_findLastAssistantMessage", &.{});
    if (scope.truthy(last)) {
        const result = try scope.invoke(receiver, "_checkCompaction", &.{ last, c.pi_js_bool(engine.context, 0) });
        return flow.wait(continuation, engine, owner, result, @intFromEnum(Stage.compacted));
    }
    try emitBeforeStart(engine, owner);
}
fn emitBeforeStart(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    try scope.put(owner, "selectedBefore", try scope.get(try scope.get(receiver, "_baseSystemPromptOptions"), "selectedTools"));
    const runner = try scope.get(receiver, "_extensionRunner");
    const emit = try scope.get(runner, "emitBeforeAgentStart");
    const trigger = try scope.get(owner, "trigger");
    const options = try scope.get(receiver, "_baseSystemPromptOptions");
    const result = try scope.call(emit, runner, &.{ trigger, options });
    try flow.wait(continuation, engine, owner, result, @intFromEnum(Stage.handlers));
}
fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    switch (@as(Stage, @enumFromInt(magic))) {
        .compacted => try emitBeforeStart(engine, owner),
        .handlers => {
            try scope.put(owner, "result", value);
            const before = try scope.get(owner, "selectedBefore");
            const selected = try scope.get(try scope.get(value, "systemPromptOptions"), "selectedTools");
            var edited = !scope.equal(try scope.get(selected, "length"), try scope.get(before, "length"));
            if (!edited) {
                // Call the actual .some method, preserving custom arrays,
                // getters and its own length/iteration semantics.
                const again = try scope.get(try scope.get(value, "systemPromptOptions"), "selectedTools");
                const some = try scope.get(again, "some");
                var roots = [_]c.JSValue{before};
                const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, differs, "", 2, 0, roots.len, &roots)));
                edited = scope.truthy(try scope.call(some, again, &.{callback}));
            }
            if (!edited) {
                const options = try scope.get(value, "systemPromptOptions");
                try scope.set(options, "selectedTools", try scope.invoke(receiver, "getActiveToolNames", &.{}));
            }
            const messages = try scope.array();
            try scope.put(owner, "messages", messages);
            const trigger = try scope.get(owner, "trigger");
            if (scope.equal(try scope.get(trigger, "messageType"), try scope.text("custom"))) {
                const push = try scope.get(messages, "push");
                _ = try scope.call(push, messages, &.{try scope.get(trigger, "message")});
                return finish(engine, owner);
            }
            const normalize = try scope.get(receiver, "_normalizePromptImages");
            const normalized = try scope.call(normalize, receiver, &.{try scope.get(trigger, "images")});
            try flow.wait(continuation, engine, owner, normalized, @intFromEnum(Stage.images));
        },
        .images => {
            const trigger = try scope.get(owner, "trigger");
            const hints = try scope.get(value, "hints");
            const text = if (try scope.positive(try scope.get(hints, "length"))) blk: {
                const prompt = try scope.stringify(try scope.get(trigger, "prompt"));
                const prefix = try scope.concat(prompt, try scope.text("\n\n"));
                break :blk try scope.concat(prefix, try scope.stringify(try scope.invoke(try scope.get(value, "hints"), "join", &.{try scope.text("\n")})));
            } else try scope.get(trigger, "prompt");
            const messages = try scope.get(owner, "messages");
            const push = try scope.get(messages, "push");
            const message = try scope.object();
            try scope.put(message, "role", try scope.text("user"));
            const content = try scope.array();
            const part = try scope.object();
            try scope.put(part, "type", try scope.text("text"));
            try scope.put(part, "text", text);
            try scope.index(content, 0, part);
            try appendSpread(&scope, content, try scope.get(value, "images"), null);
            try scope.put(message, "content", content);
            try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
            _ = try scope.call(push, messages, &.{message});
            try finish(engine, owner);
        },
    }
}
fn differs(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const name = if (argc > 0) argv[0] else c.pi_js_undefined();
    const index = if (argc > 1) argv[1] else c.pi_js_undefined();
    const before = js.getKey(engine, roots[0], index) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(before);
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsStrictEqual(engine.context, name, before)));
}
fn appendSpread(scope: *Scope, target: c.JSValue, iterable: c.JSValue, push: ?c.JSValue) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, iterable, symbol);
    defer iterator.deinit();
    // Spread fully evaluates its arguments before invoking push.
    var collected: std.ArrayList(c.JSValue) = .empty;
    defer collected.deinit(scope.engine.gpa);
    while (try iterator.next()) |item| {
        try collected.append(scope.engine.gpa, try scope.own(item));
    }
    if (push) |function| {
        _ = try scope.call(function, target, collected.items);
    } else {
        const initial: u32 = @intCast(try sdk.length(scope.engine, target));
        for (collected.items, 0..) |item, index| {
            try scope.index(target, initial + @as(u32, @intCast(index)), item);
        }
    }
}
fn finish(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const messages = try scope.get(owner, "messages");
    const pending_push = try scope.get(messages, "push");
    try appendSpread(&scope, messages, try scope.get(receiver, "_pendingNextTurnMessages"), pending_push);
    try scope.set(receiver, "_pendingNextTurnMessages", try scope.array());
    const result = try scope.get(owner, "result");
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, try scope.get(result, "messages"), symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const push = try scope.get(messages, "push");
        const message = try scope.object();
        try scope.put(message, "role", try scope.text("custom"));
        try scope.put(message, "customType", try scope.get(entry, "customType"));
        const content = try scope.get(entry, "content");
        try scope.put(message, "content", if (temp.nullish(content)) try scope.array() else content);
        try scope.put(message, "display", try scope.get(entry, "display"));
        try scope.put(message, "details", try scope.get(entry, "details"));
        try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
        _ = try scope.call(push, messages, &.{message});
    }
    const prepare = try scope.get(receiver, "_preparePromptAndToolLoadout");
    const update = try scope.call(prepare, receiver, &.{try scope.get(result, "systemPromptOptions")});
    try scope.set(receiver, "_runSystemPromptOptions", try scope.get(result, "systemPromptOptions"));
    if (scope.truthy(update)) _ = try scope.invoke(messages, "unshift", &.{update});
    try flow.settle(engine, owner, false, messages);
}
fn lastAssistant(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return findLast(engine, receiver) catch |err| sdk.fail(engine, err);
}
fn findLast(engine: *em.Engine, receiver: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = try scope.get(try scope.get(try scope.get(receiver, "agent"), "state"), "messages");
    var count = try sdk.length(engine, messages);
    while (count > 0) {
        count -= 1;
        const message = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(count))));
        if (scope.equal(try scope.get(message, "role"), try scope.text("assistant"))) return c.JS_DupValue(engine.context, message);
    }
    return c.pi_js_undefined();
}
fn toolName(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "name") catch |err| sdk.fail(engine, err);
}
fn activeTools(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return names(engine, receiver) catch |err| sdk.fail(engine, err);
}
fn names(engine: *em.Engine, receiver: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = try scope.get(try scope.get(try scope.get(receiver, "agent"), "state"), "tools");
    const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, toolName, "", 1)));
    return c.JS_DupValue(engine.context, try scope.invoke(tools, "map", &.{callback}));
}

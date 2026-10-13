//! Original ordinary session queue admission and public steer/followUp methods.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Method = enum(c_int) { _queueSteer, _queueFollowUp, _throwIfExtensionCommand, _queueUserInput, steer, followUp };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (@import("std").meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, switch (method) {
            ._queueUserInput => 4,
            .steer, .followUp => 3,
            ._queueSteer, ._queueFollowUp => 2,
            ._throwIfExtensionCommand => 1,
        }, field.value, 0, null));
        defer engine.freeValue(function);
        if (method != ._throwIfExtensionCommand) {
            const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(parent);
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn arg(argc: c_int, argv: [*c]c.JSValue, index: usize) c.JSValue {
    return if (index < @as(usize, @intCast(argc))) argv[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(magic);
    if (method == ._throwIfExtensionCommand) {
        throwIfCommand(engine, receiver, arg(argc, argv, 0)) catch |err| return sdk.fail(engine, err);
        return c.pi_js_undefined();
    }
    const pending = flow.create(engine, receiver) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(pending.owner);
    begin(engine, pending.owner, method, .{ arg(argc, argv, 0), arg(argc, argv, 1), arg(argc, argv, 2), arg(argc, argv, 3) }) catch |err| {
        flow.rejectError(engine, pending.owner, err) catch |failure| {
            engine.freeValue(pending.promise);
            return sdk.fail(engine, failure);
        };
    };
    return pending.promise;
}
fn begin(engine: *em.Engine, owner: c.JSValue, method: Method, args: [4]c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    switch (method) {
        ._queueSteer, ._queueFollowUp => {
            try enqueue(&scope, session, args[0], args[1], method == ._queueFollowUp);
            try flow.settle(engine, owner, false, c.pi_js_undefined());
        },
        .steer, .followUp => {
            const function = try scope.get(session, "_queueUserInput");
            const source = if (temp.nullish(args[2])) c.pi_js_undefined() else try scope.get(args[2], "source");
            const pending = try scope.call(function, session, &.{ args[0], args[1], try scope.text(if (method == .steer) "steer" else "followUp"), if (temp.nullish(source)) try scope.text("interactive") else source });
            try flow.wait(returned, engine, owner, pending, 0);
        },
        ._queueUserInput => {
            if (scope.truthy(try scope.invoke(args[0], "startsWith", &.{try scope.text("/")}))) _ = try scope.invoke(session, "_throwIfExtensionCommand", &.{args[0]});
            try scope.put(owner, "behavior", args[2]);
            const function = try scope.get(session, "_runInputHandlers");
            const behavior = if (scope.truthy(try scope.get(session, "isStreaming"))) args[2] else c.pi_js_undefined();
            const pending = try scope.call(function, session, &.{ args[0], args[1], args[3], behavior });
            try flow.wait(processed, engine, owner, pending, 0);
        },
        ._throwIfExtensionCommand => unreachable,
    }
}
fn enqueue(scope: *Scope, session: c.JSValue, text: c.JSValue, images: c.JSValue, follow_up: bool) !void {
    const engine = scope.engine;
    _ = try scope.invoke(try scope.get(session, if (follow_up) "_followUpMessages" else "_steeringMessages"), "push", &.{text});
    _ = try scope.invoke(session, "_emitQueueUpdate", &.{});
    const content = try scope.array();
    const item = try scope.object();
    try scope.put(item, "type", try scope.text("text"));
    try scope.put(item, "text", text);
    try scope.index(content, 0, item);
    if (scope.truthy(images)) {
        const push = try scope.get(content, "push");
        const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
        const snapshot = try scope.own(try js.collect(engine, images, symbol));
        const count = try sdk.length(engine, snapshot);
        const args = try engine.gpa.alloc(c.JSValue, count);
        defer engine.gpa.free(args);
        for (args, 0..) |*value, index| value.* = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, snapshot, @intCast(index))));
        _ = try scope.call(push, content, args);
    }
    const agent = try scope.get(session, "agent");
    const function = try scope.get(agent, if (follow_up) "followUp" else "steer");
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("user"));
    try scope.put(message, "content", content);
    try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    _ = try scope.call(function, agent, &.{message});
}
fn returned(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, value);
}
fn processed(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(value)) return flow.settle(engine, owner, false, try scope.text("handled"));
    const session = try scope.get(owner, "agent");
    const expand = try scope.get(session, "_expandSkillCommand");
    var text = try scope.call(expand, session, &.{try scope.get(value, "text")});
    const snapshot = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, try scope.get(session, "promptTemplates")));
    text = try scope.own(try @import("native_sdk_prompt_expansion.zig").expandTemplateWithEngine(engine, text, snapshot));
    const behavior = try scope.get(owner, "behavior");
    const function = try scope.get(session, if (scope.equal(behavior, try scope.text("steer"))) "_queueSteer" else "_queueFollowUp");
    const pending = try scope.call(function, session, &.{ text, try scope.get(value, "images") });
    try flow.wait(queued, engine, owner, pending, 0);
}
fn queued(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    const result = try sdk.text(engine, "queued");
    defer engine.freeValue(result);
    try flow.settle(engine, owner, false, result);
}
fn throwIfCommand(engine: *em.Engine, session: c.JSValue, text: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const index = try scope.invoke(text, "indexOf", &.{try scope.text(" ")});
    const name = if (scope.equal(index, c.JS_NewInt32(engine.context, -1))) try scope.invoke(text, "slice", &.{c.JS_NewInt32(engine.context, 1)}) else try scope.invoke(text, "slice", &.{ c.JS_NewInt32(engine.context, 1), index });
    if (scope.truthy(try scope.invoke(try scope.get(session, "_extensionRunner"), "getCommand", &.{name}))) {
        const constructor = try scope.global("Error");
        const message = try scope.concat(try scope.concat(try scope.text("Extension command \"/"), try scope.stringify(name)), try scope.text("\" cannot be queued. Use prompt() or execute the command when not streaming."));
        var args = [_]c.JSValue{message};
        const reason = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
        _ = try engine.checked(c.JS_Throw(engine.context, reason));
    }
}

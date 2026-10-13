//! Original public AgentSession.prompt body over ordinary live fields. The
//! full runtime methods must be installed independently; no replacement run
//! loop or successful placeholder is supplied by this module.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const auth = @import("native_sdk_prompt_auth.zig");
const c = em.c;
const Stage = enum(c_int) { command, input, queued, auth, started };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, dispatch, "prompt", 2));
    defer engine.freeValue(function);
    try asyncPrototype(engine, function);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "prompt", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn asyncPrototype(engine: *em.Engine, function: c.JSValue) !void {
    const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, session: c.JSValue, text: c.JSValue, options: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initial(engine, pending.owner, text, options) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn optional(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, name);
}
fn initial(engine: *em.Engine, owner: c.JSValue, text: c.JSValue, options: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(session, "_isEmittingAgentSettled"))) {
        const actions = try scope.get(session, "_deferredSettledActions");
        const push = try scope.get(actions, "push");
        var roots = [_]c.JSValue{ session, text, options };
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, deferred, "", 0, 0, roots.len, &roots)));
        try asyncPrototype(engine, callback);
        _ = try scope.call(push, actions, &.{callback});
        return flow.settle(engine, owner, false, c.pi_js_undefined());
    }
    try scope.put(owner, "text", text);
    try scope.put(owner, "options", options);
    const expand = try optional(&scope, options, "expandPromptTemplates");
    try scope.put(owner, "expand", if (temp.nullish(expand)) c.pi_js_bool(engine.context, 1) else expand);
    try scope.put(owner, "preflight", try optional(&scope, options, "preflightResult"));
    if (scope.truthy(try scope.get(owner, "expand")) and scope.truthy(try scope.invoke(text, "startsWith", &.{try scope.text("/")}))) {
        const pending = try scope.invoke(session, "_tryExecuteExtensionCommand", &.{text});
        return wait(engine, owner, pending, .command);
    }
    try input(engine, owner);
}
fn deferred(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const pending = flow.create(engine, roots[0]) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(pending.owner);
    deferInvocation(engine, pending.owner, roots[1], roots[2]) catch |err| {
        flow.rejectError(engine, pending.owner, err) catch |failure| {
            engine.freeValue(pending.promise);
            return sdk.fail(engine, failure);
        };
    };
    return pending.promise;
}
fn deferInvocation(engine: *em.Engine, owner: c.JSValue, text: c.JSValue, options: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const pending = try scope.invoke(session, "prompt", &.{ text, options });
    try flow.wait(deferredComplete, engine, owner, pending, 0);
}
fn deferredComplete(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, value);
}
fn input(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    if (!c.JS_IsUndefined(try scope.get(session, "_compactionAbortController"))) return raise(&scope, "Cannot submit a prompt while compaction is in progress. Wait for compaction to finish and retry.");
    const method = try scope.get(session, "_runInputHandlers");
    const text = try scope.get(owner, "text");
    const options = try scope.get(owner, "options");
    const images = try optional(&scope, options, "images");
    const source = try optional(&scope, options, "source");
    const behavior = if (scope.truthy(try scope.get(session, "isStreaming"))) try optional(&scope, options, "streamingBehavior") else c.pi_js_undefined();
    const pending = try scope.call(method, session, &.{ text, images, if (temp.nullish(source)) try scope.text("interactive") else source, behavior });
    try wait(engine, owner, pending, .input);
}
fn raise(scope: *Scope, message: []const u8) !void {
    const constructor = try scope.global("Error");
    var args = [_]c.JSValue{try scope.text(message)};
    const reason = try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args));
    _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, reason));
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(continued, engine, owner, value, @intFromEnum(stage));
}
fn continued(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    const stage: Stage = @enumFromInt(magic);
    switch (stage) {
        .command => {
            if (c.JS_ToBool(engine.context, value) == 1) return completeDisposition(engine, owner, "handled");
            try input(engine, owner);
        },
        .input => {
            if (c.JS_ToBool(engine.context, value) != 1) return completeDisposition(engine, owner, "handled");
            try processed(engine, owner, value);
        },
        .queued => try completeDisposition(engine, owner, "queued"),
        .auth => {
            const session = try sdk.get(engine, owner, "agent");
            defer engine.freeValue(session);
            try auth.finishLive(engine, session, value);
            try start(engine, owner);
        },
        .started => try flow.settle(engine, owner, false, c.pi_js_undefined()),
    }
}
fn completeDisposition(engine: *em.Engine, owner: c.JSValue, disposition: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const callback = try scope.get(owner, "preflight");
    if (!temp.nullish(callback)) _ = try scope.call(callback, c.pi_js_undefined(), &.{try scope.text(disposition)});
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn processed(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    var text = try scope.get(value, "text");
    const images = try scope.get(value, "images");
    if (scope.truthy(try scope.get(owner, "expand"))) {
        text = try scope.invoke(session, "_expandSkillCommand", &.{text});
        const snapshot = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, try scope.get(session, "promptTemplates")));
        text = try scope.own(try @import("native_sdk_prompt_expansion.zig").expandTemplateWithEngine(engine, text, snapshot));
    }
    try scope.put(owner, "expanded", text);
    try scope.put(owner, "currentImages", images);
    if (scope.truthy(try scope.get(session, "isStreaming"))) {
        const options = try scope.get(owner, "options");
        if (!scope.truthy(try optional(&scope, options, "streamingBehavior"))) return raise(&scope, "Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message.");
        const behavior = try scope.get(options, "streamingBehavior");
        const result = try scope.invoke(session, if (scope.equal(behavior, try scope.text("followUp"))) "_queueFollowUp" else "_queueSteer", &.{ text, images });
        return wait(engine, owner, result, .queued);
    }
    if (try auth.beginLive(engine, session)) |pending| {
        defer engine.freeValue(pending);
        return wait(engine, owner, pending, .auth);
    }
    try start(engine, owner);
}
fn start(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const method = try scope.get(session, "_startRun");
    const trigger = try scope.object();
    try scope.put(trigger, "messageType", try scope.text("user"));
    try scope.put(trigger, "prompt", try scope.get(owner, "expanded"));
    try scope.put(trigger, "images", try scope.get(owner, "currentImages"));
    var roots = [_]c.JSValue{try scope.get(owner, "preflight")};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, started, "", 0, 0, roots.len, &roots)));
    const pending = try scope.call(method, session, &.{ trigger, callback });
    try wait(engine, owner, pending, .started);
}
fn started(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (temp.nullish(roots[0])) return c.pi_js_undefined();
    const text = sdk.text(engine, "started") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(text);
    return js.call(engine, roots[0], c.pi_js_undefined(), &.{text}) catch |err| sdk.fail(engine, err);
}

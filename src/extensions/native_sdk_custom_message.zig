//! Original custom-message ingestion and transcript helpers. These functions
//! remain private components until the complete session run owner is wired.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    const method = try engine.checked(c.JS_NewCFunction(engine.context, send, "sendCustomMessage", 2));
    errdefer engine.freeValue(method);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, method, parent) < 0) return js.capture(engine);
    try sdk.put(engine, exports, "sendCustomMessage", method);
    inline for (.{ "_appendCustomMessage", "_flushPendingCustomMessages", "_refreshFinalizedContext" }, 0..) |name, index| {
        try sdk.put(engine, exports, name, try engine.checked(c.pi_js_function_magic(engine.context, synchronous, name, if (index == 0) 1 else 0, @intCast(index))));
    }
}
fn send(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, receiver: c.JSValue, message: c.JSValue, options: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    body(engine, pending.owner, receiver, message, options) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn option(scope: *Scope, options: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(options)) c.pi_js_undefined() else scope.get(options, key);
}
fn body(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, message: c.JSValue, options: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const app = try scope.object();
    try scope.put(app, "role", try scope.text("custom"));
    try scope.put(app, "customType", try scope.get(message, "customType"));
    const content = try scope.get(message, "content");
    try scope.put(app, "content", if (temp.nullish(content)) try scope.array() else content);
    try scope.put(app, "display", try scope.get(message, "display"));
    try scope.put(app, "details", try scope.get(message, "details"));
    try scope.put(app, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    if (scope.equal(try option(&scope, options, "deliverAs"), try scope.text("nextTurn"))) {
        _ = try scope.invoke(try scope.get(receiver, "_pendingNextTurnMessages"), "push", &.{app});
    } else if (scope.truthy(try scope.get(receiver, "isStreaming")) and !scope.equal(try option(&scope, options, "triggerTurn"), c.pi_js_bool(engine.context, 0))) {
        const follow_up = scope.equal(try option(&scope, options, "deliverAs"), try scope.text("followUp"));
        _ = try scope.invoke(try scope.get(receiver, "agent"), if (follow_up) "followUp" else "steer", &.{app});
    } else if (scope.truthy(try option(&scope, options, "triggerTurn"))) {
        if (scope.truthy(try scope.get(receiver, "_isEmittingAgentSettled"))) {
            const actions = try scope.get(receiver, "_deferredSettledActions");
            const push = try scope.get(actions, "push");
            var roots = [_]c.JSValue{ receiver, message, options };
            const action = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, deferred, "", 0, 0, roots.len, &roots)));
            const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, action, parent) < 0) return js.capture(engine);
            _ = try scope.call(push, actions, &.{action});
        } else {
            const callee = try scope.get(receiver, "_startRun");
            const trigger = try scope.object();
            try scope.put(trigger, "messageType", try scope.text("custom"));
            try scope.put(trigger, "message", app);
            const result = try scope.call(callee, receiver, &.{trigger});
            return flow.wait(finishVoid, engine, owner, result, 0);
        }
    } else if (scope.truthy(try scope.get(receiver, "isStreaming"))) {
        _ = try scope.invoke(try scope.get(receiver, "_pendingCustomMessages"), "push", &.{app});
    } else _ = try scope.invoke(receiver, "_appendCustomMessage", &.{app});
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn finishVoid(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}
fn finishValue(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, value);
}
fn deferred(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return deferredStart(engine, roots) catch |err| sdk.fail(engine, err);
}
fn deferredStart(engine: *em.Engine, roots: [*c]c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const value = js.invoke(engine, roots[0], "sendCustomMessage", &.{ roots[1], roots[2] }) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    defer engine.freeValue(value);
    flow.wait(finishValue, engine, pending.owner, value, 0) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn synchronous(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    syncBody(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn syncBody(engine: *em.Engine, receiver: c.JSValue, message: c.JSValue, operation: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (operation == 0) {
        const manager = try scope.get(receiver, "sessionManager");
        const append = try scope.get(manager, "appendCustomMessageEntry");
        _ = try scope.call(append, manager, &.{ try scope.get(message, "customType"), try scope.get(message, "content"), try scope.get(message, "display"), try scope.get(message, "details") });
        _ = try scope.invoke(receiver, "_refreshFinalizedContext", &.{});
        inline for (.{ "message_start", "message_end" }) |kind| {
            const emit = try scope.get(receiver, "_emit");
            const event = try scope.object();
            try scope.put(event, "type", try scope.text(kind));
            try scope.put(event, "message", message);
            _ = try scope.call(emit, receiver, &.{event});
        }
    } else if (operation == 1) {
        if (scope.equal(try scope.get(try scope.get(receiver, "_pendingCustomMessages"), "length"), c.JS_NewInt32(engine.context, 0))) return;
        const pending = try scope.get(receiver, "_pendingCustomMessages");
        try scope.set(receiver, "_pendingCustomMessages", try scope.array());
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var iterator = try js.Iterator.init(engine, pending, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer engine.freeValue(entry);
            _ = try scope.invoke(receiver, "_appendCustomMessage", &.{entry});
        }
    } else {
        const projection = try scope.invoke(try scope.get(receiver, "sessionManager"), "buildSessionProjection", &.{});
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var entries = try js.Iterator.init(engine, try scope.get(projection, "entries"), symbol);
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer engine.freeValue(entry);
            var messages = try js.Iterator.init(engine, try scope.get(entry, "messages"), symbol);
            defer messages.deinit();
            errdefer messages.closePreserving();
            while (try messages.next()) |value| {
                defer engine.freeValue(value);
                const map = try scope.get(receiver, "_entryIdsByMessage");
                const set = try scope.get(map, "set");
                _ = try scope.call(set, map, &.{ value, try scope.get(try scope.get(entry, "sourceEntry"), "id") });
            }
        }
        const state = try scope.get(try scope.get(receiver, "agent"), "state");
        try scope.set(state, "messages", try scope.get(projection, "messages"));
    }
}

//! Original low-level AgentLoop entry points and turn controller.
//! This private module uses real response and tool pipelines; no public module
//! registration is enabled here.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const changes = @import("native_agent_tool_changes.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const EntryStage = enum(c_int) { agent_started, turn_started, message_started, message_ended, loop_finished };
const TurnStage = enum(c_int) { steering, prepared, polled, turn_started, message_started, message_ended, request, response, tools, finish, turn_ended, following, ended };

pub fn loopFunction(engine: *em.Engine, continuing: bool) !c.JSValue {
    const result = try engine.checked(c.pi_js_function_magic(engine.context, loopCall, if (continuing) "runAgentLoopContinue" else "runAgentLoop", if (continuing) 5 else 6, @intFromBool(continuing)));
    errdefer engine.freeValue(result);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, result, parent) < 0) return js.capture(engine);
    return result;
}
fn loopCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, continuing: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 6;
    for (0..@min(args.len, @as(usize, @intCast(argc)))) |index| args[index] = argv[index];
    return if (continuing != 0) run(engine, c.pi_js_undefined(), args[0], args[1], args[2], args[3], args[4], true) catch |err| sdk.fail(engine, err) else run(engine, args[0], args[1], args[2], args[3], args[4], args[5], false) catch |err| sdk.fail(engine, err);
}

pub fn run(engine: *em.Engine, prompts: c.JSValue, context: c.JSValue, config: c.JSValue, emit: c.JSValue, signal: c.JSValue, stream: c.JSValue, continuing: bool) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, prompts, context, config, emit, signal, stream, continuing) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn begin(engine: *em.Engine, owner: c.JSValue, prompts: c.JSValue, context: c.JSValue, config: c.JSValue, emit: c.JSValue, signal: c.JSValue, stream: c.JSValue, continuing: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const current = try scope.object();
    var messages: c.JSValue = undefined;
    var initial: c.JSValue = undefined;
    if (continuing) {
        if (scope.equal(try scope.get(try scope.get(context, "messages"), "length"), c.JS_NewInt32(engine.context, 0))) _ = try @import("native_agent_methods.zig").raise(&scope, "Cannot continue: no messages in context");
        const list = try scope.get(context, "messages");
        const index = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try scope.get(try scope.get(context, "messages"), "length"), c.JS_NewInt32(engine.context, 1))));
        const last = try scope.own(try js.getKey(engine, list, index));
        if (scope.equal(try scope.get(last, "role"), try scope.text("assistant"))) _ = try @import("native_agent_methods.zig").raise(&scope, "Cannot continue from message role: assistant");
        messages = try scope.array();
        initial = try scope.array();
        try js.spreadInto(engine, current, context);
    } else {
        initial = try scope.own(try changes.declare(engine, context, prompts));
        messages = try changes.arraySpread(&scope, &.{initial});
        try js.spreadInto(engine, current, context);
        try scope.put(current, "messages", try changes.arraySpread(&scope, &.{ try scope.get(context, "messages"), initial }));
    }
    inline for (.{ .{ "context", current }, .{ "config", config }, .{ "emit", emit }, .{ "signal", signal }, .{ "stream", stream }, .{ "messages", messages }, .{ "initial", initial } }) |field| try scope.put(owner, field[0], field[1]);
    try scope.put(owner, "continuing", c.pi_js_bool(engine.context, @intFromBool(continuing)));
    const event = try eventOf(&scope, "agent_start");
    try entryEmit(engine, owner, event, .agent_started);
}
fn eventOf(scope: *Scope, kind: []const u8) !c.JSValue {
    const event = try scope.object();
    try scope.put(event, "type", try scope.text(kind));
    return event;
}
fn messageEvent(scope: *Scope, kind: []const u8, message: c.JSValue) !c.JSValue {
    const event = try eventOf(scope, kind);
    try scope.put(event, "message", message);
    return event;
}
fn entryEmit(engine: *em.Engine, owner: c.JSValue, event: c.JSValue, stage: EntryStage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try scope.call(try scope.get(owner, "emit"), c.pi_js_undefined(), &.{event});
    try flow.wait(entryResume, engine, owner, pending, @intFromEnum(stage));
}
fn entryResume(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage_int: c_int) !void {
    const stage: EntryStage = @enumFromInt(stage_int);
    if (rejected) return closeReject(engine, owner, value);
    entryCore(engine, owner, stage) catch |err| {
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        return closeReject(engine, owner, raw);
    };
}
fn entryCore(engine: *em.Engine, owner: c.JSValue, stage: EntryStage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .agent_started => try entryEmit(engine, owner, try eventOf(&scope, "turn_start"), .turn_started),
        .turn_started => {
            if (scope.truthy(try scope.get(owner, "continuing"))) return startTurns(engine, owner);
            const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
            var iterator = try js.Iterator.init(engine, try scope.get(owner, "initial"), symbol);
            defer iterator.deinit();
            try retainIterator(&scope, owner, &iterator);
            try entryNext(engine, owner);
        },
        .message_started => try entryEmit(engine, owner, try messageEvent(&scope, "message_end", try scope.get(owner, "message")), .message_ended),
        .message_ended => try entryNext(engine, owner),
        .loop_finished => try flow.settle(engine, owner, false, try scope.get(owner, "messages")),
    }
}
fn retainIterator(scope: *Scope, owner: c.JSValue, iterator: *js.Iterator) !void {
    try scope.put(owner, "iterator", iterator.iterator);
    try scope.put(owner, "next", iterator.next_function);
    try scope.put(owner, "steps", c.JS_NewInt32(scope.engine.context, 0));
}
fn iteratorOf(engine: *em.Engine, owner: c.JSValue) !js.Iterator {
    const iterator = try sdk.get(engine, owner, "iterator");
    errdefer engine.freeValue(iterator);
    const next = try sdk.get(engine, owner, "next");
    errdefer engine.freeValue(next);
    const raw = try sdk.get(engine, owner, "steps");
    defer engine.freeValue(raw);
    var steps: i64 = 0;
    if (c.JS_ToInt64(engine.context, &steps, raw) < 0) return js.capture(engine);
    return .{ .engine = engine, .iterator = iterator, .next_function = next, .native_steps = @intCast(steps) };
}
fn entryNext(engine: *em.Engine, owner: c.JSValue) !void {
    try sdk.put(engine, owner, "body", c.pi_js_bool(engine.context, 0));
    var iterator = try iteratorOf(engine, owner);
    defer iterator.deinit();
    const message = (try iterator.next()) orelse return startTurns(engine, owner);
    defer engine.freeValue(message);
    try sdk.put(engine, owner, "body", c.pi_js_bool(engine.context, 1));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "steps", c.JS_NewFloat64(engine.context, @floatFromInt(iterator.native_steps)));
    try scope.put(owner, "message", message);
    try entryEmit(engine, owner, try messageEvent(&scope, "message_start", message), .message_started);
}
fn startTurns(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const supplied = try scope.get(owner, "stream");
    const stream = if (temp.nullish(supplied)) try scope.own(try @import("native_agent_default_stream.zig").get(engine)) else supplied;
    const pending = try scope.own(try turns(engine, try scope.get(owner, "context"), try scope.get(owner, "messages"), try scope.get(owner, "config"), try scope.get(owner, "signal"), try scope.get(owner, "emit"), stream));
    try flow.wait(entryResume, engine, owner, pending, @intFromEnum(EntryStage.loop_finished));
}
fn turns(engine: *em.Engine, context: c.JSValue, messages: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue, stream: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    beginTurns(engine, pending.owner, context, messages, config, signal, emit, stream) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn optionalCall(scope: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const method = try scope.get(receiver, name);
    return if (temp.nullish(method)) c.pi_js_undefined() else scope.call(method, receiver, args);
}
fn beginTurns(engine: *em.Engine, owner: c.JSValue, context: c.JSValue, messages: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue, stream: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "context", context }, .{ "messages", messages }, .{ "config", config }, .{ "signal", signal }, .{ "emit", emit }, .{ "stream", stream } }) |field| try scope.put(owner, field[0], field[1]);
    try scope.put(owner, "last", c.pi_js_undefined());
    try scope.put(owner, "explicit", c.pi_js_bool(engine.context, 0));
    try flow.wait(turnResume, engine, owner, try optionalCall(&scope, config, "getSteeringMessages", &.{}), @intFromEnum(TurnStage.steering));
}
fn turnEmit(engine: *em.Engine, owner: c.JSValue, event: c.JSValue, stage: TurnStage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try turnWait(engine, owner, try scope.call(try scope.get(owner, "emit"), c.pi_js_undefined(), &.{event}), stage);
}
fn turnWait(engine: *em.Engine, owner: c.JSValue, pending: c.JSValue, stage: TurnStage) !void {
    return flow.wait(turnResume, engine, owner, pending, @intFromEnum(stage));
}
fn startTurn(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "prepared", try scope.array());
    const last = try scope.get(owner, "last");
    if (scope.truthy(last)) return turnWait(engine, owner, try optionalCall(&scope, try scope.get(owner, "config"), "prepareNextTurn", &.{last}), .prepared);
    try pendingTurn(engine, owner);
}
fn applyUpdate(scope: *Scope, owner: c.JSValue, update: c.JSValue) !void {
    const context = try scope.get(update, "context");
    if (!temp.nullish(context)) try scope.put(owner, "context", context);
    const config = try scope.get(owner, "config");
    const next = try scope.own(try js.spread(scope.engine, config));
    const model = try scope.get(update, "model");
    try scope.put(next, "model", if (temp.nullish(model)) try scope.get(config, "model") else model);
    const thinking = try scope.get(update, "thinkingLevel");
    const reasoning = if (c.JS_IsUndefined(thinking)) try scope.get(config, "reasoning") else if (scope.equal(try scope.get(update, "thinkingLevel"), try scope.text("off"))) c.pi_js_undefined() else try scope.get(update, "thinkingLevel");
    try scope.put(next, "reasoning", reasoning);
    try scope.put(owner, "config", next);
}
fn preparedTurn(engine: *em.Engine, owner: c.JSValue, update: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(update)) {
        const context = try scope.get(update, "context");
        if (!temp.nullish(context)) try scope.put(owner, "context", context);
        const messages = try scope.get(update, "messages");
        try scope.put(owner, "prepared", if (temp.nullish(messages)) try scope.array() else messages);
        // applyUpdate reads context in the Source prepare-request path; here
        // that read was already performed before the messages getter.
        const config = try scope.get(owner, "config");
        const next = try scope.own(try js.spread(engine, config));
        const model = try scope.get(update, "model");
        try scope.put(next, "model", if (temp.nullish(model)) try scope.get(config, "model") else model);
        const thinking = try scope.get(update, "thinkingLevel");
        const reasoning = if (c.JS_IsUndefined(thinking)) try scope.get(config, "reasoning") else if (scope.equal(try scope.get(update, "thinkingLevel"), try scope.text("off"))) c.pi_js_undefined() else try scope.get(update, "thinkingLevel");
        try scope.put(next, "reasoning", reasoning);
        try scope.put(owner, "config", next);
    }
    if (scope.equal(try scope.get(try scope.get(owner, "pending"), "length"), c.JS_NewInt32(engine.context, 0))) return turnWait(engine, owner, try optionalCall(&scope, try scope.get(owner, "config"), "getSteeringMessages", &.{}), .polled);
    try turnEmit(engine, owner, try eventOf(&scope, "turn_start"), .turn_started);
}
fn pendingTurn(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const combined = try changes.arraySpread(&scope, &.{ try scope.get(owner, "prepared"), try scope.get(owner, "pending") });
    const declared = try scope.own(try changes.declare(engine, try scope.get(owner, "context"), combined));
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, declared, symbol);
    defer iterator.deinit();
    try retainIterator(&scope, owner, &iterator);
    try pendingNext(engine, owner);
}
fn pendingNext(engine: *em.Engine, owner: c.JSValue) !void {
    try sdk.put(engine, owner, "body", c.pi_js_bool(engine.context, 0));
    var iterator = try iteratorOf(engine, owner);
    defer iterator.deinit();
    const message = (try iterator.next()) orelse return prepareRequest(engine, owner);
    defer engine.freeValue(message);
    try sdk.put(engine, owner, "body", c.pi_js_bool(engine.context, 1));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "steps", c.JS_NewFloat64(engine.context, @floatFromInt(iterator.native_steps)));
    try scope.put(owner, "message", message);
    try turnEmit(engine, owner, try messageEvent(&scope, "message_start", message), .message_started);
}
fn prepareRequest(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "pending", try scope.array());
    const config = try scope.get(owner, "config");
    const method = try scope.get(config, "prepareRequest");
    var pending = c.pi_js_undefined();
    if (!temp.nullish(method)) {
        const request = try scope.object();
        try scope.put(request, "context", try scope.get(owner, "context"));
        try scope.put(request, "model", try scope.get(config, "model"));
        const reasoning = try scope.get(config, "reasoning");
        try scope.put(request, "thinkingLevel", if (temp.nullish(reasoning)) try scope.text("off") else reasoning);
        pending = try scope.call(method, config, &.{ request, try scope.get(owner, "signal") });
    }
    try turnWait(engine, owner, pending, .request);
}
fn startResponse(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try @import("native_agent_response.zig").run(engine, try scope.get(owner, "context"), try scope.get(owner, "config"), try scope.get(owner, "signal"), try scope.get(owner, "emit"), try scope.get(owner, "stream")));
    try turnWait(engine, owner, result, .response);
}
fn toolCallFilter(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return isToolCall(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn isToolCall(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(value, "type"), try scope.text("toolCall"))));
}
fn assistantReady(engine: *em.Engine, owner: c.JSValue, message: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "assistant", message);
    _ = try scope.invoke(try scope.get(owner, "messages"), "push", &.{message});
    const failed = scope.equal(try scope.get(message, "stopReason"), try scope.text("error")) or scope.equal(try scope.get(message, "stopReason"), try scope.text("aborted"));
    try scope.put(owner, "failed", c.pi_js_bool(engine.context, @intFromBool(failed)));
    try scope.put(owner, "toolResults", try scope.array());
    if (failed) return finishTurn(engine, owner);
    const content = try scope.get(message, "content");
    const filter = try scope.get(content, "filter");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, toolCallFilter, "", 1)));
    const calls = try scope.call(filter, content, &.{predicate});
    try scope.put(owner, "moreTools", c.pi_js_bool(engine.context, 0));
    if (try scope.positive(try scope.get(calls, "length"))) {
        const truncated = scope.equal(try scope.get(message, "stopReason"), try scope.text("length"));
        const batch = if (truncated) try scope.own(try @import("native_agent_tools.zig").truncated(engine, calls, try scope.get(owner, "emit"))) else try scope.own(try @import("native_agent_tools.zig").execute(engine, try scope.get(owner, "context"), message, try scope.get(owner, "config"), try scope.get(owner, "signal"), try scope.get(owner, "emit")));
        return turnWait(engine, owner, batch, .tools);
    }
    try finishTurn(engine, owner);
}
fn finishTurn(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const snapshot = try scope.object();
    try scope.put(snapshot, "message", try scope.get(owner, "assistant"));
    try scope.put(snapshot, "toolResults", try scope.get(owner, "toolResults"));
    try scope.put(snapshot, "context", try scope.get(owner, "context"));
    try scope.put(snapshot, "newMessages", try scope.get(owner, "messages"));
    try scope.put(owner, "last", snapshot);
    try turnWait(engine, owner, try optionalCall(&scope, try scope.get(owner, "config"), "finishTurn", &.{ snapshot, try scope.get(owner, "signal") }), .finish);
}
fn end(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = try eventOf(&scope, "agent_end");
    try scope.put(event, "messages", try scope.get(owner, "messages"));
    try turnEmit(engine, owner, event, .ended);
}
fn afterTurn(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(owner, "failed"))) return end(engine, owner);
    const decision = try scope.get(owner, "decision");
    if (!temp.nullish(decision) and scope.equal(try scope.get(decision, "action"), try scope.text("end"))) return end(engine, owner);
    try scope.put(owner, "explicit", c.pi_js_bool(engine.context, @intFromBool(!temp.nullish(decision) and scope.equal(try scope.get(decision, "action"), try scope.text("continue")))));
    try turnWait(engine, owner, try optionalCall(&scope, try scope.get(owner, "config"), "getSteeringMessages", &.{}), .steering);
}
fn chooseNext(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = if (scope.truthy(value)) value else try scope.array();
    try scope.put(owner, "pending", pending);
    if (scope.truthy(try scope.get(owner, "moreTools")) or try scope.positive(try scope.get(pending, "length"))) {
        try scope.put(owner, "explicit", c.pi_js_bool(engine.context, 0));
        return startTurn(engine, owner);
    }
    try turnWait(engine, owner, try optionalCall(&scope, try scope.get(owner, "config"), "getFollowUpMessages", &.{}), .following);
}
fn turnResume(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage_int: c_int) !void {
    const stage: TurnStage = @enumFromInt(stage_int);
    if (rejected) return closeReject(engine, owner, value);
    turnCore(engine, owner, value, stage) catch |err| {
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        return closeReject(engine, owner, raw);
    };
}
fn turnCore(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: TurnStage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .steering => {
            if (c.JS_IsUndefined(try scope.get(owner, "last"))) {
                try scope.put(owner, "pending", if (scope.truthy(value)) value else try scope.array());
                try startTurn(engine, owner);
            } else try chooseNext(engine, owner, value);
        },
        .prepared => try preparedTurn(engine, owner, value),
        .polled => {
            try scope.put(owner, "pending", if (scope.truthy(value)) value else try scope.array());
            try turnEmit(engine, owner, try eventOf(&scope, "turn_start"), .turn_started);
        },
        .turn_started => try pendingTurn(engine, owner),
        .message_started => try turnEmit(engine, owner, try messageEvent(&scope, "message_end", try scope.get(owner, "message")), .message_ended),
        .message_ended => {
            const message = try scope.get(owner, "message");
            _ = try scope.invoke(try scope.get(try scope.get(owner, "context"), "messages"), "push", &.{message});
            _ = try scope.invoke(try scope.get(owner, "messages"), "push", &.{message});
            try pendingNext(engine, owner);
        },
        .request => {
            if (scope.truthy(value)) try applyUpdate(&scope, owner, value);
            try startResponse(engine, owner);
        },
        .response => try assistantReady(engine, owner, value),
        .tools => {
            const results = try scope.get(owner, "toolResults");
            const push = try scope.get(results, "push");
            const batch_messages = try scope.get(value, "messages");
            try callSpread(&scope, push, results, batch_messages);
            try scope.put(owner, "moreTools", c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(try scope.get(value, "terminate")))));
            const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
            var iterator = try js.Iterator.init(engine, results, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |result_value| {
                defer engine.freeValue(result_value);
                _ = try scope.invoke(try scope.get(try scope.get(owner, "context"), "messages"), "push", &.{result_value});
                _ = try scope.invoke(try scope.get(owner, "messages"), "push", &.{result_value});
            }
            try finishTurn(engine, owner);
        },
        .finish => {
            try scope.put(owner, "decision", value);
            const event = try messageEvent(&scope, "turn_end", try scope.get(owner, "assistant"));
            try scope.put(event, "toolResults", if (scope.truthy(try scope.get(owner, "failed"))) try scope.array() else try scope.get(owner, "toolResults"));
            try turnEmit(engine, owner, event, .turn_ended);
        },
        .turn_ended => try afterTurn(engine, owner),
        .following => {
            const following = if (scope.truthy(value)) value else try scope.array();
            if (try scope.positive(try scope.get(following, "length"))) {
                try scope.put(owner, "explicit", c.pi_js_bool(engine.context, 0));
                try scope.put(owner, "pending", following);
                try startTurn(engine, owner);
            } else if (scope.truthy(try scope.get(owner, "explicit"))) {
                try scope.put(owner, "explicit", c.pi_js_bool(engine.context, 0));
                try startTurn(engine, owner);
            } else try end(engine, owner);
        },
        .ended => try flow.settle(engine, owner, false, c.pi_js_undefined()),
    }
}
fn closeReject(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    const body = try sdk.get(engine, owner, "body");
    defer engine.freeValue(body);
    if (c.JS_ToBool(engine.context, body) == 0) return flow.settle(engine, owner, true, value);
    var iterator = try iteratorOf(engine, owner);
    defer iterator.deinit();
    const prior = engine.captured_exception;
    engine.captured_exception = c.JS_DupValue(engine.context, value);
    iterator.closePreserving();
    if (engine.captured_exception) |captured| engine.freeValue(captured);
    engine.captured_exception = prior;
    try flow.settle(engine, owner, true, value);
}
fn callSpread(scope: *Scope, function: c.JSValue, receiver: c.JSValue, iterable: c.JSValue) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var args: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (args.items) |item| scope.engine.freeValue(item);
        args.deinit(scope.engine.gpa);
    }
    while (try iterator.next()) |item| {
        args.append(scope.engine.gpa, item) catch |err| {
            scope.engine.freeValue(item);
            return err;
        };
    }
    _ = try scope.call(function, receiver, args.items);
}

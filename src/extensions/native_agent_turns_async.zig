//! Actual shared runLoop structured control flow, with one real Await per Source.
const std = @import("std");
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const js = @import("native_js_values.zig");
const iter = @import("native_agent_af_iterator.zig");
const changes = @import("native_agent_tool_changes.zig");
const functions = @import("native_node_function.zig");
const nullish = @import("native_sdk_prompt_scope.zig").nullish;
const Stage = enum(i32) { initial_poll, prepared, prepared_poll, turn_start, message_start, message_end, request, response, batch, finish, turn_end, steering, following, ended };
pub fn create(engine: *em.Engine, response: c.JSValue, tools: c.JSValue) !c.JSValue { return af.createResumable(engine, "runLoop", 6, invoke, &.{ response, tools }); }
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    return run(engine, args, roots, state, completion, input) catch |err| {
        const reason = try p.caught(engine, err); defer engine.freeValue(reason);
        if (!c.JS_IsObject(state.*)) return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        var s: p.Scope = .{ .engine = engine }; defer s.deinit();
        return iter.throwCompletion(&s, state.*, reason);
    };
}
fn at(args: []const c.JSValue, index: usize) c.JSValue { return if (args.len > index) args[index] else c.pi_js_undefined(); }
fn run(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return iter.throwCompletion(&s, state.*, input); }
    if (completion == .fulfilled) return resumed(&s, state.*, roots, @enumFromInt(try p.stage(&s, state.*)), input);
    const owner = try p.init(&s, state);
    inline for (.{ "context", "messages", "config", "signal", "emit", "stream" }, 0..) |name, index| try s.put(owner, name, at(args, index));
    try s.put(owner, "last", c.pi_js_undefined()); try s.put(owner, "explicit", c.pi_js_bool(engine.context, 0));
    return optional(&s, owner, "getSteeringMessages", &.{}, .initial_poll);
}
fn resumed(s: *p.Scope, owner: c.JSValue, roots: []const c.JSValue, stage: Stage, value: c.JSValue) !af.Action {
    switch (stage) {
        .initial_poll => { try setPending(s, owner, value); return startTurn(s, owner); },
        .prepared => {
            if (s.truthy(value)) {
                const context = try p.get(s, value, "context"); if (!nullish(context)) try s.put(owner, "context", context);
                const messages = try p.get(s, value, "messages"); try s.put(owner, "prepared", if (nullish(messages)) try s.array() else messages);
                try updateConfig(s, owner, value);
            }
            if (s.equal(try p.get(s, try s.get(owner, "pending"), "length"), c.JS_NewInt32(s.engine.context, 0))) return optional(s, owner, "getSteeringMessages", &.{}, .prepared_poll);
            return emit(s, owner, try event(s, "turn_start"), .turn_start);
        },
        .prepared_poll => { try setPending(s, owner, value); return emit(s, owner, try event(s, "turn_start"), .turn_start); },
        .turn_start => return pendingMessages(s, owner),
        .message_start => return emit(s, owner, try messageEvent(s, "message_end", try s.get(owner, "iteratorValue")), .message_end),
        .message_end => {
            const message = try s.get(owner, "iteratorValue");
            _ = try p.invoke(s, try p.get(s, try s.get(owner, "context"), "messages"), "push", &.{message});
            _ = try p.invoke(s, try s.get(owner, "messages"), "push", &.{message});
            return nextMessage(s, owner);
        },
        .request => {
            if (s.truthy(value)) {
                const context = try p.get(s, value, "context"); if (!nullish(context)) try s.put(owner, "context", context);
                try updateConfig(s, owner, value);
            }
            return p.wait(s, owner, roots[0], c.pi_js_undefined(), &.{ try s.get(owner, "context"), try s.get(owner, "config"), try s.get(owner, "signal"), try s.get(owner, "emit"), try s.get(owner, "stream") }, @intFromEnum(Stage.response));
        },
        .response => return assistantReady(s, owner, roots[1], value),
        .batch => {
            const results = try s.get(owner, "results"); const push = try p.get(s, results, "push");
            try callSpread(s, push, results, try p.get(s, value, "messages"));
            try s.put(owner, "moreTools", c.pi_js_bool(s.engine.context, @intFromBool(!s.truthy(try p.get(s, value, "terminate")))));
            try iter.init(s, owner, results);
            while (try iter.next(s, owner)) |result| {
                _ = try p.invoke(s, try p.get(s, try s.get(owner, "context"), "messages"), "push", &.{result});
                _ = try p.invoke(s, try s.get(owner, "messages"), "push", &.{result});
            }
            return finishTurn(s, owner);
        },
        .finish => {
            try s.put(owner, "decision", value);
            const outgoing = try messageEvent(s, "turn_end", try s.get(owner, "assistant"));
            try s.put(outgoing, "toolResults", if (s.truthy(try s.get(owner, "failed"))) try s.array() else try s.get(owner, "results"));
            return emit(s, owner, outgoing, .turn_end);
        },
        .turn_end => {
            if (s.truthy(try s.get(owner, "failed"))) return end(s, owner);
            const decision = try s.get(owner, "decision");
            if (!nullish(decision) and s.equal(try p.get(s, decision, "action"), try s.text("end"))) return end(s, owner);
            try s.put(owner, "explicit", c.pi_js_bool(s.engine.context, @intFromBool(!nullish(decision) and s.equal(try p.get(s, decision, "action"), try s.text("continue")))));
            return optional(s, owner, "getSteeringMessages", &.{}, .steering);
        },
        .steering => {
            try setPending(s, owner, value);
            if (s.truthy(try s.get(owner, "moreTools")) or try s.positive(try p.get(s, try s.get(owner, "pending"), "length"))) {
                try s.put(owner, "explicit", c.pi_js_bool(s.engine.context, 0)); return startTurn(s, owner);
            }
            return optional(s, owner, "getFollowUpMessages", &.{}, .following);
        },
        .following => {
            const following = if (s.truthy(value)) value else try s.array();
            if (try s.positive(try p.get(s, following, "length"))) {
                try s.put(owner, "explicit", c.pi_js_bool(s.engine.context, 0)); try s.put(owner, "pending", following); return startTurn(s, owner);
            }
            if (s.truthy(try s.get(owner, "explicit"))) { try s.put(owner, "explicit", c.pi_js_bool(s.engine.context, 0)); return startTurn(s, owner); }
            return end(s, owner);
        },
        .ended => return .{ .returned = c.pi_js_undefined() },
    }
}
fn awaitValue(s: *p.Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !af.Action {
    try s.put(owner, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(stage)));
    try s.put(owner, "awaitGeneration", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, s.engine.native_allocation_generation))));
    return .{ .awaited = c.JS_DupValue(s.engine.context, value) };
}
fn optional(s: *p.Scope, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue, stage: Stage) !af.Action {
    const config = try s.get(owner, "config"); const function = try p.get(s, config, name);
    if (nullish(function)) return awaitValue(s, owner, c.pi_js_undefined(), stage);
    return p.wait(s, owner, function, config, args, @intFromEnum(stage));
}
fn setPending(s: *p.Scope, owner: c.JSValue, value: c.JSValue) !void { try s.put(owner, "pending", if (s.truthy(value)) value else try s.array()); }
fn startTurn(s: *p.Scope, owner: c.JSValue) !af.Action {
    try s.put(owner, "prepared", try s.array());
    const last = try s.get(owner, "last");
    if (s.truthy(last)) return optional(s, owner, "prepareNextTurn", &.{last}, .prepared);
    return pendingMessages(s, owner);
}
fn updateConfig(s: *p.Scope, owner: c.JSValue, update: c.JSValue) !void {
    const config = try s.get(owner, "config"); const generation = s.engine.native_allocation_generation;
    const replacement = try s.own(try p.guard(s.engine, generation, js.spread(s.engine, config)));
    const model = try p.get(s, update, "model"); try s.put(replacement, "model", if (nullish(model)) try p.get(s, config, "model") else model);
    const thinking = try p.get(s, update, "thinkingLevel");
    const reasoning = if (c.JS_IsUndefined(thinking)) try p.get(s, config, "reasoning") else if (s.equal(try p.get(s, update, "thinkingLevel"), try s.text("off"))) c.pi_js_undefined() else try p.get(s, update, "thinkingLevel");
    try s.put(replacement, "reasoning", reasoning); try s.put(owner, "config", replacement);
}
fn pendingMessages(s: *p.Scope, owner: c.JSValue) !af.Action {
    const generation = s.engine.native_allocation_generation;
    const combined = try changes.arraySpread(s, &.{ try s.get(owner, "prepared"), try s.get(owner, "pending") });
    const declared = try s.own(try p.guard(s.engine, generation, changes.declare(s.engine, try s.get(owner, "context"), combined)));
    try iter.init(s, owner, declared); return nextMessage(s, owner);
}
fn nextMessage(s: *p.Scope, owner: c.JSValue) !af.Action {
    if (try iter.next(s, owner)) |message| return emit(s, owner, try messageEvent(s, "message_start", message), .message_start);
    try s.put(owner, "pending", try s.array());
    const config = try s.get(owner, "config"); const method = try p.get(s, config, "prepareRequest");
    if (nullish(method)) return awaitValue(s, owner, c.pi_js_undefined(), .request);
    const request = try s.object(); try s.put(request, "context", try s.get(owner, "context")); try s.put(request, "model", try p.get(s, config, "model"));
    const reasoning = try p.get(s, config, "reasoning"); try s.put(request, "thinkingLevel", if (nullish(reasoning)) try s.text("off") else reasoning);
    return p.wait(s, owner, method, config, &.{ request, try s.get(owner, "signal") }, @intFromEnum(Stage.request));
}
fn toolFilter(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return filterBody(engine, at(args, 0)) catch |err| return p.callbackFailure(engine, err);
}
fn filterBody(engine: *em.Engine, value: c.JSValue) !c.JSValue { var s: p.Scope = .{ .engine = engine }; defer s.deinit(); return c.pi_js_bool(engine.context, @intFromBool(s.equal(try p.get(&s, value, "type"), try s.text("toolCall")))); }
fn assistantReady(s: *p.Scope, owner: c.JSValue, tools: c.JSValue, message: c.JSValue) !af.Action {
    try s.put(owner, "assistant", message); _ = try p.invoke(s, try s.get(owner, "messages"), "push", &.{message});
    const failed = s.equal(try p.get(s, message, "stopReason"), try s.text("error")) or s.equal(try p.get(s, message, "stopReason"), try s.text("aborted"));
    try s.put(owner, "failed", c.pi_js_bool(s.engine.context, @intFromBool(failed)));
    if (failed) { try s.put(owner, "results", try s.array()); return finishTurn(s, owner); }
    const content = try p.get(s, message, "content"); const filter = try p.get(s, content, "filter");
    const predicate = try s.own(try functions.createArrow(s.engine, "", 1, toolFilter, &.{}));
    const calls = try p.call(s, filter, content, &.{predicate});
    try s.put(owner, "results", try s.array()); try s.put(owner, "moreTools", c.pi_js_bool(s.engine.context, 0));
    if (try s.positive(try p.get(s, calls, "length"))) {
        if (s.equal(try p.get(s, message, "stopReason"), try s.text("length"))) return p.wait(s, owner, try s.get(tools, "failToolCallsFromTruncatedMessage"), c.pi_js_undefined(), &.{ calls, try s.get(owner, "emit") }, @intFromEnum(Stage.batch));
        return p.wait(s, owner, try s.get(tools, "executeToolCalls"), c.pi_js_undefined(), &.{ try s.get(owner, "context"), message, try s.get(owner, "config"), try s.get(owner, "signal"), try s.get(owner, "emit") }, @intFromEnum(Stage.batch));
    }
    return finishTurn(s, owner);
}
fn finishTurn(s: *p.Scope, owner: c.JSValue) !af.Action {
    const snapshot = try s.object(); try s.put(snapshot, "message", try s.get(owner, "assistant")); try s.put(snapshot, "toolResults", try s.get(owner, "results"));
    try s.put(snapshot, "context", try s.get(owner, "context")); try s.put(snapshot, "newMessages", try s.get(owner, "messages")); try s.put(owner, "last", snapshot);
    return optional(s, owner, "finishTurn", &.{ snapshot, try s.get(owner, "signal") }, .finish);
}
fn callSpread(s: *p.Scope, function: c.JSValue, receiver: c.JSValue, iterable: c.JSValue) !void {
    const record = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    var arguments: std.ArrayList(c.JSValue) = .empty; defer arguments.deinit(s.engine.gpa);
    try iter.init(s, record, iterable);
    while (try iter.next(s, record)) |value| try arguments.append(s.engine.gpa, value);
    _ = try p.call(s, function, receiver, arguments.items);
}
fn event(s: *p.Scope, kind: []const u8) !c.JSValue { const result = try s.object(); try s.put(result, "type", try s.text(kind)); return result; }
fn messageEvent(s: *p.Scope, kind: []const u8, message: c.JSValue) !c.JSValue { const result = try event(s, kind); try s.put(result, "message", message); return result; }
fn emit(s: *p.Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !af.Action { return p.wait(s, owner, try s.get(owner, "emit"), c.pi_js_undefined(), &.{value}, @intFromEnum(stage)); }
fn end(s: *p.Scope, owner: c.JSValue) !af.Action { const outgoing = try event(s, "agent_end"); try s.put(outgoing, "messages", try s.get(owner, "messages")); return emit(s, owner, outgoing, .ended); }

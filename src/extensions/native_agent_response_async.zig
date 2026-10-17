//! Actual Source streamAssistantResponse and its lexical result AF arrow.
//! Iterator acquisition delegates to the VM, including AsyncFromSyncIterator.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const js = @import("native_js_values.zig");
const nullish = @import("native_sdk_prompt_scope.zig").nullish;
const Stage = enum(i32) { transformed, converted, api_key, response, next, emitted, result, final_start, final_end, closed };
pub fn create(engine: *em.Engine) !c.JSValue { return af.createResumable(engine, "streamAssistantResponse", 5, invoke, &.{}); }
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    return run(engine, args, state, completion, input) catch |err| {
        const reason = try p.caught(engine, err); defer engine.freeValue(reason);
        if (!c.JS_IsObject(state.*)) return .{ .thrown = c.JS_DupValue(engine.context, reason) };
        var s: p.Scope = .{ .engine = engine }; defer s.deinit();
        return fail(&s, state.*, reason);
    };
}
fn at(args: []const c.JSValue, index: usize) c.JSValue { return if (args.len > index) args[index] else c.pi_js_undefined(); }
fn run(engine: *em.Engine, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion != .start) {
        const stage: Stage = @enumFromInt(try p.stage(&s, state.*));
        if (completion == .rejected) {
            try p.rejected(&s, state.*, input);
            if (stage == .closed) return closeCompletion(&s, state.*, true, input);
            return fail(&s, state.*, input);
        }
        return switch (stage) {
            .transformed => convert(&s, state.*, input),
            .converted => converted(&s, state.*, input),
            .api_key => callStream(&s, state.*, input),
            .response => response(&s, state.*, input),
            .next => iteration(&s, state.*, input),
            .emitted => next(&s, state.*),
            .result => finalResult(&s, state.*, input),
            .final_start => emitFinal(&s, state.*),
            .final_end => if (s.truthy(try s.get(state.*, "body"))) close(&s, state.*, false, try s.get(state.*, "final")) else .{ .returned = c.JS_DupValue(engine.context, try s.get(state.*, "final")) },
            .closed => closeCompletion(&s, state.*, false, input),
        };
    }
    const owner = try p.init(&s, state);
    inline for (.{ "context", "config", "signal", "emit", "stream" }, 0..) |name, index| try s.put(owner, name, at(args, index));
    try s.put(owner, "body", c.pi_js_bool(engine.context, 0));
    const config = at(args, 1);
    const messages = try p.get(&s, at(args, 0), "messages");
    if (s.truthy(try p.get(&s, config, "transformContext"))) return p.wait(&s, owner, try p.get(&s, config, "transformContext"), config, &.{ messages, at(args, 2) }, @intFromEnum(Stage.transformed));
    return convert(&s, owner, messages);
}
fn convert(s: *p.Scope, owner: c.JSValue, messages: c.JSValue) !af.Action {
    const config = try s.get(owner, "config");
    return p.wait(s, owner, try p.get(s, config, "convertToLlm"), config, &.{messages}, @intFromEnum(Stage.converted));
}
fn converted(s: *p.Scope, owner: c.JSValue, messages: c.JSValue) !af.Action {
    const wrapper = try s.object(); try s.put(wrapper, "messages", messages);
    const generation = s.engine.native_allocation_generation;
    const normalized = try s.own(try p.guard(s.engine, generation, @import("native_ai_transcript_context.zig").normalize(s.engine, wrapper)));
    try s.put(owner, "llmContext", normalized);
    const config = try s.get(owner, "config");
    if (s.truthy(try p.get(s, config, "getApiKey"))) {
        const function = try p.get(s, config, "getApiKey");
        const provider = try p.get(s, try p.get(s, config, "model"), "provider");
        return p.wait(s, owner, function, config, &.{provider}, @intFromEnum(Stage.api_key));
    }
    return callStream(s, owner, c.pi_js_undefined());
}
fn callStream(s: *p.Scope, owner: c.JSValue, resolved: c.JSValue) !af.Action {
    const config = try s.get(owner, "config");
    const key = if (s.truthy(resolved)) resolved else try p.get(s, config, "apiKey");
    const function = try s.get(owner, "stream");
    const model = try p.get(s, config, "model");
    const context = try s.get(owner, "llmContext");
    const generation = s.engine.native_allocation_generation;
    const options = try s.own(try p.guard(s.engine, generation, js.spread(s.engine, config)));
    try s.put(options, "apiKey", key); try s.put(options, "signal", try s.get(owner, "signal"));
    return p.wait(s, owner, function, c.pi_js_undefined(), &.{ model, context, options }, @intFromEnum(Stage.response));
}
fn response(s: *p.Scope, owner: c.JSValue, stream: c.JSValue) !af.Action {
    try s.put(owner, "response", stream);
    const result = try s.own(try af.createResumableArrow(s.engine, "result", 0, resultArrow, &.{ stream, try s.get(owner, "config") }, c.pi_js_undefined()));
    try s.put(owner, "result", result);
    try s.put(owner, "partial", c.pi_js_null()); try s.put(owner, "added", c.pi_js_bool(s.engine.context, 0));
    const generation = s.engine.native_allocation_generation;
    const iterator = try s.own(try p.guard(s.engine, generation, @import("native_async_iterator_api.zig").acquire(s.engine, stream)));
    try s.put(owner, "iterator", iterator);
    try s.put(owner, "next", try p.get(s, iterator, "next"));
    try s.put(owner, "steps", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, 0))));
    return next(s, owner);
}
fn next(s: *p.Scope, owner: c.JSValue) !af.Action {
    try s.put(owner, "body", c.pi_js_bool(s.engine.context, 0));
    var steps: u64 = 0;
    if (c.JS_ToBigUint64(s.engine.context, &steps, try s.get(owner, "steps")) < 0) return js.capture(s.engine);
    steps +|= 1;
    if (s.engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: { s.engine.interrupts +|= 1; break :blk s.engine.interrupts > s.engine.options.interrupt_budget; })) {
        _ = c.JS_ThrowInternalError(s.engine.context, "interrupted");
        const reason = c.JS_GetException(s.engine.context); c.JS_SetUncatchableError(s.engine.context, reason);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, reason)); unreachable;
    }
    try s.put(owner, "steps", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, steps))));
    return p.wait(s, owner, try s.get(owner, "next"), try s.get(owner, "iterator"), &.{}, @intFromEnum(Stage.next));
}
fn iteration(s: *p.Scope, owner: c.JSValue, value: c.JSValue) !af.Action {
    if (!c.JS_IsObject(value)) return js.typeError(s.engine, "Iterator result is not an object");
    if (s.truthy(try p.get(s, value, "done"))) return requestResult(s, owner);
    const event = try p.get(s, value, "value");
    try s.put(owner, "body", c.pi_js_bool(s.engine.context, 1));
    const kind = try p.get(s, event, "type");
    if (s.equal(kind, try s.text("start"))) {
        const partial = try p.get(s, event, "partial"); try s.put(owner, "partial", partial);
        _ = try p.invoke(s, try p.get(s, try s.get(owner, "context"), "messages"), "push", &.{partial});
        try s.put(owner, "added", c.pi_js_bool(s.engine.context, 1));
        return emit(s, owner, try messageEvent(s, "message_start", try spread(s, partial)), .emitted);
    }
    inline for (.{ "text_start", "text_delta", "text_end", "thinking_start", "thinking_delta", "thinking_end", "toolcall_start", "toolcall_delta", "toolcall_end" }) |name| {
        if (s.equal(kind, try s.text(name))) {
            if (s.truthy(try s.get(owner, "partial"))) {
                const partial = try p.get(s, event, "partial"); try s.put(owner, "partial", partial);
                try replaceLast(s, owner, partial);
                const outgoing = try s.object(); try s.put(outgoing, "type", try s.text("message_update"));
                try s.put(outgoing, "assistantMessageEvent", event); try s.put(outgoing, "message", try spread(s, partial));
                return emit(s, owner, outgoing, .emitted);
            }
            return next(s, owner);
        }
    }
    if (s.equal(kind, try s.text("done")) or s.equal(kind, try s.text("error"))) return requestResult(s, owner);
    return next(s, owner);
}
fn spread(s: *p.Scope, value: c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return s.own(try p.guard(s.engine, generation, js.spread(s.engine, value))); }
fn messageEvent(s: *p.Scope, kind: []const u8, message: c.JSValue) !c.JSValue { const event = try s.object(); try s.put(event, "type", try s.text(kind)); try s.put(event, "message", message); return event; }
fn replaceLast(s: *p.Scope, owner: c.JSValue, value: c.JSValue) !void {
    const context = try s.get(owner, "context");
    const messages = try p.get(s, context, "messages");
    const length = try p.get(s, try p.get(s, context, "messages"), "length");
    const generation = s.engine.native_allocation_generation;
    const index = try s.own(try p.guard(s.engine, generation, s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 1, length, c.JS_NewInt32(s.engine.context, 1)))));
    const set_generation = s.engine.native_allocation_generation;
    js.setKey(s.engine, messages, index, value) catch |err| { _ = try p.guard(s.engine, set_generation, @as(anyerror!c.JSValue, err)); };
}
fn emit(s: *p.Scope, owner: c.JSValue, event: c.JSValue, stage: Stage) !af.Action { return p.wait(s, owner, try s.get(owner, "emit"), c.pi_js_undefined(), &.{event}, @intFromEnum(stage)); }
fn requestResult(s: *p.Scope, owner: c.JSValue) !af.Action { return p.wait(s, owner, try s.get(owner, "result"), c.pi_js_undefined(), &.{}, @intFromEnum(Stage.result)); }
fn finalResult(s: *p.Scope, owner: c.JSValue, message: c.JSValue) !af.Action {
    try s.put(owner, "final", message);
    if (s.truthy(try s.get(owner, "added"))) try replaceLast(s, owner, message) else {
        _ = try p.invoke(s, try p.get(s, try s.get(owner, "context"), "messages"), "push", &.{message});
        return emit(s, owner, try messageEvent(s, "message_start", try spread(s, message)), .final_start);
    }
    return emitFinal(s, owner);
}
fn emitFinal(s: *p.Scope, owner: c.JSValue) !af.Action { return emit(s, owner, try messageEvent(s, "message_end", try s.get(owner, "final")), .final_end); }
fn fail(s: *p.Scope, owner: c.JSValue, reason: c.JSValue) !af.Action {
    if (s.truthy(try s.get(owner, "body"))) return close(s, owner, true, reason);
    return .{ .thrown = c.JS_DupValue(s.engine.context, reason) };
}
fn close(s: *p.Scope, owner: c.JSValue, rejected: bool, value: c.JSValue) !af.Action {
    try s.put(owner, "body", c.pi_js_bool(s.engine.context, 0));
    try s.put(owner, "closeRejected", c.pi_js_bool(s.engine.context, @intFromBool(rejected))); try s.put(owner, "closeValue", value);
    return closeAttempt(s, owner) catch |err| {
        const replacement = try s.own(try p.caught(s.engine, err));
        return closeCompletion(s, owner, true, replacement);
    };
}
fn closeAttempt(s: *p.Scope, owner: c.JSValue) !af.Action {
    const iterator = try s.get(owner, "iterator"); const method = try p.get(s, iterator, "return");
    if (nullish(method)) return savedCompletion(s, owner);
    return p.wait(s, owner, method, iterator, &.{}, @intFromEnum(Stage.closed));
}
fn savedCompletion(s: *p.Scope, owner: c.JSValue) !af.Action {
    const value = c.JS_DupValue(s.engine.context, try s.get(owner, "closeValue"));
    return if (s.truthy(try s.get(owner, "closeRejected"))) .{ .thrown = value } else .{ .returned = value };
}
fn closeCompletion(s: *p.Scope, owner: c.JSValue, rejected: bool, input: c.JSValue) !af.Action {
    if (s.truthy(try s.get(owner, "closeRejected"))) return savedCompletion(s, owner);
    if (rejected) return .{ .thrown = c.JS_DupValue(s.engine.context, input) };
    if (!c.JS_IsObject(input)) return js.typeError(s.engine, "Iterator return result is not an object");
    return savedCompletion(s, owner);
}
fn resultArrow(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action { return resultBody(engine, roots, state, completion, input) catch |err| p.failure(engine, err); }
fn resultBody(engine: *em.Engine, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    if (completion == .start) {
        const owner = try p.init(&s, state); const object = try p.global(&s, "Object");
        try s.put(owner, "assignReceiver", object); try s.put(owner, "assign", try p.get(&s, object, "assign"));
        return p.wait(&s, owner, try p.get(&s, roots[0], "result"), roots[0], &.{}, 0);
    }
    const patch = try s.object(); const reasoning = try p.get(&s, roots[1], "reasoning");
    try s.put(patch, "thinkingLevel", if (nullish(reasoning)) try s.text("off") else reasoning);
    return .{ .returned = c.JS_DupValue(engine.context, try p.call(&s, try s.get(state.*, "assign"), try s.get(state.*, "assignReceiver"), &.{ input, patch })) };
}

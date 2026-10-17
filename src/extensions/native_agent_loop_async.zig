//! Actual runAgentLoop/runAgentLoopContinue entry AFs and module identities.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const js = @import("native_js_values.zig");
const iter = @import("native_agent_af_iterator.zig");
const changes = @import("native_agent_tool_changes.zig");
const cache_key = "\x00native-agent-loop-af-module";
const Stage = enum(i32) { agent_start, turn_start, message_start, message_end, loop_end };
pub fn namespace(engine: *em.Engine) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const response = try s.own(try @import("native_agent_response_async.zig").create(engine));
    const tools = try s.own(try @import("native_agent_tools_async.zig").namespace(engine));
    const turns = try s.own(try @import("native_agent_turns_async.zig").create(engine, response, tools));
    const graph = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(graph, "runLoop", turns);
    inline for (.{false, true}) |continuing| try s.put(graph, if (continuing) "runAgentLoopContinue" else "runAgentLoop", try s.own(try create(engine, continuing, turns)));
    try s.put(graph, "streamAssistantResponse", response); try s.put(graph, "toolFunctions", tools);
    const retained = c.JS_DupValue(engine.context, graph);
    engine.native_module_values.put(engine.gpa, cache_key, retained) catch |err| { engine.freeValue(retained); return err; };
    return c.JS_DupValue(engine.context, graph);
}
pub fn loopFunction(engine: *em.Engine, continuing: bool) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    return c.JS_DupValue(engine.context, try s.get(try s.own(try namespace(engine)), if (continuing) "runAgentLoopContinue" else "runAgentLoop"));
}
fn create(engine: *em.Engine, comptime continuing: bool, turns: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
            return invoke(host, continuing, args, roots[0], state, completion, input) catch |err| {
                if (!c.JS_IsObject(state.*)) return p.failure(host, err);
                const reason = try p.caught(host, err); defer host.freeValue(reason);
                var s: p.Scope = .{ .engine = host }; defer s.deinit();
                return iter.throwCompletion(&s, state.*, reason);
            };
        }
    };
    return af.createResumable(engine, if (continuing) "runAgentLoopContinue" else "runAgentLoop", if (continuing) 5 else 6, Adapter.call, &.{turns});
}
fn at(args: []const c.JSValue, index: usize) c.JSValue { return if (args.len > index) args[index] else c.pi_js_undefined(); }
fn invoke(engine: *em.Engine, comptime continuing: bool, args: []const c.JSValue, turns: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return iter.throwCompletion(&s, state.*, input); }
    if (completion == .fulfilled) {
        const stage: Stage = @enumFromInt(try p.stage(&s, state.*));
        return switch (stage) {
            .agent_start => emit(&s, state.*, try event(&s, "turn_start"), .turn_start),
            .turn_start => if (continuing) startTurns(&s, state.*, turns) else initialMessages(&s, state.*, turns),
            .message_start => emit(&s, state.*, try messageEvent(&s, "message_end", try s.get(state.*, "iteratorValue")), .message_end),
            .message_end => nextMessage(&s, state.*, turns),
            .loop_end => .{ .returned = c.JS_DupValue(engine.context, try s.get(state.*, "newMessages")) },
        };
    }
    const owner = try p.init(&s, state);
    const context = at(args, if (continuing) 0 else 1);
    const config = at(args, if (continuing) 1 else 2);
    var initial = c.pi_js_undefined(); var messages: c.JSValue = undefined; var current: c.JSValue = undefined;
    if (continuing) {
        if (s.equal(try p.get(&s, try p.get(&s, context, "messages"), "length"), c.JS_NewInt32(engine.context, 0))) _ = try p.raise(&s, "Cannot continue: no messages in context");
        const list = try p.get(&s, context, "messages");
        const length = try p.get(&s, try p.get(&s, context, "messages"), "length");
        const generation = engine.native_allocation_generation;
        const index = try s.own(try p.guard(engine, generation, engine.checked(c.JS_PiBinaryOperator(engine.context, 1, length, c.JS_NewInt32(engine.context, 1)))));
        const property_generation = engine.native_allocation_generation;
        const last = try s.own(try p.guard(engine, property_generation, js.getKey(engine, list, index)));
        if (s.equal(try p.get(&s, last, "role"), try s.text("assistant"))) _ = try p.raise(&s, "Cannot continue from message role: assistant");
        messages = try s.array(); current = try s.own(try js.spread(engine, context));
    } else {
        initial = try s.own(try changes.declare(engine, context, at(args, 0)));
        messages = try changes.arraySpread(&s, &.{initial});
        current = try s.own(try js.spread(engine, context));
        try s.put(current, "messages", try changes.arraySpread(&s, &.{try p.get(&s, context, "messages"), initial}));
    }
    try s.put(owner, "currentContext", current); try s.put(owner, "initialMessages", initial); try s.put(owner, "newMessages", messages); try s.put(owner, "config", config);
    try s.put(owner, "emit", at(args, if (continuing) 2 else 3)); try s.put(owner, "signal", at(args, if (continuing) 3 else 4)); try s.put(owner, "stream", at(args, if (continuing) 4 else 5));
    return emit(&s, owner, try event(&s, "agent_start"), .agent_start);
}
pub fn event(s: *p.Scope, kind: []const u8) !c.JSValue { const result = try s.object(); try s.put(result, "type", try s.text(kind)); return result; }
pub fn messageEvent(s: *p.Scope, kind: []const u8, message: c.JSValue) !c.JSValue { const result = try event(s, kind); try s.put(result, "message", message); return result; }
fn emit(s: *p.Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !af.Action { return p.wait(s, owner, try s.get(owner, "emit"), c.pi_js_undefined(), &.{value}, @intFromEnum(stage)); }
fn initialMessages(s: *p.Scope, owner: c.JSValue, turns: c.JSValue) !af.Action { try iter.init(s, owner, try s.get(owner, "initialMessages")); return nextMessage(s, owner, turns); }
fn nextMessage(s: *p.Scope, owner: c.JSValue, turns: c.JSValue) !af.Action {
    const message = (try iter.next(s, owner)) orelse return startTurns(s, owner, turns);
    return emit(s, owner, try messageEvent(s, "message_start", message), .message_start);
}
fn startTurns(s: *p.Scope, owner: c.JSValue, turns: c.JSValue) !af.Action {
    const supplied = try s.get(owner, "stream");
    const stream = if (c.JS_IsNull(supplied) or c.JS_IsUndefined(supplied)) try s.own(try @import("native_agent_default_stream.zig").get(s.engine)) else supplied;
    return p.wait(s, owner, turns, c.pi_js_undefined(), &.{ try s.get(owner, "currentContext"), try s.get(owner, "newMessages"), try s.get(owner, "config"), try s.get(owner, "signal"), try s.get(owner, "emit"), stream }, @intFromEnum(Stage.loop_end));
}

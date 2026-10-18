//! Real exported runAgentLoop/runAgentLoopContinue Source bodies. Initial
//! event/for-of suspensions and the final Await runLoop are VM AF actions.
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const completed = @import("native_agent_af_completion.zig");
const js = @import("native_js_values.zig");
const changes = @import("native_agent_tool_changes.zig");
const af = p.af;
const c = p.c;
const Stage = enum(i32) { agent_started, turn_started, message_started, message_ended, loop_finished };
const Step = union(enum) { action: af.Action, agent_start: void, cache_next: void, next_message: void, message_start: void, turns: void };
const Phase = enum { entry, agent_start, cache_next, next_message, message_start, turns };

pub fn create(engine: *em.Engine, comptime continuing: bool) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, resumed: af.Completion, input: c.JSValue) anyerror!af.Action {
            return dispatch(host, continuing, args, state, resumed, input);
        }
    };
    return af.createResumable(engine, if (continuing) "runAgentLoopContinue" else "runAgentLoop", if (continuing) 5 else 6, Adapter.invoke, &.{});
}
fn dispatch(engine: *em.Engine, comptime continuing: bool, args: []const c.JSValue, state: *c.JSValue, resumed: af.Completion, input: c.JSValue) !af.Action {
    var phase: Phase = .entry;
    // Finite private native transitions, never extra VM Await actions. Every
    // phase retires its whole Scope before a later Source guest operation.
    const action: af.Action = run_phase: while (true) {
        var s: p.Scope = .{ .engine = engine };
        const staged = prepare(&s, phase, continuing, args, state, resumed, input);
        if (staged) |next| switch (next) {
            .action => |value| break :run_phase try completed.finishAction(&s, value),
            else => {
                const retired = try completed.finishAction(&s, .{ .returned = c.pi_js_undefined() });
                switch (retired) {
                    .returned => |value| engine.freeValue(value),
                    else => break :run_phase retired,
                }
                phase = switch (next) {
                    .agent_start => .agent_start,
                    .cache_next => .cache_next,
                    .next_message => .next_message,
                    .message_start => .message_start,
                    .turns => .turns,
                    .action => unreachable,
                };
            },
        } else |err| break :run_phase try completed.finishAction(&s, err);
    };
    return switch (action) {
        .thrown => blk: {
            var closing: p.Scope = .{ .engine = engine };
            const closed = try completed.finishPreserving(&closing, action, closeBody(&closing, state.*));
            var clearing: p.Scope = .{ .engine = engine };
            break :blk completed.finishPreserving(&clearing, closed, clearIterator(&clearing, state.*));
        },
        else => action,
    };
}
fn prepare(s: *p.Scope, phase: Phase, comptime continuing: bool, args: []const c.JSValue, state: *c.JSValue, resumed: af.Completion, input: c.JSValue) anyerror!Step {
    return switch (phase) {
        .entry => step(s, continuing, args, state, resumed, input),
        .agent_start => emitEvent(s, state.*, try event(s, "agent_start"), .agent_started),
        .cache_next => cacheNext(s, state.*),
        .next_message => nextMessage(s, state.*),
        .message_start => startMessage(s, state.*),
        .turns => .{ .action = try awaitTurns(s, state.*) },
    };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn step(s: *p.Scope, comptime continuing: bool, args: []const c.JSValue, state: *c.JSValue, resumed: af.Completion, input: c.JSValue) !Step {
    const engine = s.engine;
    if (resumed == .rejected) {
        try p.rejected(s, state.*, input);
        return .{ .action = .{ .thrown = c.JS_DupValue(engine.context, input) } };
    }
    if (resumed == .start) {
        const owner = try p.init(s, state);
        try s.put(owner, "iterator_active", c.pi_js_bool(engine.context, 0));
        const context = arg(args, if (continuing) 0 else 1);
        const config = arg(args, if (continuing) 1 else 2);
        const emit = arg(args, if (continuing) 2 else 3);
        const signal = arg(args, if (continuing) 3 else 4);
        const stream = arg(args, if (continuing) 4 else 5);
        var initial = c.pi_js_undefined();
        var messages: c.JSValue = undefined;
        if (continuing) {
            if (s.equal(try p.get(s, try p.get(s, context, "messages"), "length"), c.JS_NewInt32(engine.context, 0))) _ = try p.raise(s, "Cannot continue: no messages in context");
            const list = try p.get(s, context, "messages");
            const length = try p.get(s, try p.get(s, context, "messages"), "length");
            const index = try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, length, c.JS_NewInt32(engine.context, 1))));
            const boundary = engine.native_allocation_generation;
            const last = try s.own(try p.guard(engine, boundary, js.getKey(engine, list, index)));
            if (s.equal(try p.get(s, last, "role"), try s.text("assistant"))) _ = try p.raise(s, "Cannot continue from message role: assistant");
            messages = try s.array();
        } else {
            initial = try s.own(try changes.declare(engine, context, arg(args, 0)));
            messages = try changes.arraySpread(s, &.{initial});
        }
        const current = try s.object();
        try js.spreadInto(engine, current, context);
        if (!continuing) try s.put(current, "messages", try changes.arraySpread(s, &.{ try p.get(s, context, "messages"), initial }));
        inline for (.{ .{ "context", current }, .{ "config", config }, .{ "emit", emit }, .{ "signal", signal }, .{ "stream", stream }, .{ "messages", messages }, .{ "initial", initial } }) |field| try s.put(owner, field[0], field[1]);
        return .{ .agent_start = {} };
    }
    const owner = state.*;
    const stage: Stage = @enumFromInt(try p.stage(s, owner));
    return switch (stage) {
        .agent_started => emitEvent(s, owner, try event(s, "turn_start"), .turn_started),
        .turn_started => if (continuing) .{ .turns = {} } else initIterator(s, owner),
        .message_started => emitEvent(s, owner, try messageEvent(s, "message_end", try s.get(owner, "message")), .message_ended),
        .message_ended => blk: {
            _ = try s.get(owner, "message");
            try s.put(owner, "message", c.pi_js_undefined());
            break :blk .{ .next_message = {} };
        },
        .loop_finished => .{ .action = .{ .returned = c.JS_DupValue(engine.context, try s.get(owner, "messages")) } },
    };
}
fn event(s: *p.Scope, name: []const u8) !c.JSValue {
    const value = try s.object(); try s.put(value, "type", try s.text(name)); return value;
}
fn messageEvent(s: *p.Scope, name: []const u8, message: c.JSValue) !c.JSValue {
    const value = try event(s, name); try s.put(value, "message", message); return value;
}
fn setStage(s: *p.Scope, owner: c.JSValue, stage: Stage) !void { try s.put(owner, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(stage))); }
fn emitEvent(s: *p.Scope, owner: c.JSValue, value: c.JSValue, next: Stage) !Step {
    const emit = try s.get(owner, "emit"); try setStage(s, owner, next);
    return .{ .action = .{ .awaited = c.JS_DupValue(s.engine.context, try p.call(s, emit, c.pi_js_undefined(), &.{value})) } };
}
fn initIterator(s: *p.Scope, owner: c.JSValue) !Step {
    const iterable = try s.get(owner, "initial");
    const symbol = try s.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
    const boundary = s.engine.native_allocation_generation;
    const method = try s.own(try p.guard(s.engine, boundary, js.getKey(s.engine, iterable, symbol)));
    const iterator = try p.call(s, method, iterable, &.{});
    if (!c.JS_IsObject(iterator)) return js.typeError(s.engine, "Iterator is not an object");
    try s.put(owner, "iterator", iterator);
    return .{ .cache_next = {} };
}
fn cacheNext(s: *p.Scope, owner: c.JSValue) !Step {
    const iterator = try s.get(owner, "iterator");
    try s.put(owner, "next", try p.get(s, iterator, "next"));
    try s.put(owner, "steps", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, 0))));
    return .{ .next_message = {} };
}
fn nextMessage(s: *p.Scope, owner: c.JSValue) !Step {
    // Abrupt iterator next/result/done/value exits precede loop-body entry;
    // unlike an abrupt body completion they do not call iterator.return.
    try s.put(owner, "iterator_active", c.pi_js_bool(s.engine.context, 0));
    var steps: u64 = 0;
    if (c.JS_ToBigUint64(s.engine.context, &steps, try s.get(owner, "steps")) < 0) return js.capture(s.engine);
    steps +|= 1;
    if (s.engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: {
        s.engine.interrupts +|= 1;
        break :blk s.engine.interrupts > s.engine.options.interrupt_budget;
    })) {
        _ = c.JS_ThrowInternalError(s.engine.context, "interrupted");
        const reason = c.JS_GetException(s.engine.context); c.JS_SetUncatchableError(s.engine.context, reason);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, reason)); unreachable;
    }
    try s.put(owner, "steps", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, steps))));
    const iterator = try s.get(owner, "iterator");
    const result = try p.call(s, try s.get(owner, "next"), iterator, &.{});
    if (!c.JS_IsObject(result)) return js.typeError(s.engine, "Iterator result is not an object");
    if (s.truthy(try p.get(s, result, "done"))) {
        try clearIterator(s, owner);
        return .{ .turns = {} };
    }
    const message = try p.get(s, result, "value");
    try s.put(owner, "message", message);
    return .{ .message_start = {} };
}
fn startMessage(s: *p.Scope, owner: c.JSValue) !Step {
    try s.put(owner, "iterator_active", c.pi_js_bool(s.engine.context, 1));
    return emitEvent(s, owner, try messageEvent(s, "message_start", try s.get(owner, "message")), .message_started);
}
fn awaitTurns(s: *p.Scope, owner: c.JSValue) !af.Action {
    const supplied = try s.get(owner, "stream");
    const stream = if (c.JS_IsNull(supplied) or c.JS_IsUndefined(supplied)) try s.own(try @import("native_agent_default_stream.zig").get(s.engine)) else supplied;
    try setStage(s, owner, .loop_finished);
    return .{ .awaited = try @import("native_agent_loop.zig").runTurns(s.engine, try s.get(owner, "context"), try s.get(owner, "messages"), try s.get(owner, "config"), try s.get(owner, "signal"), try s.get(owner, "emit"), stream) };
}
fn closeBody(s: *p.Scope, owner: c.JSValue) !void {
    if (c.JS_IsUndefined(owner) or !s.truthy(try s.get(owner, "iterator_active"))) return;
    try s.put(owner, "iterator_active", c.pi_js_bool(s.engine.context, 0));
    const iterator = try s.get(owner, "iterator");
    const method = try p.get(s, iterator, "return");
    if (c.JS_IsNull(method) or c.JS_IsUndefined(method)) return;
    _ = try p.call(s, method, iterator, &.{});
    // Throw-completion IteratorClose preserves its original throw even when
    // return() yields a primitive. This synchronous for-of never Awaits it.
}
fn clearIterator(s: *p.Scope, owner: c.JSValue) !void {
    if (c.JS_IsUndefined(owner)) return;
    // Keep each old owned field in this Scope BEFORE replacing it, so any
    // finalizer event is observed by the local per-value completion reducer.
    const iterator = try s.get(owner, "iterator");
    if (c.JS_IsUndefined(iterator)) return;
    try s.put(owner, "iterator", c.pi_js_undefined());
    inline for (.{ "next", "message" }) |name| {
        _ = try s.get(owner, name);
        try s.put(owner, name, c.pi_js_undefined());
    }
    try s.put(owner, "steps", c.pi_js_undefined());
    try s.put(owner, "iterator_active", c.pi_js_bool(s.engine.context, 0));
}

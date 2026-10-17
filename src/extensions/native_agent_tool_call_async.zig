//! Source tool preparation, execution and after-hook bodies; real AF boundaries.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const js = @import("native_js_values.zig");
const functions = @import("native_node_function.zig");
const old = @import("native_agent_tool_call.zig"); // Synchronous Source helpers only.
const nullish = @import("native_sdk_prompt_scope.zig").nullish;
pub const Kind = enum { prepare, execute, finalize };
pub fn create(engine: *em.Engine, comptime kind: Kind) !c.JSValue {
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
            return dispatch(host, kind, args, state, completion, input) catch |err| {
                const reason = p.caught(host, err) catch |fatal| {
                    if (kind == .execute and c.JS_IsObject(state.*)) {
                        var cleanup: p.Scope = .{ .engine = host }; defer cleanup.deinit();
                        if (cleanup.truthy(try cleanup.get(state.*, "sourceTry"))) try cleanup.put(state.*, "accepting", c.pi_js_bool(host.context, 0));
                    }
                    return fatal;
                }; defer host.freeValue(reason);
                if (!c.JS_IsObject(state.*)) return .{ .thrown = c.JS_DupValue(host.context, reason) };
                var s: p.Scope = .{ .engine = host }; defer s.deinit();
                if (s.truthy(try s.get(state.*, "sourceTry"))) {
                    try s.put(state.*, "sourceTry", c.pi_js_bool(host.context, 0));
                    return caught(&s, kind, state.*, reason);
                }
                return .{ .thrown = c.JS_DupValue(host.context, reason) };
            };
        }
    };
    return af.createResumable(engine, switch (kind) { .prepare => "prepareToolCall", .execute => "executePreparedToolCall", .finalize => "finalizeExecutedToolCall" }, switch (kind) { .prepare => 5, .execute => 3, .finalize => 6 }, Adapter.call, &.{});
}
fn at(args: []const c.JSValue, index: usize) c.JSValue { return if (args.len > index) args[index] else c.pi_js_undefined(); }
fn dispatch(engine: *em.Engine, comptime kind: Kind, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion != .start) {
        if (completion == .rejected) {
            try p.rejected(&s, state.*, input);
            if (s.truthy(try s.get(state.*, "sourceTry"))) { try s.put(state.*, "sourceTry", c.pi_js_bool(engine.context, 0)); return caught(&s, kind, state.*, input); }
            return .{ .thrown = c.JS_DupValue(engine.context, input) };
        }
        return switch (kind) { .prepare => afterBefore(&s, state.*, input), .execute => executed(&s, state.*, input), .finalize => afterFinalized(&s, state.*, input) };
    }
    const owner = try p.init(&s, state); try s.put(owner, "sourceTry", c.pi_js_bool(engine.context, 0));
    return switch (kind) { .prepare => beginPrepare(&s, owner, args), .execute => beginExecute(&s, owner, args), .finalize => beginFinalize(&s, owner, args) };
}
pub fn errorResult(s: *p.Scope, message: c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return s.own(try p.guard(s.engine, generation, old.errorResult(s.engine, message))); }
fn errorMessage(s: *p.Scope, reason: c.JSValue) !c.JSValue {
    const constructor = try p.global(s, "Error"); const generation = s.engine.native_allocation_generation;
    const instance = c.JS_IsInstanceOf(s.engine.context, reason, constructor);
    if (instance < 0) { _ = try p.guard(s.engine, generation, @as(anyerror!c.JSValue, js.capture(s.engine))); unreachable; }
    if (instance != 0) return p.get(s, reason, "message");
    return p.call(s, try p.global(s, "String"), c.pi_js_undefined(), &.{reason});
}
pub fn aborted(s: *p.Scope, signal: c.JSValue) !bool { return !nullish(signal) and s.truthy(try p.get(s, signal, "aborted")); }
fn immediate(s: *p.Scope, result: c.JSValue) !af.Action { const value = try s.object(); try s.put(value, "kind", try s.text("immediate")); try s.put(value, "result", result); try s.put(value, "isError", c.pi_js_bool(s.engine.context, 1)); return .{ .returned = c.JS_DupValue(s.engine.context, value) }; }
fn immediateText(s: *p.Scope, text: []const u8) !af.Action { return immediate(s, try errorResult(s, try s.text(text))); }
fn matched(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    return matchBody(&s, at(args, 0), roots[0]) catch |err| return p.callbackFailure(engine, err);
}
fn matchBody(s: *p.Scope, tool: c.JSValue, call: c.JSValue) !c.JSValue { const name = try p.get(s, tool, "name"); return c.pi_js_bool(s.engine.context, @intFromBool(s.equal(name, try p.get(s, call, "name")))); }
fn beginPrepare(s: *p.Scope, owner: c.JSValue, args: []const c.JSValue) !af.Action {
    inline for (.{ "context", "assistant", "call", "config", "signal" }, 0..) |name, index| try s.put(owner, name, at(args, index));
    const supplied = at(args, 5); const tools = if (c.JS_IsUndefined(supplied)) blk: { const live = try p.get(s, at(args, 0), "tools"); break :blk if (nullish(live)) try s.array() else live; } else supplied;
    const find = try p.get(s, tools, "find"); const predicate = try s.own(try functions.createArrow(s.engine, "", 1, matched, &.{at(args, 2)}));
    const tool = try p.call(s, find, tools, &.{predicate});
    if (!s.truthy(tool)) {
        const name_value = try p.get(s, at(args, 2), "name"); const name_generation = s.engine.native_allocation_generation;
        const name = try s.own(try p.guard(s.engine, name_generation, s.engine.checked(c.JS_ToString(s.engine.context, name_value))));
        const text = try s.concat(try s.concat(try s.text("Tool "), name), try s.text(" not found"));
        return immediate(s, try errorResult(s, text));
    }
    try s.put(owner, "tool", tool); try s.put(owner, "sourceTry", c.pi_js_bool(s.engine.context, 1));
    const call = at(args, 2); var prepared = call;
    if (s.truthy(try p.get(s, tool, "prepareArguments"))) {
        const function = try p.get(s, tool, "prepareArguments"); const arguments = try p.call(s, function, tool, &.{try p.get(s, call, "arguments")});
        if (!s.equal(arguments, try p.get(s, call, "arguments"))) { prepared = try spread(s, call); try s.put(prepared, "arguments", arguments); }
    }
    const generation = s.engine.native_allocation_generation;
    const validated = try s.own(try p.guard(s.engine, generation, @import("native_tool_arguments.zig").validateArguments(s.engine, tool, prepared)));
    try s.put(owner, "args", validated); const config = at(args, 3);
    if (s.truthy(try p.get(s, config, "beforeToolCall"))) {
        const function = try p.get(s, config, "beforeToolCall"); const request = try s.object();
        try s.put(request, "assistantMessage", at(args, 1)); try s.put(request, "toolCall", call); try s.put(request, "args", validated); try s.put(request, "context", at(args, 0));
        return p.wait(s, owner, function, config, &.{ request, at(args, 4) }, 0);
    }
    return finishPrepare(s, owner);
}
fn afterBefore(s: *p.Scope, owner: c.JSValue, value: c.JSValue) !af.Action {
    if (try aborted(s, try s.get(owner, "signal"))) return immediateText(s, "Operation aborted");
    if (!nullish(value) and s.truthy(try p.get(s, value, "block"))) {
        const reason = try p.get(s, value, "reason"); const result = try errorResult(s, if (s.truthy(reason)) reason else try s.text("Tool execution was blocked"));
        if (s.equal(try p.get(s, value, "terminate"), c.pi_js_bool(s.engine.context, 1))) try p.set(s, result, "terminate", c.pi_js_bool(s.engine.context, 1));
        return immediate(s, result);
    }
    return finishPrepare(s, owner);
}
fn finishPrepare(s: *p.Scope, owner: c.JSValue) !af.Action {
    if (try aborted(s, try s.get(owner, "signal"))) return immediateText(s, "Operation aborted");
    const result = try s.object(); try s.put(result, "kind", try s.text("prepared"));
    inline for (.{ .{ "toolCall", "call" }, .{ "tool", "tool" }, .{ "args", "args" } }) |field| try s.put(result, field[0], try s.get(owner, field[1]));
    return .{ .returned = c.JS_DupValue(s.engine.context, result) };
}
fn caught(s: *p.Scope, comptime kind: Kind, owner: c.JSValue, reason: c.JSValue) !af.Action {
    return switch (kind) {
        .prepare => immediate(s, try errorResult(s, try errorMessage(s, reason))),
        .execute => executeCaught(s, owner, reason),
        .finalize => blk: { try s.put(owner, "result", try errorResult(s, try errorMessage(s, reason))); try s.put(owner, "isError", c.pi_js_bool(s.engine.context, 1)); break :blk finishFinalize(s, owner); },
    };
}
fn beginExecute(s: *p.Scope, owner: c.JSValue, args: []const c.JSValue) !af.Action {
    inline for (.{ "prepared", "signal", "onUpdate" }, 0..) |name, index| try s.put(owner, name, at(args, index));
    try s.put(owner, "updates", try s.array()); try s.put(owner, "accepting", c.pi_js_bool(s.engine.context, 1));
    try s.put(owner, "started", try p.invoke(s, try p.global(s, "performance"), "now", &.{}));
    try s.put(owner, "sourceTry", c.pi_js_bool(s.engine.context, 1));
    const prepared = at(args, 0); const tool = try p.get(s, prepared, "tool"); const function = try p.get(s, tool, "execute");
    const id = try p.get(s, try p.get(s, prepared, "toolCall"), "id"); const arguments = try p.get(s, prepared, "args");
    const update = try s.own(try functions.createArrow(s.engine, "", 1, updateCallback, &.{owner}));
    return p.wait(s, owner, function, tool, &.{ id, arguments, at(args, 1), update }, 0);
}
fn updateCallback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return updateBody(engine, roots[0], at(args, 0)) catch |err| return p.callbackFailure(engine, err);
}
fn updateBody(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(try s.get(owner, "accepting"))) return c.pi_js_undefined();
    const updates = try s.get(owner, "updates"); const push = try p.get(&s, updates, "push");
    const promise = try p.global(&s, "Promise"); const resolve = try p.get(&s, promise, "resolve");
    const returned = try p.call(&s, try s.get(owner, "onUpdate"), c.pi_js_undefined(), &.{value});
    _ = try p.call(&s, push, updates, &.{try p.call(&s, resolve, promise, &.{returned})}); return c.pi_js_undefined();
}
fn elapsed(s: *p.Scope, owner: c.JSValue) !c.JSValue {
    const math = try p.global(s, "Math"); const round = try p.get(s, math, "round");
    const now = try p.invoke(s, try p.global(s, "performance"), "now", &.{}); const generation = s.engine.native_allocation_generation;
    const delta = try s.own(try p.guard(s.engine, generation, s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 1, now, try s.get(owner, "started")))));
    return p.call(s, round, math, &.{delta});
}
fn updatesWait(s: *p.Scope, owner: c.JSValue, stage: i32) !af.Action {
    const promise = try p.global(s, "Promise"); return p.wait(s, owner, try p.get(s, promise, "all"), promise, &.{try s.get(owner, "updates")}, stage);
}
fn executed(s: *p.Scope, owner: c.JSValue, value: c.JSValue) !af.Action {
    const stage = try p.stage(s, owner);
    if (stage == 0) {
        try s.put(owner, "result", value); try s.put(owner, "duration", try elapsed(s, owner)); try s.put(owner, "accepting", c.pi_js_bool(s.engine.context, 0));
        return updatesWait(s, owner, 1);
    }
    if (stage == 1) {
        const result = try s.get(owner, "result"); const output = try s.object(); try s.put(output, "result", result);
        try s.put(output, "isError", c.pi_js_bool(s.engine.context, @intFromBool(s.equal(try p.get(s, result, "isError"), c.pi_js_bool(s.engine.context, 1)))));
        try s.put(output, "durationMs", try s.get(owner, "duration")); return .{ .returned = c.JS_DupValue(s.engine.context, output) };
    }
    const output = try s.object(); try s.put(output, "result", try errorResult(s, try errorMessage(s, try s.get(owner, "error"))));
    try s.put(output, "isError", c.pi_js_bool(s.engine.context, 1)); try s.put(output, "durationMs", try s.get(owner, "duration")); return .{ .returned = c.JS_DupValue(s.engine.context, output) };
}
fn executeCaught(s: *p.Scope, owner: c.JSValue, reason: c.JSValue) !af.Action {
    return executeCaughtBody(s, owner, reason) catch |err| {
        try s.put(owner, "accepting", c.pi_js_bool(s.engine.context, 0));
        return err;
    };
}
fn executeCaughtBody(s: *p.Scope, owner: c.JSValue, reason: c.JSValue) !af.Action {
    try s.put(owner, "error", reason); try s.put(owner, "duration", try elapsed(s, owner)); try s.put(owner, "accepting", c.pi_js_bool(s.engine.context, 0));
    return updatesWait(s, owner, 2);
}
fn beginFinalize(s: *p.Scope, owner: c.JSValue, args: []const c.JSValue) !af.Action {
    inline for (.{ "context", "assistant", "prepared", "executed", "config", "signal" }, 0..) |name, index| try s.put(owner, name, at(args, index));
    try s.put(owner, "result", try p.get(s, at(args, 3), "result")); try s.put(owner, "isError", try p.get(s, at(args, 3), "isError"));
    const config = at(args, 4);
    if (s.truthy(try p.get(s, config, "afterToolCall"))) {
        try s.put(owner, "sourceTry", c.pi_js_bool(s.engine.context, 1)); const function = try p.get(s, config, "afterToolCall"); const request = try s.object();
        try s.put(request, "assistantMessage", at(args, 1)); try s.put(request, "toolCall", try p.get(s, at(args, 2), "toolCall")); try s.put(request, "args", try p.get(s, at(args, 2), "args"));
        try s.put(request, "result", try s.get(owner, "result")); try s.put(request, "isError", try s.get(owner, "isError")); try s.put(request, "context", at(args, 0));
        return p.wait(s, owner, function, config, &.{ request, at(args, 5) }, 0);
    }
    return finishFinalize(s, owner);
}
fn afterFinalized(s: *p.Scope, owner: c.JSValue, after: c.JSValue) !af.Action {
    if (s.truthy(after)) {
        const result = try s.get(owner, "result"); var structured = try p.get(s, after, "structuredContent");
        if (nullish(structured)) structured = if (s.truthy(try p.get(s, after, "content"))) c.pi_js_undefined() else try p.get(s, result, "structuredContent");
        const replacement = try spread(s, result);
        inline for (.{ "content", "details", "usage", "terminate" }) |name| { const value = try p.get(s, after, name); try s.put(replacement, name, if (nullish(value)) try p.get(s, result, name) else value); }
        try s.put(owner, "result", replacement);
        if (c.JS_IsUndefined(structured)) {
            const atom = c.JS_NewAtom(s.engine.context, "structuredContent"); defer c.JS_FreeAtom(s.engine.context, atom);
            if (c.JS_DeleteProperty(s.engine.context, replacement, atom, c.JS_PROP_THROW) < 0) return js.capture(s.engine);
        } else try p.set(s, replacement, "structuredContent", structured);
        const is_error = try p.get(s, after, "isError"); if (!nullish(is_error)) try s.put(owner, "isError", is_error);
    }
    try s.put(owner, "sourceTry", c.pi_js_bool(s.engine.context, 0)); return finishFinalize(s, owner);
}
fn finishFinalize(s: *p.Scope, owner: c.JSValue) !af.Action {
    const output = try s.object(); try s.put(output, "toolCall", try p.get(s, try s.get(owner, "prepared"), "toolCall"));
    try s.put(output, "result", try s.get(owner, "result")); try s.put(output, "isError", try s.get(owner, "isError")); try s.put(output, "durationMs", try p.get(s, try s.get(owner, "executed"), "durationMs"));
    return .{ .returned = c.JS_DupValue(s.engine.context, output) };
}
fn spread(s: *p.Scope, value: c.JSValue) !c.JSValue { const generation = s.engine.native_allocation_generation; return s.own(try p.guard(s.engine, generation, js.spread(s.engine, value))); }

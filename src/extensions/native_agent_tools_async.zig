//! Actual tool selector, sequential/truncated/parallel batches and their arrows.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const js = @import("native_js_values.zig");
const iter = @import("native_agent_af_iterator.zig");
const calls = @import("native_agent_tool_call_async.zig");
const events = @import("native_agent_tool_events_async.zig");
const functions = @import("native_node_function.zig");
const nullish = @import("native_sdk_prompt_scope.zig").nullish;
const Mode = enum { truncated, sequential, parallel };
const Stage = enum(i32) { start, prepared, executed, finalized, end, message, all, parallel_message };
pub fn namespace(engine: *em.Engine) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const graph = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    inline for (.{ .prepare, .execute, .finalize }) |kind| try s.put(graph, switch (kind) { .prepare => "prepare", .execute => "execute", .finalize => "finalize" }, try s.own(try calls.create(engine, kind)));
    try s.put(graph, "emitEnd", try s.own(try events.create(engine, false))); try s.put(graph, "emitMessage", try s.own(try events.create(engine, true)));
    inline for (.{ Mode.truncated, Mode.sequential, Mode.parallel }) |mode| try s.put(graph, switch (mode) { .truncated => "failToolCallsFromTruncatedMessage", .sequential => "sequential", .parallel => "parallel" }, try s.own(try batchFunction(engine, mode, graph)));
    try s.put(graph, "executeToolCalls", try s.own(try af.createResumable(engine, "executeToolCalls", 5, select, &.{graph})));
    try s.put(graph, "runToolCall", try s.own(try af.createResumable(engine, "runToolCall", 2, single, &.{graph})));
    return c.JS_DupValue(engine.context, graph);
}
fn at(args: []const c.JSValue, index: usize) c.JSValue { return if (args.len > index) args[index] else c.pi_js_undefined(); }
const Predicate = enum { tool_call, find_name, sequential, terminated, invoke_entry };
fn predicate(engine: *em.Engine, comptime kind: Predicate, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct { fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue { return predicateBody(host, kind, at(args, 0), captures) catch |err| return p.callbackFailure(host, err); } };
    return functions.createArrow(engine, "", 1, Adapter.call, roots);
}
fn predicateBody(engine: *em.Engine, comptime kind: Predicate, value: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    return switch (kind) {
        .tool_call => c.pi_js_bool(engine.context, @intFromBool(s.equal(try p.get(&s, value, "type"), try s.text("toolCall")))),
        .find_name => blk: { const name = try p.get(&s, value, "name"); break :blk c.pi_js_bool(engine.context, @intFromBool(s.equal(name, try p.get(&s, roots[0], "name")))); },
        .terminated => c.pi_js_bool(engine.context, @intFromBool(s.equal(try p.get(&s, try p.get(&s, value, "result"), "terminate"), c.pi_js_bool(engine.context, 1)))),
        .sequential => blk: {
            const tools = try p.get(&s, roots[0], "tools"); var tool = c.pi_js_undefined();
            if (!nullish(tools)) { const find = try p.get(&s, tools, "find"); const test_name = try s.own(try predicate(engine, .find_name, &.{value})); tool = try p.call(&s, find, tools, &.{test_name}); }
            break :blk c.pi_js_bool(engine.context, @intFromBool(!nullish(tool) and s.equal(try p.get(&s, tool, "executionMode"), try s.text("sequential"))));
        },
        .invoke_entry => blk: {
            if (c.JS_IsFunction(engine.context, value)) break :blk c.JS_DupValue(engine.context, try p.call(&s, value, c.pi_js_undefined(), &.{}));
            const promise = try p.global(&s, "Promise"); break :blk c.JS_DupValue(engine.context, try p.invoke(&s, promise, "resolve", &.{value}));
        },
    };
}
fn select(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) anyerror!af.Action {
    if (completion != .start) return error.UnexpectedToolSelectorResume;
    return selectBody(engine, args, roots[0]) catch |err| p.failure(engine, err);
}
fn selectBody(engine: *em.Engine, args: []const c.JSValue, graph: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const content = try p.get(&s, at(args, 1), "content"); const filter = try p.get(&s, content, "filter");
    const tool_calls = try p.call(&s, filter, content, &.{try s.own(try predicate(engine, .tool_call, &.{}))});
    const some = try p.get(&s, tool_calls, "some"); const sequential_test = try s.own(try predicate(engine, .sequential, &.{at(args, 0)}));
    const has_sequential = try p.call(&s, some, tool_calls, &.{sequential_test});
    const sequential = s.equal(try p.get(&s, at(args, 2), "toolExecution"), try s.text("sequential")) or s.truthy(has_sequential);
    const function = try s.get(graph, if (sequential) "sequential" else "parallel");
    return .{ .returned = c.JS_DupValue(engine.context, try p.call(&s, function, c.pi_js_undefined(), &.{ at(args, 0), at(args, 1), tool_calls, at(args, 2), at(args, 3), at(args, 4) })) };
}
fn batchFunction(engine: *em.Engine, comptime mode: Mode, graph: c.JSValue) !c.JSValue {
    const Adapter = struct { fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
        return batch(host, mode, args, roots[0], state, completion, input) catch |err| {
            const reason = try p.caught(host, err); defer host.freeValue(reason);
            if (!c.JS_IsObject(state.*)) return .{ .thrown = c.JS_DupValue(host.context, reason) };
            var s: p.Scope = .{ .engine = host }; defer s.deinit(); return iter.throwCompletion(&s, state.*, reason);
        };
    } };
    return af.createResumable(engine, switch (mode) { .truncated => "failToolCallsFromTruncatedMessage", .sequential => "executeToolCallsSequential", .parallel => "executeToolCallsParallel" }, if (mode == .truncated) 2 else 6, Adapter.call, &.{graph});
}
fn batch(engine: *em.Engine, comptime mode: Mode, args: []const c.JSValue, graph: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return iter.throwCompletion(&s, state.*, input); }
    if (completion == .fulfilled) return resumed(&s, mode, state.*, graph, @enumFromInt(try p.stage(&s, state.*)), input);
    const owner = try p.init(&s, state);
    if (mode == .truncated) { try s.put(owner, "calls", at(args, 0)); try s.put(owner, "emit", at(args, 1)); } else inline for (.{ "context", "assistant", "calls", "config", "signal", "emit" }, 0..) |name, index| try s.put(owner, name, at(args, index));
    if (mode != .parallel) try s.put(owner, "messages", try s.array());
    if (mode != .truncated) try s.put(owner, "finalizedCalls", try s.array());
    try iter.init(&s, owner, try s.get(owner, "calls")); return advance(&s, mode, owner, graph);
}
fn advance(s: *p.Scope, comptime mode: Mode, owner: c.JSValue, graph: c.JSValue) !af.Action {
    if (try iter.next(s, owner)) |call| return p.wait(s, owner, try s.get(owner, "emit"), c.pi_js_undefined(), &.{try events.startEvent(s, call)}, @intFromEnum(Stage.start));
    return planned(s, mode, owner, graph);
}
fn resumed(s: *p.Scope, comptime mode: Mode, owner: c.JSValue, graph: c.JSValue, stage: Stage, value: c.JSValue) !af.Action {
    switch (stage) {
        .start => {
            if (mode == .truncated) {
                const call = try s.get(owner, "iteratorValue"); const name = try p.get(s, call, "name"); const generation = s.engine.native_allocation_generation;
                const text_name = try s.own(try p.guard(s.engine, generation, s.engine.checked(c.JS_ToString(s.engine.context, name))));
                const text = try s.concat(try s.concat(try s.text("Tool call \""), text_name), try s.text("\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments."));
                const finalized = try immediateFinalized(s, call, try calls.errorResult(s, text), c.pi_js_bool(s.engine.context, 1));
                try s.put(owner, "finalized", finalized); return emitEnd(s, owner, graph, finalized);
            }
            return p.wait(s, owner, try s.get(graph, "prepare"), c.pi_js_undefined(), &.{ try s.get(owner, "context"), try s.get(owner, "assistant"), try s.get(owner, "iteratorValue"), try s.get(owner, "config"), try s.get(owner, "signal") }, @intFromEnum(Stage.prepared));
        },
        .prepared => {
            const call = try s.get(owner, "iteratorValue");
            if (s.equal(try p.get(s, value, "kind"), try s.text("immediate"))) {
                const finalized = try immediateFinalized(s, call, try p.get(s, value, "result"), try p.get(s, value, "isError"));
                try s.put(owner, "finalized", finalized); return emitEnd(s, owner, graph, finalized);
            }
            if (mode == .parallel) {
                const entry = try s.own(try af.createResumableArrow(s.engine, "", 0, parallelEntry, &.{ owner, value, call, graph }, c.pi_js_undefined()));
                _ = try p.invoke(s, try s.get(owner, "finalizedCalls"), "push", &.{entry}); return nextOrStop(s, mode, owner, graph);
            }
            try s.put(owner, "preparation", value); return execute(s, owner, graph, value, call, .executed);
        },
        .executed => return p.wait(s, owner, try s.get(graph, "finalize"), c.pi_js_undefined(), &.{ try s.get(owner, "context"), try s.get(owner, "assistant"), try s.get(owner, "preparation"), value, try s.get(owner, "config"), try s.get(owner, "signal") }, @intFromEnum(Stage.finalized)),
        .finalized => { try s.put(owner, "finalized", value); return emitEnd(s, owner, graph, value); },
        .end => {
            const finalized = try s.get(owner, "finalized");
            if (mode == .parallel) { _ = try p.invoke(s, try s.get(owner, "finalizedCalls"), "push", &.{finalized}); return nextOrStop(s, mode, owner, graph); }
            const message = try events.resultMessage(s, finalized); try s.put(owner, "message", message);
            return p.wait(s, owner, try s.get(graph, "emitMessage"), c.pi_js_undefined(), &.{ message, try s.get(owner, "emit") }, @intFromEnum(Stage.message));
        },
        .message => {
            if (mode == .sequential) _ = try p.invoke(s, try s.get(owner, "finalizedCalls"), "push", &.{try s.get(owner, "finalized")});
            _ = try p.invoke(s, try s.get(owner, "messages"), "push", &.{try s.get(owner, "message")});
            return if (mode == .truncated) advance(s, mode, owner, graph) else nextOrStop(s, mode, owner, graph);
        },
        .all => {
            try s.put(owner, "ordered", value); try s.put(owner, "messages", try s.array()); try iter.init(s, owner, value); return parallelMessage(s, owner, graph);
        },
        .parallel_message => {
            _ = try p.invoke(s, try s.get(owner, "messages"), "push", &.{try s.get(owner, "message")}); return parallelMessage(s, owner, graph);
        },
    }
}
fn immediateFinalized(s: *p.Scope, call: c.JSValue, result: c.JSValue, is_error: c.JSValue) !c.JSValue { const value = try s.object(); try s.put(value, "toolCall", call); try s.put(value, "result", result); try s.put(value, "isError", is_error); return value; }
fn emitEnd(s: *p.Scope, owner: c.JSValue, graph: c.JSValue, finalized: c.JSValue) !af.Action { return p.wait(s, owner, try s.get(graph, "emitEnd"), c.pi_js_undefined(), &.{ finalized, try s.get(owner, "emit") }, @intFromEnum(Stage.end)); }
fn nextOrStop(s: *p.Scope, comptime mode: Mode, owner: c.JSValue, graph: c.JSValue) !af.Action {
    if (try calls.aborted(s, try s.get(owner, "signal"))) { try iter.close(s, owner); return planned(s, mode, owner, graph); }
    return advance(s, mode, owner, graph);
}
fn planned(s: *p.Scope, comptime mode: Mode, owner: c.JSValue, graph: c.JSValue) !af.Action {
    _ = graph;
    if (mode == .parallel) {
        const promise = try p.global(s, "Promise"); const all = try p.get(s, promise, "all");
        const entries = try s.get(owner, "finalizedCalls"); const map = try p.get(s, entries, "map"); const mapper = try s.own(try predicate(s.engine, .invoke_entry, &.{}));
        const pending = try p.call(s, map, entries, &.{mapper}); return p.wait(s, owner, all, promise, &.{pending}, @intFromEnum(Stage.all));
    }
    return finish(s, owner, if (mode == .truncated) null else try s.get(owner, "finalizedCalls"));
}
fn finish(s: *p.Scope, owner: c.JSValue, finalized: ?c.JSValue) !af.Action {
    const value = try s.object(); try s.put(value, "messages", try s.get(owner, "messages")); var terminate = c.pi_js_bool(s.engine.context, 0);
    if (finalized) |list| if (try s.positive(try p.get(s, list, "length"))) { const every = try p.get(s, list, "every"); const test_result = try s.own(try predicate(s.engine, .terminated, &.{})); terminate = try p.call(s, every, list, &.{test_result}); };
    try s.put(value, "terminate", terminate); return .{ .returned = c.JS_DupValue(s.engine.context, value) };
}
fn parallelMessage(s: *p.Scope, owner: c.JSValue, graph: c.JSValue) !af.Action {
    if (try iter.next(s, owner)) |finalized| {
        const message = try events.resultMessage(s, finalized); try s.put(owner, "message", message);
        return p.wait(s, owner, try s.get(graph, "emitMessage"), c.pi_js_undefined(), &.{ message, try s.get(owner, "emit") }, @intFromEnum(Stage.parallel_message));
    }
    return finish(s, owner, try s.get(owner, "ordered"));
}
fn updater(s: *p.Scope, call: c.JSValue, emit: c.JSValue) !c.JSValue { return s.own(try functions.createArrow(s.engine, "", 1, updateEvent, &.{ call, emit })); }
fn updateEvent(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return updateEventBody(engine, roots[0], roots[1], at(args, 0)) catch |err| return p.callbackFailure(engine, err); }
fn updateEventBody(engine: *em.Engine, call: c.JSValue, emit: c.JSValue, partial: c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); const value = try events.event(&s, "tool_execution_update");
    try s.put(value, "toolCallId", try p.get(&s, call, "id")); try s.put(value, "toolName", try p.get(&s, call, "name")); try s.put(value, "args", try p.get(&s, call, "arguments")); try s.put(value, "partialResult", partial);
    return c.JS_DupValue(engine.context, try p.call(&s, emit, c.pi_js_undefined(), &.{value}));
}
fn execute(s: *p.Scope, owner: c.JSValue, graph: c.JSValue, prepared: c.JSValue, call: c.JSValue, stage: Stage) !af.Action { return p.wait(s, owner, try s.get(graph, "execute"), c.pi_js_undefined(), &.{ prepared, try s.get(owner, "signal"), try updater(s, call, try s.get(owner, "emit")) }, @intFromEnum(stage)); }
fn parallelEntry(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action { return parallelBody(engine, roots, state, completion, input) catch |err| p.failure(engine, err); }
fn parallelBody(engine: *em.Engine, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); const batch_owner = roots[0]; const graph = roots[3];
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    if (completion == .start) {
        const owner = try p.init(&s, state);
        if (try calls.aborted(&s, try s.get(batch_owner, "signal"))) {
            const finalized = try immediateFinalized(&s, roots[2], try calls.errorResult(&s, try s.text("Operation aborted")), c.pi_js_bool(engine.context, 1));
            try s.put(owner, "finalized", finalized); return p.wait(&s, owner, try s.get(graph, "emitEnd"), c.pi_js_undefined(), &.{ finalized, try s.get(batch_owner, "emit") }, 2);
        }
        return p.wait(&s, owner, try s.get(graph, "execute"), c.pi_js_undefined(), &.{ roots[1], try s.get(batch_owner, "signal"), try updater(&s, roots[2], try s.get(batch_owner, "emit")) }, 0);
    }
    switch (try p.stage(&s, state.*)) {
        0 => return p.wait(&s, state.*, try s.get(graph, "finalize"), c.pi_js_undefined(), &.{ try s.get(batch_owner, "context"), try s.get(batch_owner, "assistant"), roots[1], input, try s.get(batch_owner, "config"), try s.get(batch_owner, "signal") }, 1),
        1 => { try s.put(state.*, "finalized", input); return p.wait(&s, state.*, try s.get(graph, "emitEnd"), c.pi_js_undefined(), &.{ input, try s.get(batch_owner, "emit") }, 2); },
        2 => return .{ .returned = c.JS_DupValue(engine.context, try s.get(state.*, "finalized")) },
        else => return error.UnexpectedParallelToolStage,
    }
}
fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
fn single(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action { return singleBody(engine, args, roots[0], state, completion, input) catch |err| p.failure(engine, err); }
fn singleBody(engine: *em.Engine, args: []const c.JSValue, graph: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    if (completion == .start) {
        const owner = try p.init(&s, state); const options = at(args, 1); try s.put(owner, "options", options); try s.put(owner, "call", at(args, 0));
        inline for (.{ "assistantMessage", "context", "signal" }) |name| try s.put(owner, name, try p.get(&s, options, name));
        return p.wait(&s, owner, try s.get(graph, "prepare"), c.pi_js_undefined(), &.{ try s.get(owner, "context"), try s.get(owner, "assistantMessage"), at(args, 0), options, try s.get(owner, "signal"), try p.get(&s, options, "tools") }, 0);
    }
    if (try p.stage(&s, state.*) == 0) {
        if (s.equal(try p.get(&s, input, "kind"), try s.text("immediate"))) return .{ .returned = c.JS_DupValue(engine.context, try immediateFinalized(&s, try s.get(state.*, "call"), try p.get(&s, input, "result"), try p.get(&s, input, "isError"))) };
        try s.put(state.*, "preparation", input); const options = try s.get(state.*, "options"); const update = try p.get(&s, options, "onUpdate");
        return p.wait(&s, state.*, try s.get(graph, "execute"), c.pi_js_undefined(), &.{ input, try s.get(state.*, "signal"), if (nullish(update)) try s.own(try functions.createArrow(engine, "", 0, noop, &.{})) else update }, 1);
    }
    return .{ .returned = c.JS_DupValue(engine.context, try p.call(&s, try s.get(graph, "finalize"), c.pi_js_undefined(), &.{ try s.get(state.*, "context"), try s.get(state.*, "assistantMessage"), try s.get(state.*, "preparation"), input, try s.get(state.*, "options"), try s.get(state.*, "signal") })) };
}

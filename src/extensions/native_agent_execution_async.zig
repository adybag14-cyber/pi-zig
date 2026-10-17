//! Actual runPromptMessages/runContinuation and their lexical AF executors.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const functions = @import("native_node_function.zig");
pub fn create(engine: *em.Engine, comptime continuing: bool, actual_loop: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn run(host: *em.Engine, agent: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
            return outer(host, continuing, agent, args, roots[0], state, completion, input) catch |err| p.failure(host, err);
        }
    };
    return af.createResumable(engine, if (continuing) "runContinuation" else "runPromptMessages", if (continuing) 0 else 1, Adapter.run, &.{actual_loop});
}
fn outer(engine: *em.Engine, comptime continuing: bool, agent: c.JSValue, args: []const c.JSValue, loop: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .fulfilled) return .{ .returned = c.pi_js_undefined() };
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    const owner = try p.init(&s, state);
    const messages = if (args.len > 0) args[0] else c.pi_js_undefined();
    const options = if (!continuing and (args.len < 2 or c.JS_IsUndefined(args[1]))) try s.object() else if (args.len > 1) args[1] else c.pi_js_undefined();
    try s.put(owner, "options", options);
    const lifecycle = try p.get(&s, agent, "runWithLifecycle");
    const executor = try s.own(try createExecutor(engine, continuing, agent, messages, options, loop));
    return p.wait(&s, owner, lifecycle, agent, &.{executor}, 0);
}
fn createExecutor(engine: *em.Engine, comptime continuing: bool, agent: c.JSValue, messages: c.JSValue, options: c.JSValue, loop: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn run(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
            return executor(host, continuing, args, roots, state, completion, input) catch |err| p.failure(host, err);
        }
    };
    return af.createResumableArrow(engine, "", 1, Adapter.run, &.{ agent, messages, options, loop }, agent);
}
fn executor(engine: *em.Engine, comptime continuing: bool, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .fulfilled) return .{ .returned = c.pi_js_undefined() };
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    const owner = try p.init(&s, state);
    const snapshot = try p.invoke(&s, roots[0], "createContextSnapshot", &.{});
    const config = try p.invoke(&s, roots[0], "createLoopConfig", if (continuing) &.{} else &.{roots[2]});
    const emitter = try s.own(try functions.createArrow(engine, "", 1, emit, &.{roots[0]}));
    const signal = if (args.len > 0) args[0] else c.pi_js_undefined();
    const stream = try p.get(&s, roots[0], "streamFunction");
    return p.wait(&s, owner, roots[3], c.pi_js_undefined(), if (continuing) &.{ snapshot, config, emitter, signal, stream } else &.{ roots[1], snapshot, config, emitter, signal, stream }, 0);
}
fn emit(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const result = p.invoke(&s, roots[0], "processEvents", &.{if (args.len > 0) args[0] else c.pi_js_undefined()}) catch |err| return p.callbackFailure(engine, err);
    return c.JS_DupValue(engine.context, result);
}

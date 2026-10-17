//! Actual createLoopConfig lexical async arrows: return vs return-Await.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
pub const Kind = enum(i32) { prepare, steering, follow_up };
pub fn create(engine: *em.Engine, agent: c.JSValue, cell: c.JSValue, kind: Kind, name: [*:0]const u8, length: c_int) !c.JSValue {
    return af.createResumableArrow(engine, name, length, invoke, &.{ agent, cell, c.JS_NewInt32(engine.context, @intFromEnum(kind)) }, agent);
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    return run(engine, args, roots, state, completion, input) catch |err| p.failure(engine, err);
}
fn run(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .fulfilled) return .{ .returned = c.JS_DupValue(engine.context, input) };
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return .{ .thrown = c.JS_DupValue(engine.context, input) }; }
    var raw: i32 = 0;
    if (c.JS_ToInt32(engine.context, &raw, roots[2]) < 0) return @import("native_js_values.zig").capture(engine);
    const kind: Kind = @enumFromInt(raw);
    if (kind == .steering and s.truthy(try s.get(roots[1], "skip"))) {
        try s.put(roots[1], "skip", c.pi_js_bool(engine.context, 0));
        return .{ .returned = c.JS_DupValue(engine.context, try s.array()) };
    }
    if (kind != .prepare) {
        const queue = try p.get(&s, roots[0], if (kind == .steering) "steeringQueue" else "followUpQueue");
        return .{ .returned = c.JS_DupValue(engine.context, try p.invoke(&s, queue, "drain", &.{})) };
    }
    const owner = try p.init(&s, state);
    if (s.truthy(try p.get(&s, roots[0], "prepareNextTurnWithContext"))) {
        const handler = try p.get(&s, roots[0], "prepareNextTurnWithContext");
        const signal = try p.get(&s, roots[0], "signal");
        return p.wait(&s, owner, handler, roots[0], &.{ if (args.len > 0) args[0] else c.pi_js_undefined(), signal }, 0);
    }
    const handler = try p.get(&s, roots[0], "prepareNextTurn");
    if (c.JS_IsNull(handler) or c.JS_IsUndefined(handler)) {
        // Optional call skips signal lookup, but Source still says return await.
        try s.put(owner, "awaitGeneration", try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
        return .{ .awaited = c.pi_js_undefined() };
    }
    return p.wait(&s, owner, handler, roots[0], &.{try p.get(&s, roots[0], "signal")}, 0);
}

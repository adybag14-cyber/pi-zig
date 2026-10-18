//! Actual c268 public compaction selection/usage functions.
//! Keeps Source lexical slots separate from AF33/C435 expression temporaries.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const estimate = @import("native_sdk_compaction_estimate.zig");
const projection = @import("native_sdk_session_projection_live.zig");
const cache_key = "\x00sdk-public-compaction-core";
const Inputs = struct { cut: c.JSValue, turn: c.JSValue, estimate: c.JSValue };
const LastFrame = h.Frame(enum { i, entry, usage });
const ValidFrame = h.Frame(enum { points, i, entry });
const TurnFrame = h.Frame(enum { i });
const CutFrame = h.Frame(enum {
    points, accumulated, cut, i, entry, message_tokens, previous, cut_entry, starts_turn, turn_start,
});
extern "c" fn JS_PiDecrement(context: ?*c.JSContext, value: c.JSValue) c.JSValue;

pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var completed = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        completed.release(candidate);
        return completed.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    const defaults = try v.object(s);
    try v.put(s, defaults, "enabled", v.boolean(s, true));
    try v.put(s, defaults, "reserveTokens", v.number(s, 16384));
    try v.put(s, defaults, "keepRecentTokens", v.number(s, 20000));
    const cut = try v.ordinary(s, "isCutPointMessage", 1, cutMessage, &.{});
    const turn = try v.ordinary(s, "isTurnStartMessage", 1, turnMessage, &.{});
    const estimator = try v.own(s, try estimate.create(s.engine));
    const roots = [_]c.JSValue{cut, turn, estimator};
    inline for (.{
        .{ "calculateContextTokens", 1 },
        .{ "getLastAssistantUsage", 1 },
        .{ "shouldCompact", 3 },
        .{ "findTurnStartIndex", 3 },
        .{ "findCutPoint", 4 },
    }, 0..) |entry, index| {
        const Adapter = struct {
            fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
                const inputs: Inputs = .{ .cut = captures[0], .turn = captures[1], .estimate = captures[2] };
                return switch (index) {
                    0 => calculateContextTokens(engine, v.arg(args, 0)),
                    1 => getLastAssistantUsage(engine, v.arg(args, 0)),
                    2 => shouldCompact(engine, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
                    3 => findTurnStartIndex(engine, inputs, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
                    else => findCutPoint(engine, inputs, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2), v.arg(args, 3)),
                };
            }
        };
        try v.put(s, result, entry[0], try v.ordinary(s, entry[0], entry[1], Adapter.call, &roots));
    }
    try v.put(s, result, "estimateTokens", estimator);
    try v.put(s, result, "DEFAULT_COMPACTION_SETTINGS", defaults);
    return v.duplicate(s, result);
}
fn incrementOrDecrement(s: *Scope, value: c.JSValue, descending: bool) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s, if (descending)
        JS_PiDecrement(s.engine.context, value) else c.JS_PiIncrement(s.engine.context, value)));
}
fn decrement(engine: *Engine, value: c.JSValue) !c.JSValue {
    return h.expression(engine, incrementOrDecrement, .{ value, true });
}
fn relationIncoming(s: *Scope, left: c.JSValue, operation: h.math.Operation, incoming: anyerror!c.JSValue) !c.JSValue {
    const right = try v.own(s, try incoming);
    return v.duplicate(s, try h.binary(s, operation, left, right));
}
fn truthyIncoming(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.own(s, try incoming)));
}
fn zeroField(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, receiver, name), v.number(s, 0)));
}
fn minusOne(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, value, v.number(s, 1)));
}
fn lastIndex(s: *Scope, entries: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, try v.get(s, entries, "length"), v.number(s, 1)));
}
fn plusFirstFields(s: *Scope, usage: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, try v.get(s, usage, "input"), try v.get(s, usage, "output")));
}
fn plusField(s: *Scope, incoming: anyerror!c.JSValue, usage: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const left = try v.own(s, try incoming);
    return v.duplicate(s, try h.binary(s, .add, left, try v.get(s, usage, name)));
}
pub fn calculateContextTokens(engine: *Engine, usage: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    const total = v.get(&s, usage, "totalTokens") catch |err| return v.owned.finishValue(&s, @as(anyerror!c.JSValue, err));
    if (v.truthy(&s, total)) return v.owned.finishValue(&s, v.duplicate(&s, total));
    try v.owned.finishVoid(&s, {});
    return h.expression(engine, plusField, .{
        h.expression(engine, plusField, .{h.expression(engine, plusFirstFields, .{usage}), usage, @as([*:0]const u8, "cacheRead")}),
        usage, @as([*:0]const u8, "cacheWrite"),
    });
}
fn hasUsage(s: *Scope, message: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(message)) return v.typeError(s, "invalid 'in' operand");
    const name = try v.text(s, "usage");
    var atom_operation: v.guest.Boundary = .{ .engine = s.engine };
    try atom_operation.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, name);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try atom_operation.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const found = c.JS_HasProperty(s.engine.context, message, atom);
    try boundary.finishStatus(found);
    return v.boolean(s, found != 0);
}
fn calculateIncoming(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const usage = try v.own(s, try incoming);
    return calculateContextTokens(s.engine, usage);
}
fn positiveIncoming(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const tokens = try v.own(s, try incoming);
    return v.duplicate(s, try h.binary(s, .greater, tokens, v.number(s, 0)));
}
pub fn assistantUsage(engine: *Engine, message: c.JSValue) !c.JSValue {
    if (try h.fieldEqual(engine, message, "role", "assistant") and
        h.truthy(engine, try h.expression(engine, hasUsage, .{message})))
    {
        if (!try h.fieldEqual(engine, message, "stopReason", "aborted") and
            !try h.fieldEqual(engine, message, "stopReason", "error") and
            try h.fieldTest(engine, message, "usage", .truthy) and
            h.truthy(engine, try h.expression(engine, positiveIncoming, .{
                h.expression(engine, calculateIncoming, .{h.get(engine, message, "usage")}),
            })))
            return h.get(engine, message, "usage");
    }
    return c.pi_js_undefined();
}
fn usageIncoming(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const message = try v.own(s, try incoming);
    return assistantUsage(s.engine, message);
}
pub fn getLastAssistantUsage(engine: *Engine, entries: c.JSValue) !c.JSValue {
    var f = LastFrame.init(engine);
    return f.finish(lastUsageSource(&f, entries));
}
fn lastUsageSource(f: *LastFrame, entries: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.i, h.expression(engine, lastIndex, .{entries}));
    var steps: usize = 0;
    while (try h.compare(engine, .greater_equal, f.get(.i), h.number(engine, 0))) {
        try v.poll(engine, &steps);
        try f.clear(.entry);
        try f.set(.entry, h.key(engine, entries, f.get(.i)));
        if (try h.fieldEqual(engine, f.get(.entry), "type", "message")) {
            try f.clear(.usage);
            try f.set(.usage, h.expression(engine, usageIncoming, .{h.get(engine, f.get(.entry), "message")}));
            if (h.truthy(engine, f.get(.usage))) return h.duplicate(engine, f.get(.usage));
        }
        try f.set(.i, decrement(engine, f.get(.i)));
    }
    return c.pi_js_undefined();
}
fn reserveBoundary(s: *Scope, window: c.JSValue, settings: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, window, try v.get(s, settings, "reserveTokens")));
}
pub fn shouldCompact(engine: *Engine, tokens: c.JSValue, window: c.JSValue, settings: c.JSValue) !c.JSValue {
    if (!try h.fieldTest(engine, settings, "enabled", .truthy)) return c.JS_NewBool(engine.context, false);
    return h.expression(engine, relationIncoming, .{tokens, @as(h.math.Operation, .greater), h.expression(engine, reserveBoundary, .{window, settings})});
}
fn roleBody(s: *Scope, message: c.JSValue, turn: bool) !c.JSValue {
    const role = try v.get(s, message, "role");
    inline for (.{ "user", "bashExecution", "custom", "branchSummary", "compactionSummary" }) |name|
        if (try v.eq(s, role, name)) return v.boolean(s, true);
    return v.boolean(s, !turn and try v.eq(s, role, "assistant"));
}
fn cutMessage(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, roleBody, .{v.arg(args, 0), false});
}
fn turnMessage(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, roleBody, .{v.arg(args, 0), true});
}
fn someMessage(s: *Scope, incoming: anyerror!c.JSValue, callback: c.JSValue) !c.JSValue {
    const messages = try v.own(s, try incoming);
    const some = try v.get(s, messages, "some");
    return v.duplicate(s, try v.call(s, some, messages, &.{callback}));
}
fn messagesForEntry(engine: *Engine, entry: c.JSValue) !c.JSValue {
    return projection.entryMessages(engine, entry);
}
fn someForEntry(engine: *Engine, entry: c.JSValue, callback: c.JSValue) !c.JSValue {
    return h.expression(engine, someMessage, .{messagesForEntry(engine, entry), callback});
}
fn turnEntry(engine: *Engine, entry: c.JSValue, callback: c.JSValue) !c.JSValue {
    if (try h.fieldEqual(engine, entry, "type", "compaction")) return c.JS_NewBool(engine.context, false);
    return someForEntry(engine, entry, callback);
}
fn turnIncoming(s: *Scope, incoming: anyerror!c.JSValue, callback: c.JSValue) !c.JSValue {
    const entry = try v.own(s, try incoming);
    return turnEntry(s.engine, entry, callback);
}
fn validPoints(engine: *Engine, inputs: Inputs, entries: c.JSValue, start: c.JSValue, end: c.JSValue) !c.JSValue {
    var f = ValidFrame.init(engine);
    return f.finish(validSource(&f, inputs, entries, start, end));
}
fn validSource(f: *ValidFrame, inputs: Inputs, entries: c.JSValue, start: c.JSValue, end: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.points, h.array(engine));
    try f.set(.i, h.duplicate(engine, start));
    var steps: usize = 0;
    while (try h.compare(engine, .less, f.get(.i), end)) {
        try v.poll(engine, &steps);
        try f.clear(.entry);
        try f.set(.entry, h.key(engine, entries, f.get(.i)));
        if (!try h.fieldEqual(engine, f.get(.entry), "type", "compaction") and
            h.truthy(engine, try h.expression(engine, truthyIncoming, .{someForEntry(engine, f.get(.entry), inputs.cut)})))
            try h.discard(engine, f.get(.points), "push", &.{f.get(.i)});
        try f.set(.i, h.increment(engine, f.get(.i)));
    }
    return h.duplicate(engine, f.get(.points));
}
fn findTurnStartIndex(engine: *Engine, inputs: Inputs, entries: c.JSValue, index: c.JSValue, start: c.JSValue) !c.JSValue {
    var f = TurnFrame.init(engine);
    return f.finish(turnSource(&f, inputs, entries, index, start));
}
fn turnSource(f: *TurnFrame, inputs: Inputs, entries: c.JSValue, index: c.JSValue, start: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.i, h.duplicate(engine, index));
    var steps: usize = 0;
    while (try h.compare(engine, .greater_equal, f.get(.i), start)) {
        try v.poll(engine, &steps);
        if (h.truthy(engine, try h.expression(engine, truthyIncoming, .{
            h.expression(engine, turnIncoming, .{h.key(engine, entries, f.get(.i)), inputs.turn}),
        }))) return h.duplicate(engine, f.get(.i));
        try f.set(.i, decrement(engine, f.get(.i)));
    }
    return h.number(engine, -1);
}
fn sumTokens(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, sumBody, .{v.arg(args, 0), v.arg(args, 1), roots[0]});
}
fn sumBody(s: *Scope, sum: c.JSValue, message: c.JSValue, estimator: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, sum, try v.call(s, estimator, c.pi_js_undefined(), &.{message})));
}
fn reduceMessages(s: *Scope, incoming: anyerror!c.JSValue, estimator: c.JSValue) !c.JSValue {
    const messages = try v.own(s, try incoming);
    const reduce = try v.get(s, messages, "reduce");
    const callback = try v.arrow(s, "", 2, sumTokens, &.{estimator});
    return v.duplicate(s, try v.call(s, reduce, messages, &.{callback, v.number(s, 0)}));
}
fn sumValues(s: *Scope, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, a, b));
}
fn candidateAtOrAfter(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, candidateBody, .{v.arg(args, 0), roots[0]});
}
fn candidateBody(s: *Scope, candidate: c.JSValue, index: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .greater_equal, candidate, index));
}
fn findCandidate(s: *Scope, points: c.JSValue, index: c.JSValue) !c.JSValue {
    const find = try v.get(s, points, "find");
    const callback = try v.arrow(s, "", 1, candidateAtOrAfter, &.{index});
    return v.duplicate(s, try v.call(s, find, points, &.{callback}));
}
fn fallbackCandidate(s: *Scope, incoming: anyerror!c.JSValue, points: c.JSValue) !c.JSValue {
    const selected = try v.own(s, try incoming);
    if (!v.nullish(selected)) return v.duplicate(s, selected);
    const index = try v.own(s, try h.expression(s.engine, lastIndex, .{points}));
    return v.duplicate(s, try v.key(s, points, index));
}
fn precedingEntry(s: *Scope, entries: c.JSValue, cut: c.JSValue) !c.JSValue {
    const index = try h.binary(s, .subtract, cut, v.number(s, 1));
    return v.duplicate(s, try v.key(s, entries, index));
}
fn visibleMessages(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const messages = try v.own(s, try incoming);
    return v.duplicate(s, try v.get(s, messages, "length"));
}
fn visibleEntry(engine: *Engine, entry: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, positiveIncoming, .{
        h.expression(engine, visibleMessages, .{messagesForEntry(engine, entry)}),
    }));
}
fn cutResult(s: *Scope, cut: c.JSValue, turn: c.JSValue, split: bool) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "firstKeptEntryIndex", cut);
    try v.put(s, result, "turnStartIndex", turn);
    try v.put(s, result, "isSplitTurn", v.boolean(s, split));
    return v.duplicate(s, result);
}
fn findCutPoint(engine: *Engine, inputs: Inputs, entries: c.JSValue, start: c.JSValue, end: c.JSValue, keep: c.JSValue) !c.JSValue {
    var f = CutFrame.init(engine);
    return f.finish(cutSource(&f, inputs, entries, start, end, keep));
}
fn cutSource(f: *CutFrame, inputs: Inputs, entries: c.JSValue, start: c.JSValue, end: c.JSValue, keep: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.points, validPoints(engine, inputs, entries, start, end));
    if (h.truthy(engine, try h.expression(engine, zeroField, .{f.get(.points), @as([*:0]const u8, "length")})))
        return h.expression(engine, cutResult, .{start, h.number(engine, -1), false});
    try f.set(.accumulated, h.number(engine, 0));
    try f.set(.cut, h.key(engine, f.get(.points), h.number(engine, 0)));
    try f.set(.i, h.expression(engine, minusOne, .{end}));
    var steps: usize = 0;
    while (try h.compare(engine, .greater_equal, f.get(.i), start)) {
        try v.poll(engine, &steps);
        try f.clear(.message_tokens);
        try f.clear(.entry);
        try f.set(.entry, h.key(engine, entries, f.get(.i)));
        try f.set(.message_tokens, h.expression(engine, reduceMessages, .{messagesForEntry(engine, f.get(.entry)), inputs.estimate}));
        if (!c.JS_IsStrictEqual(engine.context, f.get(.message_tokens), h.number(engine, 0))) {
            try f.set(.accumulated, h.expression(engine, sumValues, .{f.get(.accumulated), f.get(.message_tokens)}));
            if (try h.compare(engine, .greater_equal, f.get(.accumulated), keep)) {
                try f.set(.cut, h.expression(engine, fallbackCandidate, .{h.expression(engine, findCandidate, .{f.get(.points), f.get(.i)}), f.get(.points)}));
                break;
            }
        }
        try f.set(.i, decrement(engine, f.get(.i)));
    }
    while (try h.compare(engine, .greater, f.get(.cut), start)) {
        try v.poll(engine, &steps);
        try f.clear(.previous);
        try f.set(.previous, h.expression(engine, precedingEntry, .{entries, f.get(.cut)}));
        if (try h.fieldEqual(engine, f.get(.previous), "type", "compaction") or
            try visibleEntry(engine, f.get(.previous))) break;
        try f.set(.cut, decrement(engine, f.get(.cut)));
    }
    try f.set(.cut_entry, h.key(engine, entries, f.get(.cut)));
    try f.set(.starts_turn, turnEntry(engine, f.get(.cut_entry), inputs.turn));
    try f.set(.turn_start, if (h.truthy(engine, f.get(.starts_turn)))
        h.number(engine, -1) else findTurnStartIndex(engine, inputs, entries, f.get(.cut), start));
    const split = !h.truthy(engine, f.get(.starts_turn)) and
        !c.JS_IsStrictEqual(engine.context, f.get(.turn_start), h.number(engine, -1));
    return h.expression(engine, cutResult, .{f.get(.cut), f.get(.turn_start), split});
}

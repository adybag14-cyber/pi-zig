//! Genuine c268 Bm25Ranker class and live Array/Map/Set callback algorithm.
//! Each escaping callback owns only its actual Source parameter/local cells.
const t = @import("native_sdk_tool_search_values.zig");
const h = t.h;
const v = t.v;
const c = t.c;
const Engine = t.Engine;
const Scope = t.Scope;
const Arguments = t.Arguments;
const RankFrame = t.Frame(enum { receiver, queryTerms, termCounts, lengths, averageLength, idf, matches });
const CountFrame = t.Frame(enum { counts, term });
const IdfFrame = t.Frame(enum { frequency });
const ScoreFrame = t.Frame(enum { score, term, count, norm });

pub fn create(s: *Scope, text_module: c.JSValue) !c.JSValue {
    const prototype = try v.object(s);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const constructor = try boundary.finishValue(s, @import("native_class.zig").constructor(
        s.engine, "Bm25Ranker", 0, prototype, construct, &.{}));
    const rank = try t.method(s, "rank", 3,
        .{ .formal_count = 3, .callback = rankCall, .hooks = t.sync.frameHooks(RankFrame) }, &.{text_module});
    var define: v.guest.Boundary = .{ .engine = s.engine }; try define.begin();
    try define.finishStatus(c.JS_DefinePropertyValueStr(s.engine.context, prototype, "rank",
        v.duplicate(s, rank), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE));
    return v.duplicate(s, constructor);
}
fn instance(s: *Scope, target: c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const prototype = try boundary.finishValue(s, c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, target));
    var node = @import("native_node_operation_scope.zig").Scope.init(s.engine);
    return v.own(s, try node.finish(instanceBody(&node, prototype)));
}
fn instanceBody(s: *@import("native_node_operation_scope.zig").Scope, prototype: c.JSValue) !c.JSValue {
    const generation = try s.beforeAllocation();
    const result = try s.checkedAllocation(c.JS_NewObjectProto(s.engine.context, prototype), generation);
    return c.JS_DupValue(s.engine.context, result);
}
fn assignOption(s: *Scope, receiver: c.JSValue, options: c.JSValue, field: [*:0]const u8, fallback: f64) !void {
    const selected = try v.get(s, options, field);
    try v.set(s, receiver, field, if (v.nullish(selected)) v.number(s, fallback) else selected);
}
fn constructBody(s: *Scope, target: c.JSValue, input: c.JSValue) !c.JSValue {
    const receiver = try instance(s, target);
    const options = if (c.JS_IsUndefined(input)) try v.object(s) else input;
    // These are the actual emitted class fields, before constructor [[Set]].
    try v.put(s, receiver, "k1", c.pi_js_undefined());
    try v.put(s, receiver, "b", c.pi_js_undefined());
    try h.statement(s.engine, assignOption, .{receiver, options, @as([*:0]const u8, "k1"), @as(f64, 1.2)});
    try h.statement(s.engine, assignOption, .{receiver, options, @as([*:0]const u8, "b"), @as(f64, 0.75)});
    return v.duplicate(s, receiver);
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, constructBody, .{target, v.arg(args, 0)});
}
fn tokenize(s: *Scope, text_module: c.JSValue, input: c.JSValue) !c.JSValue {
    return v.duplicate(s, try t.importCall(s, text_module, "tokenize", &.{input}));
}
fn querySet(s: *Scope, text_module: c.JSValue, query: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Set");
    const terms = try v.own(s, try h.expression(s.engine, tokenize, .{text_module, query}));
    return v.duplicate(s, try v.construct(s, constructor, &.{terms}));
}
fn queryArray(s: *Scope, text_module: c.JSValue, query: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    const terms = try v.own(s, try h.expression(s.engine, querySet, .{text_module, query}));
    var position: u32 = 0; try t.append(s, result, &position, terms);
    return v.duplicate(s, result);
}
fn zeroLength(engine: *Engine, value: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, t.fieldStrict,
        .{value, @as([*:0]const u8, "length"), h.number(engine, 0)}));
}
fn documentTerms(s: *Scope, text_module: c.JSValue, document: c.JSValue) !c.JSValue {
    const callable = try v.get(s, text_module, "tokenize");
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{try v.get(s, document, "text")}));
}
fn plusOne(s: *Scope, counts: c.JSValue, term: c.JSValue) !c.JSValue {
    const value = try v.own(s, try v.invokeOwned(s.engine, counts, "get", &.{term}));
    return v.duplicate(s, try h.binary(s, .add, if (v.nullish(value)) v.number(s, 0) else value, v.number(s, 1)));
}
fn countTerm(s: *Scope, counts: c.JSValue, term: c.JSValue) !void {
    const method_value = try v.get(s, counts, "set");
    const count = try v.own(s, try h.expression(s.engine, plusOne, .{counts, term}));
    _ = try v.call(s, method_value, counts, &.{term, count});
}
fn countTerms(frame: *CountFrame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try frame.take(.term, incoming);
        try h.statement(frame.engine, countTerm, .{frame.get(.counts), frame.get(.term)});
    }
}
fn countsBody(s: *Scope, args: *Arguments, text_module: c.JSValue) !c.JSValue {
    const frame = try args.createFrame(s, CountFrame);
    try frame.take(.counts, h.construct(s.engine, "Map", &.{}));
    var iterator = try v.Iterator.initOwned(s.engine, try h.expression(s.engine, documentTerms, .{text_module, args.get(0)}));
    try iterator.finish(countTerms(frame, &iterator));
    return h.duplicate(s.engine, frame.get(.counts));
}
fn countsCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, countsBody, .{args, roots[0]});
}
fn termCounts(s: *Scope, documents: c.JSValue, text_module: c.JSValue) !c.JSValue {
    const callee = try v.get(s, documents, "map");
    const callback = try t.arrow(s, "", 1,
        .{ .formal_count = 1, .callback = countsCall, .hooks = t.sync.frameHooks(CountFrame) }, &.{text_module});
    return v.duplicate(s, try v.call(s, callee, documents, &.{callback}));
}
fn sumCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, sumBody, .{args.get(0), args.get(1)});
}
fn sumBody(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, left, right));
}
fn valuesArray(s: *Scope, counts: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    const values = try v.own(s, try v.invokeOwned(s.engine, counts, "values", &.{}));
    var position: u32 = 0; try t.append(s, result, &position, values);
    return v.duplicate(s, result);
}
fn sumValues(s: *Scope, counts: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, valuesArray, .{counts}));
    const callee = try v.get(s, receiver, "reduce");
    const callback = try t.arrow(s, "", 2, .{ .formal_count = 2, .callback = sumCall }, &.{});
    return v.duplicate(s, try v.call(s, callee, receiver, &.{callback, v.number(s, 0)}));
}
fn lengthsCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, sumValues, .{args.get(0)});
}
fn lengths(s: *Scope, counts: c.JSValue) !c.JSValue {
    const callee = try v.get(s, counts, "map");
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = lengthsCall }, &.{});
    return v.duplicate(s, try v.call(s, callee, counts, &.{callback}));
}
fn sumLengths(s: *Scope, values: c.JSValue) !c.JSValue {
    const callee = try v.get(s, values, "reduce");
    const callback = try t.arrow(s, "", 2, .{ .formal_count = 2, .callback = sumCall }, &.{});
    return v.duplicate(s, try v.call(s, callee, values, &.{callback, v.number(s, 0)}));
}
fn average(s: *Scope, values: c.JSValue, documents: c.JSValue) !c.JSValue {
    const total_length = try v.own(s, try h.expression(s.engine, sumLengths, .{values}));
    const result = try h.binary(s, .divide, total_length, try v.get(s, documents, "length"));
    return v.duplicate(s, if (v.truthy(s, result)) result else v.number(s, 1));
}
fn hasCapturedTerm(s: *Scope, counts: c.JSValue, term_cell: c.JSValue) !c.JSValue {
    const callee = try v.get(s, counts, "has");
    const term = try t.sync.read(s, term_cell);
    return v.duplicate(s, try v.call(s, callee, counts, &.{term}));
}
fn hasTermCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, hasCapturedTerm, .{args.get(0), roots[0]});
}
fn filteredFrequency(s: *Scope, args: *Arguments, counts_cell: c.JSValue) !c.JSValue {
    const counts = try RankFrame.read(s, counts_cell);
    const callee = try v.get(s, counts, "filter");
    const term_cell = try args.capture(s, 0);
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = hasTermCall }, &.{term_cell});
    return v.duplicate(s, try v.call(s, callee, counts, &.{callback}));
}
fn frequency(s: *Scope, args: *Arguments, counts_cell: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, filteredFrequency, .{args, counts_cell}));
    return v.duplicate(s, try v.get(s, receiver, "length"));
}
fn subtractFrequency(s: *Scope, documents_cell: c.JSValue, value: c.JSValue) !c.JSValue {
    const documents = try t.sync.read(s, documents_cell);
    const count = try v.get(s, documents, "length");
    return v.duplicate(s, try h.binary(s, .subtract, count, value));
}
fn numerator(s: *Scope, documents_cell: c.JSValue, value: c.JSValue) !c.JSValue {
    const difference = try v.own(s, try h.expression(s.engine, subtractFrequency, .{documents_cell, value}));
    return v.duplicate(s, try h.binary(s, .add, difference, v.number(s, 0.5)));
}
fn denominator(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, value, v.number(s, 0.5)));
}
fn fraction(s: *Scope, documents_cell: c.JSValue, value: c.JSValue) !c.JSValue {
    const top = try v.own(s, try h.expression(s.engine, numerator, .{documents_cell, value}));
    const bottom = try v.own(s, try h.expression(s.engine, denominator, .{value}));
    return v.duplicate(s, try h.binary(s, .divide, top, bottom));
}
fn logArgument(s: *Scope, documents_cell: c.JSValue, value: c.JSValue) !c.JSValue {
    const right = try v.own(s, try h.expression(s.engine, fraction, .{documents_cell, value}));
    return v.duplicate(s, try h.binary(s, .add, v.number(s, 1), right));
}
fn idfValue(s: *Scope, documents_cell: c.JSValue, value: c.JSValue) !c.JSValue {
    const math = try v.global(s, "Math");
    const callee = try v.get(s, math, "log");
    const argument = try v.own(s, try h.expression(s.engine, logArgument, .{documents_cell, value}));
    return v.duplicate(s, try v.call(s, callee, math, &.{argument}));
}
fn idfPair(s: *Scope, term: c.JSValue, documents_cell: c.JSValue, value: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    try v.index(s, result, 0, term);
    try v.index(s, result, 1, try v.own(s, try h.expression(s.engine, idfValue, .{documents_cell, value})));
    return v.duplicate(s, result);
}
fn idfCallbackBody(s: *Scope, args: *Arguments, counts_cell: c.JSValue, documents_cell: c.JSValue) !c.JSValue {
    const frame = try args.createFrame(s, IdfFrame);
    try frame.take(.frequency, h.expression(s.engine, frequency, .{args, counts_cell}));
    return h.expression(s.engine, idfPair, .{args.get(0), documents_cell, frame.get(.frequency)});
}
fn idfCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, idfCallbackBody, .{args, roots[0], roots[1]});
}
fn idfPairs(s: *Scope, args: *Arguments, frame: *RankFrame) !c.JSValue {
    const receiver = frame.get(.queryTerms);
    const callee = try v.get(s, receiver, "map");
    const counts_cell = try frame.capture(s, .termCounts, "termCounts");
    const documents_cell = try args.capture(s, 1);
    const callback = try t.arrow(s, "", 1,
        .{ .formal_count = 1, .callback = idfCall, .hooks = t.sync.frameHooks(IdfFrame) }, &.{counts_cell, documents_cell});
    return v.duplicate(s, try v.call(s, callee, receiver, &.{callback}));
}
fn idfMap(s: *Scope, args: *Arguments, frame: *RankFrame) !c.JSValue {
    const constructor = try v.global(s, "Map");
    const entries = try v.own(s, try h.expression(s.engine, idfPairs, .{args, frame}));
    return v.duplicate(s, try v.construct(s, constructor, &.{entries}));
}
fn termCount(s: *Scope, counts_cell: c.JSValue, index: c.JSValue, term: c.JSValue) !c.JSValue {
    const counts = try RankFrame.read(s, counts_cell);
    const receiver = try v.key(s, counts, index);
    const callee = try v.get(s, receiver, "get");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{term}));
}
fn oneMinusB(s: *Scope, receiver_cell: c.JSValue) !c.JSValue {
    const receiver = try RankFrame.read(s, receiver_cell);
    return v.duplicate(s, try h.binary(s, .subtract, v.number(s, 1), try v.get(s, receiver, "b")));
}
fn bTimesLength(s: *Scope, receiver_cell: c.JSValue, lengths_cell: c.JSValue, index: c.JSValue) !c.JSValue {
    const receiver = try RankFrame.read(s, receiver_cell);
    const left = try v.get(s, receiver, "b");
    const all_lengths = try RankFrame.read(s, lengths_cell);
    return v.duplicate(s, try h.binary(s, .multiply, left, try v.key(s, all_lengths, index)));
}
fn normalizedLength(s: *Scope, receiver_cell: c.JSValue, lengths_cell: c.JSValue, average_cell: c.JSValue, index: c.JSValue) !c.JSValue {
    const left = try v.own(s, try h.expression(s.engine, bTimesLength, .{receiver_cell, lengths_cell, index}));
    const average_length = try RankFrame.read(s, average_cell);
    return v.duplicate(s, try h.binary(s, .divide, left, average_length));
}
fn normSum(s: *Scope, roots: []const c.JSValue, index: c.JSValue) !c.JSValue {
    const left = try v.own(s, try h.expression(s.engine, oneMinusB, .{roots[0]}));
    const right = try v.own(s, try h.expression(s.engine, normalizedLength, .{roots[0], roots[3], roots[4], index}));
    return v.duplicate(s, try h.binary(s, .add, left, right));
}
fn norm(s: *Scope, roots: []const c.JSValue, index: c.JSValue) !c.JSValue {
    const receiver = try RankFrame.read(s, roots[0]);
    const k1 = try v.get(s, receiver, "k1");
    const value = try v.own(s, try h.expression(s.engine, normSum, .{roots, index}));
    return v.duplicate(s, try h.binary(s, .multiply, k1, value));
}
fn idfTerm(s: *Scope, idf_cell: c.JSValue, term: c.JSValue) !c.JSValue {
    const receiver = try RankFrame.read(s, idf_cell);
    const callee = try v.get(s, receiver, "get");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{term}));
}
fn k1PlusOne(s: *Scope, receiver_cell: c.JSValue) !c.JSValue {
    const receiver = try RankFrame.read(s, receiver_cell);
    return v.duplicate(s, try h.binary(s, .add, try v.get(s, receiver, "k1"), v.number(s, 1)));
}
fn weightedCount(s: *Scope, receiver_cell: c.JSValue, count: c.JSValue) !c.JSValue {
    const multiplier = try v.own(s, try h.expression(s.engine, k1PlusOne, .{receiver_cell}));
    return v.duplicate(s, try h.binary(s, .multiply, count, multiplier));
}
fn countPlusNorm(s: *Scope, count: c.JSValue, norm_value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, count, norm_value));
}
fn scoreFraction(s: *Scope, receiver_cell: c.JSValue, count: c.JSValue, norm_value: c.JSValue) !c.JSValue {
    const top = try v.own(s, try h.expression(s.engine, weightedCount, .{receiver_cell, count}));
    const bottom = try v.own(s, try h.expression(s.engine, countPlusNorm, .{count, norm_value}));
    return v.duplicate(s, try h.binary(s, .divide, top, bottom));
}
fn scoreProduct(s: *Scope, roots: []const c.JSValue, frame: *ScoreFrame) !c.JSValue {
    const idf = try v.own(s, try h.expression(s.engine, idfTerm, .{roots[5], frame.get(.term)}));
    const fraction_value = try v.own(s, try h.expression(s.engine, scoreFraction, .{roots[0], frame.get(.count), frame.get(.norm)}));
    return v.duplicate(s, try h.binary(s, .multiply, if (v.nullish(idf)) v.number(s, 0) else idf, fraction_value));
}
fn scoreSum(s: *Scope, roots: []const c.JSValue, frame: *ScoreFrame) !c.JSValue {
    const current = frame.get(.score);
    const right = try v.own(s, try h.expression(s.engine, scoreProduct, .{roots, frame}));
    return v.duplicate(s, try h.binary(s, .add, current, right));
}
fn scoreTerms(frame: *ScoreFrame, iterator: *v.Iterator, roots: []const c.JSValue, index: c.JSValue) !void {
    while (try iterator.next()) |incoming| {
        try frame.take(.term, incoming);
        // The body block is reset in reverse declaration order after its head.
        try frame.clear(.norm); try frame.clear(.count);
        try frame.take(.count, h.expression(frame.engine, termCount, .{roots[2], index, frame.get(.term)}));
        if (!h.truthy(frame.engine, frame.get(.count))) continue;
        try frame.take(.norm, h.expression(frame.engine, norm, .{roots, index}));
        try frame.take(.score, h.expression(frame.engine, scoreSum, .{roots, frame}));
    }
}
fn matchRecord(s: *Scope, document: c.JSValue, score: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "name", try v.get(s, document, "name"));
    try v.put(s, result, "score", score);
    return v.duplicate(s, result);
}
fn pushMatch(s: *Scope, matches_cell: c.JSValue, document: c.JSValue, score: c.JSValue) !void {
    const receiver = try RankFrame.read(s, matches_cell);
    const callee = try v.get(s, receiver, "push");
    const result = try v.own(s, try h.expression(s.engine, matchRecord, .{document, score}));
    _ = try v.call(s, callee, receiver, &.{result});
}
fn scoreBody(s: *Scope, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    const frame = try args.createFrame(s, ScoreFrame);
    try frame.copy(.score, v.number(s, 0));
    var iterator = try v.Iterator.initOwned(s.engine, try readCell(s.engine, roots[1]));
    try iterator.finish(scoreTerms(frame, &iterator, roots, args.get(1)));
    if (try h.compare(s.engine, .greater, frame.get(.score), v.number(s, 0)))
        try h.statement(s.engine, pushMatch, .{roots[6], args.get(0), frame.get(.score)});
    return c.pi_js_undefined();
}
fn scoreCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, scoreBody, .{args, roots});
}
fn readCell(engine: *Engine, cell: c.JSValue) !c.JSValue {
    return h.expression(engine, readCellBody, .{cell});
}
fn readCellBody(s: *Scope, cell: c.JSValue) !c.JSValue {
    return v.duplicate(s, try RankFrame.read(s, cell));
}
fn forEach(s: *Scope, frame: *RankFrame, documents: c.JSValue) !void {
    const callee = try v.get(s, documents, "forEach");
    const roots = [_]c.JSValue{
        try frame.capture(s, .receiver, "this"), try frame.capture(s, .queryTerms, "queryTerms"),
        try frame.capture(s, .termCounts, "termCounts"), try frame.capture(s, .lengths, "lengths"),
        try frame.capture(s, .averageLength, "averageLength"), try frame.capture(s, .idf, "idf"),
        try frame.capture(s, .matches, "matches"),
    };
    const callback = try t.arrow(s, "", 2,
        .{ .formal_count = 2, .callback = scoreCall, .hooks = t.sync.frameHooks(ScoreFrame) }, &roots);
    _ = try v.call(s, callee, documents, &.{callback});
}
fn compareScore(s: *Scope, first: c.JSValue, second: c.JSValue) !c.JSValue {
    const left = try v.get(s, second, "score");
    return v.duplicate(s, try h.binary(s, .subtract, left, try v.get(s, first, "score")));
}
fn compareCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, compareScore, .{args.get(0), args.get(1)});
}
fn sorted(s: *Scope, matches: c.JSValue) !c.JSValue {
    const callee = try v.get(s, matches, "sort");
    const callback = try t.arrow(s, "", 2, .{ .formal_count = 2, .callback = compareCall }, &.{});
    return v.duplicate(s, try v.call(s, callee, matches, &.{callback}));
}
fn limited(s: *Scope, matches: c.JSValue, limit: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, sorted, .{matches}));
    const callee = try v.get(s, receiver, "slice");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{v.number(s, 0), limit}));
}
fn rankBody(s: *Scope, receiver: c.JSValue, args: *Arguments, text_module: c.JSValue) !c.JSValue {
    const frame = try args.createFrame(s, RankFrame);
    try frame.copy(.receiver, receiver);
    try frame.take(.queryTerms, h.expression(s.engine, queryArray, .{text_module, args.get(0)}));
    if (try zeroLength(s.engine, frame.get(.queryTerms)) or try zeroLength(s.engine, args.get(1)) or
        try h.compare(s.engine, .less_equal, args.get(2), v.number(s, 0)))
        return h.array(s.engine);
    try frame.take(.termCounts, h.expression(s.engine, termCounts, .{args.get(1), text_module}));
    try frame.take(.lengths, h.expression(s.engine, lengths, .{frame.get(.termCounts)}));
    try frame.take(.averageLength, h.expression(s.engine, average, .{frame.get(.lengths), args.get(1)}));
    try frame.take(.idf, h.expression(s.engine, idfMap, .{args, frame}));
    try frame.take(.matches, h.array(s.engine));
    try h.statement(s.engine, forEach, .{frame, args.get(1)});
    return h.expression(s.engine, limited, .{frame.get(.matches), args.get(2)});
}
fn rankCall(engine: *Engine, receiver: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, rankBody, .{receiver, args, roots[0]});
}

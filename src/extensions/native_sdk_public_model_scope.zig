//! c268 resolveModelScopeFromModels, with the original per-pattern algorithms.
//! Live callbacks/iterators retain original lexical slots separately from each
//! expression. Detached arrow captures coexist with those original slots.
const r = @import("native_sdk_model_reference_live.zig");
const h = @import("native_sdk_session_locals.zig");
const v = r.v;
const c = v.c;
const Scope = v.Scope;
pub const Inputs = struct { reference: r.Inputs, minimatch: c.JSValue, equal: c.JSValue };
const Frame = h.Frame(enum {
    scoped_models, diagnostics, add, no_match, ambiguous, pattern,
    thinking, glob_pattern, thinking_level, exact, matches_glob, model_glob,
    result, matches_plain, model_plain,
});
pub fn resolve(engine: *r.Engine, inputs: Inputs, patterns: c.JSValue, models: c.JSValue) !c.JSValue {
    var frame = Frame.init(engine);
    return frame.finish(source(&frame, inputs, patterns, models));
}
fn source(f: *Frame, inputs: Inputs, patterns: c.JSValue, models: c.JSValue) !c.JSValue {
    const e = f.engine;
    try f.set(.scoped_models, h.array(e));
    try f.set(.diagnostics, h.array(e));
    try f.set(.add, h.expression(e, addFunction, .{f.get(.scoped_models), inputs.equal}));
    try f.set(.no_match, h.expression(e, noMatchFunction, .{f.get(.diagnostics)}));
    try f.set(.ambiguous, h.expression(e, ambiguousFunction, .{f.get(.diagnostics)}));
    var iterator = try v.Iterator.init(e, patterns);
    try iterator.finish(patternsLoop(f, inputs, models, &iterator));
    return h.expression(e, scopeResult, .{f.get(.scoped_models), f.get(.diagnostics)});
}
fn patternsLoop(f: *Frame, inputs: Inputs, models: c.JSValue, iterator: *v.Iterator) !void {
    const e = f.engine;
    while (try iterator.next()) |incoming| {
        try f.set(.pattern, incoming);
        // OP_enter_scope runs after head assignment, in reverse declaration
        // order. Branch/inner-loop scopes reset only when they are entered.
        try f.clear(.matches_plain);
        try f.clear(.result);
        if (try hasGlob(e, f.get(.pattern))) {
            try f.clear(.matches_glob);
            try f.clear(.exact);
            try f.clear(.thinking_level);
            try f.clear(.glob_pattern);
            try f.clear(.thinking);
            try f.set(.thinking, r.splitThinking(e, inputs.reference.thinking, f.get(.pattern)));
            try f.set(.glob_pattern, h.expression(e, globPattern, .{f.get(.thinking), f.get(.pattern)}));
            try f.set(.thinking_level, h.expression(e, optionalThinking, .{f.get(.thinking)}));
            try f.set(.exact, h.expression(e, reference, .{inputs.reference, f.get(.glob_pattern), models, false}));
            try f.set(.matches_glob, h.array(e));
            if (try h.fieldEqual(e, f.get(.exact), "status", "resolved")) {
                try f.set(.matches_glob, h.expression(e, modelArray, .{f.get(.exact)}));
            } else if (try h.fieldEqual(e, f.get(.exact), "status", "ambiguous")) {
                try f.set(.matches_glob, h.get(e, f.get(.exact), "candidates"));
                try callDiscard(e, f.get(.ambiguous), &.{f.get(.pattern), f.get(.matches_glob)});
            } else {
                try f.set(.matches_glob, h.expression(e, globMatches, .{models, f.get(.glob_pattern), inputs.minimatch}));
            }
            if (try r.exactLength(e, f.get(.matches_glob), 0))
                try callDiscard(e, f.get(.no_match), &.{f.get(.pattern)});
            try f.clear(.model_glob);
            var matched = try v.Iterator.init(e, f.get(.matches_glob));
            try matched.finish(globLoop(f, &matched));
            continue;
        }
        try f.set(.result, h.expression(e, reference, .{inputs.reference, f.get(.pattern), models, true}));
        if (try h.fieldEqual(e, f.get(.result), "status", "not-found")) {
            try callDiscard(e, f.get(.no_match), &.{f.get(.pattern)});
            continue;
        }
        if (try h.fieldTest(e, f.get(.result), "warning", .truthy))
            try h.statement(e, invalidWarning, .{f.get(.diagnostics), f.get(.result), f.get(.pattern)});
        if (try h.fieldEqual(e, f.get(.result), "status", "ambiguous"))
            try h.statement(e, warnCandidates, .{f.get(.ambiguous), f.get(.pattern), f.get(.result)});
        try f.set(.matches_plain, if (try h.fieldEqual(e, f.get(.result), "status", "resolved"))
            h.expression(e, modelArray, .{f.get(.result)}) else h.get(e, f.get(.result), "candidates"));
        try f.clear(.model_plain);
        var matched = try v.Iterator.init(e, f.get(.matches_plain));
        try matched.finish(plainLoop(f, &matched));
    }
}
fn hasGlob(engine: *r.Engine, pattern: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, globTest, .{pattern}));
}
fn globTest(s: *Scope, pattern: c.JSValue) !c.JSValue {
    return v.boolean(s, try v.testText(s, pattern, "includes", "*") or
        try v.testText(s, pattern, "includes", "?") or try v.testText(s, pattern, "includes", "["));
}
fn globPattern(s: *Scope, thinking: c.JSValue, pattern: c.JSValue) !c.JSValue {
    const base = if (v.nullish(thinking)) c.pi_js_undefined() else try v.get(s, thinking, "base");
    return v.duplicate(s, if (v.nullish(base)) pattern else base);
}
fn optionalThinking(s: *Scope, thinking: c.JSValue) !c.JSValue {
    return if (v.nullish(thinking)) c.pi_js_undefined() else v.duplicate(s, try v.get(s, thinking, "thinkingLevel"));
}
fn reference(s: *Scope, inputs: r.Inputs, text: c.JSValue, models: c.JSValue, lenient: bool) !c.JSValue {
    const request = try v.object(s);
    try v.put(s, request, "text", text);
    try v.put(s, request, "thinkingSuffix", try v.text(s, if (lenient) "lenient" else "none"));
    try v.put(s, request, "fuzzy", v.boolean(s, lenient));
    const usable = try v.arrow(s, "", 0, alwaysUsable, &.{});
    return r.resolve(s.engine, inputs, request, models, usable);
}
fn alwaysUsable(engine: *r.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, true);
}
fn modelArray(s: *Scope, result: c.JSValue) !c.JSValue {
    const models = try v.array(s);
    try v.index(s, models, 0, try v.get(s, result, "model"));
    return v.duplicate(s, models);
}
fn globMatches(s: *Scope, models: c.JSValue, pattern: c.JSValue, minimatch: c.JSValue) !c.JSValue {
    const filter = try v.get(s, models, "filter");
    const predicate = try v.arrow(s, "", 1, globPredicate, &.{pattern, minimatch});
    return v.duplicate(s, try v.call(s, filter, models, &.{predicate}));
}
fn globPredicate(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, globPredicateBody, .{v.arg(args, 0), roots[0], roots[1]});
}
fn globPredicateBody(s: *Scope, model: c.JSValue, pattern: c.JSValue, minimatch: c.JSValue) !c.JSValue {
    const first = try v.own(s, try h.expression(s.engine, matchLabel, .{model, pattern, minimatch}));
    if (v.truthy(s, first)) return v.duplicate(s, first);
    return h.expression(s.engine, matchId, .{model, pattern, minimatch});
}
fn matchLabel(s: *Scope, model: c.JSValue, pattern: c.JSValue, minimatch: c.JSValue) !c.JSValue {
    const path = try v.own(s, try h.expression(s.engine, r.label, .{model}));
    const options = try v.object(s); try v.put(s, options, "nocase", v.boolean(s, true));
    return v.duplicate(s, try v.call(s, minimatch, c.pi_js_undefined(), &.{path, pattern, options}));
}
fn matchId(s: *Scope, model: c.JSValue, pattern: c.JSValue, minimatch: c.JSValue) !c.JSValue {
    const id = try v.get(s, model, "id");
    const options = try v.object(s); try v.put(s, options, "nocase", v.boolean(s, true));
    return v.duplicate(s, try v.call(s, minimatch, c.pi_js_undefined(), &.{id, pattern, options}));
}
fn globLoop(f: *Frame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.set(.model_glob, incoming);
        try callDiscard(f.engine, f.get(.add), &.{f.get(.model_glob), f.get(.thinking_level)});
    }
}
fn plainLoop(f: *Frame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.set(.model_plain, incoming);
        try h.statement(f.engine, addResult, .{f.get(.add), f.get(.model_plain), f.get(.result)});
    }
}
fn addResult(s: *Scope, add: c.JSValue, model: c.JSValue, result: c.JSValue) !void {
    _ = try v.call(s, add, c.pi_js_undefined(), &.{model, try v.get(s, result, "thinkingLevel")});
}
fn callDiscard(engine: *r.Engine, callable: c.JSValue, args: []const c.JSValue) !void {
    return h.statement(engine, callDiscardBody, .{callable, args});
}
fn callDiscardBody(s: *Scope, callable: c.JSValue, args: []const c.JSValue) !void {
    _ = try v.call(s, callable, c.pi_js_undefined(), args);
}
fn addFunction(s: *Scope, models: c.JSValue, equal: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.arrow(s, "add", 2, addCall, &.{models, equal}));
}
fn addCall(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (!h.truthy(engine, try h.expression(engine, hasModel, .{roots[0], roots[1], v.arg(args, 0)})))
        try h.statement(engine, appendModel, .{roots[0], v.arg(args, 0), v.arg(args, 1)});
    return c.pi_js_undefined();
}
fn hasModel(s: *Scope, models: c.JSValue, equal: c.JSValue, model: c.JSValue) !c.JSValue {
    const some = try v.get(s, models, "some");
    const predicate = try v.arrow(s, "", 1, equalCall, &.{equal, model});
    return v.boolean(s, v.truthy(s, try v.call(s, some, models, &.{predicate})));
}
fn equalCall(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, equalBody, .{v.arg(args, 0), roots[0], roots[1]});
}
fn equalBody(s: *Scope, scoped: c.JSValue, equal: c.JSValue, model: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, equal, c.pi_js_undefined(), &.{try v.get(s, scoped, "model"), model}));
}
fn appendModel(s: *Scope, models: c.JSValue, model: c.JSValue, thinking: c.JSValue) !void {
    const push = try v.get(s, models, "push");
    const row = try v.object(s);
    try v.put(s, row, "model", model); try v.put(s, row, "thinkingLevel", thinking);
    _ = try v.call(s, push, models, &.{row});
}
fn noMatchFunction(s: *Scope, diagnostics: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.arrow(s, "noMatch", 1, noMatchCall, &.{diagnostics}));
}
fn noMatchCall(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, noMatchBody, .{roots[0], v.arg(args, 0)});
}
fn noMatchBody(s: *Scope, diagnostics: c.JSValue, pattern: c.JSValue) !c.JSValue {
    const push = try v.get(s, diagnostics, "push");
    const row = try warningStart(s, "no-match");
    var message = try h.binary(s, .add, try v.text(s, "No models match pattern \""), try v.stringify(s, pattern));
    message = try h.binary(s, .add, message, try v.text(s, "\""));
    try v.put(s, row, "message", message); try v.put(s, row, "pattern", pattern);
    return v.duplicate(s, try v.call(s, push, diagnostics, &.{row}));
}
fn warningStart(s: *Scope, code: []const u8) !c.JSValue {
    const row = try v.object(s);
    try v.put(s, row, "type", try v.text(s, "warning"));
    try v.put(s, row, "code", try v.text(s, code));
    return row;
}
fn ambiguousFunction(s: *Scope, diagnostics: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.arrow(s, "ambiguous", 2, ambiguousCall, &.{diagnostics}));
}
const AmbiguousFrame = h.Frame(enum { providers });
fn ambiguousCall(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var f = AmbiguousFrame.init(engine);
    return f.finish(ambiguousBody(&f, roots[0], v.arg(args, 0), v.arg(args, 1)));
}
fn ambiguousBody(f: *AmbiguousFrame, diagnostics: c.JSValue, pattern: c.JSValue, candidates: c.JSValue) !c.JSValue {
    try f.set(.providers, h.expression(f.engine, providerNames, .{candidates}));
    try h.statement(f.engine, ambiguousWarning, .{diagnostics, pattern, f.get(.providers)});
    return c.pi_js_undefined();
}
fn providerNames(s: *Scope, candidates: c.JSValue) !c.JSValue {
    const result = try v.array(s); var position: u32 = 0;
    try r.appendIterable(s.engine, result, h.expression(s.engine, providerSet, .{candidates}), &position);
    return r.collection(s.engine, result, "sort", .ascending, &.{});
}
fn providerSet(s: *Scope, candidates: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Set");
    const providers = try v.own(s, try r.collection(s.engine, candidates, "map", .provider_value, &.{}));
    return v.duplicate(s, try v.construct(s, constructor, &.{providers}));
}
fn ambiguousWarning(s: *Scope, diagnostics: c.JSValue, pattern: c.JSValue, providers: c.JSValue) !void {
    const push = try v.get(s, diagnostics, "push");
    const row = try warningStart(s, "ambiguous");
    var message = try h.binary(s, .add, try v.text(s, "Pattern \""), try v.stringify(s, pattern));
    message = try h.binary(s, .add, message, try v.text(s, "\" matches several providers: "));
    message = try h.binary(s, .add, message, try v.own(s, try h.expression(s.engine, joinedString, .{v.invokeTextOwned(s.engine, providers, "join", ", ")})));
    message = try h.binary(s, .add, message, try v.text(s, ". Use provider/id to choose one."));
    try v.put(s, row, "message", message); try v.put(s, row, "pattern", pattern);
    _ = try v.call(s, push, diagnostics, &.{row});
}
fn joinedString(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.own(s, try incoming)));
}
fn invalidWarning(s: *Scope, diagnostics: c.JSValue, result: c.JSValue, pattern: c.JSValue) !void {
    const push = try v.get(s, diagnostics, "push");
    const row = try warningStart(s, "invalid-thinking-level");
    try r.fieldInto(s.engine, row, "message", result, "warning");
    try v.put(s, row, "pattern", pattern);
    _ = try v.call(s, push, diagnostics, &.{row});
}
fn warnCandidates(s: *Scope, ambiguous: c.JSValue, pattern: c.JSValue, result: c.JSValue) !void {
    _ = try v.call(s, ambiguous, c.pi_js_undefined(), &.{pattern, try v.get(s, result, "candidates")});
}
fn scopeResult(s: *Scope, models: c.JSValue, diagnostics: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "scopedModels", models); try v.put(s, result, "diagnostics", diagnostics);
    return v.duplicate(s, result);
}

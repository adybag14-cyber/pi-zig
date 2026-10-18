//! Actual c268 model reference resolution over live guest values.
//! Every method call is a Source operation; native frames retain lexical values
//! separately from expression temporaries. Recursive suffix calls use owned
//! activation storage rather than the native C stack.
const std = @import("std");
const h = @import("native_sdk_session_locals.zig");
pub const v = h.v;
pub const c = v.c;
pub const Engine = v.em.Engine;
pub const Scope = v.Scope;
const copy = @import("native_sdk_catalog_copy.zig");
const x = @import("native_sdk_catalog_values.zig");
pub const Inputs = struct { thinking: c.JSValue, defaults: c.JSValue };

pub const Callback = enum {
    provider_lower, id_lower, provider_split, provider_split_optional, provider_anchor, other_named,
    usable_provider, fuzzy, provider_value, same_best_id, alias,
    descending_id, default_id, provider_cli, model_label, ascending,
};
fn callback(s: *Scope, comptime kind: Callback, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
            return h.expression(engine, callbackBody, .{ kind, args, captures });
        }
    };
    return v.arrow(s, "", if (kind == .descending_id or kind == .ascending) 2 else 1, Adapter.call, roots);
}
pub fn collection(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, comptime kind: Callback, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, collectionBody, .{ receiver, name, kind, roots });
}
fn collectionBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, comptime kind: Callback, roots: []const c.JSValue) !c.JSValue {
    const callable = try v.get(s, receiver, name);
    return v.duplicate(s, try v.call(s, callable, receiver, &.{try callback(s, kind, roots)}));
}
pub fn invokeIncoming(engine: *Engine, incoming: anyerror!c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return h.expression(engine, invokeIncomingBody, .{ incoming, name, args });
}
fn invokeIncomingBody(s: *Scope, incoming: anyerror!c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.invoke(s, try v.own(s, try incoming), name, args));
}
fn lowerField(engine: *Engine, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return invokeIncoming(engine, h.get(engine, target, name), "toLowerCase", &.{});
}
fn callbackBody(s: *Scope, comptime kind: Callback, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const model = v.arg(args, 0);
    return switch (kind) {
        .provider_lower => v.boolean(s, v.equal(s, try v.own(s, try lowerField(s.engine, model, "provider")), roots[0])),
        .id_lower => v.boolean(s, v.equal(s, try v.own(s, try lowerField(s.engine, model, "id")), roots[0])),
        .provider_split => v.boolean(s, v.equal(s, try v.get(s, model, "provider"), try v.get(s, roots[0], "provider"))),
        .provider_split_optional => v.boolean(s, v.equal(s, try v.get(s, model, "provider"), if (v.nullish(roots[0])) c.pi_js_undefined() else try v.get(s, roots[0], "provider"))),
        .provider_anchor => anchorPredicate(s, model, roots[0]),
        .other_named => v.boolean(s, !v.equal(s, model, roots[0])),
        .usable_provider => v.duplicate(s, try v.call(s, roots[0], c.pi_js_undefined(), &.{try v.get(s, model, "provider")})),
        .fuzzy => fuzzyPredicate(s, model, roots[0]),
        .provider_value => v.duplicate(s, try v.get(s, model, "provider")),
        .same_best_id => v.boolean(s, v.equal(s, try v.get(s, model, "id"), try v.get(s, roots[0], "id"))),
        .alias => aliasFromField(s, model),
        .descending_id => descendingId(s, model, v.arg(args, 1)),
        .default_id => v.boolean(s, v.equal(s, try v.get(s, model, "id"), roots[0])),
        .provider_cli => v.boolean(s, v.equal(s, try v.own(s, try lowerField(s.engine, model, "provider")), try v.own(s, try v.invokeOwned(s.engine, roots[0], "toLowerCase", &.{})))),
        .model_label => label(s, model),
        .ascending => v.duplicate(s, try v.invoke(s, model, "localeCompare", &.{v.arg(args, 1)})),
    };
}
fn anchorPredicate(s: *Scope, model: c.JSValue, anchor: c.JSValue) !c.JSValue {
    // Each strict comparison retires before the && right expression.
    const matches = try h.expression(s.engine, sameField, .{ model, anchor, @as([*:0]const u8, "provider") });
    return v.boolean(s, h.truthy(s.engine, matches) and !v.equal(s, model, anchor));
}
fn sameField(s: *Scope, left: c.JSValue, right: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, left, name), try v.get(s, right, name)));
}
fn fuzzyPredicate(s: *Scope, model: c.JSValue, lower: c.JSValue) !c.JSValue {
    const first = try v.own(s, try fuzzyFirst(s.engine, model, lower));
    if (v.truthy(s, first)) return v.duplicate(s, first);
    // The falsy first result is consumed by || before reading name.
    return fuzzyName(s.engine, model, lower);
}
fn fuzzyFirst(engine: *Engine, model: c.JSValue, lower: c.JSValue) !c.JSValue {
    return invokeIncoming(engine, lowerField(engine, model, "id"), "includes", &.{lower});
}
fn fuzzyName(engine: *Engine, model: c.JSValue, lower: c.JSValue) !c.JSValue {
    var optional = false;
    const lowered = try h.expression(engine, lowerOptionalName, .{ model, &optional });
    if (optional) return lowered;
    return invokeIncoming(engine, lowered, "includes", &.{lower});
}
fn lowerOptionalName(s: *Scope, model: c.JSValue, optional: *bool) !c.JSValue {
    const name = try v.get(s, model, "name");
    if (v.nullish(name)) { optional.* = true; return c.pi_js_undefined(); }
    return v.duplicate(s, try v.invoke(s, name, "toLowerCase", &.{}));
}
fn aliasFromField(s: *Scope, model: c.JSValue) !c.JSValue {
    return isAlias(s.engine, try v.get(s, model, "id"));
}
fn descendingId(s: *Scope, a: c.JSValue, b: c.JSValue) !c.JSValue {
    const receiver = try v.get(s, b, "id");
    const callable = try v.get(s, receiver, "localeCompare");
    return v.duplicate(s, try v.call(s, callable, receiver, &.{try v.get(s, a, "id")}));
}
pub fn fieldString(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return h.expression(engine, fieldStringBody, .{ object, name });
}
fn fieldStringBody(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, object, name)));
}
pub fn label(s: *Scope, model: c.JSValue) !c.JSValue {
    const provider = try v.own(s, try fieldString(s.engine, model, "provider"));
    const first = try h.binary(s, .add, provider, try v.text(s, "/"));
    return v.duplicate(s, try h.binary(s, .add, first, try v.own(s, try fieldString(s.engine, model, "id"))));
}
pub fn hasLength(engine: *Engine, target: c.JSValue, comptime operation: h.math.Operation, expected: f64) !bool {
    return h.truthy(engine, try h.expression(engine, lengthBody, .{ target, operation, expected }));
}
fn lengthBody(s: *Scope, target: c.JSValue, comptime operation: h.math.Operation, expected: f64) !c.JSValue {
    return v.boolean(s, v.truthy(s, try h.binary(s, operation, try v.get(s, target, "length"), v.number(s, expected))));
}
pub fn exactLength(engine: *Engine, target: c.JSValue, expected: f64) !bool {
    return h.truthy(engine, try h.expression(engine, exactLengthBody, .{ target, expected }));
}
fn exactLengthBody(s: *Scope, target: c.JSValue, expected: f64) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, target, "length"), v.number(s, expected)));
}
pub fn atOwned(engine: *Engine, target: c.JSValue, position: u32) !c.JSValue {
    return h.expression(engine, atBody, .{ target, position });
}
fn atBody(s: *Scope, target: c.JSValue, position: u32) !c.JSValue { return v.duplicate(s, try v.at(s, target, position)); }
pub fn fieldInto(engine: *Engine, target: c.JSValue, name: [*:0]const u8, source: c.JSValue, field: [*:0]const u8) !void {
    return h.statement(engine, fieldIntoBody, .{ target, name, source, field });
}
fn fieldIntoBody(s: *Scope, target: c.JSValue, name: [*:0]const u8, source: c.JSValue, field: [*:0]const u8) !void {
    return v.put(s, target, name, try v.get(s, source, field));
}
fn fieldOptional(engine: *Engine, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (v.nullish(target)) c.pi_js_undefined() else h.get(engine, target, name);
}
pub fn copied(s: *Scope, source: c.JSValue) !c.JSValue { var ops: x.Ops = .{ .s = s }; return copy.object(&ops, source); }
fn notFound(engine: *Engine) !c.JSValue { return h.expression(engine, notFoundBody, .{}); }
fn notFoundBody(s: *Scope) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "status", try v.text(s, "not-found")); return v.duplicate(s, result);
}
fn resolved(engine: *Engine, model: c.JSValue) !c.JSValue { return h.expression(engine, resolvedBody, .{model}); }
fn resolvedBody(s: *Scope, model: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "status", try v.text(s, "resolved")); try v.put(s, result, "model", model); return v.duplicate(s, result);
}
fn resolvedFirst(engine: *Engine, models: c.JSValue) !c.JSValue { return h.expression(engine, resolvedFirstBody, .{models}); }
fn resolvedFirstBody(s: *Scope, models: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "status", try v.text(s, "resolved")); try v.put(s, result, "model", try v.at(s, models, 0)); return v.duplicate(s, result);
}
pub fn appendIterable(engine: *Engine, target: c.JSValue, incoming: anyerror!c.JSValue, start: *u32) !void {
    var iterator = try v.Iterator.initOwned(engine, try incoming);
    return iterator.finish(appendIterator(&iterator, target, start));
}
fn appendIterator(iterator: *v.Iterator, target: c.JSValue, position: *u32) !void {
    while (try iterator.next()) |value| {
        try h.statement(iterator.engine, appendOne, .{ target, position.*, value });
        if (position.* == std.math.maxInt(u32)) return error.OutOfMemory;
        position.* += 1;
    }
}
fn appendOne(s: *Scope, target: c.JSValue, position: u32, incoming: c.JSValue) !void { return v.index(s, target, position, try v.own(s, incoming)); }
pub fn snapshot(engine: *Engine, iterable: c.JSValue) !c.JSValue { return h.expression(engine, snapshotBody, .{iterable}); }
fn snapshotBody(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const result = try v.array(s); var position: u32 = 0;
    try appendIterable(s.engine, result, v.duplicate(s, iterable), &position);
    return v.duplicate(s, result);
}
fn prefixed(engine: *Engine, first: c.JSValue, remaining: c.JSValue) !c.JSValue { return h.expression(engine, prefixedBody, .{ first, remaining }); }
fn prefixedBody(s: *Scope, first: c.JSValue, remaining: c.JSValue) !c.JSValue {
    const result = try v.array(s); try v.index(s, result, 0, first); var position: u32 = 1;
    try appendIterable(s.engine, result, v.duplicate(s, remaining), &position); return v.duplicate(s, result);
}
const Thinking = h.Frame(enum { colon, suffix });
pub fn splitThinking(engine: *Engine, thinking: c.JSValue, text: c.JSValue) !c.JSValue {
    var frame = Thinking.init(engine); return frame.finish(splitThinkingBody(&frame, thinking, text));
}
fn splitThinkingBody(f: *Thinking, thinking: c.JSValue, text: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.colon, v.invokeTextOwned(engine, text, "lastIndexOf", ":"));
    try f.set(.suffix, h.expression(engine, suffixAfter, .{ text, f.get(.colon) }));
    if (c.JS_IsStrictEqual(engine.context, f.get(.colon), h.number(engine, -1)) or !try truthyCall(engine, thinking, &.{f.get(.suffix)})) return c.pi_js_undefined();
    return h.expression(engine, thinkingResult, .{ text, f.get(.colon), f.get(.suffix) });
}
fn suffixAfter(s: *Scope, text: c.JSValue, colon: c.JSValue) !c.JSValue {
    const callable = try v.get(s, text, "substring");
    return v.duplicate(s, try v.call(s, callable, text, &.{try h.binary(s, .add, colon, v.number(s, 1))}));
}
fn thinkingResult(s: *Scope, text: c.JSValue, colon: c.JSValue, suffix: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try h.statement(s.engine, substringInto, .{ result, text, colon });
    try v.put(s, result, "thinkingLevel", suffix); return v.duplicate(s, result);
}
fn substringInto(s: *Scope, result: c.JSValue, text: c.JSValue, colon: c.JSValue) !void {
    return v.put(s, result, "base", try v.invoke(s, text, "substring", &.{ v.number(s, 0), colon }));
}
pub fn truthyCall(engine: *Engine, callable: c.JSValue, args: []const c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, truthyCallBody, .{ callable, args }));
}
fn truthyCallBody(s: *Scope, callable: c.JSValue, args: []const c.JSValue) !c.JSValue { return v.boolean(s, v.truthy(s, try v.call(s, callable, c.pi_js_undefined(), args))); }
const Prefix = h.Frame(enum { slash, prefix, model_text, provider });
fn splitProvider(engine: *Engine, text: c.JSValue, models: c.JSValue) !c.JSValue {
    var f = Prefix.init(engine); return f.finish(splitProviderBody(&f, text, models));
}
fn splitProviderBody(f: *Prefix, text: c.JSValue, models: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.slash, v.invokeTextOwned(engine, text, "indexOf", "/"));
    if (c.JS_IsStrictEqual(engine.context, f.get(.slash), h.number(engine, -1))) return c.pi_js_undefined();
    try f.set(.prefix, invokeIncoming(engine, invokeIncoming(engine, v.invokeOwned(engine, text, "substring", &.{ h.number(engine, 0), f.get(.slash) }), "trim", &.{}), "toLowerCase", &.{}));
    try f.set(.model_text, invokeIncoming(engine, h.expression(engine, suffixAfter, .{ text, f.get(.slash) }), "trim", &.{}));
    if (!h.truthy(engine, f.get(.prefix)) or !h.truthy(engine, f.get(.model_text))) return c.pi_js_undefined();
    try f.set(.provider, h.expression(engine, prefixProvider, .{ models, f.get(.prefix) }));
    if (!h.truthy(engine, f.get(.provider))) return c.pi_js_undefined();
    return h.expression(engine, prefixResult, .{ f.get(.provider), f.get(.model_text) });
}
fn prefixProvider(s: *Scope, models: c.JSValue, prefix: c.JSValue) !c.JSValue {
    const found = try v.own(s, try collection(s.engine, models, "find", .provider_lower, &.{prefix}));
    return if (v.nullish(found)) c.pi_js_undefined() else v.duplicate(s, try v.get(s, found, "provider"));
}
fn prefixResult(s: *Scope, provider: c.JSValue, model_text: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "provider", provider); try v.put(s, result, "modelText", model_text); return v.duplicate(s, result);
}

const Reference = h.Frame(enum { text, constraint, pool, result, split, anchor, model_text, suffix });
pub fn resolve(engine: *Engine, inputs: Inputs, request: c.JSValue, models: c.JSValue, usable: c.JSValue) anyerror!c.JSValue {
    var f = Reference.init(engine); return f.finish(resolveBody(&f, inputs, request, models, usable));
}
fn resolveBody(f: *Reference, inputs: Inputs, request: c.JSValue, models: c.JSValue, usable: c.JSValue) !c.JSValue {
    const e = f.engine;
    try f.set(.text, invokeIncoming(e, h.get(e, request, "text"), "trim", &.{}));
    if (!h.truthy(e, f.get(.text))) return notFound(e);
    try f.set(.constraint, h.expression(e, constraintBody, .{request}));
    try f.set(.pool, if (h.truthy(e, f.get(.constraint))) collection(e, models, "filter", .provider_lower, &.{f.get(.constraint)}) else h.duplicate(e, models));
    try f.set(.result, resolveText(e, inputs, f.get(.text), request, f.get(.pool), usable));
    if (!try h.fieldEqual(e, f.get(.result), "status", "not-found")) return h.duplicate(e, f.get(.result));
    try f.set(.split, splitProvider(e, f.get(.text), f.get(.pool)));
    try f.set(.anchor, if (h.truthy(e, f.get(.constraint))) atOwned(e, f.get(.pool), 0) else collection(e, f.get(.pool), "find", .provider_split_optional, &.{f.get(.split)}));
    if (!h.truthy(e, f.get(.anchor))) return h.duplicate(e, f.get(.result));
    try f.set(.model_text, h.expression(e, modelTextBody, .{ f.get(.split), f.get(.text) }));
    try f.set(.suffix, if (try h.fieldEqual(e, request, "thinkingSuffix", "none")) c.pi_js_undefined() else splitThinking(e, inputs.thinking, f.get(.model_text)));
    return h.expression(e, targetResult, .{ f.get(.anchor), f.get(.pool), f.get(.model_text), f.get(.suffix) });
}
fn constraintBody(s: *Scope, request: c.JSValue) !c.JSValue {
    const provider = try v.get(s, request, "provider");
    return if (v.nullish(provider)) c.pi_js_undefined() else v.duplicate(s, try v.invoke(s, provider, "toLowerCase", &.{}));
}
fn modelTextBody(s: *Scope, split: c.JSValue, text: c.JSValue) !c.JSValue {
    const value = try v.own(s, try fieldOptional(s.engine, split, "modelText"));
    return v.duplicate(s, if (v.nullish(value)) text else value);
}
fn targetResult(s: *Scope, anchor: c.JSValue, pool: c.JSValue, model_text: c.JSValue, suffix: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "status", try v.text(s, "not-found"));
    const target = try v.object(s); try fieldInto(s.engine, target, "provider", anchor, "provider");
    try h.statement(s.engine, targetModels, .{ target, anchor, pool });
    try v.put(s, target, "modelText", model_text);
    try h.statement(s.engine, targetModelId, .{ target, suffix, model_text });
    try h.statement(s.engine, targetThinking, .{ target, suffix });
    try v.put(s, result, "target", target); return v.duplicate(s, result);
}
fn targetModels(s: *Scope, target: c.JSValue, anchor: c.JSValue, pool: c.JSValue) !void {
    const models = try v.array(s); try v.index(s, models, 0, anchor);
    var position: u32 = 1;
    try appendIterable(s.engine, models, collection(s.engine, pool, "filter", .provider_anchor, &.{anchor}), &position);
    try v.put(s, target, "providerModels", models);
}
fn targetModelId(s: *Scope, target: c.JSValue, suffix: c.JSValue, model_text: c.JSValue) !void {
    const base = try v.own(s, try fieldOptional(s.engine, suffix, "base"));
    try v.put(s, target, "modelId", if (v.nullish(base)) model_text else base);
}
fn targetThinking(s: *Scope, target: c.JSValue, suffix: c.JSValue) !void {
    try v.put(s, target, "thinkingLevel", try v.own(s, try fieldOptional(s.engine, suffix, "thinkingLevel")));
}

const Select = h.Frame(enum { lower_text, raw, split, named, provider_models, lower_model_text, others, candidates, usable_others });
fn selectReference(engine: *Engine, text: c.JSValue, pool: c.JSValue, fuzzy: c.JSValue, usable: c.JSValue) !c.JSValue {
    var f = Select.init(engine); return f.finish(selectReferenceBody(&f, text, pool, fuzzy, usable));
}
fn selectReferenceBody(f: *Select, text: c.JSValue, pool: c.JSValue, fuzzy: c.JSValue, usable: c.JSValue) !c.JSValue {
    const e = f.engine;
    try f.set(.lower_text, v.invokeOwned(e, text, "toLowerCase", &.{}));
    try f.set(.raw, collection(e, pool, "filter", .id_lower, &.{f.get(.lower_text)}));
    try f.set(.split, splitProvider(e, text, pool));
    if (h.truthy(e, f.get(.split))) {
        try f.set(.provider_models, collection(e, pool, "filter", .provider_split, &.{f.get(.split)}));
        try f.set(.lower_model_text, lowerField(e, f.get(.split), "modelText"));
        try f.set(.named, h.expression(e, namedBody, .{ f, fuzzy }));
    }
    try f.set(.others, collection(e, f.get(.raw), "filter", .other_named, &.{f.get(.named)}));
    try f.set(.candidates, if (h.truthy(e, f.get(.named))) prefixed(e, f.get(.named), f.get(.others)) else h.duplicate(e, f.get(.others)));
    if (try exactLength(e, f.get(.candidates), 0)) return c.pi_js_undefined();
    if (try providerCount(e, f.get(.candidates), .equal, 1)) return resolvedFirst(e, f.get(.candidates));
    if (h.truthy(e, f.get(.named)) and try usableField(e, usable, f.get(.named))) return resolved(e, f.get(.named));
    try f.set(.usable_others, collection(e, f.get(.others), "filter", .usable_provider, &.{usable}));
    if (try exactLength(e, f.get(.usable_others), 1)) return resolvedFirst(e, f.get(.usable_others));
    if (try exactLength(e, f.get(.usable_others), 0) and h.truthy(e, f.get(.named))) return resolved(e, f.get(.named));
    return h.expression(e, ambiguousOthers, .{ f.get(.candidates), f.get(.usable_others) });
}
fn namedBody(s: *Scope, f: *Select, fuzzy: c.JSValue) !c.JSValue {
    const literal = try v.own(s, try collection(s.engine, f.get(.provider_models), "find", .id_lower, &.{f.get(.lower_model_text)}));
    if (!v.nullish(literal)) return v.duplicate(s, literal);
    const raw = try v.own(s, try collection(s.engine, f.get(.raw), "find", .provider_split, &.{f.get(.split)}));
    if (!v.nullish(raw)) return v.duplicate(s, raw);
    if (!v.truthy(s, fuzzy)) return c.pi_js_undefined();
    return h.expression(s.engine, fuzzyNamed, .{ f.get(.split), f.get(.provider_models) });
}
fn fuzzyNamed(s: *Scope, split: c.JSValue, models: c.JSValue) !c.JSValue {
    return bestFuzzy(s.engine, try v.own(s, try h.expression(s.engine, fuzzyMatchesFromSplit, .{ split, models })));
}
fn fuzzyMatchesFromSplit(s: *Scope, split: c.JSValue, models: c.JSValue) !c.JSValue {
    return fuzzyMatches(s.engine, try v.get(s, split, "modelText"), models);
}
fn usableField(engine: *Engine, usable: c.JSValue, model: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, usableFieldBody, .{ usable, model }));
}
fn usableFieldBody(s: *Scope, usable: c.JSValue, model: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try v.call(s, usable, c.pi_js_undefined(), &.{try v.get(s, model, "provider")})));
}
fn ambiguousOthers(s: *Scope, candidates: c.JSValue, others: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "status", try v.text(s, "ambiguous"));
    try v.put(s, result, "candidates", candidates); try fieldInto(s.engine, result, "usableCount", others, "length"); return v.duplicate(s, result);
}
const Count = enum { equal, greater };
fn providerCount(engine: *Engine, models: c.JSValue, comptime kind: Count, expected: f64) !bool {
    return h.truthy(engine, try h.expression(engine, providerCountBody, .{ h.expression(engine, providerSize, .{providerSet(engine, models)}), kind, expected }));
}
fn providerSet(engine: *Engine, models: c.JSValue) !c.JSValue { return h.expression(engine, providerSetBody, .{models}); }
fn providerSetBody(s: *Scope, models: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Set");
    const mapped = try v.own(s, try collection(s.engine, models, "map", .provider_value, &.{}));
    return v.duplicate(s, try v.construct(s, constructor, &.{mapped}));
}
fn providerSize(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.own(s, try incoming), "size"));
}
fn providerCountBody(s: *Scope, incoming: anyerror!c.JSValue, comptime kind: Count, expected: f64) !c.JSValue {
    const count = try v.own(s, try incoming);
    return v.boolean(s, if (kind == .equal) v.equal(s, count, v.number(s, expected)) else v.truthy(s, try h.binary(s, .greater, count, v.number(s, expected))));
}
const Fuzzy = h.Frame(enum { lower_text });
fn fuzzyMatches(engine: *Engine, text: c.JSValue, models: c.JSValue) !c.JSValue {
    var f = Fuzzy.init(engine);
    return f.finish(fuzzyMatchesBody(&f, text, models));
}
fn fuzzyMatchesBody(f: *Fuzzy, text: c.JSValue, models: c.JSValue) !c.JSValue {
    try f.set(.lower_text, v.invokeOwned(f.engine, text, "toLowerCase", &.{}));
    return collection(f.engine, models, "filter", .fuzzy, &.{f.get(.lower_text)});
}
const FuzzySelect = h.Frame(enum { multiple_providers, usable_matches, pool, best, tied });
fn selectFuzzy(engine: *Engine, matches: c.JSValue, usable: c.JSValue) !c.JSValue {
    var f = FuzzySelect.init(engine); return f.finish(selectFuzzyBody(&f, matches, usable));
}
fn selectFuzzyBody(f: *FuzzySelect, matches: c.JSValue, usable: c.JSValue) !c.JSValue {
    const e = f.engine;
    if (try exactLength(e, matches, 0)) return c.pi_js_undefined();
    try f.set(.multiple_providers, c.pi_js_bool(e.context, @intFromBool(try providerCount(e, matches, .greater, 1))));
    try f.set(.usable_matches, if (h.truthy(e, f.get(.multiple_providers))) collection(e, matches, "filter", .usable_provider, &.{usable}) else h.array(e));
    try f.set(.pool, h.duplicate(e, if (try hasLength(e, f.get(.usable_matches), .greater, 0)) f.get(.usable_matches) else matches));
    try f.set(.best, bestFuzzy(e, f.get(.pool)));
    if (!h.truthy(e, f.get(.best))) return c.pi_js_undefined();
    try f.set(.tied, collection(e, f.get(.pool), "filter", .same_best_id, &.{f.get(.best)}));
    if (try providerCount(e, f.get(.tied), .equal, 1)) return resolved(e, f.get(.best));
    return h.expression(e, ambiguousFuzzy, .{ f.get(.tied), f.get(.usable_matches) });
}
fn ambiguousFuzzy(s: *Scope, tied: c.JSValue, usable_matches: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "status", try v.text(s, "ambiguous")); try v.put(s, result, "candidates", tied);
    if (try hasLength(s.engine, usable_matches, .greater, 0)) try fieldInto(s.engine, result, "usableCount", tied, "length")
    else try v.put(s, result, "usableCount", v.number(s, 0));
    return v.duplicate(s, result);
}
const Best = h.Frame(enum { aliases });
fn bestFuzzy(engine: *Engine, matches: c.JSValue) !c.JSValue {
    var f = Best.init(engine); return f.finish(bestFuzzyBody(&f, matches));
}
fn bestFuzzyBody(f: *Best, matches: c.JSValue) !c.JSValue {
    try f.set(.aliases, collection(f.engine, matches, "filter", .alias, &.{}));
    return h.expression(f.engine, sortedFirst, .{ sortedSnapshot(f.engine, f.get(.aliases), matches) });
}
fn sortedSnapshot(engine: *Engine, aliases: c.JSValue, matches: c.JSValue) !c.JSValue {
    return h.expression(engine, sortedSnapshotBody, .{ aliases, matches });
}
fn sortedSnapshotBody(s: *Scope, aliases: c.JSValue, matches: c.JSValue) !c.JSValue {
    const array = try v.array(s); var position: u32 = 0;
    try appendIterable(s.engine, array, v.duplicate(s, if (try hasLength(s.engine, aliases, .greater, 0)) aliases else matches), &position);
    return collection(s.engine, array, "sort", .descending_id, &.{});
}
fn sortedFirst(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue { return v.duplicate(s, try v.at(s, try v.own(s, try incoming), 0)); }
fn isAlias(engine: *Engine, id: c.JSValue) !c.JSValue { return h.expression(engine, aliasBody, .{id}); }
fn aliasBody(s: *Scope, id: c.JSValue) !c.JSValue {
    const latest = try v.own(s, try v.invokeTextOwned(s.engine, id, "endsWith", "-latest"));
    if (v.truthy(s, latest)) return v.duplicate(s, latest);
    return h.expression(s.engine, datedAlias, .{id});
}
fn datedAlias(s: *Scope, id: c.JSValue) !c.JSValue {
    const regex = try v.construct(s, s.engine.intrinsic_regexp_constructor, &.{ try v.text(s, "-\\d{8}$"), try v.text(s, "") });
    return v.boolean(s, !v.truthy(s, try v.invoke(s, regex, "test", &.{id})));
}

const Fallback = h.Frame(enum { default_id, base_model });
pub fn fallback(engine: *Engine, defaults: c.JSValue, models: c.JSValue, model_id: c.JSValue) !c.JSValue {
    var f = Fallback.init(engine); return f.finish(fallbackBody(&f, defaults, models, model_id));
}
fn fallbackBody(f: *Fallback, defaults: c.JSValue, models: c.JSValue, model_id: c.JSValue) !c.JSValue {
    const e = f.engine;
    try f.set(.default_id, h.expression(e, defaultIdBody, .{ defaults, models }));
    try f.set(.base_model, if (h.truthy(e, f.get(.default_id))) h.expression(e, defaultBase, .{ models, f.get(.default_id) }) else atOwned(e, models, 0));
    return h.expression(e, fallbackResult, .{ f.get(.base_model), model_id });
}
fn defaultIdBody(s: *Scope, defaults: c.JSValue, models: c.JSValue) !c.JSValue {
    var atom: c.JSAtom = c.JS_ATOM_NULL;
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try h.statement(s.engine, defaultKey, .{ models, &atom });
    return v.duplicate(s, try v.guest.getAtom(s, defaults, atom));
}
fn defaultKey(s: *Scope, models: c.JSValue, atom: *c.JSAtom) !void {
    const property = try v.own(s, try h.expression(s.engine, firstProvider, .{models}));
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    atom.* = c.JS_ValueToAtom(s.engine.context, property);
    return boundary.finishStatus(if (atom.* == c.JS_ATOM_NULL) -1 else 0);
}
fn firstProvider(s: *Scope, models: c.JSValue) !c.JSValue { return v.duplicate(s, try v.get(s, try v.at(s, models, 0), "provider")); }
fn defaultBase(s: *Scope, models: c.JSValue, default_id: c.JSValue) !c.JSValue {
    const candidate = try v.own(s, try collection(s.engine, models, "find", .default_id, &.{default_id}));
    return if (v.nullish(candidate)) atOwned(s.engine, models, 0) else v.duplicate(s, candidate);
}
fn fallbackResult(s: *Scope, base: c.JSValue, model_id: c.JSValue) !c.JSValue {
    const result = try copied(s, base); try v.put(s, result, "id", model_id); try v.put(s, result, "name", model_id); return v.duplicate(s, result);
}

const TextLocals = h.Frame(enum { reference, fuzzy, thinking, inner_valid, colon, suffix, inner_invalid });
const Phase = enum { enter, valid, invalid };
const Activation = struct { text: c.JSValue, locals: TextLocals, phase: Phase = .enter };
const Step = union(enum) { complete: c.JSValue, child: c.JSValue };
fn resolveText(engine: *Engine, inputs: Inputs, text: c.JSValue, request: c.JSValue, pool: c.JSValue, usable: c.JSValue) !c.JSValue {
    var activations: std.ArrayList(Activation) = .empty;
    defer activations.deinit(engine.gpa);
    const result = resolveTextFrames(engine, &activations, inputs, text, request, pool, usable);
    var completion = v.owned.Completion.initValue(engine, result);
    // An abrupt child unwinds before its suspended callers. These are actual
    // retained Source local slots, not a result-only recursion shortcut.
    while (activations.pop()) |activation| {
        for (activation.locals.values) |value| completion.release(value);
        completion.release(activation.text);
    }
    return completion.finishValue();
}
fn pushActivation(engine: *Engine, activations: *std.ArrayList(Activation), incoming: c.JSValue) !void {
    activations.append(engine.gpa, .{ .text = incoming, .locals = TextLocals.init(engine) }) catch |err| {
        var failed = v.owned.Completion.initVoid(engine, err); failed.release(incoming); return failed.finishVoid();
    };
}
fn resolveTextFrames(engine: *Engine, activations: *std.ArrayList(Activation), inputs: Inputs, text: c.JSValue, request: c.JSValue, pool: c.JSValue, usable: c.JSValue) !c.JSValue {
    try pushActivation(engine, activations, h.duplicate(engine, text));
    var steps: usize = 0;
    while (true) {
        const top = &activations.items[activations.items.len - 1];
        const step: Step = switch (top.phase) {
            .enter => block: {
                try v.poll(engine, &steps);
                break :block try scanText(top, inputs, request, pool, usable);
            },
            .valid, .invalid => .{ .complete = try finishText(top) },
        };
        switch (step) {
            .child => |child| try pushActivation(engine, activations, child),
            .complete => |result| {
                const finished = activations.pop().?;
                var completion = v.owned.Completion.initValue(engine, result);
                for (finished.locals.values) |value| completion.release(value);
                completion.release(finished.text);
                const returned = try completion.finishValue();
                if (activations.items.len == 0) return returned;
                const parent = &activations.items[activations.items.len - 1];
                if (parent.phase == .valid) try parent.locals.set(.inner_valid, returned)
                else try parent.locals.set(.inner_invalid, returned);
            },
        }
    }
}
fn scanText(activation: *Activation, inputs: Inputs, request: c.JSValue, pool: c.JSValue, usable: c.JSValue) !Step {
    const f = &activation.locals; const e = f.engine; const text = activation.text;
    try f.set(.reference, h.expression(e, selectRequested, .{ text, pool, request, usable }));
    if (h.truthy(e, f.get(.reference))) return .{ .complete = h.duplicate(e, f.get(.reference)) };
    if (try h.fieldTest(e, request, "fuzzy", .truthy)) {
        try f.set(.fuzzy, h.expression(e, selectTextFuzzy, .{ text, pool, usable }));
        if (h.truthy(e, f.get(.fuzzy))) return .{ .complete = h.duplicate(e, f.get(.fuzzy)) };
    }
    if (try h.fieldEqual(e, request, "thinkingSuffix", "none")) return .{ .complete = try notFound(e) };
    try f.set(.thinking, splitThinking(e, inputs.thinking, text));
    if (h.truthy(e, f.get(.thinking))) {
        activation.phase = .valid;
        return .{ .child = try h.get(e, f.get(.thinking), "base") };
    }
    if (try h.fieldEqual(e, request, "thinkingSuffix", "strict")) return .{ .complete = try notFound(e) };
    try f.set(.colon, v.invokeTextOwned(e, text, "lastIndexOf", ":"));
    if (c.JS_IsStrictEqual(e.context, f.get(.colon), h.number(e, -1))) return .{ .complete = try notFound(e) };
    try f.set(.suffix, h.expression(e, suffixAfter, .{ text, f.get(.colon) }));
    activation.phase = .invalid;
    return .{ .child = try v.invokeOwned(e, text, "substring", &.{ h.number(e, 0), f.get(.colon) }) };
}
fn selectRequested(s: *Scope, text: c.JSValue, pool: c.JSValue, request: c.JSValue, usable: c.JSValue) !c.JSValue {
    return selectReference(s.engine, text, pool, try v.get(s, request, "fuzzy"), usable);
}
fn selectTextFuzzy(s: *Scope, text: c.JSValue, pool: c.JSValue, usable: c.JSValue) !c.JSValue {
    return selectFuzzy(s.engine, try v.own(s, try fuzzyMatches(s.engine, text, pool)), usable);
}
fn finishText(activation: *Activation) !c.JSValue {
    const f = &activation.locals; const e = f.engine;
    const inner = if (activation.phase == .valid) f.get(.inner_valid) else f.get(.inner_invalid);
    if (try h.fieldEqual(e, inner, "status", "not-found")) return h.duplicate(e, inner);
    return h.expression(e, recursiveResult, .{ activation, inner });
}
fn recursiveResult(s: *Scope, activation: *Activation, inner: c.JSValue) !c.JSValue {
    const result = try copied(s, inner);
    if (activation.phase == .valid) {
        if (try h.fieldTest(s.engine, inner, "warning", .truthy)) try v.put(s, result, "thinkingLevel", c.pi_js_undefined())
        else try fieldInto(s.engine, result, "thinkingLevel", activation.locals.get(.thinking), "thinkingLevel");
    } else {
        try v.put(s, result, "thinkingLevel", c.pi_js_undefined());
        try h.statement(s.engine, invalidWarningInto, .{ result, activation.locals.get(.suffix), activation.text });
    }
    return v.duplicate(s, result);
}
fn invalidWarningInto(s: *Scope, result: c.JSValue, suffix: c.JSValue, text: c.JSValue) !void {
    var warning = try h.binary(s, .add, try v.text(s, "Invalid thinking level \""), try v.stringify(s, suffix));
    warning = try h.binary(s, .add, warning, try v.text(s, "\" in pattern \""));
    warning = try h.binary(s, .add, warning, try v.stringify(s, text));
    warning = try h.binary(s, .add, warning, try v.text(s, "\". Using default instead."));
    try v.put(s, result, "warning", warning);
}

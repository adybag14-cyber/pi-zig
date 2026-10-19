//! Actual c268 render-utils formatReadLineRange and its private numeric helper.
//! The public function and existing read renderer share these exact bodies.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const PromptScope = @import("native_sdk_prompt_scope.zig").Scope;
const ParseFrame = h.Frame(enum { value });
const RangeFrame = h.Frame(enum { start, count, end });

fn trimNonempty(engine: *h.Engine, value: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, trimNonemptyBody, .{value}));
}
fn trimNonemptyBody(s: *h.Scope, value: c.JSValue) !c.JSValue {
    const trimmed = try v.invoke(s, value, "trim", &.{});
    return v.boolean(s, !(try v.eq(s, trimmed, "")));
}
fn numberBody(s: *h.Scope, value: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Number");
    return v.duplicate(s, try v.call(s, constructor, c.pi_js_undefined(), &.{value}));
}
fn finiteResult(s: *h.Scope, value: c.JSValue) !c.JSValue {
    const number = try v.global(s, "Number");
    const method = try v.get(s, number, "isFinite");
    return v.duplicate(s, try v.call(s, method, number, &.{value}));
}
fn finiteBody(s: *h.Scope, value: c.JSValue) !c.JSValue {
    const result = try v.own(s, try h.expression(s.engine, finiteResult, .{value}));
    return v.boolean(s, v.truthy(s, result));
}
fn parseLineNumber(engine: *h.Engine, input: c.JSValue) !c.JSValue {
    var locals = ParseFrame.init(engine);
    try locals.set(.value, h.duplicate(engine, input));
    return locals.finish(parseNumberBody(&locals));
}
fn parseNumberBody(locals: *ParseFrame) !c.JSValue {
    const engine = locals.engine;
    if (c.JS_IsString(locals.get(.value)) and try trimNonempty(engine, locals.get(.value)))
        try locals.set(.value, h.expression(engine, numberBody, .{locals.get(.value)}));
    if (!c.JS_IsNumber(locals.get(.value))) return c.pi_js_undefined();
    const finite = h.truthy(engine, try h.expression(engine, finiteBody, .{locals.get(.value)}));
    return if (finite) h.duplicate(engine, locals.get(.value)) else c.pi_js_undefined();
}

/// Preserve the renderer's existing borrowed-Scope entry with the actual
/// complete function result transferred into that caller's owner.
pub fn format(scope: *PromptScope, offset: c.JSValue, limit: c.JSValue) !c.JSValue {
    return v.owned.ownRoot(scope, try formatOwned(scope.engine, offset, limit));
}
pub fn formatOwned(engine: *h.Engine, offset: c.JSValue, limit: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var locals = RangeFrame.init(engine);
    return locals.finish(formatBody(&locals, offset, limit));
}
fn formatBody(locals: *RangeFrame, offset: c.JSValue, limit: c.JSValue) !c.JSValue {
    const engine = locals.engine;
    if (v.nullish(offset) and v.nullish(limit)) return h.text(engine, "");
    try locals.set(.start, if (v.nullish(offset)) c.JS_NewInt32(engine.context, 1) else parseLineNumber(engine, offset));
    if (c.JS_IsUndefined(locals.get(.start))) return h.text(engine, "");
    if (v.nullish(limit)) return h.expression(engine, startText, .{locals.get(.start)});
    try locals.set(.count, parseLineNumber(engine, limit));
    if (c.JS_IsUndefined(locals.get(.count))) return h.text(engine, "");
    try locals.set(.end, h.expression(engine, endValue, .{ locals.get(.start), locals.get(.count) }));
    return h.expression(engine, rangeText, .{ locals.get(.start), locals.get(.end) });
}
fn endValue(s: *h.Scope, start: c.JSValue, count: c.JSValue) !c.JSValue {
    const sum = try h.binary(s, .add, start, count);
    return v.duplicate(s, try h.binary(s, .subtract, sum, c.JS_NewInt32(s.engine.context, 1)));
}
fn startText(s: *h.Scope, start: c.JSValue) !c.JSValue {
    const prefix = try v.text(s, ":");
    const value = try v.stringify(s, start);
    return v.duplicate(s, try h.binary(s, .add, prefix, value));
}
fn endText(s: *h.Scope, end: c.JSValue) !c.JSValue {
    if (!v.truthy(s, end)) return v.duplicate(s, try v.text(s, ""));
    const prefix = try v.text(s, "-");
    return v.duplicate(s, try h.binary(s, .add, prefix, try v.stringify(s, end)));
}
fn rangeText(s: *h.Scope, start: c.JSValue, end: c.JSValue) !c.JSValue {
    const first = try v.own(s, try h.expression(s.engine, startText, .{start}));
    const tail = try v.own(s, try h.expression(s.engine, endText, .{end}));
    return v.duplicate(s, try h.binary(s, .add, first, tail));
}
pub fn create(engine: *h.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, createBody, .{});
}
fn createBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.ordinary(s, "formatReadLineRange", 2, call, &.{}));
}
fn call(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return formatOwned(engine, v.arg(args, 0), v.arg(args, 1));
}
pub fn install(engine: *h.Engine, exports: c.JSValue) !void {
    return h.statement(engine, installBody, .{exports});
}
fn installBody(s: *h.Scope, exports: c.JSValue) !void {
    return v.put(s, exports, "formatReadLineRange", try v.own(s, try create(s.engine)));
}

//! Actual c268 ai/utils/text.ts contentText owner. Ordinary function semantics,
//! live filter/map/join calls and per-expression AF33/C435 retirement.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const cache_key = "\x00ai-content-text";
pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
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
    return v.duplicate(s, try v.ordinary(s, "contentText", 1, call, &.{}));
}
fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return contentText(engine, v.arg(args, 0), v.arg(args, 1));
}
fn textBlock(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, try h.fieldEqual(engine, v.arg(args, 0), "type", "text"));
}
fn blockText(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return h.get(engine, v.arg(args, 0), "text");
}
fn filtered(s: *Scope, content: c.JSValue) !c.JSValue {
    const filter = try v.get(s, content, "filter");
    const predicate = try v.arrow(s, "", 1, textBlock, &.{});
    return v.duplicate(s, try v.call(s, filter, content, &.{predicate}));
}
fn mapped(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const selected = try v.own(s, try incoming);
    const map = try v.get(s, selected, "map");
    const callback = try v.arrow(s, "", 1, blockText, &.{});
    return v.duplicate(s, try v.call(s, map, selected, &.{callback}));
}
fn joined(s: *Scope, incoming: anyerror!c.JSValue, separator: c.JSValue) !c.JSValue {
    const parts = try v.own(s, try incoming);
    const method = try v.get(s, parts, "join");
    return v.duplicate(s, try v.call(s, method, parts, &.{separator}));
}
pub fn contentText(engine: *Engine, content: c.JSValue, separator: c.JSValue) !c.JSValue {
    return h.expression(engine, body, .{ content, separator });
}
fn body(s: *Scope, content: c.JSValue, supplied_separator: c.JSValue) !c.JSValue {
    const separator = if (c.JS_IsUndefined(supplied_separator)) try v.text(s, "\n") else supplied_separator;
    if (c.JS_IsString(content)) return v.duplicate(s, content);
    return h.expression(s.engine, joined, .{
        h.expression(s.engine, mapped, .{h.expression(s.engine, filtered, .{content})}), separator,
    });
}

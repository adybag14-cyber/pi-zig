//! Actual c268 utils/text.ts ordinary functions. Both private model imports
//! and public frontmatter retain this same complete text module.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const cache_key = "\x00sdk-text-module-c268";

pub fn create(engine: *h.Engine) !c.JSValue {
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
fn createBody(s: *h.Scope) !c.JSValue {
    const split = try v.ordinary(s, "splitBom", 1, splitCall, &.{});
    const strip = try v.ordinary(s, "stripBom", 1, stripCall, &.{split});
    const result = try v.object(s);
    try v.put(s, result, "splitBom", split);
    try v.put(s, result, "stripBom", strip);
    return v.duplicate(s, result);
}
fn splitCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    const content = v.arg(args, 0);
    const bom = h.truthy(engine, try h.expression(engine, startsWithBom, .{content}));
    return h.expression(engine, splitBody, .{ content, bom });
}
fn startsWithBom(s: *h.Scope, content: c.JSValue) !c.JSValue {
    const method = try v.get(s, content, "startsWith");
    const value = try v.call(s, method, content, &.{try v.text(s, "\xef\xbb\xbf")});
    return v.boolean(s, v.truthy(s, value));
}
fn splitBody(s: *h.Scope, content: c.JSValue, has_bom: bool) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "bom", try v.text(s, if (has_bom) "\xef\xbb\xbf" else ""));
    try h.statement(s.engine, textField, .{ result, content, has_bom });
    return v.duplicate(s, result);
}
fn textField(s: *h.Scope, result: c.JSValue, content: c.JSValue, has_bom: bool) !void {
    const value = if (has_bom) try v.own(s, try h.expression(s.engine, sliceBody, .{content})) else content;
    return v.put(s, result, "text", value);
}
fn sliceBody(s: *h.Scope, content: c.JSValue) !c.JSValue {
    const method = try v.get(s, content, "slice");
    return v.duplicate(s, try v.call(s, method, content, &.{v.number(s, 1)}));
}
fn stripCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, stripBody, .{ roots[0], v.arg(args, 0) });
}
fn stripBody(s: *h.Scope, split: c.JSValue, content: c.JSValue) !c.JSValue {
    const record = try v.call(s, split, c.pi_js_undefined(), &.{content});
    return v.duplicate(s, try v.get(s, record, "text"));
}

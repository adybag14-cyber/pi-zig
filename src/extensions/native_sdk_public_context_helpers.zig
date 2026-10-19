//! Actual c268 public context helpers. The range renderer and source-info
//! exports come from their existing native owners; parseSkillBlock executes
//! the real fresh RegExp and the caller's live match/trim operations.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const cache_key = "\x00sdk-public-context-helpers-c268";
const MatchFrame = h.Frame(enum { matched });
const pattern = "^<skill name=\"([^\"]+)\" location=\"([^\"]+)\">\\n([\\s\\S]*?)\\n<\\/skill>(?:\\n\\n([\\s\\S]+))?$";
pub const names = .{ "parseSkillBlock", "formatReadLineRange", "createSyntheticSourceInfo" };

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
    const source_info = try v.own(s, try @import("native_sdk_source_information.zig").create(s.engine));
    const range = try v.own(s, try @import("native_sdk_read_line_range.zig").create(s.engine));
    const result = try v.object(s);
    try v.put(s, result, "parseSkillBlock", try v.ordinary(s, "parseSkillBlock", 1, parseCall, &.{}));
    try v.put(s, result, "formatReadLineRange", range);
    try v.put(s, result, "createSyntheticSourceInfo", try v.get(s, source_info, "createSyntheticSourceInfo"));
    return v.duplicate(s, result);
}
fn parseCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var locals = MatchFrame.init(engine);
    return locals.finish(parseBody(&locals, v.arg(args, 0)));
}
fn parseBody(locals: *MatchFrame, text: c.JSValue) !c.JSValue {
    const engine = locals.engine;
    try locals.set(.matched, h.expression(engine, matchBody, .{text}));
    if (!h.truthy(engine, locals.get(.matched))) return c.pi_js_null();
    return h.expression(engine, recordBody, .{locals.get(.matched)});
}
fn matchBody(s: *h.Scope, text: c.JSValue) !c.JSValue {
    const method = try v.get(s, text, "match");
    // A RegExp literal uses the retained actual intrinsic, never global RegExp.
    // It is a fresh real RegExp after the match callee has been selected.
    const expression = try v.construct(s, s.engine.intrinsic_regexp_constructor, &.{try v.text(s, pattern)});
    return v.duplicate(s, try v.call(s, method, text, &.{expression}));
}
fn recordBody(s: *h.Scope, matched: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try h.statement(s.engine, fieldBody, .{ result, matched, "name", @as(u32, 1) });
    try h.statement(s.engine, fieldBody, .{ result, matched, "location", @as(u32, 2) });
    try h.statement(s.engine, fieldBody, .{ result, matched, "content", @as(u32, 3) });
    try h.statement(s.engine, userMessageField, .{ result, matched });
    return v.duplicate(s, result);
}
fn fieldBody(s: *h.Scope, result: c.JSValue, matched: c.JSValue, comptime name: [*:0]const u8, position: u32) !void {
    return v.put(s, result, name, try v.at(s, matched, position));
}
fn trimBody(s: *h.Scope, matched: c.JSValue) !c.JSValue {
    const receiver = try v.at(s, matched, 4);
    if (v.nullish(receiver)) return c.pi_js_undefined();
    const method = try v.get(s, receiver, "trim");
    return v.duplicate(s, try v.call(s, method, receiver, &.{}));
}
fn userMessageBody(s: *h.Scope, matched: c.JSValue) !c.JSValue {
    const value = try v.own(s, try h.expression(s.engine, trimBody, .{matched}));
    return if (v.truthy(s, value)) v.duplicate(s, value) else c.pi_js_undefined();
}
fn userMessageField(s: *h.Scope, result: c.JSValue, matched: c.JSValue) !void {
    const value = try v.own(s, try h.expression(s.engine, userMessageBody, .{matched}));
    return v.put(s, result, "userMessage", value);
}

//! Actual c268 frontmatter call chain over the existing native YAML owner.
//! Public arrows and the existing prompt/skill ABI share one completed module.
//! Text methods, intrinsic RegExp literals, records and lexical slots remain
//! real guest operations with AF33/C435 ownership.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const yaml = @import("native_sdk_yaml_values.zig");
const LegacyScope = @import("native_sdk_prompt_scope.zig").Scope;
const cache_key = "\x00sdk-frontmatter-module-c268";
const ExtractFrame = h.Frame(enum { normalized, endIndex });
const ParseFrame = h.Frame(enum { yamlString, body, parsed });
pub const Result = struct { frontmatter: c.JSValue, body: c.JSValue };
pub const names = .{ "parseFrontmatter", "stripFrontmatter" };

pub fn exports(engine: *h.Engine) !c.JSValue {
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
    const parser = try v.own(s, try yaml.create(s.engine));
    const text = try v.own(s, try @import("native_sdk_text_helpers.zig").create(s.engine));
    const strip_bom = try v.get(s, text, "stripBom");
    const normalize = try v.arrow(s, "normalizeNewlines", 1, normalizeCall, &.{});
    const extract = try v.arrow(s, "extractFrontmatter", 1, extractCall, &.{ strip_bom, normalize });
    const parse_frontmatter = try v.arrow(s, "parseFrontmatter", 1, parseCall, &.{ extract, parser });
    const strip_frontmatter = try v.arrow(s, "stripFrontmatter", 1, stripCall, &.{parse_frontmatter});
    const result = try v.object(s);
    try v.put(s, result, "parseFrontmatter", parse_frontmatter);
    try v.put(s, result, "stripFrontmatter", strip_frontmatter);
    return v.duplicate(s, result);
}
/// Original internal callers asking for the parser obtain the very same arrow.
pub fn create(engine: *h.Engine) !c.JSValue {
    return h.expression(engine, parserBody, .{});
}
fn parserBody(s: *h.Scope) !c.JSValue {
    const module = try v.own(s, try exports(s.engine));
    return v.duplicate(s, try v.get(s, module, "parseFrontmatter"));
}
fn normalizeCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, normalizeBody, .{v.arg(args, 0)});
}
fn replaceBody(s: *h.Scope, input: c.JSValue, comptime pattern: []const u8) !c.JSValue {
    const method = try v.get(s, input, "replace");
    const regex = try v.construct(s, s.engine.intrinsic_regexp_constructor, &.{try v.text(s, pattern), try v.text(s, "g")});
    return v.duplicate(s, try v.call(s, method, input, &.{regex, try v.text(s, "\n")}));
}
fn normalizeBody(s: *h.Scope, input: c.JSValue) !c.JSValue {
    // The first complete call retires before selecting the second .replace;
    // its returned receiver and the second callee then share one expression.
    const receiver = try v.own(s, try h.expression(s.engine, replaceBody, .{ input, "\\r\\n" }));
    const method = try v.get(s, receiver, "replace");
    const regex = try v.construct(s, s.engine.intrinsic_regexp_constructor, &.{try v.text(s, "\\r"), try v.text(s, "g")});
    return v.duplicate(s, try v.call(s, method, receiver, &.{regex, try v.text(s, "\n")}));
}
fn extractCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var locals = ExtractFrame.init(engine);
    return locals.finish(extractBody(&locals, v.arg(args, 0), roots[0], roots[1]));
}
fn normalizedBody(s: *h.Scope, input: c.JSValue, strip_bom: c.JSValue, normalize: c.JSValue) !c.JSValue {
    const stripped = try v.call(s, strip_bom, c.pi_js_undefined(), &.{input});
    return v.duplicate(s, try v.call(s, normalize, c.pi_js_undefined(), &.{stripped}));
}
fn startsWithFence(s: *h.Scope, input: c.JSValue) !c.JSValue {
    const method = try v.get(s, input, "startsWith");
    const result = try v.call(s, method, input, &.{try v.text(s, "---")});
    return v.boolean(s, v.truthy(s, result));
}
fn endIndexBody(s: *h.Scope, input: c.JSValue) !c.JSValue {
    const method = try v.get(s, input, "indexOf");
    return v.duplicate(s, try v.call(s, method, input, &.{try v.text(s, "\n---"), v.number(s, 3)}));
}
fn extractBody(locals: *ExtractFrame, input: c.JSValue, strip_bom: c.JSValue, normalize: c.JSValue) !c.JSValue {
    const engine = locals.engine;
    try locals.set(.normalized, h.expression(engine, normalizedBody, .{ input, strip_bom, normalize }));
    if (!h.truthy(engine, try h.expression(engine, startsWithFence, .{locals.get(.normalized)})))
        return h.expression(engine, noFenceBody, .{locals.get(.normalized)});
    try locals.set(.endIndex, h.expression(engine, endIndexBody, .{locals.get(.normalized)}));
    if (c.JS_IsStrictEqual(engine.context, locals.get(.endIndex), h.number(engine, -1)))
        return h.expression(engine, noFenceBody, .{locals.get(.normalized)});
    return h.expression(engine, extractedRecord, .{ locals.get(.normalized), locals.get(.endIndex) });
}
fn noFenceBody(s: *h.Scope, normalized: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "yamlString", c.pi_js_null());
    try v.put(s, result, "body", normalized);
    return v.duplicate(s, result);
}
fn extractedRecord(s: *h.Scope, normalized: c.JSValue, end_index: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try h.statement(s.engine, yamlField, .{ result, normalized, end_index });
    try h.statement(s.engine, bodyField, .{ result, normalized, end_index });
    return v.duplicate(s, result);
}
fn yamlSlice(s: *h.Scope, normalized: c.JSValue, end_index: c.JSValue) !c.JSValue {
    const method = try v.get(s, normalized, "slice");
    return v.duplicate(s, try v.call(s, method, normalized, &.{v.number(s, 4), end_index}));
}
fn yamlField(s: *h.Scope, result: c.JSValue, normalized: c.JSValue, end_index: c.JSValue) !void {
    const value = try v.own(s, try h.expression(s.engine, yamlSlice, .{ normalized, end_index }));
    return v.put(s, result, "yamlString", value);
}
fn endPlusFour(s: *h.Scope, end_index: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, end_index, v.number(s, 4)));
}
fn bodySlice(s: *h.Scope, normalized: c.JSValue, end_index: c.JSValue) !c.JSValue {
    const method = try v.get(s, normalized, "slice");
    const start = try v.own(s, try h.expression(s.engine, endPlusFour, .{end_index}));
    return v.duplicate(s, try v.call(s, method, normalized, &.{start}));
}
fn bodyText(s: *h.Scope, normalized: c.JSValue, end_index: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, bodySlice, .{ normalized, end_index }));
    const method = try v.get(s, receiver, "trim");
    return v.duplicate(s, try v.call(s, method, receiver, &.{}));
}
fn bodyField(s: *h.Scope, result: c.JSValue, normalized: c.JSValue, end_index: c.JSValue) !void {
    const value = try v.own(s, try h.expression(s.engine, bodyText, .{ normalized, end_index }));
    return v.put(s, result, "body", value);
}
fn parseCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var locals = ParseFrame.init(engine);
    return locals.finish(parseBody(&locals, roots[0], roots[1], v.arg(args, 0)));
}
fn destructure(s: *h.Scope, locals: *ParseFrame, extract: c.JSValue, content: c.JSValue) !void {
    const record = try v.call(s, extract, c.pi_js_undefined(), &.{content});
    const object = try v.guest.toObject(s, record);
    try locals.set(.yamlString, h.get(s.engine, object, "yamlString"));
    try locals.set(.body, h.get(s.engine, object, "body"));
}
fn parseBody(locals: *ParseFrame, extract: c.JSValue, parser: c.JSValue, content: c.JSValue) !c.JSValue {
    const engine = locals.engine;
    try h.statement(engine, destructure, .{ locals, extract, content });
    if (!h.truthy(engine, locals.get(.yamlString)))
        return h.expression(engine, parsedRecord, .{ c.pi_js_null(), locals.get(.body) });
    try locals.set(.parsed, h.expression(engine, parseYamlBody, .{ parser, locals.get(.yamlString) }));
    return h.expression(engine, parsedRecord, .{ locals.get(.parsed), locals.get(.body) });
}
fn parseYamlBody(s: *h.Scope, parser: c.JSValue, input: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, parser, c.pi_js_undefined(), &.{input}));
}
fn parsedRecord(s: *h.Scope, parsed: c.JSValue, body: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "frontmatter", if (v.nullish(parsed)) try v.object(s) else parsed);
    try v.put(s, result, "body", body);
    return v.duplicate(s, result);
}
fn stripCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, stripBody, .{ roots[0], v.arg(args, 0) });
}
fn stripBody(s: *h.Scope, parser: c.JSValue, content: c.JSValue) !c.JSValue {
    const record = try v.call(s, parser, c.pi_js_undefined(), &.{content});
    return v.duplicate(s, try v.get(s, record, "body"));
}
/// Existing prompt/skill parsers receive two roots in their original Scope.
/// The actual record/destructuring expression finishes before caller work.
pub fn parseValue(scope: *LegacyScope, input: c.JSValue) !Result {
    var result: Result = .{ .frontmatter = c.pi_js_undefined(), .body = c.pi_js_undefined() };
    try h.statement(scope.engine, legacyParse, .{ scope, input, &result });
    return result;
}
fn legacyParse(s: *h.Scope, scope: *LegacyScope, input: c.JSValue, result: *Result) !void {
    const parser = try v.own(s, try create(s.engine));
    const record = try v.call(s, parser, c.pi_js_undefined(), &.{input});
    result.frontmatter = try v.owned.ownRoot(scope, try h.get(s.engine, record, "frontmatter"));
    result.body = try v.owned.ownRoot(scope, try h.get(s.engine, record, "body"));
}
pub fn parse(scope: *LegacyScope, input: []const u8) !Result {
    var result: Result = .{ .frontmatter = c.pi_js_undefined(), .body = c.pi_js_undefined() };
    try h.statement(scope.engine, legacyTextParse, .{ scope, input, &result });
    return result;
}
fn legacyTextParse(s: *h.Scope, scope: *LegacyScope, input: []const u8, result: *Result) !void {
    result.* = try parseValue(scope, try yaml.string(s, input));
}

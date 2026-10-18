//! Prepared only. Each entry requires a fresh real Engine with actual node:url
//! installed. Accepted original rows are a future caller input, never authored.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const subject = @import("extensions/native_sdk_git_url.zig");
const c = v.c;
fn namespace(engine: *v.em.Engine) !c.JSValue {
    return engine.native_module_values.get("node:url") orelse error.RequiredActualNodeUrlNamespace;
}
fn parser(s: *v.Scope) !c.JSValue {
    const actual = try s.own(try subject.create(s.engine, try namespace(s.engine)));
    return s.get(actual, "parseGitUrl");
}
pub fn captureActualCallerRows(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const parse = try parser(&s);
    const caller = try s.own(try engine.eval(@embedFile("extensions/fixtures/sdk-git-url-caller.mjs"), "actual-git-caller.js", c.JS_EVAL_TYPE_GLOBAL));
    const bytes = @embedFile("extensions/fixtures/sdk-git-url-cases.json");
    const cases = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "actual-git-cases.json")));
    return c.JS_DupValue(engine.context, try s.call(caller, c.pi_js_undefined(), &.{ parse, try namespace(engine), cases }));
}
/// Requires independently accepted original rows from the actual published Pi
/// module. No comparison may run until its original capture is authorized.
pub fn verifyAcceptedOriginalRows(engine: *v.em.Engine, accepted_rows: c.JSValue) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const rows = try s.own(try captureActualCallerRows(engine));
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    const actual = try s.call(stringify, json, &.{rows});
    const accepted = try s.call(stringify, json, &.{accepted_rows});
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, accepted));
}
fn fatalProbe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context); defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(context, global, "actualGitFatalReason", c.JS_DupValue(context, reason), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(reason); return c.JS_Throw(context, c.JS_GetException(context));
    }
    return c.JS_Throw(context, reason);
}
/// This injects a REAL native producer event at the actual global URL
/// construction boundary, inside Pi's forgiving splitRef Source catch.
/// The Proxy delegates to the real URL if the producer unexpectedly returns;
/// no URL-shaped fake result or diagnostic-name classifier is used.
pub fn verifyFreshNativeAllocationBypassesSourceCatch(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const parse = try parser(&s); const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const probe = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, fatalProbe, "actualGitNativeAllocation", 0)));
    try s.put(global, "actualGitNativeAllocation", probe);
    const setup = try engine.evalModule(
        \\globalThis.actualGitFatalReason=undefined;globalThis.actualGitCaught=0;
        \\const RealURL=globalThis.URL;
        \\globalThis.URL=new Proxy(RealURL,{construct(target,args){actualGitNativeAllocation();return Reflect.construct(target,args,target)}});
    , "actual-git-fatal-setup.mjs"); engine.freeValue(setup);
    const text = try s.text("https://example.org/team/repo@next");
    var args = [_]c.JSValue{text};
    const result = c.JS_Call(engine.context, parse, c.pi_js_undefined(), 1, &args); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    const original = try s.get(global, "actualGitFatalReason");
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, original));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    // No guest restore after a fatal or assertion failure: fresh realm teardown.
}
/// A diagnostic from an earlier completed producer is DATA at a new call.
/// Its actual bit/tag must remain untouched and cannot suppress parser entry.
pub fn verifyHistoricalCapturedDataDoesNotSkipBody(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const parse = try parser(&s); const text = try s.text("git:example.org/team/repo");
    try std.testing.expect(engine.captured_exception == null and !c.JS_HasException(engine.context));
    _ = engine.throwNativeOutOfMemoryFatal();
    const old = c.JS_GetException(engine.context); defer engine.freeValue(old);
    engine.captured_exception = c.JS_DupValue(engine.context, old);
    var args = [_]c.JSValue{text};
    const result = c.JS_Call(engine.context, parse, c.pi_js_undefined(), 1, &args); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsObject(result) and !c.JS_IsException(result));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, old, engine.captured_exception orelse return error.HistoricalReasonLost));
    try std.testing.expect(c.JS_IsUncatchableError(old));
}
pub fn verifyCancellationIsUncatchable(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const parse = try parser(&s); const text = try s.text("git:example.org/team/repo");
    var args = [_]c.JSValue{text};
    engine.cancelled.store(true, .release);
    const result = c.JS_Call(engine.context, parse, c.pi_js_undefined(), 1, &args);
    engine.cancelled.store(false, .release); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
}

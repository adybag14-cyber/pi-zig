//! Ordinary AgentSession export and bug-report summary entry points.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;

pub fn installJsonl(engine: *em.Engine, prototype: c.JSValue) !void {
    try @import("native_sdk_session_export_jsonl.zig").install(engine, prototype);
}
pub fn installHtml(engine: *em.Engine, prototype: c.JSValue) !void {
    try @import("native_sdk_export_html.zig").install(engine, prototype);
}
pub fn installSummary(engine: *em.Engine, prototype: c.JSValue, generate_summary: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, generate_summary)) return error.RequiredSharedNativeBugReportSummary;
    var roots = [_]c.JSValue{generate_summary};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, summarize, "summarizeForBugReport", 1, 0, roots.len, &roots));
    defer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "summarizeForBugReport", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn summarize(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return beginSummary(engine, session, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn beginSummary(engine: *em.Engine, session: c.JSValue, options: c.JSValue, generate_summary: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, options, generate_summary) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, options: c.JSValue, generate_summary: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const model = try scope.get(session, "model");
    if (!scope.truthy(model)) {
        try @import("native_durable_errors.zig").throwMessage(engine, "No model selected");
        return error.JavaScriptException;
    }
    try scope.put(owner, "options", options);
    try scope.put(owner, "generateSummary", generate_summary);
    const auth = try scope.invoke(session, "_getSummarizationRequestAuth", &.{ model, try scope.get(options, "signal") });
    try flow.wait(authReady, engine, owner, auth, 0);
}
fn authReady(engine: *em.Engine, owner: c.JSValue, auth: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, auth);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const options = try scope.get(owner, "options");
    const request = try scope.own(try js.spread(engine, auth));
    try scope.put(request, "messages", try scope.get(session, "messages"));
    try scope.put(request, "hint", try scope.get(options, "hint"));
    try scope.put(request, "signal", try scope.get(options, "signal"));
    try scope.put(request, "streamFn", try scope.get(try scope.get(session, "agent"), "streamFunction"));
    try scope.put(request, "retry", try scope.invoke(try scope.get(session, "settingsManager"), "getRetrySettings", &.{}));
    try scope.put(request, "sessionId", try scope.get(session, "sessionId"));
    const result = try scope.call(try scope.get(owner, "generateSummary"), c.pi_js_undefined(), &.{request});
    try flow.settle(engine, owner, false, result);
}

//! One actual session/public compaction graph over the genuine pi-ai compat
//! imports. Public compaction and AgentSession retain the same function objects.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const cache_key = "\x00sdk-session-ai-assembly-c268";

pub fn create(engine: *h.Engine, compat: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{compat});
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
fn createBody(s: *h.Scope, compat: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const complete_simple = try v.get(s, compat, "completeSimple");
    const reset = try v.get(s, compat, "resetApiProviders");
    if (!c.JS_IsFunction(engine.context, complete_simple) or !c.JS_IsFunction(engine.context, reset))
        return error.RequiredSharedNativeAiCompatBindings;
    const uuid = try v.own(s, try @import("native_ai_uuid.zig").create(engine));
    const retry = try v.own(s, try @import("native_ai_retry_call.zig").create(engine));
    const request = try v.own(s, try @import("native_sdk_complete_summarization.zig").create(engine, uuid, complete_simple, retry));
    const compaction = try v.own(s, try @import("native_sdk_public_compaction.zig").create(engine, request));
    const branch = try v.own(s, try @import("native_sdk_branch_summary.zig").exports(engine, request));
    const result = try v.object(s);
    try v.put(s, result, "completeSummarization", request);
    inline for (.{ "compact", "generateSummary", "generateSummaryWithUsage" }) |name|
        try v.put(s, result, name, try v.get(s, compaction, name));
    try v.put(s, result, "resetApiProviders", reset);
    try v.put(s, result, "branchSummary", branch);
    try v.put(s, result, "compaction", compaction);
    return v.duplicate(s, result);
}

pub fn install(engine: *h.Engine, prototype: c.JSValue, shared: c.JSValue) !void {
    try engine.checkNativeEntry();
    return h.statement(engine, installBody, .{prototype, shared});
}
fn installBody(s: *h.Scope, prototype: c.JSValue, shared: c.JSValue) !void {
    const compact = try v.get(s, shared, "compact");
    const reset = try v.get(s, shared, "resetApiProviders");
    const branch = try v.get(s, shared, "branchSummary");
    if (!c.JS_IsFunction(s.engine.context, compact) or !c.JS_IsFunction(s.engine.context, reset))
        return error.RequiredSharedNativeSessionAiBindings;
    try @import("native_sdk_session_compaction.zig").install(s.engine, prototype, compact);
    try @import("native_sdk_session_reload.zig").install(s.engine, prototype, reset);
    try @import("native_sdk_session_navigate.zig").install(s.engine, prototype, branch);
}

//! Assemble ordinary session compaction/reload over one actual pi-ai compat
//! namespace. The caller owns provider construction; no independent registry or
//! placeholder completion is created at this boundary.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

pub fn create(engine: *em.Engine, compat: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Capture the same imported bindings used by upstream. A later write to
    // the namespace does not change an already imported function binding.
    const complete_simple = try scope.get(compat, "completeSimple");
    const reset = try scope.get(compat, "resetApiProviders");
    if (!c.JS_IsFunction(engine.context, complete_simple) or !c.JS_IsFunction(engine.context, reset))
        return error.RequiredSharedNativeAiCompatBindings;
    const uuid = try scope.own(try @import("native_ai_uuid.zig").create(engine));
    const retry = try scope.own(try @import("native_ai_retry_call.zig").create(engine));
    const request = try scope.own(try @import("native_sdk_complete_summarization.zig").create(engine, uuid, complete_simple, retry));
    const generation = try scope.own(try @import("native_sdk_summary_generation.zig").exports(engine, request));
    const result = try scope.object();
    try scope.put(result, "completeSummarization", request);
    try scope.put(result, "compact", try scope.get(generation, "compact"));
    try scope.put(result, "generateSummary", try scope.get(generation, "generateSummary"));
    try scope.put(result, "generateSummaryWithUsage", try scope.get(generation, "generateSummaryWithUsage"));
    try scope.put(result, "resetApiProviders", reset);
    return c.JS_DupValue(engine.context, result);
}

pub fn install(engine: *em.Engine, prototype: c.JSValue, shared: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const compact = try scope.get(shared, "compact");
    const reset = try scope.get(shared, "resetApiProviders");
    if (!c.JS_IsFunction(engine.context, compact) or !c.JS_IsFunction(engine.context, reset))
        return error.RequiredSharedNativeSessionAiBindings;
    try @import("native_sdk_session_compaction.zig").install(engine, prototype, compact);
    try @import("native_sdk_session_reload.zig").install(engine, prototype, reset);
}

//! The fourteen actual coding-agent compaction index bindings. These are the
//! same native owners used by AgentSession; this record adds no replacement
//! callback or independent completion provider.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const cache_key = "\x00sdk-public-compaction-index-c268";
pub const names = .{
    "calculateContextTokens", "collectEntriesForBranchSummary", "compact",
    "DEFAULT_COMPACTION_SETTINGS", "estimateTokens", "findCutPoint",
    "findTurnStartIndex", "generateBranchSummary", "generateSummary",
    "generateSummaryWithUsage", "getLastAssistantUsage", "prepareBranchEntries",
    "serializeConversation", "shouldCompact",
};

/// Called by the actual shared-AI assembler with its retained
/// completeSummarization function, before any public SDK namespace selection.
pub fn create(engine: *h.Engine, complete_request: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{complete_request});
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
fn bindings(s: *h.Scope, target: c.JSValue, source: c.JSValue, comptime selected: anytype) !void {
    inline for (selected) |name| try v.put(s, target, name, try v.get(s, source, name));
}
fn createBody(s: *h.Scope, complete_request: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const branch = try v.own(s, try @import("native_sdk_branch_summary.zig").exports(engine, complete_request));
    const core = try v.own(s, try @import("native_sdk_public_compaction_core.zig").create(engine));
    const summary = try v.own(s, try @import("native_sdk_summary_generation.zig").exports(engine, complete_request));
    const text = try v.own(s, try @import("native_sdk_compaction_text.zig").exports(engine));
    const result = try v.object(s);
    try bindings(s, result, branch, .{ "collectEntriesForBranchSummary", "generateBranchSummary", "prepareBranchEntries" });
    try bindings(s, result, core, .{
        "calculateContextTokens", "DEFAULT_COMPACTION_SETTINGS", "estimateTokens",
        "findCutPoint", "findTurnStartIndex", "getLastAssistantUsage", "shouldCompact",
    });
    try bindings(s, result, summary, .{ "compact", "generateSummary", "generateSummaryWithUsage" });
    try bindings(s, result, text, .{"serializeConversation"});
    return v.duplicate(s, result);
}

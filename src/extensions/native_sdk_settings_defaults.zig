//! Complete original settings-defaults.ts value, shared once per Engine.
//! TypeScript "as const" adds no runtime freezing. This ordinary object and
//! its nested objects remain mutable, exactly like the original export.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const cache_key = "pi-private:actual-sdk-settings-defaults";

// Original ai/src/utils/retry.ts immutable exported constant. This is the
// constant supplier only; it does not publish a partial retry module.
pub const default_max_agent_retry_delay_ms: f64 = 60_000;

pub fn create(engine: *h.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const value = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(value);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var selected = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        selected.release(value);
        return selected.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, value);
    return h.duplicate(engine, value);
}
fn text(s: *h.Scope, object: c.JSValue, name: [*:0]const u8, value: []const u8) !void {
    return v.put(s, object, name, try v.text(s, value));
}
fn number(s: *h.Scope, object: c.JSValue, name: [*:0]const u8, value: f64) !void {
    return v.put(s, object, name, v.number(s, value));
}
fn boolean(s: *h.Scope, object: c.JSValue, name: [*:0]const u8, value: bool) !void {
    return v.put(s, object, name, v.boolean(s, value));
}
fn createBody(s: *h.Scope) !c.JSValue {
    const result = try v.object(s);
    try text(s, result, "transport", "auto");
    try text(s, result, "sessionShareDestination", "auto");
    try text(s, result, "steeringMode", "one-at-a-time");
    try text(s, result, "followUpMode", "one-at-a-time");
    const compaction = try v.object(s);
    try boolean(s, compaction, "enabled", true);
    try number(s, compaction, "reserveTokens", 16384);
    try number(s, compaction, "keepRecentTokens", 20000);
    try v.put(s, result, "compaction", compaction);
    const branch_summary = try v.object(s);
    try number(s, branch_summary, "reserveTokens", 16384);
    try boolean(s, branch_summary, "skipPrompt", false);
    try v.put(s, result, "branchSummary", branch_summary);
    const retry = try v.object(s);
    try boolean(s, retry, "enabled", true);
    try number(s, retry, "maxRetries", 3);
    try number(s, retry, "baseDelayMs", 2000);
    try number(s, retry, "maxAgentDelayMs", default_max_agent_retry_delay_ms);
    const provider = try v.object(s);
    try number(s, provider, "maxRetryDelayMs", 60000);
    try v.put(s, retry, "provider", provider);
    try v.put(s, result, "retry", retry);
    try boolean(s, result, "hideThinkingBlock", false);
    try boolean(s, result, "showCacheMissNotices", false);
    try boolean(s, result, "quietStartup", false);
    try text(s, result, "defaultProjectTrust", "ask");
    try boolean(s, result, "collapseChangelog", false);
    try boolean(s, result, "enableInstallTelemetry", true);
    try boolean(s, result, "enableAnalytics", false);
    try boolean(s, result, "enableSkillCommands", true);
    const terminal = try v.object(s);
    try boolean(s, terminal, "showImages", true);
    try number(s, terminal, "imageWidthCells", 60);
    try boolean(s, terminal, "clearOnShrink", false);
    try boolean(s, terminal, "showTerminalProgress", false);
    try v.put(s, result, "terminal", terminal);
    const images = try v.object(s);
    try boolean(s, images, "autoResize", true);
    try boolean(s, images, "blockImages", false);
    try v.put(s, result, "images", images);
    try text(s, result, "doubleEscapeAction", "tree");
    try text(s, result, "treeFilterMode", "default");
    try number(s, result, "editorPaddingX", 0);
    try number(s, result, "outputPad", 1);
    try number(s, result, "autocompleteMaxVisible", 5);
    const markdown = try v.object(s);
    try text(s, markdown, "codeBlockIndent", "  ");
    try text(s, markdown, "mermaid", "streaming");
    try v.put(s, result, "markdown", markdown);
    const warnings = try v.object(s);
    try boolean(s, warnings, "anthropicExtraUsage", true);
    try v.put(s, result, "warnings", warnings);
    const codemode = try v.object(s);
    try text(s, codemode, "mode", "on");
    try number(s, codemode, "inlineBudget", 3000);
    try v.put(s, result, "codemode", codemode);
    try text(s, result, "cacheWarming", "streaming");
    try text(s, result, "tuiMode", "fullscreen");
    try text(s, result, "fullscreenExitOutput", "transcript");
    try text(s, result, "fullscreenScrollbar", "auto");
    try boolean(s, result, "fullscreenCopyOnSelect", true);
    try text(s, result, "fullscreenWheelScrollLines", "auto");
    return v.duplicate(s, result);
}

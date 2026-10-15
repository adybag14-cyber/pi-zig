//! Actual five ordinary Bash/export methods. Requires the qualified platform
//! component671e2285 (or its proof successor) to be present in the intake tree.
//! Runtime bootstrap remains the native worker/application's responsibility.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn install(engine: *em.Engine, prototype: c.JSValue, shared_ai: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const executor = try scope.own(try @import("native_bash_executor.zig").create(engine));
    const local = try scope.own(try @import("native_bash_local_operations.zig").create(engine));
    try @import("native_sdk_session_bash.zig").install(engine, prototype, executor, local);
    try @import("native_sdk_session_exports.zig").installJsonl(engine, prototype);
    try @import("native_sdk_session_exports.zig").installHtml(engine, prototype);
    const request = try scope.get(shared_ai, "completeSummarization");
    if (!c.JS_IsFunction(engine.context, request)) return error.RequiredActualSharedCompleteSummarization;
    const bug_report = try scope.own(try @import("native_sdk_bug_report_summary.zig").create(engine, request));
    try @import("native_sdk_session_exports.zig").installSummary(engine, prototype, bug_report);
}

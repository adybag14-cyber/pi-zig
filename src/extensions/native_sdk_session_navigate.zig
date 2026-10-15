//! Actual AgentSession.navigateTree with live session collaborators and a
//! finally scope that survives before-tree, auth, generation and tree awaits.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const replay = @import("native_sdk_transcript_replay.zig");
const c = em.c;
const Stage = enum(c_int) { before, auth, summary, emitted };
pub fn install(engine: *em.Engine, prototype: c.JSValue, branch_bindings: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ try scope.get(branch_bindings, "collectEntriesForBranchSummary"), try scope.get(branch_bindings, "generateBranchSummary") };
    for (roots) |value| if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualBranchSummaryBindings;
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "navigateTree", 1, 0, roots.len, &roots)));
    if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "navigateTree", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return navigate(engine, session, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
fn is(scope: *Scope, value: c.JSValue, expected: []const u8) !bool {
    return scope.equal(value, try scope.text(expected));
}
fn raise(scope: *Scope, message: c.JSValue) anyerror {
    const constructor = scope.global("Error") catch |err| return err;
    return raiseWith(scope, constructor, message);
}
fn raiseWith(scope: *Scope, constructor: c.JSValue, message: c.JSValue) anyerror {
    var input = [_]c.JSValue{message};
    const reason = scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, input.len, &input)) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, reason)) catch |err| return err;
    unreachable;
}
fn outcome(scope: *Scope, cancelled: bool, aborted: bool) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "cancelled", c.pi_js_bool(scope.engine.context, @intFromBool(cancelled)));
    if (aborted) try scope.put(result, "aborted", c.pi_js_bool(scope.engine.context, 1));
    return result;
}
fn navigate(engine: *em.Engine, session: c.JSValue, target: c.JSValue, supplied_options: c.JSValue, collect: c.JSValue, generate: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, session, target, supplied_options, collect, generate) catch |err| try rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, session: c.JSValue, target: c.JSValue, supplied_options: c.JSValue, collect: c.JSValue, generate: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "finallyActive", c.pi_js_bool(engine.context, 0));
    const options = if (c.JS_IsUndefined(supplied_options)) try scope.object() else supplied_options;
    inline for (.{ .{ "options", options }, .{ "targetId", target }, .{ "generate", generate } }) |field| try scope.put(owner, field[0], field[1]);
    if (scope.truthy(try scope.get(session, "isStreaming"))) return raise(&scope, try scope.text("Wait for the current response to finish before navigating the session tree."));
    if (scope.truthy(try scope.get(session, "isCompacting"))) return raise(&scope, try scope.text("Wait for the current compaction or tree navigation to finish before navigating the session tree."));
    const old_leaf = try scope.invoke(try scope.get(session, "sessionManager"), "getLeafId", &.{});
    try scope.put(owner, "oldLeafId", old_leaf);
    if (scope.equal(target, old_leaf)) return flow.settle(engine, owner, false, try outcome(&scope, false, false));
    if (scope.truthy(try scope.get(options, "summarize")) and !scope.truthy(try scope.get(session, "model"))) return raise(&scope, try scope.text("No model available for summarization"));
    const entry = try scope.invoke(try scope.get(session, "sessionManager"), "getEntry", &.{target});
    if (!scope.truthy(entry)) {
        const constructor = try scope.global("Error");
        return raiseWith(&scope, constructor, try scope.concat(try scope.concat(try scope.text("Entry "), try scope.stringify(target)), try scope.text(" not found")));
    }
    try scope.put(owner, "targetEntry", entry);
    const collected = try scope.call(collect, c.pi_js_undefined(), &.{ try scope.get(session, "sessionManager"), old_leaf, target });
    const entries = try scope.get(collected, "entries");
    const ancestor = try scope.get(collected, "commonAncestorId");
    try scope.put(owner, "entries", entries);
    inline for (.{ "customInstructions", "replaceInstructions", "label" }) |name| try scope.put(owner, name, try scope.get(options, name));
    const preparation = try scope.object();
    try scope.put(preparation, "targetId", target);
    try scope.put(preparation, "oldLeafId", old_leaf);
    try scope.put(preparation, "commonAncestorId", ancestor);
    try scope.put(preparation, "entriesToSummarize", entries);
    var wants = try scope.get(options, "summarize");
    if (temp.nullish(wants)) wants = c.pi_js_bool(engine.context, 0);
    try scope.put(preparation, "userWantsSummary", wants);
    inline for (.{ "customInstructions", "replaceInstructions", "label" }) |name| try scope.put(preparation, name, try scope.get(owner, name));
    const controller = try scope.own(try js.builtin(engine, "AbortController", &.{}));
    try scope.set(session, "_branchSummaryAbortController", controller);
    try scope.put(owner, "finallyActive", c.pi_js_bool(engine.context, 1));
    try scope.put(owner, "extensionSummary", c.pi_js_undefined());
    try scope.put(owner, "fromExtension", c.pi_js_bool(engine.context, 0));
    if (scope.truthy(try scope.invoke(try scope.get(session, "_extensionRunner"), "hasHandlers", &.{try scope.text("session_before_tree")}))) {
        const runner = try scope.get(session, "_extensionRunner");
        const emit = try scope.get(runner, "emit");
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("session_before_tree"));
        try scope.put(event, "preparation", preparation);
        try scope.put(event, "signal", try scope.get(try scope.get(session, "_branchSummaryAbortController"), "signal"));
        return flow.wait(continueNavigation, engine, owner, try scope.call(emit, runner, &.{event}), @intFromEnum(Stage.before));
    }
    try prepareSummary(engine, owner);
}
fn continueNavigation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return finish(engine, owner, true, value);
    resumeBody(engine, owner, value, @enumFromInt(stage)) catch |err| try rejectError(engine, owner, err);
}
fn resumeBody(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .before => {
            if (!temp.nullish(value) and scope.truthy(try scope.get(value, "cancel"))) return finish(engine, owner, false, try outcome(&scope, true, false));
            if (!temp.nullish(value) and scope.truthy(try scope.get(value, "summary")) and scope.truthy(try scope.get(try scope.get(owner, "options"), "summarize"))) {
                try scope.put(owner, "extensionSummary", try scope.get(value, "summary"));
                try scope.put(owner, "fromExtension", c.pi_js_bool(engine.context, 1));
            }
            inline for (.{ "customInstructions", "replaceInstructions", "label" }) |name| {
                const override = if (temp.nullish(value)) c.pi_js_undefined() else try scope.get(value, name);
                if (!c.JS_IsUndefined(override)) try scope.put(owner, name, try scope.get(value, name));
            }
            try prepareSummary(engine, owner);
        },
        .auth => try requestSummary(engine, owner, value),
        .summary => {
            if (scope.truthy(try scope.get(value, "aborted"))) return finish(engine, owner, false, try outcome(&scope, true, true));
            if (scope.truthy(try scope.get(value, "error"))) {
                const constructor = try scope.global("Error");
                return raiseWith(&scope, constructor, try scope.get(value, "error"));
            }
            try scope.put(owner, "summaryText", try scope.get(value, "summary"));
            try scope.put(owner, "summaryUsage", try scope.get(value, "usage"));
            const details = try scope.object();
            var read = try scope.get(value, "readFiles");
            if (!scope.truthy(read)) read = try scope.array();
            try scope.put(details, "readFiles", read);
            var modified = try scope.get(value, "modifiedFiles");
            if (!scope.truthy(modified)) modified = try scope.array();
            try scope.put(details, "modifiedFiles", modified);
            try scope.put(owner, "summaryDetails", details);
            try move(engine, owner);
        },
        .emitted => {
            const result = try scope.object();
            try scope.put(result, "editorText", try scope.get(owner, "editorText"));
            try scope.put(result, "cancelled", c.pi_js_bool(engine.context, 0));
            try scope.put(result, "summaryEntry", try scope.get(owner, "summaryEntry"));
            try finish(engine, owner, false, result);
        },
    }
}
fn prepareSummary(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    inline for (.{ "summaryText", "summaryDetails", "summaryUsage" }) |name| try scope.put(owner, name, c.pi_js_undefined());
    const extension = try scope.get(owner, "extensionSummary");
    if (scope.truthy(try scope.get(try scope.get(owner, "options"), "summarize")) and try scope.positive(try scope.get(try scope.get(owner, "entries"), "length")) and !scope.truthy(extension)) {
        const signal = try scope.get(try scope.get(session, "_branchSummaryAbortController"), "signal");
        try scope.put(owner, "signal", signal);
        try scope.put(owner, "branchSettings", try scope.invoke(try scope.get(session, "settingsManager"), "getBranchSummarySettings", &.{}));
        const auth = try scope.get(session, "_getSummarizationRequestAuth");
        return flow.wait(continueNavigation, engine, owner, try scope.call(auth, session, &.{ try scope.get(session, "model"), signal }), @intFromEnum(Stage.auth));
    } else if (scope.truthy(extension)) {
        try scope.put(owner, "summaryText", try scope.get(extension, "summary"));
        try scope.put(owner, "summaryDetails", try scope.get(extension, "details"));
        try scope.put(owner, "summaryUsage", try scope.get(extension, "usage"));
    }
    try move(engine, owner);
}
fn requestSummary(engine: *em.Engine, owner: c.JSValue, auth: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const options = try scope.own(try js.spread(engine, auth));
    inline for (.{ "signal", "customInstructions", "replaceInstructions" }) |name| try scope.put(options, name, try scope.get(owner, name));
    try scope.put(options, "reserveTokens", try scope.get(try scope.get(owner, "branchSettings"), "reserveTokens"));
    try scope.put(options, "streamFn", try scope.get(try scope.get(session, "agent"), "streamFunction"));
    try scope.put(options, "retry", try scope.invoke(try scope.get(session, "settingsManager"), "getRetrySettings", &.{}));
    const callback = try scope.get(session, "_summarizationRetryCallbacks");
    const source = try scope.object();
    try scope.put(source, "source", try scope.text("branchSummary"));
    try scope.put(options, "callbacks", try scope.call(callback, session, &.{source}));
    try flow.wait(continueNavigation, engine, owner, try scope.call(try scope.get(owner, "generate"), c.pi_js_undefined(), &.{ try scope.get(owner, "entries"), options }), @intFromEnum(Stage.summary));
}
fn move(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const target = try scope.get(owner, "targetEntry");
    var leaf: c.JSValue = undefined;
    var editor = c.pi_js_undefined();
    if (try is(&scope, try scope.get(target, "type"), "message") and try is(&scope, try scope.get(try scope.get(target, "message"), "role"), "user")) {
        leaf = try scope.get(target, "parentId");
        editor = try scope.own(try replay.contentTextWithSeparator(engine, try scope.get(try scope.get(target, "message"), "content"), try scope.text("")));
    } else if (try is(&scope, try scope.get(target, "type"), "custom_message")) {
        leaf = try scope.get(target, "parentId");
        editor = try scope.own(try replay.contentTextWithSeparator(engine, try scope.get(target, "content"), try scope.text("")));
    } else leaf = try scope.get(owner, "targetId");
    try scope.put(owner, "editorText", editor);
    const summary = try scope.get(owner, "summaryText");
    const label = try scope.get(owner, "label");
    var summary_entry = c.pi_js_undefined();
    if (scope.truthy(summary)) {
        const manager = try scope.get(session, "sessionManager");
        const branch = try scope.get(manager, "branchWithSummary");
        const summary_id = try scope.call(branch, manager, &.{ leaf, summary, try scope.get(owner, "summaryDetails"), try scope.get(owner, "fromExtension"), try scope.get(owner, "summaryUsage") });
        summary_entry = try scope.invoke(try scope.get(session, "sessionManager"), "getEntry", &.{summary_id});
        if (scope.truthy(label)) _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendLabelChange", &.{ summary_id, label });
    } else if (c.JS_IsNull(leaf)) {
        _ = try scope.invoke(try scope.get(session, "sessionManager"), "resetLeaf", &.{});
    } else _ = try scope.invoke(try scope.get(session, "sessionManager"), "branch", &.{leaf});
    if (scope.truthy(label) and !scope.truthy(summary)) _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendLabelChange", &.{ try scope.get(owner, "targetId"), label });
    try scope.put(owner, "summaryEntry", summary_entry);
    _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
    _ = try scope.invoke(session, "_restoreToolsFromTranscript", &.{});
    const runner = try scope.get(session, "_extensionRunner");
    const emit = try scope.get(runner, "emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("session_tree"));
    try scope.put(event, "newLeafId", try scope.invoke(try scope.get(session, "sessionManager"), "getLeafId", &.{}));
    try scope.put(event, "oldLeafId", try scope.get(owner, "oldLeafId"));
    try scope.put(event, "summaryEntry", summary_entry);
    try scope.put(event, "fromExtension", if (scope.truthy(summary)) try scope.get(owner, "fromExtension") else c.pi_js_undefined());
    try flow.wait(continueNavigation, engine, owner, try scope.call(emit, runner, &.{event}), @intFromEnum(Stage.emitted));
}
fn cleanup(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(owner, "finallyActive"))) return;
    try scope.put(owner, "finallyActive", c.pi_js_bool(engine.context, 0));
    const session = try scope.get(owner, "agent");
    try scope.set(session, "_branchSummaryAbortController", c.pi_js_undefined());
    _ = try scope.invoke(session, "_resolveIdleWaitIfIdle", &.{});
}
fn finish(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    try cleanup(engine, owner);
    try flow.settle(engine, owner, rejected, value);
}
fn rejectError(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    cleanup(engine, owner) catch |replacement| return flow.rejectError(engine, owner, replacement);
    try flow.settle(engine, owner, true, reason);
}

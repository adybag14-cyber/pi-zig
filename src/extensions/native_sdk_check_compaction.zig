//! Ordinary automatic compaction trigger/recovery selection. Shared classifiers,
//! context estimates and latest-boundary scan are the real native utilities.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const estimate = @import("native_sdk_session_estimate.zig");
const classifier = @import("native_ai_error_classification.zig");
const c = em.c;
const Stage = enum(c_int) { final, retry, failed };
const Predicate = enum(c_int) { projectedAssistant, assistantRole, contextEdit, assistantEdit, compaction, projectedEdit, entryId };
pub fn install(engine: *em.Engine, prototype: c.JSValue, dependencies: c.JSValue) !void {
    _ = try classifier.initialize(engine);
    var roots = [_]c.JSValue{dependencies};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "_checkCompaction", 1, 0, roots.len, &roots));
    defer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "_checkCompaction", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn callback(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, session, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), if (argc > 2) argv[2] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, session: c.JSValue, dependencies: c.JSValue, message: c.JSValue, skip: c.JSValue, tools: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, dependencies, message, skip, tools) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn settleFalse(engine: *em.Engine, owner: c.JSValue) !void {
    try flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
}
fn olderThanBoundary(scope: *Scope, message: c.JSValue, boundary: c.JSValue) !bool {
    const timestamp = try scope.get(message, "timestamp");
    const constructor = try scope.global("Date");
    var args = [_]c.JSValue{try scope.get(boundary, "timestamp")};
    const date = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, &args)));
    return arithmetic.compare(scope.engine, .less_equal, timestamp, try scope.invoke(date, "getTime", &.{}));
}
fn predicate(scope: *Scope, kind: Predicate, id: c.JSValue) !c.JSValue {
    var roots = [_]c.JSValue{id};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, predicateCallback, "", 1, @intFromEnum(kind), roots.len, &roots)));
}
fn predicateCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return predicateBody(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic), roots[0]) catch |err| sdk.fail(engine, err);
}
fn predicateBody(engine: *em.Engine, entry: c.JSValue, kind: Predicate, id: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = switch (kind) {
        .assistantRole => try is(&scope, try scope.get(entry, "role"), "assistant"),
        .contextEdit => try is(&scope, try scope.get(entry, "type"), "context_edit"),
        .compaction => try is(&scope, try scope.get(entry, "type"), "compaction"),
        .projectedEdit => try is(&scope, try scope.get(try scope.get(entry, "sourceEntry"), "type"), "context_edit"),
        .assistantEdit => try is(&scope, try scope.get(entry, "type"), "context_edit") and scope.equal(try scope.get(entry, "targetId"), id),
        .entryId => scope.equal(try scope.get(entry, "id"), id),
        .projectedAssistant => scope.equal(try scope.get(try scope.get(entry, "sourceEntry"), "id"), id) and try some(&scope, try scope.get(entry, "messages"), .assistantRole, id),
    };
    return c.pi_js_bool(engine.context, @intFromBool(result));
}
fn some(scope: *Scope, values: c.JSValue, kind: Predicate, id: c.JSValue) !bool {
    return scope.truthy(try withPredicate(scope, values, "some", kind, id));
}
fn withPredicate(scope: *Scope, values: c.JSValue, method: [*:0]const u8, kind: Predicate, id: c.JSValue) !c.JSValue {
    const function = try scope.get(values, method);
    return scope.call(function, values, &.{try predicate(scope, kind, id)});
}
fn start(engine: *em.Engine, owner: c.JSValue, dependencies: c.JSValue, message: c.JSValue, skip: c.JSValue, supplied_tools: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = if (c.JS_IsUndefined(supplied_tools)) try scope.array() else supplied_tools;
    const session = try scope.get(owner, "agent");
    const settings = try scope.invoke(try scope.get(session, "settingsManager"), "getCompactionSettings", &.{try scope.get(session, "model")});
    if (!scope.truthy(try scope.get(settings, "enabled"))) return settleFalse(engine, owner);
    if ((c.JS_IsUndefined(skip) or scope.truthy(skip)) and try is(&scope, try scope.get(message, "stopReason"), "aborted")) return settleFalse(engine, owner);
    const message_model = try scope.invoke(session, "_modelForMessage", &.{message});
    const same_model = !c.JS_IsUndefined(message_model);
    const limits_model = if (temp.nullish(message_model)) try scope.get(session, "model") else message_model;
    const context_window_raw = if (temp.nullish(limits_model)) c.pi_js_undefined() else try scope.get(limits_model, "contextWindow");
    const context_window = if (temp.nullish(context_window_raw)) c.JS_NewInt32(engine.context, 0) else context_window_raw;
    const boundary = try scope.own(try @import("native_sdk_session_statistics.zig").latestCompaction(engine, try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{})));
    if (!c.JS_IsNull(boundary) and try olderThanBoundary(&scope, message, boundary)) return settleFalse(engine, owner);
    const projection = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionProjection", &.{});
    const entry_id = try scope.invoke(session, "_findPersistedMessageEntryId", &.{message});
    const projected = c.JS_IsUndefined(entry_id) or try some(&scope, try scope.get(projection, "entries"), .projectedAssistant, entry_id);
    const branch = try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{});
    const index = if (scope.truthy(entry_id)) try withPredicate(&scope, branch, "findIndex", .entryId, entry_id) else c.JS_NewInt32(engine.context, -1);
    const after = if (try arithmetic.compare(engine, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) blk: {
        const slice = try scope.get(branch, "slice");
        break :blk try scope.call(slice, branch, &.{try scope.concat(index, c.JS_NewInt32(engine.context, 1))});
    } else try scope.array();
    const has_edit = try some(&scope, after, .contextEdit, entry_id);
    const filtered = try withPredicate(&scope, after, "filter", .assistantEdit, entry_id);
    const latest_edit = try scope.invoke(filtered, "at", &.{c.JS_NewInt32(engine.context, -1)});
    const retained = c.JS_IsUndefined(entry_id) or (!try some(&scope, after, .compaction, entry_id) and (temp.nullish(latest_edit) or !c.JS_IsNull(try scope.get(latest_edit, "replacement"))));
    const usage_matches = projected and !has_edit;
    const explicit = try is(&scope, try scope.get(message, "stopReason"), "error") and try classifier.overflow(engine, message, c.pi_js_undefined());
    const overflow = same_model and ((explicit and retained) or (usage_matches and try classifier.overflow(engine, message, context_window)));
    const length = same_model and projected and try classifier.recoverableLength(engine, message, try scope.get(message_model, "maxTokens"));
    if (overflow or length) {
        const retry = !try is(&scope, try scope.get(message, "stopReason"), "stop");
        if (!retry) return flow.wait(step, engine, owner, try scope.invoke(session, "_runAutoCompaction", &.{ try scope.text("overflow"), c.pi_js_bool(engine.context, 0) }), @intFromEnum(Stage.final));
        if (scope.truthy(try scope.get(session, "_overflowRecoveryAttempted"))) {
            const error_message = try scope.text(if (overflow) "Context overflow recovery failed after one compact-and-retry attempt. Try reducing context or switching to a larger-context model." else "Truncated response recovery failed after one compact-and-retry attempt.");
            const event = try scope.object();
            try scope.put(event, "type", try scope.text("compaction_end"));
            try scope.put(event, "reason", try scope.text("overflow"));
            try scope.put(event, "result", c.pi_js_undefined());
            try scope.put(event, "aborted", c.pi_js_bool(engine.context, 0));
            try scope.put(event, "willRetry", c.pi_js_bool(engine.context, 0));
            try scope.put(event, "errorMessage", error_message);
            _ = try scope.invoke(session, "_emit", &.{event});
            const failed = try scope.object();
            try scope.put(failed, "reason", try scope.text("overflow"));
            try scope.put(failed, "errorMessage", error_message);
            try scope.put(failed, "aborted", c.pi_js_bool(engine.context, 0));
            try scope.put(failed, "willRetry", c.pi_js_bool(engine.context, 0));
            try scope.put(failed, "fromExtension", c.pi_js_bool(engine.context, 0));
            return flow.wait(step, engine, owner, try scope.invoke(session, "_emitSessionCompactFailed", &.{failed}), @intFromEnum(Stage.failed));
        }
        try scope.set(session, "_overflowRecoveryAttempted", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(session, "_omitRecoveryAttempt", &.{ message, tools });
        try scope.put(owner, "message", message);
        return flow.wait(step, engine, owner, try scope.invoke(session, "_runAutoCompaction", &.{ try scope.text("overflow"), c.pi_js_bool(engine.context, @intFromBool(retry)) }), @intFromEnum(Stage.retry));
    }
    const has_context_edits = try some(&scope, try scope.get(projection, "entries"), .projectedEdit, entry_id);
    const direct_usage = try scope.get(message, "usage");
    const direct_tokens = if (scope.truthy(direct_usage)) try estimate.calculateContextTokens(&scope, try scope.get(message, "usage")) else c.JS_NewInt32(engine.context, 0);
    var context_tokens: c.JSValue = undefined;
    if (has_context_edits) {
        context_tokens = try scope.get(try scope.own(try estimate.estimate(engine, projection, branch)), "tokens");
    } else if (try is(&scope, try scope.get(message, "stopReason"), "error") or scope.equal(direct_tokens, c.JS_NewInt32(engine.context, 0))) {
        const messages = try scope.get(try scope.get(try scope.get(session, "agent"), "state"), "messages");
        const estimated = try scope.own(try estimate.estimateContext(engine, messages));
        const usage_index = try scope.get(estimated, "lastUsageIndex");
        if (!c.JS_IsNull(usage_index)) {
            const usage_message = try scope.own(try js.getKey(engine, messages, usage_index));
            if (scope.truthy(boundary) and try is(&scope, try scope.get(usage_message, "role"), "assistant") and try olderThanBoundary(&scope, usage_message, boundary)) return settleFalse(engine, owner);
        }
        context_tokens = try scope.get(estimated, "tokens");
    } else context_tokens = direct_tokens;
    if (scope.truthy(try scope.call(try scope.get(dependencies, "shouldCompact"), c.pi_js_undefined(), &.{ context_tokens, context_window, settings }))) return flow.wait(step, engine, owner, try scope.invoke(session, "_runAutoCompaction", &.{ try scope.text("threshold"), c.pi_js_bool(engine.context, 0) }), @intFromEnum(Stage.final));
    try settleFalse(engine, owner);
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage_value: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    const stage: Stage = @enumFromInt(stage_value);
    if (stage == .failed) return settleFalse(engine, owner);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == .retry and scope.truthy(value)) try scope.set(try scope.get(owner, "agent"), "_failedResponse", try scope.get(owner, "message"));
    try flow.settle(engine, owner, false, value);
}

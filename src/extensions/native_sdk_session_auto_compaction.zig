//! Ordinary automatic threshold/overflow compaction, retaining live fields and
//! the caller's shared _runDefaultCompaction binding. No failed run is retried here.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Stage = enum(c_int) { extension, summary, saved, failed };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, dispatch, "_runAutoCompaction", 2));
    defer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "_runAutoCompaction", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, session, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, session: c.JSValue, reason: c.JSValue, retry: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, reason, retry) catch |err| try handle(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue, retry: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "reason", reason);
    try scope.put(owner, "retry", retry);
    try scope.put(owner, "controller", c.pi_js_undefined());
    try scope.put(owner, "started", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "fromExtension", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "cancelled", c.pi_js_bool(engine.context, 0));
    const session = try scope.get(owner, "agent");
    const model = try scope.get(session, "model");
    const settings = try scope.invoke(try scope.get(session, "settingsManager"), "getCompactionSettings", &.{model});
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 1));
    if (!scope.truthy(model)) return finish(engine, owner, false, c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "model", model);
    const entries = try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{});
    const preparation = try scope.own(try @import("native_sdk_compaction_prepare.zig").prepare(engine, entries, settings));
    if (!scope.truthy(preparation)) return finish(engine, owner, false, c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "preparation", preparation);
    const constructor = try scope.global("AbortController");
    const controller = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    try scope.put(owner, "controller", controller);
    try scope.set(session, "_autoCompactionAbortController", controller);
    try scope.put(owner, "started", c.pi_js_bool(engine.context, 1));
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("compaction_start"));
    try scope.put(event, "reason", reason);
    _ = try scope.invoke(session, "_emit", &.{event});
    try checkAbort(&scope, owner);
    if (scope.truthy(try scope.invoke(try scope.get(session, "_extensionRunner"), "hasHandlers", &.{try scope.text("session_before_compact")}))) {
        const runner = try scope.get(session, "_extensionRunner");
        const emit = try scope.get(runner, "emit");
        const before = try scope.object();
        try scope.put(before, "type", try scope.text("session_before_compact"));
        try scope.put(before, "preparation", preparation);
        try scope.put(before, "branchEntries", entries);
        try scope.put(before, "customInstructions", c.pi_js_undefined());
        try scope.put(before, "reason", reason);
        try scope.put(before, "willRetry", retry);
        try scope.put(before, "signal", try scope.get(controller, "signal"));
        try flow.wait(step, engine, owner, try scope.call(emit, runner, &.{before}), @intFromEnum(Stage.extension));
    } else try summarize(engine, owner, c.pi_js_undefined());
}
fn checkAbort(scope: *Scope, owner: c.JSValue) !void {
    _ = try scope.invoke(try scope.get(try scope.get(owner, "controller"), "signal"), "throwIfAborted", &.{});
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    advance(engine, owner, value, rejected, @enumFromInt(magic)) catch |err| try handle(engine, owner, err);
}
fn handle(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    const phase = try sdk.get(engine, owner, "phase");
    defer engine.freeValue(phase);
    if (c.JS_IsStrictEqual(engine.context, phase, c.JS_NewInt32(engine.context, 1))) {
        caught(engine, owner, reason) catch |failure| {
            const replacement = flow.reason(engine, failure);
            defer engine.freeValue(replacement);
            try finish(engine, owner, true, replacement);
        };
    } else if (c.JS_IsStrictEqual(engine.context, phase, c.JS_NewInt32(engine.context, 2))) try finish(engine, owner, true, reason) else try flow.settle(engine, owner, true, reason);
}
fn raise(scope: *Scope, bytes: []const u8) anyerror {
    const constructor = scope.global("Error") catch |err| return err;
    var args = [_]c.JSValue{scope.text(bytes) catch |err| return err};
    const exception = scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)) catch |err| return err;
    return throwValue(scope.engine, exception, true);
}
fn throwValue(engine: *em.Engine, value: c.JSValue, owned: bool) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, if (owned) value else c.JS_DupValue(engine.context, value))) catch |err| return err;
    unreachable;
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    if (stage == .failed) return finish(engine, owner, rejected, if (rejected) value else c.pi_js_bool(engine.context, 0));
    if (rejected) return throwValue(engine, value, false);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .extension => {
            if (!temp.nullish(value) and scope.truthy(try scope.get(value, "cancel"))) {
                try scope.put(owner, "cancelled", c.pi_js_bool(engine.context, 1));
                return raise(&scope, "Compaction cancelled");
            }
            var custom = c.pi_js_undefined();
            if (!temp.nullish(value) and scope.truthy(try scope.get(value, "compaction"))) {
                custom = try scope.get(value, "compaction");
                try scope.put(owner, "fromExtension", c.pi_js_bool(engine.context, 1));
            }
            try summarize(engine, owner, custom);
        },
        .summary => try persist(engine, owner, value),
        .saved => try success(engine, owner),
        else => unreachable,
    }
}
fn summarize(engine: *em.Engine, owner: c.JSValue, custom: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try checkAbort(&scope, owner);
    if (scope.truthy(custom)) return persist(engine, owner, custom);
    const session = try scope.get(owner, "agent");
    const function = try scope.get(session, "_runDefaultCompaction");
    const value = try scope.call(function, session, &.{ try scope.get(owner, "preparation"), try scope.get(owner, "model"), c.pi_js_undefined(), try scope.get(try scope.get(owner, "controller"), "signal"), try scope.get(owner, "reason") });
    try flow.wait(step, engine, owner, value, @intFromEnum(Stage.summary));
}
fn findSaved(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entry = if (argc > 0) argv[0] else c.pi_js_undefined();
    const kind = scope.get(entry, "type") catch |err| return sdk.fail(engine, err);
    const text = scope.text("compaction") catch |err| return sdk.fail(engine, err);
    if (!scope.equal(kind, text)) return c.pi_js_bool(engine.context, 0);
    const summary = scope.get(entry, "summary") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(summary, roots[0])));
}
fn persist(engine: *em.Engine, owner: c.JSValue, result: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const saved = try scope.object();
    inline for (.{ "summary", "firstKeptEntryId", "tokensBefore", "usage", "details" }) |key| try scope.put(saved, key, try scope.get(result, key));
    try scope.put(owner, "result", saved);
    try checkAbort(&scope, owner);
    _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendCompaction", &.{ try scope.get(saved, "summary"), try scope.get(saved, "firstKeptEntryId"), try scope.get(saved, "tokensBefore"), try scope.get(saved, "details"), try scope.get(owner, "fromExtension"), try scope.get(saved, "usage") });
    const entries = try scope.invoke(try scope.get(session, "sessionManager"), "getEntries", &.{});
    _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
    const projection = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionProjection", &.{});
    const messages = try scope.get(projection, "messages");
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, messages, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var tokens = c.JS_NewInt32(engine.context, 0);
    while (try iterator.next()) |message| {
        defer engine.freeValue(message);
        tokens = try scope.concat(tokens, try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, message)));
    }
    try scope.put(saved, "estimatedTokensAfter", tokens);
    const find = try scope.get(entries, "find");
    var roots = [_]c.JSValue{try scope.get(saved, "summary")};
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, findSaved, "", 1, 0, roots.len, &roots)));
    const entry = try scope.call(find, entries, &.{predicate});
    if (scope.truthy(try scope.get(session, "_extensionRunner")) and scope.truthy(entry)) {
        const runner = try scope.get(session, "_extensionRunner");
        const emit = try scope.get(runner, "emit");
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("session_compact"));
        try scope.put(event, "compactionEntry", entry);
        try scope.put(event, "fromExtension", try scope.get(owner, "fromExtension"));
        try scope.put(event, "reason", try scope.get(owner, "reason"));
        try scope.put(event, "willRetry", try scope.get(owner, "retry"));
        try flow.wait(step, engine, owner, try scope.call(emit, runner, &.{event}), @intFromEnum(Stage.saved));
    } else try success(engine, owner);
}
fn success(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const saved = try scope.get(owner, "result");
    const result = try scope.object();
    inline for (.{ "summary", "firstKeptEntryId", "tokensBefore", "estimatedTokensAfter", "usage", "details" }) |key| try scope.put(result, key, try scope.get(saved, key));
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("compaction_end"));
    try scope.put(event, "reason", try scope.get(owner, "reason"));
    try scope.put(event, "result", result);
    try scope.put(event, "aborted", c.pi_js_bool(engine.context, 0));
    try scope.put(event, "willRetry", try scope.get(owner, "retry"));
    _ = try scope.invoke(session, "_emit", &.{event});
    const retry = scope.truthy(try scope.get(owner, "retry"));
    const continuation = if (retry) c.pi_js_bool(engine.context, 1) else try scope.invoke(try scope.get(session, "agent"), "hasQueuedMessages", &.{});
    try finish(engine, owner, false, continuation);
}
fn caught(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 2));
    const session = try scope.get(owner, "agent");
    const constructor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(engine.context, reason, constructor);
    if (instance < 0) return js.capture(engine);
    const message = if (instance != 0) try scope.get(reason, "message") else try scope.text("compaction failed");
    const controller = try scope.get(owner, "controller");
    const cancelled = (!temp.nullish(controller) and scope.equal(try scope.get(try scope.get(controller, "signal"), "aborted"), c.pi_js_bool(engine.context, 1))) or scope.truthy(try scope.get(owner, "cancelled"));
    if (scope.truthy(try scope.get(owner, "started"))) {
        const error_message = if (cancelled) c.pi_js_undefined() else try scope.concat(try scope.text(if (scope.equal(try scope.get(owner, "reason"), try scope.text("overflow"))) "Context overflow recovery failed: " else "Auto-compaction failed: "), try scope.stringify(message));
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("compaction_end"));
        try scope.put(event, "reason", try scope.get(owner, "reason"));
        try scope.put(event, "result", c.pi_js_undefined());
        try scope.put(event, "aborted", c.pi_js_bool(engine.context, @intFromBool(cancelled)));
        try scope.put(event, "willRetry", c.pi_js_bool(engine.context, 0));
        try scope.put(event, "errorMessage", error_message);
        _ = try scope.invoke(session, "_emit", &.{event});
        const details = try scope.object();
        try scope.put(details, "reason", try scope.get(owner, "reason"));
        try scope.put(details, "errorMessage", error_message);
        try scope.put(details, "aborted", c.pi_js_bool(engine.context, @intFromBool(cancelled)));
        try scope.put(details, "willRetry", c.pi_js_bool(engine.context, 0));
        try scope.put(details, "fromExtension", try scope.get(owner, "fromExtension"));
        try flow.wait(step, engine, owner, try scope.invoke(session, "_emitSessionCompactFailed", &.{details}), @intFromEnum(Stage.failed));
    } else try finish(engine, owner, false, c.pi_js_bool(engine.context, 0));
}
fn finish(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 3));
    const session = try scope.get(owner, "agent");
    const controller = try scope.get(owner, "controller");
    finalize(&scope, session, controller) catch |err| return flow.rejectError(engine, owner, err);
    try flow.settle(engine, owner, rejected, value);
}
fn finalize(scope: *Scope, session: c.JSValue, controller: c.JSValue) !void {
    if (scope.equal(try scope.get(session, "_autoCompactionAbortController"), controller)) try scope.set(session, "_autoCompactionAbortController", c.pi_js_undefined());
    _ = try scope.invoke(session, "_resolveIdleWaitIfIdle", &.{});
}

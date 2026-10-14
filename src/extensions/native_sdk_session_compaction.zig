//! Ordinary manual session compaction. The summary function is the captured
//! actual module binding, shared with automatic compaction by the assembler.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum(c_int) { _runDefaultCompaction, _clearManualCompactionState, compact, _emitSessionCompactFailed, _refreshFinalizedContext };
const Stage = enum(c_int) { auth, aborted, extension, summary, saved, failed };
pub fn install(engine: *em.Engine, prototype: c.JSValue, compact_summary: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, compact_summary)) return error.RequiredSharedNativeCompactionBinding;
    inline for (std.meta.fields(Method)) |field| {
        var roots = [_]c.JSValue{compact_summary};
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            ._runDefaultCompaction => 5,
            .compact, ._emitSessionCompactFailed => 1,
            else => 0,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, length, field.value, roots.len, &roots));
        defer engine.freeValue(function);
        if (field.value == 0 or field.value == 2 or field.value == 3) {
            const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(parent);
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (switch (@as(Method, @enumFromInt(magic))) {
        ._runDefaultCompaction => defaultSummary(engine, session, roots[0], args),
        ._clearManualCompactionState => clear(engine, session),
        .compact => manual(engine, session, argument(args, 0)),
        ._emitSessionCompactFailed => emitFailed(engine, session, argument(args, 0)),
        ._refreshFinalizedContext => refresh(engine, session),
    }) catch |err| sdk.fail(engine, err);
}
fn clear(engine: *em.Engine, session: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(session, "_compactionAbortController", c.pi_js_undefined());
    _ = try scope.invoke(session, "_resolveIdleWaitIfIdle", &.{});
    return c.pi_js_undefined();
}
fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn controllerSignal(scope: *Scope, session: c.JSValue) !c.JSValue {
    const controller = try scope.get(session, "_compactionAbortController");
    // Preserve the upstream runtime's property-read diagnostic when an end
    // listener throws after idle state has already cleared this controller.
    // Do not turn that missing controller into a successful cancellation.
    if (c.JS_IsUndefined(controller)) return js.typeError(scope.engine, "Cannot read properties of undefined (reading 'signal')");
    if (c.JS_IsNull(controller)) return js.typeError(scope.engine, "Cannot read properties of null (reading 'signal')");
    return scope.get(controller, "signal");
}
fn refresh(engine: *em.Engine, session: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const projection = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionProjection", &.{});
    var entries = try iterator(&scope, try scope.get(projection, "entries"));
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer engine.freeValue(entry);
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        var messages = try iterator(&frame, try frame.get(entry, "messages"));
        defer messages.deinit();
        errdefer messages.closePreserving();
        while (try messages.next()) |message| {
            defer engine.freeValue(message);
            var item: Scope = .{ .engine = engine };
            defer item.deinit();
            const ids = try item.get(session, "_entryIdsByMessage");
            const set = try item.get(ids, "set");
            _ = try item.call(set, ids, &.{ message, try item.get(try item.get(entry, "sourceEntry"), "id") });
        }
    }
    const state = try scope.get(try scope.get(session, "agent"), "state");
    try scope.set(state, "messages", try scope.get(projection, "messages"));
    return c.pi_js_undefined();
}
fn defaultSummary(engine: *em.Engine, session: c.JSValue, compact_summary: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    defaultStart(engine, pending.owner, compact_summary, args) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn defaultStart(engine: *em.Engine, owner: c.JSValue, compact_summary: c.JSValue, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const saved = try scope.array();
    for (0..5) |index| try scope.index(saved, @intCast(index), argument(args, index));
    try scope.put(owner, "args", saved);
    try scope.put(owner, "compact", compact_summary);
    try flow.wait(defaultDone, engine, owner, try scope.invoke(try scope.get(owner, "agent"), "_getSummarizationRequestAuth", &.{ argument(args, 1), argument(args, 3) }), 0);
}
fn at(scope: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, index)));
}
fn defaultDone(engine: *em.Engine, owner: c.JSValue, request: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, request);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const compact_summary = try scope.get(owner, "compact");
    const session = try scope.get(owner, "agent");
    const saved = try scope.get(owner, "args");
    var args: [12]c.JSValue = undefined;
    args[0] = try at(&scope, saved, 0);
    args[1] = try scope.get(request, "model");
    args[2] = try scope.get(request, "apiKey");
    args[3] = try scope.get(request, "headers");
    args[4] = try at(&scope, saved, 2);
    args[5] = try at(&scope, saved, 3);
    args[6] = try scope.get(request, "thinkingLevel");
    args[7] = try scope.get(try scope.get(session, "agent"), "streamFunction");
    args[8] = try scope.get(request, "env");
    args[9] = try scope.invoke(try scope.get(session, "settingsManager"), "getRetrySettings", &.{});
    const input = try scope.object();
    try scope.put(input, "source", try scope.text("compaction"));
    try scope.put(input, "reason", try at(&scope, saved, 4));
    args[10] = try scope.invoke(session, "_summarizationRetryCallbacks", &.{input});
    args[11] = c.pi_js_undefined();
    try flow.settle(engine, owner, false, try scope.call(compact_summary, c.pi_js_undefined(), &args));
}
fn emitFailed(engine: *em.Engine, session: c.JSValue, event: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    emitFailedStart(engine, pending.owner, event) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn emitFailedStart(engine: *em.Engine, owner: c.JSValue, event: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    if (!scope.truthy(try scope.invoke(try scope.get(session, "_extensionRunner"), "hasHandlers", &.{try scope.text("session_compact_failed")}))) return flow.settle(engine, owner, false, c.pi_js_undefined());
    const runner = try scope.get(session, "_extensionRunner");
    const emit = try scope.get(runner, "emit");
    const input = try scope.object();
    try scope.put(input, "type", try scope.text("session_compact_failed"));
    try js.spreadInto(engine, input, event);
    try flow.wait(failedDone, engine, owner, try scope.call(emit, runner, &.{input}), 0);
}
fn failedDone(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}
fn raise(scope: *Scope, bytes: []const u8) anyerror {
    const ctor = scope.global("Error") catch |err| return err;
    var args = [_]c.JSValue{scope.text(bytes) catch |err| return err};
    const exception = scope.engine.checked(c.JS_CallConstructor(scope.engine.context, ctor, args.len, &args)) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, exception)) catch |err| return err;
    unreachable;
}
fn throwValue(engine: *em.Engine, value: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value))) catch |err| return err;
    unreachable;
}
fn manual(engine: *em.Engine, session: c.JSValue, instructions: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    manualStart(engine, pending.owner, instructions) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn manualStart(engine: *em.Engine, owner: c.JSValue, instructions: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "instructions", instructions);
    try scope.put(owner, "fromExtension", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "cancelled", c.pi_js_bool(engine.context, 0));
    try flow.wait(step, engine, owner, try scope.invoke(try scope.get(owner, "agent"), "abort", &.{}), @intFromEnum(Stage.aborted));
}
fn step(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    advance(engine, owner, value, rejected, @enumFromInt(magic)) catch |err| {
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        const phase = try sdk.get(engine, owner, "phase");
        defer engine.freeValue(phase);
        if (c.JS_IsStrictEqual(engine.context, phase, c.JS_NewInt32(engine.context, 1))) {
            caught(engine, owner, reason) catch |failure| {
                const replacement = flow.reason(engine, failure);
                defer engine.freeValue(replacement);
                try finallyReject(engine, owner, replacement);
            };
        } else if (c.JS_IsStrictEqual(engine.context, phase, c.JS_NewInt32(engine.context, 2))) {
            try finallyReject(engine, owner, reason);
        } else try flow.settle(engine, owner, true, reason);
    };
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    if (stage == .failed) {
        if (rejected) return finallyReject(engine, owner, value);
        const original = try sdk.get(engine, owner, "failure");
        defer engine.freeValue(original);
        return finallyReject(engine, owner, original);
    }
    if (rejected) return throwValue(engine, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    switch (stage) {
        .aborted => {
            const abort_ctor = try scope.global("AbortController");
            const controller = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, abort_ctor, 0, null)));
            try scope.set(session, "_compactionAbortController", controller);
            const start = try scope.object();
            try scope.put(start, "type", try scope.text("compaction_start"));
            try scope.put(start, "reason", try scope.text("manual"));
            _ = try scope.invoke(session, "_emit", &.{start});
            try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 1));
            const model = try scope.get(session, "model");
            if (!scope.truthy(model)) {
                try @import("native_sdk_prompt_auth.zig").noModel(engine);
                unreachable;
            }
            try scope.put(owner, "model", model);
            const settings = try scope.invoke(try scope.get(session, "settingsManager"), "getCompactionSettings", &.{model});
            const entries = try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{});
            try scope.put(owner, "entries", entries);
            const preparation = try scope.own(try @import("native_sdk_compaction_prepare.zig").prepare(engine, entries, settings));
            if (!scope.truthy(preparation)) {
                const last_index = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try scope.get(entries, "length"), c.JS_NewInt32(engine.context, 1))));
                const atom = try js.atom(engine, last_index);
                defer c.JS_FreeAtom(engine.context, atom);
                const last = try scope.own(try engine.checked(c.JS_GetProperty(engine.context, entries, atom)));
                if (!temp.nullish(last) and scope.equal(try scope.get(last, "type"), try scope.text("compaction"))) return raise(&scope, "Already compacted");
                return raise(&scope, "Nothing to compact (session too small)");
            }
            try scope.put(owner, "preparation", preparation);
            if (scope.truthy(try scope.invoke(try scope.get(session, "_extensionRunner"), "hasHandlers", &.{try scope.text("session_before_compact")}))) {
                const runner = try scope.get(session, "_extensionRunner");
                const emit = try scope.get(runner, "emit");
                const before = try scope.object();
                try scope.put(before, "type", try scope.text("session_before_compact"));
                try scope.put(before, "preparation", preparation);
                try scope.put(before, "branchEntries", entries);
                try scope.put(before, "customInstructions", try scope.get(owner, "instructions"));
                try scope.put(before, "reason", try scope.text("manual"));
                try scope.put(before, "willRetry", c.pi_js_bool(engine.context, 0));
                try scope.put(before, "signal", try controllerSignal(&scope, session));
                try flow.wait(step, engine, owner, try scope.call(emit, runner, &.{before}), @intFromEnum(Stage.extension));
            } else try startSummary(engine, owner, c.pi_js_undefined());
        },
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
            try startSummary(engine, owner, custom);
        },
        .summary => try persist(engine, owner, value),
        .saved => try finishManual(engine, owner),
        else => unreachable,
    }
}
fn startSummary(engine: *em.Engine, owner: c.JSValue, custom: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(custom)) return persist(engine, owner, custom);
    const session = try scope.get(owner, "agent");
    const function = try scope.get(session, "_runDefaultCompaction");
    const value = try scope.call(function, session, &.{ try scope.get(owner, "preparation"), try scope.get(owner, "model"), try scope.get(owner, "instructions"), try controllerSignal(&scope, session), try scope.text("manual") });
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
    if (scope.truthy(try scope.get(try controllerSignal(&scope, session), "aborted"))) return raise(&scope, "Compaction cancelled");
    _ = try scope.invoke(try scope.get(session, "sessionManager"), "appendCompaction", &.{ try scope.get(saved, "summary"), try scope.get(saved, "firstKeptEntryId"), try scope.get(saved, "tokensBefore"), try scope.get(saved, "details"), try scope.get(owner, "fromExtension"), try scope.get(saved, "usage") });
    const entries = try scope.invoke(try scope.get(session, "sessionManager"), "getEntries", &.{});
    _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
    const projection = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionProjection", &.{});
    var messages = try iterator(&scope, try scope.get(projection, "messages"));
    defer messages.deinit();
    errdefer messages.closePreserving();
    var tokens = c.JS_NewInt32(engine.context, 0);
    while (try messages.next()) |message| {
        defer engine.freeValue(message);
        const estimate = try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, message));
        tokens = try scope.concat(tokens, estimate);
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
        try scope.put(event, "reason", try scope.text("manual"));
        try scope.put(event, "willRetry", c.pi_js_bool(engine.context, 0));
        try flow.wait(step, engine, owner, try scope.call(emit, runner, &.{event}), @intFromEnum(Stage.saved));
    } else try finishManual(engine, owner);
}
fn finishManual(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const saved = try scope.get(owner, "result");
    const result = try scope.object();
    inline for (.{ "summary", "firstKeptEntryId", "tokensBefore", "estimatedTokensAfter", "usage", "details" }) |key| try scope.put(result, key, try scope.get(saved, key));
    _ = try scope.invoke(session, "_clearManualCompactionState", &.{});
    const emit = try scope.get(session, "_emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("compaction_end"));
    try scope.put(event, "reason", try scope.text("manual"));
    try scope.put(event, "result", result);
    try scope.put(event, "aborted", c.pi_js_bool(engine.context, 0));
    try scope.put(event, "willRetry", c.pi_js_bool(engine.context, 0));
    _ = try scope.call(emit, session, &.{event});
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 3));
    _ = try scope.invoke(session, "_clearManualCompactionState", &.{});
    try flow.settle(engine, owner, false, result);
}
fn finallyReject(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 3));
    const session = try scope.get(owner, "agent");
    _ = scope.invoke(session, "_clearManualCompactionState", &.{}) catch |err| return flow.rejectError(engine, owner, err);
    try flow.settle(engine, owner, true, reason);
}
fn caught(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 2));
    try scope.put(owner, "failure", reason);
    const session = try scope.get(owner, "agent");
    const error_ctor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(engine.context, reason, error_ctor);
    if (instance < 0) return js.capture(engine);
    const message = if (instance != 0) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
    const signal_aborted = try scope.get(try controllerSignal(&scope, session), "aborted");
    const aborted = if (scope.truthy(signal_aborted)) signal_aborted else try scope.get(owner, "cancelled");
    const error_message = if (scope.truthy(aborted)) c.pi_js_undefined() else try scope.concat(try scope.text("Compaction failed: "), try scope.stringify(message));
    _ = try scope.invoke(session, "_clearManualCompactionState", &.{});
    const emit = try scope.get(session, "_emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("compaction_end"));
    try scope.put(event, "reason", try scope.text("manual"));
    try scope.put(event, "result", c.pi_js_undefined());
    try scope.put(event, "aborted", aborted);
    try scope.put(event, "willRetry", c.pi_js_bool(engine.context, 0));
    try scope.put(event, "errorMessage", error_message);
    _ = try scope.call(emit, session, &.{event});
    const failed = try scope.get(session, "_emitSessionCompactFailed");
    const details = try scope.object();
    try scope.put(details, "reason", try scope.text("manual"));
    try scope.put(details, "errorMessage", error_message);
    try scope.put(details, "aborted", aborted);
    try scope.put(details, "willRetry", c.pi_js_bool(engine.context, 0));
    try scope.put(details, "fromExtension", try scope.get(owner, "fromExtension"));
    try flow.wait(step, engine, owner, try scope.call(failed, session, &.{details}), @intFromEnum(Stage.failed));
}

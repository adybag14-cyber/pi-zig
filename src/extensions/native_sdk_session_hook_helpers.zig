//! Four actual AgentSession async helper bodies. Constructor-installed hook
//! closures are a separate migration surface; no outer flow Promise is used.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const async_body = @import("native_async_body.zig");
const af = async_body.native;
const functions = @import("native_node_function.zig");
const c = em.c;
pub const Kind = enum { _beforeToolCall, _afterToolCall, _compactBeforeNextAssistantResponse, _dispatchTurnEndBoundary };
const Stage = enum(c_int) { before, after_hook, after_normalize, compact, boundary };

pub fn create(engine: *em.Engine, comptime kind: Kind, dependencies: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const imports = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    if (kind == ._afterToolCall) {
        const normalize = try scope.get(dependencies, "normalizeToolResultImages");
        if (!c.JS_IsFunction(engine.context, normalize)) return error.ActualToolResultNormalizerRequired;
        try scope.put(imports, "normalizeToolResultImages", normalize);
    }
    const Adapter = struct {
        fn body(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
            const generation = host.native_allocation_generation;
            return bodyWithSourceCatch(host, kind, receiver, args, roots[0], state, completion, input) catch |err| {
                try trustedBoundary(host, err, generation);
                return async_body.failureSince(host, err, generation);
            };
        }
    };
    return af.createResumable(engine, @tagName(kind), if (kind == ._compactBeforeNextAssistantResponse) 1 else 2, Adapter.body, &.{imports});
}
fn trustedBoundary(engine: *em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        try async_body.rethrowRecognizedAllocation(engine, reason, generation);
    };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn returned(engine: *em.Engine, value: c.JSValue) af.Action {
    return .{ .returned = c.JS_DupValue(engine.context, value) };
}
fn thrown(engine: *em.Engine, value: c.JSValue) af.Action {
    return .{ .thrown = c.JS_DupValue(engine.context, value) };
}
fn waitAt(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !af.Action {
    try scope.put(owner, "nativeAsyncStage", c.JS_NewInt32(scope.engine.context, @intFromEnum(stage)));
    return .{ .awaited = c.JS_DupValue(scope.engine.context, value) };
}
fn bodyWithSourceCatch(engine: *em.Engine, kind: Kind, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .rejected) {
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(state.*, "nativeGeneration")) < 0) return js.capture(engine);
        try async_body.rethrowRecognizedAllocation(engine, input, generation);
        if (c.JS_IsUncatchableError(input)) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, input)));
            unreachable;
        }
        // This is the Source catch body itself. A failure constructing its
        // replacement escapes only to the outer trusted invocation wrapper.
        if (kind == ._beforeToolCall and scope.truthy(try scope.get(state.*, "toolCallTry"))) return beforeFailure(&scope, input);
        return thrown(engine, input);
    }
    const generation = engine.native_allocation_generation;
    return resume(&scope, kind, receiver, args, imports, state, completion, input) catch |err| {
        try trustedBoundary(engine, err, generation);
        if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return error.ActualHookExceptionRequired;
        if (c.JS_IsUncatchableError(reason)) return err;
        // Source has consumed this ordinary catch. Transfer its root before
        // invoking guest Error/String hooks, which may capture the same value
        // again. Only this local root is retired after those callbacks.
        engine.captured_exception = null;
        defer engine.freeValue(reason);
        if (engine.last_error) |message| engine.gpa.free(message);
        engine.last_error = null;
        if (kind != ._beforeToolCall or c.JS_IsUndefined(state.*) or !scope.truthy(try scope.get(state.*, "toolCallTry"))) return thrown(engine, reason);
        return beforeFailure(&scope, reason);
    };
}
fn resume(scope: *Scope, kind: Kind, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const engine = scope.engine;
    if (completion == .start) {
        const generation = engine.native_allocation_generation;
        const owner = try async_body.init(scope, state);
        try scope.put(owner, "agent", receiver);
        try scope.put(owner, "input", arg(args, 0));
        try scope.put(owner, "second", arg(args, 1));
        try scope.put(owner, "nativeGeneration", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
        return switch (kind) {
            ._beforeToolCall, ._afterToolCall => startTool(scope, owner, kind, imports),
            ._compactBeforeNextAssistantResponse => startCompaction(scope, owner),
            ._dispatchTurnEndBoundary => startBoundary(scope, owner),
        };
    }
    const owner = state.*;
    const stage: Stage = @enumFromInt(try async_body.stage(scope, owner));
    return switch (stage) {
        .before => returned(engine, input),
        .after_hook => blk: {
            try scope.put(owner, "hookResult", input);
            break :blk normalizeResult(scope, owner, imports);
        },
        .after_normalize => returned(engine, try normalizedResult(scope, owner, input)),
        .compact => blk: {
            const context = try scope.own(try js.spread(engine, try scope.get(owner, "input")));
            try scope.put(context, "messages", try scope.get(try scope.invoke(try scope.get(receiver, "sessionManager"), "buildSessionProjection", &.{}), "messages"));
            break :blk returned(engine, context);
        },
        .boundary => finishBoundary(scope, owner, input),
    };
}
fn startTool(scope: *Scope, owner: c.JSValue, kind: Kind, imports: c.JSValue) !af.Action {
    const engine = scope.engine;
    const input = try scope.get(owner, "input");
    // Source parameter destructuring precedes runner lookup and its try.
    const tool_call = try scope.get(input, "toolCall");
    const args = try scope.get(input, "args");
    const before = kind == ._beforeToolCall;
    var result = c.pi_js_undefined();
    var is_error = c.pi_js_undefined();
    if (!before) {
        result = try scope.get(input, "result");
        is_error = try scope.get(input, "isError");
        try scope.put(owner, "result", result);
        try scope.put(owner, "isError", is_error);
    }
    const runner = try scope.get(try scope.get(owner, "agent"), "_extensionRunner");
    const has = scope.truthy(try scope.invoke(runner, "hasHandlers", &.{try scope.text(if (before) "tool_call" else "tool_result")}));
    if (!has) {
        if (before) return returned(engine, c.pi_js_undefined());
        try scope.put(owner, "hookResult", c.pi_js_undefined());
        // Source's conditional expression performs no await on this path.
        return normalizeResult(scope, owner, imports);
    }
    if (before) try scope.put(owner, "toolCallTry", c.pi_js_bool(engine.context, 1));
    const emit = try scope.get(runner, if (before) "emitToolCall" else "emitToolResult");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text(if (before) "tool_call" else "tool_result"));
    try scope.put(event, "toolName", try scope.get(tool_call, "name"));
    try scope.put(event, "toolCallId", try scope.get(tool_call, "id"));
    const parent = try scope.get(owner, "second");
    if (scope.truthy(parent)) try scope.put(event, "parentToolCallId", parent);
    try scope.put(event, "input", args);
    if (!before) {
        inline for (.{ "content", "details" }) |name| try scope.put(event, name, try scope.get(result, name));
        const structured = try scope.get(result, "structuredContent");
        if (!c.JS_IsUndefined(structured)) try scope.put(event, "structuredContent", try scope.get(result, "structuredContent"));
        try scope.put(event, "isError", is_error);
        try scope.put(event, "usage", try scope.get(result, "usage"));
    }
    return waitAt(scope, owner, try scope.call(emit, runner, &.{event}), if (before) .before else .after_hook);
}
fn beforeFailure(scope: *Scope, reason: c.JSValue) !af.Action {
    const engine = scope.engine;
    const error_class = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(engine.context, reason, error_class);
    if (instance < 0) return js.capture(engine);
    if (instance != 0) return thrown(engine, reason);
    const constructor = try scope.global("Error");
    const converted = try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason});
    const message = try scope.concat(try scope.text("Extension failed, blocking execution: "), try scope.stringify(converted));
    var args = [_]c.JSValue{message};
    return thrown(engine, try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args))));
}
fn normalizeResult(scope: *Scope, owner: c.JSValue, imports: c.JSValue) !af.Action {
    const session = try scope.get(owner, "agent");
    const hook = try scope.get(owner, "hookResult");
    var content = if (temp.nullish(hook)) c.pi_js_undefined() else try scope.get(hook, "content");
    if (temp.nullish(content)) content = try scope.get(try scope.get(owner, "result"), "content");
    if (temp.nullish(content)) content = try scope.array();
    try scope.put(owner, "content", content);
    const limits_model = try scope.invoke(session, "_limitsModel", &.{});
    const limits = if (temp.nullish(limits_model)) c.pi_js_undefined() else try scope.get(limits_model, "inputLimits");
    const images = if (temp.nullish(limits)) c.pi_js_undefined() else try scope.get(limits, "images");
    const resize = if (temp.nullish(images)) c.pi_js_undefined() else try scope.get(images, "resize");
    const normalize = try scope.get(imports, "normalizeToolResultImages");
    const options = try scope.object();
    try scope.put(options, "autoResizeImages", try scope.invoke(try scope.get(session, "settingsManager"), "getImageAutoResize", &.{}));
    if (scope.truthy(resize)) try scope.put(options, "resizeOptions", resize);
    return waitAt(scope, owner, try scope.call(normalize, c.pi_js_undefined(), &.{ content, options }), .after_normalize);
}
fn normalizedResult(scope: *Scope, owner: c.JSValue, content: c.JSValue) !c.JSValue {
    const hook = try scope.get(owner, "hookResult");
    if (!scope.truthy(hook) and scope.equal(content, try scope.get(owner, "content"))) return c.pi_js_undefined();
    const original = try scope.get(owner, "result");
    const result = try scope.object();
    try scope.put(result, "content", content);
    try scope.put(result, "details", if (temp.nullish(hook)) c.pi_js_undefined() else try scope.get(hook, "details"));
    try scope.put(result, "structuredContent", try scope.get(if (scope.truthy(hook)) hook else original, "structuredContent"));
    var is_error = if (temp.nullish(hook)) c.pi_js_undefined() else try scope.get(hook, "isError");
    if (temp.nullish(is_error)) is_error = try scope.get(owner, "isError");
    try scope.put(result, "isError", is_error);
    try scope.put(result, "usage", if (temp.nullish(hook)) c.pi_js_undefined() else try scope.get(hook, "usage"));
    return result;
}
fn startCompaction(scope: *Scope, owner: c.JSValue) !af.Action {
    const session = try scope.get(owner, "agent");
    const projection = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionProjection", &.{});
    const model = try scope.get(session, "model");
    if (scope.truthy(model) and !try @import("native_sdk_virtual.zig").isVirtual(scope.engine, model) and scope.truthy(try scope.invoke(session, "_exceedsCompactionThreshold", &.{ model, projection }))) {
        return waitAt(scope, owner, try scope.invoke(session, "_runAutoCompaction", &.{ try scope.text("threshold"), c.pi_js_bool(scope.engine.context, 0) }), .compact);
    }
    const result = try scope.own(try js.spread(scope.engine, try scope.get(owner, "input")));
    try scope.put(result, "messages", try scope.get(projection, "messages"));
    return returned(scope.engine, result);
}
fn startBoundary(scope: *Scope, owner: c.JSValue) !af.Action {
    const engine = scope.engine;
    const session = try scope.get(owner, "agent");
    const message = try scope.get(owner, "input");
    const results = try scope.get(owner, "second");
    const stop = try scope.get(message, "stopReason");
    var outcome: []const u8 = "completed";
    if (scope.equal(stop, try scope.text("aborted"))) outcome = "aborted" else if (scope.equal(try scope.get(message, "stopReason"), try scope.text("error"))) outcome = "error";
    try scope.set(session, "_lastActivityOutcome", try scope.text(outcome));
    const entry = try scope.invoke(session, "_findPersistedMessageEntryId", &.{message});
    if (!scope.truthy(try scope.invoke(try scope.get(session, "_extensionRunner"), "hasHandlers", &.{try scope.text("turn_end")}))) return returned(engine, c.pi_js_bool(engine.context, 0));
    if (!scope.truthy(entry)) {
        const runner = try scope.get(session, "_extensionRunner");
        const emit_error = try scope.get(runner, "emitError");
        const event = try scope.object();
        try scope.put(event, "extensionPath", try scope.text("<boundary>"));
        try scope.put(event, "event", try scope.text("turn_end"));
        try scope.put(event, "error", try scope.text("turn_end could not resolve the persisted assistant entry ID"));
        _ = try scope.call(emit_error, runner, &.{event});
        return returned(engine, c.pi_js_bool(engine.context, 0));
    }
    const flat_map = try scope.get(results, "flatMap");
    const mapper = try scope.own(try functions.createArrow(engine, "", 1, entryIds, &.{session}));
    const ids = try scope.call(flat_map, results, &.{mapper});
    const runner = try scope.get(session, "_extensionRunner");
    const emit = try scope.get(runner, "emitBoundary");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("turn_end"));
    try scope.put(event, "turnIndex", try scope.get(session, "_turnIndex"));
    try scope.put(event, "message", message);
    try scope.put(event, "toolResults", results);
    try scope.put(event, "messageEntryId", entry);
    try scope.put(event, "toolResultEntryIds", ids);
    try scope.put(event, "outcome", try scope.get(session, "_lastActivityOutcome"));
    const builder = try scope.own(try functions.createArrow(engine, "", 1, boundaryContext, &.{session}));
    return waitAt(scope, owner, try scope.call(emit, runner, &.{ event, builder }), .boundary);
}
fn entryIds(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = try scope.invoke(roots[0], "_findPersistedMessageEntryId", &.{arg(args, 0)});
    const result = try scope.array();
    if (scope.truthy(id)) try scope.index(result, 0, id);
    return c.JS_DupValue(engine.context, result);
}
fn boundaryContext(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const build = try scope.get(roots[0], "_buildBoundaryContext");
    return js.call(engine, build, roots[0], &.{ arg(args, 0), try scope.text("turn_end") });
}
fn finishBoundary(scope: *Scope, owner: c.JSValue, boundary: c.JSValue) !af.Action {
    const session = try scope.get(owner, "agent");
    const commit = try scope.get(session, "_commitBoundaryDrafts");
    _ = try scope.call(commit, session, &.{try scope.get(boundary, "entries")});
    if (scope.truthy(try scope.get(boundary, "continue"))) {
        const build = try scope.get(session, "_buildBoundaryContext");
        if (!scope.truthy(try scope.get(try scope.call(build, session, &.{ try scope.array(), try scope.text("turn_end") }), "canContinue"))) {
            _ = try scope.invoke(session, "_reportInvalidBoundaryContinuation", &.{try scope.text("turn_end")});
            return returned(scope.engine, c.pi_js_bool(scope.engine.context, 0));
        }
    }
    return returned(scope.engine, try scope.get(boundary, "continue"));
}

//! Actual AgentSession boundary and nested-call bodies. Module imports are
//! retained as lexical function roots; all session callees remain live reads.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum(c_int) { _executeNestedToolCall, _applyBoundaryDrafts, _createBoundaryPreviewManager, _getPendingBoundaryMessages, _buildBoundaryContext, _commitBoundaryDrafts, _reportInvalidBoundaryContinuation };
const Callback = enum(c_int) { getTools, sequential, run, emit, before, after, nonSystem };
pub fn install(engine: *em.Engine, prototype: c.JSValue, dependencies: c.JSValue) !void {
    inline for (.{ "SessionManager", "NestedToolCallRunner", "runToolCall", "convertToLlm", "estimateProjectedContextTokens" }) |name| {
        const value = try sdk.get(engine, dependencies, name);
        defer engine.freeValue(value);
        if (!c.JS_IsFunction(engine.context, value)) return error.RequiredNativeBoundaryDependencies;
    }
    var roots = [_]c.JSValue{dependencies};
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const length: c_int = switch (method) {
            ._executeNestedToolCall => 4,
            ._applyBoundaryDrafts, ._buildBoundaryContext => 2,
            ._getPendingBoundaryMessages => 0,
            else => 1,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, length, @intFromEnum(method), roots.len, &roots));
        defer engine.freeValue(function);
        if (method == ._executeNestedToolCall) {
            const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(parent);
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (switch (@as(Method, @enumFromInt(magic))) {
        ._executeNestedToolCall => execute(engine, session, roots[0], args),
        ._applyBoundaryDrafts => apply(engine, arg(args, 0), arg(args, 1), roots[0]),
        ._createBoundaryPreviewManager => preview(engine, session, arg(args, 0), roots[0]),
        ._getPendingBoundaryMessages => pending(engine, session),
        ._buildBoundaryContext => build(engine, session, arg(args, 0), arg(args, 1), roots[0]),
        ._commitBoundaryDrafts => commit(engine, session, arg(args, 0)),
        ._reportInvalidBoundaryContinuation => invalid(engine, session, arg(args, 0)),
    }) catch |err| sdk.fail(engine, err);
}
fn iterate(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
}
fn spread(scope: *Scope, target: c.JSValue, value: c.JSValue) !void {
    var iterator = try iterate(scope, value);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index = try sdk.length(scope.engine, target);
    while (try iterator.next()) |item| {
        defer scope.engine.freeValue(item);
        try scope.index(target, index, item);
        index += 1;
    }
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn imported(scope: *Scope, dependencies: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(dependencies, name), c.pi_js_undefined(), args);
}
fn apply(engine: *em.Engine, manager: c.JSValue, drafts: c.JSValue, dependencies: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const appended = try scope.array();
    var rows = try iterate(&scope, drafts);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |draft| {
        defer engine.freeValue(draft);
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        var id = c.pi_js_undefined();
        const kind = try frame.get(draft, "type");
        if (try is(&frame, kind, "custom")) {
            const method = try frame.get(manager, "appendCustomEntry");
            id = try frame.call(method, manager, &.{ try frame.get(draft, "customType"), try frame.get(draft, "data") });
        } else if (try is(&frame, kind, "custom_message")) {
            const method = try frame.get(manager, "appendCustomMessageEntry");
            id = try frame.call(method, manager, &.{ try frame.get(draft, "customType"), try frame.get(draft, "content"), try frame.get(draft, "display"), try frame.get(draft, "details") });
        } else if (try is(&frame, kind, "context_edit")) {
            const method = try frame.get(manager, "appendContextEdit");
            id = try frame.call(method, manager, &.{ try frame.get(draft, "targetId"), try frame.get(draft, "replacement") });
        } else if (try is(&frame, kind, "compaction")) {
            const tokens = try frame.get(try imported(&frame, dependencies, "estimateProjectedContextTokens", &.{ try frame.invoke(manager, "buildSessionProjection", &.{}), try frame.invoke(manager, "getBranch", &.{}) }), "tokens");
            const method = try frame.get(manager, "appendCompaction");
            id = try frame.call(method, manager, &.{ try frame.get(draft, "summary"), try frame.get(draft, "firstKeptEntryId"), tokens, try frame.get(draft, "details"), c.pi_js_bool(engine.context, 1), try frame.get(draft, "usage") });
        }
        const entry = try frame.invoke(manager, "getEntry", &.{id});
        if (frame.truthy(entry)) _ = try frame.invoke(appended, "push", &.{entry});
    }
    return c.JS_DupValue(engine.context, appended);
}
fn preview(engine: *em.Engine, session: c.JSValue, drafts: c.JSValue, dependencies: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const header = try scope.invoke(try scope.get(session, "sessionManager"), "getHeader", &.{});
    if (!scope.truthy(header)) return sdk.sourceError(engine, "Session header is missing");
    const manager_class = try scope.get(dependencies, "SessionManager");
    const in_memory = try scope.get(manager_class, "inMemory");
    const cwd = try scope.get(session, "_cwd");
    const entries = try scope.array();
    try scope.index(entries, 0, header);
    try spread(&scope, entries, try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{}));
    const manager = try scope.call(in_memory, manager_class, &.{ cwd, c.pi_js_undefined(), entries });
    _ = try scope.invoke(session, "_applyBoundaryDrafts", &.{ manager, drafts });
    return c.JS_DupValue(engine.context, manager);
}
fn pending(engine: *em.Engine, session: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = try scope.array();
    try spread(&scope, messages, try scope.invoke(try scope.get(session, "agent"), "peekQueuedMessages", &.{}));
    try spread(&scope, messages, try scope.get(session, "_pendingCustomMessages"));
    return c.JS_DupValue(engine.context, messages);
}
fn build(engine: *em.Engine, session: c.JSValue, drafts: c.JSValue, boundary: c.JSValue, dependencies: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const projection = try scope.invoke(try scope.invoke(session, "_createBoundaryPreviewManager", &.{drafts}), "buildSessionProjection", &.{});
    const pending_messages = try scope.invoke(session, "_getPendingBoundaryMessages", &.{});
    const llm = try imported(&scope, dependencies, "convertToLlm", &.{try scope.get(projection, "messages")});
    const last = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(llm, "length"), c.JS_NewInt32(engine.context, 1)));
    const final_message = try scope.own(try js.getKey(engine, llm, last));
    const final_role = if (temp.nullish(final_message)) c.pi_js_undefined() else try scope.get(final_message, "role");
    const some = try scope.get(llm, "some");
    const predicate = try callback(&scope, .nonSystem, &.{});
    const has_context = try scope.call(some, llm, &.{predicate});
    const context_can_continue = scope.truthy(has_context) and !try is(&scope, final_role, "assistant");
    const pending_custom = try scope.positive(try scope.get(try scope.get(session, "_pendingCustomMessages"), "length"));
    const result = try scope.object();
    try scope.put(result, "contextEntries", try scope.get(projection, "entries"));
    try scope.put(result, "contextMessages", try scope.get(projection, "messages"));
    try scope.put(result, "llmMessages", llm);
    try scope.put(result, "pendingMessages", pending_messages);
    var can: c.JSValue = c.pi_js_bool(engine.context, @intFromBool(context_can_continue or pending_custom));
    if (!scope.truthy(can)) {
        if (try is(&scope, boundary, "turn_end")) can = try scope.invoke(try scope.get(session, "agent"), "hasQueuedMessages", &.{}) else if (try is(&scope, final_role, "assistant")) can = try scope.invoke(try scope.get(session, "agent"), "hasQueuedMessages", &.{});
    }
    try scope.put(result, "canContinue", can);
    return c.JS_DupValue(engine.context, result);
}
fn commit(engine: *em.Engine, session: c.JSValue, drafts: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const method = try scope.get(session, "_applyBoundaryDrafts");
    const appended = try scope.call(method, session, &.{ try scope.get(session, "sessionManager"), drafts });
    _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
    var rows = try iterate(&scope, appended);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer engine.freeValue(entry);
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        const emit = try frame.get(session, "_emit");
        const event = try frame.object();
        try frame.put(event, "type", try frame.text("entry_appended"));
        try frame.put(event, "entry", entry);
        _ = try frame.call(emit, session, &.{event});
    }
    return c.pi_js_undefined();
}
fn invalid(engine: *em.Engine, session: c.JSValue, event: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runner = try scope.get(session, "_extensionRunner");
    const emit = try scope.get(runner, "emitError");
    const value = try scope.object();
    try scope.put(value, "extensionPath", try scope.text("<boundary>"));
    try scope.put(value, "event", event);
    try scope.put(value, "error", try scope.concat(try scope.stringify(event), try scope.text(" requested continuation without runnable model context")));
    _ = try scope.call(emit, runner, &.{value});
    return c.pi_js_undefined();
}
fn callback(scope: *Scope, kind: Callback, values: []const c.JSValue) !c.JSValue {
    const length: c_int = switch (kind) {
        .getTools, .sequential => 0,
        .run => 4,
        else => 1,
    };
    const name: [:0]const u8 = switch (kind) {
        .getTools => "getTools",
        .sequential => "isSequential",
        .run => "runToolCall",
        .emit => "emit",
        .before => "beforeToolCall",
        .after => "afterToolCall",
        .nonSystem => "",
    };
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, closure, name, length, @intFromEnum(kind), @intCast(values.len), @constCast(values.ptr))));
    if (kind == .emit) {
        const parent = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, function, parent) < 0) return js.capture(scope.engine);
    }
    return function;
}
fn closure(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return closureBody(engine, @enumFromInt(magic), args, roots) catch |err| sdk.fail(engine, err);
}
fn closureBody(engine: *em.Engine, kind: Callback, args: []const c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (kind == .nonSystem) return c.pi_js_bool(engine.context, @intFromBool(!try is(&scope, try scope.get(arg(args, 0), "role"), "system")));
    const session = roots[0];
    switch (kind) {
        .getTools => return c.JS_DupValue(engine.context, try scope.invoke(session, "_getCallableTools", &.{})),
        .sequential => return c.pi_js_bool(engine.context, @intFromBool(try is(&scope, try scope.get(try scope.get(session, "agent"), "toolExecution"), "sequential"))),
        .before, .after => return c.JS_DupValue(engine.context, try scope.invoke(session, if (kind == .before) "_beforeToolCall" else "_afterToolCall", &.{ arg(args, 0), roots[1] })),
        .run => {
            const assistant = try scope.invoke(session, "_findLastAssistantMessage", &.{});
            if (!scope.truthy(assistant)) {
                const result = try scope.object();
                try scope.put(result, "toolCall", arg(args, 0));
                const error_result = try scope.own(try @import("native_agent_tool_call.zig").errorResult(engine, try scope.text("No assistant message issued this call")));
                try scope.put(result, "result", error_result);
                try scope.put(result, "isError", c.pi_js_bool(engine.context, 1));
                const promise = try scope.global("Promise");
                return c.JS_DupValue(engine.context, try scope.invoke(promise, "resolve", &.{result}));
            }
            const function = try scope.get(roots[1], "runToolCall");
            const options = try scope.object();
            try scope.put(options, "tools", try scope.invoke(session, "_getCallableTools", &.{}));
            try scope.put(options, "assistantMessage", assistant);
            const context_value = try scope.object();
            try scope.put(context_value, "messages", try scope.get(try scope.get(try scope.get(session, "agent"), "state"), "messages"));
            try scope.put(context_value, "tools", try scope.get(try scope.get(try scope.get(session, "agent"), "state"), "tools"));
            try scope.put(options, "context", context_value);
            try scope.put(options, "beforeToolCall", try callback(&scope, .before, &.{ session, arg(args, 1) }));
            try scope.put(options, "afterToolCall", try callback(&scope, .after, &.{ session, arg(args, 1) }));
            try scope.put(options, "signal", arg(args, 2));
            try scope.put(options, "onUpdate", arg(args, 3));
            return c.JS_DupValue(engine.context, try scope.call(function, c.pi_js_undefined(), &.{ arg(args, 0), options }));
        },
        .emit => return emitAsync(engine, session, arg(args, 0)),
        .nonSystem => unreachable,
    }
}
fn execute(engine: *em.Engine, session: c.JSValue, dependencies: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const pending_value = try flow.create(engine, session);
    defer engine.freeValue(pending_value.owner);
    errdefer engine.freeValue(pending_value.promise);
    executeBody(engine, session, dependencies, args, pending_value.owner) catch |err| try flow.rejectError(engine, pending_value.owner, err);
    return pending_value.promise;
}
fn executeBody(engine: *em.Engine, session: c.JSValue, dependencies: c.JSValue, args: []const c.JSValue, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const current = try scope.get(session, "_nestedToolCalls");
    if (temp.nullish(current)) {
        const constructor_value = try scope.get(dependencies, "NestedToolCallRunner");
        const host = try scope.object();
        try scope.put(host, "getTools", try callback(&scope, .getTools, &.{session}));
        try scope.put(host, "isSequential", try callback(&scope, .sequential, &.{session}));
        try scope.put(host, "runToolCall", try callback(&scope, .run, &.{ session, dependencies }));
        try scope.put(host, "emit", try callback(&scope, .emit, &.{session}));
        var inputs = [_]c.JSValue{host};
        const runner = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor_value, inputs.len, &inputs)));
        try scope.set(session, "_nestedToolCalls", runner);
    }
    const value = try scope.invoke(try scope.get(session, "_nestedToolCalls"), "execute", &.{ arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3) });
    try flow.settle(engine, owner, false, value);
}
fn emitAsync(engine: *em.Engine, session: c.JSValue, event: c.JSValue) !c.JSValue {
    const pending_value = try flow.create(engine, session);
    defer engine.freeValue(pending_value.owner);
    errdefer engine.freeValue(pending_value.promise);
    emitStart(engine, pending_value.owner, session, event) catch |err| try flow.rejectError(engine, pending_value.owner, err);
    return pending_value.promise;
}
fn emitStart(engine: *em.Engine, owner: c.JSValue, session: c.JSValue, event: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "event", event);
    const value = try scope.invoke(try scope.get(session, "_extensionRunner"), "emit", &.{event});
    try flow.wait(emitDone, engine, owner, value, 0);
}
fn emitDone(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try scope.invoke(try scope.get(owner, "agent"), "_emit", &.{try scope.get(owner, "event")});
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}

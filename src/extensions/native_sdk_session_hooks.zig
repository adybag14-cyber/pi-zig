//! Source constructor hooks. Imported utility functions are explicit lexical
//! dependencies retained in native function data, never ordinary session fields.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const helpers = @import("native_sdk_session_hook_helpers.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Hook = enum(c_int) { beforeTool, afterTool, next, request, boundary, hidden, forced, legacyNext };
const Installer = enum(c_int) { tool, next, request, boundary, hidden, forced };
const names = [_][:0]const u8{ "_installAgentToolHooks", "_installAgentNextTurnRefresh", "_installAgentRequestProjection", "_installAgentBoundaryHooks", "_installHiddenDeclarationsProjection", "_installAgentForcedPromptProjection" };
const dependency_names = .{ "normalizeToolResultImages", "convertToLlm", "getVirtualModelState", "shouldCompact", "estimateProjectedContextTokens" };

pub fn validateDependencies(engine: *em.Engine, dependencies: c.JSValue) !void {
    inline for (dependency_names) |name| {
        const function = try sdk.get(engine, dependencies, name);
        defer engine.freeValue(function);
        if (!c.JS_IsFunction(engine.context, function)) return error.RequiredNativeSessionHookDependencies;
    }
}
pub fn installWithDependencies(engine: *em.Engine, prototype: c.JSValue, dependencies: c.JSValue) !void {
    try validateDependencies(engine, dependencies);
    try @import("native_sdk_compaction_threshold.zig").install(engine, prototype, dependencies);
    var roots = [_]c.JSValue{dependencies};
    inline for (names, 0..) |name, index| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, installerCallback, name, 0, @intCast(index), roots.len, &roots));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    inline for (std.meta.fields(helpers.Kind)) |field| {
        const function = try helpers.create(engine, @enumFromInt(field.value), dependencies);
        defer engine.freeValue(function);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
pub fn attachWithDependencies(engine: *em.Engine, session: c.JSValue, dependencies: c.JSValue) !void {
    try validateDependencies(engine, dependencies);
    inline for (std.meta.fields(Installer)) |field| try installHook(engine, session, dependencies, @enumFromInt(field.value));
}
fn installerCallback(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    installHook(engine, receiver, roots[0], @enumFromInt(magic)) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn callbackValue(scope: *Scope, session: c.JSValue, previous: c.JSValue, dependencies: c.JSValue, hook: Hook) !c.JSValue {
    var roots = [_]c.JSValue{ session, previous, dependencies };
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, hookCallback, "", if (hook == .beforeTool or hook == .afterTool) 1 else 2, @intFromEnum(hook), roots.len, &roots)));
    if (hook != .beforeTool and hook != .afterTool) {
        const parent = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, function, parent) < 0) return js.capture(scope.engine);
    }
    return function;
}
fn installHook(engine: *em.Engine, session: c.JSValue, dependencies: c.JSValue, installer: Installer) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(session, "agent");
    if (installer == .tool) {
        try scope.set(agent, "beforeToolCall", try callbackValue(&scope, session, c.pi_js_undefined(), dependencies, .beforeTool));
        return scope.set(agent, "afterToolCall", try callbackValue(&scope, session, c.pi_js_undefined(), dependencies, .afterTool));
    }
    const property: [:0]const u8 = switch (installer) {
        .next => "prepareNextTurnWithContext",
        .request => "prepareRequest",
        .boundary => "finishTurn",
        .hidden, .forced => "transformContext",
        .tool => unreachable,
    };
    var previous = try scope.get(agent, property);
    if (installer == .next and temp.nullish(previous) and scope.truthy(try scope.get(agent, "prepareNextTurn"))) previous = try callbackValue(&scope, session, c.pi_js_undefined(), dependencies, .legacyNext);
    const hook: Hook = switch (installer) {
        .next => .next,
        .request => .request,
        .boundary => .boundary,
        .hidden => .hidden,
        .forced => .forced,
        .tool => unreachable,
    };
    try scope.set(agent, property, try callbackValue(&scope, session, previous, dependencies, hook));
}
fn hookCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const first = if (argc > 0) args[0] else c.pi_js_undefined();
    const second = if (argc > 1) args[1] else c.pi_js_undefined();
    const hook: Hook = @enumFromInt(magic);
    if (hook == .beforeTool or hook == .afterTool) return js.invoke(engine, roots[0], if (hook == .beforeTool) "_beforeToolCall" else "_afterToolCall", &.{first}) catch |err| sdk.fail(engine, err);
    return begin(engine, roots[0], roots[1], roots[2], first, second, hook) catch |err| sdk.fail(engine, err);
}
fn is(scope: *Scope, value: c.JSValue, expected: []const u8) !bool {
    return scope.equal(value, try scope.text(expected));
}
fn dependency(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(try scope.get(owner, "dependencies"), name), c.pi_js_undefined(), args);
}
fn begin(engine: *em.Engine, session: c.JSValue, previous: c.JSValue, dependencies: c.JSValue, input: c.JSValue, signal: c.JSValue, hook: Hook) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    prepareOwner(engine, pending.owner, previous, dependencies, input, signal) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    start(engine, pending.owner, hook) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn prepareOwner(engine: *em.Engine, owner: c.JSValue, previous: c.JSValue, dependencies: c.JSValue, input: c.JSValue, signal: c.JSValue) !void {
    inline for (.{ "previous", "dependencies", "input", "signal" }, .{ previous, dependencies, input, signal }) |key, value| try sdk.put(engine, owner, key, c.JS_DupValue(engine.context, value));
}
const Stage = enum(c_int) { transformHidden, transformForced, compactNext, previousNext, boundaryExtension, boundaryPrevious, preparedPrevious, repreparedPrevious, preparedRequest, routedRequest, compactRequest, repreparedRequest, helperBefore };
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(advance, engine, owner, value, @intFromEnum(stage));
}
fn finish(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    try flow.settle(engine, owner, false, value);
}
fn start(engine: *em.Engine, owner: c.JSValue, hook: Hook) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const input = try scope.get(owner, "input");
    const signal = try scope.get(owner, "signal");
    const previous = try scope.get(owner, "previous");
    switch (hook) {
        .hidden, .forced => {
            const transformed = if (scope.truthy(previous)) try scope.call(previous, c.pi_js_undefined(), &.{ input, signal }) else input;
            try wait(engine, owner, transformed, if (hook == .hidden) .transformHidden else .transformForced);
        },
        .legacyNext => {
            const agent = try scope.get(session, "agent");
            const method = try scope.get(agent, "prepareNextTurn");
            try wait(engine, owner, if (temp.nullish(method)) c.pi_js_undefined() else try scope.call(method, agent, &.{signal}), .helperBefore);
        },
        .next => try wait(engine, owner, try scope.invoke(session, "_compactBeforeNextAssistantResponse", &.{try scope.get(input, "context")}), .compactNext),
        .boundary => {
            _ = try scope.invoke(try scope.get(session, "_boundaryDispatchedMessages"), "add", &.{try scope.get(input, "message")});
            try wait(engine, owner, try scope.invoke(session, "_dispatchTurnEndBoundary", &.{ try scope.get(input, "message"), try scope.get(input, "toolResults") }), .boundaryExtension);
        },
        .request => {
            try scope.put(owner, "failed", try scope.get(session, "_failedResponse"));
            try scope.set(session, "_failedResponse", c.pi_js_undefined());
            try prepareRequest(engine, owner, false);
        },
        .beforeTool, .afterTool => unreachable,
    }
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const stage: Stage = @enumFromInt(magic);
    switch (stage) {
        .transformHidden => try finish(engine, owner, try hidden(&scope, session, value)),
        .transformForced => try finish(engine, owner, try forced(&scope, session, value)),
        .compactNext => {
            try scope.put(owner, "context", value);
            const previous = try scope.get(owner, "previous");
            const turn = try scope.own(try js.spread(engine, try scope.get(owner, "input")));
            try scope.put(turn, "context", value);
            const result = if (temp.nullish(previous)) c.pi_js_undefined() else try scope.call(previous, c.pi_js_undefined(), &.{ turn, try scope.get(owner, "signal") });
            try wait(engine, owner, result, .previousNext);
        },
        .previousNext => try finish(engine, owner, try nextSnapshot(&scope, session, owner, value)),
        .boundaryExtension => {
            try scope.put(owner, "extensionContinue", value);
            const previous = try scope.get(owner, "previous");
            const decision = if (temp.nullish(previous)) c.pi_js_undefined() else try scope.call(previous, c.pi_js_undefined(), &.{ try scope.get(owner, "input"), try scope.get(owner, "signal") });
            try wait(engine, owner, decision, .boundaryPrevious);
        },
        .boundaryPrevious => {
            if (!temp.nullish(value) and try is(&scope, try scope.get(value, "action"), "end")) return finish(engine, owner, value);
            if (scope.truthy(try scope.get(owner, "extensionContinue")) or (!temp.nullish(value) and try is(&scope, try scope.get(value, "action"), "continue"))) {
                const decision = try scope.object();
                try scope.put(decision, "action", try scope.text("continue"));
                return finish(engine, owner, decision);
            }
            try finish(engine, owner, c.pi_js_undefined());
        },
        .preparedPrevious, .repreparedPrevious => {
            try scope.put(owner, "prepared", value);
            try scope.put(owner, "context", try preparedField(&scope, value, "context", try scope.get(owner, "canonical")));
            // The local async prepare() returns its object, then the outer
            // prepareRequest awaits it before model selection/routing.
            try wait(engine, owner, c.pi_js_undefined(), if (stage == .preparedPrevious) .preparedRequest else .repreparedRequest);
        },
        .preparedRequest => try requestPrepared(engine, owner),
        .routedRequest => try requestRouted(engine, owner, value),
        .compactRequest => try prepareRequest(engine, owner, true),
        .repreparedRequest => try finishRequest(engine, owner, true),
        .helperBefore => try finish(engine, owner, value),
    }
}
fn hidden(scope: *Scope, session: c.JSValue, messages: c.JSValue) !c.JSValue {
    const hidden_names = try scope.get(session, "_hiddenDeclarations");
    if (scope.equal(try scope.get(hidden_names, "size"), c.JS_NewInt32(scope.engine.context, 0))) return messages;
    var roots = [_]c.JSValue{hidden_names};
    const mapper = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, hiddenMapper, "", 1, 0, roots.len, &roots)));
    return scope.invoke(messages, "map", &.{mapper});
}
fn hiddenMapper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return hiddenMessage(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn hiddenMessage(engine: *em.Engine, message: c.JSValue, hidden_names: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!try is(&scope, try scope.get(message, "role"), "system") or (!scope.truthy(try scope.get(message, "toolsAdded")) and !scope.truthy(try scope.get(message, "toolsRemoved")))) return c.JS_DupValue(engine.context, message);
    const added = try scope.get(message, "toolsAdded");
    const removed = try scope.get(message, "toolsRemoved");
    const rest = try scope.own(try toolChangesRest(engine, message));
    var roots = [_]c.JSValue{hidden_names};
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, visibleTool, "", 1, 0, roots.len, &roots)));
    const filtered_added = if (temp.nullish(added)) c.pi_js_undefined() else try scope.invoke(added, "filter", &.{predicate});
    const kept_added = if (temp.nullish(filtered_added)) try scope.array() else filtered_added;
    const filtered_removed = if (temp.nullish(removed)) c.pi_js_undefined() else try scope.invoke(removed, "filter", &.{predicate});
    const kept_removed = if (temp.nullish(filtered_removed)) try scope.array() else filtered_removed;
    inline for (.{ "toolsAdded", "toolsRemoved" }, .{ kept_added, kept_removed }) |name, kept| {
        if (try scope.positive(try scope.get(kept, "length"))) try scope.put(rest, name, kept);
    }
    return c.JS_DupValue(engine.context, rest);
}
fn toolChangesRest(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &properties, &count, message, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, properties, count);
    const added_atom = c.JS_NewAtom(engine.context, "toolsAdded");
    defer c.JS_FreeAtom(engine.context, added_atom);
    const removed_atom = c.JS_NewAtom(engine.context, "toolsRemoved");
    defer c.JS_FreeAtom(engine.context, removed_atom);
    for (properties[0..count]) |entry| {
        if (entry.atom == added_atom or entry.atom == removed_atom) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, message, entry.atom);
        if (present < 0) return js.capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, message, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    return result;
}
fn visibleTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tool = if (argc > 0) args[0] else c.pi_js_undefined();
    const name = scope.get(tool, "name") catch |err| return sdk.fail(engine, err);
    const hidden_value = scope.invoke(roots[0], "has", &.{name}) catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(hidden_value)));
}
fn forced(scope: *Scope, session: c.JSValue, messages: c.JSValue) !c.JSValue {
    const options = try scope.get(session, "_runSystemPromptOptions");
    const force = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "forceSystemPrompt");
    if (c.JS_IsUndefined(force)) return messages;
    const current = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(scope.engine, messages));
    const head = try scope.object();
    try scope.put(head, "role", try scope.text("system"));
    try scope.put(head, "content", force);
    if (!temp.nullish(current) and scope.truthy(try scope.get(current, "toolsAdded"))) try scope.put(head, "toolsAdded", try scope.get(current, "toolsAdded"));
    const timestamp = if (temp.nullish(current)) c.pi_js_undefined() else try scope.get(current, "timestamp");
    try scope.put(head, "timestamp", if (temp.nullish(timestamp)) try scope.invoke(try scope.global("Date"), "now", &.{}) else timestamp);
    const result = try scope.array();
    _ = try scope.invoke(result, "push", &.{head});
    const predicate = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, notSystem, "", 1)));
    const filtered = try scope.invoke(messages, "filter", &.{predicate});
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, filtered, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |message| {
        defer scope.engine.freeValue(message);
        _ = try scope.invoke(result, "push", &.{message});
    }
    return result;
}
fn notSystem(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const message = if (argc > 0) args[0] else c.pi_js_undefined();
    const role = scope.get(message, "role") catch |err| return sdk.fail(engine, err);
    const system = is(&scope, role, "system") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(!system));
}
fn nextSnapshot(scope: *Scope, session: c.JSValue, owner: c.JSValue, previous: c.JSValue) !c.JSValue {
    const previous_context = if (temp.nullish(previous)) c.pi_js_undefined() else try scope.get(previous, "context");
    const context = if (temp.nullish(previous_context)) try scope.get(owner, "context") else previous_context;
    const base = try scope.get(session, "_baseSystemPromptOptions");
    const run = try scope.get(session, "_runSystemPromptOptions");
    const run_options = if (temp.nullish(run)) base else run;
    const options_input = try scope.own(try js.spread(scope.engine, run_options));
    try scope.put(options_input, "selectedTools", try scope.invoke(session, "getActiveToolNames", &.{}));
    inline for (.{ "toolSnippets", "toolGuidelines" }) |name| {
        const merged = try scope.own(try js.spread(scope.engine, try scope.get(base, name)));
        try js.spreadInto(scope.engine, merged, try scope.get(run_options, name));
        try scope.put(options_input, name, merged);
    }
    const options = try scope.own(try @import("native_sdk_prompt_normalize.zig").normalize(scope.engine, options_input));
    const update = try scope.invoke(session, "_preparePromptAndToolLoadout", &.{ options, try scope.get(context, "messages") });
    try scope.set(session, "_runSystemPromptOptions", options);
    const result = try scope.own(try js.spread(scope.engine, previous));
    const next_context = try scope.own(try js.spread(scope.engine, context));
    const state = try scope.get(try scope.get(session, "agent"), "state");
    try scope.put(next_context, "tools", try scope.invoke(try scope.get(state, "tools"), "slice", &.{}));
    try scope.put(result, "context", next_context);
    const old_messages = if (temp.nullish(previous)) c.pi_js_undefined() else try scope.get(previous, "messages");
    var messages = old_messages;
    if (scope.truthy(update)) {
        messages = if (temp.nullish(old_messages)) try scope.array() else try scope.invoke(old_messages, "slice", &.{});
        _ = try scope.invoke(messages, "push", &.{update});
    }
    try scope.put(result, "messages", messages);
    inline for (.{ "model", "thinkingLevel" }) |name| try scope.put(result, name, try scope.get(state, name));
    return result;
}
fn prepareRequest(engine: *em.Engine, owner: c.JSValue, again: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const request = try scope.get(owner, "input");
    const projection = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionProjection", &.{});
    const context = try scope.own(try js.spread(engine, try scope.get(request, "context")));
    try scope.put(context, "messages", try scope.get(projection, "messages"));
    try scope.put(context, "tools", try scope.invoke(try stateField(&scope, session, "tools"), "slice", &.{}));
    try scope.put(owner, "canonical", context);
    try scope.put(owner, "projection", projection);
    const previous = try scope.get(owner, "previous");
    var result = c.pi_js_undefined();
    if (!temp.nullish(previous)) {
        const updated = try scope.own(try js.spread(engine, request));
        try scope.put(updated, "context", context);
        inline for (.{ "model", "thinkingLevel" }) |name| try scope.put(updated, name, try stateField(&scope, session, name));
        result = try scope.call(previous, c.pi_js_undefined(), &.{ updated, try scope.get(owner, "signal") });
    }
    try wait(engine, owner, result, if (again) .repreparedPrevious else .preparedPrevious);
}
fn preparedField(scope: *Scope, previous: c.JSValue, name: [*:0]const u8, default: c.JSValue) !c.JSValue {
    const value = if (temp.nullish(previous)) c.pi_js_undefined() else try scope.get(previous, name);
    return if (temp.nullish(value)) default else value;
}
fn stateField(scope: *Scope, session: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return scope.get(try scope.get(try scope.get(session, "agent"), "state"), name);
}
fn selectedField(scope: *Scope, session: c.JSValue, previous: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = if (temp.nullish(previous)) c.pi_js_undefined() else try scope.get(previous, name);
    return if (temp.nullish(value)) stateField(scope, session, name) else value;
}
fn requestPrepared(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const previous = try scope.get(owner, "prepared");
    const session = try scope.get(owner, "agent");
    const context = try scope.get(owner, "context");
    const model = try selectedField(&scope, session, previous, "model");
    const thinking = try selectedField(&scope, session, previous, "thinkingLevel");
    try scope.put(owner, "context", context);
    try scope.put(owner, "model", model);
    try scope.put(owner, "thinkingLevel", thinking);
    if (!try @import("native_sdk_virtual.zig").isVirtual(engine, model)) return finishRequest(engine, owner, false);
    const messages = try scope.get(context, "messages");
    var last_response: i64 = -1;
    for (0..try sdk.length(engine, messages)) |index| {
        const message = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index))));
        if (try is(&scope, try scope.get(message, "role"), "assistant")) last_response = @intCast(index);
    }
    var user_turn = false;
    for (@as(usize, @intCast(last_response + 1))..try sdk.length(engine, messages)) |index| {
        const message = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index))));
        if (try is(&scope, try scope.get(message, "role"), "user")) {
            user_turn = true;
            break;
        }
    }
    const virtual_state = try dependency(&scope, owner, "getVirtualModelState", &.{ try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{}), try scope.get(model, "provider"), try scope.get(model, "id") });
    try scope.put(owner, "virtualState", virtual_state);
    const options = try scope.object();
    const failed = try scope.get(owner, "failed");
    try scope.put(options, "reason", try scope.text(if (scope.truthy(failed)) "retry" else if (user_turn) "user" else "continuation"));
    try scope.put(options, "thinkingLevel", thinking);
    try scope.put(options, "signal", try scope.get(owner, "signal"));
    try scope.put(options, "failed", failed);
    try scope.put(options, "state", virtual_state);
    try wait(engine, owner, try scope.invoke(try scope.get(session, "_modelRuntime"), "resolveModel", &.{ model, try dependency(&scope, owner, "convertToLlm", &.{messages}), options }), .routedRequest);
}
fn requestRouted(engine: *em.Engine, owner: c.JSValue, route: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "route", route);
    const session = try scope.get(owner, "agent");
    const route_state = try scope.get(route, "state");
    if (!c.JS_IsUndefined(route_state) and !scope.equal(route_state, try scope.get(owner, "virtualState"))) {
        const model = try scope.get(owner, "model");
        const data = try scope.object();
        try scope.put(data, "provider", try scope.get(model, "provider"));
        try scope.put(data, "modelId", try scope.get(model, "id"));
        try scope.put(data, "state", route_state);
        const manager = try scope.get(session, "sessionManager");
        const entry = try scope.invoke(manager, "getEntry", &.{try scope.invoke(manager, "appendCustomEntry", &.{ try scope.text("pi.virtual-model-state"), data })});
        if (scope.truthy(entry)) {
            const event = try scope.object();
            try scope.put(event, "type", try scope.text("entry_appended"));
            try scope.put(event, "entry", entry);
            _ = try scope.invoke(session, "_emit", &.{event});
        }
    }
    if (scope.truthy(try scope.invoke(session, "_exceedsCompactionThreshold", &.{ try scope.get(route, "model"), try scope.get(owner, "projection") }))) return wait(engine, owner, try scope.invoke(session, "_runAutoCompaction", &.{ try scope.text("threshold"), c.pi_js_bool(engine.context, 0) }), .compactRequest);
    try finishRequest(engine, owner, true);
}
fn finishRequest(engine: *em.Engine, owner: c.JSValue, routed: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const previous = try scope.get(owner, "prepared");
    const result = try scope.own(try js.spread(engine, previous));
    try scope.put(result, "context", try scope.get(owner, "context"));
    const selection = if (routed) try scope.get(owner, "route") else owner;
    inline for (.{ "model", "thinkingLevel" }) |name| try scope.put(result, name, try scope.get(selection, name));
    try finish(engine, owner, result);
}
pub fn combineUsage(engine: *em.Engine, first: c.JSValue, second: c.JSValue) !c.JSValue {
    return @import("native_sdk_usage_combine.zig").combine(engine, first, second);
}

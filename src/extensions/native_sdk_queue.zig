//! AgentSession queue admission and real agent queue storage. The presentation
//! strings and actual pending messages are separate, as in the Source Agent.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
pub const Behavior = enum(c_int) { steer, follow_up };
const AgentOperation = enum(c_int) { steer, followUp, clearSteeringQueue, clearFollowUpQueue, clearAllQueues, hasQueuedMessages, peekQueuedMessages };

fn displayKey(behavior: Behavior) [*:0]const u8 {
    return if (behavior == .steer) "_sdkSteeringMessages" else "_sdkFollowUpMessages";
}
fn actualKey(behavior: Behavior) [*:0]const u8 {
    return if (behavior == .steer) "_sdkAgentSteeringQueue" else "_sdkAgentFollowUpQueue";
}
fn modeKey(behavior: Behavior) [*:0]const u8 {
    return if (behavior == .steer) "_sdkSteeringMode" else "_sdkFollowUpMode";
}
fn modeName(behavior: Behavior) [*:0]const u8 {
    return if (behavior == .steer) "steeringMode" else "followUpMode";
}
pub fn initialize(owner: *sdk.State, receiver: c.JSValue) !void {
    const engine = owner.engine;
    const settings = try sdk.publicField(owner, "settingsManager");
    defer engine.freeValue(settings);
    const agent = try sdk.publicField(owner, "agent");
    defer engine.freeValue(agent);
    inline for (.{ Behavior.steer, Behavior.follow_up }) |behavior| {
        try sdk.put(engine, owner.data, displayKey(behavior), try sdk.array(engine));
        try sdk.put(engine, owner.data, actualKey(behavior), try sdk.array(engine));
        try sdk.put(engine, owner.data, modeKey(behavior), try sdk.invoke(engine, settings, if (behavior == .steer) "getSteeringMode" else "getFollowUpMode", &.{}));
        var roots = [_]c.JSValue{receiver};
        const read = try engine.checked(c.JS_NewCFunctionData2(engine.context, agentMode, modeName(behavior), 0, @intFromEnum(behavior), roots.len, &roots));
        const write = engine.checked(c.JS_NewCFunctionData2(engine.context, agentMode, modeName(behavior), 1, 2 + @intFromEnum(behavior), roots.len, &roots)) catch |err| {
            engine.freeValue(read);
            return err;
        };
        const atom = c.JS_NewAtom(engine.context, modeName(behavior));
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, agent, atom, read, write, c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
    inline for (std.meta.fields(AgentOperation)) |field| {
        var roots = [_]c.JSValue{receiver};
        try sdk.put(engine, agent, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, agentMethod, field.name, if (field.value <= 1) 1 else 0, field.value, roots.len, &roots)));
    }
}
fn agentMode(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const owner = sdk.state(engine, roots[0]) catch |err| return sdk.fail(engine, err);
    const behavior: Behavior = @enumFromInt(@mod(magic, 2));
    if (magic < 2) return sdk.get(engine, owner.data, modeKey(behavior)) catch |err| sdk.fail(engine, err);
    sdk.put(engine, owner.data, modeKey(behavior), if (argc > 0) c.JS_DupValue(context, args[0]) else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn agentMethod(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const owner = sdk.state(engine, roots[0]) catch |err| return sdk.fail(engine, err);
    return agentDispatch(owner, @enumFromInt(magic), if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn agentDispatch(owner: *sdk.State, operation: AgentOperation, message: c.JSValue) !c.JSValue {
    const engine = owner.engine;
    if (operation == .steer or operation == .followUp) {
        const queue = try sdk.get(engine, owner.data, actualKey(if (operation == .steer) .steer else .follow_up));
        defer engine.freeValue(queue);
        const ignored = try sdk.invoke(engine, queue, "push", &.{message});
        engine.freeValue(ignored);
    } else if (operation == .clearAllQueues or operation == .clearSteeringQueue or operation == .clearFollowUpQueue) {
        if (operation != .clearFollowUpQueue) try sdk.put(engine, owner.data, actualKey(.steer), try sdk.array(engine));
        if (operation != .clearSteeringQueue) try sdk.put(engine, owner.data, actualKey(.follow_up), try sdk.array(engine));
    } else if (operation == .hasQueuedMessages) {
        const steering = try sdk.get(engine, owner.data, actualKey(.steer));
        defer engine.freeValue(steering);
        const follow_up = try sdk.get(engine, owner.data, actualKey(.follow_up));
        defer engine.freeValue(follow_up);
        return c.pi_js_bool(engine.context, @intFromBool(try sdk.length(engine, steering) > 0 or try sdk.length(engine, follow_up) > 0));
    } else if (operation == .peekQueuedMessages) {
        const steering = try peek(owner, .steer);
        if (try sdk.length(engine, steering) > 0) return steering;
        engine.freeValue(steering);
        return peek(owner, .follow_up);
    }
    return c.pi_js_undefined();
}
pub fn peek(owner: *sdk.State, behavior: Behavior) !c.JSValue {
    const engine = owner.engine;
    const queue = try sdk.get(engine, owner.data, actualKey(behavior));
    defer engine.freeValue(queue);
    const selected_mode = try sdk.get(engine, owner.data, modeKey(behavior));
    defer engine.freeValue(selected_mode);
    const all = try sdk.text(engine, "all");
    defer engine.freeValue(all);
    if (c.JS_IsStrictEqual(engine.context, selected_mode, all)) return sdk.invoke(engine, queue, "slice", &.{});
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, queue, 0));
    defer engine.freeValue(first);
    const selected = try sdk.array(engine);
    errdefer engine.freeValue(selected);
    if (c.JS_ToBool(engine.context, first) == 1) try sdk.append(engine, selected, c.JS_DupValue(engine.context, first));
    return selected;
}
pub fn messages(owner: *sdk.State, behavior: Behavior) !c.JSValue {
    return sdk.get(owner.engine, owner.data, displayKey(behavior));
}
pub fn pendingCount(owner: *sdk.State) !c.JSValue {
    const steering = try messages(owner, .steer);
    defer owner.engine.freeValue(steering);
    const follow_up = try messages(owner, .follow_up);
    defer owner.engine.freeValue(follow_up);
    return c.JS_NewInt64(owner.engine.context, @as(i64, try sdk.length(owner.engine, steering)) + try sdk.length(owner.engine, follow_up));
}
pub fn mode(owner: *sdk.State, behavior: Behavior) !c.JSValue {
    const agent = try sdk.publicField(owner, "agent");
    defer owner.engine.freeValue(agent);
    return sdk.get(owner.engine, agent, modeName(behavior));
}
pub fn setMode(owner: *sdk.State, behavior: Behavior, value: c.JSValue) !void {
    const engine = owner.engine;
    const agent = try sdk.publicField(owner, "agent");
    defer engine.freeValue(agent);
    if (c.JS_SetPropertyStr(engine.context, agent, modeName(behavior), c.JS_DupValue(engine.context, value)) < 0) return @import("native_js_values.zig").capture(engine);
    const settings = try sdk.publicField(owner, "settingsManager");
    defer engine.freeValue(settings);
    const ignored = try sdk.invoke(engine, settings, if (behavior == .steer) "setSteeringMode" else "setFollowUpMode", &.{value});
    engine.freeValue(ignored);
}
pub fn clear(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ Behavior.steer, Behavior.follow_up }) |behavior| {
        const previous = try messages(owner, behavior);
        defer engine.freeValue(previous);
        try sdk.put(engine, result, if (behavior == .steer) "steering" else "followUp", try sdk.invoke(engine, previous, "slice", &.{}));
    }
    try sdk.put(engine, owner.data, displayKey(.steer), try sdk.array(engine));
    try sdk.put(engine, owner.data, displayKey(.follow_up), try sdk.array(engine));
    const agent = try sdk.publicField(owner, "agent");
    defer engine.freeValue(agent);
    const ignored = try sdk.invoke(engine, agent, "clearAllQueues", &.{});
    engine.freeValue(ignored);
    try emitUpdate(owner);
    return result;
}
fn emitUpdate(owner: *sdk.State) !void {
    const engine = owner.engine;
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, "queue_update"));
    inline for (.{ Behavior.steer, Behavior.follow_up }) |behavior| {
        const queue = try messages(owner, behavior);
        defer engine.freeValue(queue);
        try sdk.put(engine, event, if (behavior == .steer) "steering" else "followUp", try sdk.invoke(engine, queue, "slice", &.{}));
    }
    try sdk.emit(owner, event);
}
pub fn appendPrepared(owner: *sdk.State, behavior: Behavior, text: c.JSValue, images: c.JSValue) !void {
    const engine = owner.engine;
    const display = try messages(owner, behavior);
    defer engine.freeValue(display);
    const ignored = try sdk.invoke(engine, display, "push", &.{text});
    engine.freeValue(ignored);
    try emitUpdate(owner);
    const content = try sdk.array(engine);
    defer engine.freeValue(content);
    const block = try sdk.object(engine);
    defer engine.freeValue(block);
    try sdk.put(engine, block, "type", try sdk.text(engine, "text"));
    try sdk.put(engine, block, "text", c.JS_DupValue(engine.context, text));
    try sdk.append(engine, content, c.JS_DupValue(engine.context, block));
    if (c.JS_ToBool(engine.context, images) == 1) {
        // In content.push(...images), Source resolves push before evaluating
        // the iterator; array-like values without an iterator are rejected.
        const push = try sdk.get(engine, content, "push");
        defer engine.freeValue(push);
        const pushed = try @import("native_iterator_spread.zig").call(engine, content, push, images);
        engine.freeValue(pushed);
    }
    // Source resolves this.agent.steer/followUp before the object argument,
    // including before Date.now. Keep the saved receiver and callee live.
    const agent = try sdk.publicField(owner, "agent");
    defer engine.freeValue(agent);
    const callee = try sdk.get(engine, agent, if (behavior == .steer) "steer" else "followUp");
    defer engine.freeValue(callee);
    const message = try sdk.object(engine);
    defer engine.freeValue(message);
    try sdk.put(engine, message, "role", try sdk.text(engine, "user"));
    try sdk.put(engine, message, "content", c.JS_DupValue(engine.context, content));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const date = try sdk.get(engine, global, "Date");
    defer engine.freeValue(date);
    try sdk.put(engine, message, "timestamp", try sdk.invoke(engine, date, "now", &.{}));
    var parameters = [_]c.JSValue{message};
    const queued = try engine.checked(c.JS_Call(engine.context, callee, agent, 1, &parameters));
    engine.freeValue(queued);
}

pub fn enqueue(owner: *sdk.State, receiver: c.JSValue, args: []const c.JSValue, behavior: Behavior) !c.JSValue {
    return prepare(owner, receiver, args, behavior) catch |err| {
        _ = sdk.fail(owner.engine, err);
        const reason = c.JS_GetException(owner.engine.context);
        defer owner.engine.freeValue(reason);
        return owner.engine.checked(c.JS_NewSettledPromise(owner.engine.context, true, reason));
    };
}
fn prepare(owner: *sdk.State, receiver: c.JSValue, args: []const c.JSValue, behavior: Behavior) !c.JSValue {
    const engine = owner.engine;
    const text = if (args.len > 0) args[0] else c.pi_js_undefined();
    const images = if (args.len > 1) args[1] else c.pi_js_undefined();
    const options = if (args.len > 2) args[2] else c.pi_js_undefined();
    const selected_source = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "source");
    defer engine.freeValue(selected_source);
    // steer/followUp evaluate options?.source before entering _queueUserInput.
    // Do not coerce text: Source calls its actual startsWith/indexOf/slice.
    try rejectExtensionCommand(owner, text);
    const payload = try sdk.object(engine);
    defer engine.freeValue(payload);
    try sdk.put(engine, payload, "text", c.JS_DupValue(engine.context, text));
    try sdk.put(engine, payload, "images", c.JS_DupValue(engine.context, images));
    try sdk.put(engine, payload, "source", if (c.JS_IsNull(selected_source) or c.JS_IsUndefined(selected_source)) try sdk.text(engine, "interactive") else c.JS_DupValue(engine.context, selected_source));
    try sdk.put(engine, payload, "streamingBehavior", if (owner.running) try sdk.text(engine, if (behavior == .steer) "steer" else "followUp") else c.pi_js_undefined());
    const resources = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(resources);
    const pending = try @import("native_sdk_resources.zig").emitValue(engine, resources, owner.data, "input", payload);
    defer engine.freeValue(pending);
    var roots = [_]c.JSValue{ receiver, text, images };
    const continuation = try engine.checked(c.JS_NewCFunctionData2(engine.context, afterInput, "sdkQueueAfterInput", 1, @intFromEnum(behavior), roots.len, &roots));
    defer engine.freeValue(continuation);
    return engine.checked(c.JS_PromiseThen(engine.context, pending, continuation, c.pi_js_undefined()));
}
fn rejectExtensionCommand(owner: *sdk.State, input: c.JSValue) !void {
    const engine = owner.engine;
    const slash = try sdk.text(engine, "/");
    defer engine.freeValue(slash);
    const starts = try sdk.invoke(engine, input, "startsWith", &.{slash});
    defer engine.freeValue(starts);
    if (c.JS_ToBool(engine.context, starts) != 1) return;
    const space = try sdk.text(engine, " ");
    defer engine.freeValue(space);
    const index = try sdk.invoke(engine, input, "indexOf", &.{space});
    defer engine.freeValue(index);
    const one = c.JS_NewInt32(engine.context, 1);
    const selected = if (c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1)))
        try sdk.invoke(engine, input, "slice", &.{one})
    else
        try sdk.invoke(engine, input, "slice", &.{ one, index });
    defer engine.freeValue(selected);
    const commands = try @import("native_sdk_commands.zig").resolve(owner);
    defer engine.freeValue(commands);
    // ExtensionRunner.getCommand calls the mutable Array.find even when the
    // resolved command list is empty. Its predicate compares without coercion.
    const find = try sdk.get(engine, commands, "find");
    defer engine.freeValue(find);
    var roots = [_]c.JSValue{selected};
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, commandMatches, "", 1, 0, roots.len, &roots));
    defer engine.freeValue(predicate);
    var parameters = [_]c.JSValue{predicate};
    const found = try engine.checked(c.JS_Call(engine.context, find, commands, 1, &parameters));
    defer engine.freeValue(found);
    if (c.JS_ToBool(engine.context, found) != 1) return;
    const name = try engine.toString(selected);
    defer engine.gpa.free(name);
    const message = try std.fmt.allocPrint(engine.gpa, "Extension command \"/{s}\" cannot be queued. Use prompt() or execute the command when not streaming.", .{name});
    defer engine.gpa.free(message);
    _ = try sdk.sourceError(engine, message);
}
fn commandMatches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const name = sdk.get(engine, if (argc > 0) args[0] else c.pi_js_undefined(), "invocationName") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(name);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, name, roots[0])));
}
fn afterInput(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return completeInput(engine, roots[0], roots[1], roots[2], if (argc > 0) args[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| sdk.fail(engine, err);
}
fn isAction(engine: *em.Engine, result: c.JSValue, name: []const u8) !bool {
    if (c.JS_IsNull(result) or c.JS_IsUndefined(result)) return false;
    const action = try sdk.get(engine, result, "action");
    defer engine.freeValue(action);
    const expected = try sdk.text(engine, name);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, action, expected);
}
fn completeInput(engine: *em.Engine, receiver: c.JSValue, initial_text: c.JSValue, initial_images: c.JSValue, result: c.JSValue, behavior: Behavior) !c.JSValue {
    if (try isAction(engine, result, "handled")) return sdk.text(engine, "handled");
    const transformed = try isAction(engine, result, "transform");
    const text = if (transformed) try sdk.get(engine, result, "text") else c.JS_DupValue(engine.context, initial_text);
    defer engine.freeValue(text);
    const candidate_images = if (transformed) try sdk.get(engine, result, "images") else c.pi_js_undefined();
    defer engine.freeValue(candidate_images);
    const images = if (c.JS_IsNull(candidate_images) or c.JS_IsUndefined(candidate_images)) initial_images else candidate_images;
    const owner = try sdk.state(engine, receiver);
    const expanded = try @import("native_sdk_prompt_expansion.zig").expand(owner, receiver, text);
    defer engine.freeValue(expanded);
    try appendPrepared(owner, behavior, expanded, images);
    return sdk.text(engine, "queued");
}

//! Actual c268 transcript normalization over live guest values. The same
//! ordinary module functions serve pi-ai and the coding-agent summary owners.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = h.Engine;
const Scope = h.Scope;
const copy = @import("native_sdk_catalog_copy.zig");
const x = @import("native_sdk_catalog_values.zig");
const module_cache_key = "pi-private:ai-transcript-context";
const NormalizeFrame = h.Frame(enum { initial_message, messages });
extern "c" fn JS_PiArrayAppend(context: ?*c.JSContext, target: c.JSValue, position: *u32, iterable: c.JSValue) c_int;

pub fn exports(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(module_cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
    if (engine.native_module_values.get(module_cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(module_cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "createInitialSystemMessage", try v.ordinary(s, "createInitialSystemMessage", 2, initialCall, &.{}));
    try v.put(s, result, "normalizeContext", try v.ordinary(s, "normalizeContext", 1, normalizeCall, &.{}));
    return v.duplicate(s, result);
}
fn initialCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return initial(engine, v.arg(args, 0), v.arg(args, 1));
}
fn normalizeCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return normalize(engine, v.arg(args, 0));
}
fn nonemptyLength(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try h.binary(s, .greater, try v.get(s, value, "length"), v.number(s, 0))));
}
fn hasItems(engine: *Engine, value: c.JSValue) !bool {
    if (c.JS_IsUndefined(value)) return false;
    return h.truthy(engine, try h.expression(engine, nonemptyLength, .{value}));
}
pub fn initial(engine: *Engine, prompt: c.JSValue, tools: c.JSValue) !c.JSValue {
    const has_prompt = try hasItems(engine, prompt);
    const has_tools = try hasItems(engine, tools);
    if (!has_prompt and !has_tools) return c.pi_js_undefined();
    return h.expression(engine, initialRecord, .{ prompt, tools, has_tools });
}
fn toolsObject(s: *Scope, tools: c.JSValue, has_tools: bool) !c.JSValue {
    const result = try v.object(s);
    if (has_tools) try v.put(s, result, "toolsAdded", tools);
    return v.duplicate(s, result);
}
fn spreadTools(s: *Scope, target: c.JSValue, tools: c.JSValue, has_tools: bool) !void {
    const fields = try v.own(s, try h.expression(s.engine, toolsObject, .{ tools, has_tools }));
    var operations: x.Ops = .{ .s = s };
    try copy.into(&operations, target, fields);
}
fn initialRecord(s: *Scope, prompt: c.JSValue, tools: c.JSValue, has_tools: bool) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "role", try v.text(s, "system"));
    try v.put(s, result, "content", if (v.nullish(prompt)) try v.text(s, "") else prompt);
    try h.statement(s.engine, spreadTools, .{ result, tools, has_tools });
    try v.put(s, result, "timestamp", v.number(s, 0));
    return v.duplicate(s, result);
}
fn initialFromContext(s: *Scope, context: c.JSValue) !c.JSValue {
    const prompt = try v.get(s, context, "systemPrompt");
    const tools = try v.get(s, context, "tools");
    return initial(s.engine, prompt, tools);
}
fn prefixedMessages(s: *Scope, first: c.JSValue, context: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    try v.index(s, result, 0, first);
    const messages = try v.get(s, context, "messages");
    var position: u32 = 1;
    var operation: v.guest.Boundary = .{ .engine = s.engine };
    try operation.begin();
    try operation.finishStatus(JS_PiArrayAppend(s.engine.context, result, &position, messages));
    return v.duplicate(s, result);
}
fn contextRecord(s: *Scope, messages: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "messages", messages);
    return v.duplicate(s, result);
}
pub fn normalize(engine: *Engine, context: c.JSValue) !c.JSValue {
    var locals = NormalizeFrame.init(engine);
    return locals.finish(normalizeBody(engine, &locals, context));
}
fn normalizeBody(engine: *Engine, locals: *NormalizeFrame, context: c.JSValue) !c.JSValue {
    try locals.set(.initial_message, h.expression(engine, initialFromContext, .{context}));
    try locals.set(.messages, if (h.truthy(engine, locals.get(.initial_message)))
        h.expression(engine, prefixedMessages, .{ locals.get(.initial_message), context })
    else
        h.get(engine, context, "messages"));
    return h.expression(engine, contextRecord, .{locals.get(.messages)});
}

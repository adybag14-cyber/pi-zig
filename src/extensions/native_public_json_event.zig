//! Actual c268 modes/json-event.ts wire projection. The event graph stays live:
//! repeated getters, the "in" trap, rest exclusion, spread descriptors and
//! ordinary thrown DATA are all evaluated in Source order.
const v = @import("native_public_values.zig");
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const key = "\x00native.public.json-event";

pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return c.JS_DupValue(engine.context, cached);
    const candidate = try expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |cached| {
        var completion = v.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, cached));
        completion.release(candidate); return completion.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = v.owned.Completion.initVoid(engine, err);
        completion.release(candidate); try completion.finishVoid(); unreachable;
    };
    const result = c.JS_DupValue(engine.context, candidate);
    engine.native_module_values.putAssumeCapacity(key, candidate);
    return result;
}
fn expression(engine: *Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
fn createBody(s: *Scope) !c.JSValue {
    const assistant = try v.ordinary(s, "toJsonAssistantMessageEvent", 1, assistantEvent, &.{});
    const result = try v.object(s);
    try v.put(s, result, "toJsonEvent", try v.ordinary(s, "toJsonEvent", 1, jsonEvent, &.{assistant}));
    return v.duplicate(s, result);
}
fn fieldEqual(engine: *Engine, event: c.JSValue, name: [*:0]const u8, expected: []const u8) !bool {
    return c.JS_ToBool(engine.context, try expression(engine, fieldEqualBody, .{ event, name, expected })) == 1;
}
fn fieldEqualBody(s: *Scope, event: c.JSValue, name: [*:0]const u8, expected: []const u8) !c.JSValue {
    return v.boolean(s, try v.eq(s, try v.get(s, event, name), expected));
}
fn nestedField(s: *Scope, event: c.JSValue, first: [*:0]const u8, second: [*:0]const u8) !c.JSValue {
    const selected = try v.get(s, event, first);
    return v.duplicate(s, try v.get(s, selected, second));
}
fn messageRole(s: *Scope, event: c.JSValue) !c.JSValue {
    const role = try v.own(s, try expression(s.engine, nestedField, .{ event, @as([*:0]const u8, "message"), @as([*:0]const u8, "role") }));
    return v.boolean(s, try v.eq(s, role, "assistant"));
}
fn jsonEvent(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, jsonEventBody, .{ v.arg(args, 0), roots[0] });
}
fn jsonEventBody(s: *Scope, event: c.JSValue, assistant: c.JSValue) !c.JSValue {
    if (!try fieldEqual(s.engine, event, "type", "message_update")) return v.duplicate(s, event);
    if (c.JS_ToBool(s.engine.context, try expression(s.engine, messageRole, .{event})) != 1)
        return throwError(s, "message_update message is not an assistant message");
    const result = try v.object(s);
    try v.put(s, result, "type", try v.text(s, "message_update"));
    const usage = try v.own(s, try expression(s.engine, nestedField, .{ event, @as([*:0]const u8, "message"), @as([*:0]const u8, "usage") }));
    try v.put(s, result, "usage", usage);
    const delta = try v.call(s, assistant, c.pi_js_undefined(), &.{try v.get(s, event, "assistantMessageEvent")});
    try v.put(s, result, "assistantMessageEvent", delta);
    return v.duplicate(s, result);
}
fn throwError(s: *Scope, message: []const u8) !c.JSValue {
    const constructor = try v.global(s, "Error");
    const error_value = try v.construct(s, constructor, &.{try v.text(s, message)});
    return s.engine.checked(c.JS_Throw(s.engine.context, v.duplicate(s, error_value)));
}
fn assistantEvent(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, assistantBody, .{v.arg(args, 0)});
}
fn assistantBody(s: *Scope, event: c.JSValue) !c.JSValue {
    if (try fieldEqual(s.engine, event, "type", "toolcall_start")) {
        const tool_call = try v.own(s, try expression(s.engine, toolCallValue, .{event}));
        if (v.nullish(tool_call) or !try fieldEqual(s.engine, tool_call, "type", "toolCall"))
            return invalidToolCall(s, event);
        // These are actual Source lexical bindings, including the otherwise
        // unused _partial. They remain rooted through id/name access.
        const delta_event = try v.own(s, try destructuredRest(s, event));
        const result = try v.object(s);
        try copyProperties(s.engine, result, delta_event, null);
        try v.put(s, result, "id", try v.get(s, tool_call, "id"));
        try v.put(s, result, "toolName", try v.get(s, tool_call, "name"));
        return v.duplicate(s, result);
    }
    if (!try hasPartial(s.engine, event)) return v.duplicate(s, event);
    return destructuredRest(s, event);
}
fn toolCallValue(s: *Scope, event: c.JSValue) !c.JSValue {
    const content = try v.own(s, try expression(s.engine, nestedField, .{ event, @as([*:0]const u8, "partial"), @as([*:0]const u8, "content") }));
    var coercion: Scope = .{ .engine = s.engine }; var atom: c.JSAtom = c.JS_ATOM_NULL;
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try v.owned.finishVoid(&coercion, contentIndexAtom(&coercion, event, &atom));
    return v.duplicate(s, try v.guest.getAtom(s, content, atom));
}
fn contentIndexAtom(s: *Scope, event: c.JSValue, atom: *c.JSAtom) !void {
    const index = try v.get(s, event, "contentIndex");
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    atom.* = c.JS_ValueToAtom(s.engine.context, index);
    return boundary.finishStatus(if (atom.* == c.JS_ATOM_NULL) -1 else 0);
}
fn invalidToolCall(s: *Scope, event: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    const message = try v.own(s, try expression(s.engine, invalidToolCallMessage, .{event}));
    const error_value = try v.construct(s, constructor, &.{message});
    return s.engine.checked(c.JS_Throw(s.engine.context, v.duplicate(s, error_value)));
}
fn invalidToolCallMessage(s: *Scope, event: c.JSValue) !c.JSValue {
    const prefix = try v.text(s, "toolcall_start content at index ");
    const index = try v.stringify(s, try v.get(s, event, "contentIndex"));
    const start = try v.binary(s, 0, prefix, index);
    return v.duplicate(s, try v.binary(s, 0, start, try v.text(s, " is not a tool call")));
}
fn literalAtom(s: *Scope, name: [*:0]const u8) !c.JSAtom {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    // This snapshot covers only the raw non-guest intern operation.
    const generation = s.engine.native_allocation_generation;
    const atom = c.JS_NewAtom(s.engine.context, name);
    errdefer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    _ = s.engine.nativeCallbackResult(c.pi_js_undefined());
    if (c.JS_HasException(s.engine.context)) {
        const reason = c.JS_GetException(s.engine.context);
        const tag = c.pi_js_native_allocation_error_generation(reason);
        const distance = tag -% generation;
        if (tag != 0 and distance != 0 and distance <= s.engine.native_allocation_generation -% generation)
            c.JS_SetUncatchableError(s.engine.context, reason);
        _ = c.JS_Throw(s.engine.context, reason);
    }
    try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    return atom;
}
fn hasPartial(engine: *Engine, event: c.JSValue) !bool {
    return c.JS_ToBool(engine.context, try expression(engine, hasPartialBody, .{event})) == 1;
}
fn hasPartialBody(s: *Scope, event: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(event)) return v.typeError(s, "invalid 'in' operand");
    const atom = try literalAtom(s, "partial"); defer c.JS_FreeAtom(s.engine.context, atom);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const present = c.JS_HasProperty(s.engine.context, event, atom);
    try boundary.finishStatus(if (present < 0) present else 0);
    return v.boolean(s, present != 0);
}
fn destructuredRest(lexical: *Scope, event: c.JSValue) !c.JSValue {
    var binding: Scope = .{ .engine = lexical.engine };
    return v.owned.finishValue(&binding, destructuredRestBody(&binding, lexical, event));
}
fn destructuredRestBody(s: *Scope, lexical: *Scope, event: c.JSValue) !c.JSValue {
    // Object-pattern ToObject happens before the partial getter; its boxed
    // receiver is consumed after rest copying, before any later id/name get.
    const boxed = try v.guest.toObject(s, event);
    _ = try v.own(lexical, v.duplicate(s, try v.get(s, boxed, "partial")));
    return v.duplicate(s, try restEvent(s, boxed));
}
fn restEvent(s: *Scope, event: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    const excluded = try literalAtom(s, "partial"); defer c.JS_FreeAtom(s.engine.context, excluded);
    try copyProperties(s.engine, result, event, excluded);
    return result;
}
fn copyProperties(engine: *Engine, target: c.JSValue, source: c.JSValue, excluded: ?c.JSAtom) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, copyBody(&s, target, source, excluded));
}
fn copyBody(s: *Scope, target: c.JSValue, source: c.JSValue, excluded: ?c.JSAtom) !void {
    const boxed = try v.guest.toObject(s, source);
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const status = c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    defer if (names != null) c.JS_FreePropertyEnum(s.engine.context, names, count);
    try boundary.finishStatus(status);
    for (names[0..count]) |entry| {
        if (excluded != null and entry.atom == excluded.?) continue;
        if (!try enumerable(s.engine, boxed, entry.atom)) continue;
        var property: Scope = .{ .engine = s.engine };
        try v.owned.finishVoid(&property, copyProperty(&property, target, boxed, entry.atom));
    }
}
fn enumerable(engine: *Engine, source: c.JSValue, atom: c.JSAtom) !bool {
    var descriptor: c.JSPropertyDescriptor = undefined;
    var boundary: v.guest.Boundary = .{ .engine = engine }; try boundary.begin();
    const status = c.JS_GetOwnProperty(engine.context, &descriptor, source, atom);
    const outcome: anyerror!c.JSValue = if (boundary.finishStatus(status)) |_|
        c.JS_NewBool(engine.context, status != 0 and descriptor.flags & c.JS_PROP_ENUMERABLE != 0)
    else |err| err;
    var completion = v.owned.Completion.initValue(engine, outcome);
    if (status > 0) { completion.release(descriptor.value); completion.release(descriptor.getter); completion.release(descriptor.setter); }
    return c.JS_ToBool(engine.context, try completion.finishValue()) == 1;
}
fn copyProperty(s: *Scope, target: c.JSValue, source: c.JSValue, atom: c.JSAtom) !void {
    const value = try v.guest.getAtom(s, source, atom);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishStatus(c.JS_DefinePropertyValue(s.engine.context, target, atom, v.duplicate(s, value), c.JS_PROP_C_W_E));
}

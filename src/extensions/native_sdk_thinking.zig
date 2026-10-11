//! Source AgentSession thinking levels, clamping and transcript persistence.
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = engine_mod.c;
const levels = [_][:0]const u8{ "off", "minimal", "low", "medium", "high", "xhigh", "max" };
pub fn supports(engine: *engine_mod.Engine, model: c.JSValue) !bool {
    if (c.JS_IsNull(model) or c.JS_IsUndefined(model)) return false;
    const reasoning = try sdk.get(engine, model, "reasoning");
    defer engine.freeValue(reasoning);
    return c.JS_ToBool(engine.context, reasoning) == 1;
}
pub fn available(engine: *engine_mod.Engine, model: c.JSValue) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsNull(model) or c.JS_IsUndefined(model)) {
        for (levels) |level| try sdk.append(engine, result, try sdk.text(engine, level));
        return result;
    }
    if (!try supports(engine, model)) {
        try sdk.append(engine, result, try sdk.text(engine, "off"));
        return result;
    }
    for (levels, 0..) |level, index| {
        // The Source filter reads this observable property for every level.
        const map = try sdk.get(engine, model, "thinkingLevelMap");
        defer engine.freeValue(map);
        const mapped = if (c.JS_IsNull(map) or c.JS_IsUndefined(map)) c.pi_js_undefined() else try sdk.get(engine, map, level);
        defer engine.freeValue(mapped);
        if (c.JS_IsNull(mapped) or (index >= 5 and c.JS_IsUndefined(mapped))) continue;
        try sdk.append(engine, result, try sdk.text(engine, level));
    }
    return result;
}
fn contains(engine: *engine_mod.Engine, array: c.JSValue, value: c.JSValue) !bool {
    for (0..try sdk.length(engine, array)) |index| {
        const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, array, @intCast(index)));
        defer engine.freeValue(candidate);
        if (c.JS_IsStrictEqual(engine.context, value, candidate)) return true;
    }
    return false;
}
pub fn effective(engine: *engine_mod.Engine, model: c.JSValue, requested: c.JSValue) !c.JSValue {
    var choices = try available(engine, model);
    defer engine.freeValue(choices);
    if (try contains(engine, choices, requested)) return c.JS_DupValue(engine.context, requested);
    if (c.JS_IsNull(model) or c.JS_IsUndefined(model)) return sdk.text(engine, "off");
    // AgentSession asks for available levels before delegating an unsupported
    // request to the model clamp, which performs its own observable read.
    const clamped_choices = try available(engine, model);
    engine.freeValue(choices);
    choices = clamped_choices;
    var requested_index: ?usize = null;
    for (levels, 0..) |level, index| {
        const candidate = try sdk.text(engine, level);
        defer engine.freeValue(candidate);
        if (c.JS_IsStrictEqual(engine.context, requested, candidate)) {
            requested_index = index;
            break;
        }
    }
    if (requested_index) |start| {
        for (start..levels.len) |index| {
            const candidate = try sdk.text(engine, levels[index]);
            defer engine.freeValue(candidate);
            if (try contains(engine, choices, candidate)) return c.JS_DupValue(engine.context, candidate);
        }
        var index = start;
        while (index > 0) {
            index -= 1;
            const candidate = try sdk.text(engine, levels[index]);
            defer engine.freeValue(candidate);
            if (try contains(engine, choices, candidate)) return c.JS_DupValue(engine.context, candidate);
        }
    }
    return if (try sdk.length(engine, choices) != 0) engine.checked(c.JS_GetPropertyUint32(engine.context, choices, 0)) else sdk.text(engine, "off");
}
pub const Change = struct {
    level: c.JSValue,
    previous: c.JSValue,
    changed: bool,
    pub fn deinit(self: Change, engine: *engine_mod.Engine) void {
        engine.freeValue(self.level);
        engine.freeValue(self.previous);
    }
};
pub fn apply(engine: *engine_mod.Engine, session: c.JSValue, requested: c.JSValue, options: c.JSValue) !Change {
    const state = try sdk.state(engine, session);
    if (state.kind != .agent_session) return error.InvalidNativeSDKReceiver;
    const model = try sdk.agentField(state, "model");
    defer engine.freeValue(model);
    const level = try effective(engine, model, requested);
    errdefer engine.freeValue(level);
    const previous = try sdk.agentField(state, "thinkingLevel");
    errdefer engine.freeValue(previous);
    const changed = !c.JS_IsStrictEqual(engine.context, previous, level);
    try sdk.setAgentField(state, "thinkingLevel", level);
    const persist = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "persist");
    defer engine.freeValue(persist);
    if (c.JS_ToBool(engine.context, persist) == 1) {
        const settings = try sdk.publicField(state, "settingsManager");
        defer engine.freeValue(settings);
        const saved = try sdk.invoke(engine, settings, "setDefaultThinkingLevel", &.{requested});
        engine.freeValue(saved);
    }
    if (changed) {
        const manager = try sdk.publicField(state, "sessionManager");
        defer engine.freeValue(manager);
        const saved = try sdk.invoke(engine, manager, "appendThinkingLevelChange", &.{level});
        engine.freeValue(saved);
    }
    return .{ .level = level, .previous = previous, .changed = changed };
}

pub fn set(engine: *engine_mod.Engine, session: c.JSValue, requested: c.JSValue, options: c.JSValue) !void {
    const change = try apply(engine, session, requested, options);
    defer change.deinit(engine);
    if (!change.changed) return;
    const owner = try sdk.state(engine, session);
    const notification = try sdk.object(engine);
    defer engine.freeValue(notification);
    try sdk.put(engine, notification, "type", try sdk.text(engine, "thinking_level_changed"));
    try sdk.put(engine, notification, "level", c.JS_DupValue(engine.context, change.level));
    try sdk.emit(owner, notification);
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "level", c.JS_DupValue(engine.context, change.level));
    try sdk.put(engine, event, "previousLevel", c.JS_DupValue(engine.context, change.previous));
    const resources = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(resources);
    const pending = try @import("native_sdk_resources.zig").emitValue(engine, resources, owner.data, "thinking_level_select", event);
    engine.freeValue(pending);
}
pub fn cycle(engine: *engine_mod.Engine, session: c.JSValue, options: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, session);
    const model = try sdk.agentField(owner, "model");
    defer engine.freeValue(model);
    if (!try supports(engine, model)) return c.pi_js_undefined();
    const choices = try available(engine, model);
    defer engine.freeValue(choices);
    const current = try sdk.agentField(owner, "thinkingLevel");
    defer engine.freeValue(current);
    const count = try sdk.length(engine, choices);
    var next: usize = 0;
    for (0..count) |index| {
        const candidate = try engine.checked(c.JS_GetPropertyUint32(engine.context, choices, @intCast(index)));
        defer engine.freeValue(candidate);
        if (c.JS_IsStrictEqual(engine.context, candidate, current)) {
            next = (index + 1) % count;
            break;
        }
    }
    const chosen = if (count == 0) c.pi_js_undefined() else try engine.checked(c.JS_GetPropertyUint32(engine.context, choices, @intCast(next)));
    errdefer engine.freeValue(chosen);
    try set(engine, session, chosen, options);
    return chosen;
}

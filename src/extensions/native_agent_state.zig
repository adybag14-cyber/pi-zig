//! Actual Agent initial transcript and closure-backed mutable state.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
fn optional(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, name);
}
fn initialArray(scope: *Scope, initial: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try optional(scope, initial, name);
    return if (temp.nullish(value)) scope.array() else scope.invoke(value, "slice", &.{});
}
fn declarationCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return declaration(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
pub fn declaration(engine: *em.Engine, tool: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "name", try scope.get(tool, "name"));
    try scope.put(result, "description", try scope.get(tool, "description"));
    const outer_json = try scope.global("JSON");
    const parse_fn = try scope.get(outer_json, "parse");
    const inner_json = try scope.global("JSON");
    const stringify_fn = try scope.get(inner_json, "stringify");
    const parameters = try scope.get(tool, "parameters");
    const encoded = try scope.call(stringify_fn, inner_json, &.{parameters});
    try scope.put(result, "parameters", try scope.call(parse_fn, outer_json, &.{encoded}));
    if (!c.JS_IsUndefined(try scope.get(tool, "constrainedSampling"))) try scope.put(result, "constrainedSampling", try scope.get(tool, "constrainedSampling"));
    return c.JS_DupValue(engine.context, result);
}
pub fn create(engine: *em.Engine, initial: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = try initialArray(&scope, initial, "tools");
    const messages = try initialArray(&scope, initial, "messages");
    const initial_prompt = try optional(&scope, initial, "systemPrompt");
    const map_fn = try scope.get(tools, "map");
    const project = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, declarationCall, "toToolDeclaration", 1)));
    const declarations = try scope.call(map_fn, tools, &.{project});
    const has_prompt = !c.JS_IsUndefined(initial_prompt) and try scope.positive(try scope.get(initial_prompt, "length"));
    const has_tools = !c.JS_IsUndefined(declarations) and try scope.positive(try scope.get(declarations, "length"));
    const first = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, 0)));
    const first_role = try optional(&scope, first, "role");
    if (!scope.equal(first_role, try scope.text("system")) and (has_prompt or has_tools)) {
        const message = try scope.object();
        try scope.put(message, "role", try scope.text("system"));
        try scope.put(message, "content", if (temp.nullish(initial_prompt)) try scope.text("") else initial_prompt);
        if (has_tools) try scope.put(message, "toolsAdded", declarations);
        try scope.put(message, "timestamp", c.JS_NewInt32(engine.context, 0));
        _ = try scope.invoke(messages, "unshift", &.{message});
    }
    const box = try scope.object();
    try scope.put(box, "tools", tools);
    try scope.put(box, "messages", messages);
    const state = try scope.object();
    try accessor(engine, state, box, "systemPrompt", 0, false);
    const model = try optional(&scope, initial, "model");
    try scope.put(state, "model", if (temp.nullish(model)) try scope.own(try @import("native_sdk_agent_state.zig").defaultModel(engine)) else model);
    const thinking = try optional(&scope, initial, "thinkingLevel");
    try scope.put(state, "thinkingLevel", if (temp.nullish(thinking)) try scope.text("off") else thinking);
    try accessor(engine, state, box, "tools", 1, true);
    try accessor(engine, state, box, "messages", 2, true);
    try scope.put(state, "isStreaming", c.pi_js_bool(engine.context, 0));
    try scope.put(state, "streamingMessage", c.pi_js_undefined());
    try scope.put(state, "pendingToolCalls", try scope.own(try js.builtin(engine, "Set", &.{})));
    try scope.put(state, "errorMessage", c.pi_js_undefined());
    return c.JS_DupValue(engine.context, state);
}
fn accessor(engine: *em.Engine, state: c.JSValue, box: c.JSValue, name: [:0]const u8, magic: c_int, writable: bool) !void {
    const getter_name = try engine.gpa.allocSentinel(u8, 4 + name.len, 0);
    defer engine.gpa.free(getter_name);
    @memcpy(getter_name[0..4], "get ");
    @memcpy(getter_name[4..], name);
    var roots = [_]c.JSValue{box};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, field, getter_name, 0, magic, 1, &roots));
    var consumed = false;
    errdefer if (!consumed) engine.freeValue(getter);
    const setter = if (writable) setter: {
        const setter_name = try engine.gpa.allocSentinel(u8, 4 + name.len, 0);
        defer engine.gpa.free(setter_name);
        @memcpy(setter_name[0..4], "set ");
        @memcpy(setter_name[4..], name);
        break :setter try engine.checked(c.JS_NewCFunctionData2(engine.context, field, setter_name, 1, magic + 2, 1, &roots));
    } else c.pi_js_undefined();
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) {
        engine.freeValue(setter);
        return error.OutOfMemory;
    }
    defer c.JS_FreeAtom(engine.context, atom);
    consumed = true;
    if (c.JS_DefinePropertyGetSet(engine.context, state, atom, getter, setter, c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn field(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return fieldValue(engine, magic, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn fieldValue(engine: *em.Engine, magic: c_int, box: c.JSValue, value: c.JSValue) !c.JSValue {
    if (magic == 0) return @import("native_sdk_agent_state.zig").promptValue(engine, box);
    const name: [*:0]const u8 = if (magic == 1 or magic == 3) "tools" else "messages";
    if (magic < 3) return sdk.get(engine, box, name);
    const copied = try js.invoke(engine, value, "slice", &.{});
    try sdk.put(engine, box, name, copied);
    return c.pi_js_undefined();
}

//! Real before_agent_start initialization, lazy closures, event and reduction.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const dispatch = @import("native_sdk_public_runner_emit.zig");
const prompt = @import("native_sdk_prompt_render.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
fn renderCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, guarded: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return renderValue(engine, values[0], if (guarded != 0) values[1] else c.pi_js_undefined(), guarded != 0) catch |err| sdk.fail(engine, err);
}
fn renderValue(engine: *em.Engine, options: c.JSValue, runner: c.JSValue, guarded: bool) !c.JSValue {
    if (guarded) {
        const ignored = try js.invoke(engine, runner, "assertActive", &.{});
        engine.freeValue(ignored);
    }
    return prompt.render(engine, options);
}
pub fn initialize(engine: *em.Engine, retained: *dispatch.State) !void {
    retained.replace(engine, .current, try @import("native_sdk_prompt_normalize.zig").normalize(engine, retained.get(.parameter1)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const outer_object = try scope.global("Object");
    const define_properties = try scope.get(outer_object, "defineProperties");
    const fresh = try scope.object();
    const inner_object = try scope.global("Object");
    const get_descriptors = try scope.get(inner_object, "getOwnPropertyDescriptors");
    const original = try scope.invoke(retained.get(.runner), "createContext", &.{});
    const descriptors = try scope.call(get_descriptors, inner_object, &.{original});
    const context = try scope.call(define_properties, outer_object, &.{ fresh, descriptors });
    var values = [_]c.JSValue{ retained.get(.current), retained.get(.runner) };
    const getter = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, renderCall, "", 0, 1, values.len, &values)));
    try scope.set(context, "getSystemPrompt", getter);
    retained.replace(engine, .context, c.JS_DupValue(engine.context, context));
    retained.replace(engine, .aux, try sdk.array(engine));
}
pub fn prepare(engine: *em.Engine, retained: *dispatch.State) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = try scope.object();
    // Current Source copies each live trigger independently for every handler,
    // including enumerable symbols, primitive boxing and raw Proxy failures.
    // Fixed event fields then replace same-named caller properties in place.
    try js.spreadInto(engine, event, retained.get(.parameter0));
    try scope.put(event, "type", try scope.text("before_agent_start"));
    // Match actual pinned Node Source own-key order after the spread literal.
    try scope.put(event, "systemPromptOptions", retained.get(.current));
    var values = [_]c.JSValue{retained.get(.current)};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, renderCall, "get systemPrompt", 0, 0, values.len, &values));
    const atom = c.JS_NewAtom(engine.context, "systemPrompt");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, event, atom, getter, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    retained.replace(engine, .event, c.JS_DupValue(engine.context, event));
}
pub fn accept(engine: *em.Engine, retained: *dispatch.State, result: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(result)) return;
    if (scope.truthy(try scope.get(result, "message"))) {
        const push = try scope.get(retained.get(.aux), "push");
        _ = try scope.call(push, retained.get(.aux), &.{try scope.get(result, "message")});
    }
    if (!c.JS_IsUndefined(try scope.get(result, "systemPrompt"))) try scope.set(retained.get(.current), "forceSystemPrompt", try scope.get(result, "systemPrompt"));
}
pub fn output(engine: *em.Engine, retained: *dispatch.State) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "messages", c.JS_DupValue(engine.context, retained.get(.aux)));
    try sdk.put(engine, result, "systemPromptOptions", c.JS_DupValue(engine.context, retained.get(.current)));
    return result;
}

//! Real two-phase context reduction and transcript restoration over supplied refs.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const dispatch = @import("native_sdk_public_runner_emit.zig");
const replay = @import("native_sdk_transcript_replay.zig");
const c = em.c;
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn optional(engine: *em.Engine, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (nullish(value)) c.pi_js_undefined() else sdk.get(engine, value, name);
}
pub fn initialize(engine: *em.Engine, retained: *dispatch.State) !void {
    const clone = try js.global(engine, "structuredClone");
    defer engine.freeValue(clone);
    retained.replace(engine, .current, try js.call(engine, clone, c.pi_js_undefined(), &.{retained.get(.parameter0)}));
}
fn leadingSystem(engine: *em.Engine, messages: c.JSValue) !bool {
    const first = try sdk.get(engine, messages, "0");
    defer engine.freeValue(first);
    const role = try optional(engine, first, "role");
    defer engine.freeValue(role);
    const expected = try sdk.text(engine, "system");
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, role, expected);
}
pub fn prepare(engine: *em.Engine, retained: *dispatch.State) !void {
    if (retained.context_system) {
        retained.context_had_leading = try leadingSystem(engine, retained.get(.current));
    } else {
        retained.replace(engine, .aux, try replay.conversation(engine, retained.get(.current)));
        retained.replace(engine, .aux2, try js.invoke(engine, retained.get(.aux), "slice", &.{}));
    }
    const event = try sdk.object(engine);
    errdefer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, if (retained.context_system) "context_with_system" else "context"));
    try sdk.put(engine, event, "messages", c.JS_DupValue(engine.context, retained.get(if (retained.context_system) .current else .aux)));
    retained.replace(engine, .event, event);
}
fn sameCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return sameItem(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn sameItem(engine: *em.Engine, message: c.JSValue, index: c.JSValue, right: c.JSValue) !c.JSValue {
    const value = try js.getKey(engine, right, index);
    defer engine.freeValue(value);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, message, value)));
}
fn sameMessages(engine: *em.Engine, left: c.JSValue, right: c.JSValue) !bool {
    const left_length = try sdk.get(engine, left, "length");
    defer engine.freeValue(left_length);
    const right_length = try sdk.get(engine, right, "length");
    defer engine.freeValue(right_length);
    if (!c.JS_IsStrictEqual(engine.context, left_length, right_length)) return false;
    const every = try sdk.get(engine, left, "every");
    defer engine.freeValue(every);
    var roots = [_]c.JSValue{right};
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, sameCall, "", 2, 0, roots.len, &roots));
    defer engine.freeValue(predicate);
    const result = try js.call(engine, every, left, &.{predicate});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) == 1;
}
fn restore(engine: *em.Engine, current: c.JSValue, visible: c.JSValue, returned: c.JSValue) !c.JSValue {
    if (try sameMessages(engine, returned, visible)) return c.JS_DupValue(engine.context, current);
    const head = try replay.currentSystemMessage(engine, current);
    defer engine.freeValue(head);
    return if (c.JS_ToBool(engine.context, head) == 1) replay.arraySpread(engine, returned, head) else c.JS_DupValue(engine.context, returned);
}
pub fn accept(engine: *em.Engine, retained: *dispatch.State, result: c.JSValue) !void {
    const requested = try optional(engine, result, "messages");
    defer engine.freeValue(requested);
    if (retained.context_system) {
        if (!nullish(requested)) retained.replace(engine, .current, c.JS_DupValue(engine.context, requested));
        if (retained.context_had_leading and !try leadingSystem(engine, retained.get(.current))) try reportRemoval(engine, retained);
        return;
    }
    const returned = if (!nullish(requested)) c.JS_DupValue(engine.context, requested) else if (try sameMessages(engine, retained.get(.aux), retained.get(.aux2))) c.pi_js_undefined() else c.JS_DupValue(engine.context, retained.get(.aux));
    defer engine.freeValue(returned);
    if (c.JS_ToBool(engine.context, returned) != 1) return;
    retained.replace(engine, .current, try restore(engine, retained.get(.current), retained.get(.aux2), returned));
}
fn reportRemoval(engine: *em.Engine, retained: *dispatch.State) !void {
    const method = try sdk.get(engine, retained.get(.runner), "emitError");
    defer engine.freeValue(method);
    const report = try sdk.object(engine);
    defer engine.freeValue(report);
    try sdk.put(engine, report, "extensionPath", try sdk.get(engine, retained.get(.extension), "path"));
    try sdk.put(engine, report, "event", try sdk.text(engine, "context_with_system"));
    try sdk.put(engine, report, "error", try sdk.text(engine, "Handler removed the leading system message; the request has no prompt or initial tool declarations. Keep it at index 0 or replace a dropped prefix with getCurrentSystemMessage()."));
    const ignored = try js.call(engine, method, retained.get(.runner), &.{report});
    engine.freeValue(ignored);
}

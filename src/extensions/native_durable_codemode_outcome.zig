//! The exact value/error mapping between a nested durable tool and CodeMode's
//! VM. Schema values, including null, resolve even for an error tool result.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = em.c;
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn textOf(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (c.JS_IsString(value)) return value;
    if (!c.JS_IsArray(value)) return scope.text("");
    const parts = try scope.array();
    const text = try scope.text("text");
    for (0..try vm.length(scope.engine, value)) |index| {
        const part = try item(scope, value, index);
        if (c.JS_IsObject(part) and !c.JS_IsNull(part) and scope.equal(try scope.get(part, "type"), text)) _ = try scope.invoke(parts, "push", &.{try scope.get(part, "text")});
    }
    return scope.invoke(parts, "join", &.{try scope.text("\n")});
}
pub fn fromNested(engine: *em.Engine, name: c.JSValue, structured: bool, result: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.get(result, "structuredOutput");
    const value = if (structured) output else try textOf(&scope, output);
    const mapped = try scope.object();
    if (!scope.truthy(try scope.get(result, "isError")) or (structured and !c.JS_IsUndefined(value))) {
        try scope.put(mapped, "ok", c.pi_js_bool(engine.context, 1));
        // Source's object literal owns value even when that value is undefined.
        try scope.put(mapped, "value", value);
        return c.JS_DupValue(engine.context, mapped);
    }
    var message = if (structured) try scope.text("") else value;
    const diagnostics = try scope.get(result, "diagnostics");
    const messages = try scope.array();
    const error_severity = try scope.text("error");
    for (0..try vm.length(engine, diagnostics)) |index| {
        const diagnostic = try item(&scope, diagnostics, index);
        if (scope.equal(try scope.get(diagnostic, "severity"), error_severity)) _ = try scope.invoke(messages, "push", &.{try scope.get(diagnostic, "message")});
    }
    const errors = try scope.invoke(messages, "join", &.{try scope.text("\n")});
    if (!scope.truthy(message)) message = errors;
    if (!scope.truthy(message)) message = try scope.concat(try scope.concat(try scope.text("Tool "), name), try scope.text(" failed"));
    try scope.put(mapped, "ok", c.pi_js_bool(engine.context, 0));
    try scope.put(mapped, "message", message);
    if (!c.JS_IsUndefined(value)) {
        const properties = try scope.object();
        try scope.put(properties, "structuredOutput", value);
        try scope.put(mapped, "properties", properties);
    }
    return c.JS_DupValue(engine.context, mapped);
}

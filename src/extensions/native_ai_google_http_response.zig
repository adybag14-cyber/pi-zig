//! Pinned SDK HttpResponse wrapper over an actual native web Response instance.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const cache_key = "\x00native-google-http-response";
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const response = if (args.len > 0) args[0] else c.pi_js_undefined();
    const headers = try scope.object();
    var entries = try v.iterator(&scope, try scope.invoke(try scope.get(response, "headers"), "entries", &.{}));
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer engine.freeValue(entry);
        try v.js.setKey(engine, headers, try v.at(&scope, entry, 0), try v.at(&scope, entry, 1));
    }
    const result = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.set(result, "headers", headers);
    try scope.set(result, "responseInternal", response);
    return c.JS_DupValue(engine.context, result);
}
fn json(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try scope.invoke(try scope.get(receiver, "responseInternal"), "json", &.{}));
}
pub fn constructor(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |value| return c.JS_DupValue(engine.context, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const result = try scope.own(try @import("native_class.zig").constructor(engine, "HttpResponse", 1, prototype, construct, &.{}));
    const method = try scope.own(try @import("native_node_function.zig").createMethod(engine, "json", 0, json, &.{}));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "json", c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, result));
    return c.JS_DupValue(engine.context, result);
}
pub fn wrap(scope: *Scope, response: c.JSValue) !c.JSValue {
    const class = try scope.own(try constructor(scope.engine));
    var args = [_]c.JSValue{response};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, class, args.len, &args)));
}

//! Source Mistral Headers construction, sequential overrides and null tombstones.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;

pub fn create(scope: *Scope, model: c.JSValue, api_key: c.JSValue, options: c.JSValue) !c.JSValue {
    try @import("native_headers.zig").install(scope.engine);
    const initial = try scope.object();
    try scope.put(initial, "User-Agent", try scope.text(@import("../ai/pi_user_agent.zig").value));
    try scope.put(initial, "accept", try scope.text("text/event-stream"));
    try scope.put(initial, "authorization", try scope.concat(try scope.text("Bearer "), try scope.stringify(api_key)));
    try scope.put(initial, "content-type", try scope.text("application/json"));
    const headers = try scope.own(try v.js.builtin(scope.engine, "Headers", &.{initial}));
    try apply(scope, headers, try scope.get(model, "headers"));
    try apply(scope, headers, try v.optional(scope, options, "headers"));
    const explicit = try has(scope, try scope.get(model, "headers")) or try has(scope, try v.optional(scope, options, "headers"));
    if (try @import("native_ai_mistral_request.zig").cache(scope, options) and !explicit) {
        _ = try scope.invoke(headers, "set", &.{ try scope.text("x-affinity"), try scope.get(options, "sessionId") });
    }
    return headers;
}

fn apply(scope: *Scope, headers: c.JSValue, overrides: c.JSValue) !void {
    if (!scope.truthy(overrides)) return;
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{overrides}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |row| {
        defer scope.engine.freeValue(row);
        const name = try v.at(scope, row, 0);
        const value = try v.at(scope, row, 1);
        _ = if (c.JS_IsNull(value)) try scope.invoke(headers, "delete", &.{name}) else try scope.invoke(headers, "set", &.{ name, value });
    }
}

fn has(scope: *Scope, overrides: c.JSValue) !bool {
    if (!scope.truthy(overrides)) return false;
    const Predicate = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return c.pi_js_bool(engine.context, @intFromBool(try v.eq(&row, try row.invoke(if (args.len > 0) args[0] else c.pi_js_undefined(), "toLowerCase", &.{}), "x-affinity")));
        }
    };
    const names = try scope.invoke(try scope.global("Object"), "keys", &.{overrides});
    const predicate = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Predicate.call, &.{}));
    return scope.truthy(try scope.invoke(names, "some", &.{predicate}));
}

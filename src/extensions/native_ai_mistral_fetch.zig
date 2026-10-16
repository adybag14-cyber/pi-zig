//! Mistral's injectable fetch and Response/header/error-body observations.
//! Successful bodies pass directly to the VM generator's real reader. There
//! is no ordinary byte iterator or second Promise around reader.read().
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const Method = enum { begin, body, signal, next, close };
pub fn open(engine: *v.em.Engine, fetch: c.JSValue, url: c.JSValue, init: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "options", options);
    inline for (.{ "signal", "response", "body" }) |key| try scope.put(owner, key, c.pi_js_undefined());
    inline for (.{ "closed", "errorBodySent", "badResponse" }) |key| try scope.put(owner, key, c.pi_js_bool(engine.context, 0));
    const pending = try flow.create(engine, owner);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const output = try scope.object();
    try scope.put(output, "ready", pending.promise);
    const events = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return operation(host, roots[0], method);
            }
        };
        const function = try scope.own(try @import("native_node_function.zig").createArrow(engine, field.name, 0, Adapter.call, &.{owner}));
        if (method == .next) try scope.put(events, "next", function) else try scope.put(output, field.name, function);
        if (method == .close) try scope.put(output, "cancel", function);
    }
    try scope.put(output, "events", events);
    const result = scope.call(fetch, c.pi_js_undefined(), &.{ url, init }) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return c.JS_DupValue(engine.context, output);
    };
    try flow.wait(ready, engine, pending.owner, result, 0);
    return c.JS_DupValue(engine.context, output);
}
fn ready(engine: *v.em.Engine, pending: c.JSValue, response: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, pending, true, response);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(try scope.get(pending, "agent"), "response", response);
    // Optional onResponse short-circuits metadata argument evaluation in Source.
    try flow.settle(engine, pending, false, response);
}
fn operation(engine: *v.em.Engine, owner: c.JSValue, method: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .begin => {
            const response = try scope.get(owner, "response");
            const ok = scope.truthy(try scope.get(response, "ok"));
            try scope.put(owner, "badResponse", c.pi_js_bool(engine.context, @intFromBool(!ok)));
            if (ok) {
                // Source reads body once for the guard and once for the
                // generator argument, then evaluates options?.signal.
                if (!scope.truthy(try scope.get(response, "body"))) return v.errorText(&scope, try scope.text("Mistral response has no body"));
                try scope.put(owner, "body", try scope.get(response, "body"));
                try scope.put(owner, "signal", try v.optional(&scope, try scope.get(owner, "options"), "signal"));
            }
            return c.pi_js_bool(engine.context, @intFromBool(ok));
        },
        .body, .signal => return c.JS_DupValue(engine.context, try scope.get(owner, if (method == .body) "body" else "signal")),
        .close => {
            // No reader is acquired during request preparation. Once consumed,
            // the actual VM generator exclusively owns cancel/release finally.
            try scope.put(owner, "closed", c.pi_js_bool(engine.context, 1));
            return c.pi_js_undefined();
        },
        .next => {
            const pending = try flow.create(engine, owner);
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            errorBody(&scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        },
    }
}
fn iteration(scope: *Scope, pending: c.JSValue, value: c.JSValue, done: bool) !void {
    const result = try scope.object();
    try scope.put(result, "value", value);
    try scope.put(result, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    try flow.settle(scope.engine, pending, false, result);
}
fn errorBody(scope: *Scope, pending: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    if (scope.truthy(try scope.get(owner, "closed")) or scope.truthy(try scope.get(owner, "errorBodySent"))) return iteration(scope, pending, c.pi_js_undefined(), true);
    if (!scope.truthy(try scope.get(owner, "badResponse"))) return error.NativeMistralErrorBodyIteratorOnly;
    try scope.put(owner, "errorBodySent", c.pi_js_bool(scope.engine.context, 1));
    try flow.wait(readErrorBody, scope.engine, pending, try scope.invoke(try scope.get(owner, "response"), "text", &.{}), 0);
}
fn readErrorBody(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, pending, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const response = try scope.get(try scope.get(pending, "agent"), "response");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("error_body"));
    try scope.put(event, "body", value);
    try scope.put(event, "status", try scope.get(response, "status"));
    try scope.put(event, "statusText", try scope.get(response, "statusText"));
    try iteration(&scope, pending, event, false);
}

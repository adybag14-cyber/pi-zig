//! Mistral's injectable fetch/Response reader ownership and getter ordering.
//! The caller owns header-timeout signals and awaits onResponse before begin.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const Method = enum { begin, next, close, abort_reader };
pub fn open(engine: *v.em.Engine, fetch: c.JSValue, url: c.JSValue, init: c.JSValue, signal: c.JSValue, before_read: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "signal", signal);
    try scope.put(owner, "beforeRead", before_read);
    inline for (.{ "started", "closed", "done", "errorBodySent", "badResponse" }) |key| try scope.put(owner, key, c.pi_js_bool(engine.context, 0));
    inline for (.{ "response", "body", "reader", "abortReader" }) |key| try scope.put(owner, key, c.pi_js_undefined());
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
        const function = try scope.own(try @import("native_node_function.zig").createArrow(engine, if (method == .abort_reader) "onAbort" else field.name, 0, Adapter.call, &.{owner}));
        switch (method) {
            .begin, .close => try scope.put(output, field.name, function),
            .next => try scope.put(events, "next", function),
            .abort_reader => try scope.put(owner, "abortReader", function),
        }
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
    const owner = try scope.get(pending, "agent");
    try scope.put(owner, "response", response);
    // Optional onResponse short-circuits argument evaluation in Source. Keep
    // the live Response here; its metadata is read only when a hook exists.
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
                if (!scope.truthy(try scope.get(response, "body"))) return v.errorText(&scope, try scope.text("Mistral response has no body"));
                try scope.put(owner, "body", try scope.get(response, "body"));
            }
            return c.pi_js_bool(engine.context, @intFromBool(ok));
        },
        .abort_reader => {
            const cancelled = try scope.invoke(try scope.get(owner, "reader"), "cancel", &.{});
            const Ignore = struct {
                fn call(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                    return c.pi_js_undefined();
                }
            };
            _ = try scope.invoke(cancelled, "catch", &.{try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 0, Ignore.call, &.{}))});
            return c.pi_js_undefined();
        },
        .next, .close => {
            const pending = try flow.create(engine, owner);
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            if (method == .next) advance(&scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err) else cleanup(&scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
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
fn checkAbort(scope: *Scope, owner: c.JSValue) !void {
    const signal = try scope.get(owner, "signal");
    if (scope.truthy(try v.optional(scope, signal, "aborted"))) {
        _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, try scope.get(signal, "reason"))));
        unreachable;
    }
}
fn advance(scope: *Scope, pending: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    if (scope.truthy(try scope.get(owner, "closed")) or scope.truthy(try scope.get(owner, "done"))) return iteration(scope, pending, c.pi_js_undefined(), true);
    if (scope.truthy(try scope.get(owner, "badResponse"))) {
        if (scope.truthy(try scope.get(owner, "errorBodySent"))) return iteration(scope, pending, c.pi_js_undefined(), true);
        try scope.put(owner, "errorBodySent", c.pi_js_bool(scope.engine.context, 1));
        return flow.wait(read, scope.engine, pending, try scope.invoke(try scope.get(owner, "response"), "text", &.{}), 1);
    }
    if (!scope.truthy(try scope.get(owner, "started"))) {
        try scope.put(owner, "reader", try scope.invoke(try scope.get(owner, "body"), "getReader", &.{}));
        const before = try scope.get(owner, "beforeRead");
        if (!v.nullish(before)) _ = try scope.call(before, c.pi_js_undefined(), &.{});
        const signal = try scope.get(owner, "signal");
        if (!c.JS_IsUndefined(signal)) {
            const options = try scope.object();
            try scope.put(options, "once", c.pi_js_bool(scope.engine.context, 1));
            _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), try scope.get(owner, "abortReader"), options });
        }
        try scope.put(owner, "started", c.pi_js_bool(scope.engine.context, 1));
    }
    try checkAbort(scope, owner);
    try flow.wait(read, scope.engine, pending, try scope.invoke(try scope.get(owner, "reader"), "read", &.{}), 0);
}
fn read(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, pending, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(pending, "agent");
    if (stage == 1) {
        const response = try scope.get(owner, "response");
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("error_body"));
        try scope.put(event, "body", value);
        try scope.put(event, "status", try scope.get(response, "status"));
        try scope.put(event, "statusText", try scope.get(response, "statusText"));
        return iteration(&scope, pending, event, false);
    }
    // Destructuring the awaited reader record precedes the second abort check.
    // Read value even for done records, matching Source's const { done, value }.
    const done_value = try scope.get(value, "done");
    const bytes = try scope.get(value, "value");
    try checkAbort(&scope, owner);
    const done = scope.truthy(done_value);
    if (done) {
        try scope.put(owner, "done", c.pi_js_bool(engine.context, 1));
        return iteration(&scope, pending, c.pi_js_undefined(), true);
    }
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("bytes"));
    try scope.put(event, "data", bytes);
    try iteration(&scope, pending, event, false);
}
fn cleanup(scope: *Scope, pending: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    if (scope.truthy(try scope.get(owner, "closed"))) return flow.settle(scope.engine, pending, false, c.pi_js_undefined());
    try scope.put(owner, "closed", c.pi_js_bool(scope.engine.context, 1));
    if (!scope.truthy(try scope.get(owner, "started"))) return flow.settle(scope.engine, pending, false, c.pi_js_undefined());
    const signal = try scope.get(owner, "signal");
    if (!c.JS_IsUndefined(signal)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), try scope.get(owner, "abortReader") });
    const generation = scope.engine.native_allocation_generation;
    const result = scope.invoke(try scope.get(owner, "reader"), "cancel", &.{}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return released(scope, pending);
    };
    try flow.wait(closed, scope.engine, pending, result, 0);
}
fn closed(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) _ = value; // Source ignores reader.cancel rejection during finally.
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try released(&scope, pending);
}
fn released(scope: *Scope, pending: c.JSValue) !void {
    const generation = scope.engine.native_allocation_generation;
    _ = scope.invoke(try scope.get(try scope.get(pending, "agent"), "reader"), "releaseLock", &.{}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return flow.settle(scope.engine, pending, false, c.pi_js_undefined());
    };
    try flow.settle(scope.engine, pending, false, c.pi_js_undefined());
}

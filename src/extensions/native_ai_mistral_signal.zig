//! Mistral's response-header timeout signal and Source combined-signal cleanup.
//! Reader consumption uses the caller signal after cleanup, not this timeout.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;

pub fn create(scope: *Scope, caller: c.JSValue, timeout_ms: c.JSValue) !c.JSValue {
    const owner = try scope.object();
    const timeout = try scope.invoke(try scope.global("AbortSignal"), "timeout", &.{timeout_ms});
    try scope.put(owner, "timeoutSignal", timeout);
    const listeners = try scope.array();
    try scope.put(owner, "listeners", listeners);
    if (c.JS_IsUndefined(caller)) {
        try scope.put(owner, "signal", timeout);
        return owner;
    }
    const controller = try scope.own(try v.js.builtin(scope.engine, "AbortController", &.{}));
    try scope.put(owner, "controller", controller);
    try scope.put(owner, "signal", try scope.get(controller, "signal"));
    for ([_]c.JSValue{ caller, timeout }) |signal| {
        if (scope.truthy(try scope.get(signal, "aborted"))) {
            try abort(scope, controller, signal);
            break;
        }
        const Callback = struct {
            fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                engine.native_exception_diagnostics_suppressed += 1;
                defer engine.native_exception_diagnostics_suppressed -= 1;
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                try abort(&row, roots[0], roots[1]);
                return c.pi_js_undefined();
            }
        };
        const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "listener", 0, Callback.call, &.{ controller, signal }));
        const options = try scope.object();
        try scope.put(options, "once", c.pi_js_bool(scope.engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), callback, options });
        const entry = try scope.object();
        try scope.put(entry, "signal", signal);
        try scope.put(entry, "listener", callback);
        _ = try scope.invoke(listeners, "push", &.{entry});
    }
    return owner;
}

fn abort(scope: *Scope, controller: c.JSValue, signal: c.JSValue) !void {
    if (!scope.truthy(try scope.get(try scope.get(controller, "signal"), "aborted"))) {
        _ = try scope.invoke(controller, "abort", &.{try scope.get(signal, "reason")});
    }
}

pub fn cleanup(scope: *Scope, owner: c.JSValue) !void {
    var rows = try v.iterator(scope, try scope.get(owner, "listeners"));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        _ = try scope.invoke(try scope.get(entry, "signal"), "removeEventListener", &.{ try scope.text("abort"), try scope.get(entry, "listener") });
    }
}

pub fn headerError(scope: *Scope, owner: c.JSValue, caller: c.JSValue, timeout_ms: c.JSValue, original: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(try scope.get(owner, "timeoutSignal"), "aborted")) and !scope.truthy(try v.optional(scope, caller, "aborted"))) {
        const message = try scope.concat(try scope.concat(try scope.text("Mistral response headers timed out after "), try scope.stringify(timeout_ms)), try scope.text("ms"));
        return scope.own(try v.js.builtin(scope.engine, "Error", &.{message}));
    }
    return original;
}

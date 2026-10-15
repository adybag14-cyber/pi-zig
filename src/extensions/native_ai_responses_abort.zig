//! Owner-visible port of Source combineAbortSignals. Caller brands, reasons and
//! listener functions remain actual JS values; cleanup removes exact listeners.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const Method = enum { abort, cleanup };
fn callback(scope: *Scope, comptime method: Method, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            if (method == .abort) {
                if (!row.truthy(try row.get(try row.get(values[0], "signal"), "aborted"))) _ = try row.invoke(values[0], "abort", &.{try row.get(values[1], "reason")});
            } else {
                var iterator = try v.iterator(&row, values[0]);
                defer iterator.deinit();
                errdefer iterator.closePreserving();
                while (try iterator.next()) |entry| {
                    defer engine.freeValue(entry);
                    _ = try row.invoke(try row.get(entry, "signal"), "removeEventListener", &.{ try row.text("abort"), try row.get(entry, "listener") });
                }
            }
            return c.pi_js_undefined();
        }
    };
    return scope.own(try @import("native_node_function.zig").create(scope.engine, if (method == .abort) "listener" else "cleanup", 0, Adapter.call, roots));
}
pub fn combine(scope: *Scope, signals: []const c.JSValue) !c.JSValue {
    const active = try scope.array();
    for (signals) |signal| if (!c.JS_IsUndefined(signal)) {
        _ = try scope.invoke(active, "push", &.{signal});
    };
    const result = try scope.object();
    const listeners = try scope.array();
    const count = try v.length(scope, active);
    if (count == 1) try scope.put(result, "signal", try v.at(scope, active, 0));
    if (count > 1) {
        const controller = try scope.own(try v.js.builtin(scope.engine, "AbortController", &.{}));
        var iterator = try v.iterator(scope, active);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |signal| {
            defer scope.engine.freeValue(signal);
            const listener = try callback(scope, .abort, &.{ controller, signal });
            if (scope.truthy(try scope.get(signal, "aborted"))) {
                _ = try scope.call(listener, c.pi_js_undefined(), &.{});
                break;
            }
            const once = try scope.object();
            try scope.put(once, "once", c.pi_js_bool(scope.engine.context, 1));
            _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), listener, once });
            const entry = try scope.object();
            try scope.put(entry, "signal", signal);
            try scope.put(entry, "listener", listener);
            _ = try scope.invoke(listeners, "push", &.{entry});
        }
        try scope.put(result, "signal", try scope.get(controller, "signal"));
    }
    try scope.put(result, "cleanup", try callback(scope, .cleanup, &.{listeners}));
    return result;
}

//! Native owned HTTP byte records exposed through a reader-style async
//! iterator. Only this boundary unwraps worker records; SDK layers see bytes.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
pub fn create(engine: *v.em.Engine, transport: c.JSValue, convert_failure: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try @import("native_ai_openai_sdk_iterator.zig").state(&scope);
    try scope.put(owner, "transport", transport);
    try scope.put(owner, "events", try scope.get(transport, "events"));
    try scope.put(owner, "convertFailure", convert_failure);
    try scope.put(owner, "closed", c.pi_js_bool(engine.context, 0));
    const iterator = try scope.object();
    const Adapter = struct {
        fn self(host: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return c.JS_DupValue(host.context, receiver);
        }
        fn next(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const pending = try flow.create(host, roots[0]);
            defer host.freeValue(pending.owner);
            errdefer host.freeValue(pending.promise);
            if (row.truthy(try row.get(roots[0], "closed"))) try flow.settle(host, pending.owner, false, try result(&row, c.pi_js_undefined(), true)) else {
                const read = row.invoke(try row.get(roots[0], "events"), "next", &.{}) catch |err| {
                    const reason = flow.reason(host, err);
                    defer host.freeValue(reason);
                    try continued(host, pending.owner, reason, true, 0);
                    return pending.promise;
                };
                try flow.wait(continued, host, pending.owner, read, 0);
            }
            return pending.promise;
        }
        fn close(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const pending = try flow.create(host, roots[0]);
            defer host.freeValue(pending.owner);
            errdefer host.freeValue(pending.promise);
            try row.put(roots[0], "closed", c.pi_js_bool(host.context, 1));
            const canceled = row.invoke(try row.get(roots[0], "transport"), "cancel", &.{}) catch |err| {
                try flow.rejectError(host, pending.owner, err);
                return pending.promise;
            };
            try flow.wait(continued, host, pending.owner, canceled, 1);
            return pending.promise;
        }
    };
    inline for (.{ .{ "next", Adapter.next }, .{ "return", Adapter.close } }) |method| try scope.put(iterator, method[0], try scope.own(try @import("native_node_function.zig").createMethod(engine, method[0], 0, method[1], &.{owner})));
    const symbol = try scope.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
    try v.js.setKey(engine, iterator, symbol, try scope.own(try @import("native_node_function.zig").createMethod(engine, "[Symbol.asyncIterator]", 0, Adapter.self, &.{})));
    return c.JS_DupValue(engine.context, iterator);
}
fn result(scope: *Scope, value: c.JSValue, done: bool) !c.JSValue {
    const output = try scope.object();
    try scope.put(output, "value", value);
    try scope.put(output, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    return output;
}
fn continued(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(pending, "agent");
    if (rejected) {
        const conversion = try scope.get(owner, "convertFailure");
        const reason = if (v.nullish(conversion)) value else try scope.call(conversion, c.pi_js_undefined(), &.{value});
        return flow.settle(engine, pending, true, reason);
    }
    if (stage == 1 or scope.truthy(try scope.get(value, "done"))) {
        try scope.put(owner, "closed", c.pi_js_bool(engine.context, 1));
        return flow.settle(engine, pending, false, try result(&scope, c.pi_js_undefined(), true));
    }
    const record = try scope.get(value, "value");
    if (!try v.eq(&scope, try scope.get(record, "type"), "bytes")) return error.NativeOpenAISdkBodyRequiresByteFraming;
    try flow.settle(engine, pending, false, try result(&scope, try scope.get(record, "data"), false));
}

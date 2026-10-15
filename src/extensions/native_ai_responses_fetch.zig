//! Custom fetch adapter preserving the actual Response/reader and promise errors.
//! Reads only on iterator demand. All pending read/decoder/abort roots are VM values.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
pub fn open(engine: *v.em.Engine, fetch: c.JSValue, url: c.JSValue, init: c.JSValue) !c.JSValue {
    return openMode(engine, fetch, url, init, false);
}
pub fn openBytes(engine: *v.em.Engine, fetch: c.JSValue, url: c.JSValue, init: c.JSValue) !c.JSValue {
    return openMode(engine, fetch, url, init, true);
}
fn openMode(engine: *v.em.Engine, fetch: c.JSValue, url: c.JSValue, init: c.JSValue, bytes: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "bytes", c.pi_js_bool(engine.context, @intFromBool(bytes)));
    try scope.put(owner, "buffer", try scope.text(""));
    inline for (.{ "done", "closed", "errorBodySent" }) |key| try scope.put(owner, key, c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "reader", c.pi_js_undefined());
    const decoder = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.global("TextDecoder"), 0, null)));
    try scope.put(owner, "decoder", decoder);
    const pending = try flow.create(engine, owner);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const output = try scope.object();
    const iterator = try scope.object();
    const Adapter = struct {
        fn next(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const step = try flow.create(host, roots[0]);
            defer host.freeValue(step.owner);
            errdefer host.freeValue(step.promise);
            advance(&row, step.owner) catch |err| try flow.rejectError(host, step.owner, err);
            return step.promise;
        }
        fn cancel(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            try row.put(roots[0], "closed", c.pi_js_bool(host.context, 1));
            const reader = try row.get(roots[0], "reader");
            return if (v.nullish(reader)) c.pi_js_undefined() else v.js.invoke(host, reader, "cancel", &.{});
        }
    };
    try scope.put(iterator, "next", try scope.own(try @import("native_node_function.zig").create(engine, "next", 0, Adapter.next, &.{owner})));
    const cancel = try scope.own(try @import("native_node_function.zig").create(engine, "cancel", 0, Adapter.cancel, &.{owner}));
    try scope.put(output, "cancel", cancel);
    try scope.put(output, "events", iterator);
    try scope.put(output, "ready", pending.promise);
    const promise = scope.call(fetch, c.pi_js_undefined(), &.{ url, init }) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return c.JS_DupValue(engine.context, output);
    };
    try flow.wait(ready, engine, pending.owner, promise, 0);
    return c.JS_DupValue(engine.context, output);
}
fn ready(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, pending, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    completeReady(&scope, pending, value) catch |err| try flow.rejectError(engine, pending, err);
}
fn completeReady(scope: *Scope, pending: c.JSValue, response: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    try scope.put(owner, "response", response);
    const head = try scope.object();
    try scope.put(head, "status", try scope.get(response, "status"));
    try scope.put(head, "statusText", try scope.get(response, "statusText"));
    try scope.put(head, "headers", try scope.invoke(try scope.global("Object"), "fromEntries", &.{try scope.invoke(try scope.get(response, "headers"), "entries", &.{})}));
    try scope.put(owner, "head", head);
    if (scope.truthy(try scope.get(response, "ok"))) {
        const body = try scope.get(response, "body");
        if (v.nullish(body)) try scope.put(owner, "done", c.pi_js_bool(scope.engine.context, 1)) else try scope.put(owner, "reader", try scope.invoke(body, "getReader", &.{}));
    }
    try flow.settle(scope.engine, pending, false, head);
}
fn settle(scope: *Scope, pending: c.JSValue, value: c.JSValue, done: bool) !void {
    const result = try scope.object();
    try scope.put(result, "value", value);
    try scope.put(result, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    try flow.settle(scope.engine, pending, false, result);
}
fn frame(scope: *Scope, block: c.JSValue) !c.JSValue {
    const lines = try scope.invoke(block, "split", &.{try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("\\r\\n|\\r|\\n")}))});
    const data = try scope.array();
    var event = c.pi_js_null();
    var rows = try v.iterator(scope, lines);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |line| {
        defer scope.engine.freeValue(line);
        if (scope.truthy(try scope.invoke(line, "startsWith", &.{try scope.text("data:")}))) {
            var value = try scope.invoke(line, "slice", &.{c.JS_NewInt32(scope.engine.context, 5)});
            if (scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text(" ")}))) value = try scope.invoke(value, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)});
            _ = try scope.invoke(data, "push", &.{value});
        } else if (scope.truthy(try scope.invoke(line, "startsWith", &.{try scope.text("event:")}))) event = try scope.invoke(try scope.invoke(line, "slice", &.{c.JS_NewInt32(scope.engine.context, 6)}), "trim", &.{});
    }
    if (try v.length(scope, data) == 0) return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("event"));
    try scope.put(result, "data", try scope.invoke(data, "join", &.{try scope.text("\n")}));
    try scope.put(result, "event", event);
    return result;
}
fn advance(scope: *Scope, pending: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    if (scope.truthy(try scope.get(owner, "closed"))) return settle(scope, pending, c.pi_js_undefined(), true);
    if (!scope.truthy(try scope.get(try scope.get(owner, "response"), "ok"))) {
        if (scope.truthy(try scope.get(owner, "errorBodySent"))) return settle(scope, pending, c.pi_js_undefined(), true);
        try scope.put(owner, "errorBodySent", c.pi_js_bool(scope.engine.context, 1));
        return flow.wait(read, scope.engine, pending, try scope.invoke(try scope.get(owner, "response"), "text", &.{}), 1);
    }
    while (true) {
        if (scope.truthy(try scope.get(owner, "bytes"))) {
            if (scope.truthy(try scope.get(owner, "done"))) return settle(scope, pending, c.pi_js_undefined(), true);
            return flow.wait(read, scope.engine, pending, try scope.invoke(try scope.get(owner, "reader"), "read", &.{}), 2);
        }
        const buffer = try scope.get(owner, "buffer");
        const separator = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("(?:\\r\\n|\\r|\\n){2}")}));
        const match = try scope.invoke(separator, "exec", &.{buffer});
        if (!v.nullish(match)) {
            const index = try scope.get(match, "index");
            const block = try scope.invoke(buffer, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), index });
            const end = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .add, index, try scope.get(try v.at(scope, match, 0), "length")));
            try scope.put(owner, "buffer", try scope.invoke(buffer, "slice", &.{end}));
            const event = try frame(scope, block);
            if (!c.JS_IsUndefined(event)) return settle(scope, pending, event, false);
            continue;
        }
        if (scope.truthy(try scope.get(owner, "done"))) {
            try scope.put(owner, "buffer", try scope.text(""));
            const event = try frame(scope, buffer);
            if (!c.JS_IsUndefined(event)) return settle(scope, pending, event, false);
            return settle(scope, pending, c.pi_js_undefined(), true);
        }
        return flow.wait(read, scope.engine, pending, try scope.invoke(try scope.get(owner, "reader"), "read", &.{}), 0);
    }
}
fn read(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, pending, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    readValue(&scope, pending, value, stage) catch |err| try flow.rejectError(engine, pending, err);
}
fn readValue(scope: *Scope, pending: c.JSValue, value: c.JSValue, stage: c_int) !void {
    if (stage == 1) {
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("error_body"));
        try scope.put(event, "body", value);
        return settle(scope, pending, event, false);
    }
    const owner = try scope.get(pending, "agent");
    const done = scope.truthy(try scope.get(value, "done"));
    try scope.put(owner, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    if (stage == 2) {
        if (done) return settle(scope, pending, c.pi_js_undefined(), true);
        const event = try scope.object();
        try scope.put(event, "type", try scope.text("bytes"));
        try scope.put(event, "data", try scope.get(value, "value"));
        return settle(scope, pending, event, false);
    }
    const config = try scope.object();
    try scope.put(config, "stream", c.pi_js_bool(scope.engine.context, @intFromBool(!done)));
    const text = try scope.invoke(try scope.get(owner, "decoder"), "decode", if (done) &.{} else &.{ try scope.get(value, "value"), config });
    try scope.put(owner, "buffer", try scope.concat(try scope.get(owner, "buffer"), text));
    try advance(scope, pending);
}

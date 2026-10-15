//! Actual injectable Mistral request, header-timeout retirement and hook order.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const signals = @import("native_ai_mistral_signal.zig");
const Stage = enum(c_int) { headers, response_hook, error_body };

pub fn open(engine: *v.em.Engine, model: c.JSValue, payload: c.JSValue, api_key: c.JSValue, options: c.JSValue, before_read: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try scope.own(try v.js.builtin(engine, "URL", &.{try scope.get(model, "baseUrl")}));
    const regex = try scope.own(try v.js.builtin(engine, "RegExp", &.{ try scope.text("/+$"), try scope.text("u") }));
    try scope.set(base, "pathname", try scope.concat(try scope.invoke(try scope.get(base, "pathname"), "replace", &.{ regex, try scope.text("") }), try scope.text("/")));
    const target = try scope.own(try v.js.builtin(engine, "URL", &.{ try scope.text("v1/chat/completions"), base }));
    const headers = try @import("native_ai_mistral_headers.zig").create(&scope, model, api_key, options);
    const raw_timeout = try v.optional(&scope, options, "timeoutMs");
    const timeout_ms = if (v.nullish(raw_timeout)) c.JS_NewInt32(engine.context, 60000) else raw_timeout;
    const combined = try signals.create(&scope, try v.optional(&scope, options, "signal"), timeout_ms);
    const owner = try scope.object();
    try scope.put(owner, "model", model);
    try scope.put(owner, "options", options);
    try scope.put(owner, "combined", combined);
    try scope.put(owner, "timeoutMs", timeout_ms);
    // Source evaluates the fetch callee before constructing its init argument.
    const custom = try v.optional(&scope, options, "fetch");
    const fetch = if (v.nullish(custom)) try scope.global("fetch") else custom;
    const init = try scope.object();
    try scope.put(init, "method", try scope.text("POST"));
    try scope.put(init, "headers", headers);
    try scope.put(init, "body", try scope.invoke(try scope.global("JSON"), "stringify", &.{try @import("native_ai_mistral_request.zig").wire(&scope, payload)}));
    try scope.put(init, "signal", try scope.get(combined, "signal"));
    const reader = try scope.own(try @import("native_ai_mistral_fetch.zig").open(engine, fetch, target, init, try v.optional(&scope, options, "signal"), before_read));
    try scope.put(owner, "reader", reader);
    const pending = try flow.create(engine, owner);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const output = try scope.object();
    try scope.put(output, "ready", pending.promise);
    inline for (.{ "events", "cancel", "close" }) |key| try scope.put(output, key, try scope.get(reader, key));
    try wait(&scope, pending.owner, try scope.get(reader, "ready"), .headers);
    return c.JS_DupValue(engine.context, output);
}

fn wait(scope: *Scope, pending: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(continued, scope.engine, pending, value, @intFromEnum(stage));
}
fn continued(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(pending, "agent");
    const options = try scope.get(owner, "options");
    const stage: Stage = @enumFromInt(raw);
    if (stage == .headers) {
        const combined = try scope.get(owner, "combined");
        const reason = if (rejected) try signals.headerError(&scope, combined, try v.optional(&scope, options, "signal"), try scope.get(owner, "timeoutMs"), value) else value;
        try signals.cleanup(&scope, combined);
        if (rejected) return flow.settle(engine, pending, true, reason);
        const callback = try v.optional(&scope, options, "onResponse");
        var result = c.pi_js_undefined();
        if (!v.nullish(callback)) {
            const head = try scope.object();
            try scope.put(head, "status", try scope.get(value, "status"));
            const headers = try scope.object();
            var entries = try v.iterator(&scope, try scope.invoke(try scope.get(value, "headers"), "entries", &.{}));
            defer entries.deinit();
            errdefer entries.closePreserving();
            while (try entries.next()) |entry| {
                defer engine.freeValue(entry);
                try v.js.setKey(engine, headers, try v.at(&scope, entry, 0), try v.at(&scope, entry, 1));
            }
            try scope.put(head, "headers", headers);
            result = try scope.call(callback, options, &.{ head, try scope.get(owner, "model") });
        }
        return wait(&scope, pending, result, .response_hook);
    }
    if (rejected) return flow.settle(engine, pending, true, value);
    const reader = try scope.get(owner, "reader");
    switch (stage) {
        .headers => unreachable,
        .response_hook => {
            if (!scope.truthy(try scope.invoke(reader, "begin", &.{}))) {
                return wait(&scope, pending, try scope.invoke(try scope.get(reader, "events"), "next", &.{}), .error_body);
            }
            try flow.settle(engine, pending, false, c.pi_js_undefined());
        },
        .error_body => {
            const body = try scope.get(value, "value");
            const status = try scope.get(body, "status");
            const status_text = try scope.get(body, "statusText");
            const message = if (scope.truthy(status_text)) status_text else try scope.concat(try scope.text("Request failed with status "), try scope.stringify(status));
            const reason = try scope.own(try v.js.builtin(engine, "Error", &.{message}));
            try scope.set(reason, "name", try scope.text("MistralHttpError"));
            try scope.put(reason, "statusCode", status);
            try scope.put(reason, "body", try scope.get(body, "body"));
            try flow.settle(engine, pending, true, reason);
        },
    }
}

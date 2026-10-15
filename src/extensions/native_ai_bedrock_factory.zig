//! Actual native bedrock-converse-stream facade with awaited owner-thread hooks.
//! This private entrypoint is source-only until genuine Source/transport gates pass.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const request = @import("native_ai_bedrock_request.zig");
const auth = @import("native_ai_bedrock_auth.zig");
const wire = @import("native_ai_bedrock_wire.zig");
const decoder = @import("native_ai_bedrock_decode.zig");
const Stage = enum(c_int) { payload, ready, response, prepared, next, chunk };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    try @import("native_stream.zig").install(engine);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const dependencies = try s.object();
    const thinking = try s.own(try @import("native_ai_thinking.zig").create(engine));
    const estimate = try s.own(try @import("native_ai_estimate.zig").create(engine));
    try s.put(dependencies, "simple", try s.own(try @import("native_ai_simple_options.zig").create(engine, try s.get(thinking, "clampThinkingLevel"), try s.get(estimate, "estimateContextTokens"))));
    try s.put(dependencies, "env", try s.own(try @import("native_ai_env_keys.zig").create(engine, .{})));
    const result = try s.object();
    inline for (.{ "stream", "streamSimple" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(args.len, 3)], 0..) |value, i| values[i] = value;
                return stream(host, roots[0], &values, index == 1);
            }
        };
        try s.put(result, name, try s.own(try @import("native_node_function.zig").createArrow(engine, name, 3, Adapter.call, &.{dependencies})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn simpleOptions(s: *Scope, dependencies: c.JSValue, model: c.JSValue, context: c.JSValue, input: c.JSValue) !c.JSValue {
    const helper = try s.get(dependencies, "simple");
    const base = try s.invoke(helper, "buildBaseOptions", &.{ model, context, input, c.pi_js_undefined() });
    try s.put(base, "toolChoice", try v.optional(s, input, "toolChoice"));
    const reasoning = try v.optional(s, input, "reasoning");
    if (!s.truthy(reasoning)) {
        try s.put(base, "reasoning", c.pi_js_undefined());
        return base;
    }
    try s.put(base, "reasoning", reasoning);
    const budgets = try v.optional(s, input, "thinkingBudgets");
    try s.put(base, "thinkingBudgets", budgets);
    if (try request.isClaude(s, model) and !try request.supportsAdaptive(s, model)) {
        const adjusted = try s.invoke(helper, "adjustMaxTokensForThinking", &.{ try s.get(base, "maxTokens"), try s.get(model, "maxTokens"), reasoning, budgets });
        const max_tokens = try s.invoke(helper, "clampMaxTokensToContext", &.{ model, context, try s.get(adjusted, "maxTokens") });
        try s.put(base, "maxTokens", max_tokens);
        const merged = try v.spread(s, budgets);
        const level = try s.invoke(helper, "clampReasoning", &.{reasoning});
        const remaining = try s.own(try @import("native_image_arithmetic.zig").binary(s.engine, .subtract, max_tokens, c.JS_NewInt32(s.engine.context, 1024)));
        const budget = try s.invoke(try s.global("Math"), "min", &.{ try s.get(adjusted, "thinkingBudget"), try s.invoke(try s.global("Math"), "max", &.{ c.JS_NewInt32(s.engine.context, 0), remaining }) });
        try v.js.setKey(s.engine, merged, level, budget);
        try s.put(base, "thinkingBudgets", merged);
    }
    return base;
}
fn stream(engine: *v.em.Engine, dependencies: c.JSValue, args: []const c.JSValue, simple: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const options = if (simple) try simpleOptions(&s, dependencies, args[0], args[1], args[2]) else if (c.JS_IsUndefined(args[2])) try s.object() else args[2];
    const module = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativeBedrockStreamMissing;
    const constructor = try s.get(module, "AssistantMessageEventStream");
    const outer = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    // Source collapse happens synchronously before the async request body begins.
    const context = try s.own(try @import("native_ai_provider_transcript.zig").resolve(engine, args[1], false));
    const pending = try flow.create(engine, dependencies);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try s.put(owner, "model", args[0]);
    try s.put(owner, "context", context);
    try s.put(owner, "options", options);
    try s.put(owner, "stream", outer);
    try s.put(owner, "http", c.pi_js_undefined());
    try s.put(owner, "requestId", c.pi_js_undefined());
    try s.put(owner, "decoder", try s.own(try decoder.create(engine, args[0], outer)));
    setup(&s, owner) catch |err| try failError(&s, owner, err);
    return c.JS_DupValue(engine.context, outer);
}
fn setup(s: *Scope, owner: c.JSValue) !void {
    const options = try s.get(owner, "options");
    try s.put(owner, "auth", try auth.configure(s, try s.get(owner, "agent"), try s.get(owner, "model"), options));
    const payload = try s.own(try request.build(s.engine, try s.get(owner, "model"), try s.get(owner, "context"), options));
    try s.put(owner, "payload", payload);
    try wait(s, owner, try hook(s, owner, "onPayload", payload), .payload);
}
fn hook(s: *Scope, owner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const options = try s.get(owner, "options");
    const callback = try v.optional(s, options, name);
    return if (v.nullish(callback)) c.pi_js_undefined() else s.call(callback, options, &.{ value, try s.get(owner, "model") });
}
fn wait(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, s.engine, owner, value, @intFromEnum(stage));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return fail(&s, owner, value);
    advance(&s, owner, value, @enumFromInt(stage)) catch |err| try failError(&s, owner, err);
}
fn aborted(s: *Scope, owner: c.JSValue) !bool {
    return s.truthy(try v.optional(s, try v.optional(s, try s.get(owner, "options"), "signal"), "aborted"));
}
fn failError(s: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(s.engine, err);
    defer s.engine.freeValue(reason);
    if (s.engine.captured_exception) |captured| {
        s.engine.captured_exception = null;
        s.engine.freeValue(captured);
    }
    return fail(s, owner, reason);
}
fn fail(s: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const transport = try s.get(owner, "http");
    if (!v.nullish(transport)) _ = try s.invoke(transport, "cancel", &.{});
    decoder.fail(s, try s.get(owner, "decoder"), reason, try aborted(s, owner), try s.get(owner, "requestId")) catch |err| {
        try @import("native_stream.zig").reject(s.engine, try s.get(owner, "stream"), reason);
        return flow.rejectError(s.engine, owner, err);
    };
    return flow.settle(s.engine, owner, false, c.pi_js_undefined());
}
fn next(s: *Scope, owner: c.JSValue) !void {
    return wait(s, owner, try s.invoke(try s.get(owner, "iterator"), "next", &.{}), .next);
}
fn advance(s: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .payload => {
            if (!c.JS_IsUndefined(value)) try s.put(owner, "payload", value);
            try open(s, owner);
        },
        .ready => {
            try s.put(owner, "response", value);
            const response = try s.object();
            try s.put(response, "status", try s.get(value, "status"));
            const headers = try s.get(value, "headers");
            try s.put(response, "headers", headers);
            try s.put(owner, "pendingRequestId", try decoder.diagnostic(s, try s.get(headers, "x-amzn-requestid")));
            try wait(s, owner, try hook(s, owner, "onResponse", response), .response);
        },
        .response => {
            try wait(s, owner, try s.own(try @import("native_ai_bedrock_items.zig").create(s.engine, try s.get(owner, "http"), try s.get(owner, "response"), try s.get(owner, "pendingRequestId"))), .prepared);
        },
        .prepared => {
            // Source assigns responseRequestId only after client.send resolves;
            // first-event deserialization can reject before that assignment.
            try s.put(owner, "requestId", try s.get(owner, "pendingRequestId"));
            try s.put(owner, "iterator", value);
            try next(s, owner);
        },
        .next => {
            if (s.truthy(try s.get(value, "done"))) {
                try decoder.finish(s, try s.get(owner, "decoder"), try aborted(s, owner));
                return flow.settle(s.engine, owner, false, c.pi_js_undefined());
            }
            const item = try s.get(value, "value");
            try s.put(owner, "item", item);
            try wait(s, owner, try hook(s, owner, "onProviderStreamEvent", item), .chunk);
        },
        .chunk => {
            try decoder.item(s, try s.get(owner, "decoder"), try s.get(owner, "item"));
            try next(s, owner);
        },
    }
}
fn replacer(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (args.len < 2) return c.pi_js_undefined();
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if ((try v.eq(&s, args[0], "bytes") or try v.eq(&s, args[0], "redactedContent")) and s.truthy(try s.invoke(try s.global("ArrayBuffer"), "isView", &.{args[1]}))) {
        const bytes = try wire.bytes(&s, args[1]);
        const encoded = try engine.gpa.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
        defer engine.gpa.free(encoded);
        return c.JS_DupValue(engine.context, try s.text(std.base64.standard.Encoder.encode(encoded, bytes)));
    }
    return c.JS_DupValue(engine.context, args[1]);
}
fn open(s: *Scope, owner: c.JSValue) !void {
    const engine = s.engine;
    const options = try s.get(owner, "options");
    const headers = try s.object();
    try s.put(headers, "content-type", try s.text("application/json"));
    const custom = try v.optional(s, options, "headers");
    if (!v.nullish(custom)) {
        const retained = try s.own(try v.js.builtin(engine, "Map", &.{}));
        var rows = try v.iterator(s, try s.invoke(try s.global("Object"), "entries", &.{custom}));
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer engine.freeValue(entry);
            const key = try v.at(s, entry, 0);
            const lower = try s.invoke(key, "toLowerCase", &.{});
            _ = try s.invoke(retained, "delete", &.{lower});
            if (!c.JS_IsNull(try v.at(s, entry, 1))) _ = try s.invoke(retained, "set", &.{ lower, entry });
        }
        var kept = try v.iterator(s, try s.invoke(retained, "entries", &.{}));
        defer kept.deinit();
        errdefer kept.closePreserving();
        while (try kept.next()) |row| {
            defer engine.freeValue(row);
            const lower = try v.at(s, row, 0);
            const entry = try v.at(s, row, 1);
            if (try v.eq(s, lower, "authorization") or try v.eq(s, lower, "host") or s.truthy(try s.invoke(lower, "startsWith", &.{try s.text("x-amz-")}))) continue;
            try v.js.setKey(engine, headers, lower, try v.at(s, entry, 1));
        }
    }
    var fields: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (fields.items) |field| {
            engine.gpa.free(field.name);
            engine.gpa.free(field.value);
        }
        fields.deinit(engine.gpa);
    }
    var rows = try v.iterator(s, try s.invoke(try s.global("Object"), "entries", &.{headers}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer engine.freeValue(entry);
        const value = try v.at(s, entry, 1);
        if (v.nullish(value)) continue;
        const name = try engine.toString(try v.at(s, entry, 0));
        errdefer engine.gpa.free(name);
        const text = try engine.toString(value);
        errdefer engine.gpa.free(text);
        try fields.append(engine.gpa, .{ .name = name, .value = text });
    }
    const command = try s.get(owner, "payload");
    const body = try s.object();
    inline for (.{ "messages", "system", "inferenceConfig", "toolConfig", "additionalModelRequestFields", "guardrailConfig", "additionalModelResponseFieldPaths", "promptVariables", "requestMetadata", "performanceConfig", "serviceTier" }) |key| {
        const value = try s.get(command, key);
        if (!c.JS_IsUndefined(value)) try s.put(body, key, value);
    }
    const replacement = try s.own(try @import("native_node_function.zig").create(engine, "", 2, replacer, &.{}));
    const payload = try engine.toString(try s.invoke(try s.global("JSON"), "stringify", &.{ body, replacement }));
    defer engine.gpa.free(payload);
    const config = try s.get(owner, "auth");
    try s.put(config, "modelId", try s.get(command, "modelId"));
    const prepare_data = try engine.toString(try s.invoke(try s.global("JSON"), "stringify", &.{config}));
    defer {
        @memset(prepare_data, 0);
        engine.gpa.free(prepare_data);
    }
    var milliseconds: i64 = 600000;
    const timeout = try v.optional(s, options, "timeoutMs");
    if (!c.JS_IsUndefined(timeout) and c.JS_ToInt64(engine.context, &milliseconds, timeout) < 0) return v.js.capture(engine);
    const transport = try s.own(try @import("native_ai_http.zig").open(engine, .{ .url = "https://bedrock-runtime.us-east-1.amazonaws.com", .payload = payload, .headers = fields.items, .framing = .bytes, .prepare = auth.prepare, .prepare_data = prepare_data, .timeout_ms = @intCast(@max(0, milliseconds)) }, try v.optional(s, options, "signal")));
    try s.put(owner, "http", transport);
    try s.put(owner, "iterator", try s.get(transport, "events"));
    return wait(s, owner, try s.get(transport, "ready"), .ready);
}

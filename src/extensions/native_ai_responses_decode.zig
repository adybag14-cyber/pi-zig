//! Actual ordered Responses stream decoder. Every retained value is GC visible.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const arithmetic = @import("native_image_arithmetic.zig");
const Method = enum { start, push, finish, fail };
fn binary(scope: *Scope, op: arithmetic.Operation, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, op, a, b));
}
fn zero(scope: *Scope, value: c.JSValue) c.JSValue {
    return if (scope.truthy(value)) value else c.JS_NewInt32(scope.engine.context, 0);
}
fn push(scope: *Scope, list: c.JSValue, value: c.JSValue) !void {
    _ = try scope.invoke(list, "push", &.{value});
}
fn stringify(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("JSON"), "stringify", &.{value});
}
fn emit(scope: *Scope, owner: c.JSValue, kind: []const u8, block: ?c.JSValue, key: ?[*:0]const u8, value: c.JSValue) !void {
    const event = try scope.object();
    try scope.put(event, "type", try scope.text(kind));
    const output = try scope.get(owner, "output");
    if (block) |b| try scope.put(event, "contentIndex", try scope.invoke(try scope.get(owner, "indices"), "get", &.{b}));
    if (key) |k| try scope.put(event, k, value);
    try scope.put(event, if (@import("std").mem.eql(u8, kind, "done")) "message" else if (@import("std").mem.eql(u8, kind, "error")) "error" else "partial", output);
    _ = try scope.invoke(try scope.get(owner, "stream"), "push", &.{event});
}
pub fn create(engine: *v.em.Engine, model: c.JSValue, stream: c.JSValue, json: c.JSValue, grammar: c.JSValue, options: c.JSValue, effort: c.JSValue, codex: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    inline for (.{ "model", "stream", "json", "grammar", "options" }, .{ model, stream, json, grammar, options }) |key, value| try scope.put(owner, key, value);
    inline for (.{ "slots", "reasoning", "indices" }) |key| try scope.put(owner, key, try scope.own(try v.js.builtin(engine, "Map", &.{})));
    inline for (.{ "terminal", "finished" }) |key| try scope.put(owner, key, c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "codex", c.pi_js_bool(engine.context, @intFromBool(codex)));
    const output = try scope.object();
    try scope.put(output, "role", try scope.text("assistant"));
    try scope.put(output, "content", try scope.array());
    inline for (.{ "api", "provider" }) |key| try scope.put(output, key, try scope.get(model, key));
    try scope.put(output, "model", try scope.get(model, "id"));
    if (!c.JS_IsUndefined(effort)) try scope.put(output, "providerThinkingLevel", effort);
    const usage = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |key| try scope.put(usage, key, c.JS_NewInt32(engine.context, 0));
    const cost = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try scope.put(cost, key, c.JS_NewInt32(engine.context, 0));
    try scope.put(usage, "cost", cost);
    try scope.put(output, "usage", usage);
    try scope.put(output, "stopReason", try scope.text("pending"));
    try scope.put(output, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.put(owner, "output", output);
    const result = try scope.object();
    try scope.put(result, "output", output);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                if (row.truthy(try row.get(roots[0], "finished"))) return error.ResponsesDecoderAlreadyFinished;
                const first = if (args.len > 0) args[0] else c.pi_js_undefined();
                switch (@as(Method, @enumFromInt(field.value))) {
                    .start => try emit(&row, roots[0], "start", null, null, c.pi_js_undefined()),
                    .push => try chunk(&row, roots[0], first),
                    .finish => try finish(&row, roots[0], row.truthy(first)),
                    .fail => try failure(&row, roots[0], first, args.len > 1 and row.truthy(args[1])),
                }
                return c.pi_js_undefined();
            }
        };
        try scope.put(result, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, if (field.value == 0) 0 else 1, Adapter.call, &.{owner})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn failure(scope: *Scope, owner: c.JSValue, reason: c.JSValue, aborted: bool) !void {
    const output = try scope.get(owner, "output");
    var blocks = try v.iterator(scope, try scope.get(output, "content"));
    defer blocks.deinit();
    errdefer blocks.closePreserving();
    while (try blocks.next()) |block| {
        defer scope.engine.freeValue(block);
        inline for (.{ "index", "partialJson", "customInput" }) |key| try v.remove(scope, block, key);
    }
    const stop = try scope.text(if (aborted) "aborted" else "error");
    try scope.put(output, "stopReason", stop);
    const model = try scope.get(owner, "model");
    const error_mod = @import("native_ai_provider_error.zig");
    const prefix = if (scope.truthy(try scope.get(owner, "codex"))) c.pi_js_undefined() else if (try v.eq(scope, try scope.get(model, "api"), "azure-openai-responses")) try scope.text("Azure OpenAI API error") else try scope.concat(if (try v.eq(scope, try scope.get(model, "provider"), "openai")) try scope.text("OpenAI") else try scope.get(model, "provider"), try scope.text(" API error"));
    var message = try error_mod.format(scope, try error_mod.normalize(scope, reason), prefix);
    if (scope.truthy(try scope.invoke(message, "includes", &.{try scope.text("subscription_sharing_usage_limit_exceeded")}))) message = try scope.concat(message, try scope.text("\nCheck your ChatGPT usage: https://chatgpt.com/settings/usage"));
    try scope.put(output, "errorMessage", message);
    try emit(scope, owner, "error", null, "reason", stop);
    _ = try scope.invoke(try scope.get(owner, "stream"), "end", &.{});
    try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
}
fn phase(scope: *Scope, owner: c.JSValue, item: c.JSValue) !void {
    if (try v.eq(scope, try scope.get(item, "type"), "message") and try v.eq(scope, try scope.get(item, "phase"), "final_answer")) try scope.put(try scope.get(owner, "output"), "stopReason", try scope.text("stop"));
}
fn createSlot(scope: *Scope, owner: c.JSValue, index: c.JSValue, item: c.JSValue) !c.JSValue {
    const typ = try scope.get(item, "type");
    const thinking = try v.eq(scope, typ, "reasoning");
    const text = try v.eq(scope, typ, "message");
    const function = try v.eq(scope, typ, "function_call");
    const custom = try v.eq(scope, typ, "custom_tool_call");
    if (!thinking and !text and !function and !custom) return c.pi_js_undefined();
    const block = try scope.object();
    try scope.put(block, "type", try scope.text(if (thinking) "thinking" else if (text) "text" else "toolCall"));
    if (thinking or text) {
        try scope.put(block, if (thinking) "thinking" else "text", try scope.text(""));
        if (text) try phase(scope, owner, item);
    } else {
        try scope.put(block, "id", try scope.concat(try scope.concat(try scope.stringify(try scope.get(item, "call_id")), try scope.text("|")), try scope.stringify(try scope.get(item, "id"))));
        try scope.put(block, "name", try scope.get(item, "name"));
        const namespace = try scope.get(item, "namespace");
        const args = try scope.object();
        try scope.put(block, "arguments", args);
        if (!c.JS_IsUndefined(namespace)) try scope.put(block, "namespace", namespace);
        if (function) {
            const raw = try scope.get(item, "arguments");
            try scope.put(block, "partialJson", if (scope.truthy(raw)) raw else try scope.text(""));
        } else {
            const configured = try scope.invoke(try scope.get(owner, "grammar"), "get", &.{try scope.get(item, "name")});
            const property = if (v.nullish(configured)) try scope.text("input") else configured;
            const input = try scope.get(item, "input");
            try v.js.setKey(scope.engine, args, property, if (scope.truthy(input)) input else try scope.text(""));
            const scratch = try scope.object();
            try scope.put(scratch, "property", property);
            const buffer = try scope.object();
            try scope.put(buffer, "input", try scope.text(""));
            inline for (.{ "started", "closed" }) |key| try scope.put(buffer, key, c.pi_js_bool(scope.engine.context, 0));
            try scope.put(scratch, "jsonBuffer", buffer);
            try scope.put(block, "customInput", scratch);
        }
    }
    const content = try scope.get(try scope.get(owner, "output"), "content");
    _ = try scope.invoke(try scope.get(owner, "indices"), "set", &.{ block, try scope.get(content, "length") });
    try push(scope, content, block);
    _ = try scope.invoke(try scope.get(owner, "slots"), "set", &.{ index, block });
    try emit(scope, owner, if (thinking) "thinking_start" else if (text) "text_start" else "toolcall_start", block, null, c.pi_js_undefined());
    return block;
}
fn customInput(scope: *Scope, owner: c.JSValue, block: c.JSValue, next: c.JSValue, close: bool) !void {
    const scratch = try scope.get(block, "customInput");
    if (v.nullish(scratch)) return;
    const buffer = try scope.get(scratch, "jsonBuffer");
    const property = try scope.get(scratch, "property");
    const previous = try scope.get(buffer, "input");
    if (scope.truthy(try scope.get(buffer, "closed"))) {
        if (close and scope.equal(next, previous)) return;
        return v.errorText(scope, try scope.concat(try scope.concat(try scope.text("grammar tool input for property \""), property), try scope.text("\" changed after it was closed")));
    }
    if (!scope.truthy(try scope.invoke(next, "startsWith", &.{previous}))) return v.errorText(scope, try scope.concat(try scope.concat(try scope.text("grammar tool input for property \""), property), try scope.text("\" changed non-monotonically")));
    const suffix = try scope.invoke(next, "slice", &.{try scope.get(previous, "length")});
    if (!close and try v.length(scope, suffix) == 0) return;
    var delta = try scope.text("");
    if (!scope.truthy(try scope.get(buffer, "started"))) {
        delta = try scope.concat(try scope.concat(try scope.text("{"), try stringify(scope, property)), try scope.text(":\""));
        try scope.put(buffer, "started", c.pi_js_bool(scope.engine.context, 1));
    }
    const quoted = try stringify(scope, suffix);
    delta = try scope.concat(delta, try scope.invoke(quoted, "slice", &.{ c.JS_NewInt32(scope.engine.context, 1), c.JS_NewInt32(scope.engine.context, -1) }));
    if (close) {
        delta = try scope.concat(delta, try scope.text("\"}"));
        try scope.put(buffer, "closed", c.pi_js_bool(scope.engine.context, 1));
    }
    try scope.put(buffer, "input", next);
    const next_args = try scope.object();
    try v.js.setKey(scope.engine, next_args, property, next);
    try scope.put(block, "arguments", next_args);
    if (try v.length(scope, delta) > 0) try emit(scope, owner, "toolcall_delta", block, "delta", delta);
}
fn joinText(scope: *Scope, items: c.JSValue, separator: []const u8, message: bool) !c.JSValue {
    if (v.nullish(items)) return scope.text("");
    const result = try scope.array();
    var rows = try v.iterator(scope, items);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |item| {
        defer scope.engine.freeValue(item);
        try push(scope, result, try scope.get(item, if (message and !try v.eq(scope, try scope.get(item, "type"), "output_text")) "refusal" else "text"));
    }
    return scope.invoke(result, "join", &.{try scope.text(separator)});
}
fn finalizeItem(scope: *Scope, owner: c.JSValue, index: c.JSValue, item: c.JSValue) !void {
    try phase(scope, owner, item);
    const slots = try scope.get(owner, "slots");
    var block = try scope.invoke(slots, "get", &.{index});
    if (v.nullish(block)) block = try createSlot(scope, owner, index, item);
    if (v.nullish(block)) return;
    const typ = try scope.get(item, "type");
    if (try v.eq(scope, typ, "reasoning") and try v.eq(scope, try scope.get(block, "type"), "thinking")) {
        const summary = try joinText(scope, try scope.get(item, "summary"), "\n\n", false);
        const content = try joinText(scope, try scope.get(item, "content"), "\n\n", false);
        if (scope.truthy(summary) or scope.truthy(content)) try scope.put(block, "thinking", if (scope.truthy(summary)) summary else content);
        try scope.put(block, "thinkingSignature", try stringify(scope, item));
        _ = try scope.invoke(try scope.get(owner, "reasoning"), "set", &.{ try scope.get(item, "id"), block });
        try emit(scope, owner, "thinking_end", block, "content", try scope.get(block, "thinking"));
    } else if (try v.eq(scope, typ, "message") and try v.eq(scope, try scope.get(block, "type"), "text")) {
        try scope.put(block, "text", try joinText(scope, try scope.get(item, "content"), "", true));
        const signature = try scope.object();
        try scope.put(signature, "v", c.JS_NewInt32(scope.engine.context, 1));
        try scope.put(signature, "id", try scope.get(item, "id"));
        const item_phase = try scope.get(item, "phase");
        if (scope.truthy(item_phase)) try scope.put(signature, "phase", item_phase);
        try scope.put(block, "textSignature", try stringify(scope, signature));
        try emit(scope, owner, "text_end", block, "content", try scope.get(block, "text"));
    } else if (try v.eq(scope, typ, "function_call") and !c.JS_IsUndefined(try scope.get(block, "partialJson"))) {
        const raw = try scope.get(item, "arguments");
        try v.js.spreadInto(scope.engine, block, try scope.invoke(try scope.get(owner, "json"), "parseToolCallArguments", &.{if (scope.truthy(raw)) raw else try scope.get(block, "partialJson")}));
        const namespace = try scope.get(item, "namespace");
        if (!c.JS_IsUndefined(namespace)) try scope.put(block, "namespace", namespace);
        try v.remove(scope, block, "partialJson");
        try emit(scope, owner, "toolcall_end", block, "toolCall", block);
    } else if (try v.eq(scope, typ, "custom_tool_call") and scope.truthy(try scope.get(block, "customInput"))) {
        const input = try scope.get(item, "input");
        const property = try scope.get(try scope.get(block, "customInput"), "property");
        try customInput(scope, owner, block, if (v.nullish(input)) try scope.own(try v.js.getKey(scope.engine, try scope.get(block, "arguments"), property)) else input, true);
        const namespace = try scope.get(item, "namespace");
        if (!c.JS_IsUndefined(namespace)) try scope.put(block, "namespace", namespace);
        try v.remove(scope, block, "customInput");
        try emit(scope, owner, "toolcall_end", block, "toolCall", block);
    } else return;
    _ = try scope.invoke(slots, "delete", &.{index});
}
fn terminal(scope: *Scope, owner: c.JSValue, response: c.JSValue) !void {
    try scope.put(owner, "terminal", c.pi_js_bool(scope.engine.context, 1));
    const output = try scope.get(owner, "output");
    const items = try v.optional(scope, response, "output");
    if (!v.nullish(items)) {
        var rows = try v.iterator(scope, items);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |item| {
            defer scope.engine.freeValue(item);
            if (!try v.eq(scope, try scope.get(item, "type"), "reasoning") or !scope.truthy(try scope.get(item, "encrypted_content"))) continue;
            const block = try scope.invoke(try scope.get(owner, "reasoning"), "get", &.{try scope.get(item, "id")});
            if (v.nullish(block) or !scope.truthy(try scope.get(block, "thinkingSignature"))) continue;
            const stored = try scope.invoke(try scope.global("JSON"), "parse", &.{try scope.get(block, "thinkingSignature")});
            if (scope.truthy(try scope.get(stored, "encrypted_content"))) continue;
            const filled = try v.spread(scope, stored);
            try scope.put(filled, "encrypted_content", try scope.get(item, "encrypted_content"));
            try scope.put(block, "thinkingSignature", try stringify(scope, filled));
        }
    }
    const id = try v.optional(scope, response, "id");
    if (scope.truthy(id)) try scope.put(output, "responseId", id);
    const raw = try v.optional(scope, response, "usage");
    if (scope.truthy(raw)) {
        const usage = try scope.object();
        const details = try scope.get(raw, "input_tokens_details");
        const read = zero(scope, try v.optional(scope, details, "cached_tokens"));
        const write = zero(scope, try v.optional(scope, details, "cache_write_tokens"));
        try scope.put(usage, "input", try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), try binary(scope, .subtract, try binary(scope, .subtract, zero(scope, try scope.get(raw, "input_tokens")), read), write) }));
        try scope.put(usage, "output", zero(scope, try scope.get(raw, "output_tokens")));
        try scope.put(usage, "cacheRead", read);
        try scope.put(usage, "cacheWrite", write);
        try scope.put(usage, "reasoning", zero(scope, try v.optional(scope, try scope.get(raw, "output_tokens_details"), "reasoning_tokens")));
        try scope.put(usage, "totalTokens", zero(scope, try scope.get(raw, "total_tokens")));
        const cost = try scope.object();
        inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try scope.put(cost, key, c.JS_NewInt32(scope.engine.context, 0));
        try scope.put(usage, "cost", cost);
        try scope.put(output, "usage", usage);
    }
    const usage = try scope.get(output, "usage");
    _ = try scope.own(try @import("native_ai_cost.zig").calculate(scope.engine, try scope.get(owner, "model"), usage));
    var tier = try v.optional(scope, response, "service_tier");
    const requested = try v.optional(scope, try scope.get(owner, "options"), "serviceTier");
    if (v.nullish(tier) or (scope.truthy(try scope.get(owner, "codex")) and try v.eq(scope, tier, "default") and !v.nullish(requested))) tier = requested;
    const azure = try v.eq(scope, try scope.get(try scope.get(owner, "model"), "api"), "azure-openai-responses");
    const multiplier: f64 = if (azure) 1 else if (try v.eq(scope, tier, "flex")) 0.5 else if (try v.eq(scope, tier, "priority") or (!scope.truthy(try scope.get(owner, "codex")) and try v.eq(scope, tier, "fast"))) (if (try v.eq(scope, try scope.get(try scope.get(owner, "model"), "id"), "gpt-5.5")) 2.5 else 2) else 1;
    if (multiplier != 1) {
        const cost = try scope.get(usage, "cost");
        var total = c.JS_NewInt32(scope.engine.context, 0);
        inline for (.{ "input", "output", "cacheRead", "cacheWrite" }) |key| {
            const amount = try binary(scope, .multiply, try scope.get(cost, key), c.JS_NewFloat64(scope.engine.context, multiplier));
            try scope.put(cost, key, amount);
            total = try binary(scope, .add, total, amount);
        }
        try scope.put(cost, "total", total);
    }
    const status = try v.optional(scope, response, "status");
    const incomplete = try v.optional(scope, try v.optional(scope, response, "incomplete_details"), "reason");
    const has_incomplete = c.JS_IsString(incomplete) and scope.truthy(incomplete);
    try scope.put(output, "rawStopReason", if (has_incomplete) try scope.concat(try scope.concat(status, try scope.text(".")), incomplete) else status);
    var reason: []const u8 = "stop";
    var error_message = c.pi_js_undefined();
    if (try v.eq(scope, status, "incomplete")) {
        if (try v.eq(scope, incomplete, "max_output_tokens")) reason = "length" else {
            reason = "error";
            error_message = if (has_incomplete) try scope.concat(try scope.text("Response incomplete: "), incomplete) else try scope.text("Response incomplete without a provider reason");
        }
    } else if (try v.eq(scope, status, "failed") or try v.eq(scope, status, "cancelled")) reason = "error" else if (scope.truthy(status) and !try v.eq(scope, status, "completed") and !try v.eq(scope, status, "queued") and !try v.eq(scope, status, "in_progress")) return v.errorText(scope, try scope.concat(try scope.text("Unhandled stop reason: "), status));
    if (c.JS_IsUndefined(error_message)) try v.remove(scope, output, "errorMessage") else try scope.put(output, "errorMessage", error_message);
    if (@import("std").mem.eql(u8, reason, "stop")) {
        var blocks = try v.iterator(scope, try scope.get(output, "content"));
        defer blocks.deinit();
        errdefer blocks.closePreserving();
        while (try blocks.next()) |block| {
            defer scope.engine.freeValue(block);
            if (try v.eq(scope, try scope.get(block, "type"), "toolCall")) {
                reason = "toolUse";
                break;
            }
        }
    }
    try scope.put(output, "stopReason", try scope.text(reason));
}
fn chunk(scope: *Scope, owner: c.JSValue, event: c.JSValue) !void {
    const typ = try scope.get(event, "type");
    const output = try scope.get(owner, "output");
    if (try v.eq(scope, typ, "response.created")) {
        try scope.put(output, "responseId", try scope.get(try scope.get(event, "response"), "id"));
        return;
    }
    const index = try scope.get(event, "output_index");
    if (try v.eq(scope, typ, "response.output_item.added")) {
        _ = try createSlot(scope, owner, index, try scope.get(event, "item"));
        return;
    }
    if (try v.eq(scope, typ, "response.output_item.done")) return finalizeItem(scope, owner, index, try scope.get(event, "item"));
    if (try v.eq(scope, typ, "response.completed") or try v.eq(scope, typ, "response.incomplete")) return terminal(scope, owner, try scope.get(event, "response"));
    if (try v.eq(scope, typ, "error")) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Error Code "), try scope.stringify(try scope.get(event, "code"))), try scope.text(": ")), try scope.stringify(try scope.get(event, "message"))));
    if (try v.eq(scope, typ, "response.failed")) {
        try scope.put(owner, "terminal", c.pi_js_bool(scope.engine.context, 1));
        const response = try scope.get(event, "response");
        try scope.put(output, "rawStopReason", try v.optional(scope, response, "status"));
        const err = try v.optional(scope, response, "error");
        const detail = try v.optional(scope, try v.optional(scope, response, "incomplete_details"), "reason");
        var message = try scope.text("Unknown error (no error details in response)");
        if (scope.truthy(err)) {
            const code = try scope.get(err, "code");
            const msg = try scope.get(err, "message");
            message = try scope.concat(try scope.concat(if (scope.truthy(code)) code else try scope.text("unknown"), try scope.text(": ")), if (scope.truthy(msg)) msg else try scope.text("no message"));
        } else if (scope.truthy(detail)) message = try scope.concat(try scope.text("incomplete: "), detail);
        return v.errorText(scope, message);
    }
    const block = try scope.invoke(try scope.get(owner, "slots"), "get", &.{index});
    if (v.nullish(block)) return;
    const kind = try scope.get(block, "type");
    if (try v.eq(scope, kind, "thinking") and (try v.eq(scope, typ, "response.reasoning_summary_text.delta") or try v.eq(scope, typ, "response.reasoning_text.delta") or try v.eq(scope, typ, "response.reasoning_summary_part.done"))) {
        const delta = if (try v.eq(scope, typ, "response.reasoning_summary_part.done")) try scope.text("\n\n") else try scope.get(event, "delta");
        try scope.put(block, "thinking", try scope.concat(try scope.get(block, "thinking"), delta));
        try emit(scope, owner, "thinking_delta", block, "delta", delta);
    } else if (try v.eq(scope, kind, "text") and (try v.eq(scope, typ, "response.output_text.delta") or try v.eq(scope, typ, "response.refusal.delta"))) {
        const delta = try scope.get(event, "delta");
        try scope.put(block, "text", try scope.concat(try scope.get(block, "text"), delta));
        try emit(scope, owner, "text_delta", block, "delta", delta);
    } else if (try v.eq(scope, kind, "toolCall") and !c.JS_IsUndefined(try scope.get(block, "partialJson"))) {
        const old = try scope.get(block, "partialJson");
        if (try v.eq(scope, typ, "response.function_call_arguments.delta")) {
            const delta = try scope.get(event, "delta");
            const next = try scope.concat(old, delta);
            try scope.put(block, "partialJson", next);
            try scope.put(block, "arguments", try scope.invoke(try scope.get(owner, "json"), "parseStreamingJson", &.{next}));
            try emit(scope, owner, "toolcall_delta", block, "delta", delta);
        } else if (try v.eq(scope, typ, "response.function_call_arguments.done")) {
            const next = try scope.get(event, "arguments");
            try scope.put(block, "partialJson", next);
            try scope.put(block, "arguments", try scope.invoke(try scope.get(owner, "json"), "parseStreamingJson", &.{next}));
            if (scope.truthy(try scope.invoke(next, "startsWith", &.{old}))) {
                const delta = try scope.invoke(next, "slice", &.{try scope.get(old, "length")});
                if (try v.length(scope, delta) > 0) try emit(scope, owner, "toolcall_delta", block, "delta", delta);
            }
        }
    } else if (try v.eq(scope, kind, "toolCall") and scope.truthy(try scope.get(block, "customInput"))) {
        if (try v.eq(scope, typ, "response.custom_tool_call_input.delta")) {
            const property = try scope.get(try scope.get(block, "customInput"), "property");
            const old = try scope.own(try v.js.getKey(scope.engine, try scope.get(block, "arguments"), property));
            try customInput(scope, owner, block, try scope.concat(old, try scope.get(event, "delta")), false);
        } else if (try v.eq(scope, typ, "response.custom_tool_call_input.done")) try customInput(scope, owner, block, try scope.get(event, "input"), true);
    }
}
fn finish(scope: *Scope, owner: c.JSValue, aborted: bool) !void {
    if (aborted) return v.errorText(scope, try scope.text("Request was aborted"));
    if (!scope.truthy(try scope.get(owner, "terminal"))) return v.errorText(scope, try scope.text("OpenAI Responses stream ended before a terminal response event"));
    const output = try scope.get(owner, "output");
    const stop = try scope.get(output, "stopReason");
    if (try v.eq(scope, stop, "toolUse")) {
        var blocks = try v.iterator(scope, try scope.get(output, "content"));
        defer blocks.deinit();
        errdefer blocks.closePreserving();
        while (try blocks.next()) |block| {
            defer scope.engine.freeValue(block);
            if (!try v.eq(scope, try scope.get(block, "type"), "toolCall")) continue;
            if (!c.JS_IsUndefined(try scope.get(block, "partialJson")) or !c.JS_IsUndefined(try scope.get(block, "customInput"))) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("OpenAI Responses stream completed with an unfinished tool call: "), try scope.get(block, "name")), try scope.text(" (")), try scope.get(block, "id")), try scope.text(")")));
        }
    }
    if (try v.eq(scope, stop, "pending")) return v.errorText(scope, try scope.text("OpenAI Responses stream ended without a stop reason"));
    if (try v.eq(scope, stop, "error") or try v.eq(scope, stop, "aborted")) {
        const message = try scope.get(output, "errorMessage");
        return v.errorText(scope, if (scope.truthy(message)) message else try scope.text("An unknown error occurred"));
    }
    try emit(scope, owner, "done", null, "reason", stop);
    _ = try scope.invoke(try scope.get(owner, "stream"), "end", &.{});
    try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
}

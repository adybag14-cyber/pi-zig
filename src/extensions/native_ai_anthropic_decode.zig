//! Source5ab Anthropic event decoder. All stream values stay on the VM owner.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn create(engine: *v.em.Engine, model: c.JSValue, stream: c.JSValue, json: c.JSValue, oauth: bool, tools: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "model", model);
    try scope.put(owner, "usageModel", model);
    try scope.put(owner, "stream", stream);
    try scope.put(owner, "json", json);
    try scope.put(owner, "oauth", c.pi_js_bool(engine.context, @intFromBool(oauth)));
    try scope.put(owner, "tools", tools);
    const output = try scope.object();
    try scope.put(output, "role", try scope.text("assistant"));
    try scope.put(output, "content", try scope.array());
    try scope.put(output, "api", try scope.get(model, "api"));
    try scope.put(output, "provider", try scope.get(model, "provider"));
    try scope.put(output, "model", try scope.get(model, "id"));
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
    inline for (.{ "event", "start", "finish", "fail", "thinkingLevel", "strictFallback", "oauthMode" }) |name| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                const owner_value = roots[0];
                const input = if (args.len > 0) args[0] else c.pi_js_undefined();
                if (comptime @import("std").mem.eql(u8, name, "event")) try event(&row, owner_value, input) else if (comptime @import("std").mem.eql(u8, name, "start")) {
                    try push(&row, owner_value, "start", null, null, c.pi_js_undefined());
                } else if (comptime @import("std").mem.eql(u8, name, "thinkingLevel")) {
                    if (row.truthy(input)) try row.set(try row.get(owner_value, "output"), "providerThinkingLevel", input);
                } else if (comptime @import("std").mem.eql(u8, name, "oauthMode")) {
                    try row.set(owner_value, "oauth", input);
                } else if (comptime @import("std").mem.eql(u8, name, "strictFallback")) {
                    try strictFallback(&row, owner_value, input);
                } else if (comptime @import("std").mem.eql(u8, name, "finish")) {
                    const generation = host.native_allocation_generation;
                    finish(&row, owner_value, row.truthy(input)) catch |err| {
                        const classified = host.nativeAllocationError(err, generation);
                        if (classified == error.OutOfMemory) return classified;
                        const reason = @import("native_agent_async.zig").reason(host, err);
                        defer host.freeValue(reason);
                        try fail(&row, owner_value, reason, row.truthy(input));
                    };
                } else try fail(&row, owner_value, input, args.len > 1 and row.truthy(args[1]));
                return c.pi_js_undefined();
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (@import("std").mem.eql(u8, name, "fail")) 2 else if (@import("std").mem.eql(u8, name, "start")) 0 else 1, Adapter.call, &.{owner})));
    }
    try scope.put(result, "output", output);
    return c.JS_DupValue(engine.context, result);
}
fn push(scope: *Scope, owner: c.JSValue, kind: []const u8, index: ?u32, key: ?[*:0]const u8, value: c.JSValue) !void {
    const output = try scope.get(owner, "output");
    const item = try scope.object();
    try scope.put(item, "type", try scope.text(kind));
    if (index) |position| try scope.put(item, "contentIndex", c.JS_NewUint32(scope.engine.context, position));
    if (key) |name| try scope.put(item, name, value);
    try scope.put(item, "partial", output);
    _ = try scope.invoke(try scope.get(owner, "stream"), "push", &.{item});
}
fn find(scope: *Scope, blocks: c.JSValue, index: c.JSValue) !?u32 {
    var position: u32 = 0;
    while (position < try v.length(scope, blocks)) : (position += 1) {
        if (scope.equal(try scope.get(try v.at(scope, blocks, position), "index"), index)) return position;
    }
    return null;
}
fn total(scope: *Scope, owner: c.JSValue) !void {
    const usage = try scope.get(try scope.get(owner, "output"), "usage");
    var count = try scope.get(usage, "input");
    inline for (.{ "output", "cacheRead", "cacheWrite" }) |key| count = try scope.concat(count, try scope.get(usage, key));
    try scope.set(usage, "totalTokens", count);
    _ = try scope.own(try @import("native_ai_cost.zig").calculate(scope.engine, try scope.get(owner, "usageModel"), usage));
}
fn updateUsage(scope: *Scope, owner: c.JSValue, input: c.JSValue, initial: bool) !void {
    const output = try scope.get(try scope.get(owner, "output"), "usage");
    inline for (.{ .{ "input_tokens", "input" }, .{ "output_tokens", "output" }, .{ "cache_read_input_tokens", "cacheRead" }, .{ "cache_creation_input_tokens", "cacheWrite" } }) |pair| {
        const value = try scope.get(input, pair[0]);
        if (initial or !v.nullish(value)) try scope.set(output, pair[1], if (initial and !scope.truthy(value)) c.JS_NewInt32(scope.engine.context, 0) else value);
    }
    const hour = try v.optional(scope, try scope.get(input, "cache_creation"), "ephemeral_1h_input_tokens");
    if (initial or !v.nullish(hour)) try scope.set(output, "cacheWrite1h", if (initial and !scope.truthy(hour)) c.JS_NewInt32(scope.engine.context, 0) else hour);
    const reasoning = try v.optional(scope, try scope.get(input, "output_tokens_details"), "thinking_tokens");
    if (!initial and !v.nullish(reasoning)) try scope.set(output, "reasoning", reasoning);
    try total(scope, owner);
}
fn stop(scope: *Scope, output: c.JSValue, reason: c.JSValue, details: c.JSValue) !void {
    try scope.set(output, "rawStopReason", reason);
    var mapped: []const u8 = "error";
    if (try v.eq(scope, reason, "end_turn") or try v.eq(scope, reason, "pause_turn") or try v.eq(scope, reason, "stop_sequence")) mapped = "stop" else if (try v.eq(scope, reason, "max_tokens")) mapped = "length" else if (try v.eq(scope, reason, "tool_use")) mapped = "toolUse";
    try scope.set(output, "stopReason", try scope.text(mapped));
    if (try v.eq(scope, reason, "refusal")) {
        const explanation = try v.optional(scope, details, "explanation");
        try scope.set(output, "errorMessage", if (scope.truthy(explanation)) explanation else try scope.text("The model refused to complete the request"));
    } else if (try v.eq(scope, reason, "sensitive")) try scope.set(output, "errorMessage", try scope.text("Provider stopped with: sensitive")) else if (@import("std").mem.eql(u8, mapped, "error")) return v.errorText(scope, try scope.concat(try scope.text("Unhandled stop reason: "), try scope.stringify(reason)));
}
pub fn event(scope: *Scope, owner: c.JSValue, input: c.JSValue) !void {
    const output = try scope.get(owner, "output");
    const blocks = try scope.get(output, "content");
    const kind = try scope.get(input, "type");
    if (try v.eq(scope, kind, "message_start")) {
        const message = try scope.get(input, "message");
        try scope.set(output, "responseId", try scope.get(message, "id"));
        const transformations = try scope.get(message, "input_transformations");
        if (try v.array(scope, transformations)) try scope.set(owner, "transformations", transformations);
        const response_model = try scope.get(message, "model");
        const model = try scope.get(owner, "model");
        if (!scope.equal(response_model, try scope.get(model, "id"))) {
            try scope.set(output, "responseModel", response_model);
            const fallbacks = try v.optional(scope, try scope.get(model, "compat"), "allowedFallbackModels");
            if (!v.nullish(fallbacks)) {
                var rows = try v.iterator(scope, fallbacks);
                defer rows.deinit();
                errdefer rows.closePreserving();
                while (try rows.next()) |fallback| {
                    defer scope.engine.freeValue(fallback);
                    if (scope.equal(try scope.get(fallback, "provider"), try scope.get(model, "provider")) and scope.equal(try scope.get(fallback, "model"), response_model)) {
                        const cost = try scope.get(fallback, "cost");
                        if (scope.truthy(cost)) {
                            const usage_model = try v.spread(scope, model);
                            try scope.put(usage_model, "id", response_model);
                            try scope.put(usage_model, "cost", cost);
                            try scope.set(owner, "usageModel", usage_model);
                        }
                        break;
                    }
                }
            }
        }
        try updateUsage(scope, owner, try scope.get(message, "usage"), true);
    } else if (try v.eq(scope, kind, "content_block_start")) {
        const input_block = try scope.get(input, "content_block");
        const block_kind = try scope.get(input_block, "type");
        if (try v.eq(scope, block_kind, "fallback")) {
            if (try v.length(scope, blocks) > 0) return v.errorText(scope, try scope.text("Anthropic performed an unsupported mid-output model fallback"));
            return;
        }
        const block = try scope.object();
        var start: []const u8 = undefined;
        if (try v.eq(scope, block_kind, "text")) {
            try scope.put(block, "type", try scope.text("text"));
            const value = try scope.get(input_block, "text");
            try scope.put(block, "text", if (v.nullish(value)) try scope.text("") else value);
            start = "text_start";
        } else if (try v.eq(scope, block_kind, "thinking") or try v.eq(scope, block_kind, "redacted_thinking")) {
            const redacted = try v.eq(scope, block_kind, "redacted_thinking");
            try scope.put(block, "type", try scope.text("thinking"));
            const value = try scope.get(input_block, "thinking");
            try scope.put(block, "thinking", if (redacted) try scope.text("[Reasoning redacted]") else if (v.nullish(value)) try scope.text("") else value);
            const signature = try scope.get(input_block, if (redacted) "data" else "signature");
            try scope.put(block, "thinkingSignature", if (!redacted and v.nullish(signature)) try scope.text("") else signature);
            if (redacted) try scope.put(block, "redacted", c.pi_js_bool(scope.engine.context, 1));
            start = "thinking_start";
        } else if (try v.eq(scope, block_kind, "tool_use")) {
            try scope.put(block, "type", try scope.text("toolCall"));
            try scope.put(block, "id", try scope.get(input_block, "id"));
            var name = try scope.get(input_block, "name");
            if (scope.truthy(try scope.get(owner, "oauth"))) {
                const lowered = try scope.invoke(name, "toLowerCase", &.{});
                var tools = try v.iterator(scope, try scope.get(owner, "tools"));
                defer tools.deinit();
                errdefer tools.closePreserving();
                while (try tools.next()) |tool| {
                    defer scope.engine.freeValue(tool);
                    const candidate = try scope.get(tool, "name");
                    if (scope.equal(lowered, try scope.invoke(candidate, "toLowerCase", &.{}))) {
                        name = candidate;
                        break;
                    }
                }
            }
            try scope.put(block, "name", name);
            const arguments = try scope.get(input_block, "input");
            try scope.put(block, "arguments", if (v.nullish(arguments)) try scope.object() else arguments);
            try scope.put(block, "partialJson", try scope.text(""));
            start = "toolcall_start";
        } else return;
        try scope.put(block, "index", try scope.get(input, "index"));
        const position = try v.length(scope, blocks);
        _ = try scope.invoke(blocks, "push", &.{block});
        try push(scope, owner, start, position, null, c.pi_js_undefined());
    } else if (try v.eq(scope, kind, "content_block_delta")) {
        const position = (try find(scope, blocks, try scope.get(input, "index"))) orelse return;
        const block = try v.at(scope, blocks, position);
        const delta = try scope.get(input, "delta");
        const delta_kind = try scope.get(delta, "type");
        inline for (.{ .{ "text_delta", "text", "text", "text_delta" }, .{ "thinking_delta", "thinking", "thinking", "thinking_delta" }, .{ "input_json_delta", "toolCall", "partialJson", "toolcall_delta" } }) |entry| {
            if (try v.eq(scope, delta_kind, entry[0]) and try v.eq(scope, try scope.get(block, "type"), entry[1])) {
                const fragment = try scope.get(delta, if (@import("std").mem.eql(u8, entry[0], "input_json_delta")) "partial_json" else entry[2]);
                const joined = try scope.concat(try scope.get(block, entry[2]), fragment);
                try scope.set(block, entry[2], joined);
                if (comptime @import("std").mem.eql(u8, entry[0], "input_json_delta")) try scope.set(block, "arguments", try scope.invoke(try scope.get(owner, "json"), "parseStreamingJson", &.{joined}));
                try push(scope, owner, entry[3], position, "delta", fragment);
                return;
            }
        }
        if (try v.eq(scope, delta_kind, "signature_delta") and try v.eq(scope, try scope.get(block, "type"), "thinking")) {
            var signature = try scope.get(block, "thinkingSignature");
            if (!scope.truthy(signature)) signature = try scope.text("");
            try scope.set(block, "thinkingSignature", try scope.concat(signature, try scope.get(delta, "signature")));
        }
    } else if (try v.eq(scope, kind, "content_block_stop")) {
        const position = (try find(scope, blocks, try scope.get(input, "index"))) orelse return;
        const block = try v.at(scope, blocks, position);
        try v.remove(scope, block, "index");
        if (try v.eq(scope, try scope.get(block, "type"), "text")) try push(scope, owner, "text_end", position, "content", try scope.get(block, "text")) else if (try v.eq(scope, try scope.get(block, "type"), "thinking")) try push(scope, owner, "thinking_end", position, "content", try scope.get(block, "thinking")) else if (try v.eq(scope, try scope.get(block, "type"), "toolCall")) {
            const parsed = try scope.invoke(try scope.get(owner, "json"), "parseToolCallArguments", &.{try scope.get(block, "partialJson")});
            _ = try scope.invoke(try scope.global("Object"), "assign", &.{ block, parsed });
            try v.remove(scope, block, "partialJson");
            try push(scope, owner, "toolcall_end", position, "toolCall", block);
        }
    } else if (try v.eq(scope, kind, "message_delta")) {
        const transformations = try scope.get(input, "input_transformations");
        if (try v.array(scope, transformations)) try scope.set(owner, "transformations", transformations);
        const delta = try scope.get(input, "delta");
        const reason = try scope.get(delta, "stop_reason");
        if (scope.truthy(reason)) try stop(scope, output, reason, try scope.get(delta, "stop_details"));
        const tokens = try scope.get(input, "usage");
        if (scope.truthy(tokens)) try updateUsage(scope, owner, tokens, false) else try total(scope, owner);
    }
}
fn diagnostic(scope: *Scope, owner: c.JSValue, item: c.JSValue) !void {
    const output = try scope.get(owner, "output");
    const previous = try scope.get(output, "diagnostics");
    const items = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(scope.engine, if (v.nullish(previous)) try scope.array() else previous, null));
    _ = try scope.invoke(items, "push", &.{item});
    try scope.set(output, "diagnostics", items);
}
fn strictFallback(scope: *Scope, owner: c.JSValue, failure: c.JSValue) !void {
    const item = try scope.object();
    try scope.put(item, "type", try scope.text("anthropic_strict_tools_fallback"));
    try scope.put(item, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    const error_value = try scope.object();
    try scope.put(error_value, "message", try scope.get(failure, "message"));
    try scope.put(item, "error", error_value);
    const details = try scope.object();
    try scope.put(details, "reason", try scope.text("strict_tool_limits_exceeded"));
    try scope.put(item, "details", details);
    try diagnostic(scope, owner, item);
}
fn finish(scope: *Scope, owner: c.JSValue, aborted: bool) !void {
    const output = try scope.get(owner, "output");
    if (aborted) return v.errorText(scope, try scope.text("Request was aborted"));
    const reason = try scope.get(output, "stopReason");
    if (try v.eq(scope, reason, "pending")) return v.errorText(scope, try scope.text("Anthropic stream ended without a stop reason"));
    if (try v.eq(scope, reason, "aborted") or try v.eq(scope, reason, "error")) {
        const failure = try scope.get(output, "errorMessage");
        return v.errorText(scope, if (scope.truthy(failure)) failure else try scope.text("An unknown error occurred"));
    }
    const transformations = try scope.get(owner, "transformations");
    if (!v.nullish(transformations) and try v.length(scope, transformations) > 0) {
        const item = try scope.object();
        try scope.put(item, "type", try scope.text("anthropic_input_transformations"));
        try scope.put(item, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
        const details = try scope.object();
        const converted = try scope.array();
        var rows = try v.iterator(scope, transformations);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |value| {
            defer scope.engine.freeValue(value);
            const entry = try scope.object();
            inline for (.{ "type", "path", "reason" }) |key| {
                const field = try scope.get(value, key);
                try scope.put(entry, key, if (v.nullish(field)) c.pi_js_undefined() else field);
            }
            _ = try scope.invoke(converted, "push", &.{entry});
        }
        try scope.put(details, "transformations", converted);
        try scope.put(item, "details", details);
        try diagnostic(scope, owner, item);
    }
    const done = try scope.object();
    try scope.put(done, "type", try scope.text("done"));
    try scope.put(done, "reason", reason);
    try scope.put(done, "message", output);
    _ = try scope.invoke(try scope.get(owner, "stream"), "push", &.{done});
    _ = try scope.invoke(try scope.get(owner, "stream"), "end", &.{});
}
fn fail(scope: *Scope, owner: c.JSValue, failure: c.JSValue, aborted: bool) !void {
    const output = try scope.get(owner, "output");
    var rows = try v.iterator(scope, try scope.get(output, "content"));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |block| {
        defer scope.engine.freeValue(block);
        try v.remove(scope, block, "index");
        try v.remove(scope, block, "partialJson");
    }
    const reason = try scope.text(if (aborted) "aborted" else "error");
    try scope.set(output, "stopReason", reason);
    const error_constructor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, failure, error_constructor);
    if (instance < 0) return v.js.capture(scope.engine);
    try scope.set(output, "errorMessage", if (instance == 1) try scope.get(failure, "message") else try scope.invoke(try scope.global("JSON"), "stringify", &.{failure}));
    const item = try scope.object();
    try scope.put(item, "type", try scope.text("error"));
    try scope.put(item, "reason", reason);
    try scope.put(item, "error", output);
    _ = try scope.invoke(try scope.get(owner, "stream"), "push", &.{item});
    _ = try scope.invoke(try scope.get(owner, "stream"), "end", &.{});
}

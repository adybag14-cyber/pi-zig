//! Owner-thread Converse Stream event bodies. State is a GC-visible JS graph.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn create(engine: *v.em.Engine, model: c.JSValue, stream: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    const output = try s.object();
    try s.put(output, "role", try s.text("assistant"));
    try s.put(output, "content", try s.array());
    try s.put(output, "api", try s.text("bedrock-converse-stream"));
    try s.put(output, "provider", try s.get(model, "provider"));
    try s.put(output, "model", try s.get(model, "id"));
    const usage = try s.object();
    const cost = try s.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |key| try s.put(usage, key, c.JS_NewInt32(engine.context, 0));
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try s.put(cost, key, c.JS_NewInt32(engine.context, 0));
    try s.put(usage, "cost", cost);
    try s.put(output, "usage", usage);
    try s.put(output, "stopReason", try s.text("pending"));
    try s.put(output, "timestamp", try s.invoke(try s.global("Date"), "now", &.{}));
    try s.put(state, "output", output);
    try s.put(state, "model", model);
    try s.put(state, "stream", stream);
    try s.put(state, "json", try s.own(try @import("native_ai_json_parse.zig").create(engine)));
    return c.JS_DupValue(engine.context, state);
}
fn emit(s: *Scope, state: c.JSValue, kind: []const u8, index: ?u32, key: ?[*:0]const u8, value: c.JSValue) !void {
    const event = try s.object();
    try s.put(event, "type", try s.text(kind));
    if (index) |i| try s.put(event, "contentIndex", c.JS_NewUint32(s.engine.context, i));
    if (key) |name| try s.put(event, name, value);
    try s.put(event, "partial", try s.get(state, "output"));
    _ = try s.invoke(try s.get(state, "stream"), "push", &.{event});
}
fn find(s: *Scope, blocks: c.JSValue, index: c.JSValue) !?u32 {
    const n = try v.length(s, blocks);
    for (0..n) |i| if (s.equal(try s.get(try v.at(s, blocks, @intCast(i)), "index"), index)) return @intCast(i);
    return null;
}
fn flush(s: *Scope, block: c.JSValue) !void {
    const chunks = try s.get(block, "redactedChunks");
    if (!try v.eq(s, try s.get(block, "type"), "thinking") or !s.truthy(chunks)) return;
    var binary = try s.text("");
    var rows = try v.iterator(s, chunks);
    defer rows.deinit();
    errdefer rows.closePreserving();
    var steps: usize = 0;
    while (try rows.next()) |chunk| {
        defer s.engine.freeValue(chunk);
        var row: Scope = .{ .engine = s.engine };
        defer row.deinit();
        var index: f64 = 0;
        while (try @import("native_image_arithmetic.zig").compare(s.engine, .less, c.JS_NewFloat64(s.engine.context, index), try row.get(chunk, "length"))) : (index += 0x8000) {
            try @import("native_ai_budget.zig").step(s.engine, &steps);
            var window: Scope = .{ .engine = s.engine };
            defer window.deinit();
            const string = try window.global("String");
            const from_char_code = try window.get(string, "fromCharCode");
            const view = try window.invoke(chunk, "subarray", &.{ c.JS_NewFloat64(s.engine.context, index), c.JS_NewFloat64(s.engine.context, index + 0x8000) });
            var values: std.ArrayList(c.JSValue) = .empty;
            defer {
                for (values.items) |value| s.engine.freeValue(value);
                values.deinit(s.engine.gpa);
            }
            var spread = try v.iterator(&window, view);
            defer spread.deinit();
            errdefer spread.closePreserving();
            while (try spread.next()) |value| {
                try @import("native_ai_budget.zig").step(s.engine, &steps);
                values.append(s.engine.gpa, value) catch |err| {
                    s.engine.freeValue(value);
                    return err;
                };
            }
            binary = try s.concat(binary, try window.call(from_char_code, string, values.items));
        }
    }
    try s.set(block, "thinkingSignature", try s.call(try s.global("btoa"), c.pi_js_undefined(), &.{binary}));
    try v.remove(s, block, "redactedChunks");
}
fn finalize(s: *Scope, output: c.JSValue) !void {
    const blocks = try s.get(output, "content");
    const n = try v.length(s, blocks);
    for (0..n) |i| {
        var row: Scope = .{ .engine = s.engine };
        defer row.deinit();
        const block = try v.at(&row, blocks, @intCast(i));
        try v.remove(&row, block, "index");
        try v.remove(&row, block, "partialJson");
        try flush(&row, block);
    }
}
fn append(s: *Scope, block: c.JSValue, name: [*:0]const u8, delta: c.JSValue) !void {
    try s.set(block, name, try s.concat(try s.get(block, name), delta));
}
pub fn item(s: *Scope, state: c.JSValue, event: c.JSValue) !void {
    const output = try s.get(state, "output");
    const blocks = try s.get(output, "content");
    const message = try s.get(event, "messageStart");
    if (s.truthy(message)) {
        if (!try v.eq(s, try s.get(message, "role"), "assistant")) return v.errorText(s, try s.text("Unexpected assistant message start but got user message start instead"));
        return emit(s, state, "start", null, null, c.pi_js_undefined());
    }
    const start = try s.get(event, "contentBlockStart");
    if (s.truthy(start)) {
        const tool = try v.optional(s, try s.get(start, "start"), "toolUse");
        if (s.truthy(tool)) {
            const block = try s.object();
            try s.put(block, "type", try s.text("toolCall"));
            inline for (.{ .{ "id", "toolUseId" }, .{ "name", "name" } }) |pair| {
                const value = try s.get(tool, pair[1]);
                try s.put(block, pair[0], if (s.truthy(value)) value else try s.text(""));
            }
            try s.put(block, "arguments", try s.object());
            try s.put(block, "partialJson", try s.text(""));
            try s.put(block, "index", try s.get(start, "contentBlockIndex"));
            _ = try s.invoke(blocks, "push", &.{block});
            try emit(s, state, "toolcall_start", (try v.length(s, blocks)) - 1, null, c.pi_js_undefined());
        }
        return;
    }
    const delta_event = try s.get(event, "contentBlockDelta");
    if (s.truthy(delta_event)) {
        const wire_index = try s.get(delta_event, "contentBlockIndex");
        const delta = try s.get(delta_event, "delta");
        var index = try find(s, blocks, wire_index);
        var block = if (index) |i| try v.at(s, blocks, i) else c.pi_js_undefined();
        const text = try v.optional(s, delta, "text");
        if (!c.JS_IsUndefined(text)) {
            if (!s.truthy(block)) {
                block = try s.object();
                try s.put(block, "type", try s.text("text"));
                try s.put(block, "text", try s.text(""));
                try s.put(block, "index", wire_index);
                _ = try s.invoke(blocks, "push", &.{block});
                index = (try v.length(s, blocks)) - 1;
                try emit(s, state, "text_start", index, null, c.pi_js_undefined());
            }
            if (try v.eq(s, try s.get(block, "type"), "text")) {
                try append(s, block, "text", text);
                try emit(s, state, "text_delta", index, "delta", text);
            }
        } else if (s.truthy(try v.optional(s, delta, "toolUse")) and s.truthy(block) and try v.eq(s, try s.get(block, "type"), "toolCall")) {
            const input = try s.get(try s.get(delta, "toolUse"), "input");
            const chunk = if (s.truthy(input)) input else try s.text("");
            const previous = try s.get(block, "partialJson");
            try s.set(block, "partialJson", try s.concat(if (s.truthy(previous)) previous else try s.text(""), chunk));
            try s.set(block, "arguments", try s.invoke(try s.get(state, "json"), "parseStreamingJson", &.{try s.get(block, "partialJson")}));
            try emit(s, state, "toolcall_delta", index, "delta", chunk);
        } else if (s.truthy(try v.optional(s, delta, "reasoningContent"))) {
            if (!s.truthy(block)) {
                block = try s.object();
                try s.put(block, "type", try s.text("thinking"));
                try s.put(block, "thinking", try s.text(""));
                try s.put(block, "thinkingSignature", try s.text(""));
                try s.put(block, "index", wire_index);
                _ = try s.invoke(blocks, "push", &.{block});
                index = (try v.length(s, blocks)) - 1;
                try emit(s, state, "thinking_start", index, null, c.pi_js_undefined());
            }
            if (try v.eq(s, try s.get(block, "type"), "thinking")) {
                const reasoning = try s.get(delta, "reasoningContent");
                const thinking = try s.get(reasoning, "text");
                if (s.truthy(thinking)) {
                    try append(s, block, "thinking", thinking);
                    try emit(s, state, "thinking_delta", index, "delta", thinking);
                }
                const signature = try s.get(reasoning, "signature");
                if (s.truthy(signature) and !s.truthy(try s.get(block, "redacted"))) try append(s, block, "thinkingSignature", signature);
                const redacted = try s.get(reasoning, "redactedContent");
                if (s.truthy(try v.optional(s, redacted, "length"))) {
                    if (!s.truthy(try s.get(block, "redacted"))) {
                        try s.set(block, "redacted", c.pi_js_bool(s.engine.context, 1));
                        try s.set(block, "thinkingSignature", try s.text(""));
                        const placeholder = try s.text("[Reasoning redacted]");
                        try append(s, block, "thinking", placeholder);
                        try emit(s, state, "thinking_delta", index, "delta", placeholder);
                    }
                    var chunks = try s.get(block, "redactedChunks");
                    if (v.nullish(chunks)) {
                        chunks = try s.array();
                        try s.set(block, "redactedChunks", chunks);
                    }
                    _ = try s.invoke(chunks, "push", &.{redacted});
                }
            }
        }
        return;
    }
    const stop = try s.get(event, "contentBlockStop");
    if (s.truthy(stop)) {
        const index = (try find(s, blocks, try s.get(stop, "contentBlockIndex"))) orelse return;
        const block = try v.at(s, blocks, index);
        try v.remove(s, block, "index");
        const kind = try s.get(block, "type");
        if (try v.eq(s, kind, "text")) return emit(s, state, "text_end", index, "content", try s.get(block, "text"));
        if (try v.eq(s, kind, "thinking")) {
            try flush(s, block);
            return emit(s, state, "thinking_end", index, "content", try s.get(block, "thinking"));
        }
        if (try v.eq(s, kind, "toolCall")) {
            _ = try s.invoke(try s.global("Object"), "assign", &.{ block, try s.invoke(try s.get(state, "json"), "parseToolCallArguments", &.{try s.get(block, "partialJson")}) });
            try v.remove(s, block, "partialJson");
            return emit(s, state, "toolcall_end", index, "toolCall", block);
        }
        return;
    }
    const message_stop = try s.get(event, "messageStop");
    if (s.truthy(message_stop)) {
        const reason = try s.get(message_stop, "stopReason");
        try s.set(output, "rawStopReason", reason);
        var mapped: []const u8 = "error";
        if (try v.eq(s, reason, "end_turn") or try v.eq(s, reason, "stop_sequence")) mapped = "stop" else if (try v.eq(s, reason, "max_tokens") or try v.eq(s, reason, "model_context_window_exceeded")) mapped = "length" else if (try v.eq(s, reason, "tool_use")) mapped = "toolUse" else if (s.truthy(reason)) try s.set(output, "errorMessage", try s.concat(try s.text("Provider stopped with: "), try s.stringify(reason)));
        try s.set(output, "stopReason", try s.text(mapped));
        return;
    }
    const metadata = try s.get(event, "metadata");
    if (s.truthy(metadata)) {
        const input = try s.get(metadata, "usage");
        if (s.truthy(input)) {
            const usage = try s.get(output, "usage");
            inline for (.{ .{ "input", "inputTokens" }, .{ "output", "outputTokens" }, .{ "cacheRead", "cacheReadInputTokens" }, .{ "cacheWrite", "cacheWriteInputTokens" } }) |pair| {
                const value = try s.get(input, pair[1]);
                try s.set(usage, pair[0], if (s.truthy(value)) value else c.JS_NewInt32(s.engine.context, 0));
            }
            var long: c.JSValue = c.JS_NewInt32(s.engine.context, 0);
            const details = try s.get(input, "cacheDetails");
            if (!v.nullish(details)) {
                var rows = try v.iterator(s, details);
                defer rows.deinit();
                errdefer rows.closePreserving();
                while (try rows.next()) |detail| {
                    defer s.engine.freeValue(detail);
                    if (try v.eq(s, try s.get(detail, "ttl"), "1h")) {
                        const amount = try s.get(detail, "inputTokens");
                        long = try s.concat(long, if (v.nullish(amount)) c.JS_NewInt32(s.engine.context, 0) else amount);
                    }
                }
            }
            try s.set(usage, "cacheWrite1h", if (v.nullish(details)) c.pi_js_undefined() else long);
            const total = try s.get(input, "totalTokens");
            try s.set(usage, "totalTokens", if (s.truthy(total)) total else try s.concat(try s.get(usage, "input"), try s.get(usage, "output")));
            _ = try s.own(try @import("native_ai_cost.zig").calculate(s.engine, try s.get(state, "model"), usage));
        }
        return;
    }
    inline for (.{ "internalServerException", "modelStreamErrorException", "validationException", "throttlingException", "serviceUnavailableException" }) |key| {
        const exception = try s.get(event, key);
        if (s.truthy(exception)) {
            _ = try s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, exception)));
            unreachable;
        }
    }
}
pub fn finish(s: *Scope, state: c.JSValue, aborted: bool) !void {
    const output = try s.get(state, "output");
    if (aborted) return v.errorText(s, try s.text("Request was aborted"));
    const reason = try s.get(output, "stopReason");
    if (try v.eq(s, reason, "pending")) return v.errorText(s, try s.text("Bedrock stream ended without a stop reason"));
    if (try v.eq(s, reason, "error") or try v.eq(s, reason, "aborted")) {
        const message = try s.get(output, "errorMessage");
        return v.errorText(s, if (s.truthy(message)) message else try s.text("An unknown error occurred"));
    }
    try finalize(s, output);
    const event = try s.object();
    try s.put(event, "type", try s.text("done"));
    try s.put(event, "reason", reason);
    try s.put(event, "message", output);
    _ = try s.invoke(try s.get(state, "stream"), "push", &.{event});
    _ = try s.invoke(try s.get(state, "stream"), "end", &.{});
}
pub fn fail(s: *Scope, state: c.JSValue, reason: c.JSValue, aborted: bool, request_id: c.JSValue) !void {
    const output = try s.get(state, "output");
    try finalize(s, output);
    try s.set(output, "stopReason", try s.text(if (aborted) "aborted" else "error"));
    var text = try @import("native_ai_provider_error.zig").format(s, try @import("native_ai_provider_error.zig").normalize(s, reason), c.pi_js_undefined());
    if (s.truthy(try v.optional(s, reason, "__bedrockServiceException"))) {
        const name = try s.get(reason, "name");
        var prefix = name;
        inline for (.{ .{ "InternalServerException", "Internal server error" }, .{ "ModelStreamErrorException", "Model stream error" }, .{ "ValidationException", "Validation error" }, .{ "ThrottlingException", "Throttling error" }, .{ "ServiceUnavailableException", "Service unavailable" } }) |pair| if (try v.eq(s, name, pair[0])) {
            prefix = try s.text(pair[1]);
        };
        text = try s.concat(try s.concat(prefix, try s.text(": ")), text);
    }
    const regex = try s.own(try v.js.builtin(s.engine, "RegExp", &.{ try s.text("data retention mode"), try s.text("i") }));
    if (s.truthy(try s.invoke(regex, "test", &.{text}))) text = try s.concat(text, try s.text(" See https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html for supported data retention modes."));
    try s.set(output, "errorMessage", text);
    if (!aborted) {
        const details = try s.object();
        const metadata = try v.optional(s, reason, "$metadata");
        const status = try v.optional(s, metadata, "httpStatusCode");
        if (c.JS_IsNumber(status)) try s.put(details, "status", status);
        const instance = c.JS_IsInstanceOf(s.engine.context, reason, try s.global("Error"));
        if (instance < 0) return v.js.capture(s.engine);
        if (instance == 1) {
            const name = try s.get(reason, "name");
            if (s.truthy(try s.invoke(name, "endsWith", &.{try s.text("Exception")}))) {
                const normalized = try diagnostic(s, name);
                if (!c.JS_IsUndefined(normalized)) try s.put(details, "errorCode", normalized);
            }
        }
        const specific = try diagnostic(s, try v.optional(s, metadata, "requestId"));
        const id = if (c.JS_IsUndefined(specific)) request_id else specific;
        if (!c.JS_IsUndefined(id)) try s.put(details, "requestId", id);
        if (try v.length(s, try s.invoke(try s.global("Object"), "keys", &.{details})) > 0) {
            const diagnostic_event = try s.object();
            try s.put(diagnostic_event, "type", try s.text("bedrock_response_failure"));
            try s.put(diagnostic_event, "timestamp", try s.invoke(try s.global("Date"), "now", &.{}));
            try s.put(diagnostic_event, "details", details);
            var diagnostics = try s.get(output, "diagnostics");
            if (v.nullish(diagnostics)) {
                diagnostics = try s.array();
                try s.set(output, "diagnostics", diagnostics);
            }
            _ = try s.invoke(diagnostics, "push", &.{diagnostic_event});
        }
    }
    const event = try s.object();
    try s.put(event, "type", try s.text("error"));
    try s.put(event, "reason", try s.get(output, "stopReason"));
    try s.put(event, "error", output);
    _ = try s.invoke(try s.get(state, "stream"), "push", &.{event});
    _ = try s.invoke(try s.get(state, "stream"), "end", &.{});
}
pub fn diagnostic(s: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(value)) return c.pi_js_undefined();
    const trimmed = try s.invoke(value, "trim", &.{});
    const n = try v.length(s, trimmed);
    return if (n == 0 or n > 200) c.pi_js_undefined() else trimmed;
}

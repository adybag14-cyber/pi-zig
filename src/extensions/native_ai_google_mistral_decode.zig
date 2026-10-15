//! Google and Mistral stream algorithms. All mutable state is traced guest data.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const arithmetic = @import("native_image_arithmetic.zig");
pub const Kind = enum { google, vertex, mistral };
fn binary(scope: *Scope, op: arithmetic.Operation, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, op, a, b));
}
fn zero(scope: *Scope, value: c.JSValue) c.JSValue {
    return if (scope.truthy(value)) value else c.JS_NewInt32(scope.engine.context, 0);
}
fn emit(scope: *Scope, owner: c.JSValue, kind: []const u8, block: ?c.JSValue, key: ?[*:0]const u8, value: c.JSValue) !void {
    const index = if (block != null) try binary(scope, .subtract, try scope.get(try scope.get(owner, "blocks"), "length"), c.JS_NewInt32(scope.engine.context, 1)) else null;
    try emitAt(scope, owner, kind, index, key, value);
}
fn emitAt(scope: *Scope, owner: c.JSValue, kind: []const u8, index: ?c.JSValue, key: ?[*:0]const u8, value: c.JSValue) !void {
    const event = try scope.object();
    const output = try scope.get(owner, "output");
    try scope.put(event, "type", try scope.text(kind));
    if (index) |position| try scope.put(event, "contentIndex", position);
    if (key) |name| try scope.put(event, name, value);
    try scope.put(event, if (@import("std").mem.eql(u8, kind, "done")) "message" else if (@import("std").mem.eql(u8, kind, "error")) "error" else "partial", output);
    _ = try scope.invoke(try scope.get(owner, "stream"), "push", &.{event});
}
pub fn create(engine: *v.em.Engine, model: c.JSValue, stream: c.JSValue, json: c.JSValue, counter_owner: c.JSValue, comptime kind: Kind) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "model", model);
    try scope.put(owner, "stream", stream);
    try scope.put(owner, "json", json);
    try scope.put(owner, "current", c.pi_js_null());
    try scope.put(owner, "tools", c.pi_js_undefined());
    try scope.put(owner, "finished", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "counterOwner", counter_owner);
    const output = try scope.object();
    try scope.put(output, "role", try scope.text("assistant"));
    const blocks = try scope.array();
    try scope.put(output, "content", blocks);
    try scope.put(owner, "blocks", blocks);
    try scope.put(output, "api", if (kind == .mistral) try scope.get(model, "api") else try scope.text(if (kind == .google) "google-generative-ai" else "google-vertex"));
    try scope.put(output, "provider", try scope.get(model, "provider"));
    try scope.put(output, "model", try scope.get(model, "id"));
    const usage = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |key| try scope.put(usage, key, c.JS_NewInt32(engine.context, 0));
    try scope.put(usage, "cost", try emptyCost(&scope));
    try scope.put(output, "usage", usage);
    try scope.put(output, "stopReason", try scope.text("pending"));
    try scope.put(output, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.put(owner, "output", output);
    const result = try scope.object();
    try scope.put(result, "output", output);
    inline for (.{ "start", "push", "finish", "fail" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                if (row.truthy(try row.get(roots[0], "finished"))) return error.ProviderDecoderAlreadyFinished;
                switch (index) {
                    0 => {
                        try emit(&row, roots[0], "start", null, null, c.pi_js_undefined());
                        if (kind == .mistral) try row.put(roots[0], "tools", try row.own(try v.js.builtin(host, "Map", &.{})));
                    },
                    1 => if (kind != .mistral) try google(&row, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined()) else try mistral(&row, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined()),
                    2 => try finish(&row, roots[0], args.len > 0 and row.truthy(args[0]), kind),
                    3 => try fail(&row, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined(), args.len > 1 and row.truthy(args[1]), kind),
                    else => unreachable,
                }
                return c.pi_js_undefined();
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (index == 0) 0 else 1, Adapter.call, &.{owner})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn emptyCost(scope: *Scope) !c.JSValue {
    const result = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try scope.put(result, key, c.JS_NewInt32(scope.engine.context, 0));
    return result;
}
fn close(scope: *Scope, owner: c.JSValue) !void {
    const current = try scope.get(owner, "current");
    if (!scope.truthy(current)) return;
    const thinking = try v.eq(scope, try scope.get(current, "type"), "thinking");
    try emit(scope, owner, if (thinking) "thinking_end" else "text_end", current, "content", try scope.get(current, if (thinking) "thinking" else "text"));
    try scope.put(owner, "current", c.pi_js_null());
}
fn append(scope: *Scope, owner: c.JSValue, value: c.JSValue, thinking: bool, source_part: c.JSValue, skip_empty: bool) !void {
    const text = if (skip_empty) try v.sanitize(scope, value) else value;
    if (skip_empty and try v.length(scope, text) == 0) return;
    var current = try scope.get(owner, "current");
    const key: [*:0]const u8 = if (thinking) "thinking" else "text";
    if (!scope.truthy(current) or !try v.eq(scope, try scope.get(current, "type"), @import("std").mem.span(key))) {
        try close(scope, owner);
        current = try scope.object();
        try scope.put(current, "type", try scope.text(@import("std").mem.span(key)));
        try scope.put(current, key, try scope.text(""));
        if (thinking and !skip_empty) try scope.put(current, "thinkingSignature", c.pi_js_undefined());
        _ = try scope.invoke(try scope.get(try scope.get(owner, "output"), "content"), "push", &.{current});
        try scope.put(owner, "current", current);
        try emit(scope, owner, if (thinking) "thinking_start" else "text_start", current, null, c.pi_js_undefined());
    }
    try scope.set(current, key, try scope.concat(try scope.get(current, key), if (skip_empty) text else try scope.get(source_part, "text")));
    if (!skip_empty) {
        const signature_key: [*:0]const u8 = if (thinking) "thinkingSignature" else "textSignature";
        const previous = try scope.get(current, signature_key);
        const signature = try scope.get(source_part, "thoughtSignature");
        try scope.set(current, signature_key, if (c.JS_IsString(signature) and try v.length(scope, signature) > 0) signature else previous);
    }
    try emit(scope, owner, if (thinking) "thinking_delta" else "text_delta", current, "delta", if (skip_empty) text else try scope.get(source_part, "text"));
}
fn google(scope: *Scope, owner: c.JSValue, chunk: c.JSValue) !void {
    const output = try scope.get(owner, "output");
    if (!scope.truthy(try scope.get(output, "responseId"))) try scope.set(output, "responseId", try scope.get(chunk, "responseId"));
    const candidates = try scope.get(chunk, "candidates");
    const candidate = if (!v.nullish(candidates) and try v.length(scope, candidates) > 0) try v.at(scope, candidates, 0) else c.pi_js_undefined();
    const parts = try v.optional(scope, try v.optional(scope, candidate, "content"), "parts");
    if (scope.truthy(parts)) {
        var rows = try v.iterator(scope, parts);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |part| {
            defer scope.engine.freeValue(part);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            const text = try row.get(part, "text");
            if (!c.JS_IsUndefined(text)) try append(&row, owner, text, row.equal(try row.get(part, "thought"), c.pi_js_bool(scope.engine.context, 1)), part, false);
            const function = try row.get(part, "functionCall");
            if (!row.truthy(function)) continue;
            try close(&row, owner);
            var id = try row.get(try row.get(part, "functionCall"), "id");
            if (!row.truthy(id) or try hasGoogleTool(&row, owner, id)) {
                const call_name = try row.stringify(try row.get(try row.get(part, "functionCall"), "name"));
                const now = try row.stringify(try row.invoke(try row.global("Date"), "now", &.{}));
                const counter_owner = try row.get(owner, "counterOwner");
                const counter = try binary(&row, .add, try row.get(counter_owner, "counter"), c.JS_NewInt32(scope.engine.context, 1));
                try row.put(counter_owner, "counter", counter);
                id = try row.concat(try row.concat(call_name, try row.text("_")), now);
                id = try row.concat(try row.concat(id, try row.text("_")), try row.stringify(counter));
            }
            const block = try row.object();
            try row.put(block, "type", try row.text("toolCall"));
            try row.put(block, "id", id);
            const name = try row.get(try row.get(part, "functionCall"), "name");
            try row.put(block, "name", if (row.truthy(name)) name else try row.text(""));
            const args = try row.get(try row.get(part, "functionCall"), "args");
            try row.put(block, "arguments", if (v.nullish(args)) try row.object() else args);
            const sig = try row.get(part, "thoughtSignature");
            if (row.truthy(sig)) try row.put(block, "thoughtSignature", try row.get(part, "thoughtSignature"));
            _ = try row.invoke(try row.get(output, "content"), "push", &.{block});
            try emit(&row, owner, "toolcall_start", block, null, c.pi_js_undefined());
            try emit(&row, owner, "toolcall_delta", block, "delta", try row.invoke(try row.global("JSON"), "stringify", &.{try row.get(block, "arguments")}));
            try emit(&row, owner, "toolcall_end", block, "toolCall", block);
        }
    }
    const reason = try v.optional(scope, candidate, "finishReason");
    if (scope.truthy(reason)) {
        try scope.set(output, "rawStopReason", reason);
        var handled = try v.eq(scope, reason, "STOP") or try v.eq(scope, reason, "MAX_TOKENS");
        inline for (.{ "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "SAFETY", "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT", "IMAGE_RECITATION", "IMAGE_OTHER", "RECITATION", "FINISH_REASON_UNSPECIFIED", "OTHER", "LANGUAGE", "MALFORMED_FUNCTION_CALL", "UNEXPECTED_TOOL_CALL", "TOO_MANY_TOOL_CALLS", "NO_IMAGE" }) |known| {
            if (try v.eq(scope, reason, known)) handled = true;
        }
        if (!handled) return v.errorText(scope, try scope.concat(try scope.text("Unhandled stop reason: "), try scope.stringify(reason)));
        try scope.set(output, "stopReason", try scope.text(if (try v.eq(scope, reason, "MAX_TOKENS")) "length" else if (try v.eq(scope, reason, "STOP")) "stop" else "error"));
        if (try hasGoogleTool(scope, owner, null) and try v.eq(scope, try scope.get(output, "stopReason"), "stop")) try scope.set(output, "stopReason", try scope.text("toolUse"));
    }
    const raw = try scope.get(chunk, "usageMetadata");
    if (scope.truthy(raw)) {
        const usage = try scope.object();
        const read = zero(scope, try scope.get(raw, "cachedContentTokenCount"));
        const thoughts = zero(scope, try scope.get(raw, "thoughtsTokenCount"));
        try scope.put(usage, "input", try binary(scope, .subtract, zero(scope, try scope.get(raw, "promptTokenCount")), read));
        try scope.put(usage, "output", try binary(scope, .add, zero(scope, try scope.get(raw, "candidatesTokenCount")), thoughts));
        try scope.put(usage, "cacheRead", read);
        try scope.put(usage, "cacheWrite", c.JS_NewInt32(scope.engine.context, 0));
        try scope.put(usage, "reasoning", thoughts);
        try scope.put(usage, "totalTokens", zero(scope, try scope.get(raw, "totalTokenCount")));
        try setUsage(scope, owner, usage);
    }
}
fn hasGoogleTool(scope: *Scope, owner: c.JSValue, id: ?c.JSValue) !bool {
    const Predicate = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const block = if (args.len > 0) args[0] else c.pi_js_undefined();
            const found = try v.eq(&row, try row.get(block, "type"), "toolCall") and (roots.len == 0 or row.equal(try row.get(block, "id"), roots[0]));
            return c.pi_js_bool(engine.context, @intFromBool(found));
        }
    };
    var roots = [_]c.JSValue{id orelse c.pi_js_undefined()};
    const predicate = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Predicate.call, if (id != null) &roots else &.{}));
    return scope.truthy(try scope.invoke(try scope.get(try scope.get(owner, "output"), "content"), "some", &.{predicate}));
}
fn setUsage(scope: *Scope, owner: c.JSValue, usage: c.JSValue) !void {
    try scope.put(usage, "cost", try emptyCost(scope));
    _ = try scope.own(try @import("native_ai_cost.zig").calculate(scope.engine, try scope.get(owner, "model"), usage));
    try scope.set(try scope.get(owner, "output"), "usage", usage);
}
fn mistral(scope: *Scope, owner: c.JSValue, chunk: c.JSValue) !void {
    const output = try scope.get(owner, "output");
    if (!scope.truthy(try scope.get(output, "responseId"))) try scope.set(output, "responseId", try scope.get(chunk, "id"));
    const raw = try scope.get(chunk, "usage");
    if (scope.truthy(raw)) {
        const prompt = zero(scope, try scope.get(raw, "prompt_tokens"));
        var cached = c.pi_js_undefined();
        inline for (.{ .{ "promptTokensDetails", "cachedTokens" }, .{ "prompt_tokens_details", "cached_tokens" }, .{ "promptTokenDetails", "cachedTokens" }, .{ "prompt_token_details", "cached_tokens" } }) |pair| {
            if (v.nullish(cached)) cached = try v.optional(scope, try scope.get(raw, pair[0]), pair[1]);
        }
        inline for (.{ "numCachedTokens", "num_cached_tokens" }) |key| {
            if (v.nullish(cached)) cached = try scope.get(raw, key);
        }
        if (!c.JS_IsNumber(cached) or !scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{cached}))) cached = c.JS_NewInt32(scope.engine.context, 0);
        const math = try scope.global("Math");
        cached = try scope.invoke(math, "min", &.{ prompt, try scope.invoke(math, "max", &.{ c.JS_NewInt32(scope.engine.context, 0), cached }) });
        const usage = try scope.get(output, "usage");
        const input = try scope.invoke(math, "max", &.{ c.JS_NewInt32(scope.engine.context, 0), try binary(scope, .subtract, prompt, cached) });
        const completion = zero(scope, try scope.get(raw, "completion_tokens"));
        try scope.set(usage, "input", input);
        try scope.set(usage, "output", completion);
        try scope.set(usage, "cacheRead", cached);
        try scope.set(usage, "cacheWrite", c.JS_NewInt32(scope.engine.context, 0));
        const total = try scope.get(raw, "total_tokens");
        try scope.set(usage, "totalTokens", if (scope.truthy(total)) total else try binary(scope, .add, try binary(scope, .add, input, completion), cached));
        _ = try scope.own(try @import("native_ai_cost.zig").calculate(scope.engine, try scope.get(owner, "model"), usage));
    }
    const choices = try scope.get(chunk, "choices");
    if (!try v.array(scope, choices)) return v.errorText(scope, try scope.text("Invalid Mistral streaming event"));
    if (try v.length(scope, choices) == 0) return;
    const choice = try v.at(scope, choices, 0);
    const reason = try scope.get(choice, "finish_reason");
    if (scope.truthy(reason)) {
        try scope.set(output, "rawStopReason", reason);
        const stop = if (try v.eq(scope, reason, "stop")) "stop" else if (try v.eq(scope, reason, "length") or try v.eq(scope, reason, "model_length")) "length" else if (try v.eq(scope, reason, "tool_calls")) "toolUse" else "error";
        try scope.set(output, "stopReason", try scope.text(stop));
        if (@import("std").mem.eql(u8, stop, "error")) try scope.set(output, "errorMessage", if (try v.eq(scope, reason, "error")) try scope.text("Provider stopped with: error (server error)") else try scope.concat(try scope.text("Provider stopped with: "), try scope.stringify(reason)));
    }
    const delta = try scope.get(choice, "delta");
    const content = try v.optional(scope, delta, "content");
    if (!v.nullish(content)) {
        const pieces = if (c.JS_IsString(content)) blk: {
            const items = try scope.array();
            _ = try scope.invoke(items, "push", &.{content});
            break :blk items;
        } else content;
        var rows = try v.iterator(scope, pieces);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |piece| {
            defer scope.engine.freeValue(piece);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            if (c.JS_IsString(piece)) try append(&row, owner, piece, false, c.pi_js_undefined(), true) else if (try v.eq(&row, try row.get(piece, "type"), "text")) {
                const text = try row.get(piece, "text");
                try append(&row, owner, if (v.nullish(text)) try row.text("") else text, false, c.pi_js_undefined(), true);
            } else if (try v.eq(&row, try row.get(piece, "type"), "thinking")) {
                const thinking = try row.get(piece, "thinking");
                var texts = try v.iterator(&row, if (v.nullish(thinking)) try row.array() else thinking);
                defer texts.deinit();
                errdefer texts.closePreserving();
                var combined = try row.text("");
                while (try texts.next()) |part| {
                    defer scope.engine.freeValue(part);
                    const text = try row.get(part, "text");
                    if (!v.nullish(text) and try v.length(&row, text) > 0) combined = try row.concat(combined, text);
                }
                try append(&row, owner, combined, true, c.pi_js_undefined(), true);
            }
        }
    }
    const calls = try v.optional(scope, delta, "tool_calls");
    if (!scope.truthy(calls)) return;
    var rows = try v.iterator(scope, calls);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |call| {
        defer scope.engine.freeValue(call);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        try close(&row, owner);
        var id = c.pi_js_undefined();
        if (row.truthy(try row.get(call, "id")) and !try v.eq(&row, try row.get(call, "id"), "null")) id = try row.get(call, "id") else {
            const index = try row.get(call, "index");
            const fallback = if (v.nullish(index)) c.JS_NewInt32(scope.engine.context, 0) else index;
            id = try @import("native_ai_mistral_request.zig").derive(&row, try row.concat(try row.text("toolcall:"), try row.stringify(fallback)), 0);
        }
        const index = try row.get(call, "index");
        const key = if (v.nullish(index)) id else index;
        const tools = try row.get(owner, "tools");
        const existing_index = try row.invoke(tools, "get", &.{key});
        var block = c.pi_js_undefined();
        if (!c.JS_IsUndefined(existing_index)) {
            const existing = try row.own(try v.js.getKey(scope.engine, try row.get(output, "content"), existing_index));
            if (try v.eq(&row, try v.optional(&row, existing, "type"), "toolCall")) block = existing;
        }
        if (!row.truthy(block)) {
            block = try row.object();
            try row.put(block, "type", try row.text("toolCall"));
            try row.put(block, "id", id);
            try row.put(block, "name", try row.get(try row.get(call, "function"), "name"));
            try row.put(block, "arguments", try row.object());
            try row.put(block, "partialArgs", try row.text(""));
            _ = try row.invoke(try row.get(output, "content"), "push", &.{block});
            const created_index = try binary(&row, .subtract, try row.get(try row.get(output, "content"), "length"), c.JS_NewInt32(scope.engine.context, 1));
            _ = try row.invoke(tools, "set", &.{ key, created_index });
            try emitAt(&row, owner, "toolcall_start", created_index, null, c.pi_js_undefined());
        }
        const arguments = try row.get(try row.get(call, "function"), "arguments");
        const supplied_args = try row.get(try row.get(call, "function"), "arguments");
        const args = if (c.JS_IsString(arguments)) supplied_args else try row.invoke(try row.global("JSON"), "stringify", &.{if (row.truthy(supplied_args)) supplied_args else try row.object()});
        const previous = try row.get(block, "partialArgs");
        const partial = try row.concat(if (row.truthy(previous)) previous else try row.text(""), args);
        try row.set(block, "partialArgs", partial);
        try row.set(block, "arguments", try row.invoke(try row.get(owner, "json"), "parseStreamingJson", &.{partial}));
        try emitAt(&row, owner, "toolcall_delta", try row.invoke(tools, "get", &.{key}), "delta", args);
    }
}
fn formatError(scope: *Scope, value: c.JSValue, kind: Kind) !c.JSValue {
    if (kind != .mistral) return @import("native_ai_provider_error.zig").format(scope, try @import("native_ai_provider_error.zig").normalize(scope, value), c.pi_js_undefined());
    const instance = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    if (instance == 0) return @import("native_ai_provider_error.zig").safeJson(scope, value);
    const initial_status = try scope.get(value, "statusCode");
    const status = if (c.JS_IsNumber(initial_status)) try scope.get(value, "statusCode") else c.pi_js_undefined();
    const initial_body = try scope.get(value, "body");
    var text = if (c.JS_IsString(initial_body)) try scope.invoke(try scope.get(value, "body"), "trim", &.{}) else c.pi_js_undefined();
    if (c.JS_IsUndefined(status)) return scope.get(value, "message");
    if (scope.truthy(text) and try v.length(scope, text) > 4000) {
        const count = try binary(scope, .subtract, try scope.get(text, "length"), c.JS_NewInt32(scope.engine.context, 4000));
        text = try scope.concat(try scope.invoke(text, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 4000) }), try scope.text("... [truncated "));
        text = try scope.concat(try scope.concat(text, try scope.stringify(count)), try scope.text(" chars]"));
    }
    const prefix = try scope.concat(try scope.concat(try scope.text("Mistral API error ("), try scope.stringify(status)), try scope.text("): "));
    return scope.concat(prefix, if (scope.truthy(text)) text else try scope.get(value, "message"));
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue, aborted: bool, kind: Kind) !void {
    const output = try scope.get(owner, "output");
    var blocks = try v.iterator(scope, try scope.get(output, "content"));
    defer blocks.deinit();
    errdefer blocks.closePreserving();
    while (try blocks.next()) |block| {
        defer scope.engine.freeValue(block);
        try v.remove(scope, block, if (kind == .mistral) "partialArgs" else "index");
    }
    const stop = try scope.text(if (aborted) "aborted" else "error");
    try scope.set(output, "stopReason", stop);
    try scope.set(output, "errorMessage", try formatError(scope, reason, kind));
    try emit(scope, owner, "error", null, "reason", stop);
    _ = try scope.invoke(try scope.get(owner, "stream"), "end", &.{});
    try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
}
fn finish(scope: *Scope, owner: c.JSValue, aborted: bool, kind: Kind) !void {
    try close(scope, owner);
    if (kind == .mistral) {
        var rows = try v.iterator(scope, try scope.invoke(try scope.get(owner, "tools"), "values", &.{}));
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |index| {
            defer scope.engine.freeValue(index);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            const block = try row.own(try v.js.getKey(scope.engine, try row.get(try row.get(owner, "output"), "content"), index));
            if (!try v.eq(&row, try row.get(block, "type"), "toolCall")) continue;
            const parsed = try row.invoke(try row.get(owner, "json"), "parseToolCallArguments", &.{try row.get(block, "partialArgs")});
            _ = try row.invoke(try row.global("Object"), "assign", &.{ block, parsed });
            try v.remove(&row, block, "partialArgs");
            try emitAt(&row, owner, "toolcall_end", index, "toolCall", block);
        }
    }
    const output = try scope.get(owner, "output");
    const stop = try scope.get(output, "stopReason");
    var message = c.pi_js_undefined();
    if (aborted) message = try scope.text("Request was aborted") else if (try v.eq(scope, stop, "pending")) message = try scope.text(if (kind == .google) "Google stream ended without a finish reason" else if (kind == .vertex) "Google Vertex stream ended without a finish reason" else "Mistral stream ended without a finish reason") else if (try v.eq(scope, stop, "error") or try v.eq(scope, stop, "aborted")) {
        message = try scope.get(output, "errorMessage");
        if (!scope.truthy(message)) {
            const raw = try scope.get(output, "rawStopReason");
            message = if (kind != .mistral and scope.truthy(raw)) try scope.concat(try scope.text("Provider stopped with: "), raw) else try scope.text("An unknown error occurred");
        }
    }
    if (!c.JS_IsUndefined(message)) return fail(scope, owner, try scope.own(try v.js.builtin(scope.engine, "Error", &.{message})), aborted, kind);
    try emit(scope, owner, "done", null, "reason", stop);
    _ = try scope.invoke(try scope.get(owner, "stream"), "end", &.{});
    try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
}

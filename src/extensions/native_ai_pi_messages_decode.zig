//! Pi's own message-event wire codec; keeps the shared mutable partial value.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;

pub fn emptyUsage(scope: *Scope) !c.JSValue {
    const usage = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |key| try scope.put(usage, key, c.JS_NewInt32(scope.engine.context, 0));
    const cost = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try scope.put(cost, key, c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(usage, "cost", cost);
    return usage;
}
pub fn message(scope: *Scope, model: c.JSValue, reason: []const u8) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "role", try scope.text("assistant"));
    try scope.put(result, "content", try scope.array());
    inline for (.{ "api", "provider" }) |key| try scope.put(result, key, try scope.get(model, key));
    try scope.put(result, "model", try scope.get(model, "id"));
    try scope.put(result, "usage", try emptyUsage(scope));
    try scope.put(result, "stopReason", try scope.text(reason));
    try scope.put(result, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    return result;
}
pub fn initialize(scope: *Scope, owner: c.JSValue, model: c.JSValue) !void {
    try scope.put(owner, "partial", try message(scope, model, "pending"));
    try scope.put(owner, "toolJson", try scope.own(try v.js.builtin(scope.engine, "Map", &.{})));
}
fn assign(scope: *Scope, target: c.JSValue, source: c.JSValue) !void {
    _ = try scope.invoke(try scope.global("Object"), "assign", &.{ target, source });
}
pub fn appendDiagnostic(scope: *Scope, target: c.JSValue, diagnostic: c.JSValue) !void {
    const items = try scope.array();
    const previous = try scope.get(target, "diagnostics");
    if (!v.nullish(previous)) {
        var iterator = try v.iterator(scope, previous);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |item| {
            defer scope.engine.freeValue(item);
            _ = try scope.invoke(items, "push", &.{item});
        }
    }
    _ = try scope.invoke(items, "push", &.{diagnostic});
    try scope.set(target, "diagnostics", items);
}
pub fn convert(scope: *Scope, owner: c.JSValue, event: c.JSValue) !c.JSValue {
    const partial = try scope.get(owner, "partial");
    const kind = try scope.get(event, "type");
    const terminal = try v.eq(scope, kind, "done") or try v.eq(scope, kind, "error");
    if (terminal) {
        const failure = try v.eq(scope, kind, "error");
        const fields = try scope.object();
        try scope.put(fields, "stopReason", try scope.get(event, "reason"));
        try scope.put(fields, "usage", try scope.get(event, "usage"));
        if (failure) try scope.put(fields, "errorMessage", try scope.get(event, "errorMessage"));
        try scope.put(fields, "responseId", try scope.get(event, "responseId"));
        try assign(scope, partial, fields);
        const level = try scope.get(event, "providerThinkingLevel");
        if (!c.JS_IsUndefined(level)) try scope.set(partial, "providerThinkingLevel", level);
        const rewrite = try scope.get(event, "rewrite");
        if (scope.truthy(rewrite)) {
            const diagnostic = try scope.object();
            try scope.put(diagnostic, "type", try scope.text("pi_messages_rewrite"));
            try scope.put(diagnostic, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
            try scope.put(diagnostic, "details", try v.spread(scope, rewrite));
            try appendDiagnostic(scope, partial, diagnostic);
        }
        const output = try scope.object();
        try scope.put(output, "type", kind);
        try scope.put(output, "reason", try scope.get(event, "reason"));
        try scope.put(output, if (failure) "error" else "message", partial);
        return output;
    }
    const index = try scope.get(event, "contentIndex");
    const content = try scope.get(partial, "content");
    const tools = try scope.get(owner, "toolJson");
    if (try v.eq(scope, kind, "text_start") or try v.eq(scope, kind, "thinking_start") or try v.eq(scope, kind, "toolcall_start")) {
        const block = try scope.object();
        if (try v.eq(scope, kind, "toolcall_start")) {
            try scope.put(block, "type", try scope.text("toolCall"));
            try scope.put(block, "id", try scope.get(event, "id"));
            try scope.put(block, "name", try scope.get(event, "toolName"));
            try scope.put(block, "arguments", try scope.object());
            try v.js.setKey(scope.engine, content, index, block);
            _ = try scope.invoke(tools, "set", &.{ index, try scope.text("") });
        } else {
            const thinking = try v.eq(scope, kind, "thinking_start");
            try scope.put(block, "type", try scope.text(if (thinking) "thinking" else "text"));
            try scope.put(block, if (thinking) "thinking" else "text", try scope.text(""));
            try v.js.setKey(scope.engine, content, index, block);
        }
    } else if (try v.eq(scope, kind, "text_delta") or try v.eq(scope, kind, "thinking_delta")) {
        const block = try scope.own(try v.js.getKey(scope.engine, content, index));
        const key: [*:0]const u8 = if (try v.eq(scope, kind, "thinking_delta")) "thinking" else "text";
        try scope.set(block, key, try scope.concat(try scope.get(block, key), try scope.get(event, "delta")));
    } else if (try v.eq(scope, kind, "text_end") or try v.eq(scope, kind, "thinking_end")) {
        const thinking = try v.eq(scope, kind, "thinking_end");
        const block = try scope.own(try v.js.getKey(scope.engine, content, index));
        const fields = try scope.object();
        try scope.put(fields, if (thinking) "thinking" else "text", try scope.get(event, "content"));
        try scope.put(fields, if (thinking) "thinkingSignature" else "textSignature", try scope.get(event, "contentSignature"));
        if (thinking) try scope.put(fields, "redacted", try scope.get(event, "redacted"));
        try assign(scope, block, fields);
    } else if (try v.eq(scope, kind, "toolcall_delta")) {
        const previous = try scope.invoke(tools, "get", &.{index});
        const json = try scope.concat(try scope.stringify(if (v.nullish(previous)) try scope.text("") else previous), try scope.stringify(try scope.get(event, "delta")));
        _ = try scope.invoke(tools, "set", &.{ index, json });
        const block = try scope.own(try v.js.getKey(scope.engine, content, index));
        const helper = try scope.get(try scope.get(owner, "agent"), "json");
        try scope.set(block, "arguments", try scope.invoke(helper, "parseStreamingJson", &.{json}));
    } else if (try v.eq(scope, kind, "toolcall_end")) {
        const block = try scope.own(try v.js.getKey(scope.engine, content, index));
        try assign(scope, block, try scope.get(event, "toolCall"));
        _ = try scope.invoke(tools, "delete", &.{index});
        const output = try scope.object();
        try scope.put(output, "type", try scope.text("toolcall_end"));
        try scope.put(output, "contentIndex", index);
        try scope.put(output, "toolCall", block);
        try scope.put(output, "partial", partial);
        return output;
    }
    const output = try v.spread(scope, event);
    try scope.put(output, "partial", partial);
    return output;
}

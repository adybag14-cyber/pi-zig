//! Google/Vertex transcript conversion over live guest values, source5ab7fe7.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const typed = @import("../ai/google.zig");
pub fn family(scope: *Scope, model: c.JSValue) !struct { ids: bool, multimodal: bool, strict: bool } {
    const id = try scope.engine.toString(try scope.get(model, "id"));
    defer scope.engine.gpa.free(id);
    return .{ .ids = typed.requiresToolCallId(id), .multimodal = typed.supportsMultimodalFunctionResponse(id), .strict = std.ascii.startsWithIgnoreCase(id, "gemini-") and typed.requiresToolCallId(id) };
}
fn normalize(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = if (args.len > 0) args[0] else c.pi_js_undefined();
    if (!(try family(&scope, roots[0])).ids) return c.JS_DupValue(engine.context, id);
    const regex = try scope.own(try v.js.builtin(engine, "RegExp", &.{ try scope.text("[^a-zA-Z0-9_-]"), try scope.text("g") }));
    return v.js.invoke(engine, try scope.invoke(id, "replace", &.{ regex, try scope.text("_") }), "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 64) });
}
fn text(scope: *Scope, value: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "text", try v.sanitize(scope, value));
    return result;
}
fn image(scope: *Scope, value: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const data = try scope.object();
    inline for (.{ "mimeType", "data" }) |key| try scope.put(data, key, try scope.get(value, key));
    try scope.put(result, "inlineData", data);
    return result;
}
fn signature(scope: *Scope, value: c.JSValue) !bool {
    if (!c.JS_IsString(value) or try v.length(scope, value) == 0 or try v.length(scope, value) % 4 != 0) return false;
    const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("^[A-Za-z0-9+/]+={0,2}$")}));
    return scope.truthy(try scope.invoke(regex, "test", &.{value}));
}
fn turn(scope: *Scope, contents: c.JSValue, role: []const u8, parts: c.JSValue) !void {
    const result = try scope.object();
    try scope.put(result, "role", try scope.text(role));
    try scope.put(result, "parts", parts);
    _ = try scope.invoke(contents, "push", &.{result});
}
pub fn convert(engine: *v.em.Engine, model: c.JSValue, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const normalized = try scope.own(try @import("native_ai_provider_transcript.zig").resolve(engine, context, false));
    const conversation = try scope.own(try @import("native_sdk_transcript_replay.zig").conversation(engine, try scope.get(normalized, "messages")));
    const normalizer = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, normalize, &.{model}));
    const messages = try scope.own(try @import("native_ai_transform_messages.zig").transform(engine, conversation, model, normalizer));
    const result = try scope.array();
    const features = try family(&scope, model);
    const supports_images = scope.truthy(try scope.invoke(try scope.get(model, "input"), "includes", &.{try scope.text("image")}));
    var rows = try v.iterator(&scope, messages);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer engine.freeValue(message);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const role = try row.get(message, "role");
        const content = try row.get(message, "content");
        const parts = try row.array();
        if (try v.eq(&row, role, "user")) {
            if (c.JS_IsString(content)) {
                _ = try row.invoke(parts, "push", &.{try text(&row, content)});
            } else {
                var blocks = try v.iterator(&row, content);
                defer blocks.deinit();
                errdefer blocks.closePreserving();
                while (try blocks.next()) |block| {
                    defer engine.freeValue(block);
                    _ = try row.invoke(parts, "push", &.{if (try v.eq(&row, try row.get(block, "type"), "text")) try text(&row, try row.get(block, "text")) else try image(&row, block)});
                }
            }
            if (try v.length(&row, parts) > 0) try turn(&row, result, "user", parts);
        } else if (try v.eq(&row, role, "assistant")) {
            const same = row.equal(try row.get(message, "provider"), try row.get(model, "provider")) and row.equal(try row.get(message, "model"), try row.get(model, "id"));
            var blocks = try v.iterator(&row, content);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            while (try blocks.next()) |block| {
                defer engine.freeValue(block);
                var item: Scope = .{ .engine = engine };
                defer item.deinit();
                const kind = try item.get(block, "type");
                const part = try item.object();
                if (try v.eq(&item, kind, "text") or try v.eq(&item, kind, "thinking")) {
                    const thinking = try v.eq(&item, kind, "thinking");
                    const value = try item.get(block, if (thinking) "thinking" else "text");
                    const sig = try item.get(block, if (thinking) "thinkingSignature" else "textSignature");
                    const signed = same and try signature(&item, sig);
                    if ((!item.truthy(value) or try v.length(&item, try item.invoke(value, "trim", &.{})) == 0) and !signed) continue;
                    if (thinking and same) try item.put(part, "thought", c.pi_js_bool(engine.context, 1));
                    try item.put(part, "text", try v.sanitize(&item, value));
                    if (signed) try item.put(part, "thoughtSignature", sig);
                } else if (try v.eq(&item, kind, "toolCall")) {
                    const call = try item.object();
                    try item.put(call, "name", try item.get(block, "name"));
                    const arguments = try item.get(block, "arguments");
                    try item.put(call, "args", if (v.nullish(arguments)) try item.object() else arguments);
                    if (features.ids) try item.put(call, "id", try item.get(block, "id"));
                    try item.put(part, "functionCall", call);
                    const sig = try item.get(block, "thoughtSignature");
                    if (same and try signature(&item, sig)) try item.put(part, "thoughtSignature", sig);
                } else continue;
                _ = try item.invoke(parts, "push", &.{part});
            }
            if (try v.length(&row, parts) > 0) try turn(&row, result, "model", parts);
        } else if (try v.eq(&row, role, "toolResult")) {
            const texts = try row.array();
            const images = try row.array();
            var blocks = try v.iterator(&row, content);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            while (try blocks.next()) |block| {
                defer engine.freeValue(block);
                if (try v.eq(&row, try row.get(block, "type"), "text")) _ = try row.invoke(texts, "push", &.{try row.get(block, "text")}) else if (supports_images and try v.eq(&row, try row.get(block, "type"), "image")) _ = try row.invoke(images, "push", &.{try image(&row, block)});
            }
            const text_result = try row.invoke(texts, "join", &.{try row.text("\n")});
            const has_images = try v.length(&row, images) > 0;
            const response = try row.object();
            try row.put(response, if (row.truthy(try row.get(message, "isError"))) "error" else "output", if (try v.length(&row, text_result) > 0) try v.sanitize(&row, text_result) else try row.text(if (has_images) "(see attached image)" else ""));
            const call = try row.object();
            try row.put(call, "name", try row.get(message, "toolName"));
            try row.put(call, "response", response);
            if (has_images and features.multimodal) try row.put(call, "parts", images);
            if (features.ids) try row.put(call, "id", try row.get(message, "toolCallId"));
            const part = try row.object();
            try row.put(part, "functionResponse", call);
            const count = try v.length(&row, result);
            const last = if (count > 0) try v.at(&row, result, count - 1) else c.pi_js_undefined();
            var merge = false;
            if (!v.nullish(last) and try v.eq(&row, try row.get(last, "role"), "user")) {
                var previous = try v.iterator(&row, try row.get(last, "parts"));
                defer previous.deinit();
                errdefer previous.closePreserving();
                while (try previous.next()) |old| {
                    defer engine.freeValue(old);
                    if (row.truthy(try row.get(old, "functionResponse"))) merge = true;
                }
            }
            if (merge) _ = try row.invoke(try row.get(last, "parts"), "push", &.{part}) else {
                _ = try row.invoke(parts, "push", &.{part});
                try turn(&row, result, "user", parts);
            }
            if (has_images and !features.multimodal) {
                const legacy = try row.array();
                _ = try row.invoke(legacy, "push", &.{try text(&row, try row.text("Tool result image:"))});
                try turn(&row, result, "user", try row.invoke(legacy, "concat", &.{images}));
            }
        }
    }
    return c.JS_DupValue(engine.context, result);
}

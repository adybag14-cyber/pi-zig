//! Source5ab Anthropic message conversion over owner-local QuickJS values.
//! Keeps transcript block order, opaque signatures and error-image siblings.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn canonicalName(scope: *Scope, name: c.JSValue) !c.JSValue {
    const lower = try scope.invoke(name, "toLowerCase", &.{});
    inline for (.{ "Read", "Write", "Edit", "Bash", "Grep", "Glob", "AskUserQuestion", "EnterPlanMode", "ExitPlanMode", "KillShell", "NotebookEdit", "Skill", "Task", "TaskOutput", "TodoWrite", "WebFetch", "WebSearch" }) |candidate| {
        if (scope.equal(lower, try scope.invoke(try scope.text(candidate), "toLowerCase", &.{}))) return scope.text(candidate);
    }
    return name;
}
pub fn image(scope: *Scope, input: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("image"));
    const source = try scope.object();
    try scope.put(source, "type", try scope.text("base64"));
    try scope.put(source, "media_type", try scope.get(input, "mimeType"));
    try scope.put(source, "data", try scope.get(input, "data"));
    try scope.put(result, "source", source);
    return result;
}
pub fn text(scope: *Scope, input: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("text"));
    try scope.put(result, "text", try v.sanitize(scope, input));
    return result;
}
pub fn content(scope: *Scope, input: c.JSValue) !c.JSValue {
    // Tool-result text-only content is a joined string. Images retain block order.
    const parts = try scope.array();
    const texts = try scope.array();
    var has_image = false;
    var has_text = false;
    var rows = try v.iterator(scope, input);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |part| {
        defer scope.engine.freeValue(part);
        if (try v.eq(scope, try scope.get(part, "type"), "image")) {
            has_image = true;
            _ = try scope.invoke(parts, "push", &.{try image(scope, part)});
        } else {
            has_text = true;
            const value = try scope.get(part, "text");
            _ = try scope.invoke(texts, "push", &.{value});
            _ = try scope.invoke(parts, "push", &.{try text(scope, value)});
        }
    }
    if (!has_image) return v.sanitize(scope, try scope.invoke(texts, "join", &.{try scope.text("\n")}));
    if (!has_text) _ = try scope.invoke(parts, "unshift", &.{try text(scope, try scope.text("(see attached image)"))});
    return parts;
}
fn message(scope: *Scope, role: []const u8, blocks: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "role", try scope.text(role));
    try scope.put(result, "content", blocks);
    return result;
}
fn append(scope: *Scope, target: c.JSValue, source: c.JSValue) !void {
    var rows = try v.iterator(scope, source);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |value| {
        defer scope.engine.freeValue(value);
        _ = try scope.invoke(target, "push", &.{value});
    }
}
pub fn effort(scope: *Scope, value: c.JSValue) !bool {
    inline for (.{ "low", "medium", "high", "xhigh", "max" }) |level| if (try v.eq(scope, value, level)) return true;
    return false;
}
pub fn convert(engine: *v.em.Engine, messages: c.JSValue, oauth: bool, cache: c.JSValue, allow_empty: bool, managed: c.JSValue, tool_converter: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.array();
    const levels = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    const pending = try scope.array();
    const count = try v.length(&scope, messages);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const msg = try v.at(&row, messages, i);
        const role = try row.get(msg, "role");
        const blocks = try row.array();
        if (try v.eq(&row, role, "system")) {
            // Updates are deferred until the next assistant so tool results remain adjacent.
            const update = try row.own(try @import("native_ai_text.zig").system(engine, msg, true));
            if (try v.length(&row, update) > 0) _ = try row.invoke(blocks, "push", &.{try text(&row, update)});
            if (!c.JS_IsUndefined(tool_converter)) {
                const added = try row.get(msg, "toolsAdded");
                const definitions = try row.call(tool_converter, c.pi_js_undefined(), &.{if (v.nullish(added)) try row.array() else added});
                const redefined = try row.own(try v.js.builtin(engine, "Set", &.{}));
                var adds = try v.iterator(&row, if (v.nullish(added)) try row.array() else added);
                defer adds.deinit();
                errdefer adds.closePreserving();
                while (try adds.next()) |tool| {
                    defer engine.freeValue(tool);
                    _ = try row.invoke(redefined, "add", &.{try row.get(tool, "name")});
                }
                const removed = try row.get(msg, "toolsRemoved");
                var removals = try v.iterator(&row, if (v.nullish(removed)) try row.array() else removed);
                defer removals.deinit();
                errdefer removals.closePreserving();
                while (try removals.next()) |tool| {
                    defer engine.freeValue(tool);
                    const name = try row.get(tool, "name");
                    if (row.truthy(try row.invoke(redefined, "has", &.{name}))) continue;
                    const block = try row.object();
                    try row.put(block, "type", try row.text("tool_removal"));
                    const reference = try row.object();
                    try row.put(reference, "type", try row.text("tool_reference"));
                    try row.put(reference, "name", if (oauth) try canonicalName(&row, name) else name);
                    try row.put(block, "tool", reference);
                    _ = try row.invoke(blocks, "push", &.{block});
                }
                var definitions_iterator = try v.iterator(&row, definitions);
                defer definitions_iterator.deinit();
                errdefer definitions_iterator.closePreserving();
                while (try definitions_iterator.next()) |definition| {
                    defer engine.freeValue(definition);
                    const block = try row.object();
                    try row.put(block, "type", try row.text("tool_addition"));
                    const reference = try row.object();
                    try row.put(reference, "type", try row.text("tool_definition"));
                    try row.put(reference, "definition", definition);
                    try row.put(block, "tool", reference);
                    _ = try row.invoke(blocks, "push", &.{block});
                }
            }
            if (try v.length(&row, blocks) > 0) _ = try row.invoke(pending, "push", &.{try message(&row, "system", blocks)});
        } else if (try v.eq(&row, role, "user")) {
            const input = try row.get(msg, "content");
            if (c.JS_IsString(input)) {
                if (try v.length(&row, try row.invoke(input, "trim", &.{})) > 0) _ = try row.invoke(output, "push", &.{try message(&row, "user", try v.sanitize(&row, input))});
            } else {
                var items = try v.iterator(&row, input);
                defer items.deinit();
                errdefer items.closePreserving();
                while (try items.next()) |part| {
                    defer engine.freeValue(part);
                    if (try v.eq(&row, try row.get(part, "type"), "text")) {
                        const value = try v.sanitize(&row, try row.get(part, "text"));
                        if (try v.length(&row, try row.invoke(value, "trim", &.{})) == 0) continue;
                        _ = try row.invoke(blocks, "push", &.{try text(&row, value)});
                    } else _ = try row.invoke(blocks, "push", &.{try image(&row, part)});
                }
                if (try v.length(&row, blocks) > 0) _ = try row.invoke(output, "push", &.{try message(&row, "user", blocks)});
            }
        } else if (try v.eq(&row, role, "assistant")) {
            try append(&row, output, pending);
            try row.set(pending, "length", c.JS_NewInt32(engine.context, 0));
            var items = try v.iterator(&row, try row.get(msg, "content"));
            defer items.deinit();
            errdefer items.closePreserving();
            while (try items.next()) |part| {
                defer engine.freeValue(part);
                const kind = try row.get(part, "type");
                var block = c.pi_js_undefined();
                if (try v.eq(&row, kind, "text")) {
                    const value = try row.get(part, "text");
                    if (try v.length(&row, try row.invoke(value, "trim", &.{})) == 0) continue;
                    block = try text(&row, value);
                } else if (try v.eq(&row, kind, "thinking")) {
                    block = try row.object();
                    if (row.truthy(try row.get(part, "redacted"))) {
                        try row.put(block, "type", try row.text("redacted_thinking"));
                        try row.put(block, "data", try row.get(part, "thinkingSignature"));
                    } else {
                        const thought = try row.get(part, "thinking");
                        const signature = try row.get(part, "thinkingSignature");
                        const signed = row.truthy(signature) and try v.length(&row, try row.invoke(signature, "trim", &.{})) > 0;
                        if (try v.length(&row, try row.invoke(thought, "trim", &.{})) == 0 and !signed) continue;
                        if (!signed and !allow_empty) block = try text(&row, thought) else {
                            try row.put(block, "type", try row.text("thinking"));
                            try row.put(block, "thinking", try v.sanitize(&row, thought));
                            try row.put(block, "signature", if (signed) signature else try row.text(""));
                        }
                    }
                } else if (try v.eq(&row, kind, "toolCall")) {
                    block = try row.object();
                    try row.put(block, "type", try row.text("tool_use"));
                    try row.put(block, "id", try row.get(part, "id"));
                    const name = try row.get(part, "name");
                    try row.put(block, "name", if (oauth) try canonicalName(&row, name) else name);
                    const arguments = try row.get(part, "arguments");
                    try row.put(block, "input", if (v.nullish(arguments)) try row.object() else arguments);
                }
                if (!c.JS_IsUndefined(block)) _ = try row.invoke(blocks, "push", &.{block});
            }
            if (try v.length(&row, blocks) == 0) continue;
            const index = try row.get(output, "length");
            _ = try row.invoke(output, "push", &.{try message(&row, "assistant", blocks)});
            const level = try row.get(msg, "providerThinkingLevel");
            if (!c.JS_IsUndefined(managed) and try v.eq(&row, try row.get(msg, "api"), "anthropic-messages") and row.equal(try row.get(msg, "provider"), managed) and try effort(&row, level)) _ = try row.invoke(levels, "set", &.{ index, level });
        } else if (try v.eq(&row, role, "toolResult")) {
            const siblings = try row.array();
            var j = i;
            while (j < count) : (j += 1) {
                const tool = try v.at(&row, messages, j);
                if (!try v.eq(&row, try row.get(tool, "role"), "toolResult")) break;
                const split = try row.own(try @import("native_ai_transform_messages.zig").splitErrorImages(engine, tool));
                const block = try row.object();
                try row.put(block, "type", try row.text("tool_result"));
                try row.put(block, "tool_use_id", try row.get(tool, "toolCallId"));
                try row.put(block, "content", try content(&row, try row.get(if (c.JS_IsUndefined(split)) tool else split, "content")));
                try row.put(block, "is_error", try row.get(tool, "isError"));
                _ = try row.invoke(blocks, "push", &.{block});
                if (!c.JS_IsUndefined(split)) {
                    _ = try row.invoke(siblings, "push", &.{try text(&row, try row.get(split, "caption"))});
                    var images = try v.iterator(&row, try row.get(split, "images"));
                    defer images.deinit();
                    errdefer images.closePreserving();
                    while (try images.next()) |value| {
                        defer engine.freeValue(value);
                        _ = try row.invoke(siblings, "push", &.{try image(&row, value)});
                    }
                }
            }
            i = j - 1;
            try append(&row, blocks, siblings);
            _ = try row.invoke(output, "push", &.{try message(&row, "user", blocks)});
        }
    }
    try append(&scope, output, pending);
    if (!c.JS_IsUndefined(cache) and try v.length(&scope, output) > 0) {
        const last = try v.at(&scope, output, try v.length(&scope, output) - 1);
        if (try v.eq(&scope, try scope.get(last, "role"), "user") or try v.eq(&scope, try scope.get(last, "role"), "system")) {
            const value = try scope.get(last, "content");
            if (try v.array(&scope, value)) {
                const length = try v.length(&scope, value);
                if (length > 0) {
                    const block = try v.at(&scope, value, length - 1);
                    const kind = try scope.get(block, "type");
                    if (try v.eq(&scope, kind, "text") or try v.eq(&scope, kind, "image") or try v.eq(&scope, kind, "tool_result") or try v.eq(&scope, kind, "tool_addition") or try v.eq(&scope, kind, "tool_removal")) try scope.set(block, "cache_control", cache);
                }
            } else if (c.JS_IsString(value)) {
                const blocks = try scope.array();
                const block = try text(&scope, value);
                try scope.put(block, "cache_control", cache);
                _ = try scope.invoke(blocks, "push", &.{block});
                try scope.set(last, "content", blocks);
            }
        }
    }
    const result = try scope.object();
    try scope.put(result, "messages", output);
    try scope.put(result, "assistantLevels", levels);
    return c.JS_DupValue(engine.context, result);
}
pub fn insertEffort(scope: *Scope, converted: c.JSValue, active: c.JSValue) !c.JSValue {
    const result = try scope.array();
    const messages = try scope.get(converted, "messages");
    const levels = try scope.get(converted, "assistantLevels");
    var index: u32 = 0;
    while (index < try v.length(scope, messages)) : (index += 1) {
        const historical = try scope.invoke(levels, "get", &.{c.JS_NewUint32(scope.engine.context, index)});
        if (!c.JS_IsUndefined(historical)) _ = try scope.invoke(result, "push", &.{try effortMessage(scope, historical)});
        _ = try scope.invoke(result, "push", &.{try v.at(scope, messages, index)});
    }
    _ = try scope.invoke(result, "push", &.{try effortMessage(scope, active)});
    return result;
}
fn effortMessage(scope: *Scope, level: c.JSValue) !c.JSValue {
    const result = try message(scope, "system", try scope.array());
    const config = try scope.object();
    try scope.put(config, "effort", level);
    try scope.put(result, "output_config", config);
    return result;
}

//! Source5ab AWS Converse transcript codec, with actual blob/Document JS values.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn bytes(scope: *Scope, base64: c.JSValue) !c.JSValue {
    const binary = try scope.call(try scope.global("atob"), c.pi_js_undefined(), &.{base64});
    const count = try v.length(scope, binary);
    const result = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{c.JS_NewUint32(scope.engine.context, count)}));
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const value = try scope.invoke(binary, "charCodeAt", &.{c.JS_NewUint32(scope.engine.context, i)});
        if (c.JS_SetPropertyUint32(scope.engine.context, result, i, c.JS_DupValue(scope.engine.context, value)) < 0) return v.js.capture(scope.engine);
    }
    return result;
}
pub fn image(scope: *Scope, input: c.JSValue) !c.JSValue {
    const mime = try scope.get(input, "mimeType");
    var format: ?[]const u8 = null;
    inline for (.{ .{ "image/jpeg", "jpeg" }, .{ "image/jpg", "jpeg" }, .{ "image/png", "png" }, .{ "image/gif", "gif" }, .{ "image/webp", "webp" } }) |pair| if (try v.eq(scope, mime, pair[0])) {
        format = pair[1];
    };
    if (format == null) return v.errorText(scope, try scope.concat(try scope.text("Unknown image type: "), try scope.stringify(mime)));
    const result = try scope.object();
    const descriptor = try scope.object();
    const source = try scope.object();
    try scope.put(source, "bytes", try bytes(scope, try scope.get(input, "data")));
    try scope.put(descriptor, "source", source);
    try scope.put(descriptor, "format", try scope.text(format.?));
    try scope.put(result, "image", descriptor);
    return result;
}
pub fn text(scope: *Scope, input: c.JSValue, required: bool) !c.JSValue {
    const value = try v.sanitize(scope, input);
    const blank = try v.length(scope, try scope.invoke(value, "trim", &.{})) == 0;
    if (blank and !required) return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "text", if (blank) try scope.text("<empty>") else value);
    return result;
}
pub fn document(scope: *Scope, input: c.JSValue) anyerror!c.JSValue {
    if (try v.array(scope, input)) {
        const output = try scope.array();
        var rows = try v.iterator(scope, input);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer scope.engine.freeValue(entry);
            _ = try scope.invoke(output, "push", &.{try document(scope, entry)});
        }
        return output;
    }
    if (!c.JS_IsNull(input) and c.JS_IsObject(input) and !c.JS_IsFunction(scope.engine.context, input)) {
        const output = try scope.object();
        var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{input}));
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const key = try v.at(scope, entry, 0);
            if (try v.length(scope, key) == 0) continue;
            try v.js.setKey(scope.engine, output, key, try document(scope, try v.at(scope, entry, 1)));
        }
        return output;
    }
    return input;
}
fn message(scope: *Scope, role: []const u8, content: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "role", try scope.text(role));
    try scope.put(result, "content", content);
    return result;
}
pub fn cachePoint(scope: *Scope, retention: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const point = try scope.object();
    try scope.put(point, "type", try scope.text("default"));
    if (try v.eq(scope, retention, "long")) try scope.put(point, "ttl", try scope.text("1h"));
    try scope.put(result, "cachePoint", point);
    return result;
}
fn media(scope: *Scope, input: c.JSValue) !c.JSValue {
    const result = try scope.array();
    var rows = try v.iterator(scope, input);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |part| {
        defer scope.engine.freeValue(part);
        const block = if (try v.eq(scope, try scope.get(part, "type"), "image")) try image(scope, part) else try text(scope, try scope.get(part, "text"), false);
        if (!c.JS_IsUndefined(block)) _ = try scope.invoke(result, "push", &.{block});
    }
    if (try v.length(scope, result) == 0) _ = try scope.invoke(result, "push", &.{try text(scope, try scope.text(""), true)});
    return result;
}
pub fn convert(engine: *v.em.Engine, context: c.JSValue, model: c.JSValue, retention: c.JSValue, caching: bool, claude: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const original = try scope.get(context, "messages");
    const first = if (try v.length(&scope, original) > 0) try v.at(&scope, original, 0) else c.pi_js_undefined();
    const conversation = if (!c.JS_IsUndefined(first) and try v.eq(&scope, try scope.get(first, "role"), "system")) try scope.invoke(original, "slice", &.{c.JS_NewInt32(engine.context, 1)}) else original;
    const messages = try scope.own(try @import("native_ai_transform_messages.zig").transform(engine, conversation, model, try scope.own(try @import("native_ai_provider_request.zig").normalizeId(engine))));
    const result = try scope.array();
    const count = try v.length(&scope, messages);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const msg = try v.at(&row, messages, i);
        const role = try row.get(msg, "role");
        const blocks = try row.array();
        if (try v.eq(&row, role, "user")) {
            const input = try row.get(msg, "content");
            if (c.JS_IsString(input)) _ = try row.invoke(blocks, "push", &.{try text(&row, input, true)}) else {
                var rows = try v.iterator(&row, input);
                defer rows.deinit();
                errdefer rows.closePreserving();
                while (try rows.next()) |part| {
                    defer engine.freeValue(part);
                    const kind = try row.get(part, "type");
                    const block = if (try v.eq(&row, kind, "text")) try text(&row, try row.get(part, "text"), false) else if (try v.eq(&row, kind, "image")) try image(&row, part) else c.pi_js_undefined();
                    if (!c.JS_IsUndefined(block)) _ = try row.invoke(blocks, "push", &.{block});
                }
                if (try v.length(&row, blocks) == 0) _ = try row.invoke(blocks, "push", &.{try text(&row, try row.text(""), true)});
            }
            _ = try row.invoke(result, "push", &.{try message(&row, "user", blocks)});
        } else if (try v.eq(&row, role, "assistant")) {
            const input = try row.get(msg, "content");
            if (try v.length(&row, input) == 0) continue;
            var rows = try v.iterator(&row, input);
            defer rows.deinit();
            errdefer rows.closePreserving();
            while (try rows.next()) |part| {
                defer engine.freeValue(part);
                const kind = try row.get(part, "type");
                var block = c.pi_js_undefined();
                if (try v.eq(&row, kind, "text")) block = try text(&row, try row.get(part, "text"), false) else if (try v.eq(&row, kind, "toolCall")) {
                    block = try row.object();
                    const tool = try row.object();
                    try row.put(tool, "toolUseId", try row.get(part, "id"));
                    try row.put(tool, "name", try row.get(part, "name"));
                    try row.put(tool, "input", try document(&row, try row.get(part, "arguments")));
                    try row.put(block, "toolUse", tool);
                } else if (try v.eq(&row, kind, "thinking")) {
                    const signature = try row.get(part, "thinkingSignature");
                    if (row.truthy(try row.get(part, "redacted"))) {
                        if (!row.truthy(signature)) continue;
                        const generation = engine.native_allocation_generation;
                        const decoded = bytes(&row, signature) catch |err| {
                            try @import("native_ai_partial_json.zig").discard(engine, err, generation);
                            continue;
                        };
                        if (try v.length(&row, decoded) == 0) continue;
                        block = try row.object();
                        const reasoning = try row.object();
                        try row.put(reasoning, "redactedContent", decoded);
                        try row.put(block, "reasoningContent", reasoning);
                    } else {
                        const thought = try v.sanitize(&row, try row.get(part, "thinking"));
                        if (try v.length(&row, try row.invoke(thought, "trim", &.{})) == 0) continue;
                        if (claude and (!row.truthy(signature) or try v.length(&row, try row.invoke(signature, "trim", &.{})) == 0)) block = try text(&row, thought, false) else {
                            block = try row.object();
                            const reasoning = try row.object();
                            const reasoning_text = try row.object();
                            try row.put(reasoning_text, "text", thought);
                            if (claude) try row.put(reasoning_text, "signature", signature);
                            try row.put(reasoning, "reasoningText", reasoning_text);
                            try row.put(block, "reasoningContent", reasoning);
                        }
                    }
                }
                if (!c.JS_IsUndefined(block)) _ = try row.invoke(blocks, "push", &.{block});
            }
            if (try v.length(&row, blocks) > 0) _ = try row.invoke(result, "push", &.{try message(&row, "assistant", blocks)});
        } else if (try v.eq(&row, role, "toolResult")) {
            const siblings = try row.array();
            var j = i;
            while (j < count) : (j += 1) {
                const tool_msg = try v.at(&row, messages, j);
                if (!try v.eq(&row, try row.get(tool_msg, "role"), "toolResult")) break;
                const split = if (claude) try row.own(try @import("native_ai_transform_messages.zig").splitErrorImages(engine, tool_msg)) else c.pi_js_undefined();
                const block = try row.object();
                const tool = try row.object();
                try row.put(tool, "toolUseId", try row.get(tool_msg, "toolCallId"));
                try row.put(tool, "content", try media(&row, try row.get(if (c.JS_IsUndefined(split)) tool_msg else split, "content")));
                try row.put(tool, "status", try row.text(if (row.truthy(try row.get(tool_msg, "isError"))) "error" else "success"));
                try row.put(block, "toolResult", tool);
                _ = try row.invoke(blocks, "push", &.{block});
                if (!c.JS_IsUndefined(split)) {
                    _ = try row.invoke(siblings, "push", &.{try text(&row, try row.get(split, "caption"), true)});
                    var images = try v.iterator(&row, try row.get(split, "images"));
                    defer images.deinit();
                    errdefer images.closePreserving();
                    while (try images.next()) |part| {
                        defer engine.freeValue(part);
                        _ = try row.invoke(siblings, "push", &.{try image(&row, part)});
                    }
                }
            }
            i = j - 1;
            var images = try v.iterator(&row, siblings);
            defer images.deinit();
            errdefer images.closePreserving();
            while (try images.next()) |part| {
                defer engine.freeValue(part);
                _ = try row.invoke(blocks, "push", &.{part});
            }
            _ = try row.invoke(result, "push", &.{try message(&row, "user", blocks)});
        }
    }
    if (!try v.eq(&scope, retention, "none") and caching and try v.length(&scope, result) > 0) {
        const last = try v.at(&scope, result, try v.length(&scope, result) - 1);
        if (try v.eq(&scope, try scope.get(last, "role"), "user") and scope.truthy(try scope.get(last, "content"))) _ = try scope.invoke(try scope.get(last, "content"), "push", &.{try cachePoint(&scope, retention)});
    }
    return c.JS_DupValue(engine.context, result);
}

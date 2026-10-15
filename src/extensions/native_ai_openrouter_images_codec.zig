//! OpenRouter image request/output codec. This is not a chat stream adapter.
const v = @import("native_ai_provider_values.zig");
const shared = @import("native_ai_classifier_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn build(scope: *Scope, model: c.JSValue, context: c.JSValue) !c.JSValue {
    const Mapper = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const item = if (args.len > 0) args[0] else c.pi_js_undefined();
            const part = try row.object();
            if (try v.eq(&row, try row.get(item, "type"), "text")) {
                try row.put(part, "type", try row.text("text"));
                try row.put(part, "text", try v.sanitize(&row, try row.get(item, "text")));
            } else {
                try row.put(part, "type", try row.text("image_url"));
                const image = try row.object();
                var url = try row.concat(try row.text("data:"), try row.stringify(try row.get(item, "mimeType")));
                url = try row.concat(try row.concat(url, try row.text(";base64,")), try row.stringify(try row.get(item, "data")));
                try row.put(image, "url", url);
                try row.put(part, "image_url", image);
            }
            return c.JS_DupValue(host.context, part);
        }
    };
    const mapper = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Mapper.call, &.{}));
    const content = try scope.invoke(try scope.get(context, "input"), "map", &.{mapper});
    const payload = try scope.object();
    try scope.put(payload, "model", try scope.get(model, "id"));
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("user"));
    try scope.put(message, "content", content);
    const messages = try scope.array();
    try scope.index(messages, 0, message);
    try scope.put(payload, "messages", messages);
    try scope.put(payload, "stream", c.pi_js_bool(scope.engine.context, 0));
    const modalities = try scope.array();
    try scope.index(modalities, 0, try scope.text("image"));
    if (scope.truthy(try scope.invoke(try scope.get(model, "output"), "includes", &.{try scope.text("text")}))) try scope.index(modalities, 1, try scope.text("text"));
    try scope.put(payload, "modalities", modalities);
    return payload;
}
fn orZero(scope: *Scope, value: c.JSValue) c.JSValue {
    return if (scope.truthy(value)) value else c.JS_NewInt32(scope.engine.context, 0);
}
fn usage(scope: *Scope, raw: c.JSValue, model: c.JSValue) !c.JSValue {
    const prompt = orZero(scope, try scope.get(raw, "prompt_tokens"));
    const cached = orZero(scope, try v.optional(scope, try scope.get(raw, "prompt_tokens_details"), "cached_tokens"));
    const write = orZero(scope, try v.optional(scope, try scope.get(raw, "prompt_tokens_details"), "cache_write_tokens"));
    const read = if (try @import("native_image_arithmetic.zig").compare(scope.engine, .greater, write, c.JS_NewInt32(scope.engine.context, 0))) try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), try shared.binary(scope, .subtract, cached, write) }) else cached;
    const input = try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), try shared.binary(scope, .subtract, try shared.binary(scope, .subtract, prompt, read), write) });
    const output = orZero(scope, try scope.get(raw, "completion_tokens"));
    const result = try scope.object();
    try scope.put(result, "input", input);
    try scope.put(result, "output", output);
    try scope.put(result, "cacheRead", read);
    try scope.put(result, "cacheWrite", write);
    try scope.put(result, "totalTokens", try shared.binary(scope, .add, try shared.binary(scope, .add, try shared.binary(scope, .add, input, output), read), write));
    const cost = try scope.object();
    inline for (.{ .{ "input", input }, .{ "output", output }, .{ "cacheRead", read }, .{ "cacheWrite", write } }) |pair| try scope.put(cost, pair[0], try shared.binary(scope, .multiply, try shared.binary(scope, .divide, try scope.get(try scope.get(model, "cost"), pair[0]), c.JS_NewInt32(scope.engine.context, 1000000)), pair[1]));
    try scope.put(cost, "total", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(result, "cost", cost);
    var total = try scope.get(cost, "input");
    inline for (.{ "output", "cacheRead", "cacheWrite" }) |key| total = try shared.binary(scope, .add, total, try scope.get(cost, key));
    try scope.set(cost, "total", total);
    return result;
}
pub fn decode(scope: *Scope, output: c.JSValue, response: c.JSValue, model: c.JSValue) !void {
    try scope.set(output, "responseId", try scope.get(response, "id"));
    if (scope.truthy(try scope.get(response, "usage"))) try scope.set(output, "usage", try usage(scope, try scope.get(response, "usage"), model));
    const choice = try v.at(scope, try scope.get(response, "choices"), 0);
    if (!scope.truthy(choice)) return;
    const content = try scope.get(try scope.get(choice, "message"), "content");
    const blocks = try scope.get(output, "output");
    if (c.JS_IsString(content) and try v.length(scope, content) > 0) {
        const text = try scope.object();
        try scope.put(text, "type", try scope.text("text"));
        try scope.put(text, "text", content);
        _ = try scope.invoke(blocks, "push", &.{text});
    }
    const images = try scope.get(try scope.get(choice, "message"), "images");
    var iterator = try v.iterator(scope, if (v.nullish(images)) try scope.array() else images);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |image| {
        defer scope.engine.freeValue(image);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const image_url = try row.get(image, "image_url");
        const url = if (c.JS_IsString(image_url)) try row.get(image, "image_url") else try v.optional(&row, try row.get(image, "image_url"), "url");
        if (v.nullish(url) or !row.truthy(try row.invoke(url, "startsWith", &.{try row.text("data:")}))) continue;
        const regex = try row.own(try v.js.builtin(scope.engine, "RegExp", &.{try row.text("^data:([^;]+);base64,(.+)$")}));
        const matches = try row.invoke(url, "match", &.{regex});
        if (!row.truthy(matches)) continue;
        const block = try row.object();
        try row.put(block, "type", try row.text("image"));
        try row.put(block, "mimeType", try v.at(&row, matches, 1));
        try row.put(block, "data", try v.at(&row, matches, 2));
        _ = try row.invoke(blocks, "push", &.{block});
    }
}

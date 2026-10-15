//! Actual shared provider message transformation, including latest5ab image split.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const Kind = enum { normalize, downgrade, message, content, tool, image };
fn function(scope: *Scope, comptime kind: Kind, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return callback(&row, kind, if (args.len > 0) args[0] else c.pi_js_undefined(), data);
        }
    };
    return scope.own(try @import("native_node_function.zig").create(scope.engine, "", 1, Adapter.call, roots));
}
fn callback(scope: *Scope, kind: Kind, value: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = scope.engine;
    switch (kind) {
        .normalize => {
            if (!v.nullish(try scope.get(value, "content"))) return c.JS_DupValue(engine.context, value);
            const result = try v.spread(scope, value);
            try scope.put(result, "content", try scope.array());
            return c.JS_DupValue(engine.context, result);
        },
        .tool, .image => return c.pi_js_bool(engine.context, @intFromBool(try v.eq(scope, try scope.get(value, "type"), if (kind == .tool) "toolCall" else "image"))),
        .downgrade => {
            const role = try scope.get(value, "role");
            const user = try v.eq(scope, role, "user");
            if (!(user and try v.array(scope, try scope.get(value, "content"))) and !try v.eq(scope, role, "toolResult")) return c.JS_DupValue(engine.context, value);
            const result = try v.spread(scope, value);
            try scope.put(result, "content", try replaceImages(scope, try scope.get(value, "content"), if (user) "(image omitted: model does not support images)" else "(tool image omitted: model does not support images)"));
            return c.JS_DupValue(engine.context, result);
        },
        .message => {
            const role = try scope.get(value, "role");
            if (try v.eq(scope, role, "system") or try v.eq(scope, role, "user")) return c.JS_DupValue(engine.context, value);
            if (try v.eq(scope, role, "toolResult")) {
                const id = try scope.invoke(roots[1], "get", &.{try scope.get(value, "toolCallId")});
                if (scope.truthy(id) and !scope.equal(id, try scope.get(value, "toolCallId"))) {
                    const result = try v.spread(scope, value);
                    try scope.put(result, "toolCallId", id);
                    return c.JS_DupValue(engine.context, result);
                }
                return c.JS_DupValue(engine.context, value);
            }
            if (!try v.eq(scope, role, "assistant")) return c.JS_DupValue(engine.context, value);
            const same = scope.equal(try scope.get(value, "provider"), try scope.get(roots[0], "provider")) and scope.equal(try scope.get(value, "api"), try scope.get(roots[0], "api")) and scope.equal(try scope.get(value, "model"), try scope.get(roots[0], "id"));
            const mapped = try scope.invoke(try scope.get(value, "content"), "flatMap", &.{try function(scope, .content, &.{ roots[0], roots[1], roots[2], value, c.pi_js_bool(engine.context, @intFromBool(same)) })});
            const result = try v.spread(scope, value);
            try scope.put(result, "content", mapped);
            return c.JS_DupValue(engine.context, result);
        },
        .content => {
            const same = scope.truthy(roots[4]);
            const kind_value = try scope.get(value, "type");
            if (try v.eq(scope, kind_value, "thinking")) {
                if (scope.truthy(try scope.get(value, "redacted"))) return c.JS_DupValue(engine.context, if (same) value else try scope.array());
                if (same and scope.truthy(try scope.get(value, "thinkingSignature"))) return c.JS_DupValue(engine.context, value);
                if (!scope.truthy(try scope.get(value, "thinking")) or try v.eq(scope, try scope.invoke(try scope.get(value, "thinking"), "trim", &.{}), "")) return v.js.array(engine);
                if (same) return c.JS_DupValue(engine.context, value);
                const result = try scope.object();
                try scope.put(result, "type", try scope.text("text"));
                try scope.put(result, "text", try scope.get(value, "thinking"));
                return c.JS_DupValue(engine.context, result);
            }
            if (try v.eq(scope, kind_value, "text")) {
                if (same) return c.JS_DupValue(engine.context, value);
                const result = try scope.object();
                try scope.put(result, "type", try scope.text("text"));
                try scope.put(result, "text", try scope.get(value, "text"));
                return c.JS_DupValue(engine.context, result);
            }
            if (try v.eq(scope, kind_value, "toolCall")) {
                var result = value;
                if (!same and scope.truthy(try scope.get(value, "thoughtSignature"))) {
                    result = try v.spread(scope, value);
                    try v.remove(scope, result, "thoughtSignature");
                }
                if (!same and scope.truthy(roots[2])) {
                    const id = try scope.call(roots[2], c.pi_js_undefined(), &.{ try scope.get(value, "id"), roots[0], roots[3] });
                    if (!scope.equal(id, try scope.get(value, "id"))) {
                        _ = try scope.invoke(roots[1], "set", &.{ try scope.get(value, "id"), id });
                        result = try v.spread(scope, result);
                        try scope.put(result, "id", id);
                    }
                }
                return c.JS_DupValue(engine.context, result);
            }
            return c.JS_DupValue(engine.context, value);
        },
    }
}
fn replaceImages(scope: *Scope, content: c.JSValue, placeholder: []const u8) !c.JSValue {
    const result = try scope.array();
    var previous = false;
    var rows = try v.iterator(scope, content);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |block| {
        defer scope.engine.freeValue(block);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        if (try v.eq(&row, try row.get(block, "type"), "image")) {
            if (!previous) {
                const note = try row.object();
                try row.put(note, "type", try row.text("text"));
                try row.put(note, "text", try row.text(placeholder));
                _ = try row.invoke(result, "push", &.{note});
            }
            previous = true;
        } else {
            _ = try row.invoke(result, "push", &.{block});
            previous = try v.eq(&row, try row.get(block, "text"), placeholder);
        }
    }
    return result;
}
pub fn splitErrorImages(engine: *v.em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(message, "isError"))) return c.pi_js_undefined();
    const images = try scope.invoke(try scope.get(message, "content"), "filter", &.{try function(&scope, .image, &.{})});
    if (try v.length(&scope, images) == 0) return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "content", try replaceImages(&scope, try scope.get(message, "content"), "(image attached after the tool results)"));
    var caption = try scope.concat(try scope.text("Images from the error result of tool call "), try scope.stringify(try scope.get(message, "toolCallId")));
    caption = try scope.concat(caption, try scope.text(" ("));
    caption = try scope.concat(caption, try scope.stringify(try scope.get(message, "toolName")));
    try scope.put(result, "caption", try scope.concat(caption, try scope.text("):")));
    try scope.put(result, "images", images);
    return c.JS_DupValue(engine.context, result);
}
fn close(scope: *Scope, state: c.JSValue) !void {
    const pending = try scope.get(state, "pending");
    const result = try scope.get(state, "result");
    if (try v.length(scope, pending) > 0) {
        var rows = try v.iterator(scope, pending);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |tool| {
            defer scope.engine.freeValue(tool);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            if (row.truthy(try row.invoke(try row.get(state, "existing"), "has", &.{try row.get(tool, "id")}))) continue;
            const message = try row.object();
            try row.put(message, "role", try row.text("toolResult"));
            try row.put(message, "toolCallId", try row.get(tool, "id"));
            try row.put(message, "toolName", try row.get(tool, "name"));
            const content = try row.array();
            const text = try row.object();
            try row.put(text, "type", try row.text("text"));
            try row.put(text, "text", try row.text("No result provided"));
            _ = try row.invoke(content, "push", &.{text});
            try row.put(message, "content", content);
            try row.put(message, "isError", c.pi_js_bool(scope.engine.context, 1));
            try row.put(message, "timestamp", try row.invoke(try row.global("Date"), "now", &.{}));
            _ = try row.invoke(result, "push", &.{message});
        }
        try scope.put(state, "pending", try scope.array());
        try scope.put(state, "existing", try scope.own(try v.js.builtin(scope.engine, "Set", &.{})));
    }
    const held = try scope.get(state, "held");
    var rows = try v.iterator(scope, held);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer scope.engine.freeValue(message);
        _ = try scope.invoke(result, "push", &.{message});
    }
    try scope.set(held, "length", c.JS_NewInt32(scope.engine.context, 0));
}
pub fn transform(engine: *v.em.Engine, messages: c.JSValue, model: c.JSValue, normalize: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const map = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    const normalized = try scope.invoke(messages, "map", &.{try function(&scope, .normalize, &.{})});
    const image_aware = if (scope.truthy(try scope.invoke(try scope.get(model, "input"), "includes", &.{try scope.text("image")}))) normalized else try scope.invoke(normalized, "map", &.{try function(&scope, .downgrade, &.{})});
    const transformed = try scope.invoke(image_aware, "map", &.{try function(&scope, .message, &.{ model, map, normalize })});
    const state = try scope.object();
    inline for (.{ "result", "pending", "held" }) |key| try scope.put(state, key, try scope.array());
    try scope.put(state, "existing", try scope.own(try v.js.builtin(engine, "Set", &.{})));
    var index: u32 = 0;
    while (index < try v.length(&scope, transformed)) : (index += 1) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const message = try v.at(&row, transformed, index);
        const role = try row.get(message, "role");
        const result = try row.get(state, "result");
        if (try v.eq(&row, role, "assistant")) {
            try close(&row, state);
            const reason = try row.get(message, "stopReason");
            if (try v.eq(&row, reason, "error") or try v.eq(&row, reason, "aborted")) continue;
            const calls = try row.invoke(try row.get(message, "content"), "filter", &.{try function(&row, .tool, &.{})});
            if (try v.length(&row, calls) > 0) {
                try row.put(state, "pending", calls);
                try row.put(state, "existing", try row.own(try v.js.builtin(engine, "Set", &.{})));
            }
            _ = try row.invoke(result, "push", &.{message});
        } else if (try v.eq(&row, role, "toolResult")) {
            _ = try row.invoke(try row.get(state, "existing"), "add", &.{try row.get(message, "toolCallId")});
            _ = try row.invoke(result, "push", &.{message});
        } else if (try v.eq(&row, role, "system")) {
            _ = try row.invoke(if (try v.length(&row, try row.get(state, "pending")) > 0) try row.get(state, "held") else result, "push", &.{message});
        } else {
            if (try v.eq(&row, role, "user")) try close(&row, state);
            _ = try row.invoke(result, "push", &.{message});
        }
    }
    try close(&scope, state);
    return c.JS_DupValue(engine.context, try scope.get(state, "result"));
}

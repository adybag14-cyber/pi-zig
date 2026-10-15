//! Actual Decisions request conversion, refusal checks and named answer map.
const v = @import("native_ai_provider_values.zig");
const shared = @import("native_ai_classifier_values.zig");
const Scope = v.Scope;
const c = v.c;
const label = "OpenAI Decisions";
pub fn build(scope: *Scope, model: c.JSValue, context: c.JSValue) !c.JSValue {
    const model_id = try scope.get(model, "id");
    const state = try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(context, "state")});
    const raw_images = try scope.get(context, "images");
    const images = if (v.nullish(raw_images)) try scope.array() else raw_images;
    const count = try v.length(scope, images);
    var input = state;
    if (count != 0) {
        if (count > 128) return v.errorText(scope, try scope.concat(try scope.text("OpenAI Decisions accepts at most 128 images, got "), try scope.stringify(try scope.get(images, "length"))));
        const content = try scope.array();
        const text = try scope.object();
        try scope.put(text, "type", try scope.text("input_text"));
        try scope.put(text, "text", state);
        _ = try scope.invoke(content, "push", &.{text});
        var iterator = try v.iterator(scope, images);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |image| {
            defer scope.engine.freeValue(image);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            const part = try row.object();
            try row.put(part, "type", try row.text("input_image"));
            const url = try row.concat(try row.concat(try row.concat(try row.text("data:"), try row.stringify(try row.get(image, "mimeType"))), try row.text(";base64,")), try row.stringify(try row.get(image, "data")));
            try row.put(part, "image_url", url);
            _ = try row.invoke(content, "push", &.{part});
        }
        const message = try scope.object();
        try scope.put(message, "role", try scope.text("user"));
        try scope.put(message, "content", content);
        input = try scope.array();
        try scope.index(input, 0, message);
    }
    const questions = try scope.array();
    var iterator = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(context, "questions")}));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const question = try v.at(&row, entry, 1);
        const wire = try row.object();
        const choice = try v.eq(&row, try row.get(question, "type"), "choice");
        const score = !choice and try v.eq(&row, try row.get(question, "type"), "score");
        try row.put(wire, "type", try row.text(if (choice) "choice" else if (score) "score" else "predicate"));
        try row.put(wire, "name", try v.at(&row, entry, 0));
        if (choice or score) {
            try row.put(wire, "instructions", try row.get(question, "instructions"));
            const criteria = try row.get(question, "criteria");
            const list = try row.array();
            var levels = try v.iterator(&row, if (choice) try row.invoke(try row.global("Object"), "entries", &.{criteria}) else criteria);
            defer levels.deinit();
            errdefer levels.closePreserving();
            while (try levels.next()) |level| {
                defer scope.engine.freeValue(level);
                var level_scope: Scope = .{ .engine = scope.engine };
                defer level_scope.deinit();
                const part = try level_scope.object();
                if (choice) {
                    try level_scope.put(part, "value", try v.at(&level_scope, level, 0));
                    const description = try v.at(&level_scope, level, 1);
                    if (level_scope.truthy(description)) try level_scope.put(part, "description", description);
                } else try level_scope.put(part, "label", level);
                _ = try level_scope.invoke(list, "push", &.{part});
            }
            try row.put(wire, if (choice) "choices" else "levels", list);
        } else {
            const meanings = try row.array();
            inline for (.{ .{ "true", "True means: " }, .{ "false", "False means: " } }) |pair| {
                const criteria = try row.get(question, "criteria");
                if (row.truthy(try row.get(criteria, pair[0]))) _ = try row.invoke(meanings, "push", &.{try row.concat(try row.text(pair[1]), try row.stringify(try row.get(try row.get(question, "criteria"), pair[0])))});
            }
            const instructions = try row.get(question, "instructions");
            try row.put(wire, "instructions", if (try v.length(&row, meanings) > 0) try row.concat(try row.concat(try row.stringify(instructions), try row.text("\n\n")), try row.invoke(meanings, "join", &.{try row.text("\n")})) else instructions);
        }
        _ = try row.invoke(questions, "push", &.{wire});
    }
    const result = try scope.object();
    try scope.put(result, "model", model_id);
    try scope.put(result, "input", input);
    try scope.put(result, "questions", questions);
    return result;
}
pub fn answers(scope: *Scope, value: c.JSValue, context: c.JSValue) !c.JSValue {
    if (!try v.array(scope, value)) return v.errorText(scope, try scope.text("OpenAI Decisions returned an unexpected response"));
    const by_name = try scope.own(try v.js.builtin(scope.engine, "Map", &.{}));
    var source = try v.iterator(scope, value);
    defer source.deinit();
    errdefer source.closePreserving();
    while (try source.next()) |item| {
        defer scope.engine.freeValue(item);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        if (try shared.record(&row, item) and c.JS_IsString(try row.get(item, "name"))) _ = try row.invoke(by_name, "set", &.{ try row.get(item, "name"), item });
    }
    const result = try scope.object();
    var questions = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(context, "questions")}));
    defer questions.deinit();
    errdefer questions.closePreserving();
    while (try questions.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const id = try v.at(&row, entry, 0);
        const question = try v.at(&row, entry, 1);
        const answer = try row.invoke(by_name, "get", &.{id});
        if (!row.truthy(answer)) return v.errorText(&row, try row.concat(try row.text("OpenAI Decisions did not return an answer for "), try row.stringify(id)));
        if (try v.eq(&row, try row.get(answer, "type"), "refusal")) return v.errorText(&row, try row.concat(try row.text("OpenAI Decisions refused to answer "), try row.stringify(id)));
        const parsed = try row.object();
        const choice = try v.eq(&row, try row.get(question, "type"), "choice");
        const score = !choice and try v.eq(&row, try row.get(question, "type"), "score");
        if (choice) {
            if (!try v.eq(&row, try row.get(answer, "type"), "choice") or !c.JS_IsString(try row.get(answer, "choice"))) return v.errorText(&row, try row.concat(try row.text("OpenAI Decisions did not return a choice answer for "), try row.stringify(id)));
            try row.put(parsed, "type", try row.text("choice"));
            try row.put(parsed, "choice", try row.get(answer, "choice"));
            const values = try row.get(answer, "probabilities");
            if (!try v.array(&row, values)) return v.errorText(&row, try row.concat(try row.text("OpenAI Decisions returned invalid probabilities for "), try row.stringify(id)));
            const probabilities = try row.object();
            var entries = try v.iterator(&row, values);
            defer entries.deinit();
            errdefer entries.closePreserving();
            while (try entries.next()) |probability| {
                defer scope.engine.freeValue(probability);
                var part: Scope = .{ .engine = scope.engine };
                defer part.deinit();
                if (!try shared.record(&part, probability) or !c.JS_IsString(try part.get(probability, "value"))) return v.errorText(&part, try part.concat(try part.text("OpenAI Decisions returned invalid probabilities for "), try part.stringify(id)));
                const key = try part.get(probability, "value");
                const field = try part.concat(try part.concat(try part.concat(try part.text("probability for "), try part.stringify(id)), try part.text(".")), try part.stringify(try part.get(probability, "value")));
                try shared.define(&part, probabilities, key, try shared.required(&part, try part.text(label), try part.get(probability, "probability"), field));
            }
            try row.put(parsed, "probabilities", probabilities);
        } else if (score) {
            if (!try v.eq(&row, try row.get(answer, "type"), "score")) return v.errorText(&row, try row.concat(try row.text("OpenAI Decisions did not return a score answer for "), try row.stringify(id)));
            try row.put(parsed, "type", try row.text("score"));
            try row.put(parsed, "score", try shared.required(&row, try row.text(label), try row.get(answer, "score"), try row.concat(try row.text("score for "), try row.stringify(id))));
        } else {
            if (!try v.eq(&row, try row.get(answer, "type"), "predicate")) return v.errorText(&row, try row.concat(try row.text("OpenAI Decisions did not return a predicate answer for "), try row.stringify(id)));
            try row.put(parsed, "type", try row.text("bool"));
            try row.put(parsed, "probability", try shared.required(&row, try row.text(label), try row.get(answer, "probability"), try row.concat(try row.text("probability for "), try row.stringify(id))));
        }
        if (choice or score) try row.put(parsed, "confidence", try shared.required(&row, try row.text(label), try row.get(answer, "confidence"), try row.concat(try row.text("confidence for "), try row.stringify(id))));
        try shared.define(&row, result, id, parsed);
    }
    return result;
}

//! System One wire values, response envelopes and billed malformed answers.
const v = @import("native_ai_provider_values.zig");
const shared = @import("native_ai_classifier_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn payload(scope: *Scope, model: c.JSValue, context: c.JSValue, cloudflare: bool) !c.JSValue {
    const questions = try scope.object();
    var iterator = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(context, "questions")}));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const question = try v.at(&row, entry, 1);
        var value = question;
        if (try v.eq(&row, try row.get(question, "type"), "bool")) {
            value = try v.spread(&row, question);
            try row.put(value, "type", try row.text("noul"));
        }
        try shared.define(&row, questions, try v.at(&row, entry, 0), value);
    }
    const request = try scope.object();
    try scope.put(request, "state", try scope.get(context, "state"));
    try scope.put(request, "questions", questions);
    const result = try scope.object();
    try scope.put(result, "model", try scope.get(model, "id"));
    if (cloudflare) try scope.put(result, "input", request) else try v.js.spreadInto(scope.engine, result, request);
    return result;
}
fn unexpected(scope: *Scope, label: c.JSValue) anyerror {
    return v.errorText(scope, scope.concat(scope.stringify(label) catch |err| return err, scope.text(" returned an unexpected response") catch |err| return err) catch |err| return err);
}
pub fn unwrap(scope: *Scope, body: c.JSValue, label: c.JSValue, cloudflare: bool) !c.JSValue {
    if (!try shared.record(scope, body)) return unexpected(scope, label);
    if (!cloudflare) return body;
    if (scope.equal(try scope.get(body, "success"), c.pi_js_bool(scope.engine.context, 0))) {
        const errors = try scope.get(body, "errors");
        if (try v.array(scope, errors)) {
            const messages = try scope.array();
            var iterator = try v.iterator(scope, errors);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |entry| {
                defer scope.engine.freeValue(entry);
                var row: Scope = .{ .engine = scope.engine };
                defer row.deinit();
                if (!try shared.record(&row, entry)) continue;
                const message = try row.get(entry, "message");
                if (c.JS_IsString(message)) _ = try row.invoke(messages, "push", &.{message});
            }
            if (try v.length(scope, messages) > 0) return v.errorText(scope, try scope.concat(try scope.concat(try scope.stringify(label), try scope.text(" error: ")), try scope.invoke(messages, "join", &.{try scope.text("; ")})));
        }
        return v.errorText(scope, try scope.concat(try scope.stringify(label), try scope.text(" request failed")));
    }
    const result = try scope.get(body, "result");
    if (!try shared.record(scope, result)) return unexpected(scope, label);
    if (try v.js.hasKey(scope.engine, result, try scope.text("answers"))) return result;
    if (!try v.eq(scope, try scope.get(result, "state"), "Completed")) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.stringify(label), try scope.text(" run did not complete (state: ")), try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{try scope.get(result, "state")})), try scope.text(")")));
    const nested = try scope.get(result, "result");
    if (!try shared.record(scope, nested)) return unexpected(scope, label);
    return nested;
}
pub fn answers(scope: *Scope, label: c.JSValue, value: c.JSValue, context: c.JSValue) !c.JSValue {
    if (!try shared.record(scope, value)) return unexpected(scope, label);
    const output = try scope.object();
    var iterator = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{try scope.get(context, "questions")}));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const id = try v.at(&row, entry, 0);
        const question = try v.at(&row, entry, 1);
        const answer = try row.own(try v.js.getKey(scope.engine, value, id));
        const lead = try row.concat(try row.stringify(label), try row.text(" did not return an answer for "));
        if (!try shared.record(&row, answer)) return v.errorText(&row, try row.concat(lead, try row.stringify(id)));
        const parsed = try row.object();
        var with_confidence = true;
        if (try v.eq(&row, try row.get(question, "type"), "choice")) {
            if (!try v.eq(&row, try row.get(answer, "type"), "choice") or !c.JS_IsString(try row.get(answer, "choice"))) return v.errorText(&row, try row.concat(try row.concat(try row.stringify(label), try row.text(" did not return a choice answer for ")), try row.stringify(id)));
            try row.put(parsed, "type", try row.text("choice"));
            try row.put(parsed, "choice", try row.get(answer, "choice"));
            const probabilities = try row.get(answer, "probabilities");
            if (!try shared.record(&row, probabilities)) return v.errorText(&row, try row.concat(try row.concat(try row.stringify(label), try row.text(" returned invalid probabilities for ")), try row.stringify(id)));
            const normalized = try row.object();
            var entries = try v.iterator(&row, try row.invoke(try row.global("Object"), "entries", &.{probabilities}));
            defer entries.deinit();
            errdefer entries.closePreserving();
            while (try entries.next()) |pair| {
                defer scope.engine.freeValue(pair);
                var probability_scope: Scope = .{ .engine = scope.engine };
                defer probability_scope.deinit();
                const key = try v.at(&probability_scope, pair, 0);
                const field = try probability_scope.concat(try probability_scope.concat(try probability_scope.concat(try probability_scope.text("probability for "), try probability_scope.stringify(id)), try probability_scope.text(".")), try probability_scope.stringify(key));
                try shared.define(&probability_scope, normalized, key, try shared.required(&probability_scope, label, try v.at(&probability_scope, pair, 1), field));
            }
            try row.put(parsed, "probabilities", normalized);
        } else if (try v.eq(&row, try row.get(question, "type"), "score")) {
            if (!try v.eq(&row, try row.get(answer, "type"), "score")) return v.errorText(&row, try row.concat(try row.concat(try row.stringify(label), try row.text(" did not return a score answer for ")), try row.stringify(id)));
            try row.put(parsed, "type", try row.text("score"));
            try row.put(parsed, "score", try shared.required(&row, label, try row.get(answer, "score"), try row.concat(try row.text("score for "), try row.stringify(id))));
        } else {
            with_confidence = false;
            if (!try v.eq(&row, try row.get(answer, "type"), "noul")) return v.errorText(&row, try row.concat(try row.concat(try row.stringify(label), try row.text(" did not return a bool answer for ")), try row.stringify(id)));
            try row.put(parsed, "type", try row.text("bool"));
            try row.put(parsed, "probability", try shared.required(&row, label, try row.get(answer, "noul"), try row.concat(try row.text("probability for "), try row.stringify(id))));
        }
        if (with_confidence) try row.put(parsed, "confidence", try shared.required(&row, label, try row.get(answer, "confidence"), try row.concat(try row.text("confidence for "), try row.stringify(id))));
        try shared.define(&row, output, id, parsed);
    }
    return output;
}

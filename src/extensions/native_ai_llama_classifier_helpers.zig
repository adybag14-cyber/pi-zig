//! Actual llama.cpp classifier exports over live VM values and collections.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const shared = @import("native_ai_classifier_values.zig");
const Scope = v.Scope;
const c = v.c;
const Method = enum { llamaServerRoot, renderQuestion, labelProbabilities, peakConfidence, answerFromProbabilities };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const labels = try scope.array();
    try scope.index(labels, 0, try scope.text("Yes"));
    try scope.index(labels, 1, try scope.text("No"));
    const result = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(args.len, values.len)], 0..) |value, index| values[index] = value;
                const output = switch (@as(Method, @enumFromInt(field.value))) {
                    .llamaServerRoot => try root(&row, values[0]),
                    .renderQuestion => try render(&row, roots[0], values[0], values[1]),
                    .labelProbabilities => try probabilities(&row, values[0], values[1]),
                    .peakConfidence => try confidence(&row, values[0]),
                    .answerFromProbabilities => try answer(&row, values[0], values[1], values[2]),
                };
                return c.JS_DupValue(host.context, output);
            }
        };
        try scope.put(result, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, switch (@as(Method, @enumFromInt(field.value))) {
            .llamaServerRoot, .peakConfidence => 1,
            .renderQuestion, .labelProbabilities => 2,
            .answerFromProbabilities => 3,
        }, Adapter.call, &.{labels})));
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn root(scope: *Scope, base: c.JSValue) !c.JSValue {
    const trailing = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("/+$"), try scope.text("u") }));
    const suffix = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("/v1$"), try scope.text("u") }));
    return scope.invoke(try scope.invoke(base, "replace", &.{ trailing, try scope.text("") }), "replace", &.{ suffix, try scope.text("") });
}
fn labeled(scope: *Scope, question: c.JSValue, booleans: c.JSValue) !struct { labels: c.JSValue, keys: c.JSValue } {
    const choice = try v.eq(scope, try scope.get(question, "type"), "choice");
    if (choice or try v.eq(scope, try scope.get(question, "type"), "score")) {
        const criteria = try scope.get(question, "criteria");
        const keys = if (choice) try scope.invoke(try scope.global("Object"), "keys", &.{criteria}) else criteria;
        const length = try v.length(scope, keys);
        const max: u32 = if (choice) 62 else 10;
        if (length < 2 or length > max) {
            const lead = try scope.text(if (choice) "A choice question needs 2 to 62 options, got " else "A score question needs 2 to 10 levels, got ");
            return v.errorText(scope, try scope.concat(lead, try scope.stringify(try scope.get(keys, "length"))));
        }
        const labels = try scope.array();
        const alphabet = if (choice) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" else "0123456789";
        for (alphabet[0..length], 0..) |_, index| try scope.index(labels, @intCast(index), try scope.text(alphabet[index .. index + 1]));
        return .{ .labels = labels, .keys = if (choice) keys else labels };
    }
    const keys = try scope.array();
    try scope.index(keys, 0, try scope.text("true"));
    try scope.index(keys, 1, try scope.text("false"));
    return .{ .labels = booleans, .keys = keys };
}
fn task(scope: *Scope, question: c.JSValue, labels: c.JSValue) !c.JSValue {
    const head = try scope.concat(try scope.text("Question: "), try scope.stringify(try scope.get(question, "instructions")));
    const choice = try v.eq(scope, try scope.get(question, "type"), "choice");
    if (choice or try v.eq(scope, try scope.get(question, "type"), "score")) {
        const criteria = try scope.get(question, "criteria");
        const source = if (choice) try scope.invoke(try scope.global("Object"), "entries", &.{criteria}) else criteria;
        const Mapper = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                const entry = if (args.len > 0) args[0] else c.pi_js_undefined();
                const index = if (args.len > 1) args[1] else c.pi_js_undefined();
                var output: c.JSValue = undefined;
                if (row.truthy(roots[1])) {
                    const description = try v.at(&row, entry, 1);
                    const option = try row.concat(try row.stringify(try v.at(&row, entry, 0)), if (row.truthy(description)) try row.concat(try row.text(": "), try row.stringify(description)) else try row.text(""));
                    output = if (row.truthy(roots[0])) try row.concat(try row.concat(try row.stringify(try row.own(try v.js.getKey(host, roots[0], index))), try row.text(". ")), option) else try row.concat(try row.text("- "), option);
                } else output = try row.concat(try row.concat(try row.stringify(index), try row.text(". ")), try row.stringify(entry));
                return c.JS_DupValue(host.context, output);
            }
        };
        const render_line = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 2, Mapper.call, &.{ labels, c.pi_js_bool(scope.engine.context, @intFromBool(choice)) }));
        const lines = try scope.invoke(source, "map", &.{render_line});
        return scope.concat(try scope.concat(head, try scope.text(if (choice) "\n\nOptions:\n" else "\n\nLevels:\n")), try scope.invoke(lines, "join", &.{try scope.text("\n")}));
    }
    const criteria = try scope.get(question, "criteria");
    const meanings = try scope.array();
    inline for (.{ .{ "true", "Yes means: " }, .{ "false", "No means: " } }) |pair| {
        const value = try scope.get(criteria, pair[0]);
        if (scope.truthy(value)) _ = try scope.invoke(meanings, "push", &.{try scope.concat(try scope.text(pair[1]), try scope.stringify(try scope.get(criteria, pair[0])))});
    }
    return if (try v.length(scope, meanings) > 0) scope.concat(try scope.concat(head, try scope.text("\n\n")), try scope.invoke(meanings, "join", &.{try scope.text("\n")})) else head;
}
pub fn render(scope: *Scope, booleans: c.JSValue, context: c.JSValue, id: c.JSValue) !c.JSValue {
    const question = try scope.own(try v.js.getKey(scope.engine, try scope.get(context, "questions"), id));
    if (!scope.truthy(question)) return v.errorText(scope, try scope.concat(try scope.text("Unknown question: "), try scope.stringify(id)));
    const labels = try labeled(scope, question, booleans);
    const state = try scope.concat(try scope.text("State:\n"), try scope.stringify(try scope.invoke(try scope.global("JSON"), "stringify", &.{ try scope.get(context, "state"), c.pi_js_null(), c.JS_NewInt32(scope.engine.context, 1) })));
    const final_task = try task(scope, question, labels.labels);
    const instruction = try scope.text(if (try v.eq(scope, try scope.get(question, "type"), "choice")) "Answer with one letter." else if (try v.eq(scope, try scope.get(question, "type"), "score")) "Answer with one level number." else "Answer Yes or No.");
    const final = try scope.concat(try scope.concat(final_task, try scope.text("\n\n")), instruction);
    const questions = try scope.invoke(try scope.global("Object"), "values", &.{try scope.get(context, "questions")});
    const overview = try scope.array();
    try scope.index(overview, 0, try scope.text(if (try v.length(scope, questions) == 1) "Task: answer the following question about the state." else "Task: answer each of the following questions about the state."));
    var iterator = try v.iterator(scope, questions);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |item| {
        defer scope.engine.freeValue(item);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        _ = try row.invoke(overview, "push", &.{try task(&row, item, c.pi_js_undefined())});
    }
    const parts = try scope.array();
    try scope.index(parts, 0, state);
    try scope.index(parts, 1, try scope.invoke(overview, "join", &.{try scope.text("\n\n")}));
    try scope.index(parts, 2, state);
    try scope.index(parts, 3, final);
    const output = try scope.object();
    try scope.put(output, "content", try scope.invoke(parts, "join", &.{try scope.text("\n\n")}));
    try scope.put(output, "labels", labels.labels);
    try scope.put(output, "keys", labels.keys);
    return output;
}
fn maximum(scope: *Scope, values: c.JSValue) !c.JSValue {
    var args: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (args.items) |value| scope.engine.freeValue(value);
        args.deinit(scope.engine.gpa);
    }
    var iterator = try v.iterator(scope, values);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        args.append(scope.engine.gpa, value) catch |err| {
            scope.engine.freeValue(value);
            return err;
        };
    }
    return scope.invoke(try scope.global("Math"), "max", args.items);
}
const Mapping = enum { scale, exponent, normalize, sum, score };
fn mapper(scope: *Scope, mode: Mapping, value: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const first = if (args.len > 0) args[0] else c.pi_js_undefined();
            const second = if (args.len > 1) args[1] else c.pi_js_undefined();
            var mode_value: i32 = 0;
            if (c.JS_ToInt32(host.context, &mode_value, roots[0]) < 0) return v.js.capture(host);
            const output = switch (@as(Mapping, @enumFromInt(mode_value))) {
                .scale, .normalize => try shared.binary(&row, .divide, first, roots[1]),
                .exponent => try row.invoke(try row.global("Math"), "exp", &.{try shared.binary(&row, .subtract, first, roots[1])}),
                .sum => try shared.binary(&row, .add, first, second),
                .score => try shared.binary(&row, .add, first, try shared.binary(&row, .multiply, if (args.len > 2) args[2] else c.pi_js_undefined(), second)),
            };
            return c.JS_DupValue(host.context, output);
        }
    };
    return scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", if (mode == .score) 3 else if (mode == .sum) 2 else 1, Adapter.call, &.{ c.JS_NewInt32(scope.engine.context, @intFromEnum(mode)), value }));
}
pub fn probabilities(scope: *Scope, logprobs: c.JSValue, temperature: c.JSValue) !c.JSValue {
    const scaled = try scope.invoke(logprobs, "map", &.{try mapper(scope, .scale, temperature)});
    const weights = try scope.invoke(scaled, "map", &.{try mapper(scope, .exponent, try maximum(scope, scaled))});
    const total = try scope.invoke(weights, "reduce", &.{ try mapper(scope, .sum, c.pi_js_undefined()), c.JS_NewInt32(scope.engine.context, 0) });
    return scope.invoke(weights, "map", &.{try mapper(scope, .normalize, total)});
}
pub fn confidence(scope: *Scope, probabilities_value: c.JSValue) !c.JSValue {
    const n = try scope.get(probabilities_value, "length");
    const peak = try maximum(scope, probabilities_value);
    const numerator = try shared.binary(scope, .subtract, try shared.binary(scope, .multiply, n, peak), c.JS_NewInt32(scope.engine.context, 1));
    const score = try shared.binary(scope, .divide, numerator, try shared.binary(scope, .subtract, n, c.JS_NewInt32(scope.engine.context, 1)));
    return scope.invoke(try scope.global("Math"), "min", &.{ c.JS_NewInt32(scope.engine.context, 1), try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), score }) });
}
pub fn answer(scope: *Scope, question: c.JSValue, keys: c.JSValue, probabilities_value: c.JSValue) !c.JSValue {
    const result = try scope.object();
    if (try v.eq(scope, try scope.get(question, "type"), "bool")) {
        try scope.put(result, "type", try scope.text("bool"));
        try scope.put(result, "probability", try scope.own(try v.js.getKey(scope.engine, probabilities_value, try scope.invoke(keys, "indexOf", &.{try scope.text("true")}))));
        return result;
    }
    const confidence_value = try confidence(scope, probabilities_value);
    if (try v.eq(scope, try scope.get(question, "type"), "score")) {
        const score = try scope.invoke(probabilities_value, "reduce", &.{ try mapper(scope, .score, c.pi_js_undefined()), c.JS_NewInt32(scope.engine.context, 0) });
        try scope.put(result, "type", try scope.text("score"));
        try scope.put(result, "score", score);
        try scope.put(result, "confidence", confidence_value);
        return result;
    }
    var best: u32 = 0;
    var index: u32 = 1;
    while (index < try v.length(scope, probabilities_value)) : (index += 1) {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        if (try @import("native_image_arithmetic.zig").compare(scope.engine, .greater, try v.at(&row, probabilities_value, index), try v.at(&row, probabilities_value, best))) best = index;
    }
    // Source's keys.map preserves holes; use the source mapping method rather
    // than treating a hole as an explicit undefined key.
    const Pair = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const pair = try row.array();
            try row.index(pair, 0, if (args.len > 0) args[0] else c.pi_js_undefined());
            try row.index(pair, 1, try row.own(try v.js.getKey(host, roots[0], if (args.len > 1) args[1] else c.pi_js_undefined())));
            return c.JS_DupValue(host.context, pair);
        }
    };
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 2, Pair.call, &.{probabilities_value}));
    const mapped_probabilities = try scope.invoke(try scope.global("Object"), "fromEntries", &.{try scope.invoke(keys, "map", &.{callback})});
    try scope.put(result, "type", try scope.text("choice"));
    try scope.put(result, "choice", try v.at(scope, keys, best));
    try scope.put(result, "probabilities", mapped_probabilities);
    try scope.put(result, "confidence", confidence_value);
    return result;
}

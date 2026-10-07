//! Pi's OpenAI Decisions classifier payload and answer projection.
const std = @import("std");
const Value = std.json.Value;
// ECMAScript enumerates canonical array-index keys first, in numeric order.
// Preserve the insertion order of all other keys, including "01" and 2^32-1.
fn arrayIndex(key: []const u8) ?u32 {
    if (key.len == 0 or (key.len > 1 and key[0] == '0')) return null;
    for (key) |byte| if (byte < '0' or byte > '9') return null;
    const index = std.fmt.parseInt(u32, key, 10) catch return null;
    return if (index == std.math.maxInt(u32)) null else index;
}
fn jsOrder(a: std.mem.Allocator, value: Value) !Value {
    switch (value) {
        .array => |values| {
            var result: std.array_list.Managed(Value) = .init(a);
            for (values.items) |item| try result.append(try jsOrder(a, item));
            return .{ .array = result };
        },
        .object => |values| {
            const keys = try a.dupe([]const u8, values.keys());
            std.mem.sort([]const u8, keys, {}, struct {
                fn less(_: void, left: []const u8, right: []const u8) bool {
                    const lhs = arrayIndex(left);
                    const rhs = arrayIndex(right);
                    if (lhs) |index| return if (rhs) |other| index < other else true;
                    return false;
                }
            }.less);
            var result: std.json.ObjectMap = .empty;
            // sort is not stable for ordinary keys; insert them from the original map.
            for (keys) |key| if (arrayIndex(key) != null) try result.put(a, key, try jsOrder(a, values.get(key).?));
            var iterator = values.iterator();
            while (iterator.next()) |entry| if (arrayIndex(entry.key_ptr.*) == null) try result.put(a, entry.key_ptr.*, try jsOrder(a, entry.value_ptr.*));
            return .{ .object = result };
        },
        else => return value,
    }
}
fn object(value: Value) !std.json.ObjectMap {
    return if (value == .object) value.object else error.InvalidDecisionsObject;
}
fn field(value: std.json.ObjectMap, name: []const u8) !Value {
    return value.get(name) orelse error.MissingDecisionsField;
}
fn string(value: Value) ![]const u8 {
    return if (value == .string) value.string else error.InvalidDecisionsString;
}
fn finite(value: Value) !Value {
    const number: f64 = switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => return error.InvalidDecisionsNumber,
    };
    if (!std.math.isFinite(number)) return error.InvalidDecisionsNumber;
    return value;
}
fn isFinite(value: ?Value) bool {
    _ = finite(value orelse return false) catch return false;
    return true;
}
fn kindIs(value: std.json.ObjectMap, expected: []const u8) bool {
    const kind = value.get("type") orelse return false;
    return kind == .string and std.mem.eql(u8, kind.string, expected);
}
/// Expected malformed/refused answers retain upstream's user-facing diagnostic.
pub fn answerDiagnostic(a: std.mem.Allocator, output: std.json.ObjectMap, context: std.json.ObjectMap) !?[]const u8 {
    const raw = output.get("answers") orelse return try a.dupe(u8, "OpenAI Decisions returned an unexpected response");
    if (raw != .array) return try a.dupe(u8, "OpenAI Decisions returned an unexpected response");
    var by_name: std.json.ObjectMap = .empty;
    for (raw.array.items) |value| if (value == .object) {
        if (value.object.get("name")) |name| if (name == .string) try by_name.put(a, name.string, value);
    };
    const questions = try object(try field(context, "questions"));
    var iterator = questions.iterator();
    while (iterator.next()) |entry| {
        const id = entry.key_ptr.*;
        const question = try object(entry.value_ptr.*);
        const answer = try object(by_name.get(id) orelse return try std.fmt.allocPrint(a, "OpenAI Decisions did not return an answer for {s}", .{id}));
        if (kindIs(answer, "refusal")) return try std.fmt.allocPrint(a, "OpenAI Decisions refused to answer {s}", .{id});
        const kind = try string(try field(question, "type"));
        if (std.mem.eql(u8, kind, "choice")) {
            const choice = answer.get("choice");
            if (!kindIs(answer, "choice") or choice == null or choice.? != .string) return try std.fmt.allocPrint(a, "OpenAI Decisions did not return a choice answer for {s}", .{id});
            const probabilities = answer.get("probabilities");
            if (probabilities == null or probabilities.? != .array) return try std.fmt.allocPrint(a, "OpenAI Decisions returned invalid probabilities for {s}", .{id});
            for (probabilities.?.array.items) |row| {
                if (row != .object or row.object.get("value") == null or row.object.get("value").? != .string) return try std.fmt.allocPrint(a, "OpenAI Decisions returned invalid probabilities for {s}", .{id});
                if (!isFinite(row.object.get("probability"))) return try std.fmt.allocPrint(a, "OpenAI Decisions returned an invalid probability for {s}.{s}", .{ id, row.object.get("value").?.string });
            }
            if (!isFinite(answer.get("confidence"))) return try std.fmt.allocPrint(a, "OpenAI Decisions returned an invalid confidence for {s}", .{id});
        } else if (std.mem.eql(u8, kind, "score")) {
            if (!kindIs(answer, "score")) return try std.fmt.allocPrint(a, "OpenAI Decisions did not return a score answer for {s}", .{id});
            if (!isFinite(answer.get("score"))) return try std.fmt.allocPrint(a, "OpenAI Decisions returned an invalid score for {s}", .{id});
            if (!isFinite(answer.get("confidence"))) return try std.fmt.allocPrint(a, "OpenAI Decisions returned an invalid confidence for {s}", .{id});
        } else {
            if (!kindIs(answer, "predicate")) return try std.fmt.allocPrint(a, "OpenAI Decisions did not return a predicate answer for {s}", .{id});
            if (!isFinite(answer.get("probability"))) return try std.fmt.allocPrint(a, "OpenAI Decisions returned an invalid probability for {s}", .{id});
        }
    }
    return null;
}
fn put(a: std.mem.Allocator, target: *std.json.ObjectMap, name: []const u8, value: Value) !void {
    try target.put(a, name, value);
}
pub fn payload(gpa: std.mem.Allocator, model: []const u8, raw_context: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const context = try object(try jsOrder(a, try std.json.parseFromSliceLeaky(Value, a, raw_context, .{ .allocate = .alloc_always })));
    const state = try field(context, "state");
    _ = try object(state);
    const state_json = try std.json.Stringify.valueAlloc(a, state, .{});
    var input: Value = .{ .string = state_json };
    if (context.get("images")) |images| {
        if (images != .array) return error.InvalidDecisionsImages;
        if (images.array.items.len > 128) return error.TooManyDecisionsImages;
        if (images.array.items.len > 0) {
            var content: std.array_list.Managed(Value) = .init(a);
            var text: std.json.ObjectMap = .empty;
            try put(a, &text, "type", .{ .string = "input_text" });
            try put(a, &text, "text", .{ .string = state_json });
            try content.append(.{ .object = text });
            for (images.array.items) |image| {
                const record = try object(image);
                const mime = try string(try field(record, "mimeType"));
                const data = try string(try field(record, "data"));
                var item: std.json.ObjectMap = .empty;
                try put(a, &item, "type", .{ .string = "input_image" });
                try put(a, &item, "image_url", .{ .string = try std.fmt.allocPrint(a, "data:{s};base64,{s}", .{ mime, data }) });
                try content.append(.{ .object = item });
            }
            var message: std.json.ObjectMap = .empty;
            try put(a, &message, "role", .{ .string = "user" });
            try put(a, &message, "content", .{ .array = content });
            var messages: std.array_list.Managed(Value) = .init(a);
            try messages.append(.{ .object = message });
            input = .{ .array = messages };
        }
    }
    const questions = try object(try field(context, "questions"));
    var wire: std.array_list.Managed(Value) = .init(a);
    var iterator = questions.iterator();
    while (iterator.next()) |entry| {
        const question = try object(entry.value_ptr.*);
        const kind = try string(try field(question, "type"));
        const instructions = try string(try field(question, "instructions"));
        var item: std.json.ObjectMap = .empty;
        try put(a, &item, "type", .{ .string = if (std.mem.eql(u8, kind, "bool")) "predicate" else kind });
        try put(a, &item, "name", .{ .string = entry.key_ptr.* });
        try put(a, &item, "instructions", .{ .string = instructions });
        if (std.mem.eql(u8, kind, "choice")) {
            const criteria = try object(try field(question, "criteria"));
            var choices: std.array_list.Managed(Value) = .init(a);
            var names = criteria.iterator();
            while (names.next()) |choice| {
                var value: std.json.ObjectMap = .empty;
                try put(a, &value, "value", .{ .string = choice.key_ptr.* });
                const description = try string(choice.value_ptr.*);
                if (description.len > 0) try put(a, &value, "description", .{ .string = description });
                try choices.append(.{ .object = value });
            }
            try put(a, &item, "choices", .{ .array = choices });
        } else if (std.mem.eql(u8, kind, "score")) {
            const criteria = try field(question, "criteria");
            if (criteria != .array) return error.InvalidDecisionsLevels;
            var levels: std.array_list.Managed(Value) = .init(a);
            for (criteria.array.items) |label| {
                _ = try string(label);
                var level: std.json.ObjectMap = .empty;
                try put(a, &level, "label", label);
                try levels.append(.{ .object = level });
            }
            try put(a, &item, "levels", .{ .array = levels });
        } else if (std.mem.eql(u8, kind, "bool")) {
            const criteria = try object(try field(question, "criteria"));
            var meanings: std.ArrayList(u8) = .empty;
            for ([_][]const u8{ "true", "false" }, [_][]const u8{ "True", "False" }) |key, label| {
                if (criteria.get(key)) |meaning| {
                    const text = try string(meaning);
                    if (text.len > 0) {
                        if (meanings.items.len > 0) try meanings.append(a, '\n');
                        try meanings.appendSlice(a, label);
                        try meanings.appendSlice(a, " means: ");
                        try meanings.appendSlice(a, text);
                    }
                }
            }
            if (meanings.items.len > 0) try put(a, &item, "instructions", .{ .string = try std.fmt.allocPrint(a, "{s}\n\n{s}", .{ instructions, meanings.items }) });
        } else return error.InvalidDecisionsQuestion;
        try wire.append(.{ .object = item });
    }
    var body: std.json.ObjectMap = .empty;
    try put(a, &body, "model", .{ .string = model });
    try put(a, &body, "input", input);
    try put(a, &body, "questions", .{ .array = wire });
    return std.json.Stringify.valueAlloc(gpa, Value{ .object = body }, .{});
}

pub fn answers(a: std.mem.Allocator, output: std.json.ObjectMap, context: std.json.ObjectMap) !std.json.ObjectMap {
    const raw = try field(output, "answers");
    if (raw != .array) return error.InvalidDecisionsResponse;
    var by_name: std.json.ObjectMap = .empty;
    for (raw.array.items) |value| {
        if (value == .object) if (value.object.get("name")) |name| {
            if (name == .string) try by_name.put(a, name.string, value);
        };
    }
    const questions = try object(try field(context, "questions"));
    var result: std.json.ObjectMap = .empty;
    var iterator = questions.iterator();
    while (iterator.next()) |entry| {
        const question = try object(entry.value_ptr.*);
        const answer = try object(by_name.get(entry.key_ptr.*) orelse return error.MissingDecisionsAnswer);
        const kind = try string(try field(question, "type"));
        const answer_kind = try string(try field(answer, "type"));
        if (std.mem.eql(u8, answer_kind, "refusal")) return error.DecisionsRefusal;
        var projected: std.json.ObjectMap = .empty;
        try put(a, &projected, "type", .{ .string = kind });
        if (std.mem.eql(u8, kind, "choice")) {
            if (!std.mem.eql(u8, answer_kind, "choice")) return error.InvalidDecisionsChoice;
            const choice = try field(answer, "choice");
            _ = try string(choice);
            const probabilities = try field(answer, "probabilities");
            if (probabilities != .array) return error.InvalidDecisionsProbabilities;
            var probability_map: std.json.ObjectMap = .empty;
            for (probabilities.array.items) |row| {
                const value = try object(row);
                try probability_map.put(a, try string(try field(value, "value")), try finite(try field(value, "probability")));
            }
            try put(a, &projected, "choice", choice);
            try put(a, &projected, "probabilities", .{ .object = probability_map });
            try put(a, &projected, "confidence", try finite(try field(answer, "confidence")));
        } else if (std.mem.eql(u8, kind, "score")) {
            if (!std.mem.eql(u8, answer_kind, "score")) return error.InvalidDecisionsScore;
            try put(a, &projected, "score", try finite(try field(answer, "score")));
            try put(a, &projected, "confidence", try finite(try field(answer, "confidence")));
        } else {
            if (!std.mem.eql(u8, kind, "bool") or !std.mem.eql(u8, answer_kind, "predicate")) return error.InvalidDecisionsPredicate;
            try put(a, &projected, "probability", try finite(try field(answer, "probability")));
        }
        try result.put(a, entry.key_ptr.*, .{ .object = projected });
    }
    return result;
}

test "latest Decisions payload and answer diagnostics match authenticated original functions" {
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(Value, gpa, @embedFile("fixtures/openai-decisions-7fb.json"), .{});
    defer captured.deinit();
    for (captured.value.object.get("payloads").?.array.items) |row| {
        const raw = if (row.object.get("rawContext")) |value| try gpa.dupe(u8, value.string) else try std.json.Stringify.valueAlloc(gpa, row.object.get("context").?, .{});
        defer gpa.free(raw);
        const actual = try payload(gpa, "decision-test", raw);
        defer gpa.free(actual);
        const expected = try std.json.Stringify.valueAlloc(gpa, row.object.get("body").?, .{});
        defer gpa.free(expected);
        try std.testing.expectEqualStrings(expected, actual);
    }
    for (captured.value.object.get("responses").?.array.items) |row| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var output: std.json.ObjectMap = .empty;
        try output.put(a, "answers", row.object.get("answers").?);
        const context = captured.value.object.get("context").?.object;
        const diagnostic = try answerDiagnostic(a, output, context);
        if (row.object.get("error")) |expected| {
            try std.testing.expectEqualStrings(expected.string, diagnostic.?);
        } else {
            try std.testing.expect(diagnostic == null);
            const actual = try std.json.Stringify.valueAlloc(a, Value{ .object = try answers(a, output, context) }, .{});
            const expected = try std.json.Stringify.valueAlloc(a, row.object.get("expected").?, .{});
            try std.testing.expectEqualStrings(expected, actual);
        }
    }
    const Sweep = struct {
        fn run(a: std.mem.Allocator, raw: []const u8) !void {
            const body = try payload(a, "decision-test", raw);
            defer a.free(body);
        }
    };
    const raw = try std.json.Stringify.valueAlloc(gpa, captured.value.object.get("payloads").?.array.items[2].object.get("context").?, .{});
    defer gpa.free(raw);
    try std.testing.checkAllAllocationFailures(gpa, Sweep.run, .{raw});
}

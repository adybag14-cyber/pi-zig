//! Codemode's model facade over one explicitly admitted model registry.
const std = @import("std");
const json = @import("protocol.zig").json;
const Value = json.Value;
pub const Operation = enum { getModelsOfType, getAvailableOfType, getModelOfType, classify, generateImages };
pub const Runtime = struct {
    context: ?*anyopaque,
    invoke: *const fn (?*anyopaque, std.mem.Allocator, Operation, Value, ?*bool) anyerror!json.Owned,
    docs_path: []const u8 = "docs/codemode.md",
};
const classifier_shape = "{ state: { ... }, images?: [{ type: \"image\", data: <base64>, mimeType }], questions: { <id>: { type: \"choice\", instructions, criteria: { <label>: <meaning> } } | { type: \"score\", instructions, criteria: [<lowest level>, ..., <highest level>] } | { type: \"bool\", instructions, criteria: { true: <meaning>, false: <meaning> } } } }";
fn argument(args: Value, index: usize) ?Value { return if (args == .array and index < args.array.items.len) args.array.items[index] else null; }
fn isString(value: ?Value) bool { return value != null and value.? == .string; }
fn strings(value: Value) bool {
    const values = if (value == .array) value.array.items else if (value == .object) value.object.values() else return false;
    if (values.len == 0) return false;
    for (values) |item| if (item != .string) return false;
    return true;
}
fn describe(a: std.mem.Allocator, value: ?Value) ![]const u8 {
    const item = value orelse return "undefined";
    return switch (item) {
        .null => "null", .string => "a string", .array => if (item.array.items.len == 0) "an empty array" else "an array",
        .bool => "a boolean", .integer, .float, .number_string => "a number",
        .object => if (item.object.count() == 0) "{}" else std.fmt.allocPrint(a, "{{ {s}{s} }}", .{ try std.mem.join(a, ", ", item.object.keys()[0..@min(6, item.object.count())]), if (item.object.count() > 6) ", ..." else "" }),
    };
}
fn errorResult(gpa: std.mem.Allocator, message: []const u8) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .{ .object = .empty };
    try result.value.object.put(a, "__pi_codemode_error", .{ .string = try a.dupe(u8, message) });
    return result;
}
fn contextProblem(a: std.mem.Allocator, operation: Operation, value: ?Value) !?[]const u8 {
    if (value == null or value.? != .object) return try std.fmt.allocPrint(a, "expects a context object as its second argument, got {s}", .{try describe(a, value)});
    const context = value.?;
    if (operation == .generateImages) {
        const input = json.get(context, "input");
        if (input == null or input.? != .array or input.?.array.items.len == 0) return try std.fmt.allocPrint(a, "context.input must be a non-empty array of blocks, got {s}", .{try describe(a, input)});
        for (input.?.array.items, 0..) |block, index| {
            if (block == .object and isString(json.get(block, "type"))) {
                const kind = json.get(block, "type").?.string;
                if (std.mem.eql(u8, kind, "text") and isString(json.get(block, "text"))) continue;
                if (std.mem.eql(u8, kind, "image") and isString(json.get(block, "data")) and isString(json.get(block, "mimeType"))) continue;
            }
            return try std.fmt.allocPrint(a, "context.input[{d}] must be a text or image block, got {s}", .{ index, try describe(a, block) });
        }
        return null;
    }
    const state = json.get(context, "state");
    if (state == null or state.? != .object) return try std.fmt.allocPrint(a, "context.state must be an object, got {s}", .{try describe(a, state)});
    if (json.get(context, "images")) |images| {
        if (images != .array) return try std.fmt.allocPrint(a, "context.images must be an array, got {s}", .{try describe(a, images)});
        for (images.array.items, 0..) |image, index| if (image != .object or !isString(json.get(image, "type")) or !std.mem.eql(u8, json.get(image, "type").?.string, "image") or !isString(json.get(image, "data")) or !isString(json.get(image, "mimeType"))) return try std.fmt.allocPrint(a, "context.images[{d}] must be an image block, got {s}", .{ index, try describe(a, image) });
    }
    const questions = json.get(context, "questions");
    if (questions == null or questions.? != .object or questions.?.object.count() == 0) return try std.fmt.allocPrint(a, "context.questions must map question IDs to questions, got {s}", .{try describe(a, questions)});
    var entries = questions.?.object.iterator();
    while (entries.next()) |entry| {
        const at = try std.fmt.allocPrint(a, "context.questions.{s}", .{entry.key_ptr.*});
        const question = entry.value_ptr.*;
        if (question != .object) return try std.fmt.allocPrint(a, "{s} must be a question object, got {s}", .{ at, try describe(a, question) });
        if (!isString(json.get(question, "instructions"))) return try std.fmt.allocPrint(a, "{s}.instructions must be a string", .{at});
        const kind = json.get(question, "type");
        const criteria = json.get(question, "criteria");
        if (isString(kind) and std.mem.eql(u8, kind.?.string, "choice")) {
            if (criteria == null or criteria.? != .object or !strings(criteria.?)) return try std.fmt.allocPrint(a, "{s} is a \"choice\" question, so criteria must map each label to its meaning", .{at});
        } else if (isString(kind) and std.mem.eql(u8, kind.?.string, "score")) {
            if (criteria == null or criteria.? != .array or !strings(criteria.?)) return try std.fmt.allocPrint(a, "{s} is a \"score\" question, so criteria must list the levels as strings, lowest first", .{at});
        } else if (isString(kind) and std.mem.eql(u8, kind.?.string, "bool")) {
            if (criteria == null or criteria.? != .object or !isString(json.get(criteria.?, "true")) or !isString(json.get(criteria.?, "false"))) return try std.fmt.allocPrint(a, "{s} is a \"bool\" question, so criteria must be {{ true: string, false: string }}", .{at});
        } else return try std.fmt.allocPrint(a, "{s}.type must be \"choice\", \"score\", or \"bool\", got {s}", .{ at, if (kind) |item| try json.stringify(a, item) else "undefined" });
    }
    return null;
}
fn article(kind: []const u8) []const u8 { return if (std.mem.eql(u8, kind, "image")) "an" else "a"; }
pub fn execute(gpa: std.mem.Allocator, runtime: Runtime, operation: Operation, args: Value, aborted: ?*bool) !json.Owned {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const first = argument(args, 0);
    if (operation == .getModelsOfType or operation == .getAvailableOfType or operation == .getModelOfType) {
        if (operation == .getModelOfType and (!isString(argument(args, 1)) or !isString(argument(args, 2)))) {
            var values: std.ArrayList([]const u8) = .empty;
            if (args == .array) for (args.array.items) |value| try values.append(a, try describe(a, value));
            return errorResult(gpa, try std.fmt.allocPrint(a, "models.getModelOfType(type, provider, id) expects three strings, got ({s}). The provider and the id are separate arguments, for example models.getModelOfType(\"classifier\", \"typesafe\", \"jev-latest\").", .{try std.mem.join(a, ", ", values.items)}));
        }
        if (!isString(first) or (!std.mem.eql(u8, first.?.string, "chat") and !std.mem.eql(u8, first.?.string, "image") and !std.mem.eql(u8, first.?.string, "classifier"))) return errorResult(gpa, try std.fmt.allocPrint(a, "Unknown model type {s}. Use \"chat\", \"image\", or \"classifier\".", .{if (first) |value| try json.stringify(a, value) else "undefined"}));
        const provider = argument(args, 1);
        if (provider != null and provider.? != .null and provider.? != .string) return errorResult(gpa, "provider must be a string");
        var result = try runtime.invoke(runtime.context, gpa, operation, args, aborted);
        errdefer result.deinit();
        if (result.value == .array) {
            for (result.value.array.items) |*model| if (model.* == .object) { _ = model.object.swapRemove("headers"); };
        } else if (result.value == .object) { _ = result.value.object.swapRemove("headers"); }
        return result;
    }
    const kind: []const u8 = if (operation == .classify) "classifier" else "image";
    const name: []const u8 = if (operation == .classify) "models.classify" else "models.generateImages";
    const hint = try std.fmt.allocPrint(a, "List the {s} models you can use with models.getAvailableOfType(\"{s}\").", .{ kind, kind });
    if (first == null or first.? != .object or !isString(json.get(first.?, "provider")) or !isString(json.get(first.?, "id"))) return errorResult(gpa, try std.fmt.allocPrint(a, "{s}() expects {s} {s} model as its first argument, got {s}.{s} {s}", .{ name, article(kind), kind, try describe(a, first), if (first == null or first.? == .null) " models.getModelOfType() returns undefined for an unknown provider or id." else "", hint }));
    const provider = json.get(first.?, "provider").?;
    const id = json.get(first.?, "id").?;
    var lookup: Value = .{ .array = .init(a) };
    try lookup.array.appendSlice(&.{ .{ .string = kind }, provider, id });
    var canonical = try runtime.invoke(runtime.context, gpa, .getModelOfType, lookup, aborted);
    defer canonical.deinit();
    if (canonical.value == .null) {
        for ([_][]const u8{ "chat", "image", "classifier" }) |other| {
            if (std.mem.eql(u8, other, kind)) continue;
            lookup.array.items[0] = .{ .string = other };
            var candidate = try runtime.invoke(runtime.context, gpa, .getModelOfType, lookup, aborted);
            defer candidate.deinit();
            if (candidate.value != .null) return errorResult(gpa, try std.fmt.allocPrint(a, "\"{s}/{s}\" is {s} {s} model, not {s} {s} model. {s}", .{ provider.string, id.string, article(other), other, article(kind), kind, hint }));
        }
        return errorResult(gpa, try std.fmt.allocPrint(a, "Unknown {s} model \"{s}/{s}\". {s}", .{ kind, provider.string, id.string, hint }));
    }
    const context = argument(args, 1);
    if (try contextProblem(a, operation, context)) |problem| return errorResult(gpa, if (operation == .classify) try std.fmt.allocPrint(a, "models.classify() {s}. Expected context: {s}. See \"Classify\" in {s}.", .{ problem, classifier_shape, runtime.docs_path }) else try std.fmt.allocPrint(a, "models.generateImages() {s}. Expected context: {{ input: [{{ type: \"text\", text: <prompt> }}, ...optional {{ type: \"image\", data: <base64>, mimeType }} references] }}. See \"Generate images\" in {s}.", .{ problem, runtime.docs_path }));
    var checked: Value = .{ .array = .init(a) };
    try checked.array.appendSlice(&.{ canonical.value, context.? });
    return runtime.invoke(runtime.context, gpa, operation, checked, aborted);
}
test "native codemode models exact source catalog errors contexts and canonical private lookup" {
    const gpa = std.testing.allocator;
    var captured = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-models-original-6fb.json"));
    defer captured.deinit();
    const State = struct {
        capture: Value,
        canonical: bool = false,
        fn invoke(raw: ?*anyopaque, allocator: std.mem.Allocator, operation: Operation, args: Value, _: ?*bool) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var result = try json.Owned.empty(allocator);
            errdefer result.deinit();
            const a = result.arena.allocator();
            if (operation == .classify or operation == .generateImages) {
                const headers = json.get(argument(args, 0).?, "headers").?;
                try std.testing.expectEqualStrings("PRIVATE_HEADER", json.get(headers, "Authorization").?.string);
                try std.testing.expect(json.get(argument(args, 0).?, "baseUrl") == null);
                self.canonical = true;
                const original_rows = json.get(self.capture, "rows").?.array.items;
                result.value = try json.clone(a, json.get(original_rows[if (operation == .classify) @as(usize, 14) else 13], "result").?);
                return result;
            }
            const kind = argument(args, 0).?.string;
            const provider = argument(args, 1);
            const id = argument(args, 2);
            result.value = if (operation == .getModelOfType) .null else .{ .array = .init(a) };
            for (json.get(self.capture, "models").?.array.items) |model| {
                if (!std.mem.eql(u8, json.get(model, "type").?.string, kind)) continue;
                if (provider != null and provider.? == .string and !std.mem.eql(u8, provider.?.string, json.get(model, "provider").?.string)) continue;
                if (operation == .getModelOfType) {
                    if (std.mem.eql(u8, id.?.string, json.get(model, "id").?.string)) result.value = try json.clone(a, model);
                } else try result.value.array.append(try json.clone(a, model));
            }
            return result;
        }
    };
    var state: State = .{ .capture = captured.value };
    for (json.get(captured.value, "rows").?.array.items) |row| {
        const name = json.get(row, "name").?.string;
        const operation = std.meta.stringToEnum(Operation, name["models.".len..]).?;
        var result = try execute(gpa, .{ .context = &state, .invoke = State.invoke, .docs_path = json.get(captured.value, "docsPath").?.string }, operation, json.get(row, "args").?, null);
        defer result.deinit();
        if (json.get(row, "error")) |failure| {
            const actual = json.get(result.value, "__pi_codemode_error") orelse return error.ExpectedSourceModelError;
            try std.testing.expectEqualStrings(json.get(failure, "message").?.string, actual.string);
        } else {
            try std.testing.expect(json.equal(json.get(row, "result").?, result.value));
        }
    }
    try std.testing.expect(state.canonical);
}

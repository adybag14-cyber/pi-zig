//! Pi tool discovery tokenization and stable Okapi BM25 ranking.
const std = @import("std");
pub const Document = struct { name: []const u8, text: []const u8 };
pub const Match = struct { name: []const u8, score: f64 };
pub const Options = struct { k1: f64 = 1.2, b: f64 = 0.75 };
pub const description = "# Tool discovery\n\nSearches over deferred tool metadata with BM25 and exposes matching tools for the next model call.\n\nSome of the tools, such as tools of MCP servers, may not have been provided to you upfront, and you should use this tool (`tool_search`) to search for the required tools. For MCP tool discovery, always use `tool_search`.";
pub const Tool = struct { name: []const u8, description: []const u8 = "", parameters: std.json.Value };
pub const Namespace = struct { name: []const u8, description: []const u8 = "", instructions: []const u8 = "" };
pub fn blank(value: []const u8) bool {
    const view = std.unicode.Utf8View.init(value) catch return false;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |point| switch (point) {
        0x9...0xd, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => {},
        else => return false,
    };
    return true;
}
fn schemaText(a: std.mem.Allocator, value: std.json.Value, parts: *std.ArrayList([]const u8), depth: usize) !void {
    if (value != .object) return;
    if (depth > 512) return error.ToolSearchSchemaTooDeep;
    if (value.object.get("description")) |text| if (text == .string) try parts.append(a, text.string);
    if (value.object.get("properties")) |properties| if (properties == .object) {
        var iterator = properties.object.iterator();
        while (iterator.next()) |property| {
            try parts.append(a, property.key_ptr.*);
            try schemaText(a, property.value_ptr.*, parts, depth + 1);
        }
    };
    if (value.object.get("items")) |items| try schemaText(a, items, parts, depth + 1);
    for ([_][]const u8{ "anyOf", "oneOf", "allOf" }) |field| if (value.object.get(field)) |variants| {
        if (variants == .array) for (variants.array.items) |variant| try schemaText(a, variant, parts, depth + 1);
    };
}
/// The text is owned; its name borrows the tool descriptor.
pub fn createDocument(gpa: std.mem.Allocator, tool: Tool, namespace: ?Namespace) !Document {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const expanded = try a.dupe(u8, tool.name);
    for (expanded) |*byte| if (byte.* == '_') {
        byte.* = ' ';
    };
    var parts: std.ArrayList([]const u8) = .empty;
    try parts.appendSlice(a, &.{ tool.name, expanded, tool.description });
    try schemaText(a, tool.parameters, &parts, 0);
    if (namespace) |value| try parts.appendSlice(a, &.{ value.name, value.description, value.instructions });
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    for (parts.items) |part| {
        if (blank(part)) continue;
        if (output.items.len > 0) try output.append(gpa, ' ');
        try output.appendSlice(gpa, part);
    }
    return .{ .name = tool.name, .text = try output.toOwnedSlice(gpa) };
}
const stop_words = [_][]const u8{ "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "with" };
fn stop(term: []const u8) bool {
    for (stop_words) |word| if (std.mem.eql(u8, word, term)) return true;
    return false;
}
fn stem(a: std.mem.Allocator, term: []const u8) ![]const u8 {
    if (term.len > 4 and std.mem.endsWith(u8, term, "ies")) return std.fmt.allocPrint(a, "{s}y", .{term[0 .. term.len - 3]});
    if (term.len > 4) for ([_][]const u8{ "ches", "shes", "sses", "xes", "zes" }) |suffix| {
        if (std.mem.endsWith(u8, term, suffix)) return a.dupe(u8, term[0 .. term.len - 2]);
    };
    if (term.len > 3 and std.mem.endsWith(u8, term, "s") and !std.mem.endsWith(u8, term, "ss")) return a.dupe(u8, term[0 .. term.len - 1]);
    return a.dupe(u8, term);
}
/// Returned tokens and array storage belong to the caller allocator.
pub fn tokenize(a: std.mem.Allocator, input: []const u8) ![]const []const u8 {
    var normalized: std.ArrayList(u8) = .empty;
    defer normalized.deinit(a);
    var index: usize = 0;
    while (index < input.len) {
        const current = input[index];
        if (current < 128) {
            const previous = if (index > 0) input[index - 1] else 0;
            const next = if (index + 1 < input.len) input[index + 1] else 0;
            if (std.ascii.isUpper(current) and (std.ascii.isLower(previous) or std.ascii.isDigit(previous) or (std.ascii.isUpper(previous) and std.ascii.isLower(next)))) try normalized.append(a, ' ');
            try normalized.append(a, if (std.ascii.isAlphanumeric(current)) std.ascii.toLower(current) else ' ');
            index += 1;
        } else {
            const width = std.unicode.utf8ByteSequenceLength(current) catch 1;
            const available = @min(@as(usize, width), input.len - index);
            const point = std.unicode.utf8Decode(input[index .. index + available]) catch 0;
            // JavaScript lowercasing these Unicode characters produces ASCII.
            if (point == 0x212a) try normalized.append(a, 'k') else if (point == 0x130) try normalized.appendSlice(a, "i ") else try normalized.append(a, ' ');
            index += available;
        }
    }
    var tokens: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (tokens.items) |value| a.free(value);
        tokens.deinit(a);
    }
    var terms = std.mem.tokenizeScalar(u8, normalized.items, ' ');
    while (terms.next()) |term| if (!stop(term)) {
        const value = try stem(a, term);
        errdefer a.free(value);
        try tokens.append(a, value);
    };
    return tokens.toOwnedSlice(a);
}
pub fn freeTokens(a: std.mem.Allocator, tokens: []const []const u8) void {
    for (tokens) |term| a.free(term);
    a.free(tokens);
}
/// Match names borrow documents; the returned match array is owned.
pub fn rank(gpa: std.mem.Allocator, query: []const u8, documents: []const Document, limit: usize, options: Options) ![]Match {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const terms = try tokenize(a, query);
    if (terms.len == 0 or documents.len == 0 or limit == 0) return gpa.alloc(Match, 0);
    var query_counts: std.StringHashMapUnmanaged(void) = .empty;
    var unique: std.ArrayList([]const u8) = .empty;
    for (terms) |term| {
        const entry = try query_counts.getOrPut(a, term);
        if (!entry.found_existing) try unique.append(a, term);
    }
    const counts = try a.alloc(std.StringHashMapUnmanaged(usize), documents.len);
    const lengths = try a.alloc(usize, documents.len);
    var total_length: usize = 0;
    for (documents, 0..) |document, i| {
        counts[i] = .empty;
        const words = try tokenize(a, document.text);
        lengths[i] = words.len;
        total_length += words.len;
        for (words) |word| {
            const entry = try counts[i].getOrPut(a, word);
            if (!entry.found_existing) entry.value_ptr.* = 0;
            entry.value_ptr.* += 1;
        }
    }
    const average = if (total_length == 0) 1.0 else @as(f64, @floatFromInt(total_length)) / @as(f64, @floatFromInt(documents.len));
    const idf = try a.alloc(f64, unique.items.len);
    for (unique.items, 0..) |term, i| {
        var frequency: usize = 0;
        for (counts) |document| if (document.contains(term)) {
            frequency += 1;
        };
        idf[i] = @log(1.0 + (@as(f64, @floatFromInt(documents.len - frequency)) + 0.5) / (@as(f64, @floatFromInt(frequency)) + 0.5));
    }
    const Scored = struct { value: Match, index: usize };
    var matches: std.ArrayList(Scored) = .empty;
    for (documents, 0..) |document, index| {
        var score: f64 = 0;
        const norm = options.k1 * (1.0 - options.b + options.b * @as(f64, @floatFromInt(lengths[index])) / average);
        for (unique.items, 0..) |term, i| if (counts[index].get(term)) |count| {
            const frequency: f64 = @floatFromInt(count);
            score += idf[i] * (frequency * (options.k1 + 1.0) / (frequency + norm));
        };
        if (score > 0) try matches.append(a, .{ .value = .{ .name = document.name, .score = score }, .index = index });
    }
    std.mem.sort(Scored, matches.items, {}, struct {
        fn before(_: void, left: Scored, right: Scored) bool {
            return if (left.value.score == right.value.score) left.index < right.index else left.value.score > right.value.score;
        }
    }.before);
    const result = try gpa.alloc(Match, @min(limit, matches.items.len));
    for (result, matches.items[0..result.len]) |*target, value| target.* = value.value;
    return result;
}

fn numeric(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => unreachable,
    };
}
test "tool discovery tokenizer and BM25 match actual upstream Unicode camelcase ties options and empty queries" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/tool-search-7fb.json"), .{});
    defer parsed.deinit();
    for (parsed.value.object.get("tokens").?.array.items) |row| {
        const actual = try tokenize(gpa, row.object.get("text").?.string);
        defer freeTokens(gpa, actual);
        const expected = row.object.get("tokens").?.array.items;
        try std.testing.expectEqual(expected.len, actual.len);
        for (actual, expected) |term, value| try std.testing.expectEqualStrings(value.string, term);
    }
    const rows = parsed.value.object.get("documents").?.array.items;
    const source_tools = parsed.value.object.get("tools").?.array.items;
    const raw_namespace = parsed.value.object.get("namespace").?.object;
    const namespace: Namespace = .{ .name = raw_namespace.get("name").?.string, .description = raw_namespace.get("description").?.string, .instructions = raw_namespace.get("instructions").?.string };
    for (source_tools, rows, 0..) |tool, expected, index| {
        const document = try createDocument(gpa, .{ .name = tool.object.get("name").?.string, .description = tool.object.get("description").?.string, .parameters = tool.object.get("parameters").? }, if (index < 2) namespace else null);
        defer gpa.free(document.text);
        try std.testing.expectEqualStrings(expected.object.get("text").?.string, document.text);
    }
    const docs = try gpa.alloc(Document, rows.len);
    defer gpa.free(docs);
    for (docs, rows) |*doc, row| doc.* = .{ .name = row.object.get("name").?.string, .text = row.object.get("text").?.string };
    for (parsed.value.object.get("rank").?.array.items) |request| {
        var options: Options = .{};
        if (request.object.get("options")) |value| {
            options.k1 = numeric(value.object.get("k1").?);
            options.b = numeric(value.object.get("b").?);
        }
        const actual = try rank(gpa, request.object.get("query").?.string, docs, @intCast(request.object.get("limit").?.integer), options);
        defer gpa.free(actual);
        const expected = request.object.get("matches").?.array.items;
        try std.testing.expectEqual(expected.len, actual.len);
        for (actual, expected) |result, match| {
            try std.testing.expectEqualStrings(match.object.get("name").?.string, result.name);
            try std.testing.expectApproxEqAbs(numeric(match.object.get("score").?), result.score, 0.000000000001);
        }
    }
    const Sweep = struct {
        fn run(a: std.mem.Allocator, documents: []const Document) !void {
            const result = try rank(a, "issues labels repoOwner", documents, 8, .{});
            defer a.free(result);
            const tokens = try tokenize(a, "queries HTTPServer İStanbul");
            defer freeTokens(a, tokens);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Sweep.run, .{docs});
}

//! Codemode first-line directives, including ECMAScript whitespace and key order.
const std = @import("std");
const json = @import("protocol.zig").json;
pub const prefix = "// @options:";
pub const Parsed = struct { code: []const u8, max_output_tokens: ?u64 = null, timeout_ms: ?u32 = null };
fn whitespace(point: u21) bool {
    return switch (point) {
        0x0009...0x000d, 0x0020, 0x00a0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn trim(source: []const u8, leading_only: bool) []const u8 {
    var iterator = (std.unicode.Wtf8View.init(source) catch return source).iterator();
    var begin: ?usize = null;
    var end: usize = 0;
    var before: usize = 0;
    while (iterator.nextCodepoint()) |point| {
        if (!whitespace(point)) {
            if (leading_only) return source[before..];
            if (begin == null) begin = before;
            end = iterator.i;
        }
        before = iterator.i;
    }
    return source[begin orelse source.len .. if (begin == null) source.len else end];
}
fn arrayIndex(key: []const u8) ?u32 {
    if (key.len == 0 or key.len > 10 or (key.len > 1 and key[0] == '0')) return null;
    for (key) |byte| if (!std.ascii.isDigit(byte)) return null;
    const value = std.fmt.parseInt(u32, key, 10) catch return null;
    return if (value == std.math.maxInt(u32)) null else value;
}
fn unsupported(object: std.json.ObjectMap) ?[]const u8 {
    var numeric: ?u32 = null;
    var numeric_key: ?[]const u8 = null;
    var first: ?[]const u8 = null;
    var iterator = object.iterator();
    while (iterator.next()) |field| {
        const key = field.key_ptr.*;
        if (std.mem.eql(u8, key, "max_output_tokens") or std.mem.eql(u8, key, "timeout_ms")) continue;
        if (arrayIndex(key)) |index| {
            if (numeric == null or index < numeric.?) {
                numeric = index;
                numeric_key = key;
            }
        } else if (first == null) first = key;
    }
    return numeric_key orelse first;
}
pub fn parse(gpa: std.mem.Allocator, source: []const u8) !Parsed {
    if (trim(source, false).len == 0) return error.EmptyCodemodeSource;
    const newline = std.mem.indexOfScalar(u8, source, '\n');
    const line = source[0 .. newline orelse source.len];
    const first = trim(if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line, true);
    if (!std.mem.startsWith(u8, first, prefix)) return .{ .code = source };
    const code = if (newline) |index| source[index..] else "";
    if (trim(code, false).len == 0) return error.CodemodeOptionsWithoutSource;
    const directive = trim(first[prefix.len..], false);
    if (directive.len == 0) return error.CodemodeOptionsMustBeObject;
    var options = json.Owned.parseJavaScriptNumbers(gpa, directive) catch |cause| switch (cause) {
        error.OutOfMemory => return cause,
        else => return error.InvalidCodemodeOptionsJson,
    };
    defer options.deinit();
    if (options.value != .object) return error.CodemodeOptionsMustBeObject;
    if (unsupported(options.value.object) != null) return error.UnsupportedCodemodeOption;
    var result: Parsed = .{ .code = code };
    if (options.value.object.get("max_output_tokens")) |field| {
        result.max_output_tokens = json.asInteger(field) catch return error.InvalidCodemodeOutputTokens;
    }
    if (options.value.object.get("timeout_ms")) |field| {
        const value = json.asInteger(field) catch return error.InvalidCodemodeTimeout;
        if (value == 0 or value > 2_147_483_647) return error.InvalidCodemodeTimeout;
        result.timeout_ms = @intCast(value);
    }
    return result;
}
pub fn diagnostic(cause: anyerror) []const u8 {
    return switch (cause) {
        error.EmptyCodemodeSource => "Expected JavaScript source text (non-empty). Provide JS only, optionally with a first line `// @options: {\"max_output_tokens\": 1000}`.",
        error.CodemodeOptionsWithoutSource => "The @options line must be followed by JavaScript source on subsequent lines",
        error.CodemodeOptionsMustBeObject => "@options must be a JSON object with supported fields `max_output_tokens` and `timeout_ms`",
        error.InvalidCodemodeOutputTokens => "@options field `max_output_tokens` must be a non-negative safe integer",
        error.InvalidCodemodeTimeout => "@options field `timeout_ms` must be a positive integer up to 2147483647",
        else => @errorName(cause),
    };
}
pub fn diagnosticForInput(gpa: std.mem.Allocator, input: []const u8, cause: anyerror) ![]u8 {
    if (cause != error.UnsupportedCodemodeOption) return gpa.dupe(u8, diagnostic(cause));
    const newline = std.mem.indexOfScalar(u8, input, '\n') orelse input.len;
    const first = trim(input[0..newline], true);
    var options = try json.Owned.parseJavaScriptNumbers(gpa, trim(first[prefix.len..], false));
    defer options.deinit();
    if (unsupported(options.value.object)) |key| return std.fmt.allocPrint(gpa, "@options only supports `max_output_tokens` and `timeout_ms`; got `{s}`", .{key});
    return gpa.dupe(u8, diagnostic(cause));
}
test "native codemode source directives preserve original line numbers and reject invalid limits" {
    const source = " \t// @options: {\"timeout_ms\":123,\"max_output_tokens\":0}\r\nreturn 1;";
    const result = try parse(std.testing.allocator, source);
    try std.testing.expectEqualStrings("\nreturn 1;", result.code);
    try std.testing.expectEqual(@as(?u32, 123), result.timeout_ms);
    try std.testing.expectEqual(@as(?u64, 0), result.max_output_tokens);
    try std.testing.expectError(error.EmptyCodemodeSource, parse(std.testing.allocator, "\n\t"));
    try std.testing.expectError(error.CodemodeOptionsWithoutSource, parse(std.testing.allocator, "// @options: {}"));
    try std.testing.expectError(error.InvalidCodemodeTimeout, parse(std.testing.allocator, "// @options: {\"timeout_ms\":0}\nreturn 1"));
    try std.testing.expectError(error.InvalidCodemodeOutputTokens, parse(std.testing.allocator, "// @options: {\"max_output_tokens\":-1}\nreturn 1"));
    try std.testing.expectError(error.UnsupportedCodemodeOption, parse(std.testing.allocator, "// @options: {\"unknown\":1}\nreturn 1"));
}

test "native codemode source ECMA whitespace key order and numeric validation match actual ea Source" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-source-ecma-ea.json"));
    defer fixture.deinit();
    for (fixture.value.object.get("rows").?.array.items) |row| {
        const input = row.object.get("input").?.string;
        const actual = parse(gpa, input) catch |cause| {
            const message = try diagnosticForInput(gpa, input, cause);
            defer gpa.free(message);
            const expected_error = row.object.get("error") orelse {
                std.debug.print("Unexpected error {s} in {s}\n", .{ @errorName(cause), row.object.get("name").?.string });
                return error.UnexpectedSourceError;
            };
            try std.testing.expectEqualStrings(expected_error.object.get("message").?.string, message);
            continue;
        };
        const expected = row.object.get("result") orelse return error.ExpectedSourceError;
        try std.testing.expectEqualStrings(expected.object.get("code").?.string, actual.code);
        const options = expected.object.get("options").?.object;
        try std.testing.expectEqual(if (options.get("maxOutputTokens")) |v| try json.asInteger(v) else @as(?u64, null), actual.max_output_tokens);
        try std.testing.expectEqual(if (options.get("timeoutMs")) |v| @as(u32, @intCast(try json.asInteger(v))) else @as(?u32, null), actual.timeout_ms);
    }
    try std.testing.expectError(error.NonfiniteJSONNumber, json.Owned.parse(gpa, "1e999"));
    var ecma = try json.Owned.parseJavaScriptNumbers(gpa, "1e999");
    defer ecma.deinit();
    try std.testing.expect(std.math.isPositiveInf(ecma.value.float));
}

test "native codemode source parser replays actual original results and validation messages" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/codemode-source-7fb.json"));
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |case| {
        const actual = parse(gpa, case.object.get("input").?.string) catch |cause| {
            try std.testing.expectEqualStrings(case.object.get("error").?.string, diagnostic(cause));
            continue;
        };
        const expected = case.object.get("result").?;
        try std.testing.expectEqualStrings(expected.object.get("code").?.string, actual.code);
        const options = expected.object.get("options").?;
        if (options.object.get("maxOutputTokens")) |tokens| try std.testing.expectEqual(try json.asInteger(tokens), actual.max_output_tokens.?) else try std.testing.expect(actual.max_output_tokens == null);
        if (options.object.get("timeoutMs")) |timeout| try std.testing.expectEqual(@as(u32, @intCast(try json.asInteger(timeout))), actual.timeout_ms.?) else try std.testing.expect(actual.timeout_ms == null);
    }
}

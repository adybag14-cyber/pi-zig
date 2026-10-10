//! Codemode first-line directive and source validation, pinned to Pi 1.0.4.
const std = @import("std");
const json = @import("protocol.zig").json;
pub const prefix = "// @options:";
pub const Parsed = struct { code: []const u8, max_output_tokens: ?u64 = null, timeout_ms: ?u32 = null };
pub fn parse(gpa: std.mem.Allocator, source: []const u8) !Parsed {
    if (std.mem.trim(u8, source, " \t\r\n").len == 0) return error.EmptyCodemodeSource;
    const newline = std.mem.indexOfScalar(u8, source, '\n');
    const first = std.mem.trimStart(u8, std.mem.trimEnd(u8, source[0 .. newline orelse source.len], "\r"), " \t");
    if (!std.mem.startsWith(u8, first, prefix)) return .{ .code = source };
    const code = if (newline) |index| source[index..] else "";
    if (std.mem.trim(u8, code, " \t\r\n").len == 0) return error.CodemodeOptionsWithoutSource;
    const directive = std.mem.trim(u8, first[prefix.len..], " \t\r");
    if (directive.len == 0) return error.CodemodeOptionsMustBeObject;
    var options = json.Owned.parse(gpa, directive) catch |cause| switch (cause) {
        error.OutOfMemory => return cause,
        else => return error.InvalidCodemodeOptionsJson,
    };
    defer options.deinit();
    if (options.value != .object) return error.CodemodeOptionsMustBeObject;
    var result: Parsed = .{ .code = code };
    var fields = options.value.object.iterator();
    while (fields.next()) |field| {
        if (std.mem.eql(u8, field.key_ptr.*, "max_output_tokens")) {
            const value = json.asInteger(field.value_ptr.*) catch return error.InvalidCodemodeOutputTokens;
            if (value > 9_007_199_254_740_991) return error.InvalidCodemodeOutputTokens;
            result.max_output_tokens = value;
        } else if (std.mem.eql(u8, field.key_ptr.*, "timeout_ms")) {
            const value = json.asInteger(field.value_ptr.*) catch return error.InvalidCodemodeTimeout;
            if (value == 0 or value > 2_147_483_647) return error.InvalidCodemodeTimeout;
            result.timeout_ms = @intCast(value);
        } else return error.UnsupportedCodemodeOption;
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
    const first = std.mem.trim(u8, input[0..newline], " \t\r");
    var options = try json.Owned.parse(gpa, std.mem.trim(u8, first[prefix.len..], " \t\r"));
    defer options.deinit();
    var iterator = options.value.object.iterator();
    while (iterator.next()) |field| if (!std.mem.eql(u8, field.key_ptr.*, "max_output_tokens") and !std.mem.eql(u8, field.key_ptr.*, "timeout_ms")) {
        return std.fmt.allocPrint(gpa, "@options only supports `max_output_tokens` and `timeout_ms`; got `{s}`", .{field.key_ptr.*});
    };
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

//! TEST-ONLY original-config projection for six precise documentation fragments.
//! The original Source560 capture and all nonpath prompt text remain unchanged.
const std = @import("std");
const builtin = @import("builtin");
const json = @import("../mcp/protocol.zig").json;
fn string(value: json.Value, name: []const u8) ![]const u8 {
    const field = value.object.get(name) orelse return error.MissingSourceDocField;
    if (field != .string) return error.InvalidSourceDocField;
    return field.string;
}
fn same(value: json.Value, name: []const u8, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, try string(value, name));
}
fn record(proof: json.Value, id: []const u8, captured: []const u8) !json.Value {
    const records = proof.object.get("records") orelse return error.MissingSourceDocRecords;
    if (records != .array or records.array.items.len != 3) return error.InvalidSourceDocRecords;
    var found: ?json.Value = null;
    for (records.array.items) |row| if (std.mem.eql(u8, try string(row, "id"), id)) {
        if (found != null) return error.DuplicateSourceDocRecord;
        try same(row, "capturedWindows", captured);
        if ((try string(row, "resolved")).len == 0) return error.InvalidResolvedSourceDoc;
        found = row;
    };
    return found orelse error.MissingSourceDocRecord;
}
fn replaceFragment(expected: *json.Owned, text: *json.Value, source: json.Value, prefix: []const u8, suffix: []const u8) !void {
    if (text.* != .string) return error.InvalidCapturedPromptText;
    const arena = expected.arena.allocator();
    const captured = try string(source, "capturedWindows");
    const resolved = try string(source, "resolved");
    const original = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ prefix, captured, suffix });
    const position = std.mem.indexOf(u8, text.string, original) orelse return error.MissingCapturedDocFragment;
    if (std.mem.indexOfPos(u8, text.string, position + original.len, original) != null) return error.DuplicateCapturedDocFragment;
    const replacement = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ prefix, resolved, suffix });
    text.* = .{ .string = try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ text.string[0..position], replacement, text.string[position + original.len ..] }) };
}
pub fn project(gpa: std.mem.Allocator, expected: *json.Owned) !usize {
    const path = std.testing.environ.getAlloc(gpa, "PI_SDK_SOURCE_DOCS_ORACLE") catch |err| switch (err) {
        error.EnvironmentVariableMissing => return 0,
        else => return err,
    };
    defer gpa.free(path);
    const raw = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, gpa, .limited(64 * 1024));
    defer gpa.free(raw);
    var proof = try json.Owned.parse(gpa, raw);
    defer proof.deinit();
    try same(proof.value, "schema", "sdk-source-doc-path-oracle-562-v1");
    try same(proof.value, "configTsSha256", "B3B77644910D3FAC28A06625E90F993A8C1BC6C9458F148C723E64E0C99EB23E");
    try same(proof.value, "configJsSha256", "B53418CA3BC54B70E18CCB192EB471696F5211C5AA2E80D68FE6FE3851FF23AE");
    try same(proof.value, "callerTsSha256", "5E28C82634113D0CCA7FF5DA6FA94E27AAAE80E461CD5664CED9DBCEF6F89089");
    try same(proof.value, "manifestSha256", "C07E1824BFA0DE5935C19FCAD3056F08F2E06837C4CF08956DF17650282FEBA2");
    const input = proof.value.object.get("input") orelse return error.MissingSourceDocInput;
    try same(input, "name", "PI_PACKAGE_DIR");
    try same(input, "value", "C:/sdk-agent-start-package");
    const node = proof.value.object.get("node") orelse return error.MissingSourceDocRuntime;
    try same(node, "version", "24.14.0");
    try same(node, "platform", switch (builtin.os.tag) {
        .windows => "win32",
        .linux => "linux",
        .macos => "darwin",
        else => return error.UnsupportedSourceDocPlatform,
    });
    const paths = expected.value.object.get("sourcePaths") orelse return error.MissingOriginalDocPaths;
    const readme = try record(proof.value, "readme", try string(paths, "readme"));
    const docs = try record(proof.value, "docs", try string(paths, "docs"));
    const examples = try record(proof.value, "examples", try string(paths, "examples"));
    const rows = expected.value.object.getPtr("rows") orelse return error.MissingOriginalAgentRows;
    if (rows.array.items.len != 18) return error.OriginalSource560ShapeChanged;
    const row = &rows.array.items[13];
    try same(row.*, "id", "default-docs");
    const events = row.object.getPtr("events") orelse return error.MissingOriginalDocEvents;
    if (events.array.items.len != 11) return error.OriginalDocEventShapeChanged;
    const rendered = &events.array.items[5];
    if (rendered.array.items.len != 4 or rendered.array.items[0] != .string) return error.InvalidOriginalDocRender;
    try std.testing.expectEqualStrings("render", rendered.array.items[0].string);
    inline for (.{ 1, 2 }) |index| {
        const text = &rendered.array.items[index];
        try replaceFragment(expected, text, readme, "- Main documentation: ", "\n");
        try replaceFragment(expected, text, docs, "- Additional docs: ", "\n");
        try replaceFragment(expected, text, examples, "- Examples: ", " (extensions, custom tools, SDK)");
    }
    return 6;
}

//! TEST-ONLY: precise original-Source cwd projection, never product code.
//! Reads an independent unchanged production resolvePath oracle receipt.
const std = @import("std");
const builtin = @import("builtin");
const json = @import("../mcp/protocol.zig").json;
pub const Capture = enum { command_actions, normalized_options };
fn string(value: json.Value, name: []const u8) ![]const u8 {
    const field = value.object.get(name) orelse return error.MissingSourceOracleField;
    if (field != .string) return error.InvalidSourceOracleField;
    return field.string;
}
fn same(value: json.Value, name: []const u8, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, try string(value, name));
}
fn record(proof: json.Value, id: []const u8, input: []const u8) !json.Value {
    const records = proof.object.get("records") orelse return error.MissingSourceOracleRecords;
    if (records != .array or records.array.items.len != 3) return error.InvalidSourceOracleRecords;
    var found: ?json.Value = null;
    for (records.array.items) |entry| if (std.mem.eql(u8, try string(entry, "id"), id)) {
        if (found != null) return error.DuplicateSourceOracleRecord;
        try same(entry, "input", input);
        found = entry;
    };
    return found orelse error.MissingSourceOracleRecord;
}
fn replaceCwd(expected: *json.Owned, object: *json.Value, source: json.Value) !void {
    const field = object.object.getPtr("cwd") orelse return error.MissingCapturedCwd;
    if (field.* != .string) return error.InvalidCapturedCwd;
    // The canonical Windows capture remains immutable. Project only a field
    // whose raw value matches this independent Source record's exact origin.
    try std.testing.expectEqualStrings(try string(source, "capturedWindows"), field.string);
    const resolved = try string(source, "resolved");
    if (resolved.len == 0) return error.InvalidResolvedSourceCwd;
    field.* = .{ .string = try expected.arena.allocator().dupe(u8, resolved) };
}
pub fn project(gpa: std.mem.Allocator, expected: *json.Owned, capture: Capture) !usize {
    const path = std.testing.environ.getAlloc(gpa, "PI_SDK_SOURCE_CWD_ORACLE") catch |cause| switch (cause) {
        error.EnvironmentVariableMissing => return 0,
        else => return cause,
    };
    defer gpa.free(path);
    const raw = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, gpa, .limited(64 * 1024));
    defer gpa.free(raw);
    var proof = try json.Owned.parse(gpa, raw);
    defer proof.deinit();
    try same(proof.value, "schema", "sdk-source-cwd-oracle-542-v1");
    try same(proof.value, "source", "ea448f454af474f3e2fe9733b331e17b0662f5d6");
    try same(proof.value, "sdkSha256", "61F398403C7510BEC849583B2C46272DF11AC5AA8D2E24B4DED97A108DD55B28");
    try same(proof.value, "pathsTsSha256", "64C3EBEF724FA21ED0042E127908B4323A5D2F1B8AAA91EEE550442332FE8502");
    try same(proof.value, "pathsJsSha256", "D5D48C2B2B2442C7E72AEE6E98A79D828A52DCE9526B152288186834C1DCF4A5");
    try same(proof.value, "childProcessJsSha256", "CFC7B3361E42B61EE75AECC2B436FF7462F7E4431B4B646DA7166F3C5706C9B8");
    try same(proof.value, "manifestSha256", "2A793675AD5BC9016B790B75D1ED0A5AF4BF8A1B5B7EA1733C15DF65436B31DF");
    const node = proof.value.object.get("node") orelse return error.MissingSourceOracleRuntime;
    try same(node, "version", "24.14.0");
    try same(node, "platform", switch (builtin.os.tag) {
        .windows => "win32",
        .linux => "linux",
        .macos => "darwin",
        else => return error.UnsupportedSourceOraclePlatform,
    });
    const rows = expected.value.object.getPtr("rows") orelse return error.MissingOriginalSourceRows;
    switch (capture) {
        .command_actions => {
            if (rows.array.items.len != 3) return error.OriginalSource505ShapeChanged;
            const row = &rows.array.items[0];
            try same(row.*, "id", "default-actions");
            const options = row.object.getPtr("options") orelse return error.OriginalSource505OptionsMissing;
            try replaceCwd(expected, options, try record(proof.value, "command-actions/default-actions", "/sdk-command-actions/default-actions"));
            return 1;
        },
        .normalized_options => {
            if (rows.array.items.len != 2) return error.OriginalNormalizedSourceShapeChanged;
            var projected: usize = 0;
            inline for (.{ "metadata-and-copy", "empty-metadata" }, 0..) |id, index| {
                const row = &rows.array.items[index];
                try same(row.*, "id", id);
                const source = try record(proof.value, "normalized-options/" ++ id, "/sdk-normalized-options/" ++ id);
                inline for (.{ "before", "mutated", "after" }) |phase| {
                    const graph = row.object.getPtr(phase) orelse return error.OriginalNormalizedSourcePhaseMissing;
                    try replaceCwd(expected, graph, source);
                    projected += 1;
                }
            }
            try std.testing.expectEqual(@as(usize, 6), projected);
            return projected;
        },
    }
}

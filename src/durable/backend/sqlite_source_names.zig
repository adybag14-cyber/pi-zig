//! Immutable identifier history for the original durable SQLite schema.
const std = @import("std");

pub const table_names = [_][]const u8{
    "durable_schema", "durable_metadata", "record_ids", "conversations",      "entries",
    "tasks",          "submissions",      "documents",  "document_revisions",
};
pub const index_names = [_][]const u8{
    "conversations_by_owner_conversation", "conversations_by_owner_task",
    "entries_by_conversation",             "entry_heads_by_conversation",
    "tasks_by_status",                     "tasks_by_conversation",
    "tasks_by_kind",                       "tasks_by_abort_requested",
    "tasks_by_background",                 "submissions_by_request",
    "submissions_by_conversation",         "submissions_by_status",
    "documents_by_address",                "documents_by_scope",
    "documents_by_scope_kind",             "document_revisions_by_kind",
};
pub const identifiers = table_names ++ index_names;

pub fn validatePrefix(prefix: []const u8) !void {
    if (prefix.len == 0 or !(std.ascii.isAlphabetic(prefix[0]) or prefix[0] == '_')) return error.InvalidSqliteSchemaPrefix;
    for (prefix[1..]) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return error.InvalidSqliteSchemaPrefix;
    if (std.ascii.startsWithIgnoreCase(prefix, "sqlite_")) return error.ReservedSqliteSchemaPrefix;
}

pub const Names = struct {
    gpa: std.mem.Allocator,
    prefix: ?[]const u8,
    mapped: ?[identifiers.len][]const u8 = null,

    pub fn init(gpa: std.mem.Allocator, prefix: ?[]const u8) !Names {
        if (prefix) |value| try validatePrefix(value);
        return .{ .gpa = gpa, .prefix = if (prefix) |value| try gpa.dupe(u8, value) else null };
    }
    pub fn deinit(self: *Names) void {
        if (self.prefix) |value| self.gpa.free(value);
        if (self.mapped) |values| for (values) |value| self.gpa.free(value);
    }
    pub fn clone(self: *const Names, gpa: std.mem.Allocator) !Names {
        if (self.mapped) |values| {
            var mapped: [identifiers.len][]const u8 = undefined;
            var owned: usize = 0;
            errdefer for (mapped[0..owned]) |value| gpa.free(value);
            for (values, 0..) |value, index| {
                mapped[index] = try gpa.dupe(u8, value);
                owned += 1;
            }
            return .{ .gpa = gpa, .prefix = null, .mapped = mapped };
        }
        return init(gpa, self.prefix);
    }
    /// Only explicit identifier placeholders are expanded. SQL literals and
    /// bound values never pass through an identifier substitution.
    pub fn render(self: *const Names, template: []const u8) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(self.gpa);
        var offset: usize = 0;
        while (std.mem.indexOfScalarPos(u8, template, offset, '{')) |start| {
            try output.appendSlice(self.gpa, template[offset..start]);
            const end = std.mem.indexOfScalarPos(u8, template, start + 1, '}') orelse return error.InvalidSqliteIdentifierTemplate;
            const name = template[start + 1 .. end];
            var identifier: ?usize = null;
            for (identifiers, 0..) |candidate, index| if (std.mem.eql(u8, name, candidate)) {
                identifier = index;
                break;
            };
            const index = identifier orelse return error.InvalidSqliteIdentifierTemplate;
            if (self.mapped) |values| {
                try output.appendSlice(self.gpa, values[index]);
            } else {
                try output.appendSlice(self.gpa, self.prefix orelse "");
                try output.appendSlice(self.gpa, name);
            }
            offset = end + 1;
        }
        try output.appendSlice(self.gpa, template[offset..]);
        return output.toOwnedSlice(self.gpa);
    }
};

test "native durable SQLite prefix validates identifiers and preserves default names" {
    const gpa = std.testing.allocator;
    for ([_][]const u8{ "", "a-b", "1bad", "a.b", "a b", "é", "x;DROP" }) |prefix| try std.testing.expectError(error.InvalidSqliteSchemaPrefix, validatePrefix(prefix));
    for ([_][]const u8{ "sqlite_", "SQLITE_x", "SqlItE_tables" }) |prefix| try std.testing.expectError(error.ReservedSqliteSchemaPrefix, validatePrefix(prefix));
    for ([_][]const u8{ "_", "tenant_1", "sqlite", "Pi_" }) |prefix| try validatePrefix(prefix);
    var plain = try Names.init(gpa, null);
    defer plain.deinit();
    const default = try plain.render("SELECT * FROM {entries}");
    defer gpa.free(default);
    try std.testing.expectEqualStrings("SELECT * FROM entries", default);
    var scoped = try Names.init(gpa, "tenant_");
    defer scoped.deinit();
    const sql = try scoped.render("CREATE INDEX {tasks_by_status} ON {tasks}(status)");
    defer gpa.free(sql);
    try std.testing.expectEqualStrings("CREATE INDEX tenant_tasks_by_status ON tenant_tasks(status)", sql);
    try std.testing.expectError(error.InvalidSqliteIdentifierTemplate, scoped.render("SELECT {unknown}"));
}

fn mappedOwnershipExercise(gpa: std.mem.Allocator) !void {
    const borrowed: Names = .{ .gpa = gpa, .prefix = null, .mapped = identifiers };
    var owned = try borrowed.clone(gpa);
    defer owned.deinit();
    const sql = try owned.render("SELECT * FROM {entries}");
    defer gpa.free(sql);
    try std.testing.expectEqualStrings("SELECT * FROM entries", sql);
}
test "native durable SQLite prefix resolved identifier clones unwind every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, mappedOwnershipExercise, .{});
}

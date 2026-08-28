//! Public data model for the native SQLite session repository.
const std = @import("std");

fn freeOptional(gpa: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| gpa.free(bytes);
}

pub const SessionMetadata = struct {
    id: []u8,
    created_at_ms: i64,
    cwd: []u8,
    path: []u8,
    parent_session_id: ?[]u8 = null,
    name: ?[]u8 = null,
    metadata_json: ?[]u8 = null,

    pub fn deinit(self: *SessionMetadata, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.cwd);
        gpa.free(self.path);
        freeOptional(gpa, self.parent_session_id);
        freeOptional(gpa, self.name);
        freeOptional(gpa, self.metadata_json);
        self.* = undefined;
    }
};

pub const CreateSessionOptions = struct {
    id: ?[]const u8 = null,
    created_at_ms: ?i64 = null,
    cwd: []const u8,
    parent_session_id: ?[]const u8 = null,
    metadata_json: ?[]const u8 = null,
};

pub const EntryType = enum {
    message,
    model_change,
    thinking_level_change,
    active_tools_change,
    compaction,
    branch_summary,
    custom,

    pub fn wireName(self: EntryType) []const u8 {
        return switch (self) {
            .message => "message",
            .model_change => "model_change",
            .thinking_level_change => "thinking_level_change",
            .active_tools_change => "active_tools_change",
            .compaction => "compaction",
            .branch_summary => "branch_summary",
            .custom => "custom",
        };
    }

    pub fn parse(value: []const u8) ?EntryType {
        inline for (std.meta.tags(EntryType)) |tag| {
            if (std.mem.eql(u8, value, tag.wireName())) return tag;
        }
        return null;
    }
};

pub const Entry = struct {
    id: []u8,
    seq: i64,
    parent_id: ?[]u8,
    entry_type: EntryType,
    timestamp_ms: i64,
    payload_json: []u8,
    custom_type: ?[]u8 = null,

    pub fn deinit(self: *Entry, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        freeOptional(gpa, self.parent_id);
        gpa.free(self.payload_json);
        freeOptional(gpa, self.custom_type);
        self.* = undefined;
    }
};

pub const AppendEntry = struct {
    id: ?[]const u8 = null,
    parent_id: ?[]const u8 = null,
    entry_type: EntryType,
    timestamp_ms: ?i64 = null,
    payload_json: []const u8,
    custom_type: ?[]const u8 = null,
};

pub const Order = enum { oldest_first, newest_first };

pub const EntryQuery = struct {
    entry_type: ?EntryType = null,
    custom_type: ?[]const u8 = null,
    after_seq: ?i64 = null,
    stop_at_id: ?[]const u8 = null,
    stop_at_type: ?EntryType = null,
    order: Order = .oldest_first,
    limit: ?usize = null,
};

pub const Stats = struct {
    message_count: i64 = 0,
    cached_tokens: f64 = 0,
    uncached_tokens: f64 = 0,
    total_tokens: f64 = 0,
    cost_total: f64 = 0,
};

pub const Usage = struct {
    input: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    total_tokens: f64 = 0,
    cost_total: f64 = 0,
};

pub const Fact = struct {
    seq: i64,
    kind: []u8,
    key: ?[]u8,
    value_json: ?[]u8,

    pub fn deinit(self: *Fact, gpa: std.mem.Allocator) void {
        gpa.free(self.kind);
        freeOptional(gpa, self.key);
        freeOptional(gpa, self.value_json);
        self.* = undefined;
    }
};

pub const WriterLease = struct {
    session_id: []u8,
    owner_id: []u8,
    fence: i64,
    expires_at_ms: i64,

    pub fn deinit(self: *WriterLease, gpa: std.mem.Allocator) void {
        gpa.free(self.session_id);
        gpa.free(self.owner_id);
        self.* = undefined;
    }
};

pub const Lane = struct {
    name: []u8,
    leaf_id: ?[]u8,
    open_operation_id: ?[]u8,

    pub fn deinit(self: *Lane, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        freeOptional(gpa, self.leaf_id);
        freeOptional(gpa, self.open_operation_id);
        self.* = undefined;
    }
};

pub const Record = struct {
    id: []u8,
    seq: i64,
    lane: []u8,
    run_id: ?[]u8,
    record_type: []u8,
    op_kind: ?[]u8,
    timestamp_ms: i64,
    payload_json: []u8,

    pub fn deinit(self: *Record, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.lane);
        freeOptional(gpa, self.run_id);
        gpa.free(self.record_type);
        freeOptional(gpa, self.op_kind);
        gpa.free(self.payload_json);
        self.* = undefined;
    }
};

pub const AppendRecord = struct {
    id: ?[]const u8 = null,
    lane: []const u8 = "main",
    run_id: ?[]const u8 = null,
    record_type: []const u8,
    op_kind: ?[]const u8 = null,
    timestamp_ms: ?i64 = null,
    payload_json: []const u8,
    usage: ?Usage = null,
};

pub const RecordQuery = struct {
    lane: ?[]const u8 = null,
    record_type: ?[]const u8 = null,
    op_kind: ?[]const u8 = null,
    run_id: ?[]const u8 = null,
    after_seq: ?i64 = null,
    order: Order = .oldest_first,
    limit: ?usize = null,
};

pub const LaneMove = struct {
    seq: i64,
    lane: []u8,
    leaf_id: ?[]u8,

    pub fn deinit(self: *LaneMove, gpa: std.mem.Allocator) void {
        gpa.free(self.lane);
        freeOptional(gpa, self.leaf_id);
        self.* = undefined;
    }
};

pub const LogItem = union(enum) {
    entry: Entry,
    record: Record,
    lane: LaneMove,
    fact: Fact,

    pub fn seq(self: *const LogItem) i64 {
        return switch (self.*) {
            .entry => |value| value.seq,
            .record => |value| value.seq,
            .lane => |value| value.seq,
            .fact => |value| value.seq,
        };
    }

    pub fn deinit(self: *LogItem, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .entry => |*value| value.deinit(gpa),
            .record => |*value| value.deinit(gpa),
            .lane => |*value| value.deinit(gpa),
            .fact => |*value| value.deinit(gpa),
        }
        self.* = undefined;
    }
};

pub const LogOptions = struct {
    after_seq: i64 = 0,
    limit: ?usize = null,
};

pub const ForkScope = enum { branch, tree };
pub const ForkPosition = enum { before, at };

pub const ForkOptions = struct {
    id: ?[]const u8 = null,
    cwd: []const u8,
    parent_session_id: ?[]const u8 = null,
    metadata_json: ?[]const u8 = null,
    scope: ForkScope = .branch,
    entry_id: ?[]const u8 = null,
    position: ?ForkPosition = null,
};

pub const SearchHit = struct {
    session_id: []u8,
    entry_id: []u8,
    timestamp_ms: i64,
    score: f64,
    name: ?[]u8,
    cwd: []u8,

    pub fn deinit(self: *SearchHit, gpa: std.mem.Allocator) void {
        gpa.free(self.session_id);
        gpa.free(self.entry_id);
        freeOptional(gpa, self.name);
        gpa.free(self.cwd);
        self.* = undefined;
    }
};

pub const SearchOptions = struct {
    entry_types: ?[]const EntryType = null,
    limit: ?usize = null,
};

test "entry type wire names round-trip" {
    inline for (std.meta.tags(EntryType)) |tag| {
        try std.testing.expectEqual(tag, EntryType.parse(tag.wireName()).?);
    }
    try std.testing.expect(EntryType.parse("unknown") == null);
}

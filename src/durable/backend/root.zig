//! Native durable backend capabilities; legacy session stores remain separate.
const std = @import("std");
pub const json = @import("json.zig");
pub const delta = @import("delta.zig");
pub const memory = @import("memory.zig");
pub const query = @import("query.zig");
pub const sqlite = @import("sqlite.zig");
pub const jsonl = @import("jsonl.zig");
pub const Backend = union(enum) {
    memory: *memory.Memory,
    sqlite: *sqlite.Sqlite,
    jsonl: *jsonl.Jsonl,
    pub fn mintId(self: Backend) !u64 {
        return switch (self) {
            .memory => |store| store.mintId(),
            .sqlite => |store| store.mintId(),
            .jsonl => |store| store.mintId(),
        };
    }
    pub fn commitAt(self: Backend, writes: json.Value, seq: ?u64) !u64 {
        return switch (self) {
            .memory => |store| blk: {
                var prepared = try store.prepare(writes, seq);
                defer prepared.deinit();
                break :blk try prepared.apply();
            },
            .sqlite => |store| store.commitAt(writes, seq),
            .jsonl => |store| store.commitAt(writes, seq, .{}),
        };
    }
    pub fn snapshot(self: Backend, gpa: std.mem.Allocator) !*memory.State {
        return switch (self) {
            .memory => |store| store.state.duplicate(gpa),
            .sqlite => |store| store.snapshot(gpa),
            .jsonl => |store| store.snapshot(gpa),
        };
    }
    pub fn readRecord(self: Backend, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        return switch (self) {
            .memory => |store| store.readRecord(gpa, id),
            .sqlite => |store| store.readRecord(gpa, id),
            .jsonl => |store| store.readRecord(gpa, id),
        };
    }
    pub fn readTableRecord(self: Backend, gpa: std.mem.Allocator, table: memory.Table, id: u64) !?json.Owned {
        return switch (self) {
            .memory => |store| blk: {
                const row = store.state.rows.get(id) orelse break :blk null;
                if (row.table != table) break :blk null;
                break :blk try store.readRecord(gpa, id);
            },
            .sqlite => |store| store.readTableRecord(gpa, table, id),
            .jsonl => |store| store.readTableRecord(gpa, table, id),
        };
    }
    pub fn readEntry(self: Backend, gpa: std.mem.Allocator, id: u64, conversation: ?u64) !?json.Owned {
        return switch (self) {
            .memory => |store| query.entry(gpa, store, id, conversation),
            .sqlite => |store| store.readEntry(gpa, id, conversation),
            .jsonl => |store| store.readEntry(gpa, id, conversation),
        };
    }
    pub fn readDocument(self: Backend, gpa: std.mem.Allocator, id: u64, at: memory.Point) !?json.Owned {
        return switch (self) {
            .memory => |store| store.readDocument(gpa, id, at),
            .sqlite => |store| store.readDocument(gpa, id, at),
            .jsonl => |store| store.readDocument(gpa, id, at),
        };
    }
    pub fn scan(self: Backend, gpa: std.mem.Allocator, parameters: query.Query) !json.Owned {
        return switch (self) {
            .memory => |store| query.scan(gpa, store, parameters),
            .sqlite => |store| store.scan(gpa, parameters),
            .jsonl => |store| store.scan(gpa, parameters),
        };
    }
};

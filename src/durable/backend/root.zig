//! Native durable backend capabilities; legacy session stores remain separate.
const std = @import("std");
pub const json = @import("json.zig");
pub const delta = @import("delta.zig");
pub const memory = @import("memory.zig");
pub const query = @import("query.zig");
pub const sqlite = @import("sqlite.zig");
pub const sqlite_source = @import("sqlite_source.zig");
pub const jsonl = @import("jsonl.zig");
/// An owned caller supplies lifetime and synchronization. VM adapters must
/// marshal calls to their owner before entering this native capability.
pub const Custom = struct {
    context: ?*anyopaque,
    vtable: *const VTable,
    callbacks_on_owner: bool = false,
    pub const VTable = struct {
        mintId: *const fn (?*anyopaque) anyerror!u64,
        commitAt: *const fn (?*anyopaque, json.Value, ?u64) anyerror!u64,
        snapshot: *const fn (?*anyopaque, std.mem.Allocator) anyerror!*memory.State,
        readRecord: *const fn (?*anyopaque, std.mem.Allocator, u64) anyerror!?json.Owned,
        readTableRecord: *const fn (?*anyopaque, std.mem.Allocator, memory.Table, u64) anyerror!?json.Owned,
        readEntry: *const fn (?*anyopaque, std.mem.Allocator, u64, ?u64) anyerror!?json.Owned,
        readDocument: *const fn (?*anyopaque, std.mem.Allocator, u64, memory.Point) anyerror!?json.Owned,
        scan: *const fn (?*anyopaque, std.mem.Allocator, query.Query) anyerror!json.Owned,
    };
};
pub const Backend = union(enum) {
    memory: *memory.Memory,
    sqlite: *sqlite.Sqlite,
    sqlite_source: *sqlite_source.Sqlite,
    jsonl: *jsonl.Jsonl,
    custom: Custom,
    pub fn mintId(self: Backend) !u64 {
        return switch (self) {
            .memory => |store| store.mintId(),
            .sqlite => |store| store.mintId(),
            .sqlite_source => |store| store.mintId(),
            .jsonl => |store| store.mintId(),
            .custom => |store| store.vtable.mintId(store.context),
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
            .sqlite_source => |store| store.commitAt(writes, seq),
            .jsonl => |store| store.commitAt(writes, seq, .{}),
            .custom => |store| store.vtable.commitAt(store.context, writes, seq),
        };
    }
    pub fn snapshot(self: Backend, gpa: std.mem.Allocator) !*memory.State {
        return switch (self) {
            .memory => |store| store.state.duplicate(gpa),
            .sqlite => |store| store.snapshot(gpa),
            .sqlite_source => |store| store.snapshot(gpa),
            .jsonl => |store| store.snapshot(gpa),
            .custom => |store| store.vtable.snapshot(store.context, gpa),
        };
    }
    pub fn readRecord(self: Backend, gpa: std.mem.Allocator, id: u64) !?json.Owned {
        return switch (self) {
            .memory => |store| store.readRecord(gpa, id),
            .sqlite => |store| store.readRecord(gpa, id),
            .sqlite_source => |store| store.readRecord(gpa, id),
            .jsonl => |store| store.readRecord(gpa, id),
            .custom => |store| store.vtable.readRecord(store.context, gpa, id),
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
            .sqlite_source => |store| store.readTableRecord(gpa, table, id),
            .jsonl => |store| store.readTableRecord(gpa, table, id),
            .custom => |store| store.vtable.readTableRecord(store.context, gpa, table, id),
        };
    }
    pub fn readEntry(self: Backend, gpa: std.mem.Allocator, id: u64, conversation: ?u64) !?json.Owned {
        return switch (self) {
            .memory => |store| query.entry(gpa, store, id, conversation),
            .sqlite => |store| store.readEntry(gpa, id, conversation),
            .sqlite_source => |store| store.readEntry(gpa, id, conversation),
            .jsonl => |store| store.readEntry(gpa, id, conversation),
            .custom => |store| store.vtable.readEntry(store.context, gpa, id, conversation),
        };
    }
    pub fn readDocument(self: Backend, gpa: std.mem.Allocator, id: u64, at: memory.Point) !?json.Owned {
        return switch (self) {
            .memory => |store| store.readDocument(gpa, id, at),
            .sqlite => |store| store.readDocument(gpa, id, at),
            .sqlite_source => |store| store.readDocument(gpa, id, at),
            .jsonl => |store| store.readDocument(gpa, id, at),
            .custom => |store| store.vtable.readDocument(store.context, gpa, id, at),
        };
    }
    pub fn scan(self: Backend, gpa: std.mem.Allocator, parameters: query.Query) !json.Owned {
        return switch (self) {
            .memory => |store| query.scan(gpa, store, parameters),
            .sqlite => |store| store.scan(gpa, parameters),
            .sqlite_source => |store| store.scan(gpa, parameters),
            .jsonl => |store| store.scan(gpa, parameters),
            .custom => |store| store.vtable.scan(store.context, gpa, parameters),
        };
    }
};

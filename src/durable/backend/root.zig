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
        findDocument: ?*const fn (?*anyopaque, std.mem.Allocator, json.Value, memory.Point) anyerror!?json.Owned = null,
        sourceScan: ?*const fn (?*anyopaque, std.mem.Allocator, memory.Table, json.Value, u64, ?json.Value) anyerror!json.Owned = null,
        latestHeadMarker: ?*const fn (?*anyopaque, std.mem.Allocator, u64, ?u64) anyerror!?json.Owned = null,
        submissionByRequest: ?*const fn (?*anyopaque, std.mem.Allocator, u64, []const u8) anyerror!?json.Owned = null,
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
    pub fn findDocument(self: Backend, gpa: std.mem.Allocator, address: json.Value, point: memory.Point) !?json.Owned {
        if (self == .custom) if (self.custom.vtable.findDocument) |read| return read(self.custom.context, gpa, address, point);
        var view: memory.Memory = .{ .gpa = gpa, .state = try self.snapshot(gpa) };
        defer view.deinit();
        return query.findDocument(gpa, &view, address, point);
    }
    pub fn sourceScan(self: Backend, gpa: std.mem.Allocator, table: memory.Table, filters: json.Value, limit: u64, cursor: ?json.Value) !json.Owned {
        if (self == .custom) if (self.custom.vtable.sourceScan) |read| return read(self.custom.context, gpa, table, filters, limit, cursor);
        var view: memory.Memory = .{ .gpa = gpa, .state = try self.snapshot(gpa) };
        defer view.deinit();
        return @import("source_scan.zig").scan(gpa, &view, table, filters, limit, cursor);
    }
    pub fn latestHeadMarker(self: Backend, gpa: std.mem.Allocator, conversation: u64, before: ?u64) !?json.Owned {
        if (self == .custom) if (self.custom.vtable.latestHeadMarker) |read| return read(self.custom.context, gpa, conversation, before);
        var view: memory.Memory = .{ .gpa = gpa, .state = try self.snapshot(gpa) };
        defer view.deinit();
        return @import("source_scan.zig").latestHead(gpa, &view, conversation, before);
    }
    pub fn submissionByRequest(self: Backend, gpa: std.mem.Allocator, conversation: u64, request: []const u8) !?json.Owned {
        if (self == .custom) if (self.custom.vtable.submissionByRequest) |read| return read(self.custom.context, gpa, conversation, request);
        const view = try self.snapshot(gpa);
        defer view.destroy(gpa);
        const key = try memory.requestKey(gpa, .{ .integer = @intCast(conversation) }, .{ .string = request });
        defer gpa.free(key);
        const id = view.submissionRequests.get(key) orelse return null;
        const row = view.rows.get(id) orelse return null;
        var result = try json.Owned.empty(gpa);
        errdefer result.deinit();
        result.value = try json.clone(result.arena.allocator(), row.record);
        return result;
    }
};

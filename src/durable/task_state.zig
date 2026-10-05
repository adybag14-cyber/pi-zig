//! Durable task records and ownership walks, pinned to Pi b7dfc049 spec §5.
const std = @import("std");
const backend = @import("backend/root.zig");
pub const json = backend.json;
pub const Value = json.Value;
pub const Status = enum { pending, running, waiting, completing, terminal };
pub fn field(v: Value, key: []const u8) !Value {
    return json.required(v, key);
}
pub fn number(v: Value, key: []const u8) !u64 {
    return json.asInteger(try field(v, key));
}
pub fn text(v: Value, key: []const u8) ![]const u8 {
    return json.asString(try field(v, key));
}
pub fn flag(v: Value, key: []const u8) !bool {
    const value = try field(v, key);
    if (value != .bool) return error.InvalidTaskBoolean;
    return value.bool;
}
pub fn status(v: Value) !Status {
    return std.meta.stringToEnum(Status, try text(try field(v, "state"), "status")) orelse error.InvalidTaskStatus;
}
pub fn live(v: Value) !bool {
    return try status(v) != .terminal;
}
pub fn failed(v: Value) !bool {
    const s = try status(v);
    if (s != .completing and s != .terminal) return false;
    return !std.mem.eql(u8, try text(try field(try field(v, "state"), "outcome"), "status"), "completed");
}
pub fn cancellation(v: Value) !bool {
    return try live(v) and (try flag(v, "abortRequested") or try failed(v));
}
pub fn validate(v: Value) !void {
    _ = try number(v, "id");
    _ = try number(v, "conversationId");
    if ((try text(v, "kind")).len == 0 or try number(v, "version") == 0) return error.InvalidTaskDefinition;
    _ = try field(v, "input");
    _ = try flag(v, "background");
    _ = try flag(v, "abortRequested");
    if (json.get(v, "owner")) |owner| {
        _ = try json.asInteger(owner);
        if (try flag(v, "background")) return error.BackgroundChildTask;
    }
    const state = try field(v, "state");
    switch (try status(v)) {
        .pending, .running, .waiting => {
            if ((try text(try field(state, "checkpoint"), "phase")).len == 0) return error.InvalidTaskCheckpoint;
            if (try status(v) == .waiting) {
                const on = try field(state, "on");
                if (on != .array) return error.InvalidTaskWait;
                for (on.array.items) |id| _ = try json.asInteger(id);
                const policy = try text(state, "policy");
                if (!std.mem.eql(u8, policy, "failFast") and !std.mem.eql(u8, policy, "allSettled")) return error.InvalidTaskWait;
            }
        },
        .completing, .terminal => {
            const outcome = try field(state, "outcome");
            const kind = try text(outcome, "status");
            if (std.mem.eql(u8, kind, "completed")) {
                _ = try field(outcome, "result");
            } else if (std.mem.eql(u8, kind, "failed") or std.mem.eql(u8, kind, "faulted")) {
                _ = try field(outcome, "error");
            } else if (std.mem.eql(u8, kind, "aborted") or std.mem.eql(u8, kind, "orphaned")) {
                _ = try field(outcome, "reason");
            } else return error.InvalidTaskOutcome;
        },
    }
}
pub fn object(gpa: std.mem.Allocator) Value {
    _ = gpa;
    return .{ .object = .empty };
}
pub fn withState(gpa: std.mem.Allocator, record: Value, state: Value) !Value {
    var next = try json.clone(gpa, record);
    try next.object.put(gpa, "state", try json.clone(gpa, state));
    const name = try text(state, "status");
    if (std.mem.eql(u8, name, "terminal") or std.mem.eql(u8, name, "completing")) _ = next.object.orderedRemove("memos");
    return next;
}
pub fn checkpointState(gpa: std.mem.Allocator, name: []const u8, checkpoint: Value) !Value {
    var state = object(gpa);
    try state.object.put(gpa, "status", .{ .string = name });
    try state.object.put(gpa, "checkpoint", checkpoint);
    return state;
}
pub fn outcomeState(gpa: std.mem.Allocator, name: []const u8, outcome: Value) !Value {
    var state = object(gpa);
    try state.object.put(gpa, "status", .{ .string = name });
    try state.object.put(gpa, "outcome", outcome);
    return state;
}
pub fn makeOutcome(gpa: std.mem.Allocator, name: []const u8, value: Value) !Value {
    var result = object(gpa);
    try result.object.put(gpa, "status", .{ .string = name });
    try result.object.put(gpa, if (std.mem.eql(u8, name, "completed")) "result" else if (std.mem.eql(u8, name, "failed") or std.mem.eql(u8, name, "faulted")) "error" else "reason", value);
    return result;
}
pub const Up = union(enum) { task: u64, conversation: u64 };
pub fn parent(v: Value) !Up {
    return if (json.get(v, "owner")) |owner| .{ .task = try json.asInteger(owner) } else .{ .conversation = try number(v, "conversationId") };
}
pub const Graph = struct {
    state: *const backend.memory.State,
    pub fn task(self: Graph, id: u64) !Value {
        const row = self.state.rows.get(id) orelse return error.UnknownTask;
        if (row.table != .task) return error.UnknownTask;
        return row.record;
    }
    fn next(self: Graph, at: Up) !?Up {
        return switch (at) {
            .task => |id| try parent(try self.task(id)),
            .conversation => |id| blk: {
                const row = self.state.rows.get(id) orelse return error.UnknownConversation;
                if (row.table != .conversation) return error.UnknownConversation;
                const owner = json.get(row.record, "owner") orelse break :blk null;
                break :blk .{ .task = try number(owner, "taskId") };
            },
        };
    }
    pub fn reaches(self: Graph, start: Up, wanted: Up, crossBackground: bool) !bool {
        var at: ?Up = start;
        var remaining = self.state.rows.count() + 1;
        while (at) |step| {
            if (remaining == 0) return error.TaskOwnershipCycle;
            remaining -= 1;
            if (std.meta.eql(step, wanted)) return true;
            if (step == .task and !crossBackground and try flag(try self.task(step.task), "background")) return false;
            at = try self.next(step);
        }
        return false;
    }
    pub fn hasOwnedLive(self: Graph, id: u64) !bool {
        var rows = self.state.rows.iterator();
        while (rows.next()) |item| {
            const row = item.value_ptr.*;
            if (row.table != .task or !try live(row.record) or try flag(row.record, "background")) continue;
            if (try self.reaches(try parent(row.record), .{ .task = id }, false)) return true;
        }
        return false;
    }
    pub fn belowCancelled(self: Graph, start: Up) !bool {
        var at: ?Up = start;
        var remaining = self.state.rows.count() + 1;
        while (at) |step| {
            if (remaining == 0) return error.TaskOwnershipCycle;
            remaining -= 1;
            if (step == .task) {
                const record = try self.task(step.task);
                if (try cancellation(record)) return true;
                if (try flag(record, "background")) return false;
            }
            at = try self.next(step);
        }
        return false;
    }
    pub fn waitingOn(self: Graph, record: Value) !bool {
        if (try status(record) != .waiting) return false;
        for ((try field(try field(record, "state"), "on")).array.items) |member| {
            if (try live(try self.task(try json.asInteger(member)))) return true;
        }
        return false;
    }
};

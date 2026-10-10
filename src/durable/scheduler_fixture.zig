//! Abrupt-exit fixture: a real process exits after durable reservation, without Zig defers.
const std = @import("std");
const backend = @import("backend/root.zig");
const session_mod = @import("session.zig");
const scheduler_mod = @import("scheduler.zig");
const types = @import("types.zig");
const model = @import("task_state.zig");
fn seed(_: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !backend.json.Value {
    _ = try tx.createRootConversation();
    const checkpoint = try backend.json.parseLeaky(tx.owned.arena.allocator(), "{\"phase\":\"start\",\"count\":7}");
    return .{ .integer = @intCast(try tx.createTask("crash", 1, .null, checkpoint, .{ .conversationId = 1 })) };
}
fn crash(_: ?*anyopaque, _: *scheduler_mod.Runtime, _: backend.json.Value, _: types.Context) !void {
    std.process.exit(86);
}
fn abortTask(_: ?*anyopaque, runtime: *scheduler_mod.Runtime, _: backend.json.Value, _: types.Context) !void {
    const Change = struct {
        fn apply(_: ?*anyopaque, tx: *session_mod.Transaction, _: backend.json.Value) !?backend.json.Value {
            return try model.outcomeState(tx.owned.arena.allocator(), "terminal", try model.makeOutcome(tx.owned.arena.allocator(), "aborted", .null));
        }
    };
    try runtime.commit(Change.apply, null);
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.FixtureDatabaseRequired;
    var store = try backend.sqlite.Sqlite.open(init.gpa, init.io, args[1], .{});
    defer store.deinit();
    var session = session_mod.Session.init(init.gpa, init.io, .{ .sqlite = store });
    defer session.deinit();
    var scheduler = try scheduler_mod.Scheduler.init(init.gpa, init.io, &session, .{ .max_workers = 1 });
    defer scheduler.deinit();
    try scheduler.register(.{ .name = "crash", .version = 1, .phases = &.{.{ .name = "start", .run = crash }}, .abort = abortTask });
    var result = try session.commit(seed, null, .{}, .{});
    result.deinit();
    try scheduler.open();
    scheduler.enable();
    _ = try scheduler.drive();
    return error.CrashFixtureUnexpectedlyReturned;
}

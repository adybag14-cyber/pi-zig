//! Native process fixture for original SQLite interoperability; data only input.
const std = @import("std");
const sqlite = @import("durable/backend/sqlite_source.zig");
const json = @import("durable/backend/json.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.FixturePathAndModeRequired;
    if (std.mem.eql(u8, args[2], "private-seed")) {
        const store = try @import("durable/backend/sqlite.zig").Sqlite.open(init.gpa, init.io, args[1], .{});
        defer store.deinit();
        return write(init.gpa, store, "seed");
    }
    const store = try sqlite.Sqlite.open(init.gpa, init.io, args[1], .{});
    defer store.deinit();
    if (std.mem.eql(u8, args[2], "migrate")) return;
    return write(init.gpa, store, args[2]);
}
fn write(gpa: std.mem.Allocator, store: anytype, mode: []const u8) !void {
    var writes = try json.Owned.parse(gpa, if (std.mem.eql(u8, mode, "seed"))
        \\[{"type":"conversation","value":{"id":1}},{"type":"entry","value":{"id":2,"conversationId":1,"kind":"user","data":{"text":"Ω\ud800"},"head":2}},{"type":"task","value":{"id":3,"kind":"fixture.Ω\ud800","version":1,"conversationId":1,"input":{"n":1},"background":false,"abortRequested":false,"state":{"status":"pending","checkpoint":{"phase":"go"}}}},{"type":"submission","value":{"id":4,"conversationId":1,"requestId":"request\ud800","status":"queued","data":{"text":"hello"}}},{"type":"document.create","record":{"id":5,"kind":"doc.Ω\ud800","key":"key\ud800","scope":{"kind":"conversation","conversationId":1},"history":"rewindable","fork":"asOf"},"content":{"version":1,"kind":"base","value":{"n":1,"s":"A😀B"}}}]
    else if (std.mem.eql(u8, mode, "append"))
        \\[{"type":"entry","value":{"id":6,"conversationId":1,"kind":"native","head":6,"data":{"text":"你好\udfff"}}},{"type":"document.change","id":5,"content":{"version":1,"kind":"delta","ops":[["s",["n"],9],["a",["s"],"Z"]]}}]
    else
        return error.InvalidFixtureMode);
    defer writes.deinit();
    _ = try store.commitAt(writes.value, null);
    if (std.mem.eql(u8, mode, "seed")) {
        var delta = try json.Owned.parse(gpa, "[{\"type\":\"document.change\",\"id\":5,\"content\":{\"version\":1,\"kind\":\"delta\",\"ops\":[[\"s\",[\"n\"],2],[\"a\",[\"s\"],\"Ω\"]]}}]");
        defer delta.deinit();
        _ = try store.commitAt(delta.value, null);
    }
}

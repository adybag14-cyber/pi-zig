//! Independent artifact producer/reader used only for original interop gates.
const std = @import("std");
const implementation = @import("durable/backend/jsonl.zig");
const json = implementation.json;
const local = @import("durable/execution_env.zig");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.ExpectedModeAndDirectory;
    var environ = try std.process.Environ.createMap(init.minimal.environ, init.gpa);
    defer environ.deinit();
    var provider = try local.ExecutionEnv.init(init.gpa, init.io, .{ .cwd = args[2], .environ = &environ, .temp_dir = args[2] });
    defer provider.deinit();
    var store = try implementation.Jsonl.open(init.gpa, ".", &provider, .{}, .{ .fsync = true });
    defer store.deinit();
    if (std.mem.eql(u8, args[1], "write")) {
        var capture = try json.Owned.parse(init.gpa, @embedFile("durable/fixtures/jsonl-7fb59f9.json"));
        defer capture.deinit();
        for (capture.value.object.get("cases").?.array.items[0].object.get("commits").?.array.items) |writes| {
            _ = try store.commit(writes, .{});
        }
    } else if (!std.mem.eql(u8, args[1], "read")) return error.InvalidFixtureMode;
    var output = try json.Owned.empty(init.gpa);
    defer output.deinit();
    const allocator = output.arena.allocator();
    var value: json.Value = .{ .object = .empty };
    var task = (try store.task(init.gpa, 2)).?;
    defer task.deinit();
    var document = (try store.document(init.gpa, 4, .current)).?;
    defer document.deinit();
    var copy = (try store.document(init.gpa, 5, .current)).?;
    defer copy.deinit();
    try value.object.put(allocator, "task", try json.clone(allocator, task.value));
    try value.object.put(allocator, "document", try json.clone(allocator, document.value));
    try value.object.put(allocator, "copy", try json.clone(allocator, copy.value));
    try value.object.put(allocator, "nextId", .{ .integer = @intCast(try store.mintId()) });
    const encoded = try json.stringify(init.gpa, value);
    defer init.gpa.free(encoded);
    try std.Io.File.stdout().writeStreamingAll(init.io, encoded);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

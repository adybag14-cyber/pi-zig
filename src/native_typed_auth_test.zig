const std = @import("std");
const json = @import("mcp/protocol.zig").json;
fn exercise(gpa: std.mem.Allocator) !void {
    var fixture = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/typed-auth-6fb2e78.json"));
    defer fixture.deinit();
    const model = blk: {
        for (@import("ai/providers.zig").all_models) |row| if (row.kind == .classifier and std.mem.eql(u8, row.providerName(), "typesafe") and std.mem.eql(u8, row.id, "jev-latest")) break :blk row;
        return error.MissingSourceClassifier;
    };
    for (fixture.value.array.items) |row| {
        const input = row.object.get("input").?;
        var env: std.process.Environ.Map = .init(gpa);
        defer env.deinit();
        var entries = input.object.get("env").?.object.iterator();
        while (entries.next()) |entry| try env.put(entry.key_ptr.*, entry.value_ptr.string);
        const explicit = input.object.get("explicit");
        var resolved = try @import("coding_agent/typed_model_auth.zig").resolve(gpa, std.testing.io, &env, model, .null, input.object.get("config") orelse .null, input.object.get("stored"), if (explicit) |value| value.string else null);
        defer resolved.deinit();
        if (!json.equal(row.object.get("result").?, resolved.value)) {
            const actual = try json.stringify(gpa, resolved.value);
            defer gpa.free(actual);
            std.debug.print("typed auth actual {s}\n", .{actual});
            return error.TypedAuthSourceMismatch;
        }
    }
}
test "typed auth Source stored configured explicit environment and kind scoped private headers" {
    try exercise(std.testing.allocator);
}
test "typed auth releases every failed allocation" {
    const Sweep = struct {
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                return if (err == error.WriteFailed and failing.has_induced_failure) error.OutOfMemory else err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Sweep.run, .{});
}

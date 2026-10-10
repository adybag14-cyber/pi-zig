const std = @import("std");
const json = @import("mcp/protocol.zig").json;
const typed = @import("coding_agent/typed_model_registry.zig");
const registry_mod = @import("extensions/provider_registry.zig");
const models = @import("mcp/codemode_models.zig");
fn expectRetired(result: anyerror!json.Owned) !void {
    var value = result catch |err| {
        if (err == error.TypedRegistryOwnerRetired) return;
        return err;
    };
    defer value.deinit();
    return error.ExpectedRetiredRegistry;
}
const Backend = struct {
    registry: *registry_mod.Registry,
    owner: ?*typed.Owner = null,
    retire: bool = false,
    fn available(_: ?*anyopaque, gpa: std.mem.Allocator, rows: []const typed.Snapshot, _: ?*bool) !json.Owned {
        var result = try json.Owned.empty(gpa);
        errdefer result.deinit();
        const a = result.arena.allocator();
        result.value = .{ .array = .init(a) };
        for (rows) |row| try result.value.array.append(try json.clone(a, row.value));
        return result;
    }
    fn operate(raw: ?*anyopaque, gpa: std.mem.Allocator, row: *const typed.Snapshot, _: models.Operation, _: json.Value, _: ?*bool) !json.Owned {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try self.registry.registerJson("typed", "{\"models\":[]}");
        // The previous registration and its arrays have been freed. Every model
        // field/configuration in this operation must still be privately owned.
        try std.testing.expectEqualStrings("Class", row.info.display);
        try std.testing.expectEqualStrings("fixture-classifier", row.info.operation_api.?);
        if (self.retire) self.owner.?.retire();
        var result = try json.Owned.empty(gpa);
        errdefer result.deinit();
        result.value = try json.clone(result.arena.allocator(), row.value);
        return result;
    }
};
fn exercise(gpa: std.mem.Allocator) !void {
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    var registry = registry_mod.Registry.initAll(gpa, std.testing.io, &env, null, &.{}, &.{}, &.{});
    defer registry.deinit();
    var backend: Backend = .{ .registry = &registry };
    var owner: typed.Owner = .{ .io = std.testing.io, .backend = .{ .context = &backend, .operate = Backend.operate, .available = Backend.available } };
    defer owner.retire();
    backend.owner = &owner;
    try owner.bind(&registry);
    const entry = owner.runtime();
    const runtime = try entry.acquire.?(entry.context, gpa);
    defer runtime.release.?(runtime.context, gpa);
    var configs = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/typed-catalog-configs-6fb2e78.json"));
    defer configs.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/typed-catalog-6fb2e78.json"));
    defer expected.deinit();
    for (configs.value.array.items, expected.value.array.items) |config, rows| {
        const bytes = try json.stringify(gpa, config);
        defer gpa.free(bytes);
        try registry.registerJson("typed", bytes);
        for ([_]models.Operation{ .getModelsOfType, .getAvailableOfType }) |op| for ([_][]const u8{ "classifier", "image" }) |kind| {
            var args = try json.Owned.empty(gpa);
            defer args.deinit();
            const a = args.arena.allocator();
            args.value = .{ .array = .init(a) };
            try args.value.array.appendSlice(&.{ .{ .string = kind }, .{ .string = "typed" } });
            var result = try runtime.invoke(runtime.context, gpa, op, args.value, null);
            defer result.deinit();
            var wanted = try json.Owned.empty(gpa);
            defer wanted.deinit();
            wanted.value = .{ .array = .init(wanted.arena.allocator()) };
            for (rows.array.items) |row| if (std.mem.eql(u8, row.object.get("type").?.string, kind)) try wanted.value.array.append(try json.clone(wanted.arena.allocator(), row));
            try std.testing.expect(json.equal(wanted.value, result.value));
        };
    }
    const first = try json.stringify(gpa, configs.value.array.items[0]);
    defer gpa.free(first);
    try registry.registerJson("typed", first);
    var operation = try json.Owned.parse(gpa, "[{\"provider\":\"typed\",\"id\":\"same\"},{}]");
    defer operation.deinit();
    var captured = try runtime.invoke(runtime.context, gpa, .classify, operation.value, null);
    defer captured.deinit();
    try std.testing.expect(json.equal(expected.value.array.items[0].array.items[0], captured.value));
    try registry.registerJson("typed", first);
    backend.retire = true;
    try expectRetired(runtime.invoke(runtime.context, gpa, .classify, operation.value, null));
    try expectRetired(runtime.invoke(runtime.context, gpa, .getModelsOfType, operation.value, null));
    try owner.bind(&registry);
    try expectRetired(runtime.invoke(runtime.context, gpa, .getModelsOfType, operation.value, null));
}
test "typed registry owner Source catalog snapshots survive replacement and private generation retires" {
    try exercise(std.testing.allocator);
}
test "typed registry owner releases every failed snapshot allocation" {
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

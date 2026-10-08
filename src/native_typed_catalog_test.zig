const std = @import("std");
const registry_mod = @import("extensions/provider_registry.zig");
fn exercise(gpa: std.mem.Allocator) !void {
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    const baseline = [_]@import("ai/providers.zig").ModelInfo{.{ .kind = .image, .provider = .openrouter, .provider_id = "other", .id = "same", .display = "Unrelated", .operation_api = "openrouter-images", .base_url = "https://other.invalid" }};
    var registry = registry_mod.Registry.initAll(gpa, std.testing.io, &env, null, &.{}, &baseline, &.{});
    defer registry.deinit();
    var fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/typed-catalog-configs-6fb2e78.json"), .{});
    defer fixture.deinit();
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try output.writer.writeByte('[');
    for (fixture.value.array.items, 0..) |config, index| {
        const bytes = try std.json.Stringify.valueAlloc(gpa, config, .{});
        defer gpa.free(bytes);
        try registry.registerJson("typed", bytes);
        if (index != 0) try output.writer.writeByte(',');
        try output.writer.writeByte('[');
        var wrote = false;
        for (registry.allCatalog()) |model| if (std.mem.eql(u8, model.providerName(), "typed")) {
            if (wrote) try output.writer.writeByte(',');
            wrote = true;
            try output.writer.writeAll(model.source_metadata_json.?);
        };
        try output.writer.writeByte(']');
        try std.testing.expectEqual(@as(usize, 0), registry.catalog().len);
    }
    try output.writer.writeByte(']');
    try std.testing.expectEqualStrings(std.mem.trim(u8, @embedFile("extensions/fixtures/typed-catalog-6fb2e78.json"), "\r\n"), output.written());
}
test "typed catalog Source all metadata replacements and same id kind collision" {
    try exercise(std.testing.allocator);
}
test "typed catalog releases every failed registration allocation" {
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

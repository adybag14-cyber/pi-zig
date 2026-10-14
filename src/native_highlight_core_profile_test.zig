//! Separate allocation measurement; this never replaces the full GPA checker.
const std = @import("std");
test "native highlight inline profile unchanged actual74 full body and allocation baseline measurement only" {
    var counter = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try @import("native_highlight_core_b45_test.zig").exercise(counter.allocator());
    try std.testing.expectEqual(counter.allocated_bytes, counter.freed_bytes);
    std.debug.print("HIGHLIGHT_INLINE_PROFILE actual_source_cases=74 eager_factories=21 baseline={d} allocated_bytes={d} freed_bytes={d} full_GPA=false\n", .{ counter.alloc_index, counter.allocated_bytes, counter.freed_bytes });
}

//! Canonical coverage for all original CodeMode, worker-owner and TUI failures.
const std = @import("std");
const runtime = @import("agent_allocation_coverage.zig");
pub const graphs = [_][]const u8{ "codemode-host", "codemode-workers", "codemode-discovery", "codemode-adapter", "codemode-vm-owner", "tui-alt", "codemode-controlled-run" };
pub const State = runtime.StateFor(&graphs, "EXHAUSTIVE_ALLOCATION", null, true);

pub fn verifyDirectory(gpa: std.mem.Allocator, io: std.Io, directory: []const u8, shards: usize, group: usize, groups: usize) !void {
    return runtime.verifyDirectoryFor(State, gpa, io, directory, shards, group, groups, "exhaustive-range", "exhaustive-coverage.json");
}

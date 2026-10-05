//! Upstream ExtensionRunner command invocation-name resolution.
const std = @import("std");
pub const Registration = struct { owner_index: usize, name: []const u8 };
pub const Resolved = struct { owner_index: usize, name: []const u8, invocation_name: []u8 };

pub fn deinit(gpa: std.mem.Allocator, values: []Resolved) void {
    for (values) |value| gpa.free(value.invocation_name);
    gpa.free(values);
}

pub fn resolve(gpa: std.mem.Allocator, registrations: []const Registration) ![]Resolved {
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    defer counts.deinit(gpa);
    var seen: std.StringHashMapUnmanaged(usize) = .empty;
    defer seen.deinit(gpa);
    var taken: std.StringHashMapUnmanaged(void) = .empty;
    defer taken.deinit(gpa);
    for (registrations) |registration| {
        const count = try counts.getOrPut(gpa, registration.name);
        if (!count.found_existing) count.value_ptr.* = 0;
        count.value_ptr.* += 1;
    }
    const results = try gpa.alloc(Resolved, registrations.len);
    var populated: usize = 0;
    errdefer {
        for (results[0..populated]) |value| gpa.free(value.invocation_name);
        gpa.free(results);
    }
    for (registrations, results) |registration, *result| {
        const occurrence = try seen.getOrPut(gpa, registration.name);
        if (!occurrence.found_existing) occurrence.value_ptr.* = 0;
        occurrence.value_ptr.* += 1;
        var suffix = occurrence.value_ptr.*;
        var invocation = if (counts.get(registration.name).? > 1) try std.fmt.allocPrint(gpa, "{s}:{d}", .{ registration.name, suffix }) else try gpa.dupe(u8, registration.name);
        var transferred = false;
        errdefer if (!transferred) gpa.free(invocation);
        while (taken.contains(invocation)) {
            suffix += 1;
            const replacement = try std.fmt.allocPrint(gpa, "{s}:{d}", .{ registration.name, suffix });
            gpa.free(invocation);
            invocation = replacement;
        }
        try taken.put(gpa, invocation, {});
        result.* = .{ .owner_index = registration.owner_index, .name = registration.name, .invocation_name = invocation };
        populated += 1;
        transferred = true;
    }
    return results;
}

test "command aliases match actual upstream reserved before after multiple collisions and unload" {
    const Case = struct { names: []const []const u8, expected: []const []const u8 };
    const cases = [_]Case{
        .{ .names = &.{ "same", "same" }, .expected = &.{ "same:1", "same:2" } },
        .{ .names = &.{ "same:1", "same", "same" }, .expected = &.{ "same:1", "same:2", "same:3" } },
        .{ .names = &.{ "same", "same", "same:1" }, .expected = &.{ "same:1", "same:2", "same:1:2" } },
        .{ .names = &.{ "same:1", "same:2", "same", "same", "same" }, .expected = &.{ "same:1", "same:2", "same:3", "same:4", "same:5" } },
        .{ .names = &.{"same"}, .expected = &.{"same"} },
    };
    for (cases) |case| {
        const registrations = try std.testing.allocator.alloc(Registration, case.names.len);
        defer std.testing.allocator.free(registrations);
        for (case.names, registrations, 0..) |name, *registration, i| registration.* = .{ .name = name, .owner_index = i };
        const results = try resolve(std.testing.allocator, registrations);
        defer deinit(std.testing.allocator, results);
        for (case.expected, results) |expected, actual| try std.testing.expectEqualStrings(expected, actual.invocation_name);
    }
}

test "command alias allocation failures retain all borrowed registration names" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const names = [_]Registration{ .{ .owner_index = 0, .name = "same:1" }, .{ .owner_index = 0, .name = "same" }, .{ .owner_index = 1, .name = "same" } };
            const values = try resolve(gpa, &names);
            defer deinit(gpa, values);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

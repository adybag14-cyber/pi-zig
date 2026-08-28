//! Generic clone-on-push undo history.
//!
//! The original TUI uses `structuredClone` so snapshots never alias mutable
//! editor/widget state.  Zig makes that ownership policy explicit through the
//! clone and destroy callbacks supplied at comptime.
const std = @import("std");

pub fn UndoStack(
    comptime T: type,
    comptime cloneFn: fn (std.mem.Allocator, T) anyerror!T,
    comptime destroyFn: fn (std.mem.Allocator, *T) void,
) type {
    return struct {
        const Self = @This();

        gpa: std.mem.Allocator,
        items: std.ArrayList(T) = .empty,
        max_depth: ?usize = null,

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa };
        }

        pub fn initBounded(gpa: std.mem.Allocator, max_depth: usize) Self {
            return .{ .gpa = gpa, .max_depth = max_depth };
        }

        pub fn deinit(self: *Self) void {
            self.clear();
            self.items.deinit(self.gpa);
            self.* = undefined;
        }

        pub fn push(self: *Self, value: T) !void {
            const copy = try cloneFn(self.gpa, value);
            errdefer {
                var owned = copy;
                destroyFn(self.gpa, &owned);
            }
            if (self.max_depth) |limit| {
                if (limit == 0) {
                    var owned = copy;
                    destroyFn(self.gpa, &owned);
                    return;
                }
                while (self.items.items.len >= limit) {
                    var oldest = self.items.orderedRemove(0);
                    destroyFn(self.gpa, &oldest);
                }
            }
            try self.items.append(self.gpa, copy);
        }

        /// Ownership of the detached snapshot transfers to the caller.
        pub fn pop(self: *Self) ?T {
            return self.items.pop();
        }

        pub fn clear(self: *Self) void {
            for (self.items.items) |*item| destroyFn(self.gpa, item);
            self.items.clearRetainingCapacity();
        }

        pub fn len(self: *const Self) usize {
            return self.items.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.items.len == 0;
        }
    };
}

const TestState = struct {
    text: []u8,
    cursor: usize,
};

fn cloneTestState(gpa: std.mem.Allocator, state: TestState) !TestState {
    return .{ .text = try gpa.dupe(u8, state.text), .cursor = state.cursor };
}

fn destroyTestState(gpa: std.mem.Allocator, state: *TestState) void {
    gpa.free(state.text);
    state.* = undefined;
}

test "undo stack deep-clones, pops ownership and clears" {
    const gpa = std.testing.allocator;
    const Stack = UndoStack(TestState, cloneTestState, destroyTestState);
    var history = Stack.init(gpa);
    defer history.deinit();

    var original = TestState{ .text = try gpa.dupe(u8, "alpha"), .cursor = 5 };
    defer destroyTestState(gpa, &original);
    try history.push(original);
    original.text[0] = 'A';

    var restored = history.pop().?;
    defer destroyTestState(gpa, &restored);
    try std.testing.expectEqualStrings("alpha", restored.text);
    try std.testing.expect(history.isEmpty());
}

test "bounded undo stack evicts oldest snapshots" {
    const gpa = std.testing.allocator;
    const Stack = UndoStack(TestState, cloneTestState, destroyTestState);
    var history = Stack.initBounded(gpa, 2);
    defer history.deinit();
    try history.push(.{ .text = @constCast("one"), .cursor = 1 });
    try history.push(.{ .text = @constCast("two"), .cursor = 2 });
    try history.push(.{ .text = @constCast("three"), .cursor = 3 });
    try std.testing.expectEqual(@as(usize, 2), history.len());
    var latest = history.pop().?;
    defer destroyTestState(gpa, &latest);
    try std.testing.expectEqualStrings("three", latest.text);
}

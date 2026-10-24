// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original MaybeStackBuffer storage for native vector/encoding temporaries.
//! The caller retains the Environment and keeps this owner at a stable address.
//! Heap growth uses its actual charged allocator, one full-GC retry, then CHECK.
const std = @import("std");
const callbacks = @import("native_node_callback_scope.zig");
const check = @import("native_node_check_failure.zig");
const c = @import("native_node_argument_values.zig").c;

pub fn Buffer(comptime T: type, comptime stack_count: usize) type {
    if (stack_count == 0) @compileError("MaybeStackBuffer requires stack storage");
    return struct {
        const Self = @This();
        environment: *callbacks.Environment = undefined,
        stack: [stack_count]T = undefined,
        heap: ?[]T = null,
        length: usize = 0,

        pub fn init(self: *Self, environment: *callbacks.Environment,
            count: usize) !void
        {
            self.* = .{ .environment = environment };
            // The Source default constructor provides a zero-length terminator.
            self.stack[0] = std.mem.zeroes(T);
            if (count > stack_count) {
                const engine = try environment.requireEngine();
                _ = std.math.mul(usize, @sizeOf(T), count) catch
                    check.assertion(engine, .{
                        .file_line = "src/util-inl.h:245",
                        .message = "(b) == (ret / a)",
                        .function = "node::MultiplyWithOverflowCheck",
                    });
                self.heap = environment.allocator().alloc(T, count) catch blk: {
                    c.JS_RunGC(engine.runtime);
                    break :blk environment.allocator().alloc(T, count) catch
                        check.assertion(engine, .{
                            .file_line = "src/util-inl.h:292",
                            .message = "!(n > 0) || (ret != nullptr)",
                            .function = "node::Realloc",
                        });
                };
            }
            self.length = count;
        }
        pub fn data(self: *Self) []T {
            return if (self.heap) |items| items else self.stack[0..self.length];
        }
        pub fn isAllocated(self: *const Self) bool { return self.heap != null; }
        pub fn deinit(self: *Self) void {
            if (self.heap) |items| self.environment.allocator().free(items);
            self.heap = null;
            self.length = 0;
        }
    };
}

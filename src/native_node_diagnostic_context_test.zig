//! Borrowed diagnostic admission at actual synchronous native boundaries.
//! This is not an Isolate/Context entry implementation or a stack formatter.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_node_diagnostic_context.h");
    @cInclude("native_node_diagnostic_context_test_support.h");
});
const memory_limit: usize = 32 * 1024 * 1024;

const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn deinit(self: *Fixture) void {
        if (self.runtime) |runtime| c.JS_PiCancelExecutionTermination(runtime);
        if (self.context) |context| {
            self.context = null;
            while (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
};

test "Node diagnostic context actual VM creation does not admit an ambient context" {
    try std.testing.expect(c.pi_node_diagnostic_context_current() == null);
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try std.testing.expect(c.pi_node_diagnostic_context_current() == null);
}

test "Node diagnostic context nested actual contexts restore their caller without retaining a VM" {
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    var second: Fixture = .{}; try second.init(); defer second.deinit();
    const before = c.pi_node_diagnostic_context_enter(first.context);
    defer c.pi_node_diagnostic_context_leave(before);
    try std.testing.expect(c.pi_node_diagnostic_context_current() == first.context);
    {
        const previous = c.pi_node_diagnostic_context_enter(second.context);
        defer c.pi_node_diagnostic_context_leave(previous);
        try std.testing.expect(previous == first.context);
        try std.testing.expect(c.JS_GetRuntime(c.pi_node_diagnostic_context_current()) == second.runtime);
    }
    try std.testing.expect(c.pi_node_diagnostic_context_current() == first.context);
    second.deinit();
    try std.testing.expect(c.JS_GetRuntime(c.pi_node_diagnostic_context_current()) == first.runtime);
}

test "Node diagnostic context explicit native-only admission masks and restores an entered caller" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const before = c.pi_node_diagnostic_context_enter(f.context);
    defer c.pi_node_diagnostic_context_leave(before);
    {
        const previous = c.pi_node_diagnostic_context_enter(null);
        defer c.pi_node_diagnostic_context_leave(previous);
        try std.testing.expect(previous == f.context);
        try std.testing.expect(c.pi_node_diagnostic_context_current() == null);
    }
    try std.testing.expect(c.pi_node_diagnostic_context_current() == f.context);
}

test "Node diagnostic context same-context reentry leaves the outer borrowed admission live" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const before = c.pi_node_diagnostic_context_enter(f.context);
    defer c.pi_node_diagnostic_context_leave(before);
    {
        const previous = c.pi_node_diagnostic_context_enter(f.context);
        defer c.pi_node_diagnostic_context_leave(previous);
        try std.testing.expect(previous == f.context);
        try std.testing.expect(c.pi_node_diagnostic_context_current() == f.context);
    }
    try std.testing.expect(c.pi_node_diagnostic_context_current() == f.context);
}

test "Node diagnostic context native projection works with an exhausted JS heap without allocating" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var before: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(f.runtime.?, &before);
    const used_before = c.pi_js_native_memory_used(f.memory);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    defer c.JS_SetMemoryLimit(f.runtime.?, @intCast(before.malloc_limit));
    {
        const previous = c.pi_node_diagnostic_context_enter(f.context);
        defer c.pi_node_diagnostic_context_leave(previous);
        try std.testing.expect(c.pi_node_diagnostic_context_current() == f.context);
    }
    var after: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(f.runtime.?, &after);
    try std.testing.expectEqual(before.malloc_count, after.malloc_count);
    try std.testing.expectEqual(before.memory_used_size, after.memory_used_size);
    try std.testing.expectEqual(used_before, c.pi_js_native_memory_used(f.memory));
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "Node diagnostic context ordinary and fatal pending reasons remain the same actual owned value" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    for (0..2) |mode| {
        const reason = c.JS_NewError(f.context.?);
        try std.testing.expect(!c.JS_IsException(reason));
        defer c.JS_FreeValue(f.context.?, reason);
        if (mode == 1) c.JS_SetUncatchableError(f.context.?, reason);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        {
            const previous = c.pi_node_diagnostic_context_enter(f.context);
            defer c.pi_node_diagnostic_context_leave(previous);
            try std.testing.expect(c.JS_HasException(f.context.?));
            try std.testing.expect(c.pi_node_diagnostic_context_current() == f.context);
        }
        try std.testing.expect(c.JS_HasException(f.context.?));
        const actual = c.JS_GetException(f.context.?);
        defer c.JS_FreeValue(f.context.?, actual);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, actual));
        try std.testing.expectEqual(mode == 1, c.JS_IsUncatchableError(actual));
    }
}

test "Node diagnostic context private termination lease and actual pending token survive admission" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    _ = c.JS_PiCheckExecutionTermination(f.context.?);
    try std.testing.expect(c.JS_HasException(f.context.?));
    const generation = c.JS_PiExecutionTerminationGeneration(f.runtime.?);
    {
        const previous = c.pi_node_diagnostic_context_enter(f.context);
        defer c.pi_node_diagnostic_context_leave(previous);
        try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        try std.testing.expect(c.JS_HasException(f.context.?));
    }
    try std.testing.expectEqual(generation, c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    const reason = c.JS_GetException(f.context.?);
    defer {
        if (c.JS_PiIsExecutionTermination(reason)) {
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
            c.JS_PiCancelExecutionTermination(f.runtime.?);
        }
        c.JS_FreeValue(f.context.?, reason);
    }
    try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
}

test "Node diagnostic context C++ locals retire before nested and outer scopes restore" {
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    var second: Fixture = .{}; try second.init(); defer second.deinit();
    const before = c.pi_node_diagnostic_context_enter(first.context);
    defer c.pi_node_diagnostic_context_leave(before);
    try std.testing.expectEqual(@as(u32, 63),
        c.pi_node_test_diagnostic_context_scope(second.context, first.context, 0));
    try std.testing.expect(c.pi_node_diagnostic_context_current() == first.context);
}

test "Node diagnostic context C++ early return keeps each destructor in its real caller scope" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try std.testing.expectEqual(@as(u32, 47),
        c.pi_node_test_diagnostic_context_scope(f.context, null, 1));
    try std.testing.expect(c.pi_node_diagnostic_context_current() == null);
}

const Worker = struct {
    started_empty: bool = false,
    admitted_actual_context: bool = false,
    finished_empty: bool = false,
    failed: bool = false,
    fn run(self: *Worker) void {
        self.started_empty = c.pi_node_diagnostic_context_current() == null;
        var f: Fixture = .{};
        f.init() catch { self.failed = true; return; };
        defer f.deinit();
        {
            const previous = c.pi_node_diagnostic_context_enter(f.context);
            defer c.pi_node_diagnostic_context_leave(previous);
            self.admitted_actual_context = previous == null and
                c.pi_node_diagnostic_context_current() == f.context and
                c.JS_GetRuntime(c.pi_node_diagnostic_context_current()) == f.runtime;
        }
        self.finished_empty = c.pi_node_diagnostic_context_current() == null;
    }
};

test "Node diagnostic context actual worker thread neither inherits nor overwrites its caller admission" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const before = c.pi_node_diagnostic_context_enter(f.context);
    defer c.pi_node_diagnostic_context_leave(before);
    var worker: Worker = .{};
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    thread.join();
    try std.testing.expect(!worker.failed);
    try std.testing.expect(worker.started_empty and worker.admitted_actual_context and worker.finished_empty);
    try std.testing.expect(c.pi_node_diagnostic_context_current() == f.context);
}

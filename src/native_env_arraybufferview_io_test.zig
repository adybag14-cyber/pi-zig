const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const h = @import("extensions/native_env_remote_helpers.zig");
const async_value = @import("extensions/native_agent_async.zig");
const c = js.c;

test "native Env ArrayBufferView IO actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nENV_ARRAYBUFFERVIEW_IO_TEST_INVENTORY={s}\n", .{text});
}

// Verification adapter for the actual normalized internal binding result. The
// production worker owns the descriptor, bytes, original views and close state.
fn counted(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, method: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = if (rejected) value else try scope.get(value, if (method == 0 or method == 2) "bytesRead" else "bytesWritten");
    try async_value.settle(engine, owner, rejected, result);
}
fn kernelCall(scope: *Scope, raw: c.JSValue, operation: c.JSValue, args: []const c.JSValue, method: c_int) !c.JSValue {
    const pending = try async_value.create(scope.engine, raw);
    defer scope.engine.freeValue(pending.owner);
    errdefer scope.engine.freeValue(pending.promise);
    beginKernel(scope, pending.owner, raw, operation, args, method) catch |err| try async_value.rejectError(scope.engine, pending.owner, err);
    return pending.promise;
}
fn beginKernel(scope: *Scope, owner: c.JSValue, raw: c.JSValue, operation: c.JSValue, args: []const c.JSValue, method: c_int) !void {
    try async_value.wait(counted, scope.engine, owner, try scope.call(operation, raw, args), method);
}

// Only the explicit, already normalized scalar-view form is under comparison
// here. This is a fixture adapter, not a replacement FileHandle implementation.
// It preserves the two live byteLength reads of that real Node frontend branch;
// the production kernel performs genuine brand/bounds/backing checks afterward.
fn explicitScalar(scope: *Scope, raw: c.JSValue, operation: c.JSValue, args: []const c.JSValue, write: bool) !c.JSValue {
    var fd: i64 = undefined;
    if (c.JS_ToInt64(scope.engine.context, &fd, try scope.get(raw, "fd")) < 0) return js.capture(scope.engine);
    if (fd == -1) return c.JS_DupValue(scope.engine.context, try scope.call(operation, raw, args));
    const target = h.arg(args, 0);
    const offset_value = h.arg(args, 1);
    const count_value = h.arg(args, 2);
    if (!c.JS_IsNumber(offset_value) or !c.JS_IsNumber(count_value)) return error.UnnormalizedViewScalarFixture;
    var offset: f64 = undefined;
    var count: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &offset, offset_value) < 0 or c.JS_ToFloat64(scope.engine.context, &count, count_value) < 0) return js.capture(scope.engine);
    if (!std.math.isFinite(offset) or offset < 0 or @trunc(offset) != offset or !std.math.isFinite(count) or count < 0 or @trunc(count) != count) return error.UnnormalizedViewScalarFixture;
    // These are actual empty-view and range checks, rather than synthetic
    // getter calls. General overloads and invalid-argument Node errors are not
    // provided by this explicitly normalized verification adapter.
    const empty = if (write) scope.equal(try scope.get(target, "byteLength"), c.JS_NewInt32(scope.engine.context, 0)) else count == 0;
    if (empty) {
        const result = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
        try scope.put(result, if (write) "bytesWritten" else "bytesRead", c.JS_NewInt32(scope.engine.context, 0));
        try scope.put(result, "buffer", target);
        return @import("extensions/native_durable.zig").resolvedPromise(scope.engine, result);
    }
    if (!write and scope.equal(try scope.get(target, "byteLength"), c.JS_NewInt32(scope.engine.context, 0))) return error.InvalidNormalizedReadEmptyBuffer;
    var available: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &available, try scope.get(target, "byteLength")) < 0) return js.capture(scope.engine);
    if (offset + count > available) return error.InvalidNormalizedViewScalarRange;
    return c.JS_DupValue(scope.engine.context, try scope.call(operation, raw, args));
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, method: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (if (method < 4) kernelCall(&scope, roots[0], roots[1], args, method) else explicitScalar(&scope, roots[0], roots[1], args, method == 5)) catch |err| @import("extensions/native_durable.zig").rejectedPromise(engine, err);
}
fn adapter(scope: *Scope, raw: c.JSValue, comptime public_phase: bool) !c.JSValue {
    const result = if (public_phase) raw else try scope.object();
    inline for (.{ "read", "write", "readv", "writev" }, 0..) |name, index| {
        if (!public_phase or index < 2) {
            var roots = [_]c.JSValue{ raw, try scope.get(raw, name) };
            const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, invoke, name, if (index < 2) 4 else 2, @intCast(index + if (public_phase) @as(usize, 4) else 0), roots.len, &roots)));
            try scope.put(result, name, function);
        }
    }
    return result;
}

// Every allocator route is serialized: both the VM and admitted I/O workers can
// allocate while a FailingAllocator attempt owns the same child state.
const LockedAllocator = struct {
    child: std.mem.Allocator,
    mutex: std.Io.Mutex = .init,
    fn allocator(self: *LockedAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        return self.child.rawAlloc(len, alignment, ra);
    }
    fn resize(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) bool {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        return self.child.rawResize(bytes, alignment, len, ra);
    }
    fn remap(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) ?[*]u8 {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        return self.child.rawRemap(bytes, alignment, len, ra);
    }
    fn free(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *LockedAllocator = @ptrCast(@alignCast(raw));
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        self.child.rawFree(bytes, alignment, ra);
    }
};
fn replay(gpa: std.mem.Allocator, comptime public_phase: bool) !void {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "file", .data = &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } });
    const raw = try tmp.dir.openFile(std.testing.io, "file", .{ .mode = .read_write });
    var locked: LockedAllocator = .{ .child = gpa };
    const engine = em.Engine.init(locked.allocator(), .{ .host_await_timeout_ms = 10_000 }) catch |err| {
        raw.close(std.testing.io);
        return err;
    };
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = scope.object() catch |err| {
        raw.close(std.testing.io);
        return err;
    };
    const file = try scope.own(try @import("extensions/native_env_node_file_io.zig").createArrayBufferViewFile(&scope, raw, true, bindings));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, if (public_phase) "file" else "kernel", try adapter(&scope, file, public_phase));
    const source = if (public_phase) @embedFile("extensions/fixtures/env-node-view-public-getters-source-24.json") else @embedFile("extensions/fixtures/env-node-view-kernel-source-24.json");
    const body = if (public_phase) @embedFile("extensions/fixtures/env-node-view-public-getters-source-24.input.txt") else @embedFile("extensions/fixtures/env-node-view-kernel-source-24.input.txt");
    try scope.put(global, "viewIoSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-view-io.json"))));
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(body ++ "\nif(JSON.stringify(packet)!==JSON.stringify(viewIoSource))throw Error(JSON.stringify({actual:packet,expected:viewIoSource}));export const proof=true;", "native-env-arraybufferview-io.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("ArrayBufferView IO Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
fn kernelAllocation(gpa: std.mem.Allocator) !void {
    return replay(gpa, false);
}
fn publicAllocation(gpa: std.mem.Allocator) !void {
    return replay(gpa, true);
}
test "native Env ArrayBufferView IO real kernel four-case scalar vectors bytes and zero observable getters match Node24" {
    try replay(std.testing.allocator, false);
}
test "native Env ArrayBufferView IO explicit scalar frontend seven-case getter phases original identity pending close and closed errors match Node24" {
    try replay(std.testing.allocator, true);
}
test "native Env ArrayBufferView IO kernel worker roots release at every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, kernelAllocation, .{});
}
test "native Env ArrayBufferView IO explicit scalar phase and pending close roots release at every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publicAllocation, .{});
}

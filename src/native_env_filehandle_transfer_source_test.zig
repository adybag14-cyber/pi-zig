const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const files = @import("extensions/native_env_node_file_io.zig");
const c = js.c;
test "native Env FileHandle transfer source actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nENV_FILE_HANDLE_TRANSFER_SOURCE_TEST_INVENTORY={s}\n", .{text});
}
const Gate = struct {
    engine: *em.Engine,
    file: c.JSValue,
    held: bool = false,
    fn hold(self: *Gate) !void {
        if (self.held) return error.PendingViewBarrierAlreadyHeld;
        try files.holdForPendingOwnershipTest(self.engine, self.file);
        self.held = true;
    }
    fn release(self: *Gate) void {
        if (!self.held) return;
        self.held = false;
        files.releaseForPendingOwnershipTest(self.engine, self.file);
    }
};
fn gateFrom(engine: *em.Engine, root: c.JSValue) !*Gate {
    var address: u64 = undefined;
    if (c.JS_ToBigUint64(engine.context, &address, root) < 0) return js.capture(engine);
    return @ptrFromInt(@as(usize, @intCast(address)));
}
fn blocker(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, release: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const gate = gateFrom(engine, roots[1]) catch |err| return @import("extensions/native_durable.zig").reject(engine, err);
    if (release != 0) gate.release() else gate.hold() catch |err| return @import("extensions/native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(js.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
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
fn replay(gpa: std.mem.Allocator) !void {
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
    const file = try scope.own(try files.createLeasedArrayBufferViewFile(&scope, raw, true, bindings, 32 * 1024 * 1024));
    // The Zig guard releases the real mutex before Scope/Hub/VM teardown even
    // when VM interruption or allocation failure prevents a JS finally callback.
    var gate: Gate = .{ .engine = engine, .file = file };
    defer gate.release();
    try @import("extensions/native_env_node_file_frontend.zig").installPrivate(&scope, file);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "file", file);
    var roots = [_]c.JSValue{ file, try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, @intFromPtr(&gate)))) };
    inline for (.{ "queueBlocker", "releaseBlocker" }, 0..) |name, index| {
        try scope.put(global, name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, blocker, name, @intCast(index), @intCast(index), roots.len, &roots))));
    }
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const source = @embedFile("extensions/fixtures/env-node-rab-same-transfer-source-24.json");
    const body = @embedFile("extensions/fixtures/env-node-rab-same-transfer-source-24.input.txt");
    try scope.put(global, "pendingViewSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-rab-same-transfer.json"))));
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(body ++ "\nif(JSON.stringify(packet)!==JSON.stringify(pendingViewSource))throw Error(JSON.stringify({actual:packet,expected:pendingViewSource}));export const proof=true;", "native-rab-same-transfer-source.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("RAB same transfer actual Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env FileHandle transfer source equal length resizable read and write match genuine Node packet with real worker barrier and GC" {
    try replay(std.testing.allocator);
}

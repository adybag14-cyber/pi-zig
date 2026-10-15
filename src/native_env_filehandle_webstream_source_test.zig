//! Compare the real descriptor/controller assembly with immutable genuine
//! Node24 packets. Reference captures are recorded outside this worktree.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const files = @import("extensions/native_env_node_file_io.zig");
const c = js.c;

test "native Env FileHandle webstream source actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nENV_FILE_HANDLE_WEBSTREAM_SOURCE_TEST_INVENTORY={s}\n", .{text});
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
const Gate = struct {
    engine: *js.Engine,
    descriptor: c.JSValue,
    held: bool = false,
    fn release(self: *Gate) void {
        if (!self.held) return;
        self.held = false;
        files.releaseForPendingOwnershipTest(self.engine, self.descriptor);
    }
};
fn blocker(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, release: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var address: u64 = undefined;
    if (c.JS_ToBigUint64(context, &address, roots[1]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    const gate: *Gate = @ptrFromInt(@as(usize, @intCast(address)));
    if (release != 0) gate.release() else {
        if (gate.held) return @import("extensions/native_durable.zig").reject(engine, error.PendingViewBarrierAlreadyHeld);
        files.holdForPendingOwnershipTest(engine, gate.descriptor) catch |err| return @import("extensions/native_durable.zig").reject(engine, err);
        gate.held = true;
    }
    return c.pi_js_undefined();
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(js.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
fn replay(gpa: std.mem.Allocator, case_name: []const u8) !void {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "file", .data = &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } });
    const raw = try tmp.dir.openFile(std.testing.io, "file", .{ .mode = .read_write });
    var locked: LockedAllocator = .{ .child = gpa };
    const engine = js.Engine.init(locked.allocator(), .{ .host_await_timeout_ms = 10_000 }) catch |err| {
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
    const descriptor = try scope.own(try files.createLeasedArrayBufferViewFile(&scope, raw, true, bindings, 32 * 1024 * 1024));
    var gate: Gate = .{ .engine = engine, .descriptor = descriptor };
    defer gate.release();
    const file = try @import("extensions/native_env_node_file_assembly.zig").create(&scope, descriptor, bindings);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "file", file);
    try scope.put(global, "caseName", try scope.text(case_name));
    var roots = [_]c.JSValue{ descriptor, try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, @intFromPtr(&gate)))) };
    inline for (.{ "queueBlocker", "releaseBlocker" }, 0..) |name, index| try scope.put(global, name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, blocker, name, @intCast(index), @intCast(index), roots.len, &roots))));
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const source = @embedFile("extensions/fixtures/env-node-filehandle-webstream-dynamic-source-24.json");
    try scope.put(global, "webStreamSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-webstream-dynamic.json"))));
    const generation = engine.native_allocation_generation;
    const body = @embedFile("extensions/fixtures/env-node-filehandle-webstream-dynamic-symbols-source-24.input.txt");
    const result = engine.evalModule(body ++ "\nif(JSON.stringify(packet)!==JSON.stringify(webStreamSource[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:webStreamSource[caseName]}));export const proof=true;", "native-filehandle-webstream-source.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("FileHandle webstream actual Source case {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" });
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env FileHandle webstream source default reader" {
    try replay(std.testing.allocator, "default-reader");
}
test "native Env FileHandle webstream source auto close" {
    try replay(std.testing.allocator, "auto-close");
}
test "native Env FileHandle webstream source BYOB zero offset detach and EOF" {
    try replay(std.testing.allocator, "byob-zero");
}
test "native Env FileHandle webstream source cancel retains file" {
    try replay(std.testing.allocator, "cancel");
}
test "native Env FileHandle webstream source invalid options locks before validation" {
    try replay(std.testing.allocator, "invalid-options-lock");
}
test "native Env FileHandle webstream source getter order" {
    try replay(std.testing.allocator, "getter-order");
}
test "native Env FileHandle webstream source captures mutable read" {
    try replay(std.testing.allocator, "capture-read");
}
test "native Env FileHandle webstream source close pending real worker barrier" {
    try replay(std.testing.allocator, "close-pending");
}

const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
test "native Env FileHandle actual compiled primitive inventory" {
    const builtin = @import("builtin");
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nENV_FILE_HANDLE_TEST_INVENTORY={s}\n", .{text});
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const value = @import("extensions/native_safe_promise.zig").finallyValue(&scope, data[0], if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined()) catch |err| return @import("extensions/native_durable.zig").reject(engine, err);
    return c.JS_DupValue(engine.context, value);
}
fn install(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const holder = try scope.own(try @import("extensions/native_safe_promise.zig").create(engine));
    var data = [_]c.JSValue{holder};
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, "nativeFinally", 2, 0, 1, &data)));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "nativeFinally", function);
}
test "native Env FileHandle protected finally matches actual Node24 primordial ordering species identity and prototype poisoning" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const source = @embedFile("extensions/fixtures/env-node-safe-finally-source-24.json");
    try scope.put(global, "safeFinallySource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-safe-finally.json"))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/env-node-safe-finally-source-24.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(safeFinallySource))throw Error(JSON.stringify({actual:packet,expected:safeFinallySource}));export const proof=true;", "native-safe-finally-source.mjs") catch |err| {
        std.debug.print("Native FileHandle protected-promise Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
fn allocation(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const source = @embedFile("extensions/fixtures/env-node-safe-finally-allocation-driver.json");
    try scope.put(global, "safeFinallyAllocationSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-safe-finally-allocation.json"))));
    const generation = engine.native_allocation_generation;
    // Unexpected errors retain their original identity. The failure driver must
    // never replace a caught native OOM with a new comparison/diagnostic Error.
    const result = engine.evalModule(@embedFile("extensions/fixtures/env-node-safe-finally-allocation-driver.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(safeFinallyAllocationSource))throw Error(JSON.stringify({actual:packet,expected:safeFinallyAllocationSource}));export const proof=true;", "native-safe-finally-allocation.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            std.debug.print("Protected promise GPA fail_index={d}: {s}\n", .{ failing.fail_index, engine.last_error orelse "no diagnostic" });
        }
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env FileHandle protected constructor and pending finally roots release every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocation, .{});
}
test "native Env FileHandle real descriptor metadata operations match original Node24 timestamps ownership and closed errors" {
    if (@import("builtin").os.tag != .windows) return error.MissingRequiredPlatformFileHandleMetadataReference;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "file", .data = "metadata" });
    const raw = try tmp.dir.openFile(std.testing.io, "file", .{ .mode = .read_write });
    const engine = em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 }) catch |err| {
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
    const file = try scope.own(try @import("extensions/native_env_node_file_io.zig").create(&scope, raw, true, bindings));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "file", file);
    const source = @embedFile("extensions/fixtures/env-node-filehandle-metadata-source-24.json");
    try scope.put(global, "fileMetadataSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-filehandle-metadata.json"))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/env-node-filehandle-metadata-source-24.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(fileMetadataSource))throw Error(JSON.stringify({actual:packet,expected:fileMetadataSource}));export const proof=true;", "native-filehandle-metadata-source.mjs") catch |err| {
        std.debug.print("Native FileHandle metadata Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

test "native Env FileHandle real libuv vectors match original Node24 buffer identity slices cursor partial EOF and closed errors" {
    if (@import("builtin").os.tag != .windows) return error.MissingRequiredPlatformFileHandleVectorReference;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "file", .data = &.{ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 } });
    const raw = try tmp.dir.openFile(std.testing.io, "file", .{ .mode = .read_write });
    const engine = em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 }) catch |err| {
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
    const file = try scope.own(try @import("extensions/native_env_node_file_io.zig").create(&scope, raw, true, bindings));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "file", file);
    const source = @embedFile("extensions/fixtures/env-node-filehandle-vectors-source-24.json");
    try scope.put(global, "fileVectorsSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-filehandle-vectors.json"))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/env-node-filehandle-vectors-source-24.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(fileVectorsSource))throw Error(JSON.stringify({actual:packet,expected:fileVectorsSource}));export const proof=true;", "native-filehandle-vectors-source.mjs") catch |err| {
        std.debug.print("Native FileHandle vectors Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

// The failing allocator is shared by VM ownership and I/O task admission.
// Zig0.16's Threaded mutex serializes every allocator vtable route, including
// cleanup after the owner pump has joined workers.
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
fn descriptorAllocation(gpa: std.mem.Allocator) !void {
    // Native file setup is outside fault injection. Every VM attempt owns a
    // fresh descriptor and deinit joins its jobs before the real tree cleanup.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "file", .data = &.{ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 } });
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
    const file = try scope.own(try @import("extensions/native_env_node_file_io.zig").create(&scope, raw, true, bindings));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "file", file);
    const source = @embedFile("extensions/fixtures/env-node-filehandle-descriptor-gpa-source-24.json");
    try scope.put(global, "fileDescriptorGpaSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-filehandle-descriptor-gpa.json"))));
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(@embedFile("extensions/fixtures/env-node-filehandle-descriptor-gpa-source-24.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(fileDescriptorGpaSource))throw Error(JSON.stringify({actual:packet,expected:fileDescriptorGpaSource}));export const proof=true;", "native-filehandle-descriptor-gpa-source.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            std.debug.print("FileHandle descriptor GPA fail_index={d}: {s}\n", .{ failing.fail_index, engine.last_error orelse "no diagnostic" });
        }
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native Env FileHandle metadata vectored workers pending close and view roots release every host allocation failure" {
    if (@import("builtin").os.tag != .windows) return error.MissingRequiredPlatformFileHandleDescriptorAllocationReference;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, descriptorAllocation, .{});
}

fn retainedContents(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, method: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const contents = @import("extensions/native_env_node_fs_contents.zig");
    const h = @import("extensions/native_env_remote_helpers.zig");
    const value = (if (method == 0) contents.readRetained(engine, data[0], data[1], h.arg(args, 0)) else contents.writeRetained(engine, data[0], data[1], h.arg(args, 0), h.arg(args, 1))) catch |err| return @import("extensions/native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(value);
    return @import("extensions/native_durable.zig").resolvedPromise(engine, value) catch |err| @import("extensions/native_durable.zig").rejectedPromise(engine, err);
}
test "native Env FileHandle internal retained content engine preserves descriptor cursor abort cause and zero writes like original Node24" {
    if (@import("builtin").os.tag != .windows) return error.MissingRequiredPlatformFileHandleRetainedContentsReference;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "file", .data = "abcdef" });
    const raw = try tmp.dir.openFile(std.testing.io, "file", .{ .mode = .read_write });
    const engine = em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 }) catch |err| {
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
    const file = try scope.own(try @import("extensions/native_env_node_file_io.zig").create(&scope, raw, true, bindings));
    try @import("extensions/node_buffer.zig").install(engine);
    var promises = try @import("extensions/native_durable_await.zig").Intrinsics.init(engine);
    defer promises.deinit(engine);
    try scope.put(bindings, "promise_constructor", promises.constructor);
    try scope.put(bindings, "promise_resolve", promises.resolve);
    try scope.put(bindings, "promise_then", promises.then_function);
    try scope.put(bindings, "fileHandleBuffer", try scope.global("Buffer"));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "file", file);
    var data = [_]c.JSValue{ bindings, file };
    try scope.put(global, "readRetained", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, retainedContents, "readRetained", 1, 0, data.len, &data))));
    try scope.put(global, "writeRetained", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, retainedContents, "writeRetained", 2, 1, data.len, &data))));
    const source = @embedFile("extensions/fixtures/env-node-filehandle-retained-contents-source-24.json");
    try scope.put(global, "fileRetainedContentsSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-filehandle-retained-contents.json"))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/env-node-filehandle-retained-contents-source-24.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(fileRetainedContentsSource))throw Error(JSON.stringify({actual:packet,expected:fileRetainedContentsSource}));export const proof=true;", "native-filehandle-retained-contents-source.mjs") catch |err| {
        std.debug.print("Native FileHandle retained contents Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}

//! Real native Environment managed-buffer table and backing-token controls.
//! Native allocation/retry policy and public StreamBase dispatch are separate.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_node_managed_buffers.h");
    @cInclude("native_node_environment_map_test_support.h");
});
const Token = c.JSPiArrayBufferBackingStore;
const Table = c.PiNodeManagedBuffers;
const memory_limit: usize = 32 * 1024 * 1024;

const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    table: ?*Table = null,
    storage: ?[*]u8 = null,
    storage_bytes: usize = 0,
    storage_alignment: std.mem.Alignment = .@"1",
    storage_charged: bool = false,

    fn init(self: *Fixture, with_context: bool) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        if (with_context) try self.openContext();
        self.storage_bytes = c.pi_node_managed_buffers_storage_size();
        self.storage_alignment = .fromByteUnits(c.pi_node_managed_buffers_storage_alignment());
        if (c.pi_js_native_memory_reserve(self.memory, self.storage_bytes) == 0) return error.OutOfMemory;
        self.storage_charged = true;
        self.storage = std.heap.c_allocator.rawAlloc(self.storage_bytes,
            self.storage_alignment, @returnAddress()) orelse return error.OutOfMemory;
        self.table = c.pi_node_managed_buffers_construct(self.storage.?);
    }
    fn openContext(self: *Fixture) !void {
        std.debug.assert(self.context == null);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn destroyTable(self: *Fixture) void {
        if (self.table) |table| {
            self.table = null;
            c.pi_node_managed_buffers_destroy(table);
        }
        if (self.storage) |storage| {
            self.storage = null;
            std.heap.c_allocator.rawFree(storage[0..self.storage_bytes],
                self.storage_alignment, @returnAddress());
        }
        if (self.storage_charged) {
            self.storage_charged = false;
            c.pi_js_native_memory_release(self.memory, self.storage_bytes);
        }
    }
    fn closeVm(self: *Fixture) void {
        if (self.context) |context| {
            self.context = null;
            while (c.JS_HasException(context))
                c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| {
            self.runtime = null;
            c.JS_FreeRuntime(runtime);
        }
    }
    fn deinit(self: *Fixture) void {
        self.destroyTable();
        self.closeVm();
        if (self.memory) |memory| {
            self.memory = null;
            c.pi_js_release_memory_owner(memory);
        }
    }
    fn used(self: *Fixture) usize { return c.pi_js_native_memory_used(self.memory); }
    fn count(self: *Fixture) usize { return c.pi_node_managed_buffers_count(self.table.?); }
    fn make(self: *Fixture, length: usize, zeroed: bool) !Token {
        var result: Token = std.mem.zeroes(Token);
        errdefer c.JS_PiReleaseArrayBufferBackingStore(&result);
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_PiTryNewArrayBufferBackingStore(self.runtime.?, length, zeroed, &result));
        try std.testing.expect(result.owner != null);
        return result;
    }
    fn adopt(self: *Fixture, owned: *Token) c.uv_buf_t {
        var buffer: c.uv_buf_t = undefined;
        c.pi_node_managed_buffers_adopt(self.table.?, self.memory, owned, &buffer);
        return buffer;
    }
    fn take(self: *Fixture, buffer: c.uv_buf_t) Token {
        var result: Token = std.mem.zeroes(Token);
        c.pi_node_managed_buffers_release(self.table.?, self.context, &buffer, &result);
        return result;
    }
};
fn empty(token: *const Token) !void {
    try std.testing.expect(token.owner == null);
    try std.testing.expectEqual(@as(usize, 0), c.JS_PiArrayBufferBackingStoreByteLength(token));
    try std.testing.expect(c.JS_PiArrayBufferBackingStoreData(token) == null);
}
fn contents(token: *const Token, expected: []const u8) !void {
    try std.testing.expectEqual(expected.len, c.JS_PiArrayBufferBackingStoreByteLength(token));
    const bytes = c.JS_PiArrayBufferBackingStoreData(token);
    try std.testing.expect(bytes != null or expected.len == 0);
    if (expected.len != 0) try std.testing.expectEqualSlices(u8, expected, bytes[0..expected.len]);
}
const Insert = struct {
    fixture: *Fixture,
    token: *Token,
    buffer: c.uv_buf_t = undefined,
    called: bool = false,
    fn run(raw: ?*anyopaque) callconv(.c) void {
        const self: *Insert = @ptrCast(@alignCast(raw.?));
        self.called = true;
        self.buffer = self.fixture.adopt(self.token);
    }
};

test "Node managed buffers constructs the actual empty native map without a context" {
    var f: Fixture = .{}; try f.init(false); defer f.deinit();
    try std.testing.expect(f.context == null);
    try std.testing.expectEqual(@as(usize, 0), f.count());
    const with_table = f.used();
    const bytes = f.storage_bytes;
    f.destroyTable();
    try std.testing.expectEqual(with_table - bytes, f.used());
}

test "Node managed buffers consumes the actual token before any JS wrapper exists" {
    var f: Fixture = .{}; try f.init(true); defer f.deinit();
    var token = try f.make(16, false);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const data = c.JS_PiArrayBufferBackingStoreData(&token);
    @memcpy(data[0..16], "native-map-bytes!");
    var before: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(f.runtime.?, &before);
    const buffer = f.adopt(&token);
    try empty(&token);
    try std.testing.expectEqual(@as(usize, 1), f.count());
    try std.testing.expectEqual(@intFromPtr(data), @intFromPtr(buffer.base));
    try std.testing.expectEqual(@as(usize, 16), @as(usize, buffer.len));
    var after: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(f.runtime.?, &after);
    try std.testing.expectEqual(before.obj_count, after.obj_count);
    var taken = f.take(buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    try std.testing.expectEqual(@as(usize, 0), f.count());
    try contents(&taken, "native-map-bytes!");
}

test "Node managed buffers insertion does not enter the exhausted JS heap" {
    var f: Fixture = .{}; try f.init(true); defer f.deinit();
    var token = try f.make(8, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    var buffer: c.uv_buf_t = undefined;
    {
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        defer c.JS_SetMemoryLimit(f.runtime.?, 0);
        buffer = f.adopt(&token);
    }
    try empty(&token);
    try std.testing.expectEqual(@as(usize, 1), f.count());
    try std.testing.expect(!c.JS_HasException(f.context.?));
    var taken = f.take(buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    try contents(&taken, &([_]u8{0} ** 8));
}

test "Node managed buffers release keys on actual base and ignores the copied length" {
    var f: Fixture = .{}; try f.init(true); defer f.deinit();
    var token = try f.make(12, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const owner = token.owner;
    var buffer = f.adopt(&token);
    buffer.len = 0;
    var taken = f.take(buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    try std.testing.expect(taken.owner == owner);
    try std.testing.expectEqual(@as(usize, 12), c.JS_PiArrayBufferBackingStoreByteLength(&taken));
    try std.testing.expectEqual(@as(usize, 0), f.count());
}

test "Node managed buffers null base bypasses lookup while retaining other entries" {
    var f: Fixture = .{}; try f.init(false); defer f.deinit();
    var token = try f.make(9, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const real = f.adopt(&token);
    const before = f.used();
    var none = f.take(c.uv_buf_init(null, 99));
    defer c.JS_PiReleaseArrayBufferBackingStore(&none);
    try empty(&none);
    try std.testing.expectEqual(before, f.used());
    try std.testing.expectEqual(@as(usize, 1), f.count());
    var taken = f.take(real);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    try std.testing.expectEqual(@as(usize, 9), c.JS_PiArrayBufferBackingStoreByteLength(&taken));
}

test "Node managed buffers preserves the real zero owner until map destruction" {
    var f: Fixture = .{}; try f.init(false); defer f.deinit();
    const before = f.used();
    var token = try f.make(0, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const buffer = f.adopt(&token);
    try empty(&token);
    try std.testing.expect(buffer.base == null);
    try std.testing.expectEqual(@as(usize, 1), f.count());
    var none = f.take(buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&none);
    try empty(&none);
    try std.testing.expectEqual(@as(usize, 1), f.count());
    try std.testing.expect(f.used() > before);
    const storage_bytes = f.storage_bytes;
    f.destroyTable();
    try std.testing.expectEqual(before - storage_bytes, f.used());
}

test "Node managed buffers duplicate insertion retires only the unselected native owner" {
    var f: Fixture = .{}; try f.init(false); defer f.deinit();
    var first = try f.make(0, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&first);
    _ = f.adopt(&first);
    const after_first = f.used();
    var second = try f.make(0, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&second);
    try std.testing.expect(f.used() > after_first);
    const second_buffer = f.adopt(&second);
    try empty(&first);
    try empty(&second);
    try std.testing.expect(second_buffer.base == null);
    try std.testing.expectEqual(@as(usize, 1), f.count());
    try std.testing.expectEqual(after_first, f.used());
}

test "Node managed buffers moves out before erase and survives native table destruction" {
    var f: Fixture = .{}; try f.init(false); defer f.deinit();
    var token = try f.make(7, false);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    @memcpy(c.JS_PiArrayBufferBackingStoreData(&token)[0..7], "retains");
    const buffer = f.adopt(&token);
    var taken = f.take(buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    f.destroyTable();
    try contents(&taken, "retains");
}

test "Node managed buffers release then adopts the same real backing into a later ArrayBuffer" {
    var f: Fixture = .{}; try f.init(true); defer f.deinit();
    var token = try f.make(10, false);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const data = c.JS_PiArrayBufferBackingStoreData(&token);
    @memcpy(data[0..10], "same-store");
    const buffer = f.adopt(&token);
    var taken = f.take(buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    const value = c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &taken);
    defer c.JS_FreeValue(f.context.?, value);
    try std.testing.expect(!c.JS_IsException(value));
    try empty(&taken);
    var length: usize = 0;
    const actual = c.JS_GetArrayBuffer(f.context.?, &length, value);
    try std.testing.expectEqual(@as(usize, 10), length);
    try std.testing.expectEqual(@intFromPtr(data), @intFromPtr(actual));
    try std.testing.expectEqualSlices(u8, "same-store", actual[0..length]);
    try std.testing.expectEqual(@as(usize, 0), f.count());
}

test "Node managed buffers native map operations preserve an actual pending reason" {
    var f: Fixture = .{}; try f.init(true); defer f.deinit();
    var token = try f.make(5, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const reason = c.JS_NewError(f.context.?);
    defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(!c.JS_IsException(reason));
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    const buffer = f.adopt(&token);
    var taken = f.take(buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    try std.testing.expect(c.JS_HasException(f.context.?));
    const actual = c.JS_GetException(f.context.?);
    defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, actual));
    try std.testing.expectEqual(@as(usize, 5), c.JS_PiArrayBufferBackingStoreByteLength(&taken));
}

test "Node managed buffers real node allocation retries through the actual native new handler" {
    var f: Fixture = .{}; try f.init(true); defer f.deinit();
    var token = try f.make(19, true);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const owner = token.owner;
    var operation: Insert = .{ .fixture = &f, .token = &token };
    var observation: c.PiEnvironmentRetryObservation = std.mem.zeroes(c.PiEnvironmentRetryObservation);
    try std.testing.expectEqual(@as(c_int, 0),
        c.pi_environment_test_retry(f.memory, memory_limit, Insert.run, &operation, &observation));
    try std.testing.expect(operation.called);
    try std.testing.expectEqual(@as(usize, 1), observation.calls);
    try std.testing.expectEqual(memory_limit, observation.first_used);
    try std.testing.expect(observation.reserved != 0);
    try empty(&token);
    try std.testing.expectEqual(@as(usize, 1), f.count());
    try std.testing.expect(!c.JS_HasException(f.context.?));
    var taken = f.take(operation.buffer);
    defer c.JS_PiReleaseArrayBufferBackingStore(&taken);
    try std.testing.expect(taken.owner == owner);
    try std.testing.expectEqual(@as(usize, 19), c.JS_PiArrayBufferBackingStoreByteLength(&taken));
}

test "Node managed buffers all native backing and table charges retire after the originating runtime" {
    var f: Fixture = .{}; try f.init(true); defer f.deinit();
    for (0..24) |index| {
        var token = try f.make(index + 1, true);
        defer c.JS_PiReleaseArrayBufferBackingStore(&token);
        _ = f.adopt(&token);
        try empty(&token);
    }
    try std.testing.expectEqual(@as(usize, 24), f.count());
    f.closeVm();
    try std.testing.expect(f.runtime == null and f.context == null);
    try std.testing.expect(f.used() > f.storage_bytes);
    try std.testing.expectEqual(@as(usize, 24), f.count());
    f.destroyTable();
    try std.testing.expectEqual(@as(usize, 0), f.used());
}

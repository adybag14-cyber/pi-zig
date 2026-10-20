//! Native allocation precedes every JavaScript ArrayBuffer wrapper in this root.
//! These controls exercise the actual installed storage owner and intrinsic
//! adoption. The original embedding GC/retry/fatal policy is a separate owner.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const memory_limit: usize = 64 * 1024 * 1024;
fn emptyStore() c.JSPiArrayBufferBackingStore { return std.mem.zeroes(c.JSPiArrayBufferBackingStore); }
fn emptyLease() c.JSPiArrayBufferLease { return std.mem.zeroes(c.JSPiArrayBufferLease); }
fn expectEmpty(store: *const c.JSPiArrayBufferBackingStore) !void {
    try std.testing.expect(store.owner == null);
    try std.testing.expectEqual(@as(usize, 0), store.byte_length);
    try std.testing.expect(store.functions.allocate == null and store.functions.shared_owner == null);
    try std.testing.expect(store.functions.data == null and store.functions.byte_length == null);
    try std.testing.expect(store.functions.resize == null and store.functions.retain == null);
    try std.testing.expect(store.functions.release == null and store.functions.opaque == null);
    try std.testing.expect(c.JS_PiArrayBufferBackingStoreData(store) == null);
    try std.testing.expectEqual(@as(usize, 0), c.JS_PiArrayBufferBackingStoreByteLength(store));
}
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,

    fn initRuntime(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
    }
    fn init(self: *Fixture) !void {
        try self.initRuntime();
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn deinit(self: *Fixture) void {
        if (self.context) |context| {
            self.context = null;
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            _ = c.JS_PiCheckExecutionTermination(context);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            while (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            if (c.JS_HasException(self.context.?))
                c.JS_FreeValue(self.context.?, c.JS_GetException(self.context.?));
            return error.NativeBackingStoreControlJavaScriptException;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "native-backing-store-control.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        c.JS_FreeValue(self.context.?, try self.eval(source));
    }
    fn set(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        const status = c.JS_SetPropertyStr(self.context.?, global_object, name,
            c.JS_DupValue(self.context.?, value));
        if (status < 0 or c.JS_HasException(self.context.?)) {
            if (c.JS_HasException(self.context.?))
                c.JS_FreeValue(self.context.?, c.JS_GetException(self.context.?));
            return error.NativeBackingStoreControlPropertyFailure;
        }
    }
    fn allocate(self: *Fixture, length: usize, zero_initialized: bool) !c.JSPiArrayBufferBackingStore {
        var store = emptyStore();
        errdefer c.JS_PiReleaseArrayBufferBackingStore(&store);
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_PiTryNewArrayBufferBackingStore(self.runtime.?, length, zero_initialized, &store));
        try std.testing.expect(store.owner != null);
        return store;
    }
    fn exception(self: *Fixture, result: c.JSValue) !c.JSValue {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn view(self: *Fixture, buffer: c.JSValue) !c.JSValue {
        const args = [_]c.JSValue{buffer};
        return self.checked(c.JS_NewTypedArray(self.context.?, args.len, @constCast(&args), c.JS_TYPED_ARRAY_UINT8));
    }
    fn lease(self: *Fixture, view_value: c.JSValue) !c.JSPiArrayBufferLease {
        var result = emptyLease();
        errdefer c.JS_PiReleaseArrayBufferLease(&result);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_PiAcquireArrayBufferView(self.context.?, view_value, &result));
        try std.testing.expect(!c.JS_HasException(self.context.?));
        return result;
    }
};
const Budget = struct {
    memory: ?*anyopaque,
    bytes: usize,
    fn fill(f: *Fixture) !Budget {
        const bytes = memory_limit - c.pi_js_native_memory_used(f.memory);
        try std.testing.expectEqual(@as(c_int, 1), c.pi_js_native_memory_reserve(f.memory, bytes));
        return .{ .memory = f.memory, .bytes = bytes };
    }
    fn release(self: *Budget) void {
        const bytes = self.bytes;
        self.bytes = 0;
        if (bytes != 0) c.pi_js_native_memory_release(self.memory, bytes);
    }
};

test "VM native backing store allocates before a context with no JS wrapper or heap allocation" {
    const allocations = c.pi_js_array_buffer_backing_allocations();
    var f: Fixture = .{}; try f.initRuntime(); defer f.deinit();
    var before: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(f.runtime.?, &before);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    var store = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const status = c.JS_PiTryNewArrayBufferBackingStore(f.runtime.?, 32, false, &store);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    var after: c.JSMemoryUsage = undefined;
    c.JS_ComputeMemoryUsage(f.runtime.?, &after);
    try std.testing.expectEqual(@as(c_int, 1), status);
    try std.testing.expect(store.owner != null);
    try std.testing.expectEqual(@as(usize, 32), c.JS_PiArrayBufferBackingStoreByteLength(&store));
    try std.testing.expect(c.JS_PiArrayBufferBackingStoreData(&store) != null);
    try std.testing.expectEqual(before.obj_count, after.obj_count);
    try std.testing.expectEqual(before.malloc_count, after.malloc_count);
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    try std.testing.expectEqual(allocations + 1, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(store.owner));
}

test "VM native backing store exposes real writable bytes before consuming adoption without a copy" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(64, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const owner = store.owner;
    const data = c.JS_PiArrayBufferBackingStoreData(&store);
    for (data[0..64], 0..) |*byte, index| byte.* = @intCast(index + 7);
    const allocations = c.pi_js_array_buffer_backing_allocations();
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store));
    defer c.JS_FreeValue(f.context.?, buffer);
    try expectEmpty(&store);
    try std.testing.expect(c.JS_IsArrayBuffer(buffer));
    var length: usize = 0;
    const actual = c.JS_GetArrayBuffer(f.context.?, &length, buffer);
    try std.testing.expectEqual(@as(usize, 64), length);
    try std.testing.expect(actual == data);
    for (actual[0..64], 0..) |byte, index| try std.testing.expectEqual(@as(u8, @intCast(index + 7)), byte);
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(owner));
    const view_value = try f.view(buffer); defer c.JS_FreeValue(f.context.?, view_value);
    var lease = try f.lease(view_value); defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expect(lease.owner == owner and lease.data == data);
    try std.testing.expectEqual(@as(usize, 64), lease.byte_length);
}

test "VM native backing store zero initialization is a separate actual allocation mode" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(97, true); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const data = c.JS_PiArrayBufferBackingStoreData(&store);
    for (data[0..97]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    data[96] = 179;
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store));
    defer c.JS_FreeValue(f.context.?, buffer);
    try f.set("buffer", buffer);
    try f.run("const v=new Uint8Array(buffer);if(v.length!==97||v[96]!==179||v[0]!==0)throw Error('native initialized bytes');");
}

test "VM native backing store zero length retains a real owner with null logical data" {
    const allocations = c.pi_js_array_buffer_backing_allocations();
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(0, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const owner = store.owner;
    try std.testing.expect(c.JS_PiArrayBufferBackingStoreData(&store) == null);
    try std.testing.expectEqual(@as(usize, 0), c.JS_PiArrayBufferBackingStoreByteLength(&store));
    var held = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&held);
    c.JS_PiDupArrayBufferBackingStore(&held, &store);
    try std.testing.expect(held.owner == owner);
    try std.testing.expectEqual(@as(usize, 2), c.pi_js_array_buffer_backing_references(owner));
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store));
    defer c.JS_FreeValue(f.context.?, buffer);
    try expectEmpty(&store);
    const view_value = try f.view(buffer); defer c.JS_FreeValue(f.context.?, view_value);
    var lease = try f.lease(view_value); defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expect(lease.owner == owner);
    try std.testing.expectEqual(@as(usize, 0), lease.byte_length);
    try std.testing.expectEqual(allocations + 1, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(@as(usize, 3), c.pi_js_array_buffer_backing_references(owner));
}

test "VM native backing store duplicates and releases independent entitlements with exact charge retirement" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const used = c.pi_js_native_memory_used(f.memory);
    const allocations = c.pi_js_array_buffer_backing_allocations();
    var first = try f.allocate(31, false); defer c.JS_PiReleaseArrayBufferBackingStore(&first);
    var second = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&second);
    c.JS_PiDupArrayBufferBackingStore(&second, &first);
    const owner = first.owner;
    c.JS_PiArrayBufferBackingStoreData(&first)[0] = 81;
    c.JS_PiReleaseArrayBufferBackingStore(&first);
    try expectEmpty(&first);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(owner));
    try std.testing.expectEqual(@as(u8, 81), c.JS_PiArrayBufferBackingStoreData(&second)[0]);
    c.JS_PiReleaseArrayBufferBackingStore(&second);
    try expectEmpty(&second);
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
    c.JS_PiReleaseArrayBufferBackingStore(&second);
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
}

test "VM native backing store adoption uses the intrinsic realm despite poisoned public constructors" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.intrinsicArrayBuffer=ArrayBuffer;globalThis.hits=0;
        \\Object.defineProperty(globalThis,'ArrayBuffer',{configurable:true,get(){++hits;throw Error('public constructor');}});
    );
    var store = try f.allocate(16, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    @memset(c.JS_PiArrayBufferBackingStoreData(&store)[0..16], 29);
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store));
    defer c.JS_FreeValue(f.context.?, buffer);
    try f.set("buffer", buffer);
    try f.run("if(hits!==0||Object.getPrototypeOf(buffer)!==intrinsicArrayBuffer.prototype||buffer.resizable||buffer.byteLength!==16||new Uint8Array(buffer)[15]!==29)throw Error('intrinsic adoption');");
}

test "VM native backing store wrapper allocation failure consumes exactly its native entitlement" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const allocations = c.pi_js_array_buffer_backing_allocations();
    var store = try f.allocate(16, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    defer c.JS_FreeValue(f.context.?, result);
    const reason = try f.exception(result); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsNull(reason));
    try expectEmpty(&store);
    try std.testing.expect(c.JS_PiOutOfMemoryOccurrence(f.runtime.?) > occurrence);
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
}

test "VM native backing store prior ordinary pending consumes the store before any wrapper allocation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
    const allocations = c.pi_js_array_buffer_backing_allocations();
    var store = try f.allocate(8, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    defer c.JS_FreeValue(f.context.?, result);
    const actual = try f.exception(result); defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
    try std.testing.expect(!c.JS_IsUncatchableError(actual));
    try expectEmpty(&store);
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
}

test "VM native backing store prior generic fatal is preserved without an allocation report" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
    c.JS_SetUncatchableError(f.context.?, reason);
    var store = try f.allocate(8, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    const result = c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store);
    defer c.JS_FreeValue(f.context.?, result);
    const actual = try f.exception(result); defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try expectEmpty(&store);
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
}

test "VM native backing store prior native termination remains the actual published event" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(8, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
    const result = c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    try expectEmpty(&store);
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    const actual = c.JS_GetException(f.context.?);
    defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_PiIsExecutionTermination(actual));
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, actual));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM native backing store native quota and overflow failure leave pending and OOM history unchanged" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
    const used = c.pi_js_native_memory_used(f.memory);
    const allocations = c.pi_js_array_buffer_backing_allocations();
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.runtime.?);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    var store = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    var budget = try Budget.fill(&f); defer budget.release();
    const status = c.JS_PiTryNewArrayBufferBackingStore(f.runtime.?, 32, false, &store);
    budget.release();
    try std.testing.expectEqual(@as(c_int, -1), status);
    try expectEmpty(&store);
    try std.testing.expectEqual(@as(c_int, -1),
        c.JS_PiTryNewArrayBufferBackingStore(f.runtime.?, std.math.maxInt(usize), false, &store));
    try expectEmpty(&store);
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.runtime.?));
    try std.testing.expect(c.JS_HasException(f.context.?));
    const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
}

test "VM native backing store absence of a provider returns empty without inventing a JS failure" {
    const runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
    defer c.JS_FreeRuntime(runtime);
    const context = c.JS_NewContext(runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(context);
    var store = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(runtime);
    c.JS_SetMemoryLimit(runtime, 1);
    const status = c.JS_PiTryNewArrayBufferBackingStore(runtime, 32, false, &store);
    c.JS_SetMemoryLimit(runtime, 0);
    try std.testing.expectEqual(@as(c_int, 0), status);
    try expectEmpty(&store);
    try std.testing.expect(!c.JS_HasException(context));
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(runtime));
}

test "VM native backing store adoption rejects another native allocation domain and consumes the original owner" {
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    var second: Fixture = .{}; try second.init(); defer second.deinit();
    const used = c.pi_js_native_memory_used(first.memory);
    const allocations = c.pi_js_array_buffer_backing_allocations();
    var store = try first.allocate(16, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    const result = c.JS_PiAdoptArrayBufferBackingStore(second.context.?, &store);
    defer c.JS_FreeValue(second.context.?, result);
    const reason = try second.exception(result); defer c.JS_FreeValue(second.context.?, reason);
    try std.testing.expect(c.JS_IsError(reason) and !c.JS_IsUncatchableError(reason));
    try expectEmpty(&store);
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(first.memory));
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expect(!c.JS_HasException(first.context.?));
}

test "VM native backing store missing owner is distinct from an owned zero-length store" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = emptyStore();
    const result = c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store);
    defer c.JS_FreeValue(f.context.?, result);
    const reason = try f.exception(result); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsError(reason) and !c.JS_IsUncatchableError(reason));
    try expectEmpty(&store);
    var zero = try f.allocate(0, true); defer c.JS_PiReleaseArrayBufferBackingStore(&zero);
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &zero));
    defer c.JS_FreeValue(f.context.?, buffer);
    try std.testing.expect(c.JS_IsArrayBuffer(buffer));
    try expectEmpty(&zero);
}

const NativeWorker = struct {
    store: c.JSPiArrayBufferBackingStore = std.mem.zeroes(c.JSPiArrayBufferBackingStore),
    proceed: std.atomic.Value(bool) = .init(false),
    observed: bool = false,
    fn run(self: *NativeWorker) void {
        while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        const data = c.JS_PiArrayBufferBackingStoreData(&self.store);
        self.observed = c.JS_PiArrayBufferBackingStoreByteLength(&self.store) == 32 and data[0] == 211;
        for (0..64) |_| {
            var temporary = emptyStore();
            c.JS_PiDupArrayBufferBackingStore(&temporary, &self.store);
            c.JS_PiReleaseArrayBufferBackingStore(&temporary);
        }
        c.JS_PiReleaseArrayBufferBackingStore(&self.store);
    }
};
test "VM native backing store workers retain and retire storage after its runtime and caller domain retire" {
    const allocations = c.pi_js_array_buffer_backing_allocations();
    const owners = c.pi_js_native_memory_owners();
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(32, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    c.JS_PiArrayBufferBackingStoreData(&store)[0] = 211;
    var first: NativeWorker = .{};
    var second: NativeWorker = .{};
    defer c.JS_PiReleaseArrayBufferBackingStore(&first.store);
    defer c.JS_PiReleaseArrayBufferBackingStore(&second.store);
    c.JS_PiDupArrayBufferBackingStore(&first.store, &store);
    c.JS_PiDupArrayBufferBackingStore(&second.store, &store);
    const first_thread = try std.Thread.spawn(.{}, NativeWorker.run, .{&first});
    var first_joined = false;
    defer { if (!first_joined) { first.proceed.store(true, .release); first_thread.join(); } }
    const second_thread = try std.Thread.spawn(.{}, NativeWorker.run, .{&second});
    var second_joined = false;
    defer { if (!second_joined) { second.proceed.store(true, .release); second_thread.join(); } }
    c.JS_PiReleaseArrayBufferBackingStore(&store);
    f.deinit();
    try std.testing.expectEqual(allocations + 1, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    first.proceed.store(true, .release);
    second.proceed.store(true, .release);
    first_thread.join(); first_joined = true;
    second_thread.join(); second_joined = true;
    try std.testing.expect(first.observed and second.observed);
    try expectEmpty(&first.store); try expectEmpty(&second.store);
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

test "VM native backing store short-copy ordering retires the old allocation before wrapper adoption" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const allocations = c.pi_js_array_buffer_backing_allocations();
    var original = try f.allocate(64, false); defer c.JS_PiReleaseArrayBufferBackingStore(&original);
    @memset(c.JS_PiArrayBufferBackingStoreData(&original)[0..64], 117);
    var shorter = try f.allocate(17, false); defer c.JS_PiReleaseArrayBufferBackingStore(&shorter);
    const owner = shorter.owner;
    const data = c.JS_PiArrayBufferBackingStoreData(&shorter);
    @memcpy(data[0..17], c.JS_PiArrayBufferBackingStoreData(&original)[0..17]);
    try std.testing.expectEqual(allocations + 2, c.pi_js_array_buffer_backing_allocations());
    c.JS_PiReleaseArrayBufferBackingStore(&original);
    try expectEmpty(&original);
    try std.testing.expectEqual(allocations + 1, c.pi_js_array_buffer_backing_allocations());
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &shorter));
    defer c.JS_FreeValue(f.context.?, buffer);
    try expectEmpty(&shorter);
    var length: usize = 0;
    try std.testing.expect(c.JS_GetArrayBuffer(f.context.?, &length, buffer) == data);
    try std.testing.expectEqual(@as(usize, 17), length);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(owner));
    for (data[0..17]) |byte| try std.testing.expectEqual(@as(u8, 117), byte);
}

test "VM native backing store adopted wrapper and actual view lease retain independent detach owners" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(16, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    var held = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&held);
    c.JS_PiDupArrayBufferBackingStore(&held, &store);
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store));
    defer c.JS_FreeValue(f.context.?, buffer);
    const view_value = try f.view(buffer); defer c.JS_FreeValue(f.context.?, view_value);
    var lease = try f.lease(view_value); defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expect(lease.owner == held.owner);
    try std.testing.expectEqual(@as(usize, 3), c.pi_js_array_buffer_backing_references(held.owner));
    c.JS_DetachArrayBuffer(f.context.?, buffer);
    try std.testing.expectEqual(@as(usize, 2), c.pi_js_array_buffer_backing_references(held.owner));
    try std.testing.expectEqual(@as(usize, 0), c.JS_PiArrayBufferViewByteLength(view_value));
    lease.data[5] = 93;
    try std.testing.expectEqual(@as(u8, 93), c.JS_PiArrayBufferBackingStoreData(&held)[5]);
    c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(held.owner));
}

test "VM native backing store explicit duplicate can back two intrinsic wrappers without copying" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(9, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    var duplicate = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&duplicate);
    c.JS_PiDupArrayBufferBackingStore(&duplicate, &store);
    const owner = store.owner;
    const first = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store));
    defer c.JS_FreeValue(f.context.?, first);
    const second = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &duplicate));
    defer c.JS_FreeValue(f.context.?, second);
    var first_length: usize = 0; var second_length: usize = 0;
    const first_data = c.JS_GetArrayBuffer(f.context.?, &first_length, first);
    const second_data = c.JS_GetArrayBuffer(f.context.?, &second_length, second);
    try std.testing.expect(first_data == second_data);
    try std.testing.expectEqual(@as(usize, 9), first_length);
    try std.testing.expectEqual(first_length, second_length);
    first_data[8] = 47;
    try std.testing.expectEqual(@as(u8, 47), second_data[8]);
    c.JS_DetachArrayBuffer(f.context.?, first);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(owner));
    try std.testing.expectEqual(@as(u8, 47), second_data[8]);
}

test "VM native backing store adopted buffers preserve actual equal and changed transfer ownership" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(16, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    @memset(c.JS_PiArrayBufferBackingStoreData(&store)[0..16], 23);
    var held = emptyStore(); defer c.JS_PiReleaseArrayBufferBackingStore(&held);
    c.JS_PiDupArrayBufferBackingStore(&held, &store);
    const buffer = try f.checked(c.JS_PiAdoptArrayBufferBackingStore(f.context.?, &store));
    defer c.JS_FreeValue(f.context.?, buffer);
    try f.set("buffer", buffer);
    const allocations = c.pi_js_array_buffer_backing_allocations();
    try f.run("globalThis.equal=buffer.transfer(16);");
    const equal = try f.eval("equal"); defer c.JS_FreeValue(f.context.?, equal);
    const view_value = try f.view(equal); defer c.JS_FreeValue(f.context.?, view_value);
    var lease = try f.lease(view_value); defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expect(lease.owner == held.owner);
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try f.run("globalThis.changed=equal.transfer(24);const v=new Uint8Array(changed);if(v.length!==24||v[15]!==23||v[16]!==0||v[23]!==0)throw Error('changed transfer');");
    try std.testing.expectEqual(allocations + 1, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(@as(u8, 23), c.JS_PiArrayBufferBackingStoreData(&held)[15]);
    try std.testing.expectEqual(@as(usize, 16), c.JS_PiArrayBufferBackingStoreByteLength(&held));
}

test "VM native backing store uninitialized mode leaves JS fixed resizable and shared initialization intact" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var store = try f.allocate(32, false); defer c.JS_PiReleaseArrayBufferBackingStore(&store);
    @memset(c.JS_PiArrayBufferBackingStoreData(&store)[0..32], 151);
    try f.run(
        \\const fixed=new ArrayBuffer(32),rab=new ArrayBuffer(8,{maxByteLength:32}),shared=new SharedArrayBuffer(8,{maxByteLength:32});
        \\for(const buffer of [fixed,rab,shared])if(new Uint8Array(buffer).some(value=>value!==0))throw Error('initial zero');
        \\rab.resize(32);shared.grow(32);
        \\for(const buffer of [rab,shared])if(new Uint8Array(buffer).some(value=>value!==0))throw Error('growth zero');
    );
    for (c.JS_PiArrayBufferBackingStoreData(&store)[0..32]) |byte|
        try std.testing.expectEqual(@as(u8, 151), byte);
}

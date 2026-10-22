//! Intrinsic Buffer::Data address controls over the actual VM and physical
//! native ArrayBuffer storage. No user-buffer listener, FileHandle template,
//! production trace/bootstrap, or asynchronous borrowed-buffer use is claimed.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const memory_limit: usize = 64 * 1024 * 1024;
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
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            c.JS_FreeValue(self.context.?, c.JS_GetException(self.context.?));
            return error.ActualViewDataControlJavaScriptException;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-view-data-control.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        c.JS_FreeValue(self.context.?, try self.eval(source));
    }
    fn set(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, object);
        const status = c.JS_SetPropertyStr(self.context.?, object, name,
            c.JS_DupValue(self.context.?, value));
        if (status < 0 or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, c.JS_GetException(self.context.?));
            return error.ActualViewDataControlPropertyFailure;
        }
    }
    fn data(self: *Fixture, view: c.JSValue, expected: usize, length: usize) !void {
        try std.testing.expectEqual(expected, @intFromPtr(c.JS_PiArrayBufferViewData(view)));
        try std.testing.expectEqual(length, c.JS_PiArrayBufferViewByteLength(view));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn backing(self: *Fixture, value: c.JSValue, length: usize) ![*c]u8 {
        var actual_length: usize = 0;
        const actual = c.JS_GetArrayBuffer(self.context.?, &actual_length, value);
        try std.testing.expect(!c.JS_HasException(self.context.?));
        try std.testing.expectEqual(length, actual_length);
        return actual;
    }
};
const Clone = struct {
    bytes: []u8,
    backing: ?*anyopaque,

    fn init(f: *Fixture, value: c.JSValue) !Clone {
        var length: usize = 0;
        var table: c.JSSABTab = std.mem.zeroes(c.JSSABTab);
        const raw = c.JS_WriteObject2(f.context.?, &length, value, c.JS_WRITE_OBJ_SAB, &table);
        defer c.js_free(f.context.?, @ptrCast(table.tab));
        if (raw == null) return error.ActualViewDataSerializationFailure;
        defer c.js_free(f.context.?, raw);
        try std.testing.expectEqual(@as(usize, 1), table.len);
        const bytes = try std.testing.allocator.dupe(u8, raw[0..length]);
        const backing: ?*anyopaque = @ptrCast(table.tab[0]);
        c.pi_js_retain_shared_buffer(backing);
        return .{ .bytes = bytes, .backing = backing };
    }
    fn read(self: *const Clone, f: *Fixture) !c.JSValue {
        return f.checked(c.JS_ReadObject(f.context.?, self.bytes.ptr, self.bytes.len, c.JS_READ_OBJ_SAB));
    }
    fn deinit(self: *Clone) void {
        const backing = self.backing;
        self.backing = null;
        if (backing) |actual| c.pi_js_release_shared_buffer(actual);
        std.testing.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

test "VM view data every typed-array width and DataView expose the physical backing offset" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const buffer = try f.eval("new ArrayBuffer(64)");
    defer c.JS_FreeValue(f.context.?, buffer);
    const base = try f.backing(buffer, 64);
    try std.testing.expect(base != null);
    inline for (.{
        .{ c.JS_TYPED_ARRAY_UINT8C, 1 }, .{ c.JS_TYPED_ARRAY_INT8, 1 },
        .{ c.JS_TYPED_ARRAY_UINT8, 1 }, .{ c.JS_TYPED_ARRAY_INT16, 2 },
        .{ c.JS_TYPED_ARRAY_UINT16, 2 }, .{ c.JS_TYPED_ARRAY_INT32, 4 },
        .{ c.JS_TYPED_ARRAY_UINT32, 4 }, .{ c.JS_TYPED_ARRAY_BIG_INT64, 8 },
        .{ c.JS_TYPED_ARRAY_BIG_UINT64, 8 }, .{ c.JS_TYPED_ARRAY_FLOAT16, 2 },
        .{ c.JS_TYPED_ARRAY_FLOAT32, 4 }, .{ c.JS_TYPED_ARRAY_FLOAT64, 8 },
    }) |pair| {
        const args = [_]c.JSValue{ buffer, c.JS_NewInt32(f.context.?, 8), c.JS_NewInt32(f.context.?, 3) };
        const view = try f.checked(c.JS_NewTypedArray(f.context.?, args.len, @constCast(&args), pair[0]));
        defer c.JS_FreeValue(f.context.?, view);
        try f.data(view, @intFromPtr(base) + 8, 3 * pair[1]);
        c.JS_PiArrayBufferViewData(view)[0] = 0x6d;
        try std.testing.expectEqual(@as(u8, 0x6d), base[8]);
        base[8] = 0x2a;
        try std.testing.expectEqual(@as(u8, 0x2a), c.JS_PiArrayBufferViewData(view)[0]);
    }
    try f.set("buffer", buffer);
    const data = try f.eval("new DataView(buffer,7,9)");
    defer c.JS_FreeValue(f.context.?, data);
    try f.data(data, @intFromPtr(base) + 7, 9);
    c.JS_PiArrayBufferViewData(data)[8] = 0x71;
    try std.testing.expectEqual(@as(u8, 0x71), base[15]);
}

test "VM view data live empty views retain their exact end pointer" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const buffer = try f.eval("new ArrayBuffer(16)");
    defer c.JS_FreeValue(f.context.?, buffer);
    const base = try f.backing(buffer, 16);
    try std.testing.expect(base != null);
    try f.set("buffer", buffer);
    inline for (.{ "new Uint8Array(buffer,16,0)", "new Uint32Array(buffer,16,0)", "new DataView(buffer,16,0)" }) |expression| {
        const view = try f.eval(expression);
        defer c.JS_FreeValue(f.context.?, view);
        try f.data(view, @intFromPtr(base) + 16, 0);
        // The one-past-end address is observed only; no zero-length dereference.
    }
}

test "VM view data bypasses getters and rejects forged live and revoked proxy brands" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.calls=0;globalThis.buffer=new ArrayBuffer(32);
        \\globalThis.typed=new Uint16Array(buffer,4,5);globalThis.data=new DataView(buffer,3,7);
        \\for(const view of [typed,data])for(const name of ['buffer','byteOffset','byteLength','length'])
        \\ Object.defineProperty(view,name,{get(){++calls;throw Error('guest view getter');}});
        \\globalThis.proxy=new Proxy(typed,{get(){++calls;throw Error('proxy getter');}});
        \\const pair=Proxy.revocable(data,{});globalThis.revoked=pair.proxy;pair.revoke();
    );
    const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
    const base = try f.backing(buffer, 32);
    const typed = try f.eval("typed"); defer c.JS_FreeValue(f.context.?, typed);
    const data = try f.eval("data"); defer c.JS_FreeValue(f.context.?, data);
    try f.data(typed, @intFromPtr(base) + 4, 10);
    try f.data(data, @intFromPtr(base) + 3, 7);
    inline for (.{ "proxy", "revoked", "buffer", "new SharedArrayBuffer(9)", "({byteOffset:99})",
        "Object.create(Uint8Array.prototype)", "Object.create(DataView.prototype)", "null", "undefined", "1", "'text'" }) |expression| {
        const invalid = try f.eval(expression);
        defer c.JS_FreeValue(f.context.?, invalid);
        try f.data(invalid, 0, 0);
    }
    try f.run("if(calls!==0)throw Error('intrinsic data entered guest code');");
}

test "VM view data detached typed and DataView addresses are null while lease acquisition still throws" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(16);globalThis.typed=new Uint32Array(buffer,4,2);globalThis.data=new DataView(buffer,3,6);");
    const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
    const typed = try f.eval("typed"); defer c.JS_FreeValue(f.context.?, typed);
    const data = try f.eval("data"); defer c.JS_FreeValue(f.context.?, data);
    c.JS_DetachArrayBuffer(f.context.?, buffer);
    for ([_]c.JSValue{ typed, data }) |view| {
        try f.data(view, 0, 0);
        var lease: c.JSPiArrayBufferLease = std.mem.zeroes(c.JSPiArrayBufferLease);
        defer c.JS_PiReleaseArrayBufferLease(&lease);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiAcquireArrayBufferView(f.context.?, view, &lease));
        try std.testing.expect(lease.owner == null and lease.data == null and lease.byte_length == 0);
        try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsError(reason) and !c.JS_IsUncatchableError(reason));
    }
}

test "VM view data fixed resizable views preserve stored offsets while out of bounds and after regrowth" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.buffer=new ArrayBuffer(16,{maxByteLength:32});
        \\globalThis.typed=new Uint32Array(buffer,4,2);globalThis.data=new DataView(buffer,5,6);
        \\globalThis.empty=new DataView(buffer,12,0);
    );
    const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
    const base = try f.backing(buffer, 16);
    const typed = try f.eval("typed"); defer c.JS_FreeValue(f.context.?, typed);
    const data = try f.eval("data"); defer c.JS_FreeValue(f.context.?, data);
    const empty = try f.eval("empty"); defer c.JS_FreeValue(f.context.?, empty);
    try f.run("buffer.resize(3)");
    try f.data(typed, @intFromPtr(base) + 4, 0);
    try f.data(data, @intFromPtr(base) + 5, 0);
    try f.data(empty, @intFromPtr(base) + 12, 0);
    // These OOB addresses are not dereferenced. The actual engine storage
    // reserves native capacity and does not move on resize.
    try std.testing.expectEqual(@intFromPtr(base), @intFromPtr(try f.backing(buffer, 3)));
    try f.run("buffer.resize(12)");
    try f.data(typed, @intFromPtr(base) + 4, 8);
    try f.data(data, @intFromPtr(base) + 5, 6);
    try f.data(empty, @intFromPtr(base) + 12, 0);
    c.JS_PiArrayBufferViewData(data)[5] = 0x35;
    try std.testing.expectEqual(@as(u8, 0x35), base[10]);
}

test "VM view data tracking resizable views keep the address independently of rounded usable length" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(11,{maxByteLength:32});globalThis.typed=new Uint32Array(buffer,4);globalThis.data=new DataView(buffer,4);");
    const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
    const base = try f.backing(buffer, 11);
    const typed = try f.eval("typed"); defer c.JS_FreeValue(f.context.?, typed);
    const data = try f.eval("data"); defer c.JS_FreeValue(f.context.?, data);
    try f.data(typed, @intFromPtr(base) + 4, 4); try f.data(data, @intFromPtr(base) + 4, 7);
    try f.run("buffer.resize(6)");
    try f.data(typed, @intFromPtr(base) + 4, 0); try f.data(data, @intFromPtr(base) + 4, 2);
    try f.run("buffer.resize(4)");
    try f.data(typed, @intFromPtr(base) + 4, 0); try f.data(data, @intFromPtr(base) + 4, 0);
    try f.run("buffer.resize(0)");
    try f.data(typed, @intFromPtr(base) + 4, 0); try f.data(data, @intFromPtr(base) + 4, 0);
    try f.run("buffer.resize(15)");
    try f.data(typed, @intFromPtr(base) + 4, 8); try f.data(data, @intFromPtr(base) + 4, 11);
}

test "VM view data shared aliases expose one native address across real runtime growth" {
    var source: Fixture = .{}; try source.init(); defer source.deinit();
    var receiver: Fixture = .{}; try receiver.init(); defer receiver.deinit();
    const shared = try source.eval("globalThis.shared=new SharedArrayBuffer(8,{maxByteLength:32})");
    defer c.JS_FreeValue(source.context.?, shared);
    var clone = try Clone.init(&source, shared); defer clone.deinit();
    const other = try clone.read(&receiver); defer c.JS_FreeValue(receiver.context.?, other);
    try receiver.set("shared", other);
    try receiver.run("globalThis.typed=new Uint32Array(shared,4);globalThis.data=new DataView(shared,3);");
    const typed = try receiver.eval("typed"); defer c.JS_FreeValue(receiver.context.?, typed);
    const data = try receiver.eval("data"); defer c.JS_FreeValue(receiver.context.?, data);
    const source_view = try source.eval("new Uint8Array(shared)");
    defer c.JS_FreeValue(source.context.?, source_view);
    const base = c.JS_PiArrayBufferViewData(source_view);
    try std.testing.expect(base != null);
    try receiver.data(typed, @intFromPtr(base) + 4, 4);
    try receiver.data(data, @intFromPtr(base) + 3, 5);
    try source.run("shared.grow(19)");
    // No receiver getter or lease acquisition precedes these intrinsic reads.
    try receiver.data(data, @intFromPtr(base) + 3, 16);
    try receiver.data(typed, @intFromPtr(base) + 4, 12);
    c.JS_PiArrayBufferViewData(data)[15] = 0x63;
    try std.testing.expectEqual(@as(u8, 0x63), base[18]);
}

test "VM view data allocates nothing under the actual VM memory limit" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const view = try f.eval("new DataView(new ArrayBuffer(17),3,11)");
    defer c.JS_FreeValue(f.context.?, view);
    var lease: c.JSPiArrayBufferLease = std.mem.zeroes(c.JSPiArrayBufferLease);
    defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiAcquireArrayBufferView(f.context.?, view, &lease));
    const invalid = try f.eval("({})"); defer c.JS_FreeValue(f.context.?, invalid);
    const used = c.pi_js_native_memory_used(f.memory);
    const references = c.pi_js_array_buffer_backing_references(lease.owner);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    defer c.JS_SetMemoryLimit(f.runtime.?, 0);
    for (0..16) |_| {
        try f.data(view, @intFromPtr(lease.data), 11);
        try f.data(invalid, 0, 0);
    }
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
    try std.testing.expectEqual(references, c.pi_js_array_buffer_backing_references(lease.owner));
}

test "VM view data preserves actual ordinary uncatchable and private termination completions" {
    for (0..3) |mode| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const buffer = try f.eval("new ArrayBuffer(16)"); defer c.JS_FreeValue(f.context.?, buffer);
        const base = try f.backing(buffer, 16);
        try f.set("buffer", buffer);
        const view = try f.eval("new Uint16Array(buffer,4,4)"); defer c.JS_FreeValue(f.context.?, view);
        const reason = if (mode == 2) c.JS_PiNativeTerminationResult() else try f.checked(c.JS_NewError(f.context.?));
        defer c.JS_FreeValue(f.context.?, reason);
        if (mode == 1) c.JS_SetUncatchableError(f.context.?, reason);
        // A flagged Error is still data until the following genuine throw.
        try f.data(view, @intFromPtr(base) + 4, 8);
        if (mode == 2) {
            c.JS_PiRequestExecutionTermination(f.runtime.?);
            try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
        } else _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        const generation = c.JS_PiExecutionTerminationGeneration(f.runtime.?);
        const used = c.pi_js_native_memory_used(f.memory);
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const actual_pointer = c.JS_PiArrayBufferViewData(view);
        const invalid_pointer = c.JS_PiArrayBufferViewData(c.pi_js_null());
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(@intFromPtr(base) + 4, @intFromPtr(actual_pointer));
        try std.testing.expect(invalid_pointer == null);
        try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
        try std.testing.expect(c.JS_HasException(f.context.?));
        try std.testing.expectEqual(generation, c.JS_PiExecutionTerminationGeneration(f.runtime.?));
        if (mode == 2) try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        const actual = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, actual);
        if (mode == 2) {
            try std.testing.expect(c.JS_PiIsExecutionTermination(actual));
            _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, actual));
            c.JS_PiCancelExecutionTermination(f.runtime.?);
        } else {
            try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
            try std.testing.expectEqual(mode == 1, c.JS_IsUncatchableError(actual));
        }
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
}

test "VM view data borrows without keeping the actual view or native backing alive" {
    const baseline = c.pi_js_array_buffer_backing_allocations();
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var buffer = try f.eval("new ArrayBuffer(24)"); defer c.JS_FreeValue(f.context.?, buffer);
    const args = [_]c.JSValue{ buffer, c.JS_NewInt32(f.context.?, 4), c.JS_NewInt32(f.context.?, 5) };
    var view = try f.checked(c.JS_NewTypedArray(f.context.?, args.len, @constCast(&args), c.JS_TYPED_ARRAY_UINT16));
    defer c.JS_FreeValue(f.context.?, view);
    var lease: c.JSPiArrayBufferLease = std.mem.zeroes(c.JSPiArrayBufferLease);
    defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiAcquireArrayBufferView(f.context.?, view, &lease));
    const references = c.pi_js_array_buffer_backing_references(lease.owner);
    try std.testing.expectEqual(@as(usize, 2), references);
    for (0..16) |_| try f.data(view, @intFromPtr(lease.data), 10);
    try std.testing.expectEqual(references, c.pi_js_array_buffer_backing_references(lease.owner));
    c.JS_FreeValue(f.context.?, view); view = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, buffer); buffer = c.pi_js_undefined();
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(lease.owner));
    c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expectEqual(baseline, c.pi_js_array_buffer_backing_allocations());
    // No borrowed address is used after its last actual native entitlement.
}

const External = struct {
    calls: usize = 0,
    fn retire(_: ?*c.JSRuntime, raw_owner: ?*anyopaque, ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
        const self: *External = @ptrCast(@alignCast(raw_owner.?));
        if (ptr == null or size != 0) @panic("Unexpected external storage resize");
        self.calls += 1;
        return null;
    }
};

test "VM view data observes unmanaged external storage without adding a lease or changing cleanup" {
    var external: External = .{};
    var bytes: [16]u8 = @splat(0);
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var buffer = try f.checked(c.JS_NewArrayBuffer(f.context.?, &bytes, bytes.len, 0, External.retire, &external, false));
    defer c.JS_FreeValue(f.context.?, buffer);
    const args = [_]c.JSValue{ buffer, c.JS_NewInt32(f.context.?, 4), c.JS_NewInt32(f.context.?, 3) };
    var view = try f.checked(c.JS_NewTypedArray(f.context.?, args.len, @constCast(&args), c.JS_TYPED_ARRAY_UINT16));
    defer c.JS_FreeValue(f.context.?, view);
    try f.data(view, @intFromPtr(&bytes) + 4, 6);
    c.JS_PiArrayBufferViewData(view)[5] = 0x56;
    try std.testing.expectEqual(@as(u8, 0x56), bytes[9]);
    var lease: c.JSPiArrayBufferLease = std.mem.zeroes(c.JSPiArrayBufferLease);
    defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiAcquireArrayBufferView(f.context.?, view, &lease));
    try std.testing.expect(lease.owner == null);
    try std.testing.expectEqual(@as(usize, 0), external.calls);
    c.JS_DetachArrayBuffer(f.context.?, buffer);
    try f.data(view, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), external.calls);
    c.JS_FreeValue(f.context.?, view); view = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, buffer); buffer = c.pi_js_undefined();
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), external.calls);
}

test "VM view data follows real ArrayBuffer transfer detachment and the receiving physical storage" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(16);globalThis.oldView=new Uint8Array(buffer,4,4);oldView.set([1,2,3,4]);");
    const old_view = try f.eval("oldView"); defer c.JS_FreeValue(f.context.?, old_view);
    try std.testing.expect(c.JS_PiArrayBufferViewData(old_view) != null);
    const moved = try f.eval("globalThis.moved=buffer.transfer()");
    defer c.JS_FreeValue(f.context.?, moved);
    try f.data(old_view, 0, 0);
    const base = try f.backing(moved, 16);
    const received = try f.eval("new DataView(moved,4,4)");
    defer c.JS_FreeValue(f.context.?, received);
    try f.data(received, @intFromPtr(base) + 4, 4);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, c.JS_PiArrayBufferViewData(received)[0..4]);
}

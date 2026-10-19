//! Actual allocation-owner controls for managed ArrayBuffer storage. JavaScript
//! programs execute in the linked VM; native leases and workers own only native
//! storage. Source authoring is separate from Root's build/runtime qualification.
const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    if (builtin.os.tag == .windows) {
        @cDefine("WIN32_LEAN_AND_MEAN", "1");
        @cDefine("NOMINMAX", "1");
        @cInclude("windows.h");
    }
});
const memory_limit: usize = 64 * 1024 * 1024;
fn emptyLease() c.JSPiArrayBufferLease { return std.mem.zeroes(c.JSPiArrayBufferLease); }
fn expectEmpty(lease: *const c.JSPiArrayBufferLease) !void {
    try std.testing.expect(lease.owner == null);
    try std.testing.expect(lease.data == null);
    try std.testing.expectEqual(@as(usize, 0), lease.byte_length);
    try std.testing.expect(lease.retain == null and lease.release == null);
}
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
        if (self.context) |context| { self.context = null; c.JS_FreeContext(context); }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            if (!c.JS_IsException(value)) c.JS_FreeValue(self.context.?, value);
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualBackingControlJavaScriptException;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-native-backing-control.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        const result = try self.eval(source);
        c.JS_FreeValue(self.context.?, result);
    }
    fn set(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global);
        const result = c.JS_SetPropertyStr(self.context.?, global, name, c.JS_DupValue(self.context.?, value));
        if (result < 0 or c.JS_HasException(self.context.?)) {
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualBackingControlPropertyFailure;
        }
    }
    fn lease(self: *Fixture, source: [:0]const u8) !c.JSPiArrayBufferLease {
        const view = try self.eval(source);
        defer c.JS_FreeValue(self.context.?, view);
        var result = emptyLease();
        errdefer c.JS_PiReleaseArrayBufferLease(&result);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_PiAcquireArrayBufferView(self.context.?, view, &result));
        try std.testing.expect(!c.JS_HasException(self.context.?));
        try std.testing.expect(result.owner != null and result.data != null);
        return result;
    }
    fn exception(self: *Fixture, result: c.JSValue) !c.JSValue {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn number(self: *Fixture, source: [:0]const u8) !i32 {
        const result = try self.eval(source);
        defer c.JS_FreeValue(self.context.?, result);
        var value: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &value, result));
        return value;
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
        const bytes = self.bytes; self.bytes = 0;
        if (bytes != 0) c.pi_js_native_memory_release(self.memory, bytes);
    }
};
// Trusted same-process SAB serialization. The table is explicitly retained,
// independently of both runtimes and the copied serialized bytes.
const Clone = struct {
    bytes: []u8,
    backing: ?*anyopaque,
    fn init(f: *Fixture, source: [:0]const u8) !Clone {
        const value = try f.eval(source);
        defer c.JS_FreeValue(f.context.?, value);
        var length: usize = 0;
        var table: c.JSSABTab = std.mem.zeroes(c.JSSABTab);
        const raw = c.JS_WriteObject2(f.context.?, &length, value, c.JS_WRITE_OBJ_SAB, &table);
        defer c.js_free(f.context.?, table.tab);
        if (raw == null) return error.ActualBackingControlSerializationFailure;
        defer c.js_free(f.context.?, raw);
        try std.testing.expectEqual(@as(usize, 1), table.len);
        const bytes = try std.testing.allocator.dupe(u8, raw[0..length]);
        const backing: ?*anyopaque = @ptrCast(table.tab[0]);
        c.pi_js_retain_shared_buffer(backing);
        return .{ .bytes = bytes, .backing = backing };
    }
    fn install(self: *const Clone, f: *Fixture) !void {
        const value = try f.checked(c.JS_ReadObject(f.context.?, self.bytes.ptr, self.bytes.len, c.JS_READ_OBJ_SAB));
        defer c.JS_FreeValue(f.context.?, value);
        try f.set("shared", value);
    }
    fn deinit(self: *Clone) void {
        const backing = self.backing; self.backing = null;
        if (backing) |value| c.pi_js_release_shared_buffer(value);
        std.testing.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

test "VM backing actual intrinsic TypedArray and DataView spans ignore guest accessors" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.buffer=new ArrayBuffer(32);
        \\globalThis.words=new Uint16Array(buffer,4,5);
        \\globalThis.view=new DataView(buffer,7,9);
        \\globalThis.visits=0;
        \\for(const item of [words,view])for(const key of ["buffer","byteOffset","byteLength","length"])
        \\ Object.defineProperty(item,key,{get(){++visits;throw Error("guest span getter");}});
    );
    var words = try f.lease("words"); defer c.JS_PiReleaseArrayBufferLease(&words);
    var view = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&view);
    try std.testing.expect(words.owner == view.owner);
    try std.testing.expectEqual(@as(usize, 10), words.byte_length);
    try std.testing.expectEqual(@as(usize, 9), view.byte_length);
    try std.testing.expectEqual(@as(usize, 3), @intFromPtr(view.data) - @intFromPtr(words.data));
    words.data[0] = 73;
    try f.run("if(new Uint8Array(buffer)[4]!==73||visits!==0)throw Error('intrinsic span');");
}
test "VM backing actual empty spans and invalid view brands leave native output empty" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.buffer=new ArrayBuffer(8);
        \\globalThis.empty=new Uint8Array(buffer,8,0);
        \\globalThis.traps=0;
        \\globalThis.proxy=new Proxy(empty,{get(){++traps;throw Error("proxy get");}});
    );
    var lease = try f.lease("empty"); defer c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expectEqual(@as(usize, 0), lease.byte_length);
    inline for (.{ "proxy", "buffer", "({buffer})", "null", "1" }) |source| {
        const value = try f.eval(source); defer c.JS_FreeValue(f.context.?, value);
        var rejected = emptyLease();
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiAcquireArrayBufferView(f.context.?, value, &rejected));
        try expectEmpty(&rejected);
        try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); c.JS_FreeValue(f.context.?, reason);
    }
    try std.testing.expectEqual(@as(i32, 0), try f.number("traps"));
}
test "VM backing actual pending entry preserves the exact reason and owner count" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.view=new Uint8Array(16);");
    var held = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&held);
    const view = try f.eval("view"); defer c.JS_FreeValue(f.context.?, view);
    const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
    const references = c.pi_js_array_buffer_backing_references(held.owner);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    var rejected = emptyLease();
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiAcquireArrayBufferView(f.context.?, view, &rejected));
    try expectEmpty(&rejected);
    try std.testing.expectEqual(references, c.pi_js_array_buffer_backing_references(held.owner));
    const observed = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, observed);
    try std.testing.expect(c.pi_js_object_identity(reason) == c.pi_js_object_identity(observed));
}
const External = struct {
    calls: usize = 0,
    fn retire(_: ?*c.JSRuntime, opaque: ?*anyopaque, ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
        const self: *External = @ptrCast(@alignCast(opaque.?));
        if (size != 0 or ptr == null) @panic("Unexpected external ArrayBuffer resize");
        self.calls += 1;
        return null;
    }
};
test "VM backing external C storage stays unmanaged and keeps its actual free callback" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var state: External = .{};
    var bytes: [8]u8 = @splat(0);
    const buffer = try f.checked(c.JS_NewArrayBuffer(f.context.?, &bytes, bytes.len, 0, External.retire, &state, false));
    defer c.JS_FreeValue(f.context.?, buffer);
    try f.set("external", buffer);
    try f.run("globalThis.view=new Uint8Array(external);");
    const view = try f.eval("view"); defer c.JS_FreeValue(f.context.?, view);
    var lease = emptyLease();
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiAcquireArrayBufferView(f.context.?, view, &lease));
    try expectEmpty(&lease);
    c.JS_DetachArrayBuffer(f.context.?, buffer);
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try f.run("if(!external.detached||view.length!==0)throw Error('external detach');");
}
test "VM backing duplicate leases own the native allocation after detach and collection" {
    const baseline = c.pi_js_array_buffer_backing_allocations();
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(16);globalThis.view=new Uint8Array(buffer);view[0]=11;");
    var first = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&first);
    var second = emptyLease(); defer c.JS_PiReleaseArrayBufferLease(&second);
    c.JS_PiDupArrayBufferLease(&second, &first);
    const owner = first.owner;
    try std.testing.expectEqual(@as(usize, 3), c.pi_js_array_buffer_backing_references(owner));
    const buffer = try f.eval("buffer");
    c.JS_DetachArrayBuffer(f.context.?, buffer); c.JS_FreeValue(f.context.?, buffer);
    try f.run("if(!buffer.detached||view.length!==0)throw Error('detach');delete globalThis.buffer;delete globalThis.view;");
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 2), c.pi_js_array_buffer_backing_references(owner));
    first.data[0] = 39;
    c.JS_PiReleaseArrayBufferLease(&first);
    try expectEmpty(&first);
    try std.testing.expectEqual(@as(u8, 39), second.data[0]);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(owner));
    c.JS_PiReleaseArrayBufferLease(&second);
    try expectEmpty(&second);
    c.JS_PiReleaseArrayBufferLease(&second);
    try std.testing.expectEqual(baseline, c.pi_js_array_buffer_backing_allocations());
}
test "VM backing fixed equal transfer reuses storage and old lease writes reach the target" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.old=new ArrayBuffer(16);globalThis.view=new Uint8Array(old);view[3]=7;");
    var old = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&old);
    try f.run("globalThis.next=old.transfer();globalThis.nextView=new Uint8Array(next);if(!old.detached||view.length!==0)throw Error('transfer detach');");
    var next = try f.lease("nextView"); defer c.JS_PiReleaseArrayBufferLease(&next);
    try std.testing.expect(old.owner == next.owner and old.data == next.data);
    old.data[3] = 91;
    try f.run("if(nextView[3]!==91||next.byteLength!==16||next.resizable)throw Error('transfer allocation identity');");
}
test "VM backing changed fixed transfer copies before detaching and leaves old writes separate" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.old=new ArrayBuffer(8);globalThis.view=new Uint8Array(old);view.set([1,2,3,4,5,6,7,8]);");
    var old = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&old);
    try f.run("globalThis.next=old.transfer(12);globalThis.nextView=new Uint8Array(next);if(!old.detached)throw Error('transfer detach');");
    var next = try f.lease("nextView"); defer c.JS_PiReleaseArrayBufferLease(&next);
    try std.testing.expect(old.owner != next.owner and old.data != next.data);
    try std.testing.expectEqualSlices(u8, &.{ 1,2,3,4,5,6,7,8,0,0,0,0 }, next.data[0..next.byte_length]);
    old.data[0] = 99;
    try std.testing.expectEqual(@as(u8, 1), next.data[0]);
    try f.run("globalThis.short=next.transfer(3);if(String(new Uint8Array(short))!=='1,2,3')throw Error('transfer prefix');");
}
test "VM backing resizable equal transfer allocates fresh storage and preserves maximum" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.old=new ArrayBuffer(8,{maxByteLength:64});globalThis.view=new Uint8Array(old);view[0]=13;");
    var old = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&old);
    try f.run("globalThis.next=old.transfer();globalThis.nextView=new Uint8Array(next);if(!old.detached||!next.resizable||next.maxByteLength!==64)throw Error('RAB transfer shape');");
    var next = try f.lease("nextView"); defer c.JS_PiReleaseArrayBufferLease(&next);
    try std.testing.expect(old.owner != next.owner and old.data != next.data);
    old.data[0] = 27;
    try std.testing.expectEqual(@as(u8, 13), next.data[0]);
    try f.run("globalThis.fixed=next.transferToFixedLength();if(fixed.resizable||new Uint8Array(fixed)[0]!==13)throw Error('fixed transfer');");
}
test "VM backing zero transfer detaches without moving the outstanding native span" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.old=new ArrayBuffer(8,{maxByteLength:16});globalThis.view=new Uint8Array(old);view[7]=51;");
    var lease = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&lease);
    try f.run("globalThis.empty=old.transfer(0);if(!old.detached||empty.byteLength!==0||empty.maxByteLength!==16||!empty.resizable)throw Error('zero transfer');");
    try std.testing.expectEqual(@as(usize, 8), lease.byte_length);
    try std.testing.expectEqual(@as(u8, 51), lease.data[7]);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(lease.owner));
}
test "VM backing transfer coercion precedes detach checks and maximum failure keeps source live" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.buffer=new ArrayBuffer(8,{maxByteLength:16});
        \\globalThis.calls=0;
        \\try{buffer.transfer({valueOf(){++calls;return 17;}});throw Error("missing range failure");}
        \\catch(error){if(!(error instanceof RangeError))throw error;}
        \\if(calls!==1||buffer.detached||buffer.byteLength!==8)throw Error("maximum changed source");
        \\const next=buffer.transfer({valueOf(){++calls;return 4;}});
        \\try{buffer.transfer({valueOf(){++calls;return 4;}});throw Error("missing detached failure");}
        \\catch(error){if(!(error instanceof TypeError))throw error;}
        \\if(calls!==3||next.byteLength!==4)throw Error("coercion before detached check");
    );
}

test "VM backing external shared C storage keeps its callback and never enters trusted serialization" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var state: External = .{};
    // A real caller-owned allocation with a deliberately non-Pi prefix. The
    // public C entry must never interpret the preceding bytes as an owner.
    var allocation: [@sizeOf(usize) + 8]u8 align(@alignOf(usize)) = @splat(0);
    const data = allocation[@sizeOf(usize)..];
    const baseline = c.pi_js_array_buffer_backing_allocations();
    const shared_baseline = c.pi_js_shared_buffer_allocations();
    var buffer = try f.checked(c.JS_NewArrayBuffer(f.context.?, data.ptr, data.len, 0, External.retire, &state, true));
    defer c.JS_FreeValue(f.context.?, buffer);
    try f.set("externalShared", buffer);
    try f.run("globalThis.externalView=new Uint8Array(externalShared);externalView[0]=47;");
    var view = try f.eval("externalView"); defer c.JS_FreeValue(f.context.?, view);
    var lease = emptyLease();
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiAcquireArrayBufferView(f.context.?, view, &lease));
    try expectEmpty(&lease);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(u8, 47), data[0]);
    try std.testing.expectEqual(baseline, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(shared_baseline, c.pi_js_shared_buffer_allocations());
    var length: usize = 0;
    var table: c.JSSABTab = std.mem.zeroes(c.JSSABTab);
    const serialized = c.JS_WriteObject2(f.context.?, &length, buffer, c.JS_WRITE_OBJ_SAB, &table);
    defer c.js_free(f.context.?, table.tab);
    if (serialized != null) { c.js_free(f.context.?, serialized); return error.ExternalSharedEnteredTrustedSerialization; }
    try std.testing.expect(c.JS_HasException(f.context.?));
    const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try f.set("serializationReason", reason);
    try f.run("if(!(serializationReason instanceof TypeError)||serializationReason.message!=='external SharedArrayBuffer storage is not serializable')throw Error('foreign SAB serialization reason');");
    try std.testing.expectEqual(@as(usize, 0), table.len);
    try std.testing.expectEqual(@as(usize, 0), state.calls);
    try f.run("if(externalView[0]!==47||externalShared.byteLength!==8)throw Error('foreign SAB changed');delete globalThis.externalView;delete globalThis.externalShared;");
    c.JS_FreeValue(f.context.?, view); view = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, buffer); buffer = c.pi_js_undefined();
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try std.testing.expectEqual(baseline, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(shared_baseline, c.pi_js_shared_buffer_allocations());
}

test "VM backing failed mixed shared serialization retires its partial table and foreign owner exactly once" {
    const allocation_baseline = c.pi_js_array_buffer_backing_allocations();
    const memory_baseline = c.pi_js_native_memory_owners();
    var state: External = .{};
    var allocation: [@sizeOf(usize) + 8]u8 align(@alignOf(usize)) = @splat(0);
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const memory = f.memory;
    c.pi_js_retain_memory_owner(memory);
    defer c.pi_js_release_memory_owner(memory);
    {
        const data = allocation[@sizeOf(usize)..];
        const foreign = try f.checked(c.JS_NewArrayBuffer(f.context.?, data.ptr, data.len, 0, External.retire, &state, true));
        defer c.JS_FreeValue(f.context.?, foreign);
        try f.set("externalShared", foreign);
        // The first element admits a real native table entry before the
        // unsupported external element takes the writer's actual failure path.
        const pair = try f.eval("[new SharedArrayBuffer(8),externalShared]");
        defer c.JS_FreeValue(f.context.?, pair);
        var length: usize = 0;
        var table: c.JSSABTab = std.mem.zeroes(c.JSSABTab);
        const bytes = c.JS_WriteObject2(f.context.?, &length, pair, c.JS_WRITE_OBJ_SAB, &table);
        defer c.js_free(f.context.?, table.tab);
        if (bytes != null) { c.js_free(f.context.?, bytes); return error.MixedSharedSerializationUnexpectedlySucceeded; }
        try std.testing.expectEqual(@as(usize, 0), length);
        try std.testing.expectEqual(@as(usize, 0), table.len);
        try std.testing.expect(table.tab == null);
        try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try f.set("serializationReason", reason);
        try f.run("if(!(serializationReason instanceof TypeError)||serializationReason.message!=='external SharedArrayBuffer storage is not serializable')throw Error('original mixed serialization error');");
        try std.testing.expectEqual(@as(usize, 0), state.calls);
    }
    f.deinit();
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try std.testing.expectEqual(allocation_baseline, c.pi_js_array_buffer_backing_allocations());
    // The retained actual allocator survives runtime destruction, so a leaked
    // BCWriter SAB table remains charged and cannot hide behind owner teardown.
    try std.testing.expectEqual(@as(usize, 0), c.pi_js_native_memory_used(memory));
    try std.testing.expectEqual(memory_baseline + 1, c.pi_js_native_memory_owners());
}

test "VM backing resizable storage keeps its base and exact shrink zeroing across page growth" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(8,{maxByteLength:8388608});globalThis.full=new Uint8Array(buffer);");
    var initial = try f.lease("full"); defer c.JS_PiReleaseArrayBufferLease(&initial);
    const page = c.pi_js_array_buffer_backing_page_size(initial.owner);
    try std.testing.expect(page > 32 and page * 3 <= 8388608);
    try f.set("pageSize", c.JS_NewUint32(f.context.?, @intCast(page)));
    try f.run("buffer.resize(pageSize*2+8);full.fill(171);");
    var span = try f.lease("full"); defer c.JS_PiReleaseArrayBufferLease(&span);
    try std.testing.expect(initial.owner == span.owner and initial.data == span.data);
    try std.testing.expectEqual(page * 3, c.pi_js_array_buffer_backing_committed(span.owner));
    try f.run("buffer.resize(8);");
    try std.testing.expectEqual(@as(usize, 8), c.pi_js_array_buffer_backing_byte_length(span.owner));
    try std.testing.expectEqual(page, c.pi_js_array_buffer_backing_committed(span.owner));
    try std.testing.expectEqual(@as(u8, 171), span.data[0]);
    try std.testing.expectEqual(@as(u8, 0), span.data[8]);
    try std.testing.expectEqual(@as(u8, 0), span.data[page - 1]);
    // This part of the old I/O span remains in the committed partial page.
    // A native write after shrink must not be cleared again by later growth.
    span.data[16] = 66;
    try f.run("buffer.resize(pageSize*2+8);if(full[16]!==66||full[8]!==0||full[pageSize]!==0||full[pageSize*2]!==0||full[0]!==171)throw Error('resize storage contents');");
    var grown = try f.lease("full"); defer c.JS_PiReleaseArrayBufferLease(&grown);
    try std.testing.expect(grown.owner == span.owner and grown.data == span.data);
    try std.testing.expectEqual(page * 2 + 8, grown.byte_length);
    try std.testing.expectEqual(@as(usize, 8), initial.byte_length);
}
test "VM backing tracking and fixed view spans follow resize while old leases keep their snapshot" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.buffer=new ArrayBuffer(12,{maxByteLength:32});
        \\globalThis.tracking=new Uint8Array(buffer,4);
        \\globalThis.fixed=new Uint8Array(buffer,4,4);
        \\globalThis.data=new DataView(buffer,4);
        \\globalThis.fixedData=new DataView(buffer,4,4);
    );
    var prior = try f.lease("tracking"); defer c.JS_PiReleaseArrayBufferLease(&prior);
    try f.run("buffer.resize(4);if(tracking.length!==0||data.byteLength!==0)throw Error('zero tracking span');");
    var empty = try f.lease("tracking"); defer c.JS_PiReleaseArrayBufferLease(&empty);
    var empty_data = try f.lease("data"); defer c.JS_PiReleaseArrayBufferLease(&empty_data);
    try std.testing.expectEqual(@as(usize, 0), empty.byte_length);
    try std.testing.expectEqual(@as(usize, 0), empty_data.byte_length);
    try std.testing.expectEqual(@as(usize, 8), prior.byte_length);
    try f.run("try{data.getUint8(0);throw Error('missing zero-span failure');}catch(e){if(!(e instanceof RangeError))throw e;}");
    inline for (.{ "fixed", "fixedData" }) |name| {
        const view = try f.eval(name); defer c.JS_FreeValue(f.context.?, view);
        var rejected = emptyLease();
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiAcquireArrayBufferView(f.context.?, view, &rejected));
        try expectEmpty(&rejected);
        try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); c.JS_FreeValue(f.context.?, reason);
    }
    try f.run("buffer.resize(16);if(tracking.length!==12||fixed.length!==4||data.byteLength!==12||fixedData.byteLength!==4)throw Error('restored view span');");
    var restored = try f.lease("fixedData"); defer c.JS_PiReleaseArrayBufferLease(&restored);
    try std.testing.expect(restored.owner == prior.owner and restored.data == prior.data);
    try std.testing.expectEqual(@as(usize, 4), restored.byte_length);
    const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
    c.JS_DetachArrayBuffer(f.context.?, buffer);
    inline for (.{ "tracking", "data" }) |name| {
        const view = try f.eval(name); defer c.JS_FreeValue(f.context.?, view);
        var rejected = emptyLease();
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiAcquireArrayBufferView(f.context.?, view, &rejected));
        try expectEmpty(&rejected);
        try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?); c.JS_FreeValue(f.context.?, reason);
    }
}
test "VM backing Windows shrink decommits actual data pages while retaining the reservation" {
    if (comptime builtin.os.tag == .windows) {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try f.run("globalThis.buffer=new ArrayBuffer(8,{maxByteLength:8388608});globalThis.view=new Uint8Array(buffer);");
        var held = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&held);
        var information: c.MEMORY_BASIC_INFORMATION = undefined;
        try std.testing.expect(c.VirtualQuery(held.data, &information, @sizeOf(c.MEMORY_BASIC_INFORMATION)) != 0);
        try std.testing.expectEqual(@as(c.DWORD, c.MEM_COMMIT), information.State);
        try f.run("buffer.resize(0);");
        try std.testing.expectEqual(@as(usize, 0), c.pi_js_array_buffer_backing_committed(held.owner));
        try std.testing.expect(c.VirtualQuery(held.data, &information, @sizeOf(c.MEMORY_BASIC_INFORMATION)) != 0);
        try std.testing.expectEqual(@as(c.DWORD, c.MEM_RESERVE), information.State);
        // No read/write is attempted through the now-decommitted old span.
        try f.run("buffer.resize(8);if(new Uint8Array(buffer).some(x=>x!==0))throw Error('recommit zero');");
        try std.testing.expect(c.VirtualQuery(held.data, &information, @sizeOf(c.MEMORY_BASIC_INFORMATION)) != 0);
        try std.testing.expectEqual(@as(c.DWORD, c.MEM_COMMIT), information.State);
    } else return error.SkipZigTest;
}
test "VM backing failed native page growth leaves source length bytes and charge unchanged" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(8,{maxByteLength:8388608});globalThis.view=new Uint8Array(buffer);view[0]=92;");
    var held = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&held);
    const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
    const resize = try f.eval("ArrayBuffer.prototype.resize"); defer c.JS_FreeValue(f.context.?, resize);
    const page = c.pi_js_array_buffer_backing_page_size(held.owner);
    const committed = c.pi_js_array_buffer_backing_committed(held.owner);
    const allocations = c.pi_js_array_buffer_backing_allocations();
    const arguments = [_]c.JSValue{c.JS_NewUint32(f.context.?, @intCast(page * 2))};
    const memory_used = c.pi_js_native_memory_used(f.memory);
    var budget = try Budget.fill(&f); defer budget.release();
    const failure = c.JS_Call(f.context.?, resize, buffer, 1, @constCast(&arguments));
    const reason = try f.exception(failure);
    budget.release();
    c.JS_FreeValue(f.context.?, reason);
    try std.testing.expectEqual(memory_used, c.pi_js_native_memory_used(f.memory));
    try std.testing.expectEqual(@as(usize, 8), c.pi_js_array_buffer_backing_byte_length(held.owner));
    try std.testing.expectEqual(committed, c.pi_js_array_buffer_backing_committed(held.owner));
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(@as(u8, 92), held.data[0]);
    try f.run("if(buffer.detached||buffer.byteLength!==8||view.length!==8||view[0]!==92)throw Error('failed growth changed source');");
}
test "VM backing allocation failure preserves exact fixed equal changed and zero transfer detach order" {
    inline for (.{ @as(i32, 8), @as(i32, 16), @as(i32, 0) }) |length| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try f.run("globalThis.buffer=new ArrayBuffer(8);globalThis.view=new Uint8Array(buffer);view[0]=29;");
        var held = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&held);
        const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
        const transfer = try f.eval("ArrayBuffer.prototype.transfer"); defer c.JS_FreeValue(f.context.?, transfer);
        const arguments = [_]c.JSValue{c.JS_NewInt32(f.context.?, length)};
        var budget = try Budget.fill(&f); defer budget.release();
        const failure = c.JS_Call(f.context.?, transfer, buffer, 1, @constCast(&arguments));
        const reason = try f.exception(failure);
        budget.release();
        defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expectEqual(@as(u8, 29), held.data[0]);
        if (length == 16) {
            try f.run("if(buffer.detached||buffer.byteLength!==8||view[0]!==29)throw Error('copy failure detached source');");
            try std.testing.expectEqual(@as(usize, 2), c.pi_js_array_buffer_backing_references(held.owner));
        } else {
            try f.run("if(!buffer.detached||view.length!==0)throw Error('reuse failure kept source attached');");
            try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(held.owner));
        }
    }
}
const LeaseWorker = struct {
    lease: c.JSPiArrayBufferLease,
    proceed: std.atomic.Value(bool) = .init(false),
    wrote: bool = false,
    fn run(self: *LeaseWorker) void {
        while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        self.lease.data[0] = 103;
        self.wrote = self.lease.data[0] == 103;
        c.JS_PiReleaseArrayBufferLease(&self.lease);
    }
};
test "VM backing a native worker owns fixed storage after the originating runtime and allocator caller retire" {
    const allocations = c.pi_js_array_buffer_backing_allocations();
    const owners = c.pi_js_native_memory_owners();
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.view=new Uint8Array(16);");
    var held = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&held);
    var worker: LeaseWorker = .{ .lease = emptyLease() };
    c.JS_PiDupArrayBufferLease(&worker.lease, &held);
    var started = false;
    defer if (!started) c.JS_PiReleaseArrayBufferLease(&worker.lease);
    const thread = try std.Thread.spawn(.{}, LeaseWorker.run, .{&worker});
    started = true;
    var joined = false;
    defer { if (!joined) { worker.proceed.store(true, .release); thread.join(); } }
    c.JS_PiReleaseArrayBufferLease(&held);
    f.deinit();
    try std.testing.expectEqual(allocations + 1, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    worker.proceed.store(true, .release);
    thread.join(); joined = true;
    try std.testing.expect(worker.wrote);
    try expectEmpty(&worker.lease);
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}

test "VM backing managed shared roundtrip uses current native length and refreshes the C buffer result" {
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    try first.run("globalThis.shared=new SharedArrayBuffer(8,{maxByteLength:64});new Uint8Array(shared)[0]=11;");
    var held = try first.lease("new Uint8Array(shared)"); defer c.JS_PiReleaseArrayBufferLease(&held);
    var clone = try Clone.init(&first, "shared"); defer clone.deinit();
    // Serialized length 8 is stale before the second wrapper exists.
    try first.run("shared.grow(24);");
    var second: Fixture = .{}; try second.init(); defer second.deinit();
    try clone.install(&second);
    try second.run("if(shared.byteLength!==24||!shared.growable||shared.maxByteLength!==64)throw Error('current cloned shared length');globalThis.view=new Uint8Array(shared);");
    const shared = try second.eval("shared"); defer c.JS_FreeValue(second.context.?, shared);
    try first.run("shared.grow(48);new Uint8Array(shared)[47]=73;");
    // This is the second runtime's first buffer operation after growth.
    var length: usize = 0;
    const data = c.JS_GetArrayBuffer(second.context.?, &length, shared);
    try std.testing.expect(!c.JS_HasException(second.context.?));
    try std.testing.expect(data == held.data);
    try std.testing.expectEqual(@as(usize, 48), length);
    try std.testing.expectEqual(@as(u8, 73), data[47]);
    var view = try second.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&view);
    try std.testing.expect(view.owner == held.owner);
    try std.testing.expectEqual(@as(usize, 48), view.byte_length);
    try std.testing.expectEqual(@as(usize, 8), held.byte_length);
}
test "VM backing first operations in another runtime refresh actual shared view caches" {
    inline for (.{
        .{ "if(bytes[23]!==77)throw Error('indexed read after shared growth');", false },
        .{ "bytes[23]=91;", true },
        .{ "if(data.getUint8(23)!==77)throw Error('DataView read after shared growth');", false },
        .{ "data.setUint8(23,91);", true },
        .{ "const copy=bytes.slice();if(copy.length!==24||copy[23]!==77)throw Error('slice after shared growth');", false },
        .{ "const copy=[...bytes];if(copy.length!==24||copy[23]!==77)throw Error('iterator after shared growth');", false },
        .{ "if(Object.keys(bytes).length!==24)throw Error('own keys after shared growth');", false },
        .{ "const copy=bytes.map(x=>x);if(copy.length!==24||copy[23]!==77)throw Error('map after shared growth');", false },
    }) |entry| {
        var first: Fixture = .{}; try first.init(); defer first.deinit();
        try first.run("globalThis.shared=new SharedArrayBuffer(8,{maxByteLength:64});");
        var clone = try Clone.init(&first, "shared"); defer clone.deinit();
        var second: Fixture = .{}; try second.init(); defer second.deinit();
        try clone.install(&second);
        try second.run("globalThis.bytes=new Uint8Array(shared);globalThis.data=new DataView(shared);");
        try first.run("shared.grow(24);new Uint8Array(shared)[23]=77;");
        // Each case gets a fresh pair of runtimes. No earlier byteLength,
        // length, indexed, or native lease read refreshes these stale views.
        try second.run(entry[0]);
        if (entry[1]) try first.run("if(new Uint8Array(shared)[23]!==91)throw Error('shared write was not physical');");
    }
}
test "VM backing zero maximum growable shared buffers retain real empty managed spans" {
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    try first.run("globalThis.shared=new SharedArrayBuffer(0,{maxByteLength:0});shared.grow(0);");
    var held = try first.lease("new Uint8Array(shared)"); defer c.JS_PiReleaseArrayBufferLease(&held);
    try std.testing.expectEqual(@as(usize, 0), held.byte_length);
    try std.testing.expectEqual(@as(usize, 0), c.pi_js_array_buffer_backing_committed(held.owner));
    var clone = try Clone.init(&first, "shared"); defer clone.deinit();
    var second: Fixture = .{}; try second.init(); defer second.deinit();
    try clone.install(&second);
    try second.run("if(!shared.growable||shared.byteLength!==0||shared.maxByteLength!==0)throw Error('empty shared shape');try{shared.grow(1);throw Error('missing shared max failure');}catch(e){if(!(e instanceof RangeError))throw e;}");
    var empty = try second.lease("new Uint8Array(shared)"); defer c.JS_PiReleaseArrayBufferLease(&empty);
    try std.testing.expect(empty.owner == held.owner and empty.data == held.data);
    try std.testing.expectEqual(@as(usize, 0), empty.byte_length);
}
test "VM backing shared native entitlements survive both runtimes and the serializer table" {
    const allocations = c.pi_js_array_buffer_backing_allocations();
    const owners = c.pi_js_native_memory_owners();
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    try first.run("globalThis.shared=new SharedArrayBuffer(8,{maxByteLength:64});");
    var clone = try Clone.init(&first, "shared"); defer clone.deinit();
    var second: Fixture = .{}; try second.init(); defer second.deinit();
    try clone.install(&second);
    var held = try second.lease("new Uint8Array(shared)"); defer c.JS_PiReleaseArrayBufferLease(&held);
    first.deinit();
    second.deinit();
    try std.testing.expectEqual(allocations + 1, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(owners + 1, c.pi_js_native_memory_owners());
    try std.testing.expectEqual(@as(usize, 2), c.pi_js_array_buffer_backing_references(held.owner));
    clone.deinit();
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(held.owner));
    held.data[0] = 61;
    try std.testing.expectEqual(@as(u8, 61), held.data[0]);
    c.JS_PiReleaseArrayBufferLease(&held);
    try std.testing.expectEqual(allocations, c.pi_js_array_buffer_backing_allocations());
    try std.testing.expectEqual(owners, c.pi_js_native_memory_owners());
}
const GrowWorker = struct {
    clone: *const Clone,
    target: u32,
    ready: *std.atomic.Value(usize),
    proceed: *std.atomic.Value(bool),
    announced: bool = false,
    status: i32 = -1,
    failure: ?anyerror = null,
    fn announce(self: *GrowWorker) void {
        if (self.announced) return;
        self.announced = true;
        _ = self.ready.fetchAdd(1, .release);
    }
    fn run(self: *GrowWorker) void {
        self.perform() catch |err| { self.failure = err; };
        // Even setup failure releases the parent's readiness wait.
        self.announce();
    }
    fn perform(self: *GrowWorker) !void {
        // Each VM is created, used and destroyed on this one worker. Only
        // immutable serialized bytes and a native backing entitlement cross.
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try self.clone.install(&f);
        try f.set("target", c.JS_NewUint32(f.context.?, self.target));
        self.announce();
        while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        self.status = try f.number("(function(){try{shared.grow(target);return 0;}catch(e){if(!(e instanceof RangeError))throw e;return 1;}})()");
    }
};
test "VM backing two actual runtime workers share monotonic atomic growth and race failure" {
    var first: Fixture = .{}; try first.init(); defer first.deinit();
    try first.run("globalThis.shared=new SharedArrayBuffer(8,{maxByteLength:64});");
    var held = try first.lease("new Uint8Array(shared)"); defer c.JS_PiReleaseArrayBufferLease(&held);
    var clone = try Clone.init(&first, "shared"); defer clone.deinit();
    first.deinit();
    var ready: std.atomic.Value(usize) = .init(0);
    var proceed: std.atomic.Value(bool) = .init(false);
    var small: GrowWorker = .{ .clone = &clone, .target = 16, .ready = &ready, .proceed = &proceed };
    var large: GrowWorker = .{ .clone = &clone, .target = 48, .ready = &ready, .proceed = &proceed };
    const first_thread = try std.Thread.spawn(.{}, GrowWorker.run, .{&small});
    var joined_first = false;
    defer { if (!joined_first) { proceed.store(true, .release); first_thread.join(); } }
    const second_thread = try std.Thread.spawn(.{}, GrowWorker.run, .{&large});
    var joined_second = false;
    defer { if (!joined_second) { proceed.store(true, .release); second_thread.join(); } }
    while (ready.load(.acquire) < 2) std.atomic.spinLoopHint();
    proceed.store(true, .release);
    first_thread.join(); joined_first = true;
    second_thread.join(); joined_second = true;
    if (small.failure) |err| return err;
    if (large.failure) |err| return err;
    try std.testing.expect(small.status == 0 or small.status == 1);
    try std.testing.expectEqual(@as(i32, 0), large.status);
    try std.testing.expectEqual(@as(usize, 48), c.pi_js_array_buffer_backing_byte_length(held.owner));
    try std.testing.expectEqual(@as(usize, 8), held.byte_length);
    try std.testing.expectEqual(@as(usize, 2), c.pi_js_array_buffer_backing_references(held.owner));
}
const WrapperProbe = struct { retired: usize = 0 };
fn wrapperMarkerFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const probe: *WrapperProbe = @ptrCast(@alignCast(raw));
    _ = c.JS_SetOpaque(value, null);
    probe.retired += 1;
}
test "VM backing native leases retain allocation without retaining the JavaScript buffer wrapper" {
    const baseline = c.pi_js_array_buffer_backing_allocations();
    var probe: WrapperProbe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(f.runtime.?, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual backing wrapper lifetime marker", .finalizer = wrapperMarkerFinalizer };
    try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, id, &definition));
    try f.run("globalThis.buffer=new ArrayBuffer(8);globalThis.view=new Uint8Array(buffer);");
    var held = try f.lease("view"); defer c.JS_PiReleaseArrayBufferLease(&held);
    {
        const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
        const marker = try f.checked(c.JS_NewObjectClass(f.context.?, id)); defer c.JS_FreeValue(f.context.?, marker);
        _ = c.JS_SetOpaque(marker, &probe);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(f.context.?, buffer, "marker",
            c.JS_DupValue(f.context.?, marker), c.JS_PROP_C_W_E));
    }
    try f.run("delete globalThis.buffer;delete globalThis.view;");
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.retired);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(held.owner));
    try std.testing.expectEqual(baseline + 1, c.pi_js_array_buffer_backing_allocations());
    held.data[0] = 19;
    c.JS_PiReleaseArrayBufferLease(&held);
    try std.testing.expectEqual(baseline, c.pi_js_array_buffer_backing_allocations());
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.retired);
}

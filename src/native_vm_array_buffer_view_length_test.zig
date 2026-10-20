//! Actual intrinsic ArrayBufferView::ByteLength controls. The separate storage
//! lease retains its throwing contract. This root is install-only; source
//! review does not claim native execution or public filesystem qualification.
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
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualViewLengthControlJavaScriptException;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-view-length-control.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
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
            c.JS_FreeValue(self.context.?, c.JS_GetException(self.context.?));
            return error.ActualViewLengthControlPropertyFailure;
        }
    }
    fn length(self: *Fixture, value: c.JSValue, expected: usize) !void {
        try std.testing.expectEqual(expected, c.JS_PiArrayBufferViewByteLength(value));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn expressionLength(self: *Fixture, source: [:0]const u8, expected: usize) !void {
        const value = try self.eval(source);
        defer c.JS_FreeValue(self.context.?, value);
        try self.length(value, expected);
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
        if (raw == null) return error.ActualViewLengthSerializationFailure;
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

test "VM view byteLength fixed spans use every actual typed-array element width and DataView bytes" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const buffer = try f.eval("new ArrayBuffer(64)");
    defer c.JS_FreeValue(f.context.?, buffer);
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
        try f.length(view, 3 * pair[1]);
    }
    try f.set("buffer", buffer);
    try f.expressionLength("new DataView(buffer,7,9)", 9);
    try f.expressionLength("new DataView(buffer,64,0)", 0);
    try f.expressionLength("new Uint32Array(buffer,64,0)", 0);
}

test "VM view byteLength bypasses guest getters and rejects live and revoked proxy brands" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.calls=0;
        \\globalThis.typed=new Uint16Array(5);globalThis.data=new DataView(new ArrayBuffer(13),2,7);
        \\for(const view of [typed,data])for(const name of ['buffer','byteOffset','byteLength','length'])
        \\ Object.defineProperty(view,name,{get(){++calls;throw Error('guest view getter');}});
        \\globalThis.proxy=new Proxy(typed,{get(){++calls;throw Error('proxy getter');}});
        \\const pair=Proxy.revocable(data,{});globalThis.revoked=pair.proxy;pair.revoke();
    );
    try f.expressionLength("typed", 10);
    try f.expressionLength("data", 7);
    inline for (.{ "proxy", "revoked", "new ArrayBuffer(9)", "({byteLength:99})",
        "Object.create(Uint8Array.prototype)", "Object.create(DataView.prototype)", "null", "undefined", "1", "'text'" }) |source|
        try f.expressionLength(source, 0);
    try f.run("if(calls!==0)throw Error('intrinsic length entered guest code');");
}

test "VM view byteLength detached views return zero while actual lease acquisition still throws" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(16);globalThis.typed=new Uint32Array(buffer,4,2);globalThis.data=new DataView(buffer,3,6);");
    const buffer = try f.eval("buffer"); defer c.JS_FreeValue(f.context.?, buffer);
    const typed = try f.eval("typed"); defer c.JS_FreeValue(f.context.?, typed);
    const data = try f.eval("data"); defer c.JS_FreeValue(f.context.?, data);
    c.JS_DetachArrayBuffer(f.context.?, buffer);
    for ([_]c.JSValue{ typed, data }) |view| {
        try f.length(view, 0);
        var lease: c.JSPiArrayBufferLease = std.mem.zeroes(c.JSPiArrayBufferLease);
        defer c.JS_PiReleaseArrayBufferLease(&lease);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiAcquireArrayBufferView(f.context.?, view, &lease));
        try std.testing.expect(lease.owner == null and lease.data == null and lease.byte_length == 0);
        try std.testing.expect(c.JS_HasException(f.context.?));
        const reason = c.JS_GetException(f.context.?);
        defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsError(reason) and !c.JS_IsUncatchableError(reason));
    }
}

test "VM view byteLength fixed resizable views become zero out of bounds and recover on regrowth" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.buffer=new ArrayBuffer(16,{maxByteLength:32});
        \\globalThis.typed=new Uint32Array(buffer,4,2);globalThis.data=new DataView(buffer,5,6);
        \\globalThis.empty=new DataView(buffer,12,0);
    );
    const typed = try f.eval("typed"); defer c.JS_FreeValue(f.context.?, typed);
    const data = try f.eval("data"); defer c.JS_FreeValue(f.context.?, data);
    const empty = try f.eval("empty"); defer c.JS_FreeValue(f.context.?, empty);
    try f.run("buffer.resize(11)");
    try f.length(typed, 0); try f.length(data, 6); try f.length(empty, 0);
    try f.run("buffer.resize(10)");
    try f.length(typed, 0); try f.length(data, 0);
    try f.run("buffer.resize(12)");
    try f.length(typed, 8); try f.length(data, 6); try f.length(empty, 0);
}

test "VM view byteLength tracking resizable spans round typed elements and preserve exact DataView bytes" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run("globalThis.buffer=new ArrayBuffer(11,{maxByteLength:32});globalThis.typed=new Uint32Array(buffer,4);globalThis.data=new DataView(buffer,4);");
    const typed = try f.eval("typed"); defer c.JS_FreeValue(f.context.?, typed);
    const data = try f.eval("data"); defer c.JS_FreeValue(f.context.?, data);
    try f.length(typed, 4); try f.length(data, 7);
    try f.run("buffer.resize(6)"); try f.length(typed, 0); try f.length(data, 2);
    try f.run("buffer.resize(4)"); try f.length(typed, 0); try f.length(data, 0);
    try f.run("buffer.resize(3)"); try f.length(typed, 0); try f.length(data, 0);
    try f.run("buffer.resize(15)"); try f.length(typed, 8); try f.length(data, 11);
}

test "VM view byteLength shared growth preserves fixed spans and updates tracking spans" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.run(
        \\globalThis.shared=new SharedArrayBuffer(8,{maxByteLength:32});
        \\globalThis.fixed=new Uint16Array(shared,2,2);globalThis.tracking=new Uint16Array(shared,2);
        \\globalThis.fixedData=new DataView(shared,3,3);globalThis.trackingData=new DataView(shared,3);
    );
    const fixed = try f.eval("fixed"); defer c.JS_FreeValue(f.context.?, fixed);
    const tracking = try f.eval("tracking"); defer c.JS_FreeValue(f.context.?, tracking);
    const fixed_data = try f.eval("fixedData"); defer c.JS_FreeValue(f.context.?, fixed_data);
    const tracking_data = try f.eval("trackingData"); defer c.JS_FreeValue(f.context.?, tracking_data);
    try f.run("shared.grow(15)");
    try f.length(fixed, 4); try f.length(tracking, 12);
    try f.length(fixed_data, 3); try f.length(tracking_data, 12);
}

test "VM view byteLength sees foreign runtime shared growth before any receiver realm getter" {
    inline for (.{ false, true }) |data_first| {
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
        try receiver.length(typed, 4); try receiver.length(data, 5);
        try source.run("shared.grow(19)");
        // Each fresh pair makes the selected kind the first read after foreign
        // growth. No earlier receiver operation can refresh its stale cache.
        if (data_first) {
            try receiver.length(data, 16); try receiver.length(typed, 12);
        } else {
            try receiver.length(typed, 12); try receiver.length(data, 16);
        }
    }
}

test "VM view byteLength is allocation free under the real VM heap limit" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const view = try f.eval("new DataView(new ArrayBuffer(17),3,11)");
    defer c.JS_FreeValue(f.context.?, view);
    const invalid = try f.eval("({})"); defer c.JS_FreeValue(f.context.?, invalid);
    const used = c.pi_js_native_memory_used(f.memory);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    defer c.JS_SetMemoryLimit(f.runtime.?, 0);
    try f.length(view, 11); try f.length(invalid, 0);
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
}

test "VM view byteLength preserves actual ordinary and uncatchable pending reasons without inspection" {
    inline for (.{ false, true }) |uncatchable| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const view = try f.eval("new Uint16Array(7)"); defer c.JS_FreeValue(f.context.?, view);
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        if (uncatchable) c.JS_SetUncatchableError(f.context.?, reason);
        // Flagged DATA alone remains DATA until the following actual throw.
        try std.testing.expectEqual(@as(usize, 14), c.JS_PiArrayBufferViewByteLength(view));
        try std.testing.expect(!c.JS_HasException(f.context.?));
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        defer c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(@as(usize, 14), c.JS_PiArrayBufferViewByteLength(view));
        try std.testing.expectEqual(@as(usize, 0), c.JS_PiArrayBufferViewByteLength(c.pi_js_null()));
        try std.testing.expect(c.JS_HasException(f.context.?));
        const observed = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, observed);
        try std.testing.expect(c.pi_js_object_identity(reason) == c.pi_js_object_identity(observed));
        try std.testing.expectEqual(uncatchable, c.JS_IsUncatchableError(observed));
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
}

test "VM view byteLength borrows without retaining the view or its native backing entitlement" {
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
    for (0..16) |_| try f.length(view, 10);
    try std.testing.expectEqual(references, c.pi_js_array_buffer_backing_references(lease.owner));
    c.JS_FreeValue(f.context.?, view); view = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, buffer); buffer = c.pi_js_undefined();
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), c.pi_js_array_buffer_backing_references(lease.owner));
    c.JS_PiReleaseArrayBufferLease(&lease);
    try std.testing.expectEqual(baseline, c.pi_js_array_buffer_backing_allocations());
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
test "VM view byteLength leaves unmanaged external storage ownership and callback unchanged" {
    var external: External = .{};
    var bytes: [16]u8 = @splat(0);
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    var buffer = try f.checked(c.JS_NewArrayBuffer(f.context.?, &bytes, bytes.len, 0, External.retire, &external, false));
    defer c.JS_FreeValue(f.context.?, buffer);
    const args = [_]c.JSValue{ buffer, c.JS_NewInt32(f.context.?, 4), c.JS_NewInt32(f.context.?, 3) };
    var view = try f.checked(c.JS_NewTypedArray(f.context.?, args.len, @constCast(&args), c.JS_TYPED_ARRAY_UINT16));
    defer c.JS_FreeValue(f.context.?, view);
    try f.length(view, 6);
    try std.testing.expectEqual(@as(usize, 0), external.calls);
    c.JS_DetachArrayBuffer(f.context.?, buffer);
    try f.length(view, 0);
    try std.testing.expectEqual(@as(usize, 1), external.calls);
    c.JS_FreeValue(f.context.?, view); view = c.pi_js_undefined();
    c.JS_FreeValue(f.context.?, buffer); buffer = c.pi_js_undefined();
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), external.calls);
}

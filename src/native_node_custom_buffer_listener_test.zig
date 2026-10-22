//! Focused source controls for the actual CustomBufferJSListener owner.
//! The imported concrete FileHandle/Shutdown fixture uses real VM, descriptor,
//! request and listener owners. Its selected trace/allocation/hook observations
//! do not supply missing production bootstrap or public FunctionTemplate policy.
const std = @import("std");
const support = @import("native_node_stream_shutdown_test_support.zig");
const custom = @import("extensions/native_node_custom_buffer_listener.zig");
const resources = @import("extensions/native_node_stream_resource.zig");
const shutdown = @import("extensions/native_node_stream_shutdown.zig");
const callable = @import("extensions/native_node_module_callable.zig");
const a = support.a;
const c = a.c;
const uv = resources.uv;
const File = support.base_support.File;

const Fixture = struct {
    native: support.Fixture = undefined,
    file: File = undefined,
    native_ready: bool = false,
    file_ready: bool = false,

    fn init(self: *Fixture) !void {
        self.* = .{};
        errdefer self.deinit();
        try self.file.init();
        self.file_ready = true;
        try self.native.init();
        self.native_ready = true;
        _ = try self.native.create(self.file.take());
        try self.base().engine.bindFunction("actualCustomNread", readNread, 0);
        try self.base().engine.bindFunction("actualStopCustomRead", stopRead, 0);
        try self.base().engine.bindFunction("actualDestroyCustomStream", destroyStream, 0);
        try self.base().evaluate("globalThis.customReads=[];globalThis.customArguments=[];");
        try self.onread("(function(value){customReads.push(actualCustomNread());customArguments.push([arguments.length,value]);})");
    }
    fn deinit(self: *Fixture) void {
        if (self.native_ready) { self.native_ready = false; self.native.deinit(); }
        if (self.file_ready) { self.file_ready = false; self.file.deinit(); }
    }
    fn base(self: *Fixture) *support.base_support.Fixture { return &self.native.base; }
    fn resource(self: *Fixture) !*resources.Resource {
        return &(try self.base().handle()).stream.resource;
    }
    fn onread(self: *Fixture, source: []const u8) !void {
        const function = try self.base().value(source);
        defer self.base().engine.freeValue(function);
        const ignored = try a.expression(self.base().engine, struct {
            fn body(s: *a.Scope, f: *Fixture, selected: c.JSValue) !c.JSValue {
                try f.base().registry().setStreamOnRead(s, f.base().primary_wrapper.?, selected);
                return c.pi_js_undefined();
            }
        }.body, .{ self, function });
        self.base().engine.freeValue(ignored);
    }
    fn use(self: *Fixture, value: c.JSValue) !*resources.Listener {
        const handle = try self.base().handle();
        try std.testing.expectEqual(@as(c_int, 0), custom.useUserBuffer(&handle.stream, value));
        return handle.stream.resource.listener orelse error.CustomBufferListenerNotPublished;
    }
    fn allocated(self: *Fixture, suggested: usize) !uv.uv_buf_t {
        return (try self.resource()).emitAlloc(suggested);
    }
    fn read(self: *Fixture, count: isize, buffer: uv.uv_buf_t) !void {
        return (try self.resource()).emitRead(count, buffer);
    }
};

fn selectedBase(context: *c.JSContext) *support.base_support.Fixture {
    const engine = a.v.em.Engine.fromContext(context);
    return @ptrCast(@alignCast(engine.host_control_context.?));
}
fn readNread(context: ?*c.JSContext, _: c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const f = selectedBase(context.?);
    return c.JS_NewInt32(context.?, f.env().streamBaseField(.read_bytes_or_error).*);
}
fn destroyStream(context: ?*c.JSContext, _: c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const f = selectedBase(context.?);
    const handle = f.handle() catch |err| return callable.failure(f.engine, err, 0);
    handle.stream.deinit();
    return c.pi_js_undefined();
}
fn stopRead(context: ?*c.JSContext, _: c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const f = selectedBase(context.?);
    const handle = f.handle() catch |err| return callable.failure(f.engine, err, 0);
    return c.JS_NewInt32(context.?, handle.readStop());
}
fn expectBuffer(actual: uv.uv_buf_t, pointer: usize, length: usize) !void {
    try std.testing.expectEqual(pointer, @intFromPtr(actual.base));
    try std.testing.expectEqual(length, @as(usize, actual.len));
}
fn expectFailure(f: *Fixture, expected: c.JSValue, result: anyerror!void) !void {
    try std.testing.expectError(error.JavaScriptException, result);
    const actual = try f.base().takeCaught();
    defer f.base().engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.base().engine.context, expected, actual));
    try std.testing.expectEqual(c.JS_IsUncatchableError(expected), c.JS_IsUncatchableError(actual));
    try std.testing.expect(!c.JS_HasException(f.base().engine.context));
}

test "native CustomBuffer listener publishes the actual borrowed typed view span and writes its physical storage" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("globalThis.customBacking=new ArrayBuffer(16);globalThis.customView=new Uint8Array(customBacking,3,6);customView");
    defer f.base().engine.freeValue(view);
    const pointer = @intFromPtr(c.JS_PiArrayBufferViewData(view));
    const previous = (try f.resource()).listener.?;
    const listener = try f.use(view);
    try std.testing.expect(listener.previous_listener == previous);
    try std.testing.expect(listener.stream == try f.resource());
    const buffer = try f.allocated(65536);
    try expectBuffer(buffer, pointer, 6);
    buffer.base[2] = 0x6b;
    try f.base().expect("customView[2]===0x6b&&new Uint8Array(customBacking)[5]===0x6b");
    try f.read(3, buffer);
    try f.base().expect("customReads.length===1&&customReads[0]===3&&customArguments[0][0]===1&&customArguments[0][1]===undefined");
    try std.testing.expectEqual(@as(u64, 3), (try f.resource()).bytes_read);
    try std.testing.expectEqual(@as(usize, 0), f.base().allocations);
    try std.testing.expectEqual(@as(usize, 0), f.base().env().managed_buffers.count());
    try std.testing.expectEqual(@as(i32, 0), f.base().env().streamBaseField(.array_buffer_offset).*);
}

test "native CustomBuffer listener uses actual DataView fields without invoking shadow getters" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value(
        "globalThis.customBacking=new ArrayBuffer(20);globalThis.customView=new DataView(customBacking,5,7);" ++
        "globalThis.customGetterCalls=0;for(const key of ['buffer','byteOffset','byteLength'])Object.defineProperty(customView,key,{get(){customGetterCalls++;throw Error('getter');}});customView");
    defer f.base().engine.freeValue(view);
    _ = try f.use(view);
    const buffer = try f.allocated(1);
    try expectBuffer(buffer, @intFromPtr(c.JS_PiArrayBufferViewData(view)), 7);
    buffer.base[6] = 0x9e;
    try f.base().expect("customGetterCalls===0&&new Uint8Array(customBacking)[11]===0x9e");
    try f.read(0, buffer);
    try f.base().expect("customReads.length===1&&customReads[0]===0");
}

test "native CustomBuffer listener returns the same empty view buffer regardless of suggested size" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("globalThis.customBacking=new ArrayBuffer(8);new Uint8Array(customBacking,8,0)");
    defer f.base().engine.freeValue(view);
    _ = try f.use(view);
    const pointer = @intFromPtr(c.JS_PiArrayBufferViewData(view));
    try expectBuffer(try f.allocated(0), pointer, 0);
    try expectBuffer(try f.allocated(123456), pointer, 0);
    // Original UseUserBuffer itself does not reject an empty branded view.
    // The separate native I/O nonzero-allocation caller precondition is not invoked.
    try std.testing.expectEqual(@as(usize, 0), f.base().allocations);
}

test "native CustomBuffer listener calls onread for zero and nonnull negative reads and retains undefined results" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(8)");
    defer f.base().engine.freeValue(view);
    _ = try f.use(view);
    var buffer = try f.allocated(99);
    const original = buffer;
    // Only base identity is compared; the incoming len is not buffer_.len.
    buffer.len = 1;
    try f.read(0, buffer);
    try f.read(-7, buffer);
    try expectBuffer(try f.allocated(1), @intFromPtr(original.base), original.len);
    try f.base().expect("customReads.length===2&&customReads[0]===0&&customReads[1]===-7&&customArguments.every(v=>v[0]===1&&v[1]===undefined)");
    try std.testing.expectEqual(@as(u64, 0), (try f.resource()).bytes_read);
}

test "native CustomBuffer listener null error branch ignores even an invalid replacement result" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(9)");
    defer f.base().engine.freeValue(view);
    _ = try f.use(view);
    const buffer = try f.allocated(1);
    try f.onread("(function(){customReads.push(actualCustomNread());return 17;})");
    try f.read(-9, .{ .base = null, .len = 0 });
    try expectBuffer(try f.allocated(1), @intFromPtr(buffer.base), buffer.len);
    try f.base().expect("customReads.length===1&&customReads[0]===-9");
    try std.testing.expectEqual(@as(usize, 1), f.base().after_read_callbacks);
}

test "native CustomBuffer listener commits the actual returned view for the next allocation" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const first = try f.base().value("globalThis.customFirst=new Uint8Array(8);globalThis.customNext=new DataView(new ArrayBuffer(18),6,5);customFirst");
    defer f.base().engine.freeValue(first);
    const second = try f.base().global("customNext");
    defer f.base().engine.freeValue(second);
    _ = try f.use(first);
    const first_buffer = try f.allocated(1);
    try f.onread("(function(){customReads.push(actualCustomNread());return customNext;})");
    try f.read(2, first_buffer);
    const next_buffer = try f.allocated(65536);
    try expectBuffer(next_buffer, @intFromPtr(c.JS_PiArrayBufferViewData(second)), 5);
    next_buffer.base[4] = 91;
    try f.base().expect("customNext.getUint8(4)===91&&customReads[0]===2");
    try std.testing.expectEqual(@as(u64, 2), (try f.resource()).bytes_read);
}

test "native CustomBuffer listener actual descriptor reads reuse caller buffers through FileHandle completion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    // The real file contains ABCDEFGH. Two physical reads consume its bytes;
    // a third reaches real EOF and the guest callback invokes actual ReadStop.
    const handle = try f.base().handle();
    const first = try f.base().value("globalThis.customFirst=new Uint8Array(4);globalThis.customSecond=new Uint8Array(4);customFirst");
    defer f.base().engine.freeValue(first);
    _ = try f.use(first);
    try f.onread("(function(value){const nread=actualCustomNread();customReads.push(nread);customArguments.push(value);if(nread<0)actualStopCustomRead();return customReads.length===1?customSecond:undefined;})");
    try std.testing.expectEqual(@as(c_int, 0), try f.base().start());
    try f.base().pumpIo();
    try f.base().expect("Array.from(customFirst).join(',')==='65,66,67,68'&&Array.from(customSecond).join(',')==='69,70,71,72'");
    try f.base().expect("customReads.length===3&&customReads[0]===4&&customReads[1]===4&&customReads[2]<0&&customArguments.every(v=>v===undefined)");
    try std.testing.expectEqual(@as(usize, 3), f.base().read_begins);
    try std.testing.expectEqual(@as(usize, 3), f.base().read_ends);
    try std.testing.expect(f.base().read_member_exact);
    try std.testing.expectEqual(@as(u64, 8), handle.stream.resource.bytes_read);
    try std.testing.expectEqual(@as(usize, 0), f.base().allocations);
    try std.testing.expectEqual(@as(usize, 0), f.base().env().managed_buffers.count());
}

test "native CustomBuffer listener actual ordinary and uncatchable callback throws preserve the original buffer" {
    for ([_]bool{ false, true }) |fatal| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const view = try f.base().value("globalThis.customReason=new Error('custom read');new Uint8Array(8)");
        defer f.base().engine.freeValue(view);
        const reason = try f.base().global("customReason");
        defer f.base().engine.freeValue(reason);
        if (fatal) c.JS_SetUncatchableError(f.base().engine.context, reason);
        _ = try f.use(view);
        const buffer = try f.allocated(1);
        try f.onread("(function(){throw customReason;})");
        try expectFailure(&f, reason, f.read(4, buffer));
        try expectBuffer(try f.allocated(1), @intFromPtr(buffer.base), buffer.len);
        try std.testing.expectEqual(@as(usize, 1), f.base().after_read_callbacks);
        try std.testing.expectEqual(@as(u64, 4), (try f.resource()).bytes_read);
        try std.testing.expectEqual(@as(usize, 1), f.base().env().callback_depth);
    }
}

const External = struct {
    calls: usize = 0,
    fn retire(_: ?*c.JSRuntime, raw: ?*anyopaque, pointer: ?*anyopaque,
        size: usize) callconv(.c) ?*anyopaque
    {
        const self: *External = @ptrCast(@alignCast(raw.?));
        if (pointer == null or size != 0) @panic("unexpected CustomBuffer external resize");
        self.calls += 1;
        return null;
    }
};

test "native CustomBuffer listener does not retain the actual external buffer or its JavaScript view" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var external: External = .{};
    var bytes: [16]u8 = @splat(0);
    var backing = try f.base().engine.checked(c.JS_NewArrayBuffer(
        f.base().engine.context, &bytes, bytes.len, 0, External.retire, &external, false));
    defer f.base().engine.freeValue(backing);
    const args = [_]c.JSValue{ backing, c.JS_NewInt32(f.base().engine.context, 4),
        c.JS_NewInt32(f.base().engine.context, 6) };
    var view = try f.base().engine.checked(c.JS_NewTypedArray(
        f.base().engine.context, args.len, @constCast(&args), c.JS_TYPED_ARRAY_UINT8));
    defer f.base().engine.freeValue(view);
    const listener = try f.use(view);
    try expectBuffer(try f.allocated(1), @intFromPtr(&bytes) + 4, 6);
    f.base().engine.freeValue(view); view = c.pi_js_undefined();
    f.base().engine.freeValue(backing); backing = c.pi_js_undefined();
    c.JS_RunGC(f.base().engine.runtime);
    try std.testing.expectEqual(@as(usize, 1), external.calls);
    try std.testing.expect(listener.stream == try f.resource());
    // The borrowed address has no entitlement now; no further alloc/read uses it.
    listener.on_destroy(listener);
    try std.testing.expectEqual(@as(usize, 1), external.calls);
}

test "native CustomBuffer listener native deletion unlinks the live head before releasing its exact charge" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(4)");
    defer f.base().engine.freeValue(view);
    const resource = try f.resource();
    const previous = resource.listener;
    const memory = f.base().engine.native_memory_owner;
    const before = c.pi_js_native_memory_used(memory);
    const listener = try f.use(view);
    try std.testing.expect(c.pi_js_native_memory_used(memory) > before);
    listener.on_destroy(listener);
    try std.testing.expect(resource.listener == previous);
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(memory));
}

test "native CustomBuffer listener interior deletion preserves the actual remaining listener chain" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(4)");
    defer f.base().engine.freeValue(view);
    const resource = try f.resource();
    const original = resource.listener;
    const memory = f.base().engine.native_memory_owner;
    const before = c.pi_js_native_memory_used(memory);
    const first = try f.use(view);
    const first_charge = c.pi_js_native_memory_used(memory) - before;
    const second = try f.use(view);
    first.on_destroy(first);
    try std.testing.expect(resource.listener == second and second.previous_listener == original);
    try std.testing.expectEqual(before + first_charge, c.pi_js_native_memory_used(memory));
    second.on_destroy(second);
    try std.testing.expect(resource.listener == original);
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(memory));
}

test "native CustomBuffer listener StreamBase destruction consumes its actual self deleting chain" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(4)");
    defer f.base().engine.freeValue(view);
    const handle = try f.base().handle();
    const memory = f.base().engine.native_memory_owner;
    const before = c.pi_js_native_memory_used(memory);
    _ = try f.use(view);
    _ = try f.use(view);
    try std.testing.expect(c.pi_js_native_memory_used(memory) > before);
    handle.stream.deinit();
    try std.testing.expect(handle.stream.resource.listener == null);
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(memory));
}

test "native CustomBuffer listener unlinked allocation survives Engine teardown and retires without a context" {
    const owners_before = c.pi_js_native_memory_owners();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(4)");
    const listener = try f.use(view);
    (try f.resource()).remove(listener);
    try std.testing.expect(listener.stream == null and listener.previous_listener == null);
    f.base().engine.freeValue(view);
    const memory = f.base().engine.native_memory_owner;
    f.deinit();
    try std.testing.expectEqual(owners_before + 1, c.pi_js_native_memory_owners());
    try std.testing.expect(c.pi_js_native_memory_used(memory) > 0);
    listener.on_destroy(listener);
    try std.testing.expectEqual(owners_before, c.pi_js_native_memory_owners());
}

test "native CustomBuffer listener callback may destroy the actual listener and return undefined" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(4)");
    defer f.base().engine.freeValue(view);
    _ = try f.use(view);
    const buffer = try f.allocated(1);
    try f.onread("(function(){actualDestroyCustomStream();})");
    try f.read(1, buffer);
    try std.testing.expect((try f.resource()).listener == null);
    try std.testing.expectEqual(@as(usize, 1), f.base().after_read_callbacks);
    try std.testing.expectEqual(@as(usize, 1), f.base().env().callback_depth);
}

test "native CustomBuffer listener selects the genuine shutdown reporter for the real native close request" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const view = try f.base().value("new Uint8Array(4)");
    defer f.base().engine.freeValue(view);
    const listener = try f.use(view);
    try std.testing.expect(listener.after_shutdown == shutdown.reportAfterShutdown);
    const request = try f.native.request();
    defer f.base().engine.freeValue(request);
    try f.native.publishRequest(request);
    try std.testing.expectEqual(@as(c_int, 0), try f.native.run(request));
    try f.base().pumpIo();
    try f.base().expect("shutdownCalls.length===1&&shutdownCalls[0][0]===shutdownRequest&&shutdownCalls[0][1]===0&&shutdownCalls[0][2]===shutdownHandle&&shutdownCalls[0][3]===undefined");
    try std.testing.expect(f.native.callback_cleaned and f.native.callback_uncounted);
    try std.testing.expectEqual(@as(usize, 1), f.native.begins);
    try std.testing.expectEqual(@as(usize, 1), f.native.ends);
}

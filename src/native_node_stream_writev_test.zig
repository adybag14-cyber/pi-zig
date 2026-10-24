//! Focused original StreamBase::Writev/encoding controls; authored, not executed.
//! Fixture virtuals observe actual buffers, WriteWrap and Environment state.
//! They do not replace the production owner or publish a public FileHandle.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const a = support.a;
const c = a.c;
const vectors = @import("extensions/native_node_stream_writev.zig");
const bytes = @import("extensions/native_node_stream_string_bytes.zig");
const temporary = @import("extensions/native_node_maybe_stack_buffer.zig");
const requests = @import("extensions/native_node_stream_request.zig");
const streams = @import("extensions/native_node_stream_base.zig");
const dispatch = @import("extensions/native_node_stream_js_dispatch.zig");
const managed = @import("extensions/native_node_managed_buffers.zig");
const callable = @import("extensions/native_node_module_callable.zig");
const uv = managed.uv;

const Fixture = struct {
    base: support.Fixture = undefined,
    ready: bool = false,
    error_key: ?c.JSValue = null,
    complete_key: ?c.JSValue = null,
    original_allocation: ?streams.Allocation = null,
    allocation_count: usize = 0,
    allocation_lengths: [16]usize = undefined,
    allocation_modes: [16]streams.Initialization = undefined,
    pending_request: ?*requests.Write = null,
    last_request: ?*requests.Write = null,
    held_state: ?*support.native.State = null,
    hold_sync: bool = false,
    last_status: c_int = -99999,
    write_status: c_int = uv.UV_EIO,
    write_calls: usize = 0,
    vector_count: usize = 0,
    vector_lengths: [32]usize = undefined,
    vector_data: [32][*c]const u8 = undefined,
    write_length: usize = 0,
    write_prefix: [512]u8 = undefined,
    write_counter: u64 = 0,
    write_provider: u32 = 0,
    gc_before_write: bool = false,
    try_calls: usize = 0,
    try_counter: u64 = 0,
    try_length: usize = 0,
    try_status: c_int = 0,
    try_complete: bool = false,
    try_consumed: usize = 0,
    message: bool = false,
    error_clears: usize = 0,
    nested_before: f64 = -1,
    nested_after: f64 = -1,

    fn init(self: *Fixture) !void {
        self.* = .{};
        try self.base.init(); self.ready = true;
        errdefer self.deinit();
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                f.error_key = a.duplicate(s.engine, try s.text("error"));
                f.complete_key = a.duplicate(s.engine, try s.text("oncomplete"));
                return c.pi_js_undefined();
            }
        }.body, .{self});
        self.base.engine.freeValue(ignored);
        try self.base.evaluate("globalThis.writevCalls=[];globalThis.writevReason={};");
    }
    fn create(self: *Fixture, fd: c_int) !*support.Handle {
        const handle = try self.base.create(fd, null, null);
        const binding: streams.WriteBindings = .{ .request = .{
            .template_owner = self.base.template_owner.?,
            .error_string = self.error_key.?, .oncomplete_string = self.complete_key.?,
        }, .handle_string = handle.handle_string };
        handle.stream.operations.write = binding;
        handle.stream_operations.write = binding;
        self.original_allocation = handle.stream.operations.allocation;
        const observer: streams.Allocation = .{ .raw = self, .new_backing_store = observeAllocation };
        handle.stream.operations.allocation = observer;
        handle.stream_operations.allocation = observer;
        try self.base.expose("writevHandle", self.base.primary_wrapper.?);
        return handle;
    }
    fn closed(self: *Fixture) !*support.Handle {
        const handle = try self.create(-1);
        try std.testing.expectEqual(@as(c_int, -1), try self.base.releaseDescriptor());
        return handle;
    }
    fn request(self: *Fixture) !c.JSValue {
        return a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                return a.duplicate(s.engine, try support.templates.newWriteWrapInstance(
                    s, f.base.template_owner.?));
            }
        }.body, .{self});
    }
    fn publish(self: *Fixture, wrapper: c.JSValue) !void {
        try self.base.expose("writevRequest", wrapper);
        try self.base.evaluate("writevRequest.oncomplete=function(status,stream,error){" ++
            "writevCalls.push([this,status,stream,error]);};");
    }
    fn write(self: *Fixture, wrapper: c.JSValue, chunks: c.JSValue,
        all_buffers: c.JSValue) !c_int
    {
        self.last_status = -99999;
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, object: c.JSValue,
                input: c.JSValue, all: c.JSValue) !c.JSValue
            {
                f.last_status = try vectors.writev(s, &(try f.base.handle()).stream,
                    &.{object, input, all});
                return c.pi_js_undefined();
            }
        }.body, .{self, wrapper, chunks, all_buffers});
        self.base.engine.freeValue(ignored);
        return self.last_status;
    }
    fn publicCall(self: *Fixture, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        return a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, r: c.JSValue, argv: []const c.JSValue) !c.JSValue {
                return dispatch.jsMethod(s, f.base.registry(), r, .writev, argv);
            }
        }.body, .{self, receiver, args});
    }
    fn complete(self: *Fixture, status: c_int) !void {
        const request = self.pending_request orelse return error.WritevRequestRequired;
        self.pending_request = null;
        try request.request.done(status, null);
    }
    fn releaseHeld(self: *Fixture) !void {
        const state = self.held_state orelse return;
        self.held_state = null;
        try state.releaseNative();
    }
    fn retired(self: *Fixture, wrapper: c.JSValue) !void {
        try std.testing.expect(self.base.registry().unwrap(wrapper) == null);
        try std.testing.expect(requests.Request.fromObject(self.base.registry(), wrapper) == null);
    }
    fn sameReason(self: *Fixture) !void {
        const reason = try self.base.takeCaught(); defer self.base.engine.freeValue(reason);
        const expected = try self.base.global("writevReason"); defer self.base.engine.freeValue(expected);
        try std.testing.expect(c.JS_IsStrictEqual(self.base.engine.context, reason, expected));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
    }
    fn deinit(self: *Fixture) void {
        if (!self.ready) return;
        if (self.pending_request != null) {
            const old = self.base.env().can_call_into_js;
            self.base.env().can_call_into_js = false;
            self.complete(uv.UV_ECANCELED) catch @panic("writev cleanup failed");
            self.base.env().can_call_into_js = old;
        }
        self.releaseHeld() catch @panic("writev retained owner cleanup failed");
        self.base.stopIo();
        for ([_]*?c.JSValue{ &self.error_key, &self.complete_key }) |slot| {
            if (slot.*) |value| { slot.* = null; self.base.engine.freeValue(value); }
        }
        self.base.deinit(); self.ready = false;
    }
};

fn fixture(engine: *support.em.Engine) *Fixture {
    const base: *support.Fixture = @ptrCast(@alignCast(engine.host_control_context.?));
    return @fieldParentPtr("base", base);
}
fn observeAllocation(raw: ?*anyopaque, env: *support.callbacks.Environment,
    length: usize, initialization: streams.Initialization) managed.Token
{
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    std.debug.assert(f.allocation_count < f.allocation_lengths.len);
    f.allocation_lengths[f.allocation_count] = length;
    f.allocation_modes[f.allocation_count] = initialization;
    f.allocation_count += 1;
    const original = f.original_allocation.?;
    return original.new_backing_store(original.raw, env, length, initialization);
}
fn writeProbe(stream: *streams.Base, _: *a.Scope, request: *requests.Write,
    buffers: []uv.uv_buf_t, send: ?*uv.uv_stream_t) anyerror!c_int
{
    const f = fixture(stream.resource.engine);
    if (send != null or buffers.len > f.vector_lengths.len) return error.UnselectedWritevProbe;
    if (f.gc_before_write) c.JS_RunGC(stream.resource.engine.runtime);
    f.write_calls += 1; f.vector_count = buffers.len; f.write_length = 0;
    for (buffers, 0..) |buffer, index| {
        f.vector_lengths[index] = buffer.len;
        f.vector_data[index] = @ptrCast(buffer.base);
        const copied = @min(@as(usize, buffer.len), f.write_prefix.len - @min(f.write_length, f.write_prefix.len));
        if (copied != 0) @memcpy(f.write_prefix[f.write_length..][0..copied],
            f.vector_data[index][0..copied]);
        f.write_length += buffer.len;
    }
    f.write_counter = stream.resource.bytes_written;
    f.write_provider = request.request.asyncWrap().provider;
    f.last_request = request;
    if (f.hold_sync) {
        try request.request.asyncWrap().retainNative();
        f.held_state = request.request.asyncWrap();
    }
    if (f.write_status == 0) {
        std.debug.assert(f.pending_request == null); f.pending_request = request;
    }
    return f.write_status;
}
fn hasTry(_: *const streams.Base) bool { return true; }
fn tryProbe(stream: *streams.Base, _: *a.Scope, buffers: *[]uv.uv_buf_t) anyerror!c_int {
    const f = fixture(stream.resource.engine);
    f.try_calls += 1; f.try_counter = stream.resource.bytes_written;
    f.try_length = 0;
    for (buffers.*) |buffer| f.try_length += buffer.len;
    var amount = if (f.try_complete) f.try_length else f.try_consumed;
    while (buffers.*.len > 0 and amount >= buffers.*[0].len) {
        amount -= buffers.*[0].len; buffers.* = buffers.*[1..];
    }
    if (amount != 0) {
        std.debug.assert(buffers.*.len > 0);
        buffers.*[0].base += amount;
        buffers.*[0].len -= @intCast(amount);
    }
    return f.try_status;
}
fn configureTry(handle: *support.Handle) void {
    handle.stream.virtuals.has_do_try_write = hasTry;
    handle.stream.virtuals.do_try_write = tryProbe;
}
fn errorString(stream: *streams.Base) ?[*:0]const u8 {
    return if (fixture(stream.resource.engine).message) "native-vector-write" else null;
}
fn clearError(stream: *streams.Base) void {
    const f = fixture(stream.resource.engine); f.message = false; f.error_clears += 1;
}
fn expectStatus(engine: *support.em.Engine, value: c.JSValue, expected: c_int) !void {
    var status: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &status, value));
    try std.testing.expectEqual(@as(i32, expected), status);
}
fn expectResult(f: *Fixture, count: i32, async_write: bool) !void {
    try std.testing.expectEqual(count, f.base.env().streamBaseField(.bytes_written).*);
    try std.testing.expectEqual(@as(i32, @intFromBool(async_write)),
        f.base.env().streamBaseField(.last_write_was_async).*);
}
fn codecCase(f: *Fixture, input: []const u8, encoding: bytes.Encoding,
    capacity: usize, expected: []const u8) !void
{
    const value = try f.base.value(input); defer f.base.engine.freeValue(value);
    var output: [32]u8 = @splat(0xa5);
    var written: usize = undefined;
    const ignored = try a.expression(f.base.engine, struct {
        fn body(s: *a.Scope, fx: *Fixture, string: c.JSValue, enc: bytes.Encoding,
            out: []u8, size: *usize) !c.JSValue
        {
            size.* = try bytes.write(s, fx.base.env(), string, enc, out.ptr, out.len);
            return c.pi_js_undefined();
        }
    }.body, .{ f, value, encoding, output[0..capacity], &written });
    f.base.engine.freeValue(ignored);
    try std.testing.expectEqual(expected.len, written);
    try std.testing.expectEqualSlices(u8, expected, output[0..written]);
    for (output[written..]) |sentinel| try std.testing.expectEqual(@as(u8, 0xa5), sentinel);
}
fn reenter(context: ?*c.JSContext, _: c.JSValue, _: c_int,
    _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue
{
    const engine = support.em.Engine.fromContext(context.?);
    return a.expression(engine, struct {
        fn body(s: *a.Scope) !c.JSValue {
            const f = fixture(s.engine);
            const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
            const wrapper = try s.get(global, "nestedWritevRequest");
            const chunks = try s.get(global, "nestedWritevChunks");
            f.nested_before = f.base.env().uidField(.default_trigger).*;
            const result = try dispatch.jsMethod(s, f.base.registry(), f.base.primary_wrapper.?,
                .writev, &.{wrapper, chunks, c.pi_js_bool(s.engine.context, 0)});
            f.nested_after = f.base.env().uidField(.default_trigger).*;
            return result;
        }
    }.body, .{}) catch |err| callable.failure(engine, err, 0);
}

test "native Stream vector write encoding aliases use primitive C strings without coercing objects" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try f.base.evaluate("globalThis.encodingCoercions=0;");
    inline for (.{
        .{ "'UTf-8'", bytes.Encoding.utf8 }, .{ "'UCS-2'", bytes.Encoding.ucs2 },
        .{ "'Utf16LE'", bytes.Encoding.ucs2 }, .{ "'UTF-16LE'", bytes.Encoding.ucs2 },
        .{ "'LaTiN1'", bytes.Encoding.latin1 }, .{ "'BINARY'", bytes.Encoding.latin1 },
        .{ "'BUFFER'", bytes.Encoding.buffer }, .{ "'BASE64'", bytes.Encoding.base64 },
        .{ "'Base64Url'", bytes.Encoding.base64url }, .{ "'ASCII'", bytes.Encoding.ascii },
        .{ "'HeX\\0ignored'", bytes.Encoding.hex }, .{ "'unknown'", bytes.Encoding.utf8 },
        .{ "23", bytes.Encoding.utf8 }, .{ "Symbol('hex')", bytes.Encoding.utf8 },
        .{ "({toString(){encodingCoercions++;throw writevReason;}})", bytes.Encoding.utf8 },
        .{ "new String('hex')", bytes.Encoding.utf8 },
        .{ "'ascii'+'x'.repeat(1100)", bytes.Encoding.utf8 },
    }) |item| {
        const input = try f.base.value(item[0]); defer f.base.engine.freeValue(input);
        var result: bytes.Encoding = undefined;
        const ignored = try a.expression(f.base.engine, struct {
            fn body(s: *a.Scope, fx: *Fixture, value: c.JSValue, out: *bytes.Encoding) !c.JSValue {
                out.* = try bytes.parseEncoding(s, fx.base.env(), value);
                return c.pi_js_undefined();
            }
        }.body, .{ &f, input, &result });
        f.base.engine.freeValue(ignored);
        try std.testing.expectEqual(item[1], result);
    }
    try f.base.expect("encodingCoercions===0");
}

test "native Stream vector write bounded UTF8 preserves scalar boundaries and untouched suffix" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try codecCase(&f, "'\\ud83d\\ude00Z'", .utf8, 0, &.{});
    try codecCase(&f, "'\\ud83d\\ude00Z'", .utf8, 3, &.{});
    try codecCase(&f, "'\\ud83d\\ude00Z'", .utf8, 4, &.{0xf0,0x9f,0x98,0x80});
    try codecCase(&f, "'\\ud83d\\ude00Z'", .utf8, 5, &.{0xf0,0x9f,0x98,0x80,'Z'});
    try codecCase(&f, "'\\ud800X'", .utf8, 2, &.{});
    try codecCase(&f, "'\\ud800X'", .utf8, 4, &.{0xef,0xbf,0xbd,'X'});
    try codecCase(&f, "'A\\u00e9\\u20ac'", .utf8, 2, "A");
    try codecCase(&f, "'A\\u00e9\\u20ac'", .utf8, 5, &.{'A',0xc3,0xa9});
    try codecCase(&f, "'A\\u00e9\\u20ac'", .buffer, 6, &.{'A',0xc3,0xa9,0xe2,0x82,0xac});
    try codecCase(&f, "'\\0A'", .utf8, 2, &.{0,'A'});
}

test "native Stream vector write ASCII Latin1 and UCS2 clip bytes without splitting units" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try codecCase(&f, "'\\u00e9\\u0101\\ud83d\\ude00'", .ascii, 3, &.{0xe9,1,0x3d});
    try codecCase(&f, "'\\u00e9\\u0101\\ud83d\\ude00'", .latin1, 4, &.{0xe9,1,0x3d,0});
    try codecCase(&f, "'A\\u0101\\ud800'", .ucs2, 1, &.{});
    try codecCase(&f, "'A\\u0101\\ud800'", .ucs2, 5, &.{0x41,0,1,1});
    try codecCase(&f, "'\\ud83d\\ude00\\ud800'", .ucs2, 6, &.{0x3d,0xd8,0,0xde,0,0xd8});
}

test "native Stream vector write base64 preserves garbage padding aliases and bounded fallback" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    inline for (.{bytes.Encoding.base64, bytes.Encoding.base64url}) |encoding| {
        try codecCase(&f, "'SGVsbG8='", encoding, 5, "Hello");
        try codecCase(&f, "'SGV!sbG8=TAIL'", encoding, 4, "Hell");
        try codecCase(&f, "'SGVsbG8='", encoding, 1, "H");
        try codecCase(&f, "'_w'", encoding, 1, &.{0xff});
        try codecCase(&f, "'/w=='", encoding, 1, &.{0xff});
        try codecCase(&f, "'-_8='", encoding, 2, &.{0xfb,0xff});
        try codecCase(&f, "'A'", encoding, 4, &.{});
        try codecCase(&f, "'===='", encoding, 4, &.{});
        try codecCase(&f, "'Zg'", encoding, 4, "f");
        try codecCase(&f, "'Zg=='", encoding, 0, &.{});
    }
}

test "native Stream vector write wide base64 and hex retain TwoByteValue low byte semantics" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try codecCase(&f, "'\\u0154\\u0151=='", .base64, 4, "M");
    try codecCase(&f, "'\\u0154\\u0151=='", .base64url, 1, "M");
    try codecCase(&f, "'\\u0134\\u0131\\u0166\\u0166'", .hex, 4, &.{0x41,0xff});
    try codecCase(&f, "'41f'", .hex, 4, "A");
    try codecCase(&f, "'41zz42'", .hex, 4, "A");
    try codecCase(&f, "'414243'", .hex, 2, "AB");
    try codecCase(&f, "'\\u0154\\u0151'+'='.repeat(1021)", .base64, 1, "M");
    try codecCase(&f, "'\\u0154\\u0151'+'='.repeat(1022)", .base64, 0, &.{});
}

test "native Stream vector write storage capacities preserve encoded base64 formulas and long UTF8" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    inline for (.{
        .{ "'A'", bytes.Encoding.base64, @as(usize,4) },
        .{ "'A'", bytes.Encoding.base64url, @as(usize,2) },
        .{ "'AB'", bytes.Encoding.base64url, @as(usize,3) },
        .{ "'ABC'", bytes.Encoding.base64url, @as(usize,4) },
        .{ "'ABCD'", bytes.Encoding.base64url, @as(usize,6) },
        .{ "'414243'", bytes.Encoding.hex, @as(usize,3) },
        .{ "'\\ud83d\\ude00'", bytes.Encoding.ucs2, @as(usize,4) },
        .{ "'a'.repeat(65536)", bytes.Encoding.utf8, @as(usize,196608) },
        .{ "'a'.repeat(65536)", bytes.Encoding.buffer, @as(usize,196608) },
    }) |item| {
        const input = try f.base.value(item[0]); defer f.base.engine.freeValue(input);
        var result: usize = undefined;
        const ignored = try a.expression(f.base.engine, struct {
            fn body(s: *a.Scope, string: c.JSValue, out: *usize) !c.JSValue {
                out.* = try bytes.storageSize(s, string, item[1]);
                return c.pi_js_undefined();
            }
        }.body, .{input, &result});
        f.base.engine.freeValue(ignored);
        try std.testing.expectEqual(item[2], result);
    }
}

test "native Stream vector write temporary storage uses real charged heap only beyond native stack" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const memory = f.base.engine.native_memory_owner;
    const before = c.pi_js_native_memory_used(memory);
    var small: temporary.Buffer(uv.uv_buf_t, 16) = undefined;
    try small.init(f.base.env(), 16);
    try std.testing.expect(!small.isAllocated());
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(memory));
    small.deinit();
    var large: temporary.Buffer(uv.uv_buf_t, 16) = undefined;
    try large.init(f.base.env(), 17);
    try std.testing.expect(large.isAllocated());
    try std.testing.expectEqual(@as(usize,17), large.data().len);
    try std.testing.expect(c.pi_js_native_memory_used(memory) > before);
    large.deinit();
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(memory));
    var wide: temporary.Buffer(u16, 1024) = undefined;
    try wide.init(f.base.env(), 1024); try std.testing.expect(!wide.isAllocated()); wide.deinit();
    try wide.init(f.base.env(), 1025); try std.testing.expect(wide.isAllocated()); wide.deinit();
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(memory));
}

test "native Stream vector write accepts DataView and every typed array as all buffer chunks" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks = try f.base.value("(()=>{const ab=new ArrayBuffer(8);new Uint8Array(ab).set([1,2,3,4,5,6,7,8]);" ++
        "return [new DataView(ab,1,3),new Uint16Array(ab,4,1),new Uint8ClampedArray(ab,6,2)];})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),
        try f.write(wrapper, chunks, c.pi_js_bool(f.base.engine.context,1)));
    try std.testing.expectEqualSlices(u8, &.{2,3,4,5,6,7,8}, f.write_prefix[0..f.write_length]);
    try std.testing.expectEqualSlices(usize, &.{3,2,2}, f.vector_lengths[0..f.vector_count]);
    try std.testing.expectEqual(@as(usize,0), f.allocation_count);
    try std.testing.expectEqual(@as(u32,52), f.write_provider);
    try expectResult(&f,7,false); try f.retired(wrapper);
}

test "native Stream vector write empty arrays and ignored odd tails still enter real Write without try" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe;
    inline for (.{"[]", "Object.defineProperty([0],0,{get(){throw writevReason;}})"}) |source| {
        const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
        const chunks=try f.base.value(source); defer f.base.engine.freeValue(chunks);
        try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
        try std.testing.expectEqual(@as(usize,0),f.vector_count);
        try std.testing.expectEqual(@as(u32,52),f.write_provider);
        try expectResult(&f,0,false); try f.retired(wrapper);
    }
    try std.testing.expectEqual(@as(usize,0),f.allocation_count);
    try std.testing.expectEqual(@as(usize,2),f.write_calls);
}

test "native Stream vector write all buffers flag requires actual true rather than truthiness" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const chunks = try f.base.value("['A','ascii']"); defer f.base.engine.freeValue(chunks);
    inline for (.{"1", "'yes'", "new Boolean(true)", "null"}) |source| {
        const flag = try f.base.value(source); defer f.base.engine.freeValue(flag);
        const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
        try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,flag));
        try std.testing.expectEqualSlices(u8,"A",f.write_prefix[0..f.write_length]);
        try f.retired(wrapper);
    }
}

test "native Stream vector write two passes repeat Get ToString and encoding in original order" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks = try f.base.value("(()=>{globalThis.vectorEvents=[];let count=0;const a=[0,0];" ++
        "Object.defineProperty(a,0,{get(){vectorEvents.push('get');return {toString(){vectorEvents.push('string');return ++count===1?'xx':'\\u00e9';}};}});" ++
        "Object.defineProperty(a,1,{get(){vectorEvents.push('encoding');return count===1?'ascii':'utf8';}});return a;})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try f.base.expect("JSON.stringify(vectorEvents)==='[\"get\",\"string\",\"encoding\",\"get\",\"string\",\"encoding\"]'");
    try std.testing.expectEqual(@as(usize,2),f.allocation_lengths[0]);
    try std.testing.expectEqualSlices(u8,&.{0xc3,0xa9},f.write_prefix[0..f.write_length]);
    try expectResult(&f,2,false); try f.retired(wrapper);
}

test "native Stream vector write buffer chunks skip both encoding getters in mixed mode" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks = try f.base.value("Object.defineProperty([new Uint8Array([65,66]),0],1,{get(){throw writevReason;}})");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqualSlices(u8,"AB",f.write_prefix[0..f.write_length]);
    try std.testing.expectEqual(@as(usize,0),f.allocation_count);
    try f.retired(wrapper);
}

test "native Stream vector write changed second pass strings share remaining bounded storage" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks = try f.base.value("(()=>{let n=0;const a=[0,'utf8','Z','ascii'];" ++
        "Object.defineProperty(a,0,{get(){return ++n===1?'x':'\\ud83d\\ude00';}});return a;})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqual(@as(usize,4),f.allocation_lengths[0]);
    try std.testing.expectEqualSlices(usize,&.{4,0},f.vector_lengths[0..f.vector_count]);
    try std.testing.expectEqualSlices(u8,&.{0xf0,0x9f,0x98,0x80},f.write_prefix[0..f.write_length]);
    try expectResult(&f,4,false); try f.retired(wrapper);
}

test "native Stream vector write changed UTF8 pair cannot fit in a first pass three byte capacity" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks = try f.base.value("(()=>{let n=0;return Object.defineProperty([0,'utf8'],0,{get(){return ++n===1?'a':'\\ud83d\\ude00';}});})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqual(@as(usize,3),f.allocation_lengths[0]);
    try std.testing.expectEqual(@as(usize,1),f.write_calls);
    try std.testing.expectEqualSlices(usize,&.{0},f.vector_lengths[0..f.vector_count]);
    try expectResult(&f,0,false); try f.retired(wrapper);
}

test "native Stream vector write buffer to string transition keeps a genuinely absent backing" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks = try f.base.value("(()=>{globalThis.zeroEncodingGets=0;let n=0;const a=[0,0];" ++
        "Object.defineProperty(a,0,{get(){return ++n===1?new Uint8Array([65]):'abc';}});" ++
        "Object.defineProperty(a,1,{get(){zeroEncodingGets++;return 'ascii';}});return a;})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqual(@as(usize,0),f.allocation_count);
    try std.testing.expectEqualSlices(usize,&.{0},f.vector_lengths[0..f.vector_count]);
    try std.testing.expect(f.vector_data[0]==null);
    try f.base.expect("zeroEncodingGets===1"); try expectResult(&f,0,false); try f.retired(wrapper);
}

test "native Stream vector write string to buffer transition still transfers its original positive backing" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe; f.write_status=0;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const chunks = try f.base.value("(()=>{globalThis.transitionBuffer=new Uint8Array([65,66]);let n=0;" ++
        "return Object.defineProperty([0,'utf8'],0,{get(){return ++n===1?'x':transitionBuffer;}});})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,0),try f.write(wrapper,chunks,c.pi_js_undefined()));
    const request=f.pending_request.?;
    try std.testing.expect(request.backing_store!=null);
    try std.testing.expectEqual(@as(usize,3),c.JS_PiArrayBufferBackingStoreByteLength(&request.backing_store.?));
    try std.testing.expect(f.vector_data[0] != c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?));
    try std.testing.expectEqualSlices(u8,"AB",f.write_prefix[0..f.write_length]);
    try expectResult(&f,2,true); try f.complete(0); try f.retired(wrapper);
}

test "native Stream vector write snapshots count before getters extend the array" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write=writeProbe;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("(()=>{globalThis.countReads=0;const a=[0,'ascii'];" ++
        "Object.defineProperty(a,0,{get(){if(++countReads===1)a.push({toString(){throw writevReason;}},'ascii');return 'A';}});return a;})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try f.base.expect("countReads===2");
    try std.testing.expectEqual(@as(usize,1),f.vector_count);
    try std.testing.expectEqualSlices(u8,"A",f.write_prefix[0..f.write_length]); try f.retired(wrapper);
}

test "native Stream vector write combines all eight encodings in the actual vector callback" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("['A','ascii','\\u00e9','latin1','\\u00e9','utf8','Z','ucs2'," ++
        "'B','buffer','TQ==','base64','_w','base64url','4142','hex']");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqual(@as(usize,23),f.allocation_lengths[0]);
    try std.testing.expectEqual(streams.Initialization.uninitialized,f.allocation_modes[0]);
    try std.testing.expectEqualSlices(usize,&.{1,1,2,2,1,1,1,2},f.vector_lengths[0..f.vector_count]);
    try std.testing.expectEqualSlices(u8,&.{65,0xe9,0xc3,0xa9,90,0,66,77,0xff,65,66},f.write_prefix[0..f.write_length]);
    try expectResult(&f,11,false); try f.retired(wrapper);
}

test "native Stream vector write first pass abrupt Gets and coercions preserve reason and result state" {
    inline for (.{
        "Object.defineProperty([0,'utf8'],0,{get(){throw writevReason;}})",
        "[{toString(){throw writevReason;}},'utf8']",
        "Object.defineProperty(['A',0],1,{get(){throw writevReason;}})",
    }) |source| {
        var f: Fixture=undefined; try f.init(); defer f.deinit();
        const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe;
        const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
        const chunks=try f.base.value(source); defer f.base.engine.freeValue(chunks);
        f.base.env().streamBaseField(.bytes_written).*=313;
        f.base.env().streamBaseField(.last_write_was_async).*=1;
        try std.testing.expectError(error.JavaScriptException,f.write(wrapper,chunks,c.pi_js_undefined()));
        try f.sameReason();
        try std.testing.expectEqual(@as(c_int,-1),f.last_status);
        try std.testing.expectEqual(@as(usize,0),f.allocation_count);
        try std.testing.expectEqual(@as(usize,0),f.write_calls);
        try std.testing.expectEqual(@as(u64,0),handle.stream.resource.bytes_written);
        try expectResult(&f,313,true); try f.retired(wrapper);
    }
}

test "native Stream vector write second pass abrupt Gets and coercions retire local backing before Write" {
    inline for (.{
        "(()=>{let n=0;return Object.defineProperty([0,'utf8'],0,{get(){if(++n===2)throw writevReason;return 'A';}});})()",
        "(()=>{let n=0;return [{toString(){if(++n===2)throw writevReason;return 'A';}},'utf8'];})()",
        "(()=>{let n=0;return Object.defineProperty(['A',0],1,{get(){if(++n===2)throw writevReason;return 'utf8';}});})()",
    }) |source| {
        var f: Fixture=undefined; try f.init(); defer f.deinit();
        const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe;
        const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
        const chunks=try f.base.value(source); defer f.base.engine.freeValue(chunks);
        f.base.env().streamBaseField(.bytes_written).*=413;
        f.base.env().streamBaseField(.last_write_was_async).*=1;
        try std.testing.expectError(error.JavaScriptException,f.write(wrapper,chunks,c.pi_js_undefined()));
        try f.sameReason();
        try std.testing.expectEqual(@as(c_int,-1),f.last_status);
        try std.testing.expectEqual(@as(usize,1),f.allocation_count);
        try std.testing.expectEqual(@as(usize,3),f.allocation_lengths[0]);
        try std.testing.expectEqual(@as(usize,0),f.write_calls);
        try expectResult(&f,413,true); try f.retired(wrapper);
    }
}

test "native Stream vector write retained local views survive replacement and native collection" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe; f.gc_before_write=true;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("(()=>{const a=[new Uint8Array([65,66]),0];" ++
        "Object.defineProperty(a,1,{get(){delete a[0];return new DataView(new Uint8Array([67,68]).buffer);}});return a;})()");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),
        try f.write(wrapper,chunks,c.pi_js_bool(f.base.engine.context,1)));
    try std.testing.expectEqualSlices(u8,"ABCD",f.write_prefix[0..f.write_length]);
    try std.testing.expectEqual(@as(usize,0),f.allocation_count); try f.retired(wrapper);
}

test "native Stream vector write accepted encoded backing survives input GC completion and native retention" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe; f.write_status=0;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const chunks=try f.base.value("['A','ascii','\\u00e9','utf8']");
    var input_owned=true; defer if(input_owned) f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,0),try f.write(wrapper,chunks,c.pi_js_undefined()));
    const request=f.pending_request.?; const state=request.request.asyncWrap();
    try std.testing.expect(request.backing_store!=null);
    const data=c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?);
    try std.testing.expectEqual(@as(usize,4),c.JS_PiArrayBufferBackingStoreByteLength(&request.backing_store.?));
    try std.testing.expect(f.vector_data[0]==data and f.vector_data[1]==data+1);
    f.base.engine.freeValue(chunks); input_owned=false; c.JS_RunGC(f.base.engine.runtime);
    try std.testing.expectEqualSlices(u8,&.{65,0xc3,0xa9},data[0..3]);
    try state.retainNative(); f.held_state=state;
    try f.complete(0);
    try std.testing.expect(state.detached and request.backing_store!=null);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(),wrapper)==null);
    try std.testing.expect(f.base.registry().unwrap(wrapper)==state);
    try std.testing.expectEqualSlices(u8,&.{65,0xc3,0xa9},data[0..3]);
    try f.releaseHeld(); try f.retired(wrapper);
    try f.base.expect("writevCalls.length===1 && writevCalls[0][0]===writevRequest && writevCalls[0][1]===0 && writevCalls[0][2]===writevHandle");
}

test "native Stream vector write synchronous native error transfers backing until its retained owner retires" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe; f.hold_sync=true;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("['A','utf8']"); defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    const request=f.last_request.?; const state=f.held_state.?;
    try std.testing.expect(state.detached and request.backing_store!=null);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(),wrapper)==null);
    try std.testing.expect(f.base.registry().unwrap(wrapper)==state);
    try std.testing.expectEqual(@as(usize,3),c.JS_PiArrayBufferBackingStoreByteLength(&request.backing_store.?));
    try std.testing.expectEqual(@as(u8,65),c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?)[0]);
    try f.releaseHeld(); try f.retired(wrapper);
}

test "native Stream vector write try completion bypasses request publication but counts full bytes" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); configureTry(handle); f.try_complete=true;
    handle.stream.virtuals.do_write=writeProbe;
    const wrapper=try f.base.value("({})"); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("['ab','ascii','cd','ascii']"); defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,0),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqual(@as(usize,1),f.try_calls);
    try std.testing.expectEqual(@as(u64,4),f.try_counter);
    try std.testing.expectEqual(@as(u64,4),handle.stream.resource.bytes_written);
    try std.testing.expectEqual(@as(usize,0),f.write_calls);
    try std.testing.expectEqual(@as(usize,1),f.allocation_count); try expectResult(&f,4,false);
}

test "native Stream vector write partial try advances across vector boundaries without double counting" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); configureTry(handle); f.try_consumed=3;
    handle.stream.virtuals.do_write=writeProbe;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("['ab','ascii','cde','ascii',new Uint8Array([88,89]),'ignored']");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EIO),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqualSlices(usize,&.{2,2},f.vector_lengths[0..f.vector_count]);
    try std.testing.expectEqualSlices(u8,"deXY",f.write_prefix[0..f.write_length]);
    try std.testing.expectEqual(@as(u64,7),f.try_counter);
    try std.testing.expectEqual(@as(u64,7),f.write_counter);
    try std.testing.expectEqual(@as(usize,5),f.allocation_lengths[0]);
    try expectResult(&f,7,false); try f.retired(wrapper);
}

test "native Stream vector write try failure returns full attempted byte count with no WriteWrap" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); configureTry(handle); f.try_consumed=1; f.try_status=uv.UV_EPIPE;
    handle.stream.virtuals.do_write=writeProbe;
    const wrapper=try f.base.value("({})"); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("['AB','ascii','CD','ascii']"); defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,uv.UV_EPIPE),try f.write(wrapper,chunks,c.pi_js_undefined()));
    try std.testing.expectEqual(@as(usize,0),f.write_calls);
    try std.testing.expectEqual(@as(u64,4),handle.stream.resource.bytes_written);
    try expectResult(&f,4,false);
}

test "native Stream vector write seventeen native views use vector heap without inventing backing lease" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe; f.write_status=0;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const chunks=try f.base.value("Array.from({length:17},(_,i)=>new Uint8Array([i]))");
    defer f.base.engine.freeValue(chunks);
    try std.testing.expectEqual(@as(c_int,0),
        try f.write(wrapper,chunks,c.pi_js_bool(f.base.engine.context,1)));
    try std.testing.expectEqual(@as(usize,17),f.vector_count);
    for(f.write_prefix[0..17],0..) |value,index| try std.testing.expectEqual(@as(u8,@intCast(index)),value);
    try std.testing.expectEqual(@as(usize,0),f.allocation_count);
    try std.testing.expect(f.pending_request.?.backing_store==null);
    try expectResult(&f,17,true); try f.complete(0); try f.retired(wrapper);
}

test "native Stream vector write accepted request with later error setter failure preserves default native result" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe; f.write_status=0;
    handle.stream.virtuals.error_string=errorString;
    handle.stream.virtuals.clear_error=clearError; f.message=true;
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    try f.base.evaluate("Object.defineProperty(writevRequest,'error',{set(){throw writevReason;}})");
    const chunks=try f.base.value("['A','utf8']"); defer f.base.engine.freeValue(chunks);
    try std.testing.expectError(error.JavaScriptException,f.write(wrapper,chunks,c.pi_js_undefined()));
    try f.sameReason(); try std.testing.expectEqual(@as(c_int,uv.UV_EBUSY),f.last_status);
    try std.testing.expect(f.pending_request!=null and f.pending_request.?.backing_store==null);
    try std.testing.expect(f.message and f.error_clears==0);
    try std.testing.expectEqual(@as(u64,1),handle.stream.resource.bytes_written);
    try expectResult(&f,0,false);
    // The Source did not return a wrap to receive the token. Do not dereference
    // its former encoded vector after this point; this probe owns no real I/O.
    try f.complete(0); try f.retired(wrapper);
}

test "native Stream vector write ordinary init hook throw still transfers accepted encoded backing" {
    var f: Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.closed(); handle.stream.virtuals.do_write=writeProbe; f.write_status=0;
    try f.base.installInitRecorder();
    try f.base.evaluate("ownerInitHook=function(){throw writevReason;}");
    const hook=try f.base.global("ownerInitHook"); defer f.base.engine.freeValue(hook);
    try f.base.env().installHooks(.{.init=hook,.before=hook,.after=hook,.destroy=hook,.promise_resolve=hook},
        f.base.binding_target.?);
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const chunks=try f.base.value("['\\u00e9','utf8']"); defer f.base.engine.freeValue(chunks);
    try std.testing.expectError(error.JavaScriptException,f.write(wrapper,chunks,c.pi_js_undefined()));
    try f.sameReason(); try std.testing.expectEqual(@as(c_int,0),f.last_status);
    const request=f.pending_request.?;
    try std.testing.expect(request.backing_store!=null);
    try std.testing.expectEqualSlices(u8,&.{0xc3,0xa9},
        c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?)[0..2]);
    try expectResult(&f,2,true); try f.complete(0); try f.retired(wrapper);
}

test "native Stream vector write real FileHandle dispatch preserves ENOSYS and trigger scope" {
    var file:support.File=undefined; try file.init(); defer file.deinit();
    var f:Fixture=undefined; try f.init(); defer f.deinit();
    const fd=file.take(); const handle=try f.create(fd);
    try f.base.installInitRecorder();
    const wrapper=try f.request(); defer f.base.engine.freeValue(wrapper);
    const chunks=try f.base.value("['AB','ascii']"); defer f.base.engine.freeValue(chunks);
    f.base.env().uidField(.default_trigger).*=727;
    const result=try f.publicCall(f.base.primary_wrapper.?,&.{wrapper,chunks,c.pi_js_undefined()});
    defer f.base.engine.freeValue(result);
    try expectStatus(f.base.engine,result,uv.UV_ENOSYS);
    try std.testing.expectEqual(@as(f64,727),f.base.env().uidField(.default_trigger).*);
    try std.testing.expect(handle.isAlive() and support.File.status(fd)==0);
    try std.testing.expectEqual(@as(u64,2),handle.stream.resource.bytes_written);
    try f.base.expect("ownerInitEvents.length===1 && ownerInitEvents[0][0]==='WRITEWRAP'");
    try expectResult(&f,2,false); try f.retired(wrapper);
    file.descriptor=try f.base.releaseDescriptor();
}

test "native Stream vector write absent and dead dispatch guards precede native argument CHECKs" {
    var f:Fixture=undefined; try f.init(); defer f.deinit(); _=try f.closed();
    const absent=try f.base.value("({})"); defer f.base.engine.freeValue(absent);
    const missing=try f.publicCall(absent,&.{}); defer f.base.engine.freeValue(missing);
    try std.testing.expect(c.JS_IsUndefined(missing));
    const dead=try f.publicCall(f.base.primary_wrapper.?,&.{}); defer f.base.engine.freeValue(dead);
    try expectStatus(f.base.engine,dead,uv.UV_EINVAL);
    try std.testing.expectEqual(@as(usize,0),f.allocation_count);
}

test "native Stream vector write getter reentry uses canonical dispatch and restores outer trigger state" {
    var file:support.File=undefined; try file.init(); defer file.deinit();
    var f:Fixture=undefined; try f.init(); defer f.deinit();
    const handle=try f.create(file.take()); handle.stream.virtuals.do_write=writeProbe;
    const outer=try f.request(); defer f.base.engine.freeValue(outer);
    const nested=try f.request(); defer f.base.engine.freeValue(nested);
    try f.base.expose("nestedWritevRequest",nested);
    try f.base.evaluate("globalThis.nestedWritevChunks=['I','ascii'];");
    const ignored=try a.expression(f.base.engine,struct {
        fn body(s:*a.Scope)!c.JSValue {
            const generation=try s.beforeAllocation();
            const function=try s.checkedAllocation(c.pi_js_function_magic(
                s.engine.context,reenter,"nativeReenterWritev",0,0),generation);
            const global=try s.checked(c.JS_GetGlobalObject(s.engine.context));
            try s.put(global,"nativeReenterWritev",function);
            return c.pi_js_undefined();
        }
    }.body,.{});
    f.base.engine.freeValue(ignored);
    const chunks=try f.base.value("(()=>{let n=0;return Object.defineProperty([0,'ascii'],0," ++
        "{get(){if(++n===1)nativeReenterWritev();return 'OUT';}});})()");
    defer f.base.engine.freeValue(chunks);
    f.base.env().uidField(.default_trigger).*=733;
    const result=try f.publicCall(f.base.primary_wrapper.?,&.{outer,chunks,c.pi_js_undefined()});
    defer f.base.engine.freeValue(result);
    try expectStatus(f.base.engine,result,uv.UV_EIO);
    try std.testing.expectEqual(@as(usize,2),f.write_calls);
    try std.testing.expectEqualSlices(usize,&.{1,3},f.allocation_lengths[0..f.allocation_count]);
    try std.testing.expectEqualSlices(u8,"OUT",f.write_prefix[0..f.write_length]);
    try std.testing.expectEqual(@as(u64,4),handle.stream.resource.bytes_written);
    try std.testing.expectEqual(handle.wrap.async_id,f.nested_before);
    try std.testing.expectEqual(f.nested_before,f.nested_after);
    try std.testing.expectEqual(@as(f64,733),f.base.env().uidField(.default_trigger).*);
    try f.retired(outer); try f.retired(nested); try expectResult(&f,3,false);
    file.descriptor=try f.base.releaseDescriptor();
}

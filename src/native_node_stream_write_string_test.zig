//! Focused genuine StreamBase::WriteString controls; authored, not executed.
//! Native virtual probes observe this callback's selected data and result path.
//! Actual FileHandle, WriteWrap, Environment, backing and completion owners run.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const a = support.a;
const c = a.c;
const strings = @import("extensions/native_node_stream_write_string.zig");
const writes = @import("extensions/native_node_stream_write.zig");
const requests = @import("extensions/native_node_stream_request.zig");
const streams = @import("extensions/native_node_stream_base.zig");
const dispatch = @import("extensions/native_node_stream_js_dispatch.zig");
const managed = @import("extensions/native_node_managed_buffers.zig");
const uv = managed.uv;

const Fixture = struct {
    base: support.Fixture = undefined,
    ready: bool = false,
    error_key: ?c.JSValue = null,
    complete_key: ?c.JSValue = null,
    original_allocation: ?streams.Allocation = null,
    allocation_count: usize = 0,
    allocation_lengths: [8]usize = undefined,
    allocation_modes: [8]streams.Initialization = undefined,
    pending_request: ?*requests.Write = null,
    last_status: c_int = -99999,
    write_status: c_int = uv.UV_EIO,
    write_calls: usize = 0,
    write_length: usize = 0,
    write_prefix: [256]u8 = undefined,
    write_data: [*c]const u8 = null,
    write_counter: u64 = 0,
    write_provider: u32 = 0,
    try_calls: usize = 0,
    try_counter: u64 = 0,
    try_length: usize = 0,
    try_status: c_int = 0,
    try_complete: bool = false,
    try_consumed: usize = 0,
    message: bool = false,
    error_clears: usize = 0,

    fn init(self: *Fixture) !void {
        self.* = .{};
        try self.base.init();
        self.ready = true;
        errdefer self.deinit();
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                f.error_key = a.duplicate(s.engine, try s.text("error"));
                f.complete_key = a.duplicate(s.engine, try s.text("oncomplete"));
                return c.pi_js_undefined();
            }
        }.body, .{self});
        self.base.engine.freeValue(ignored);
        try self.base.evaluate("globalThis.stringWriteCalls=[];globalThis.stringWriteReason={};");
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
        try self.base.expose("stringWriteHandle", self.base.primary_wrapper.?);
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
        try self.base.expose("stringWriteRequest", wrapper);
        try self.base.evaluate(
            "stringWriteRequest.oncomplete=function(status,stream,error){" ++
            "stringWriteCalls.push([this,status,stream,error]);};");
    }
    fn write(self: *Fixture, wrapper: c.JSValue, value: c.JSValue,
        comptime encoding: strings.Encoding) !c_int
    {
        return self.writeWithHandle(wrapper, value, c.pi_js_undefined(), encoding);
    }
    fn writeWithHandle(self: *Fixture, wrapper: c.JSValue, value: c.JSValue,
        handle: c.JSValue, comptime encoding: strings.Encoding) !c_int
    {
        self.last_status = -99999;
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, object: c.JSValue,
                input: c.JSValue, send: c.JSValue) !c.JSValue
            {
                f.last_status = try strings.writeString(s, &(try f.base.handle()).stream,
                    &.{object, input, send}, encoding);
                return c.pi_js_undefined();
            }
        }.body, .{self, wrapper, value, handle});
        self.base.engine.freeValue(ignored);
        return self.last_status;
    }
    fn publicCall(self: *Fixture, receiver: c.JSValue,
        method: dispatch.Method, args: []const c.JSValue) !c.JSValue
    {
        return a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, r: c.JSValue, selected: dispatch.Method,
                argv: []const c.JSValue) !c.JSValue
            {
                return dispatch.jsMethod(s, f.base.registry(), r, selected, argv);
            }
        }.body, .{self, receiver, method, args});
    }
    fn complete(self: *Fixture, status: c_int) !void {
        const pending = self.pending_request orelse return error.StringWriteRequestRequired;
        self.pending_request = null;
        return pending.request.done(status, null);
    }
    fn retired(self: *Fixture, wrapper: c.JSValue) !void {
        try std.testing.expect(self.base.registry().unwrap(wrapper) == null);
        try std.testing.expect(requests.Request.fromObject(self.base.registry(), wrapper) == null);
    }
    fn sameReason(self: *Fixture) !void {
        const reason = try self.base.takeCaught();
        defer self.base.engine.freeValue(reason);
        const expected = try self.base.global("stringWriteReason");
        defer self.base.engine.freeValue(expected);
        try std.testing.expect(c.JS_IsStrictEqual(self.base.engine.context, reason, expected));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
    }
    fn deinit(self: *Fixture) void {
        if (!self.ready) return;
        if (self.pending_request != null) {
            const old = self.base.env().can_call_into_js;
            self.base.env().can_call_into_js = false;
            self.complete(uv.UV_ECANCELED) catch @panic("string write cleanup failed");
            self.base.env().can_call_into_js = old;
        }
        self.base.stopIo();
        for ([_]*?c.JSValue{ &self.error_key, &self.complete_key }) |slot| {
            if (slot.*) |value| { slot.* = null; self.base.engine.freeValue(value); }
        }
        self.base.deinit();
        self.ready = false;
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
    if (send != null or buffers.len != 1) return error.UnselectedStringWriteProbe;
    f.write_calls += 1;
    f.write_length = buffers[0].len;
    f.write_data = @ptrCast(buffers[0].base);
    const copied = @min(f.write_length, f.write_prefix.len);
    if (copied != 0) @memcpy(f.write_prefix[0..copied], f.write_data[0..copied]);
    f.write_counter = stream.resource.bytes_written;
    f.write_provider = request.request.asyncWrap().provider;
    if (f.write_status == 0) {
        std.debug.assert(f.pending_request == null);
        f.pending_request = request;
    }
    return f.write_status;
}
fn hasTry(_: *const streams.Base) bool { return true; }
fn tryProbe(stream: *streams.Base, _: *a.Scope, buffers: *[]uv.uv_buf_t) anyerror!c_int {
    const f = fixture(stream.resource.engine);
    if (buffers.*.len != 1) return error.UnselectedStringTryWriteProbe;
    f.try_calls += 1;
    f.try_counter = stream.resource.bytes_written;
    f.try_length = buffers.*[0].len;
    if (f.try_complete) {
        buffers.* = buffers.*[1..];
    } else {
        std.debug.assert(f.try_consumed <= buffers.*[0].len);
        if (f.try_consumed != 0) buffers.*[0].base += f.try_consumed;
        buffers.*[0].len -= @intCast(f.try_consumed);
    }
    return f.try_status;
}
fn configureTry(handle: *support.Handle) void {
    handle.stream.virtuals.has_do_try_write = hasTry;
    handle.stream.virtuals.do_try_write = tryProbe;
}
fn errorString(stream: *streams.Base) ?[*:0]const u8 {
    return if (fixture(stream.resource.engine).message) "native-string-write" else null;
}
fn clearError(stream: *streams.Base) void {
    const f = fixture(stream.resource.engine);
    f.message = false;
    f.error_clears += 1;
}
fn expectStatus(engine: *support.em.Engine, value: c.JSValue, expected: c_int) !void {
    var status: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &status, value));
    try std.testing.expectEqual(@as(i32, expected), status);
}
fn expectResult(f: *Fixture, bytes: i32, async_write: bool) !void {
    try std.testing.expectEqual(bytes, f.base.env().streamBaseField(.bytes_written).*);
    try std.testing.expectEqual(@as(i32, @intFromBool(async_write)),
        f.base.env().streamBaseField(.last_write_was_async).*);
}

test "native Stream string write borrowed view preserves actual primitive code units without coercion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const narrow = try f.base.value("'xxA\\u00e9\\0Bzz'.slice(2,6)");
    defer f.base.engine.freeValue(narrow);
    var view: c.JSPiStringView = undefined;
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiBorrowFlatStringView(narrow, &view));
    try std.testing.expectEqual(@as(usize, 4), view.length);
    try std.testing.expect(view.data8 != null and view.data16 == null);
    try std.testing.expectEqualSlices(u8, &.{0x41,0xe9,0,0x42}, view.data8[0..4]);
    const wide = try f.base.value("('padding'.repeat(20)+'\\u0102\\ud83d\\ude00\\ud800'+'tail').slice(140,144)");
    defer f.base.engine.freeValue(wide);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiBorrowFlatStringView(wide, &view));
    try std.testing.expect(view.data8 == null and view.data16 != null);
    c.JS_RunGC(f.base.engine.runtime);
    try std.testing.expectEqualSlices(u16, &.{0x0102,0xd83d,0xde00,0xd800}, view.data16[0..view.length]);
    const empty = try f.base.value("''"); defer f.base.engine.freeValue(empty);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiBorrowFlatStringView(empty, &view));
    try std.testing.expectEqual(@as(usize, 0), view.length);
    const object = try f.base.value("({toString(){throw Error('coerced')}})");
    defer f.base.engine.freeValue(object);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiBorrowFlatStringView(object, &view));
    try std.testing.expect(view.data8 == null and view.data16 == null and view.length == 0);
    try std.testing.expect(!c.JS_HasException(f.base.engine.context));
}

test "native Stream string write all four dispatch methods keep physical FileHandle ENOSYS and provider52" {
    var file: support.File = undefined; try file.init(); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.create(file.take());
    const fd = handle.getFD();
    const refs = handle.wrap.native_references;
    const value = try f.base.value("'abc'"); defer f.base.engine.freeValue(value);
    try f.base.installInitRecorder();
    f.base.env().uidField(.default_trigger).* = 131;
    inline for (.{ dispatch.Method.write_ascii_string, .write_latin1_string,
        .write_utf8_string, .write_ucs2_string }, .{3,3,3,6}) |method, expected|
    {
        const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
        const returned = try f.publicCall(f.base.primary_wrapper.?, method, &.{wrapper, value});
        defer f.base.engine.freeValue(returned);
        try expectStatus(f.base.engine, returned, uv.UV_ENOSYS);
        try expectResult(&f, expected, false);
        try std.testing.expectEqual(@as(f64, 131), f.base.env().uidField(.default_trigger).*);
        try f.retired(wrapper);
    }
    try std.testing.expectEqual(@as(u64, 15), handle.stream.resource.bytes_written);
    try std.testing.expectEqual(refs, handle.wrap.native_references);
    try std.testing.expect(handle.isAlive() and support.File.status(fd) == 0);
    try f.base.expect("ownerInitEvents.length===4 && ownerInitEvents.every(row=>row[0]==='WRITEWRAP')");
    file.descriptor = try f.base.releaseDescriptor();
}

test "native Stream string write ASCII and Latin1 preserve low bytes high bits NUL and surrogate units" {
    inline for (.{strings.Encoding.ascii, .latin1}) |encoding| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
        const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
        const value = try f.base.value("'\\u00e9\\u0101\\ud83d\\ude00\\ud800\\0'");
        defer f.base.engine.freeValue(value);
        try std.testing.expectEqual(@as(c_int, uv.UV_EIO), try f.write(wrapper, value, encoding));
        try std.testing.expectEqualSlices(u8, &.{0xe9,1,0x3d,0,0,0}, f.write_prefix[0..f.write_length]);
        try std.testing.expectEqual(@as(usize, 6), f.allocation_lengths[0]);
        try std.testing.expectEqual(streams.Initialization.uninitialized, f.allocation_modes[0]);
        try expectResult(&f, 6, false);
        try f.retired(wrapper);
    }
}

test "native Stream string write UTF8 combines pairs replaces lone surrogates and preserves embedded NUL" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("'\\0A\\u00e9\\u20ac\\ud83d\\ude00\\ud800Z\\udc00'");
    defer f.base.engine.freeValue(value);
    _ = try f.write(wrapper, value, .utf8);
    const expected = [_]u8{0,0x41,0xc3,0xa9,0xe2,0x82,0xac,0xf0,0x9f,0x98,0x80,0xef,0xbf,0xbd,0x5a,0xef,0xbf,0xbd};
    try std.testing.expectEqualSlices(u8, &expected, f.write_prefix[0..f.write_length]);
    try std.testing.expectEqual(@as(usize, 27), f.allocation_lengths[0]);
    try expectResult(&f, 18, false);
}

test "native Stream string write UCS2 emits little endian code units without surrogate replacement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("'\\u0102\\u00ff\\ud83d\\ude00\\ud800\\0'");
    defer f.base.engine.freeValue(value);
    _ = try f.write(wrapper, value, .ucs2);
    const expected = [_]u8{2,1,0xff,0,0x3d,0xd8,0,0xde,0,0xd8,0,0};
    try std.testing.expectEqualSlices(u8, &expected, f.write_prefix[0..f.write_length]);
    try std.testing.expectEqual(@as(usize, 12), f.allocation_lengths[0]);
    try expectResult(&f, 12, false);
}

test "native Stream string write direct complete try bypasses template backing and native request" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); configureTry(handle); f.try_complete = true;
    handle.stream.operations.write = null;
    handle.stream.virtuals.do_write = null;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("'A\\ud83d\\ude00B'"); defer f.base.engine.freeValue(value);
    try std.testing.expectEqual(@as(c_int, 0), try f.write(wrapper, value, .utf8));
    try std.testing.expectEqual(@as(usize, 1), f.try_calls);
    try std.testing.expectEqual(@as(u64, 0), f.try_counter);
    try std.testing.expectEqual(@as(u64, 6), handle.stream.resource.bytes_written);
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
    try std.testing.expectEqual(@as(usize, 0), f.write_calls);
    try expectResult(&f, 6, false);
    try f.retired(wrapper);
}

test "native Stream string write direct try error counts only consumed bytes but reports the whole string" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); configureTry(handle);
    f.try_status = uv.UV_EIO; f.try_consumed = 2;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("'A\\ud83d\\ude00B'"); defer f.base.engine.freeValue(value);
    try std.testing.expectEqual(@as(c_int, uv.UV_EIO), try f.write(wrapper, value, .utf8));
    try std.testing.expectEqual(@as(u64, 2), handle.stream.resource.bytes_written);
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
    try std.testing.expectEqual(@as(usize, 0), f.write_calls);
    try expectResult(&f, 6, false);
    try f.retired(wrapper);
}

test "native Stream string write partial try copies the exact remaining byte suffix and never retries" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); configureTry(handle); f.try_consumed = 2;
    handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("'A\\ud83d\\ude00B'"); defer f.base.engine.freeValue(value);
    try std.testing.expectEqual(@as(c_int, uv.UV_EIO), try f.write(wrapper, value, .utf8));
    try std.testing.expectEqual(@as(usize, 1), f.try_calls);
    try std.testing.expectEqual(@as(usize, 1), f.write_calls);
    try std.testing.expectEqualSlices(u8, &.{0x9f,0x98,0x80,0x42}, f.write_prefix[0..f.write_length]);
    try std.testing.expectEqual(@as(usize, 4), f.allocation_lengths[0]);
    try std.testing.expectEqual(@as(u64, 6), f.write_counter);
    try std.testing.expectEqual(@as(u32, 52), f.write_provider);
    try expectResult(&f, 6, false);
    try f.retired(wrapper);
}

test "native Stream string write accepted partial backing survives completion Dispose until native retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); configureTry(handle); f.try_consumed = 2;
    handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const value = try f.base.value("'A\\ud83d\\ude00B'"); defer f.base.engine.freeValue(value);
    try std.testing.expectEqual(@as(c_int, 0), try f.write(wrapper, value, .utf8));
    const request = f.pending_request.?;
    const state = request.request.asyncWrap();
    try std.testing.expect(request.backing_store != null);
    try std.testing.expectEqual(@as(usize, 4),
        c.JS_PiArrayBufferBackingStoreByteLength(&request.backing_store.?));
    const bytes = c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?);
    try std.testing.expect(bytes == f.write_data);
    try std.testing.expectEqualSlices(u8, &.{0x9f,0x98,0x80,0x42}, bytes[0..4]);
    try expectResult(&f, 6, true);
    try state.retainNative();
    var holding = true;
    defer if (holding) state.releaseNative() catch @panic("retained string WriteWrap release failed");
    try f.complete(0);
    try std.testing.expect(request.backing_store != null and state.detached);
    try std.testing.expectEqualSlices(u8, &.{0x9f,0x98,0x80,0x42}, bytes[0..4]);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == null);
    try std.testing.expect(f.base.registry().unwrap(wrapper) == state);
    holding = false;
    try state.releaseNative();
    try f.retired(wrapper);
    try f.base.expect("stringWriteCalls.length===1 && stringWriteCalls[0][0]===stringWriteRequest && stringWriteCalls[0][1]===0 && stringWriteCalls[0][2]===stringWriteHandle");
}

test "native Stream string write full async backing owns encoded bytes after the input root is released" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const value = try f.base.value("'\\u00e9'");
    const status = f.write(wrapper, value, .utf8);
    f.base.engine.freeValue(value);
    try std.testing.expectEqual(@as(c_int, 0), try status);
    c.JS_RunGC(f.base.engine.runtime);
    const request = f.pending_request.?;
    try std.testing.expectEqual(@as(usize, 3),
        c.JS_PiArrayBufferBackingStoreByteLength(&request.backing_store.?));
    const bytes = c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?);
    try std.testing.expectEqualSlices(u8, &.{0xc3,0xa9}, bytes[0..2]);
    try std.testing.expectEqual(@as(usize, 2), f.write_length);
    try expectResult(&f, 2, true);
    try f.complete(0); try f.retired(wrapper);
}

test "native Stream string write 16KiB shortcut uses StorageSize including the UTF8 triple" {
    inline for (.{
        .{ strings.Encoding.ascii, 16384, true },
        .{ strings.Encoding.ascii, 16385, false },
        .{ strings.Encoding.utf8, 5461, true },
        .{ strings.Encoding.utf8, 5462, false },
    }) |case| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const handle = try f.closed(); configureTry(handle); f.try_complete = true;
        handle.stream.virtuals.do_write = writeProbe;
        const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
        const expression = try std.fmt.allocPrint(std.testing.allocator, "'x'.repeat({d})", .{case[1]});
        defer std.testing.allocator.free(expression);
        const value = try f.base.value(expression); defer f.base.engine.freeValue(value);
        _ = try f.write(wrapper, value, case[0]);
        try std.testing.expectEqual(@as(usize, if (case[2]) 1 else 0), f.try_calls);
        try std.testing.expectEqual(@as(usize, if (case[2]) 0 else 1), f.allocation_count);
        if (!case[2]) try std.testing.expectEqual(@as(usize, case[1] *
            (if (case[0] == .utf8) 3 else 1)), f.allocation_lengths[0]);
        try expectResult(&f, case[1], false);
    }
}

test "native Stream string write long UTF8 retains original Size then StorageSize capacity" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); configureTry(handle); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("'x'.repeat(65536)"); defer f.base.engine.freeValue(value);
    _ = try f.write(wrapper, value, .utf8);
    try std.testing.expectEqual(@as(usize, 0), f.try_calls);
    try std.testing.expectEqual(@as(usize, 196608), f.allocation_lengths[0]);
    try std.testing.expectEqual(@as(usize, 65536), f.write_length);
    try std.testing.expectEqual(@as(u64, 65536), handle.stream.resource.bytes_written);
    try expectResult(&f, 65536, false);
}

test "native Stream string write empty nontry input still uses zero backing and a real native request" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("''"); defer f.base.engine.freeValue(value);
    _ = try f.write(wrapper, value, .utf8);
    try std.testing.expectEqual(@as(usize, 1), f.allocation_count);
    try std.testing.expectEqual(@as(usize, 0), f.allocation_lengths[0]);
    try std.testing.expectEqual(@as(usize, 1), f.write_calls);
    try std.testing.expectEqual(@as(u32, 52), f.write_provider);
    try std.testing.expectEqual(@as(usize, 0), f.write_length);
    try expectResult(&f, 0, false); try f.retired(wrapper);
}

test "native Stream string write nonIPC object handle does not disable direct try or select handle Set" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); configureTry(handle); f.try_complete = true;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    try f.base.evaluate("Object.defineProperty(stringWriteRequest,'handle',{set(){throw stringWriteReason;}})");
    const value = try f.base.value("'abc'"); defer f.base.engine.freeValue(value);
    const send = try f.base.value("({})"); defer f.base.engine.freeValue(send);
    try std.testing.expectEqual(@as(c_int, 0), try f.writeWithHandle(wrapper, value, send, .ascii));
    try std.testing.expectEqual(@as(usize, 1), f.try_calls);
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
    try expectResult(&f, 3, false);
}

test "native Stream string write failed error Set after partial native error preserves prefix result and reason" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); configureTry(handle); f.try_consumed = 2;
    handle.stream.virtuals.do_write = writeProbe;
    handle.stream.virtuals.error_string = errorString;
    handle.stream.virtuals.clear_error = clearError; f.message = true;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    try f.base.evaluate("Object.defineProperty(stringWriteRequest,'error',{set(){throw stringWriteReason;}})");
    const value = try f.base.value("'A\\ud83d\\ude00B'"); defer f.base.engine.freeValue(value);
    f.base.env().uidField(.default_trigger).* = 137;
    try std.testing.expectError(error.JavaScriptException, f.write(wrapper, value, .utf8));
    try f.sameReason();
    try std.testing.expectEqual(@as(c_int, uv.UV_EBUSY), f.last_status);
    try std.testing.expectEqual(@as(u64, 6), handle.stream.resource.bytes_written);
    try std.testing.expectEqual(@as(f64, 137), f.base.env().uidField(.default_trigger).*);
    try std.testing.expect(f.message and f.error_clears == 0);
    try expectResult(&f, 2, false); try f.retired(wrapper);
}

test "native Stream string write ordinary init hook throw still transfers accepted async backing" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    try f.base.installInitRecorder();
    try f.base.evaluate("ownerInitHook=function(){throw stringWriteReason;}");
    const hook = try f.base.global("ownerInitHook"); defer f.base.engine.freeValue(hook);
    try f.base.env().installHooks(.{ .init = hook, .before = hook, .after = hook,
        .destroy = hook, .promise_resolve = hook }, f.base.binding_target.?);
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const value = try f.base.value("'\\u00e9'"); defer f.base.engine.freeValue(value);
    f.base.env().uidField(.default_trigger).* = 139;
    try std.testing.expectError(error.JavaScriptException, f.write(wrapper, value, .utf8));
    try f.sameReason();
    try std.testing.expectEqual(@as(c_int, 0), f.last_status);
    try std.testing.expectEqual(@as(f64, 139), f.base.env().uidField(.default_trigger).*);
    const request = f.pending_request.?;
    try std.testing.expect(request.backing_store != null);
    const bytes = c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?);
    try std.testing.expectEqualSlices(u8, &.{0xc3,0xa9}, bytes[0..2]);
    try expectResult(&f, 2, true);
    try f.complete(0); try f.retired(wrapper);
}

test "native Stream string write all new JSMethod entries preserve absent and dead receiver guards" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); _ = try f.closed();
    const absent = try f.base.value("({})"); defer f.base.engine.freeValue(absent);
    inline for (.{ dispatch.Method.write_ascii_string, .write_latin1_string,
        .write_utf8_string, .write_ucs2_string }) |method|
    {
        const missing = try f.publicCall(absent, method, &.{});
        defer f.base.engine.freeValue(missing);
        try std.testing.expect(c.JS_IsUndefined(missing));
        const dead = try f.publicCall(f.base.primary_wrapper.?, method, &.{});
        defer f.base.engine.freeValue(dead);
        try expectStatus(f.base.engine, dead, uv.UV_EINVAL);
    }
    try std.testing.expectEqual(@as(usize, 0), f.allocation_count);
}

test "native Stream string write flattens an actual VM rope before borrowing or UTF8 encoding" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.closed(); handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const rope = try f.base.value("'a'.repeat(1024)+'\\u00e9'.repeat(1024)");
    defer f.base.engine.freeValue(rope);
    try std.testing.expectEqual(@as(c_int, c.JS_TAG_STRING_ROPE), c.JS_VALUE_GET_TAG(rope));
    var view: c.JSPiStringView = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiBorrowFlatStringView(rope, &view));
    try std.testing.expect(view.data8 == null and view.data16 == null and view.length == 0);
    try std.testing.expect(!c.JS_HasException(f.base.engine.context));
    try std.testing.expectEqual(@as(c_int, 0), try f.write(wrapper, rope, .utf8));
    const request = f.pending_request.?;
    const bytes = c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?);
    try std.testing.expectEqual(@as(usize, 6144),
        c.JS_PiArrayBufferBackingStoreByteLength(&request.backing_store.?));
    for (bytes[0..1024]) |byte| try std.testing.expectEqual(@as(u8, 0x61), byte);
    for (0..1024) |position| {
        try std.testing.expectEqual(@as(u8, 0xc3), bytes[1024 + position * 2]);
        try std.testing.expectEqual(@as(u8, 0xa9), bytes[1024 + position * 2 + 1]);
    }
    try std.testing.expectEqual(@as(usize, 3072), f.write_length);
    try expectResult(&f, 3072, true);
    try f.complete(0); try f.retired(wrapper);
}

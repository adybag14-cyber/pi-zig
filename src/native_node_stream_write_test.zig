//! Focused controls for the retained Node24 StreamBase write path.
//! No compiler, metadata query, native runtime, or Node capture was run here.
const std = @import("std");
const support = @import("native_node_file_handle_owner_test_support.zig");
const a = support.a;
const c = a.c;
const templates = support.templates;
const writes = @import("extensions/native_node_stream_write.zig");
const requests = @import("extensions/native_node_stream_request.zig");
const streams = @import("extensions/native_node_stream_base.zig");
const resources = @import("extensions/native_node_stream_resource.zig");
const dispatch = @import("extensions/native_node_stream_js_dispatch.zig");
const custom = @import("extensions/native_node_custom_buffer_listener.zig");
const managed = @import("extensions/native_node_managed_buffers.zig");
const uv = resources.uv;

const Fixture = struct {
    base: support.Fixture = undefined,
    ready: bool = false,
    error_key: ?c.JSValue = null,
    complete_key: ?c.JSValue = null,
    observed_request: ?c.JSValue = null,
    result: ?writes.Result = null,
    last_status: c_int = -99999,
    write_status: c_int = uv.UV_EIO,
    write_calls: usize = 0,
    write_count: usize = 0,
    write_first_length: usize = 0,
    write_provider: u32 = 0,
    write_trigger: f64 = -1,
    write_send: ?*uv.uv_stream_t = null,
    try_calls: usize = 0,
    try_status: c_int = 0,
    try_drop: usize = 0,
    try_counter: u64 = 0,
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
        try self.base.engine.bindFunction("writeNativeState", nativeState, 1);
        try self.base.evaluate("globalThis.writeCalls=[];globalThis.writeReason={};");
    }
    fn create(self: *Fixture, fd: c_int) !*support.Handle {
        const handle = try self.base.create(fd, null, null);
        // Deliberately supply only write bindings. Shared completion must not
        // accidentally depend on an unrelated Shutdown template being bound.
        const bindings: streams.WriteBindings = .{ .request = .{
            .template_owner = self.base.template_owner.?,
            .error_string = self.error_key.?, .oncomplete_string = self.complete_key.?,
        }, .handle_string = handle.handle_string };
        handle.stream.operations.write = bindings;
        handle.stream_operations.write = bindings;
        try self.base.expose("writeHandle", self.base.primary_wrapper.?);
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
                return a.duplicate(s.engine,
                    try templates.newWriteWrapInstance(s, f.base.template_owner.?));
            }
        }.body, .{self});
    }
    fn publish(self: *Fixture, wrapper: c.JSValue) !void {
        try self.base.expose("writeRequest", wrapper);
        try self.base.evaluate(
            "writeRequest.oncomplete=function(status,stream,error){" ++
            "writeCalls.push([this,status,stream,error,writeNativeState(this)]);};");
    }
    fn run(self: *Fixture, buffers: []uv.uv_buf_t, input: ?c.JSValue,
        skip: bool, send: ?*uv.uv_stream_t) !void
    {
        std.debug.assert(self.result == null);
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, b: []uv.uv_buf_t,
                object: ?c.JSValue, skip_try: bool, send_handle: ?*uv.uv_stream_t) !c.JSValue
            {
                f.result = try writes.run(s, &(try f.base.handle()).stream,
                    b, send_handle, object, skip_try);
                return c.pi_js_undefined();
            }
        }.body, .{self, buffers, input, skip, send});
        self.base.engine.freeValue(ignored);
    }
    fn release(self: *Fixture) !void {
        if (self.result == null) return;
        defer self.result = null;
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                try f.result.?.release(s);
                return c.pi_js_undefined();
            }
        }.body, .{self});
        self.base.engine.freeValue(ignored);
    }
    fn buffer(self: *Fixture, wrapper: c.JSValue, value: c.JSValue) !c_int {
        self.last_status = -99999;
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, w: c.JSValue, v: c.JSValue) !c.JSValue {
                f.last_status = try writes.writeBuffer(s, &(try f.base.handle()).stream, &.{w, v});
                return c.pi_js_undefined();
            }
        }.body, .{self, wrapper, value});
        self.base.engine.freeValue(ignored);
        return self.last_status;
    }
    fn publicCall(self: *Fixture, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        return a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, r: c.JSValue, argv: []const c.JSValue) !c.JSValue {
                return dispatch.jsMethod(s, f.base.registry(), r, .write_buffer, argv);
            }
        }.body, .{self, receiver, args});
    }
    fn retired(self: *Fixture, wrapper: c.JSValue) !void {
        try std.testing.expect(self.base.registry().unwrap(wrapper) == null);
        try std.testing.expect(requests.Request.fromObject(self.base.registry(), wrapper) == null);
        try std.testing.expectEqual(@as(c_int, 0), self.base.env().requests.waiting);
    }
    fn sameReason(self: *Fixture) !void {
        const reason = try self.base.takeCaught();
        defer self.base.engine.freeValue(reason);
        const expected = try self.base.global("writeReason");
        defer self.base.engine.freeValue(expected);
        try std.testing.expect(c.JS_IsStrictEqual(self.base.engine.context, reason, expected));
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
    }
    fn installError(self: *Fixture) !void {
        const handle = try self.base.handle();
        handle.stream.virtuals.error_string = errorString;
        handle.stream.virtuals.clear_error = clearError;
        self.message = true;
    }
    fn deinit(self: *Fixture) void {
        if (!self.ready) return;
        self.release() catch @panic("write result pointer retirement failed");
        self.base.stopIo();
        for ([_]*?c.JSValue{ &self.error_key, &self.complete_key, &self.observed_request }) |slot| {
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
fn writeProbe(stream: *streams.Base, _: *a.Scope, request: *requests.Write,
    buffers: []uv.uv_buf_t, send: ?*uv.uv_stream_t) anyerror!c_int
{
    const f = fixture(stream.resource.engine);
    f.write_calls += 1;
    f.write_count = buffers.len;
    f.write_first_length = if (buffers.len == 0) 0 else buffers[0].len;
    f.write_provider = request.request.asyncWrap().provider;
    f.write_trigger = stream.environment.uidField(.default_trigger).*;
    f.write_send = send;
    if (f.observed_request) |old| stream.resource.engine.freeValue(old);
    f.observed_request = a.duplicate(stream.resource.engine, request.request.object().?);
    return f.write_status;
}
fn hasTry(_: *const streams.Base) bool { return true; }
fn tryProbe(stream: *streams.Base, _: *a.Scope, buffers: *[]uv.uv_buf_t) anyerror!c_int {
    const f = fixture(stream.resource.engine);
    f.try_calls += 1;
    f.try_counter = stream.resource.bytes_written;
    buffers.* = buffers.*[f.try_drop..];
    return f.try_status;
}
fn errorString(stream: *streams.Base) ?[*:0]const u8 {
    return if (fixture(stream.resource.engine).message) "native-\x80\xff" else null;
}
fn clearError(stream: *streams.Base) void {
    const f = fixture(stream.resource.engine);
    f.message = false;
    f.error_clears += 1;
}
fn nativeState(context: ?*c.JSContext, _: c.JSValue, argc: c_int,
    argv: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = support.em.Engine.fromContext(context.?);
    const registry = fixture(engine).base.registry();
    const object = if (argc > 0) argv[0] else c.pi_js_undefined();
    const request = requests.Request.fromObject(registry, object) orelse
        return c.JS_NewInt32(context, 0);
    return c.JS_NewInt32(context, @intFromBool(
        registry.unwrap(object) == request.asyncWrap() and !request.asyncWrap().detached));
}
fn smallBuffers(bytes: *[5]u8) [2]uv.uv_buf_t {
    return .{ uv.uv_buf_init(@ptrCast(bytes.ptr), 2),
        uv.uv_buf_init(@ptrCast(bytes.ptr + 2), 3) };
}

test "native Stream write actual WriteWrap template has independent empty slots and no Shutdown fields" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const constructor = try templates.constructor(f.base.engine, f.base.template_owner.?, .writewrap);
    defer f.base.engine.freeValue(constructor);
    try f.base.expose("ActualWriteWrap", constructor);
    try f.base.evaluate("globalThis.writeRequest=new ActualWriteWrap();");
    try f.base.expect("Object.keys(writeRequest).length===0 && " ++
        "Object.getPrototypeOf(writeRequest)===ActualWriteWrap.prototype && " ++
        "typeof writeRequest.getAsyncId==='function' && " ++
        "!Object.hasOwn(writeRequest,'oncomplete') && !Object.hasOwn(writeRequest,'handle')");
    const wrapper = try f.base.global("writeRequest"); defer f.base.engine.freeValue(wrapper);
    try f.retired(wrapper);
    const shutdown = try templates.newInstance(f.base.engine, f.base.template_owner.?, .shutdownwrap);
    defer f.base.engine.freeValue(shutdown);
    try f.base.expose("otherRequest", shutdown);
    try f.base.expect("Object.keys(otherRequest).join(',')==='oncomplete,callback,handle'");
}

test "native Stream write FileHandle WriteBuffer preserves ENOSYS attempted bytes live descriptor and trigger" {
    var file: support.File = .{}; defer file.deinit(); try file.init();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const handle = try f.create(file.take());
    const fd = handle.getFD();
    const native_refs = handle.wrap.native_references;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    const value = try f.base.value("new Uint8Array([0,1,2,3,4]).subarray(1,4)");
    defer f.base.engine.freeValue(value);
    try f.base.installInitRecorder();
    try f.base.expose("writeHandleId", c.JS_NewFloat64(f.base.engine.context, handle.wrap.async_id));
    f.base.env().uidField(.default_trigger).* = 91;
    const result = try f.publicCall(f.base.primary_wrapper.?, &.{wrapper, value});
    defer f.base.engine.freeValue(result);
    var status: i32 = 0; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.base.engine.context, &status, result));
    try std.testing.expectEqual(@as(i32, uv.UV_ENOSYS), status);
    try std.testing.expectEqual(@as(u64, 3), handle.stream.resource.bytes_written);
    try std.testing.expectEqual(@as(i32, 3), f.base.env().streamBaseField(.bytes_written).*);
    try std.testing.expectEqual(@as(i32, 0), f.base.env().streamBaseField(.last_write_was_async).*);
    try std.testing.expectEqual(@as(f64, 91), f.base.env().uidField(.default_trigger).*);
    try std.testing.expectEqual(native_refs, handle.wrap.native_references);
    try std.testing.expect(handle.isAlive() and support.File.status(fd) == 0);
    try f.base.expect("ownerInitEvents.length===1 && ownerInitEvents[0][0]==='WRITEWRAP' && ownerInitEvents[0][2]===writeHandleId");
    try f.retired(wrapper);
    file.descriptor = try f.base.releaseDescriptor();
}

test "native Stream write immediate failure clears request before returned native pointer retires" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); _ = try f.closed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, wrapper, false, null);
    try std.testing.expect(!f.result.?.is_async and f.result.?.wrap == null);
    try std.testing.expectEqual(@as(c_int, uv.UV_ENOSYS), f.result.?.err);
    try std.testing.expectEqual(@as(usize, 5), f.result.?.bytes);
    const state = f.result.?.wrap_obj.?;
    try std.testing.expectEqual(@as(usize, 1), state.native_references);
    try std.testing.expect(state.detached and f.base.registry().unwrap(wrapper) == state);
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == null);
    try f.release(); try f.retired(wrapper);
}

test "native Stream write async result keeps native request through live forwarded completion and Dispose" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    var listener: resources.Listener = .{}; handle.stream.resource.push(&listener);
    defer listener.deinit();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, wrapper, false, null);
    try std.testing.expect(f.result.?.is_async and f.result.?.wrap != null);
    try std.testing.expectEqual(@as(u32, 52), f.write_provider);
    const state = f.result.?.wrap_obj.?;
    try f.result.?.wrap.?.request.done(0, null);
    try f.base.expect("writeCalls.length===1 && writeCalls[0][0]===writeRequest && " ++
        "writeCalls[0][1]===0 && writeCalls[0][2]===writeHandle && writeCalls[0][3]===undefined && writeCalls[0][4]===1");
    try std.testing.expect(requests.Request.fromObject(f.base.registry(), wrapper) == null);
    try std.testing.expect(state.detached and f.base.registry().unwrap(wrapper) == state);
    try f.release(); try f.retired(wrapper);
}

test "native Stream write complete try-write bypasses absent request template and keeps original total" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.operations.write = null; handle.stream.virtuals.do_write = null;
    handle.stream.virtuals.has_do_try_write = hasTry; handle.stream.virtuals.do_try_write = tryProbe;
    f.try_drop = 2;
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, null, false, null);
    try std.testing.expectEqual(@as(usize, 1), f.try_calls);
    try std.testing.expectEqual(@as(u64, 5), f.try_counter);
    try std.testing.expect(!f.result.?.is_async and f.result.?.err == 0 and f.result.?.bytes == 5);
    try std.testing.expect(f.result.?.wrap == null and f.result.?.wrap_obj == null);
    try std.testing.expectEqual(@as(usize, 0), f.write_calls);
}

test "native Stream write partial try-write forwards remaining vectors while counting attempted total" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.has_do_try_write = hasTry; handle.stream.virtuals.do_try_write = tryProbe;
    handle.stream.virtuals.do_write = writeProbe; f.try_drop = 1;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, wrapper, false, null);
    try std.testing.expectEqual(@as(usize, 1), f.write_count);
    try std.testing.expectEqual(@as(usize, 3), f.write_first_length);
    try std.testing.expectEqual(@as(usize, 5), f.result.?.bytes);
    try std.testing.expectEqual(@as(u64, 5), f.try_counter);
    try std.testing.expectEqual(@as(u64, 5), handle.stream.resource.bytes_written);
    try std.testing.expectEqual(handle.wrap.async_id, f.write_trigger);
}

test "native Stream write try failure has no request and explicit skip bypasses try-write" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.has_do_try_write = hasTry; handle.stream.virtuals.do_try_write = tryProbe;
    handle.stream.virtuals.do_write = writeProbe; f.try_status = uv.UV_EPIPE;
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, null, false, null);
    try std.testing.expectEqual(@as(c_int, uv.UV_EPIPE), f.result.?.err);
    try std.testing.expect(f.result.?.wrap_obj == null and f.result.?.bytes == 5);
    try std.testing.expectEqual(@as(usize, 0), f.write_calls);
    try f.release();
    try f.run(&buffers, null, true, null);
    try std.testing.expectEqual(@as(usize, 1), f.try_calls);
    try std.testing.expectEqual(@as(usize, 1), f.write_calls);
    try std.testing.expectEqual(@as(u64, 10), handle.stream.resource.bytes_written);
}

test "native Stream write nonnull borrowed send handle bypasses try-write and preserves pointer identity" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.has_do_try_write = hasTry; handle.stream.virtuals.do_try_write = tryProbe;
    handle.stream.virtuals.do_write = writeProbe;
    // No libuv operation dereferences this opaque input in the selected probe;
    // this control observes the native branch/identity, not IPC handle creation.
    var borrowed: uv.uv_stream_t = std.mem.zeroes(uv.uv_stream_t);
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, null, false, &borrowed);
    try std.testing.expectEqual(@as(usize, 0), f.try_calls);
    try std.testing.expectEqual(@as(usize, 1), f.write_calls);
    try std.testing.expect(f.write_send == &borrowed);
}

test "native Stream write invalid buffer types throw intrinsic TypeError without updating result slots" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    f.base.env().streamBaseField(.bytes_written).* = 73;
    f.base.env().streamBaseField(.last_write_was_async).* = 74;
    for ([_][]const u8{"undefined", "null", "{}", "new Int8Array(2)", "new Uint8ClampedArray(2)",
        "new DataView(new ArrayBuffer(2))", "new ArrayBuffer(2)", "new Proxy(new Uint8Array(2),{})"}) |input|
    {
        const value = try f.base.value(input); defer f.base.engine.freeValue(value);
        try std.testing.expectError(error.JavaScriptException, f.buffer(wrapper, value));
        try std.testing.expectEqual(@as(c_int, 0), f.last_status);
        const reason = try f.base.takeCaught(); defer f.base.engine.freeValue(reason);
        try f.base.expose("writeTypeError", reason);
        try f.base.expect("writeTypeError instanceof TypeError && writeTypeError.code==='ERR_INVALID_ARG_TYPE' && " ++
            "writeTypeError.message==='Second argument must be a buffer'");
        try std.testing.expectEqual(@as(i32, 73), f.base.env().streamBaseField(.bytes_written).*);
        try std.testing.expectEqual(@as(i32, 74), f.base.env().streamBaseField(.last_write_was_async).*);
        try std.testing.expectEqual(@as(u64, 0), handle.stream.resource.bytes_written);
        try f.retired(wrapper);
    }
}

test "native Stream write invalid type uses intrinsic error and original observable code Set" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); _ = try f.closed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    try f.base.evaluate("globalThis.OriginalTypeError=TypeError;globalThis.codeSet=[];" ++
        "Object.defineProperty(OriginalTypeError.prototype,'code',{configurable:true,set(v){codeSet.push([this,v]);}});" ++
        "globalThis.TypeError=function(){throw writeReason;};");
    try std.testing.expectError(error.JavaScriptException, f.buffer(wrapper, c.pi_js_undefined()));
    const reason = try f.base.takeCaught(); defer f.base.engine.freeValue(reason);
    try f.base.expose("writeTypeError", reason);
    try f.base.expect("writeTypeError instanceof OriginalTypeError && codeSet.length===1 && " ++
        "codeSet[0][0]===writeTypeError && codeSet[0][1]==='ERR_INVALID_ARG_TYPE' && !Object.hasOwn(writeTypeError,'code')");
}

test "native Stream write error setter throw returns EBUSY zero result and preserves reason and uncleared error" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    try f.installError(); f.base.env().uidField(.default_trigger).* = 113;
    try f.base.evaluate("Object.defineProperty(writeRequest,'error',{set(v){throw writeReason;}})");
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try std.testing.expectError(error.JavaScriptException, f.run(&buffers, wrapper, false, null));
    try f.sameReason();
    try std.testing.expect(f.result != null and f.result.?.err == uv.UV_EBUSY and f.result.?.bytes == 0);
    try std.testing.expect(f.result.?.wrap == null and f.result.?.wrap_obj == null and !f.result.?.is_async);
    try std.testing.expect(f.message and f.error_clears == 0);
    try std.testing.expectEqual(@as(u64, 5), handle.stream.resource.bytes_written);
    try std.testing.expectEqual(@as(f64, 113), f.base.env().uidField(.default_trigger).*);
    try f.retired(wrapper);
}

test "native Stream write false error Set permits continuation and clears the original error" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); _ = try f.closed();
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    try f.installError();
    try f.base.evaluate("Object.defineProperty(writeRequest,'error',{value:'fixed',writable:false})");
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, wrapper, false, null);
    try std.testing.expectEqual(@as(c_int, uv.UV_ENOSYS), f.result.?.err);
    try std.testing.expectEqual(@as(usize, 5), f.result.?.bytes);
    try std.testing.expect(!f.message and f.error_clears == 1);
    try f.base.expect("writeRequest.error==='fixed'");
}

test "native Stream write ordinary init-hook throw preserves completed WriteWrap and DoWrite result" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe;
    try f.base.installInitRecorder();
    try f.base.evaluate("ownerInitHook=function(id,type,trigger,resource){throw writeReason;}");
    const hook = try f.base.global("ownerInitHook"); defer f.base.engine.freeValue(hook);
    try f.base.env().installHooks(.{ .init = hook, .before = hook, .after = hook,
        .destroy = hook, .promise_resolve = hook }, f.base.binding_target.?);
    f.base.env().uidField(.default_trigger).* = 117;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try std.testing.expectError(error.JavaScriptException, f.run(&buffers, wrapper, false, null));
    try f.sameReason();
    try std.testing.expectEqual(@as(usize, 1), f.write_calls);
    try std.testing.expect(f.result != null and f.result.?.err == uv.UV_EIO and f.result.?.bytes == 5);
    try std.testing.expectEqual(@as(f64, 117), f.base.env().uidField(.default_trigger).*);
    try f.release(); try f.retired(wrapper);
}

test "native Stream write completion throw still disposes and custom listener uses shared actual reporter" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    const view = try f.base.value("new Uint8Array(4)"); defer f.base.engine.freeValue(view);
    try std.testing.expectEqual(@as(c_int, 0), custom.useUserBuffer(&handle.stream, view));
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    try f.base.evaluate("writeRequest.oncomplete=function(){writeCalls.push(writeNativeState(this));throw writeReason;}");
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, wrapper, false, null);
    const state = f.result.?.wrap_obj.?;
    try std.testing.expectError(error.JavaScriptException, f.result.?.wrap.?.request.done(uv.UV_EIO, null));
    try f.sameReason();
    try f.base.expect("writeCalls.length===1 && writeCalls[0]===1");
    try std.testing.expect(state.detached and requests.Request.fromObject(f.base.registry(), wrapper) == null);
    try f.release(); try f.retired(wrapper);
}

test "native Stream write absent native request uses actual instance template and completion suppresses disabled JS" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, null, false, null);
    const observed = f.observed_request.?;
    try std.testing.expectEqual(f.base.registry().classId(.writewrap), c.JS_GetClassID(observed));
    try f.publish(observed);
    f.base.env().can_call_into_js = false;
    try f.result.?.wrap.?.request.done(0, null);
    f.base.env().can_call_into_js = true;
    try f.base.expect("writeCalls.length===0");
    try f.release(); try f.retired(observed);
}

test "native Stream write unsigned attempted counter wraps and shared Int32 result truncates exactly" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe;
    handle.stream.resource.bytes_written = std.math.maxInt(u64) - 1;
    var byte: u8 = 0;
    // This integer-boundary control performs no data access or OS write.
    var buffers: [2]uv.uv_buf_t = .{
        .{ .base = @ptrCast(&byte), .len = std.math.maxInt(u32) },
        .{ .base = @ptrCast(&byte), .len = 2 },
    };
    try f.run(&buffers, null, false, null);
    try std.testing.expectEqual(@as(usize, std.math.maxInt(u32)) + 2, f.result.?.bytes);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u32)), handle.stream.resource.bytes_written);
    writes.setResult(f.base.env(), &f.result.?);
    try std.testing.expectEqual(@as(i32, 1), f.base.env().streamBaseField(.bytes_written).*);
    try std.testing.expectEqual(@as(i32, 0), f.base.env().streamBaseField(.last_write_was_async).*);
}

test "native Stream write backing token transfers once and survives Dispose until native pointer retirement" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper);
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try f.run(&buffers, wrapper, false, null);
    const request = f.result.?.wrap.?;
    var empty: managed.Token = std.mem.zeroes(managed.Token);
    request.setBackingStore(&empty);
    try std.testing.expect(request.backing_store == null);
    var token = handle.stream.operations.allocation.new_backing_store(
        handle.stream.operations.allocation.raw, f.base.env(), 4, .zero_initialized);
    defer c.JS_PiReleaseArrayBufferBackingStore(&token);
    const pointer = c.JS_PiArrayBufferBackingStoreData(&token);
    pointer[0] = 37;
    request.setBackingStore(&token);
    try std.testing.expect(c.JS_PiArrayBufferBackingStoreData(&token) == null);
    try request.request.dispose();
    try std.testing.expect(request.backing_store != null);
    try std.testing.expect(c.JS_PiArrayBufferBackingStoreData(&request.backing_store.?) == pointer);
    try std.testing.expectEqual(@as(u8, 37), pointer[0]);
    try f.release(); try f.retired(wrapper);
}

test "native Stream write JSMethod absent and closed receiver guards run before buffer argument CHECK" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    const plain = try f.base.value("({})"); defer f.base.engine.freeValue(plain);
    const absent = try f.publicCall(plain, &.{}); defer f.base.engine.freeValue(absent);
    try std.testing.expect(c.JS_IsUndefined(absent));
    const dead = try f.publicCall(f.base.primary_wrapper.?, &.{}); defer f.base.engine.freeValue(dead);
    var status: i32 = 0; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.base.engine.context, &status, dead));
    try std.testing.expectEqual(@as(i32, uv.UV_EINVAL), status);
    try std.testing.expectEqual(@as(u64, 0), handle.stream.resource.bytes_written);
}

test "native Stream write WriteBuffer publishes async result before releasing its local native pointer" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    const view = try f.base.value("new Uint8Array(4)"); defer f.base.engine.freeValue(view);
    try std.testing.expectEqual(@as(c_int, 0), try f.buffer(wrapper, view));
    try std.testing.expectEqual(@as(i32, 4), f.base.env().streamBaseField(.bytes_written).*);
    try std.testing.expectEqual(@as(i32, 1), f.base.env().streamBaseField(.last_write_was_async).*);
    const request = requests.Write.fromObject(f.base.registry(), wrapper).?;
    try std.testing.expectEqual(@as(usize, 0), request.request.asyncWrap().native_references);
    try request.request.done(0, null);
    try f.base.expect("writeCalls.length===1 && writeCalls[0][1]===0 && writeCalls[0][4]===1");
    try f.retired(wrapper);
}

test "native Stream write accepted async request survives later error Set failure until its real completion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit(); const handle = try f.closed();
    handle.stream.virtuals.do_write = writeProbe; f.write_status = 0;
    const wrapper = try f.request(); defer f.base.engine.freeValue(wrapper); try f.publish(wrapper);
    try f.installError();
    try f.base.evaluate("Object.defineProperty(writeRequest,'error',{set(v){throw writeReason;}})");
    var bytes: [5]u8 = .{1,2,3,4,5}; var buffers = smallBuffers(&bytes);
    try std.testing.expectError(error.JavaScriptException, f.run(&buffers, wrapper, false, null));
    try f.sameReason();
    try std.testing.expect(f.result.?.err == uv.UV_EBUSY and f.result.?.bytes == 0 and
        f.result.?.wrap == null and f.result.?.wrap_obj == null);
    const request = requests.Write.fromObject(f.base.registry(), wrapper).?;
    try std.testing.expect(!request.request.asyncWrap().detached);
    try std.testing.expectEqual(@as(usize, 0), request.request.asyncWrap().native_references);
    try std.testing.expect(f.message and f.error_clears == 0);
    try request.request.done(0, null);
    try f.base.expect("writeCalls.length===1 && writeCalls[0][1]===0 && writeCalls[0][3]==='native-\\x80\\xff'");
    try std.testing.expect(!f.message and f.error_clears == 1);
    try f.retired(wrapper);
}

//! Focused source controls over the frozen concrete FileHandle fixture.
//! The callbacks below observe real native state. They are not production
//! trace, allocation, bootstrap or hook-policy implementations.
const std = @import("std");
pub const base_support = @import("native_node_file_handle_owner_test_support.zig");
pub const a = base_support.a;
pub const c = a.c;
pub const native = base_support.native;
pub const Handle = base_support.Handle;
pub const requests = @import("extensions/native_node_stream_request.zig");
pub const shutdown = @import("extensions/native_node_stream_shutdown.zig");
pub const streams = @import("extensions/native_node_stream_base.zig");
pub const uv = base_support.uv;
const templates = base_support.templates;

pub const Fixture = struct {
    base: base_support.Fixture = undefined,
    base_ready: bool = false,
    error_key: ?c.JSValue = null,
    oncomplete_key: ?c.JSValue = null,
    observed_request: ?c.JSValue = null,
    begins: usize = 0,
    ends: usize = 0,
    begin_provider: u32 = 0,
    begin_unsubmitted: bool = false,
    begin_stream_exact: bool = false,
    begin_handle_references: usize = 0,
    end_closing: bool = false,
    end_uncounted: bool = false,
    end_accepted_uncleaned: bool = false,
    end_native_references: usize = 0,
    end_result: c_int = 0,
    callback_cleaned: bool = false,
    callback_uncounted: bool = false,
    last_status: c_int = -99999,
    message_available: bool = false,
    error_reads: usize = 0,
    error_clears: usize = 0,

    pub fn init(self: *Fixture) !void {
        self.* = .{};
        try self.base.init();
        self.base_ready = true;
        errdefer self.deinit();
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                f.error_key = a.duplicate(s.engine, try s.text("error"));
                f.oncomplete_key = a.duplicate(s.engine, try s.text("oncomplete"));
                return c.pi_js_undefined();
            }
        }.body, .{self});
        self.base.engine.freeValue(ignored);
        try self.base.engine.bindFunction("observeShutdownNativeFlags", nativeFlags, 1);
        try self.base.evaluate("globalThis.shutdownCalls=[];globalThis.shutdownReason={};");
    }
    pub fn create(self: *Fixture, descriptor: c_int) !*Handle {
        const handle = try self.base.create(descriptor, null, null);
        const bindings: streams.ShutdownBindings = .{
            .template_owner = self.base.template_owner.?,
            .error_string = self.error_key.?, .oncomplete_string = self.oncomplete_key.?,
        };
        handle.stream.operations.shutdown = bindings;
        handle.stream_operations.shutdown = bindings;
        handle.close_trace = .{ .raw = self, .begin_sync = beginSync,
            .end_sync = endSync, .begin_async = beginAsync, .end_async = endAsync };
        try self.base.expose("shutdownHandle", self.base.primary_wrapper.?);
        return handle;
    }
    pub fn createClosed(self: *Fixture) !*Handle {
        const handle = try self.create(-1);
        // Use the real release/AfterClose operation to produce closed_, rather
        // than patching constructor fields or introducing a pretend descriptor.
        try std.testing.expectEqual(@as(c_int, -1), try self.base.releaseDescriptor());
        return handle;
    }
    pub fn request(self: *Fixture) !c.JSValue {
        return a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture) !c.JSValue {
                return a.duplicate(s.engine, try templates.newShutdownWrapInstance(
                    s, f.base.template_owner.?));
            }
        }.body, .{self});
    }
    pub fn publishRequest(self: *Fixture, request_value: c.JSValue) !void {
        try self.base.expose("shutdownRequest", request_value);
        // This is the genuine JS caller's handle property. The native
        // FileHandleCloseWrap itself deliberately owns no handle Global.
        try self.base.evaluate(
            "shutdownRequest.handle=shutdownHandle;" ++
            "shutdownRequest.oncomplete=function(status,stream,error){" ++
            "shutdownCalls.push([this,status,stream,error,observeShutdownNativeFlags(this)]);};");
    }
    pub fn run(self: *Fixture, request_value: ?c.JSValue) !c_int {
        self.last_status = -99999;
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, request_input: ?c.JSValue) !c.JSValue {
                f.last_status = try (try f.base.handle()).shutdown(s, request_input);
                return c.pi_js_undefined();
            }
        }.body, .{self, request_value});
        self.base.engine.freeValue(ignored);
        return self.last_status;
    }
    pub fn simple(self: *Fixture, object: c.JSValue) !*requests.Shutdown {
        var selected: ?*requests.Shutdown = null;
        const ignored = try a.expression(self.base.engine, struct {
            fn body(s: *a.Scope, f: *Fixture, wrapper: c.JSValue,
                out: *?*requests.Shutdown) !c.JSValue
            {
                out.* = try shutdown.createDefault(
                    (try f.base.handle()).getStreamBase(), s, wrapper);
                // This is the test caller's actual BaseObjectPtr entitlement.
                // retainNative increments before its possible failing check.
                const state = out.*.?.request.asyncWrap();
                state.retainNative() catch |err| {
                    var completion = a.owned.Completion.initVoid(s.engine, err);
                    out.*.?.request.dispose() catch {};
                    state.releaseNative() catch {};
                    out.* = null;
                    try completion.finishVoid();
                    unreachable;
                };
                return c.pi_js_undefined();
            }
        }.body, .{self, object, &selected});
        self.base.engine.freeValue(ignored);
        return selected orelse error.ActualSimpleShutdownRequired;
    }
    pub fn expectRetired(self: *Fixture, object: c.JSValue) !void {
        try std.testing.expect(self.base.registry().unwrap(object) == null);
        try std.testing.expect(requests.Request.fromObject(self.base.registry(), object) == null);
        try std.testing.expectEqual(@as(c_int, 0), self.base.env().requests.waiting);
        try std.testing.expectEqual(@as(usize, 0), self.base.queueCount());
    }
    pub fn installMessage(self: *Fixture) !void {
        const handle = try self.base.handle();
        handle.stream.virtuals.error_string = errorString;
        handle.stream.virtuals.clear_error = clearError;
        self.message_available = true;
    }
    pub fn deinit(self: *Fixture) void {
        if (!self.base_ready) return;
        self.base.stopIo(); // drains every accepted callback while keys live
        for (.{ &self.observed_request, &self.error_key, &self.oncomplete_key }) |slot| {
            if (slot.*) |value| {
                slot.* = null;
                self.base.engine.freeValue(value);
            }
        }
        self.base.deinit();
        self.base_ready = false;
    }
};

fn fixture(engine: *base_support.em.Engine) *Fixture {
    const base: *base_support.Fixture = @ptrCast(@alignCast(engine.host_control_context.?));
    return @fieldParentPtr("base", base);
}
fn nativeFlags(context: ?*c.JSContext, _: c.JSValue,
    argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = base_support.em.Engine.fromContext(context.?);
    const f = fixture(engine);
    const handle = f.base.handle() catch unreachable;
    if (argc == 1 and f.ends != 0) if (f.observed_request) |observed| {
        if (c.JS_IsStrictEqual(engine.context, argv[0], observed)) {
            const state = f.base.registry().unwrap(observed) orelse unreachable;
            const request: *Handle.ShutdownReq = @fieldParentPtr("wrap", state);
            const info = uv.pi_uv_fs_request_info(request.actual.?);
            f.callback_cleaned = info.cleaned != 0;
            f.callback_uncounted = !request.entry.counted;
        }
    };
    return c.JS_NewInt32(engine.context,
        @as(c_int, @intFromBool(handle.read_state.closed)) +
        2 * @as(c_int, @intFromBool(handle.read_state.closing)));
}
fn beginSync(raw: ?*anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.base.sync_begins += 1;
}
fn endSync(raw: ?*anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    f.base.sync_ends += 1;
}
fn beginAsync(raw: ?*anyopaque, pointer: *anyopaque) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const request: *Handle.ShutdownReq = @ptrCast(@alignCast(pointer));
    f.begins += 1;
    f.begin_provider = request.wrap.provider;
    f.begin_unsubmitted = !request.entry.dispatched and !request.entry.counted;
    const handle = f.base.handle() catch unreachable;
    f.begin_stream_exact = request.shutdown.request.stream == &handle.stream;
    f.begin_handle_references = handle.wrap.native_references;
    // Preparation is not completion. Do not call completion-only info here.
    std.debug.assert(request.actual != null);
    if (f.observed_request) |previous| f.base.engine.freeValue(previous);
    f.observed_request = a.duplicate(f.base.engine, request.wrap.object().?);
}
fn endAsync(raw: ?*anyopaque, pointer: *anyopaque, result: c_int) void {
    const f: *Fixture = @ptrCast(@alignCast(raw.?));
    const request: *Handle.ShutdownReq = @ptrCast(@alignCast(pointer));
    const info = uv.pi_uv_fs_request_info(request.actual.?);
    f.ends += 1;
    f.end_result = result;
    f.end_closing = (f.base.handle() catch unreachable).read_state.closing;
    f.end_uncounted = !request.entry.counted and f.base.env().requests.waiting == 0;
    f.end_accepted_uncleaned = info.accepted != 0 and info.cleaned == 0;
    f.end_native_references = request.wrap.native_references;
}
fn errorString(stream: *streams.Base) ?[*:0]const u8 {
    const f = fixture(stream.environment.engine.?);
    f.error_reads += 1;
    return if (f.message_available) "native-\x80\xff" else null;
}
fn clearError(stream: *streams.Base) void {
    const f = fixture(stream.environment.engine.?);
    f.message_available = false;
    f.error_clears += 1;
}

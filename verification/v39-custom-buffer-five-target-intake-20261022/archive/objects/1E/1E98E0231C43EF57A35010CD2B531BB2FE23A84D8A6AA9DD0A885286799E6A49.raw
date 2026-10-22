//! Native node::fs::FileHandleReadWrap constructor and ReqWrap ownership.
//! The concrete FileHandle type supplies its actual AsyncWrap through
//! getAsyncWrap(). The pointer is borrowed, exactly as file_handle_ in Source.
//! This module neither constructs a template instance nor owns its read buffer:
//! the real FileHandle ReadStart caller supplies the selected FSReqCallback
//! InstanceTemplate object and retains the emitted span through EmitRead.
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const request_state = @import("native_node_request_state.zig");
const io = @import("native_node_fs_request_io.zig");
const c = a.c;
const uv = io.uv;
const Scope = a.Scope;

// The complete Node provider macro places FSREQCALLBACK at index 8. This is the
// actual provider of FileHandleReadWrap, distinct from FSREQPROMISE at index 9.
const fsreqcallback_provider: u32 = 8;

/// The type parameter expresses the original concrete borrowed FileHandle*
/// without imposing another native owner or a dynamic callback interface.
pub fn Type(comptime Handle: type) type {
    return struct {
        const ReadWrap = @This();

        wrap: native.State = undefined,
        entry: request_state.Entry = undefined,
        // These two members have the original declaration/ownership order.
        // buffer is assigned only by the real StreamResource EmitAlloc.
        file_handle: *Handle = undefined,
        buffer: uv.uv_buf_t = undefined,

        // Port allocation and partial-construction bookkeeping. The C owner
        // reserves the actual reusable uv_fs_t before the AsyncWrap init hook.
        actual: ?*uv.PiUvFsRequest = null,
        attached: bool = false,
        entry_initialized: bool = false,

        pub fn fromEntry(entry_value: *request_state.Entry) *ReadWrap {
            return @alignCast(@fieldParentPtr("entry", entry_value));
        }
        fn fromWrap(state: *native.State) *ReadWrap {
            return @alignCast(@fieldParentPtr("wrap", state));
        }
        fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {
            // Neither borrowed FileHandle* nor uv_buf_t is a JS graph edge.
        }
        fn retire(state: *native.State, _: *Scope) !void {
            const read_wrap = fromWrap(state);
            // FileHandleReadWrap's destructor is defaulted. In particular it
            // does not free the StreamResource payload or retain/release the
            // borrowed FileHandle/BindingData. ReqWrapBase then leaves its
            // actual Environment queue before the AsyncWrap base retires.
            if (read_wrap.entry_initialized) {
                read_wrap.entry_initialized = false;
                read_wrap.entry.deinit();
            }
        }
        fn destroy(state: *native.State) void {
            const allocator = state.registry.environment.allocator();
            const read_wrap = fromWrap(state);
            if (read_wrap.actual) |request| {
                read_wrap.actual = null;
                // This releases only the C storage entitlement. A previous
                // callback event may independently retain that same request.
                uv.pi_uv_fs_request_release(request);
            }
            allocator.destroy(read_wrap);
        }
        fn cancel(entry_value: *request_state.Entry) void {
            const read_wrap = fromEntry(entry_value);
            if (read_wrap.actual) |request| _ = uv.pi_uv_fs_cancel(request);
        }
        const derived: native.Derived = .{
            .mark = mark, .retire = retire, .destroy = destroy,
        };

        fn initialize(read_wrap: *ReadWrap, s: *Scope,
            registry: *native.Registry, wrapper: c.JSValue,
            borrowed_handle: *Handle) !void
        {
            read_wrap.wrap.initialize(registry, wrapper, derived,
                fsreqcallback_provider, -1) catch |err|
            {
                read_wrap.attached = registry.unwrap(wrapper) == &read_wrap.wrap;
                s.boundary.escaping();
                // AsyncWrap's native constructor invokes void AsyncReset.
                // Its completed ordinary init-hook rethrow does not suppress
                // ReqWrap construction or the later FileHandle* member write.
                // The caller's stable Scope continues to own that exact reason.
                if (!read_wrap.attached or !read_wrap.wrap.init_hook_ran or
                    err != error.JavaScriptException or s.boundary.isFatal())
                    return err;
            };
            read_wrap.attached = true;
            try read_wrap.entry.initialize(&read_wrap.wrap, cancel);
            read_wrap.entry_initialized = true;
            try read_wrap.wrap.makeWeak();
            // Initial ReqWrap Reset occurs before the derived handle member.
            read_wrap.entry.reset();
            const status = uv.pi_uv_fs_request_reset(read_wrap.actual.?);
            if (status != 0) return error.ActualFileHandleReadWrapInitialResetRequired;
            read_wrap.file_handle = borrowed_handle;
        }

        /// Compile-time equivalent of MakeDetachedBaseObject<FileHandleReadWrap>.
        /// wrapper is the actual already-created InstanceTemplate local held
        /// by this caller Scope. Success returns one owned native pointer;
        /// the caller moves it into current_read_ or the real native freelist.
        /// No Controller entitlement is stored in this native request.
        pub fn createDetached(s: *Scope, controller: *io.Controller,
            borrowed_handle: *Handle, wrapper: c.JSValue) !*ReadWrap
        {
            const handle_state = borrowed_handle.getAsyncWrap();
            const registry = handle_state.registry;
            if (registry.environment != controller.environment or
                (try registry.environment.requireEngine()) != s.engine)
                return error.ActualFileHandleReadWrapEnvironmentMismatch;
            try controller.beginCall(s.engine);
            defer controller.endCall();
            try s.pending();
            const allocator = registry.environment.allocator();
            const read_wrap = try allocator.create(ReadWrap);
            read_wrap.* = .{};

            const result = uv.pi_uv_fs_request_create(controller.service,
                uv.PI_UV_FS_READ, 0, &read_wrap.actual);
            if (result.allocation_failed != 0 or result.status < 0 or read_wrap.actual == null) {
                const failure: anyerror = if (result.allocation_failed != 0)
                    error.OutOfMemory else error.ActualFileHandleReadWrapStorageRequired;
                return failConstruction(s, read_wrap, registry, failure, false);
            }
            read_wrap.initialize(s, registry, wrapper, borrowed_handle) catch |err|
                return failConstruction(s, read_wrap, registry, err, false);

            // BaseObjectPtr construction happens only after the full derived
            // constructor. retainNative increments before its possible engine
            // check, so failure cleanup owns that one increment as well.
            read_wrap.wrap.retainNative() catch |err|
                return failConstruction(s, read_wrap, registry, err, true);
            read_wrap.wrap.detach() catch |err|
                return failConstruction(s, read_wrap, registry, err, true);
            return read_wrap;
        }

        fn failConstruction(s: *Scope, read_wrap: *ReadWrap,
            registry: *native.Registry, err: anyerror,
            owns_native_pointer: bool) !*ReadWrap
        {
            // Publish the actual typed/native failure before either attached
            // State or raw unsubmitted storage retires. Ordinary init-hook
            // continuation is handled above and does not enter this branch.
            var completion = a.owned.Completion.initVoid(s.engine, err);
            if (read_wrap.attached) {
                if (owns_native_pointer) {
                    read_wrap.wrap.detach() catch {};
                    read_wrap.wrap.releaseNative() catch {};
                } else {
                    read_wrap.wrap.retire(false) catch {};
                }
            } else {
                if (read_wrap.actual) |request| {
                    read_wrap.actual = null;
                    uv.pi_uv_fs_request_release(request);
                }
                registry.environment.allocator().destroy(read_wrap);
            }
            try completion.finishVoid();
            unreachable;
        }

        /// Source Reset is called after uv_fs_req_cleanup and actual dequeue,
        /// before emplace_back and EmitRead. The C reset keeps prior event
        /// entitlements release-only; it creates no wrapper/buffer allocation.
        pub fn reset(read_wrap: *ReadWrap) !void {
            read_wrap.entry.reset();
            const request = read_wrap.actual orelse
                return error.ActualFileHandleReadWrapStorageRequired;
            if (uv.pi_uv_fs_request_reset(request) != 0)
                return error.ActualFileHandleReadWrapResetAdmissionRequired;
        }

        /// Each returned native pointer has exactly one matching release.
        /// Its last release may destroy this allocation; no access follows it.
        pub fn release(read_wrap: *ReadWrap) !void {
            return read_wrap.wrap.releaseNative();
        }
    };
}

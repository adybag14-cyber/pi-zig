// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24.13 StreamResource/StreamListener native list lifetime.
//! The owner embeds these records at stable addresses and keeps its Engine alive
//! through their destruction. No callback pair owns a JavaScript root.
//!
//! StreamBase's default_listener_ is a member: its StreamListener destructor
//! unlinks it BEFORE the StreamResource base destructor processes the remaining
//! listeners. The selected read vtable is native and borrowed; write operations
//! and the JS prototype remain separate.
const em = @import("engine.zig");
const check = @import("native_node_check_failure.zig");
const std = @import("std");
pub const uv = @import("native_node_managed_buffers.zig").uv;

/// Original pure virtual read operations. A listener used by EmitAlloc/EmitRead
/// must supply its actual compiled implementation; lifecycle-only listeners do
/// not install a passing placeholder for these operations.
pub const ReadMethods = struct {
    allocate: *const fn (*Listener, usize) anyerror!uv.uv_buf_t,
    read: *const fn (*Listener, isize, uv.uv_buf_t) anyerror!void,
};

pub const Listener = struct {
    stream: ?*Resource = null,
    previous_listener: ?*Listener = null,
    on_destroy: *const fn (*Listener) void = defaultOnDestroy,
    read_methods: ?*const ReadMethods = null,

    // The original virtual default OnStreamDestroy() has an empty body.
    fn defaultOnDestroy(_: *Listener) void {}

    /// Actual StreamListener::~StreamListener. Call this before releasing the
    /// listener's native storage. Removing an already unlinked listener is not
    /// attempted; the owning Resource may still be in its destructor callback.
    pub fn deinit(self: *Listener) void {
        if (self.stream) |stream| stream.remove(self);
    }
};

pub const Resource = struct {
    // A borrowed diagnostic context projects Node's current isolate into the
    // genuine native CHECK bridge. It is not a JS root or another Env owner.
    engine: *em.Engine,
    listener: ?*Listener = null,
    bytes_read: u64 = 0,
    bytes_written: u64 = 0,

    pub fn init(engine: *em.Engine) Resource {
        return .{ .engine = engine };
    }

    /// StreamResource::PushStreamListener, including the original CHECKs and
    /// the previous -> stream -> head publication order.
    pub fn push(self: *Resource, listener: ?*Listener) void {
        const selected = listener orelse check.assertion(self.engine, .{
            .file_line = "src/stream_base-inl.h:61",
            .message = "(listener) != nullptr",
            .function = "node::StreamResource::PushStreamListener",
        });
        if (selected.stream != null) check.assertion(self.engine, .{
            .file_line = "src/stream_base-inl.h:62",
            .message = "(listener->stream_) == nullptr",
            .function = "node::StreamResource::PushStreamListener",
        });
        selected.previous_listener = self.listener;
        selected.stream = self;
        self.listener = selected;
    }

    /// The original loop intentionally has no success-free exit. A missing
    /// listener reaches its native CHECK; it is not an ordinary host error.
    pub fn remove(self: *Resource, listener: ?*Listener) void {
        const selected = listener orelse check.assertion(self.engine, .{
            .file_line = "src/stream_base.cc:831",
            .message = "(listener) != nullptr",
            .function = "node::StreamResource::RemoveStreamListener",
        });
        var previous: ?*Listener = null;
        var current = self.listener;
        while (true) {
            const actual = current orelse check.assertion(self.engine, .{
                .file_line = "src/stream_base.cc:840",
                .message = "(current) != nullptr",
                .function = "node::StreamResource::RemoveStreamListener",
            });
            if (actual == selected) {
                if (previous) |prior|
                    prior.previous_listener = actual.previous_listener
                else
                    self.listener = selected.previous_listener;
                break;
            }
            previous = actual;
            current = actual.previous_listener;
        }
        selected.stream = null;
        selected.previous_listener = null;
    }

    /// StreamResource::EmitAlloc selects the live head. The native abstract
    /// interface requires the head and its real read vtable to exist.
    pub fn emitAlloc(self: *Resource, suggested_size: usize) !uv.uv_buf_t {
        const selected = self.listener.?;
        std.debug.assert(selected.read_methods != null);
        return selected.read_methods.?.allocate(selected, suggested_size);
    }

    /// The original unsigned counter advances before the selected read method.
    /// This call may delete the native stream; do not access self after it.
    pub fn emitRead(self: *Resource, nread: isize, buffer: uv.uv_buf_t) !void {
        if (nread > 0) self.bytes_read +%= @intCast(nread);
        const selected = self.listener.?;
        std.debug.assert(selected.read_methods != null);
        return selected.read_methods.?.read(selected, nread, buffer);
    }

    /// Actual StreamResource::~StreamResource. OnStreamDestroy may unlink and
    /// free its own listener or alter the native chain. After that callback,
    /// use only the saved pointer identity until the live head is established.
    /// A newly pushed listener is visited by the same original while loop.
    pub fn deinit(self: *Resource) void {
        while (self.listener) |selected| {
            selected.on_destroy(selected);
            if (self.listener == selected) self.remove(self.listener);
        }
    }
};

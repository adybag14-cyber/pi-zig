// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node24.13 StreamResource/StreamListener native list lifetime.
//! The owner embeds these records at stable addresses and keeps its Engine alive
//! through their destruction. No callback pair owns a JavaScript root.
//!
//! StreamBase's default_listener_ is a member: its StreamListener destructor
//! unlinks it BEFORE the StreamResource base destructor processes the remaining
//! listeners. Read/write virtual operations and the JS prototype are separate.
const em = @import("engine.zig");
const check = @import("native_node_check_failure.zig");

pub const Listener = struct {
    stream: ?*Resource = null,
    previous_listener: ?*Listener = null,
    on_destroy: *const fn (*Listener) void = defaultOnDestroy,

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

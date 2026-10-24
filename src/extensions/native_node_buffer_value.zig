// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Native util.cc BufferValue with its original MaybeStackBuffer lifetime.
//! This is an owned native byte copy. The Environment is borrowed through
//! deinit; no JS wrapper or asynchronous backing-store lease is retained.
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const temporary = @import("native_node_maybe_stack_buffer.zig");
const strings = @import("native_node_stream_string_bytes.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;

pub const BufferValue = struct {
    storage: temporary.Buffer(u8, 1024) = undefined,
    initialized: bool = false,
    valid: bool = false,

    /// Keep this owner at a stable address. null is V8's empty Local, which is
    /// distinct from a valid empty string or an actual zero-length view.
    pub fn init(self: *BufferValue, s: *a.Scope,
        environment: *callbacks.Environment, value: ?c.JSValue) !void
    {
        self.* = .{};
        try s.pending();
        if (try environment.requireEngine() != s.engine)
            return error.ActualBufferValueEnvironmentMismatch;
        try self.storage.init(environment, 0);
        self.initialized = true;
        errdefer self.deinit();
        const input = value orelse return;
        if (c.JS_IsString(input)) {
            // The real flat owner is rooted before native growth may run GC.
            const view = try strings.flat(s, input);
            const expected = if (view.data8 != null)
                (if (self.storage.capacity() < view.length *% 2 +% 1)
                    strings.exactUtf8(&view) else view.length *% 2) +% 1
                else view.length *% 3 +% 1;
            try self.storage.allocateSufficientStorage(expected);
            const destination = self.storage.capacityData();
            const written = strings.boundedUtf8(&view, destination.ptr, expected);
            self.storage.length = written;
            destination[written] = 0;
            self.valid = true;
        } else if (c.JS_GetTypedArrayType(input) >= 0 or c.JS_IsDataView(input)) {
            const owner = try s.own(a.duplicate(s.engine, input));
            const length = c.JS_PiArrayBufferViewByteLength(owner);
            try self.storage.allocateSufficientStorage(length + 1);
            const destination = self.storage.capacityData();
            // Source deliberately ignores CopyContents' returned count. In
            // particular tracking views copy zero stored bytes; do not replace
            // this with a dynamic-span memcpy or initialize the unused suffix.
            _ = c.JS_PiArrayBufferViewCopyContents(owner, destination.ptr, length);
            self.storage.length = length;
            destination[length] = 0;
            self.valid = true;
        }
        // All other values invalidate without ToString, getters or proxy traps.
    }

    pub fn bytes(self: *BufferValue) ?[:0]const u8 {
        if (!self.valid) return null;
        return self.storage.capacityData()[0..self.storage.length :0];
    }
    pub fn capacity(self: *const BufferValue) usize {
        return if (self.valid) self.storage.capacity() else 0;
    }
    pub fn isAllocated(self: *const BufferValue) bool {
        return self.valid and self.storage.isAllocated();
    }
    /// Original ToNamespacedPath supplies a distinct native String span, valid
    /// through this copy. It must not alias this owner's potentially reallocated
    /// storage. The full span, including embedded NUL bytes, remains native.
    pub fn copyFromNative(self: *BufferValue, source: []const u8) !void {
        if (!self.valid) check.assertion(try self.storage.environment.requireEngine(), .{
            .file_line = "src/util-inl.h:554",
            .message = "!IsInvalidated()",
            .function = "node::MaybeStackBuffer::AllocateSufficientStorage",
        });
        try self.storage.allocateSufficientStorage(source.len + 1);
        const destination = self.storage.capacityData();
        @memcpy(destination[0..source.len], source);
        self.storage.length = source.len;
        destination[source.len] = 0;
    }
    pub fn deinit(self: *BufferValue) void {
        if (self.initialized) self.storage.deinit();
        self.initialized = false;
        self.valid = false;
    }
};

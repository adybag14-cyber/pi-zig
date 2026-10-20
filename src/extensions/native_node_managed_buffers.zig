//! The actual native managed-buffer table embedded in one Environment block.
//! Backing allocation/retry and intrinsic ArrayBuffer adoption are separate.
//! This owner holds no JS roots and never reconstructs a token from its data.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
pub const uv = @cImport({ @cInclude("uv.h"); });
pub const Token = c.JSPiArrayBufferBackingStore;
const Native = opaque {};
extern fn pi_node_managed_buffers_storage_size() usize;
extern fn pi_node_managed_buffers_storage_alignment() usize;
extern fn pi_node_managed_buffers_construct(storage: *anyopaque) *Native;
extern fn pi_node_managed_buffers_destroy(table: *Native) void;
extern fn pi_node_managed_buffers_adopt(table: *Native, memory_owner: *anyopaque,
    owned: *Token, buffer: *uv.uv_buf_t) void;
extern fn pi_node_managed_buffers_release(table: *Native, context: *c.JSContext,
    buffer: *const uv.uv_buf_t, owned_out: *Token) void;
extern fn pi_node_managed_buffers_count(table: *const Native) usize;

pub const Layout = struct {
    offset: usize,
    bytes: usize,
    alignment: std.mem.Alignment,
};
/// Native size/alignment are obtained from the very C++ owner being embedded.
pub fn layout(comptime Parent: type) !Layout {
    const native_alignment = pi_node_managed_buffers_storage_alignment();
    const alignment = @max(@alignOf(Parent), native_alignment);
    const offset = std.mem.alignForward(usize, @sizeOf(Parent), native_alignment);
    const bytes = std.math.add(usize, offset, pi_node_managed_buffers_storage_size()) catch return error.OutOfMemory;
    return .{ .offset = offset, .bytes = bytes, .alignment = .fromByteUnits(alignment) };
}

pub const Store = struct {
    native: ?*Native = null,
    pub fn init(self: *Store, stable_storage: *anyopaque) void {
        std.debug.assert(self.native == null);
        self.native = pi_node_managed_buffers_construct(stable_storage);
    }
    pub fn deinit(self: *Store) void {
        const native = self.native orelse return;
        self.native = null;
        pi_node_managed_buffers_destroy(native);
    }
    /// The caller owns a complete native backing token from its actual provider.
    /// This consumes it into the real map; no JS ArrayBuffer is constructed.
    pub fn adopt(self: *Store, memory_owner: *anyopaque, owned: *Token) uv.uv_buf_t {
        var buffer: uv.uv_buf_t = undefined;
        pi_node_managed_buffers_adopt(self.native.?, memory_owner, owned, &buffer);
        return buffer;
    }
    pub fn release(self: *Store, context: *c.JSContext, buffer: uv.uv_buf_t) Token {
        var result: Token = std.mem.zeroes(Token);
        pi_node_managed_buffers_release(self.native.?, context, &buffer, &result);
        return result;
    }
    pub fn count(self: *const Store) usize {
        return pi_node_managed_buffers_count(self.native.?);
    }
};

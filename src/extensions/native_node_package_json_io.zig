// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual selected util.cc ReadFileSync over the shared pinned libuv owner.
//! Native read failures remain negative statuses; allocation failures remain
//! typed host failures. The returned byte allocation is independently owned
//! until the caller finishes the parser's borrowed-input operation.
const std = @import("std");
const js = @import("native_js_values.zig");
const check = @import("native_node_check_failure.zig");
const uv = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("uv.h");
    @cInclude("fcntl.h");
});

pub const Bytes = struct {
    storage: std.ArrayList(u8),
    pub fn slice(self: *const Bytes) []const u8 { return self.storage.items; }
    pub fn deinit(self: *Bytes, allocator: std.mem.Allocator) void {
        self.storage.deinit(allocator);
        self.storage = .empty;
    }
};
pub const Result = union(enum) {
    // This is the actual negative uv status returned by ReadFileSync, including
    // ordinary open and read failures. The modules owner caches a null result.
    unavailable: c_int,
    bytes: Bytes,
};

fn closeFile(engine: *js.Engine, descriptor: uv.uv_file) void {
    var request: uv.uv_fs_t = undefined;
    const status = uv.uv_fs_close(null, &request, descriptor, null);
    if (status != 0) {
        const site = @src();
        check.assertion(engine, .{
            .file_line = std.fmt.comptimePrint("{s}:{d}", .{site.file, site.line}),
            .message = "(0) == (uv_fs_close(nullptr, &close_req, file, nullptr))",
            .function = site.fn_name,
        });
    }
    uv.uv_fs_req_cleanup(&request);
}

/// The allocator must be the actual retained native charged domain. Its owner
/// outlives the returned Bytes and every parse borrowing them. This synchronous
/// operation invokes no public fs object, guest callback or worker VM entry.
pub fn read(engine: *js.Engine, allocator: std.mem.Allocator, path: [:0]const u8) !Result {
    var request: uv.uv_fs_t = undefined;
    defer uv.uv_fs_req_cleanup(&request);
    const descriptor = uv.uv_fs_open(null, &request, path.ptr, uv.O_RDONLY, 0, null);
    if (request.result < 0) return .{ .unavailable = @intCast(request.result) };
    uv.uv_fs_req_cleanup(&request);
    defer closeFile(engine, descriptor);

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var buffer: [4096]u8 = undefined;
    var span = uv.uv_buf_init(&buffer, buffer.len);
    while (true) {
        // Original size_t result->length() is passed to libuv's signed offset.
        // The admitted native binding is 64-bit; preserve that bit conversion.
        const offset: i64 = @bitCast(@as(u64, @intCast(output.items.len)));
        const count = uv.uv_fs_read(null, &request, descriptor, &span, 1, offset, null);
        if (request.result < 0) {
            output.deinit(allocator);
            return .{ .unavailable = @intCast(request.result) };
        }
        uv.uv_fs_req_cleanup(&request);
        if (count <= 0) break;
        output.appendSlice(allocator, buffer[0..@intCast(count)]) catch |err| {
            // The real native allocator has failed. Record its producer before
            // the buffer and descriptor are retired by the enclosing defers.
            if (err == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
            return err;
        };
    }
    return .{ .bytes = .{ .storage = output } };
}

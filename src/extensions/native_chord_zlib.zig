//! Pinned Node24.14.0 C zlib raw deflate/inflate, owned by the native Zig allocator.
const std = @import("std");
const z = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("zlib.h");
});
const Alloc = struct { gpa: std.mem.Allocator, failed: bool = false };
fn allocate(context_data: ?*anyopaque, count: c_uint, size: c_uint) callconv(.c) ?*anyopaque {
    const owner: *Alloc = @ptrCast(@alignCast(context_data.?));
    const bytes = std.math.mul(usize, count, size) catch {
        owner.failed = true;
        return null;
    };
    const length = std.math.add(usize, bytes, @sizeOf(usize)) catch {
        owner.failed = true;
        return null;
    };
    const memory = owner.gpa.rawAlloc(length, .of(usize), @returnAddress()) orelse {
        owner.failed = true;
        return null;
    };
    const header: *usize = @ptrCast(@alignCast(memory));
    header.* = length;
    @memset(memory[@sizeOf(usize)..length], 0);
    return memory + @sizeOf(usize);
}
fn release(context_data: ?*anyopaque, pointer: ?*anyopaque) callconv(.c) void {
    const raw = pointer orelse return;
    const owner: *Alloc = @ptrCast(@alignCast(context_data.?));
    const bytes: [*]u8 = @ptrCast(raw);
    const memory = bytes - @sizeOf(usize);
    const header: *const usize = @ptrCast(@alignCast(memory));
    owner.gpa.rawFree(memory[0..header.*], .of(usize), @returnAddress());
}
pub const Failure = error{ OutOfMemory, ZlibData, ZlibUnexpectedEnd, ZlibRange };
pub fn deflate(gpa: std.mem.Allocator, input: []const u8) Failure![]u8 {
    if (input.len > std.math.maxInt(c_uint)) return error.ZlibRange;
    var owner: Alloc = .{ .gpa = gpa };
    var stream: z.z_stream = std.mem.zeroes(z.z_stream);
    stream.zalloc = allocate;
    stream.zfree = release;
    stream.@"opaque" = &owner;
    const initialized = z.deflateInit2_(&stream, 1, z.Z_DEFLATED, -15, 8, z.Z_DEFAULT_STRATEGY, z.ZLIB_VERSION, @sizeOf(z.z_stream));
    if (initialized != z.Z_OK) return if (owner.failed or initialized == z.Z_MEM_ERROR) error.OutOfMemory else error.ZlibData;
    defer _ = z.deflateEnd(&stream);
    const bound = z.deflateBound(&stream, @intCast(input.len));
    if (bound > std.math.maxInt(c_uint)) return error.ZlibRange;
    const output = try gpa.alloc(u8, @intCast(bound));
    errdefer gpa.free(output);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = output.ptr;
    stream.avail_out = @intCast(output.len);
    const status = z.deflate(&stream, z.Z_FINISH);
    if (status != z.Z_STREAM_END) return if (owner.failed or status == z.Z_MEM_ERROR) error.OutOfMemory else error.ZlibData;
    return gpa.realloc(output, @intCast(stream.total_out));
}
pub fn inflate(gpa: std.mem.Allocator, input: []const u8, diagnostic: *?[]const u8) Failure![]u8 {
    if (input.len > std.math.maxInt(c_uint)) return error.ZlibRange;
    var owner: Alloc = .{ .gpa = gpa };
    var stream: z.z_stream = std.mem.zeroes(z.z_stream);
    stream.zalloc = allocate;
    stream.zfree = release;
    stream.@"opaque" = &owner;
    const initialized = z.inflateInit2_(&stream, -15, z.ZLIB_VERSION, @sizeOf(z.z_stream));
    if (initialized != z.Z_OK) return if (owner.failed or initialized == z.Z_MEM_ERROR) error.OutOfMemory else error.ZlibData;
    defer _ = z.inflateEnd(&stream);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    var chunk: [32 * 1024]u8 = undefined;
    while (true) {
        stream.next_out = &chunk;
        stream.avail_out = chunk.len;
        const status = z.inflate(&stream, z.Z_NO_FLUSH);
        if (status == z.Z_MEM_ERROR or owner.failed) return error.OutOfMemory;
        if (status != z.Z_OK and status != z.Z_STREAM_END and status != z.Z_BUF_ERROR) {
            if (stream.msg != null) diagnostic.* = std.mem.span(stream.msg);
            return error.ZlibData;
        }
        try output.appendSlice(gpa, chunk[0 .. chunk.len - stream.avail_out]);
        if (status == z.Z_STREAM_END) return output.toOwnedSlice(gpa);
        if (stream.avail_out != 0 and stream.avail_in == 0) return error.ZlibUnexpectedEnd;
        if (status == z.Z_BUF_ERROR) return error.ZlibUnexpectedEnd;
    }
}

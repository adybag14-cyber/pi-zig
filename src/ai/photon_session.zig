const std = @import("std");
const c = @cImport({
    @cInclude("session_api.h");
});
pub const Operation = c.enum_PiSessionOperation;
pub const Reply = c.PiSessionReply;
pub const operations = c;
pub const Failure = struct {
    status: c_int,
    message: ?[]u8,
    pub fn deinit(self: *Failure, allocator: std.mem.Allocator) void {
        if (self.message) |bytes| allocator.free(bytes);
        self.* = undefined;
    }
};
pub const Result = union(enum) { value: Reply, failure: Failure };
pub const Session = struct {
    gpa: std.mem.Allocator,
    raw: *c.PiPhotonSession,
    pub fn allocate(context: ?*anyopaque, length: usize, alignment: usize) callconv(.c) ?*anyopaque {
        const allocator: *std.mem.Allocator = @ptrCast(@alignCast(context.?));
        return allocator.rawAlloc(length, .fromByteUnits(alignment), @returnAddress());
    }
    pub fn release(context: ?*anyopaque, pointer: ?*anyopaque, length: usize, alignment: usize) callconv(.c) void {
        const allocator: *std.mem.Allocator = @ptrCast(@alignCast(context.?));
        const bytes: [*]u8 = @ptrCast(pointer.?);
        allocator.rawFree(bytes[0..length], .fromByteUnits(alignment), @returnAddress());
    }
    pub fn init(gpa: std.mem.Allocator) !*Session {
        const self = try gpa.create(Session);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        const created = c.pi_session_create(.{ .context = &self.gpa, .allocate = allocate, .release = release }, 32 * 1024 * 1024);
        if (created.status != 0) return if (created.status == 1) error.OutOfMemory else error.CodecSessionCreationFailed;
        self.raw = created.session.?;
        return self;
    }
    pub fn deinit(self: *Session) void {
        const gpa = self.gpa;
        std.debug.assert(c.pi_session_destroy(self.raw) == 0);
        gpa.destroy(self);
    }
    pub fn call(self: *Session, op: c.enum_PiSessionOperation, handle: u32, input: ?[]const u8, width: u32, height: u32, quality: u32) c.PiSessionReply {
        return c.pi_session_call(self.raw, op, handle, if (input) |bytes| bytes.ptr else null, if (input) |bytes| bytes.len else 0, width, height, quality, std.math.maxInt(u32));
    }
    pub fn checked(self: *Session, reply: c.PiSessionReply) !c.PiSessionReply {
        if (reply.status == 0) return reply;
        self.freeReply(reply);
        return if (reply.status == 1) error.OutOfMemory else error.CodecSessionOperationFailed;
    }
    pub fn invoke(self: *Session, op: Operation, handle: u32, input: ?[]const u8, width: u32, height: u32, quality: u32) !Result {
        const reply = self.call(op, handle, input, width, height, quality);
        if (reply.status == 0) return .{ .value = reply };
        if (reply.bytes != null) self.gpa.free(reply.bytes[0..reply.length]);
        if (reply.status == 1) {
            if (reply.message != null) self.gpa.free(reply.message[0..reply.message_length]);
            return error.OutOfMemory;
        }
        return .{ .failure = .{ .status = reply.status, .message = if (reply.message != null) reply.message[0..reply.message_length] else null } };
    }
    pub fn freeReply(self: *Session, reply: c.PiSessionReply) void {
        if (reply.bytes != null) self.gpa.free(reply.bytes[0..reply.length]);
        if (reply.message != null) self.gpa.free(reply.message[0..reply.message_length]);
    }
};

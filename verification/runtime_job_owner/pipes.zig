//! One local restricted overlapped server, with an explicitly inherited client.
const std = @import("std");
const w = @import("win32.zig");
const security = @import("security.zig");
const Deadline = @import("deadline.zig").Deadline;
const Operation = @import("overlapped.zig").Operation;
pub const Pair = struct {
    server: ?w.H,
    client: ?w.H,
    pub fn create(allocator: std.mem.Allocator, acl: *const security.PrivateAcl,
        suffix: []const u8, duplex: bool, deadline: Deadline) !Pair
    {
        if (suffix.len == 0 or suffix.len > 32) return error.InvalidPipeSuffix;
        for (suffix) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-') return error.InvalidPipeSuffix;
        try deadline.normal();
        const random = try security.nonce();
        const hex = std.fmt.bytesToHex(random, .lower);
        const path = try std.fmt.allocPrint(allocator, "\\\\.\\pipe\\pi-runtime-{s}-{s}", .{ hex, suffix });
        defer allocator.free(path);
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
        defer allocator.free(wide);
        var attributes = acl.attributes(false);
        // FIRST_PIPE_INSTANCE | OVERLAPPED | INBOUND/DUPLEX, BYTE/WAIT,
        // REJECT_REMOTE_CLIENTS. At most one client and bounded OS buffers.
        const server = w.CreateNamedPipeW(wide.ptr,
            0x00080000 | w.file_flag_overlapped | @as(u32, if (duplex) 3 else 1),
            0x00000008, 1, 65536, 65536, 1000, &attributes);
        if (server == w.invalid) return error.PrivatePipeCreateFailed;
        errdefer _ = w.CloseHandle(server);
        var connection = try Operation.init(server);
        // This function does not return any live OVERLAPPED. If connection does
        // not retire within its budget, retain state at a stable address and
        // exit the owner negative rather than freeing stack-backed pending I/O.
        // Therefore connection is heap allocated below before issuing I/O.
        defer connection.close() catch {};
        const pending = try allocator.create(Operation);
        pending.* = connection;
        connection.event = null; // ownership moved before I/O starts
        var safe_to_free = true;
        defer if (safe_to_free) {
            pending.close() catch {};
            allocator.destroy(pending);
        };
        pending.overlapped.event = pending.event;
        pending.pending = true;
        if (w.ConnectNamedPipe(server, &pending.overlapped) == 0) {
            const cause = w.GetLastError();
            if (cause == 535) { // ERROR_PIPE_CONNECTED
                pending.pending = false;
            } else if (cause != w.error_io_pending) {
                pending.pending = false;
                return error.PrivatePipeConnectFailed;
            }
        }
        var client_attributes = acl.attributes(true);
        const access: u32 = if (duplex) w.generic_read | w.generic_write else w.generic_write;
        const client = w.CreateFileW(wide.ptr, access, 0, &client_attributes, w.open_existing,
            if (duplex) w.file_flag_overlapped else 0, null);
        if (client == w.invalid) {
            pending.cancel() catch {};
            if (pending.pending and w.WaitForSingleObject(pending.event.?,
                @min(2000, Deadline.remaining(deadline.cutoff_ms))) == w.wait_object) _ = pending.poll();
            safe_to_free = !pending.pending;
            return error.PrivatePipeClientFailed;
        }
        errdefer _ = w.CloseHandle(client);
        if (pending.pending) {
            if (w.WaitForSingleObject(pending.event.?, @min(2000, Deadline.remaining(deadline.cutoff_ms))) != w.wait_object) {
                pending.cancel() catch {};
                if (w.WaitForSingleObject(pending.event.?, Deadline.remaining(deadline.retirementEnd())) == w.wait_object)
                    _ = pending.poll();
                safe_to_free = !pending.pending;
                return error.PrivatePipeConnectionTimeout;
            }
            switch (pending.poll()) {
                .complete => {},
                .pending => {
                    safe_to_free = false;
                    return error.PrivatePipeConnectionUnretired;
                },
                .failed => return error.PrivatePipeConnectFailed,
            }
        }
        var flags: u32 = 0;
        if (w.GetHandleInformation(server, &flags) == 0 or flags & w.handle_flag_inherit != 0)
            return error.ServerPipeInheritable;
        if (w.GetHandleInformation(client, &flags) == 0 or flags & w.handle_flag_inherit == 0)
            return error.ClientPipeNotInheritable;
        return .{ .server = server, .client = client };
    }
    pub fn closeClient(self: *Pair) !void {
        if (self.client) |client| {
            if (w.CloseHandle(client) == 0) return error.ClientPipeCloseFailed;
            self.client = null;
        }
    }
    /// All read/write operation states must already be retired before this call.
    pub fn closeServer(self: *Pair, pending_io: bool) !void {
        if (pending_io) return error.PendingPipeIoMustRemainAlive;
        if (self.server) |server| {
            if (w.CloseHandle(server) == 0) return error.ServerPipeCloseFailed;
            self.server = null;
        }
    }
};

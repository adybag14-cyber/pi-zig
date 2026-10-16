//! Local private channels; never a host/global named synchronization object.
const std = @import("std");
const w = @import("win32.zig");
const TokenUser = extern struct { sid: *anyopaque, attributes: u32 };
pub const PrivateAcl = struct {
    descriptor: ?*anyopaque,
    pub fn create(allocator: std.mem.Allocator) !PrivateAcl {
        var token: w.H = undefined;
        if (w.OpenProcessToken(w.GetCurrentProcess(), 8, &token) == 0) return error.TokenQueryFailed;
        defer _ = w.CloseHandle(token);
        var buffer: [4096]u8 align(8) = undefined;
        var needed: u32 = 0;
        if (w.GetTokenInformation(token, 1, &buffer, buffer.len, &needed) == 0 or
            needed < @sizeOf(TokenUser) or needed > buffer.len) return error.TokenUserUnverifiable;
        const user: *const TokenUser = @ptrCast(&buffer);
        var sid_text: ?[*:0]u16 = null;
        if (w.ConvertSidToStringSidW(user.sid, &sid_text) == 0) return error.SidSerializationFailed;
        const sid = sid_text orelse return error.SidSerializationFailed;
        defer _ = w.LocalFree(@ptrCast(sid));
        const sid_utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(sid));
        defer allocator.free(sid_utf8);
        const sddl = try std.fmt.allocPrint(allocator, "O:{s}D:P(A;;GA;;;SY)(A;;GA;;;{s})", .{ sid_utf8, sid_utf8 });
        defer allocator.free(sddl);
        const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, sddl);
        defer allocator.free(wide);
        var descriptor: ?*anyopaque = null;
        if (w.ConvertStringSecurityDescriptorToSecurityDescriptorW(wide.ptr, 1, &descriptor, null) == 0 or descriptor == null)
            return error.PrivateAclFailed;
        return .{ .descriptor = descriptor };
    }
    pub fn attributes(self: *const PrivateAcl, inherit: bool) w.Security {
        return .{ .length = @sizeOf(w.Security), .descriptor = self.descriptor, .inherit = @intFromBool(inherit) };
    }
    pub fn close(self: *PrivateAcl) !void {
        if (self.descriptor) |descriptor| {
            if (w.LocalFree(descriptor) != null) return error.PrivateAclReleaseFailed;
            self.descriptor = null;
        }
    }
};

pub fn nonce() ![32]u8 {
    var result: [32]u8 = undefined;
    if (w.BCryptGenRandom(null, &result, result.len, 2) < 0) return error.OsRandomFailed;
    return result;
}

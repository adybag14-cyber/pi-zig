//! Optional byte-only request preparation executed inside the owned HTTP worker.
const std = @import("std");
pub const View = struct { method: std.http.Method, url: []const u8, payload: []const u8, headers: []const std.http.Header };
pub const Budget = struct {
    io: std.Io,
    abort_flag: *bool,
    deadline_ms: ?i64,
    pub fn remaining(self: Budget) !?u64 {
        if (@atomicLoad(bool, self.abort_flag, .acquire)) return error.ProviderRequestAborted;
        const deadline = self.deadline_ms orelse return null;
        const now = std.Io.Clock.awake.now(self.io).toMilliseconds();
        if (now >= deadline) return error.ProviderRequestTimeout;
        return @intCast(deadline - now);
    }
};
pub const Prepared = struct {
    /// Additional headers own both the name and value. Original headers remain borrowed.
    headers: []std.http.Header,
    url: ?[]u8 = null,
    pub fn deinit(self: *Prepared, a: std.mem.Allocator) void {
        for (self.headers) |header| {
            @memset(@constCast(header.value), 0);
            a.free(header.name);
            a.free(header.value);
        }
        a.free(self.headers);
        if (self.url) |url| a.free(url);
        self.* = undefined;
    }
};
pub const Callback = *const fn (std.mem.Allocator, View, []const u8, Budget) anyerror!Prepared;

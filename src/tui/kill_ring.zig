//! Emacs-style kill ring used by the native editor.
const std = @import("std");

pub const KillRing = struct {
    gpa: std.mem.Allocator,
    entries: std.ArrayList([]u8) = .empty,

    pub fn init(gpa: std.mem.Allocator) KillRing {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *KillRing) void {
        for (self.entries.items) |entry| self.gpa.free(entry);
        self.entries.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn push(self: *KillRing, text: []const u8, prepend: bool, accumulate: bool) !void {
        if (text.len == 0) return;
        if (accumulate and self.entries.items.len > 0) {
            const idx = self.entries.items.len - 1;
            const old = self.entries.items[idx];
            const merged = try self.gpa.alloc(u8, old.len + text.len);
            if (prepend) {
                @memcpy(merged[0..text.len], text);
                @memcpy(merged[text.len..], old);
            } else {
                @memcpy(merged[0..old.len], old);
                @memcpy(merged[old.len..], text);
            }
            self.gpa.free(old);
            self.entries.items[idx] = merged;
            return;
        }
        try self.entries.append(self.gpa, try self.gpa.dupe(u8, text));
    }

    pub fn peek(self: *const KillRing) ?[]const u8 {
        if (self.entries.items.len == 0) return null;
        return self.entries.items[self.entries.items.len - 1];
    }

    /// Upstream rotates the newest entry to the front, making the previous
    /// newest element available through peek() on the next yank-pop cycle.
    pub fn rotate(self: *KillRing) void {
        if (self.entries.items.len <= 1) return;
        const newest = self.entries.pop().?;
        var i = self.entries.items.len;
        self.entries.appendAssumeCapacity(newest);
        while (i > 0) : (i -= 1) self.entries.items[i] = self.entries.items[i - 1];
        self.entries.items[0] = newest;
    }
};

test "kill ring accumulates directionally and rotates" {
    var ring = KillRing.init(std.testing.allocator);
    defer ring.deinit();
    try ring.push("world", false, false);
    try ring.push("hello ", true, true);
    try std.testing.expectEqualStrings("hello world", ring.peek().?);
    try ring.push("older", false, false);
    try std.testing.expectEqualStrings("older", ring.peek().?);
    ring.rotate();
    try std.testing.expectEqualStrings("hello world", ring.peek().?);
}

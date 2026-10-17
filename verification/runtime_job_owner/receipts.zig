//! Bounded synchronous evidence writes: worker/sealer thread only, never timer.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const manifest = @import("manifest.zig");
const Deadline = @import("deadline.zig").Deadline;
pub const Quota = struct { used: u64 = 0, limit: u64 = 256 * 1024 * 1024 };
pub const Writer = struct {
    handle: ?w.H,
    quota: *Quota,
    deadline: Deadline,
    bytes: u64 = 0,
    hash: std.crypto.hash.sha2.Sha256 = std.crypto.hash.sha2.Sha256.init(.{}),
    failure: ?anyerror = null,
    pub fn create(allocator: std.mem.Allocator, evidence_root: []const u8, path: []const u8,
        quota: *Quota, deadline: Deadline) !Writer
    {
        try files.contained(evidence_root, files.container ++ "\\evidence");
        try files.contained(path, evidence_root);
        try files.requirePhysicalAncestors(allocator, path);
        const handle = try files.openLeaf(allocator, path, w.generic_write, w.create_new, 0);
        errdefer _ = w.CloseHandle(handle);
        _ = try files.requirePhysical(handle);
        var flags: u32 = 0;
        if (w.GetHandleInformation(handle, &flags) == 0 or flags & w.handle_flag_inherit != 0)
            return error.EvidenceHandleInheritable;
        return .{ .handle = handle, .quota = quota, .deadline = deadline };
    }
    pub fn write(self: *Writer, bytes: []const u8) !void {
        if (self.failure) |err| return err;
        if (bytes.len > self.quota.limit - self.quota.used) return error.EvidenceQuotaExceeded;
        const handle = self.handle orelse return error.EvidenceClosed;
        var offset: usize = 0;
        while (offset < bytes.len) {
            try self.deadline.normal();
            const amount: u32 = @intCast(@min(bytes.len - offset, 65536));
            var count: u32 = 0;
            if (w.WriteFile(handle, bytes[offset..].ptr, amount, &count, null) == 0 or count == 0 or count > amount) {
                self.failure = error.EvidenceWriteFailed;
                return error.EvidenceWriteFailed;
            }
            self.hash.update(bytes[offset..][0..count]);
            self.bytes += count;
            self.quota.used += count;
            offset += count;
        }
    }
    pub fn json(self: *Writer, value: anytype) !void {
        var buffer: [256 * 1024]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try std.json.Stringify.value(value, .{}, &writer);
        try writer.writeByte('\n');
        try self.write(writer.buffered());
    }
    pub fn finish(self: *Writer) !files.Hash {
        if (self.failure) |err| return err;
        try self.deadline.normal();
        const handle = self.handle orelse return error.EvidenceClosed;
        // This may block in the sealer thread; supervisor timing/watchdog never
        // joins indefinitely and retains state until bounded process exit.
        if (w.FlushFileBuffers(handle) == 0) {
            self.failure = error.EvidenceFlushFailed;
            return error.EvidenceFlushFailed;
        }
        var digest: files.Hash = undefined;
        self.hash.final(&digest);
        if (w.CloseHandle(handle) == 0) {
            self.failure = error.EvidenceCloseFailed;
            return error.EvidenceCloseFailed;
        }
        self.handle = null;
        return digest;
    }
    pub fn closePartial(self: *Writer) !void {
        if (self.handle) |handle| {
            if (w.CloseHandle(handle) == 0) return error.EvidencePartialCloseFailed;
            self.handle = null;
        }
    }
};

pub const InventorySink = struct {
    observed_files: *Writer,
    namespace: *Writer,
    differences: *Writer,
    pub fn sink(self: *InventorySink) manifest.Sink { return .{ .context = self, .write_fn = emit }; }
    fn emit(raw: *anyopaque, record: manifest.Record) !void {
        const self: *InventorySink = @ptrCast(@alignCast(raw));
        switch (record) {
            .file => |row| {
                const actual_hex = std.fmt.bytesToHex(row.sha256, .upper);
                const actual_text: []const u8 = &actual_hex;
                try self.observed_files.json(.{ .relative = row.relative, .sha256 = actual_text });
                try self.namespace.json(.{ .kind = "file", .relative = row.relative, .sha256 = actual_text });
                if (row.expected) |expected| {
                    if (!std.mem.eql(u8, &expected, &row.sha256)) {
                        const expected_hex = std.fmt.bytesToHex(expected, .upper);
                        const expected_text: []const u8 = &expected_hex;
                        try self.differences.json(.{ .kind = "drift", .relative = row.relative,
                            .expected_sha256 = expected_text, .actual_sha256 = actual_text });
                    }
                } else try self.differences.json(.{ .kind = "extra", .relative = row.relative, .sha256 = actual_text });
            },
            .reparse => |row| try self.namespace.json(.{ .kind = "reparse", .relative = row.relative, .tag = row.tag }),
            .directory => |row| try self.namespace.json(.{ .kind = "directory", .relative = row.relative }),
            .missing => |row| {
                const hex = std.fmt.bytesToHex(row.expected, .upper);
                const text: []const u8 = &hex;
                // Expected missing rows are differences, never actual files.
                try self.differences.json(.{ .kind = "missing", .relative = row.relative, .expected_sha256 = text });
            },
        }
    }
};

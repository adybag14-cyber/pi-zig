//! Ordered Node envPairs remain authoritative. Zig Environ.Map has stricter
//! key preconditions than Node and must never receive unchecked guest names.
const std = @import("std");
const builtin = @import("builtin");
pub const Environment = struct {
    gpa: std.mem.Allocator,
    pairs: std.ArrayList([]u8) = .empty,
    projection: std.process.Environ.Map,
    projection_complete: bool = true,
    pub fn init(gpa: std.mem.Allocator) Environment { return .{ .gpa = gpa, .projection = .init(gpa) }; }
    pub fn deinit(self: *Environment) void {
        for (self.pairs.items) |pair| self.gpa.free(pair);
        self.pairs.deinit(self.gpa);
        self.projection.deinit();
    }
    pub fn append(self: *Environment, key: []const u8, value: []const u8) !void {
        const pair = try std.fmt.allocPrint(self.gpa, "{s}={s}", .{ key, value });
        errdefer self.gpa.free(pair);
        // A coercion that introduces NUL after Node's string-only validation
        // cannot be put into a sentinel block without losing data. Keep this
        // an explicit private unsupported boundary, not a forged Node error.
        if (std.mem.indexOfScalar(u8, pair, 0) != null) return error.NativeSerializedEnvironmentNulUnsupported;
        if (std.process.Environ.Map.validateKeyForPut(key)) {
            if (self.projection.contains(key)) self.projection_complete = false;
            try self.projection.put(key, value);
        } else self.projection_complete = false;
        try self.pairs.append(self.gpa, pair);
    }
    /// ChildProcess.prototype.spawn accepts native envPairs directly. Preserve
    /// their byte order/data; no Environ.Map assertion or lossy reserialization.
    pub fn appendSerialized(self: *Environment, value: []const u8) !void {
        if (std.mem.indexOfScalar(u8, value, 0) != null) return error.NativeSerializedEnvironmentNulUnsupported;
        const copy = try self.gpa.dupe(u8, value); errdefer self.gpa.free(copy);
        try self.pairs.append(self.gpa, copy); self.projection_complete = false;
    }
    pub fn get(self: *const Environment, name: []const u8) ?[]const u8 {
        for (self.pairs.items) |pair| {
            const separator = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
            const same = if (builtin.os.tag == .windows) std.ascii.eqlIgnoreCase(pair[0..separator], name) else std.mem.eql(u8, pair[0..separator], name);
            if (same) return pair[separator + 1 ..];
        }
        return null;
    }
    pub fn posixMap(self: *const Environment) !*const std.process.Environ.Map {
        if (!self.projection_complete) return error.NativeRawPosixEnvironmentRequiresDedicatedExecve;
        return &self.projection;
    }
};

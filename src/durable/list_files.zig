//! Native equivalent of pi-env/list.rs. The walk owns its ignore stack and never follows child links.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const ignores = @import("list_ignore.zig");
pub const maximum_payload = 16 * 1024 * 1024 - 64 * 1024;
pub const Options = struct {
    hidden: bool = true,
    gitignore: bool = true,
    exclude: []const []const u8 = &.{},
    maxEntries: u64 = 50_000,
    maxBytes: u64 = 4 * 1024 * 1024,
    timeoutMs: u64 = 10_000,
    pub fn valid(self: Options) bool {
        const safe = 9007199254740991;
        return self.maxEntries <= safe and self.maxBytes <= safe and self.timeoutMs <= safe;
    }
    pub fn invalidMessage(self: Options) ?[]const u8 {
        inline for (.{ "maxEntries", "maxBytes", "timeoutMs" }) |key| {
            if (@field(self, key) > 9007199254740991) return key ++ " must be a non-negative safe integer";
        }
        return null;
    }
    pub fn fromJson(value: std.json.Value) !Options {
        if (value != .object) return error.InvalidField;
        var result: Options = .{};
        inline for (.{ "hidden", "gitignore" }) |key| if (value.object.get(key)) |field| {
            if (field == .bool) @field(result, key) = field.bool;
        };
        inline for (.{ "maxEntries", "maxBytes", "timeoutMs" }) |key| if (value.object.get(key)) |field| {
            if (field != .null) {
                @field(result, key) = switch (field) {
                    .integer => |n| if (n >= 0) @intCast(n) else return error.InvalidField,
                    .number_string => |n| std.fmt.parseInt(u64, n, 10) catch return error.InvalidField,
                    else => return error.InvalidField,
                };
            }
        };
        return result;
    }
};
pub const Entry = struct { path: []u8, kind: types.FileKind };
pub const Listing = struct {
    entries: []Entry,
    truncated: bool,
    pub fn deinit(self: *Listing, gpa: std.mem.Allocator) void {
        for (self.entries) |entry| gpa.free(entry.path);
        gpa.free(self.entries);
        self.* = undefined;
    }
    pub fn payload(self: Listing, gpa: std.mem.Allocator) ![]u8 {
        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(gpa);
        for (self.entries) |entry| {
            try bytes.append(gpa, switch (entry.kind) {
                .file => 'f',
                .directory => 'd',
                .symlink => 'l',
            });
            try bytes.appendSlice(gpa, entry.path);
            try bytes.append(gpa, 0);
        }
        return bytes.toOwnedSlice(gpa);
    }
};
const Name = struct { raw: []u8, kind: std.Io.File.Kind };
const Walker = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    options: Options,
    context: types.Context,
    ignore: ignores.Stack,
    started: std.Io.Timestamp,
    entries: std.ArrayList(Entry) = .empty,
    bytes: u64 = 0,
    truncated: bool = false,
    fn walk(self: *Walker, full: []const u8, relative: []const u8) anyerror!void {
        if (self.context.aborted()) return error.Canceled;
        const mark = self.ignore.mark();
        defer self.ignore.restore(mark);
        if (self.options.gitignore) try self.ignore.enter(full);
        const native_full = try nativePath(self.gpa, self.io, full);
        defer self.gpa.free(native_full);
        var dir = std.Io.Dir.cwd().openDir(self.io, native_full, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        var names: std.ArrayList(Name) = .empty;
        defer {
            for (names.items) |name| self.gpa.free(name.raw);
            names.deinit(self.gpa);
        }
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch null) |entry| {
            if (self.context.aborted()) return error.Canceled;
            const name = try self.gpa.dupe(u8, entry.name);
            errdefer self.gpa.free(name);
            try names.append(self.gpa, .{ .raw = name, .kind = entry.kind });
        }
        std.mem.sort(Name, names.items, {}, struct {
            fn less(_: void, a: Name, b: Name) bool {
                return std.mem.lessThan(u8, a.raw, b.raw);
            }
        }.less);
        for (names.items) |name| {
            if (self.context.aborted()) return error.Canceled;
            if (std.mem.eql(u8, name.raw, ".git")) continue;
            var excluded = false;
            for (self.options.exclude) |skip| if (std.mem.eql(u8, skip, name.raw)) {
                excluded = true;
                break;
            };
            if (excluded) continue;
            const child = try std.fs.path.join(self.gpa, &.{ full, name.raw });
            defer self.gpa.free(child);
            // WalkDir preserves the file type already returned by readdir. In particular, re-statting a Windows
            // name through a Win32 path can normalize away trailing spaces and lose a real directory entry.
            const entry_kind = if (name.kind == .unknown) fallback: {
                const native_child = try nativePath(self.gpa, self.io, child);
                defer self.gpa.free(native_child);
                const stat = std.Io.Dir.cwd().statFile(self.io, native_child, .{ .follow_symlinks = false }) catch continue;
                break :fallback stat.kind;
            } else name.kind;
            const kind: types.FileKind = switch (entry_kind) {
                .file => .file,
                .directory => .directory,
                .sym_link => .symlink,
                else => continue,
            };
            const decision = if (self.options.gitignore) try self.ignore.decision(child, kind == .directory) else null;
            if (decision orelse false) continue;
            if (decision == null and !self.options.hidden and ((name.raw.len > 0 and name.raw[0] == '.') or try windowsHidden(self.gpa, self.io, child))) continue;
            const decoded = try decodeName(self.gpa, name.raw);
            defer self.gpa.free(decoded);
            const path = if (relative.len == 0) try self.gpa.dupe(u8, decoded) else try std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ relative, decoded });
            var transferred = false;
            defer if (!transferred) self.gpa.free(path);
            const size = path.len + 2;
            const elapsed = std.Io.Clock.awake.now(self.io).nanoseconds - self.started.nanoseconds;
            if (self.entries.items.len >= self.options.maxEntries or size > @min(self.options.maxBytes, maximum_payload) -| self.bytes or elapsed > @as(i128, self.options.timeoutMs) * std.time.ns_per_ms) {
                self.truncated = true;
                return;
            }
            try self.entries.append(self.gpa, .{ .path = path, .kind = kind });
            transferred = true;
            self.bytes += size;
            if (kind == .directory) try self.walk(child, path);
            if (self.truncated) return;
        }
    }
};
fn windowsHidden(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !bool {
    if (builtin.os.tag != .windows) return false;
    const Native = struct {
        extern "kernel32" fn GetFileAttributesW([*:0]const u16) callconv(.winapi) u32;
    };
    const native = try nativePath(gpa, io, path);
    defer gpa.free(native);
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, native);
    defer gpa.free(wide);
    const attributes = Native.GetFileAttributesW(wide.ptr);
    return attributes != 0xffffffff and attributes & 2 != 0;
}
fn nativePath(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    if (builtin.os.tag != .windows or std.mem.startsWith(u8, path, "\\\\?\\") or std.mem.startsWith(u8, path, "\\\\.\\")) return gpa.dupe(u8, path);
    const absolute = try @import("path.zig").absoluteCwd(gpa, io, path);
    defer gpa.free(absolute);
    const result = if (std.mem.startsWith(u8, absolute, "\\\\")) try std.fmt.allocPrint(gpa, "\\\\?\\UNC\\{s}", .{absolute[2..]}) else try std.fmt.allocPrint(gpa, "\\\\?\\{s}", .{absolute});
    for (result) |*byte| if (byte.* == '/') {
        byte.* = '\\';
    };
    return result;
}
pub fn decodePath(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const Sink = struct {
        gpa: std.mem.Allocator,
        bytes: std.ArrayList(u8) = .empty,
        pub fn codepoint(self: *@This(), scalar: u21) !void {
            var encoded: [4]u8 = undefined;
            const n = try std.unicode.utf8Encode(scalar, &encoded);
            try self.bytes.appendSlice(self.gpa, encoded[0..n]);
        }
    };
    var sink: Sink = .{ .gpa = gpa };
    errdefer sink.bytes.deinit(gpa);
    var decoder: @import("decode.zig").Decoder = .{ .drop_initial_bom = false };
    try decoder.push(bytes, &sink);
    try decoder.finish(&sink);
    return sink.bytes.toOwnedSlice(gpa);
}
fn decodeName(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    if (builtin.os.tag != .windows) return decodePath(gpa, bytes);
    // Windows OsStr::to_string_lossy replaces each unpaired UTF-16 surrogate once. The native iterator's WTF-8
    // representation encodes that surrogate as three bytes; a UTF-8 decoder would replace those three separately.
    const result = try gpa.dupe(u8, bytes);
    var index: usize = 0;
    while (index + 2 < result.len) : (index += 1) {
        if (result[index] == 0xed and result[index + 1] >= 0xa0 and result[index + 1] <= 0xbf and result[index + 2] >= 0x80 and result[index + 2] <= 0xbf) {
            @memcpy(result[index..][0..3], "\xef\xbf\xbd");
            index += 2;
        }
    }
    return result;
}
pub fn list(gpa: std.mem.Allocator, io: std.Io, root: []const u8, home: ?[]const u8, options: Options, context: types.Context) !Listing {
    if (root.len == 0) return error.FileNotFound;
    if (std.mem.indexOfScalar(u8, root, 0) != null) return error.NulPath;
    const absolute = try @import("path.zig").absoluteCwd(gpa, io, root);
    defer gpa.free(absolute);
    const native_root = try nativePath(gpa, io, absolute);
    defer gpa.free(native_root);
    const stat = std.Io.Dir.cwd().statFile(io, native_root, .{}) catch |err| {
        if (builtin.os.tag == .windows and (err == error.BadPathName or err == error.InvalidArgument)) return error.FileNotFound;
        return err;
    };
    if (stat.kind != .directory) return error.NotDir;
    var walker: Walker = .{ .gpa = gpa, .io = io, .options = options, .context = context, .ignore = try ignores.Stack.init(gpa, io, absolute, home, options.gitignore), .started = std.Io.Clock.awake.now(io) };
    defer walker.ignore.deinit();
    errdefer {
        for (walker.entries.items) |entry| gpa.free(entry.path);
        walker.entries.deinit(gpa);
    }
    try walker.walk(absolute, "");
    return .{ .entries = try walker.entries.toOwnedSlice(gpa), .truncated = walker.truncated };
}

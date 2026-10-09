//! Project instruction selection and linked-worktree scope follow Pi f1b2e77f.
const std = @import("std");
const encoding = @import("../extensions/binary_encoding.zig");
pub const File = struct {
    path: []u8,
    content: []u8,
    pub fn deinit(self: *File, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.content);
    }
};
pub const Files = struct {
    items: []File,
    pub fn deinit(self: *Files, gpa: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(gpa);
        gpa.free(self.items);
    }
};
fn absolute(a: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return std.fs.path.resolve(a, &.{path});
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try std.Io.Dir.cwd().realPath(io, &buffer);
    return std.fs.path.resolve(a, &.{ buffer[0..length], path });
}
fn canonical(a: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().realPathFileAlloc(io, path, a) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        return a.dupe(u8, path);
    };
}
fn bytes(a: std.mem.Allocator, io: std.Io, path: []const u8) !?[]u8 {
    const info = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = true }) catch return null;
    if (info.kind != .file) return null;
    return std.Io.Dir.cwd().readFileAlloc(io, path, a, .unlimited) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        return null;
    };
}
fn selected(gpa: std.mem.Allocator, io: std.Io, directory: []const u8) !?File {
    for ([_][]const u8{ "AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD" }) |name| {
        const path = try std.fs.path.join(gpa, &.{ directory, name });
        errdefer gpa.free(path);
        const raw = (try bytes(gpa, io, path)) orelse {
            gpa.free(path);
            continue;
        };
        defer gpa.free(raw);
        const decoded = try encoding.decode(gpa, raw, .utf8);
        defer gpa.free(decoded);
        const text = if (std.mem.startsWith(u8, decoded, "\xef\xbb\xbf")) decoded[3..] else decoded;
        return .{ .path = path, .content = try gpa.dupe(u8, text) };
    }
    return null;
}
fn exists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = true }) catch return false;
    return true;
}
fn trim(text: []const u8) []const u8 {
    return @import("../mcp/codemode_declarations.zig").trimJs(text);
}
fn shadowed(a: std.mem.Allocator, io: std.Io, cwd: []const u8) !?[]const u8 {
    var directory: []const u8 = cwd;
    while (true) {
        const git = try std.fs.path.join(a, &.{ directory, ".git" });
        const info = std.Io.Dir.cwd().statFile(io, git, .{ .follow_symlinks = true }) catch null;
        if (info) |value| {
            var common: ?[]const u8 = null;
            if (value.kind == .file) {
                if (try bytes(a, io, git)) |body| {
                    const text = trim(body);
                    if (std.mem.startsWith(u8, text, "gitdir: ")) {
                        const git_dir = try std.fs.path.resolve(a, &.{ directory, trim(text[8..]) });
                        if (!exists(io, try std.fs.path.join(a, &.{ git_dir, "HEAD" }))) return null;
                        const common_path = try std.fs.path.join(a, &.{ git_dir, "commondir" });
                        common = if (try bytes(a, io, common_path)) |common_body| try std.fs.path.resolve(a, &.{ git_dir, trim(common_body) }) else git_dir;
                    }
                }
            } else if (value.kind == .directory) {
                if (!exists(io, try std.fs.path.join(a, &.{ git, "HEAD" }))) return null;
                common = git;
            }
            if (common) |common_path| {
                const common_real = try canonical(a, io, common_path);
                const worktree_real = try canonical(a, io, directory);
                const main = std.fs.path.dirname(common_real) orelse return null;
                const prefix = try std.fmt.allocPrint(a, "{s}{c}", .{ main, std.fs.path.sep });
                if (!std.mem.startsWith(u8, worktree_real, prefix)) return null;
                const main_git = try canonical(a, io, try std.fs.path.join(a, &.{ main, ".git" }));
                if (!std.mem.eql(u8, main_git, common_real)) return null;
                if (try selected(a, io, worktree_real)) |own| return try std.fs.path.join(a, &.{ main, std.fs.path.basename(own.path) });
                return null;
            }
        }
        const parent = std.fs.path.dirname(directory) orelse return null;
        if (std.mem.eql(u8, parent, directory)) return null;
        directory = parent;
    }
}
pub fn load(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8, agent_dir: ?[]const u8, include_project: bool) !Files {
    var scratch: std.heap.ArenaAllocator = .init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    var output: std.ArrayList(File) = .empty;
    errdefer {
        for (output.items) |*item| item.deinit(gpa);
        output.deinit(gpa);
    }
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    if (agent_dir) |path| {
        const directory = try absolute(a, io, path);
        if (try selected(gpa, io, directory)) |item| {
            var owned = item;
            errdefer owned.deinit(gpa);
            try seen.put(a, try a.dupe(u8, item.path), {});
            try output.append(gpa, item);
        }
    }
    const global_count = output.items.len;
    if (include_project) {
        var directory: []const u8 = try absolute(a, io, cwd);
        const hidden = try shadowed(a, io, directory);
        while (true) {
            if (try selected(gpa, io, directory)) |item| {
                var owned = item;
                var transferred = false;
                defer if (!transferred) owned.deinit(gpa);
                const identity = if (hidden != null) try std.fs.path.join(a, &.{ try canonical(a, io, directory), std.fs.path.basename(item.path) }) else "";
                if (!(hidden != null and std.mem.eql(u8, hidden.?, identity)) and !seen.contains(item.path)) {
                    try seen.put(a, try a.dupe(u8, item.path), {});
                    try output.insert(gpa, global_count, item);
                    transferred = true;
                }
            }
            const parent = std.fs.path.dirname(directory) orelse break;
            if (std.mem.eql(u8, parent, directory)) break;
            directory = parent;
        }
    }
    return .{ .items = try output.toOwnedSlice(gpa) };
}

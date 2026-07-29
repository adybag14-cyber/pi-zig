//! Discover SKILL.md under skills directories.
const std = @import("std");
const Io = std.Io;

pub const Skill = struct {
    name: []const u8,
    path: []const u8,
    content: []const u8,

    pub fn deinit(self: *Skill, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.path);
        gpa.free(self.content);
        self.* = undefined;
    }
};

/// Search:
/// - ~/.pi/agent/skills/<name>/SKILL.md
/// - <cwd>/.pi/skills/<name>/SKILL.md (when trust_project)
/// - <cwd>/.agents/skills/<name>/SKILL.md (when trust_project)
/// - package skills dirs passed in package_skill_dirs
pub fn discover(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    agent_dir: ?[]const u8,
    package_skill_dirs: []const []const u8,
) ![]Skill {
    return discoverTrusted(gpa, io, cwd, agent_dir, package_skill_dirs, true);
}

pub fn discoverTrusted(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    agent_dir: ?[]const u8,
    package_skill_dirs: []const []const u8,
    trust_project: bool,
) ![]Skill {
    var skills: std.ArrayList(Skill) = .empty;
    errdefer {
        for (skills.items) |*s| s.deinit(gpa);
        skills.deinit(gpa);
    }

    if (agent_dir) |ad| {
        const p = try std.fs.path.join(gpa, &.{ ad, "skills" });
        defer gpa.free(p);
        try scanSkillsDir(gpa, io, p, &skills);
    }

    if (trust_project) {
        {
            const p = try std.fs.path.join(gpa, &.{ cwd, ".pi", "skills" });
            defer gpa.free(p);
            try scanSkillsDir(gpa, io, p, &skills);
        }
        {
            const p = try std.fs.path.join(gpa, &.{ cwd, ".agents", "skills" });
            defer gpa.free(p);
            try scanSkillsDir(gpa, io, p, &skills);
        }
    }

    for (package_skill_dirs) |psd| {
        try scanSkillsDir(gpa, io, psd, &skills);
    }

    return try skills.toOwnedSlice(gpa);
}

fn scanSkillsDir(gpa: std.mem.Allocator, io: Io, dir_path: []const u8, out: *std.ArrayList(Skill)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const skill_path = try std.fs.path.join(gpa, &.{ dir_path, entry.name, "SKILL.md" });
        defer gpa.free(skill_path);
        const content = std.Io.Dir.cwd().readFileAlloc(io, skill_path, gpa, .limited(512 * 1024)) catch continue;
        errdefer gpa.free(content);
        try out.append(gpa, .{
            .name = try gpa.dupe(u8, entry.name),
            .path = try gpa.dupe(u8, skill_path),
            .content = content,
        });
    }
}

/// Keep only skills whose names appear in `allow`. Empty `allow` keeps all.
/// Takes ownership of `skills` slice and frees non-matching entries.
pub fn filterByNames(gpa: std.mem.Allocator, skills: []Skill, allow: []const []const u8) ![]Skill {
    if (allow.len == 0) return skills;
    var kept: std.ArrayList(Skill) = .empty;
    errdefer {
        for (kept.items) |*s| s.deinit(gpa);
        kept.deinit(gpa);
    }
    for (skills) |s| {
        var match = false;
        for (allow) |name| {
            if (std.mem.eql(u8, s.name, name)) {
                match = true;
                break;
            }
        }
        if (match) {
            try kept.append(gpa, s);
        } else {
            var mut = s;
            mut.deinit(gpa);
        }
    }
    gpa.free(skills);
    return try kept.toOwnedSlice(gpa);
}

/// Build a short skills summary for the system prompt.
pub fn summarize(gpa: std.mem.Allocator, skills: []const Skill) ![]u8 {
    if (skills.len == 0) return try gpa.dupe(u8, "");
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "# Available skills\n");
    for (skills) |s| {
        // First non-empty line as description
        var desc: []const u8 = s.name;
        var lines = std.mem.splitScalar(u8, s.content, '\n');
        while (lines.next()) |line| {
            const t = std.mem.trim(u8, line, " \t\r#");
            if (t.len > 0) {
                desc = t;
                break;
            }
        }
        const line = try std.fmt.allocPrint(gpa, "- **{s}**: {s}\n", .{ s.name, truncate(desc, 120) });
        defer gpa.free(line);
        try out.appendSlice(gpa, line);
    }
    return try out.toOwnedSlice(gpa);
}

fn truncate(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

test "discover skills from temp dir" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const skill_dir = try std.fs.path.join(gpa, &.{ root, ".pi", "skills", "demo" });
    defer gpa.free(skill_dir);
    try std.Io.Dir.cwd().createDirPath(io, skill_dir);
    const skill_file = try std.fs.path.join(gpa, &.{ skill_dir, "SKILL.md" });
    defer gpa.free(skill_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = skill_file, .data = "# Demo skill\nDoes demo things.\n" });

    const skills = try discover(gpa, io, root, null, &.{});
    defer {
        for (skills) |*s| {
            var mut = s.*;
            mut.deinit(gpa);
        }
        gpa.free(skills);
    }
    try std.testing.expectEqual(@as(usize, 1), skills.len);
    try std.testing.expectEqualStrings("demo", skills[0].name);

    const sum = try summarize(gpa, skills);
    defer gpa.free(sum);
    try std.testing.expect(std.mem.indexOf(u8, sum, "demo") != null);
}

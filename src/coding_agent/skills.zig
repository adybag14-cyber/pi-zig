//! Discover SKILL.md under skills directories.
const std = @import("std");
const Io = std.Io;

pub const Skill = struct {
    name: []const u8,
    description: []const u8,
    path: []const u8,
    content: []const u8,
    disable_model_invocation: bool = false,

    pub fn deinit(self: *Skill, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.description);
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
    return loadTrusted(gpa, io, cwd, agent_dir, trust_project, package_skill_dirs, true);
}

/// Load exact skill files/directories supplied by the shared resource resolver.
/// `include_defaults=false` prevents a second unconditional scan after settings
/// filters have already selected the authoritative top-level resource set.
pub fn loadTrusted(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    agent_dir: ?[]const u8,
    trust_project: bool,
    explicit_paths: []const []const u8,
    include_defaults: bool,
) ![]Skill {
    var skills: std.ArrayList(Skill) = .empty;
    errdefer {
        for (skills.items) |*s| s.deinit(gpa);
        skills.deinit(gpa);
    }

    if (include_defaults) {
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
    }

    for (explicit_paths) |path| try scanSkillPath(gpa, io, path, &skills);
    return try skills.toOwnedSlice(gpa);
}

fn scanSkillPath(gpa: std.mem.Allocator, io: Io, path: []const u8, out: *std.ArrayList(Skill)) !void {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return;
    if (stat.kind == .file) {
        if (std.mem.eql(u8, std.fs.path.basename(path), "SKILL.md")) {
            const parent = std.fs.path.dirname(path) orelse ".";
            try loadSkillFile(gpa, io, path, std.fs.path.basename(parent), out);
        }
        return;
    }
    if (stat.kind != .directory) return;

    // A manifest may name a single skill directory rather than its parent
    // collection. Prefer that exact skill when SKILL.md exists.
    const direct = try std.fs.path.join(gpa, &.{ path, "SKILL.md" });
    defer gpa.free(direct);
    if (std.Io.Dir.cwd().statFile(io, direct, .{})) |direct_stat| {
        if (direct_stat.kind == .file) {
            try loadSkillFile(gpa, io, direct, std.fs.path.basename(path), out);
            return;
        }
    } else |_| {}

    try scanSkillsDir(gpa, io, path, out);
}

fn scanSkillsDir(gpa: std.mem.Allocator, io: Io, dir_path: []const u8, out: *std.ArrayList(Skill)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const skill_path = try std.fs.path.join(gpa, &.{ dir_path, entry.name, "SKILL.md" });
        defer gpa.free(skill_path);
        try loadSkillFile(gpa, io, skill_path, entry.name, out);
    }
}

fn loadSkillFile(gpa: std.mem.Allocator, io: Io, skill_path: []const u8, fallback_name: []const u8, out: *std.ArrayList(Skill)) !void {
    const content = std.Io.Dir.cwd().readFileAlloc(io, skill_path, gpa, .limited(512 * 1024)) catch return;
    errdefer gpa.free(content);
    const fm = parseFrontmatter(content);
    const description = fm.description orelse {
        gpa.free(content);
        return;
    };
    if (std.mem.trim(u8, description, " \t\r\n").len == 0) {
        gpa.free(content);
        return;
    }
    try out.append(gpa, .{
        .name = try gpa.dupe(u8, fm.name orelse fallback_name),
        .description = try gpa.dupe(u8, description),
        .path = try gpa.dupe(u8, skill_path),
        .content = content,
        .disable_model_invocation = fm.disable_model_invocation,
    });
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
    var visible: usize = 0;
    for (skills) |skill| {
        if (!skill.disable_model_invocation) visible += 1;
    }
    if (visible == 0) return try gpa.dupe(u8, "");

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(
        gpa,
        "\n\nThe following skills provide specialized instructions for specific tasks.\n" ++
            "Use the read tool to load a skill's file when the task matches its description.\n" ++
            "When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.\n\n" ++
            "<available_skills>\n",
    );
    for (skills) |skill| {
        if (skill.disable_model_invocation) continue;
        try out.appendSlice(gpa, "  <skill>\n    <name>");
        try appendXmlEscaped(gpa, &out, skill.name);
        try out.appendSlice(gpa, "</name>\n    <description>");
        try appendXmlEscaped(gpa, &out, skill.description);
        try out.appendSlice(gpa, "</description>\n    <location>");
        try appendXmlEscaped(gpa, &out, skill.path);
        try out.appendSlice(gpa, "</location>\n  </skill>\n");
    }
    try out.appendSlice(gpa, "</available_skills>");
    return try out.toOwnedSlice(gpa);
}

const Frontmatter = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    disable_model_invocation: bool = false,
};

fn parseFrontmatter(content: []const u8) Frontmatter {
    var result: Frontmatter = .{};
    var lines = std.mem.splitScalar(u8, content, '\n');
    const first = lines.next() orelse return result;
    if (!std.mem.eql(u8, std.mem.trim(u8, first, " \t\r"), "---")) return result;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "---")) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        var value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
            value = value[1 .. value.len - 1];
        }
        if (std.mem.eql(u8, key, "name")) result.name = value;
        if (std.mem.eql(u8, key, "description")) result.description = value;
        if (std.mem.eql(u8, key, "disable-model-invocation")) {
            result.disable_model_invocation = std.ascii.eqlIgnoreCase(value, "true");
        }
    }
    return result;
}

fn appendXmlEscaped(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |c| switch (c) {
        '&' => try out.appendSlice(gpa, "&amp;"),
        '<' => try out.appendSlice(gpa, "&lt;"),
        '>' => try out.appendSlice(gpa, "&gt;"),
        '"' => try out.appendSlice(gpa, "&quot;"),
        '\'' => try out.appendSlice(gpa, "&apos;"),
        else => try out.append(gpa, c),
    };
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
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = skill_file, .data = "---\nname: demo\ndescription: Does demo things.\n---\n# Demo skill\n" });

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

test "skill frontmatter controls prompt visibility and XML escaping" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const visible_dir = try std.fs.path.join(gpa, &.{ root, ".pi", "skills", "fallback-name" });
    defer gpa.free(visible_dir);
    try std.Io.Dir.cwd().createDirPath(io, visible_dir);
    const visible_file = try std.fs.path.join(gpa, &.{ visible_dir, "SKILL.md" });
    defer gpa.free(visible_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = visible_file, .data = "---\nname: xml-skill\ndescription: Use <tags> & safely\n---\nbody\n" });

    const hidden_dir = try std.fs.path.join(gpa, &.{ root, ".pi", "skills", "hidden" });
    defer gpa.free(hidden_dir);
    try std.Io.Dir.cwd().createDirPath(io, hidden_dir);
    const hidden_file = try std.fs.path.join(gpa, &.{ hidden_dir, "SKILL.md" });
    defer gpa.free(hidden_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = hidden_file, .data = "---\ndescription: hidden from model\ndisable-model-invocation: true\n---\nbody\n" });

    const found = try discoverTrusted(gpa, io, root, null, &.{}, true);
    defer {
        for (found) |*skill| {
            var mut = skill.*;
            mut.deinit(gpa);
        }
        gpa.free(found);
    }
    try std.testing.expectEqual(@as(usize, 2), found.len);
    const prompt = try summarize(gpa, found);
    defer gpa.free(prompt);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "<name>xml-skill</name>") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "Use &lt;tags&gt; &amp; safely") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "hidden from model") == null);
}

test "skill without description is not loaded" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const dir = try std.fs.path.join(gpa, &.{ root, ".pi", "skills", "bad" });
    defer gpa.free(dir);
    try std.Io.Dir.cwd().createDirPath(io, dir);
    const file = try std.fs.path.join(gpa, &.{ dir, "SKILL.md" });
    defer gpa.free(file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = "---\nname: bad\n---\nno description\n" });
    const found = try discoverTrusted(gpa, io, root, null, &.{}, true);
    defer gpa.free(found);
    try std.testing.expectEqual(@as(usize, 0), found.len);
}

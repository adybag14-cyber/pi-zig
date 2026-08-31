//! Shared project/global environment for CLI and server agent turns.
//! Owns every slice referenced by AgentConfig for its full lifetime.
const std = @import("std");
const Io = std.Io;
const agent = @import("../agent/root.zig");
const settings_mod = @import("settings.zig");
const context_mod = @import("context.zig");
const skills_mod = @import("skills.zig");
const packages_mod = @import("packages.zig");
const top_level_resources_mod = @import("top_level_resources.zig");
const system_prompt_mod = @import("system_prompt.zig");

pub const Options = struct {
    agent_dir: ?[]const u8 = null,
    trust_project: bool = false,
    include_context_files: bool = true,
    include_skills: bool = true,
    skill_names: []const []const u8 = &.{},
    system_override: ?[]const u8 = null,
    extra_appends: []const []const u8 = &.{},
    thinking_level: ?[]const u8 = null,
    tool_allow: ?[]const []const u8 = null,
    tool_exclude: ?[]const []const u8 = null,
    no_tools: bool = false,
};

pub const ProjectEnvironment = struct {
    gpa: std.mem.Allocator,
    settings: settings_mod.Settings,
    system_prompt: []u8,
    context_prompt: []u8,
    tool_filter: agent.ToolFilter,
    max_turns: usize,
    compaction_enabled: bool,
    compaction_reserve_tokens: u64,
    compaction_keep_recent_tokens: u64,
    branch_summary_reserve_tokens: u64,
    branch_summary_skip_prompt: bool,
    auto_resize_images: bool,
    block_images: bool,
    enable_skill_commands: bool,
    context_count: usize,
    skills_count: usize,
    owned_allow: ?[]const []const u8 = null,
    owned_builtin_allow: ?[]const []const u8 = null,
    owned_exclude: ?[]const []const u8 = null,

    pub fn deinit(self: *ProjectEnvironment) void {
        if (self.owned_allow) |items| freeStringSlice(self.gpa, items);
        if (self.owned_builtin_allow) |items| freeStringSlice(self.gpa, items);
        if (self.owned_exclude) |items| freeStringSlice(self.gpa, items);
        self.gpa.free(self.system_prompt);
        self.gpa.free(self.context_prompt);
        self.settings.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn agentConfig(self: *const ProjectEnvironment) agent.AgentConfig {
        return .{
            .max_turns = self.max_turns,
            .system_prompt = self.system_prompt,
            .context_prompt = self.context_prompt,
            .tool_filter = self.tool_filter,
            .auto_compaction_enabled = self.compaction_enabled,
            .compaction_reserve_tokens = self.compaction_reserve_tokens,
            .compaction_keep_recent_tokens = self.compaction_keep_recent_tokens,
            .branch_summary_reserve_tokens = self.branch_summary_reserve_tokens,
            .branch_summary_skip_prompt = self.branch_summary_skip_prompt,
            .auto_resize_images = self.auto_resize_images,
            .block_images = self.block_images,
            .enable_skill_commands = self.enable_skill_commands,
        };
    }
};

pub fn load(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    opts: Options,
) !ProjectEnvironment {
    var settings = try settings_mod.loadMergeTrusted(gpa, io, opts.agent_dir, cwd, opts.trust_project);
    errdefer settings.deinit(gpa);

    var context_prompt = try gpa.dupe(u8, "");
    errdefer gpa.free(context_prompt);
    var system_prompt = try gpa.dupe(u8, agent.default_system_prompt);
    errdefer gpa.free(system_prompt);
    var context_count: usize = 0;
    var skills_count: usize = 0;

    if (opts.include_context_files) {
        var bundle = try context_mod.discoverTrusted(gpa, io, cwd, opts.agent_dir, opts.trust_project);
        defer bundle.deinit(gpa);
        context_count = bundle.files.len;

        const assembled_context = try context_mod.assembleContextPrompt(gpa, bundle.files);
        gpa.free(context_prompt);
        context_prompt = assembled_context;

        var package_resources = packages_mod.Resources.init(gpa);
        defer package_resources.deinit();
        var top_resources = top_level_resources_mod.Resources.init(gpa);
        defer top_resources.deinit();

        if (opts.agent_dir) |agent_dir| {
            const installed = try packages_mod.listConfigured(gpa, io, agent_dir, cwd, opts.trust_project);
            defer {
                for (installed) |*pkg| pkg.deinit(gpa);
                gpa.free(installed);
            }
            package_resources.deinit();
            package_resources = try packages_mod.resolveResources(gpa, io, installed);
            top_resources.deinit();
            top_resources = try top_level_resources_mod.resolve(gpa, io, agent_dir, cwd, opts.trust_project);
        }

        var skills_summary = try gpa.dupe(u8, "");
        defer gpa.free(skills_summary);
        if (opts.include_skills) {
            var resolved_skill_paths: std.ArrayList([]const u8) = .empty;
            defer resolved_skill_paths.deinit(gpa);
            try resolved_skill_paths.appendSlice(gpa, top_resources.skills.items);
            try resolved_skill_paths.appendSlice(gpa, package_resources.skills.items);
            var discovered = if (opts.agent_dir != null)
                try skills_mod.loadTrusted(gpa, io, cwd, opts.agent_dir, opts.trust_project, resolved_skill_paths.items, false)
            else
                try skills_mod.discoverTrusted(gpa, io, cwd, opts.agent_dir, package_resources.skills.items, opts.trust_project);
            if (opts.skill_names.len > 0) {
                discovered = try skills_mod.filterByNames(gpa, discovered, opts.skill_names);
            }
            defer {
                for (discovered) |*skill| skill.deinit(gpa);
                gpa.free(discovered);
            }
            skills_count = discovered.len;
            const summary = try skills_mod.summarize(gpa, discovered);
            gpa.free(skills_summary);
            skills_summary = summary;
        }

        const assembled_system = try system_prompt_mod.assemble(gpa, .{
            .base_prompt = opts.system_override orelse bundle.system_override orelse agent.default_system_prompt,
            .system_override = opts.system_override orelse bundle.system_override,
            .append_system = bundle.append_system,
            .skills_summary = skills_summary,
            .extra_appends = opts.extra_appends,
            .thinking_level = opts.thinking_level orelse settings.thinking_level,
        });
        gpa.free(system_prompt);
        system_prompt = assembled_system;
    } else if (opts.system_override) |override| {
        const assembled = try system_prompt_mod.assemble(gpa, .{
            .system_override = override,
            .extra_appends = opts.extra_appends,
            .thinking_level = opts.thinking_level orelse settings.thinking_level,
        });
        gpa.free(system_prompt);
        system_prompt = assembled;
    } else if ((opts.thinking_level orelse settings.thinking_level) != null or opts.extra_appends.len > 0) {
        const assembled = try system_prompt_mod.assemble(gpa, .{
            .extra_appends = opts.extra_appends,
            .thinking_level = opts.thinking_level orelse settings.thinking_level,
        });
        gpa.free(system_prompt);
        system_prompt = assembled;
    }

    const owned_allow = if (opts.tool_allow) |items| try dupeStringSlice(gpa, items) else null;
    errdefer if (owned_allow) |items| freeStringSlice(gpa, items);
    const owned_builtin_allow = if (opts.tool_allow == null) try dupeStringSlice(gpa, settings.tools orelse &agent.tools.default_tool_names) else null;
    errdefer if (owned_builtin_allow) |items| freeStringSlice(gpa, items);
    const owned_exclude = if (opts.tool_exclude) |items| try dupeStringSlice(gpa, items) else null;
    errdefer if (owned_exclude) |items| freeStringSlice(gpa, items);

    return .{
        .gpa = gpa,
        .settings = settings,
        .system_prompt = system_prompt,
        .context_prompt = context_prompt,
        .tool_filter = .{
            .allow = owned_allow,
            .builtin_allow = owned_builtin_allow,
            .exclude = owned_exclude,
            .no_tools = opts.no_tools,
        },
        .max_turns = settings.max_turns,
        .compaction_enabled = settings.compaction_enabled orelse true,
        .compaction_reserve_tokens = settings.compaction_reserve_tokens orelse 16_384,
        .compaction_keep_recent_tokens = settings.compaction_keep_recent_tokens orelse 20_000,
        .branch_summary_reserve_tokens = settings.branch_summary_reserve_tokens orelse 16_384,
        .branch_summary_skip_prompt = settings.branch_summary_skip_prompt orelse false,
        .auto_resize_images = settings.auto_resize_images orelse true,
        .block_images = settings.block_images orelse false,
        .enable_skill_commands = settings.enable_skill_commands orelse true,
        .context_count = context_count,
        .skills_count = skills_count,
        .owned_allow = owned_allow,
        .owned_builtin_allow = owned_builtin_allow,
        .owned_exclude = owned_exclude,
    };
}

fn dupeStringSlice(gpa: std.mem.Allocator, src: []const []const u8) ![]const []const u8 {
    var out = try gpa.alloc([]const u8, src.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |item| gpa.free(item);
        gpa.free(out);
    }
    for (src, 0..) |item, i| {
        out[i] = try gpa.dupe(u8, item);
        initialized += 1;
    }
    return out;
}

fn freeStringSlice(gpa: std.mem.Allocator, items: []const []const u8) void {
    for (items) |item| gpa.free(item);
    gpa.free(items);
}

test "project environment owns settings tool filter and prompt resources" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const settings_path = try std.fs.path.join(gpa, &.{ root, ".pi", "settings.json" });
    defer gpa.free(settings_path);
    if (std.fs.path.dirname(settings_path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings_path, .data =
        \\{"tools":["read"],"maxTurns":3,"compaction":{"reserveTokens":12000,"keepRecentTokens":22000}}
    });
    const agents_path = try std.fs.path.join(gpa, &.{ root, "AGENTS.md" });
    defer gpa.free(agents_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents_path, .data = "PROJECT-MARKER" });

    const skill_dir = try std.fs.path.join(gpa, &.{ root, ".pi", "skills", "demo" });
    defer gpa.free(skill_dir);
    try std.Io.Dir.cwd().createDirPath(io, skill_dir);
    const skill_path = try std.fs.path.join(gpa, &.{ skill_dir, "SKILL.md" });
    defer gpa.free(skill_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = skill_path, .data =
        \\---
        \\name: demo
        \\description: Demo project capability
        \\---
        \\body
    });

    var env = try load(gpa, io, root, .{ .trust_project = true });
    defer env.deinit();
    try std.testing.expectEqual(@as(usize, 3), env.max_turns);
    try std.testing.expectEqual(@as(u64, 12_000), env.compaction_reserve_tokens);
    try std.testing.expectEqual(@as(u64, 22_000), env.compaction_keep_recent_tokens);
    try std.testing.expectEqual(@as(u64, 16_384), env.branch_summary_reserve_tokens);
    try std.testing.expect(!env.branch_summary_skip_prompt);
    try std.testing.expectEqual(@as(usize, 1), env.skills_count);
    try std.testing.expect(env.tool_filter.isEnabled("read"));
    try std.testing.expect(!env.tool_filter.isEnabled("write"));
    try std.testing.expect(std.mem.indexOf(u8, env.context_prompt, "PROJECT-MARKER") != null);
    try std.testing.expect(std.mem.indexOf(u8, env.system_prompt, "Demo project capability") != null);
}

test "project environment tool filter remains valid after settings ownership is internal" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const settings_path = try std.fs.path.join(gpa, &.{ root, ".pi", "settings.json" });
    defer gpa.free(settings_path);
    if (std.fs.path.dirname(settings_path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings_path, .data = "{\"tools\":[\"bash\"]}" });

    var env = try load(gpa, io, root, .{ .trust_project = true });
    defer env.deinit();
    // Exercise the borrowed ToolFilter repeatedly; ASan-like allocator checks in
    // std.testing catch accidental settings-owned backing storage regressions.
    try std.testing.expect(env.tool_filter.isEnabled("bash"));
    try std.testing.expect(!env.tool_filter.isEnabled("read"));
}

test "project environment honors disabled top-level skill settings" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const skill_path = try std.fs.path.join(gpa, &.{ agent_dir, "skills", "hidden", "SKILL.md" });
    defer gpa.free(skill_path);
    if (std.fs.path.dirname(skill_path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = skill_path, .data =
        \\---
        \\name: hidden-top-level
        \\description: This top-level skill must remain disabled
        \\---
        \\body
    });
    const settings_path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(settings_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings_path, .data =
        \\{"skills":["-skills/hidden/SKILL.md"]}
    });

    var env = try load(gpa, io, root, .{ .agent_dir = agent_dir, .trust_project = false });
    defer env.deinit();
    try std.testing.expectEqual(@as(usize, 0), env.skills_count);
    try std.testing.expect(std.mem.indexOf(u8, env.system_prompt, "This top-level skill must remain disabled") == null);
}

test "project environment loads manifest-selected package skill file" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const package_root = try std.fs.path.join(gpa, &.{ root, "package" });
    defer gpa.free(package_root);
    const skill_path = try std.fs.path.join(gpa, &.{ package_root, "capability", "SKILL.md" });
    defer gpa.free(skill_path);
    if (std.fs.path.dirname(skill_path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = skill_path, .data =
        \\---
        \\name: package-demo
        \\description: Package manifest skill is active
        \\---
        \\body
    });
    const package_json = try std.fs.path.join(gpa, &.{ package_root, "package.json" });
    defer gpa.free(package_json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = package_json, .data =
        \\{"name":"package-demo","pi":{"skills":["capability/SKILL.md"]}}
    });
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    const packages_json = try std.fs.path.join(gpa, &.{ agent_dir, "packages.json" });
    defer gpa.free(packages_json);
    var package_list_json: std.Io.Writer.Allocating = .init(gpa);
    defer package_list_json.deinit();
    try package_list_json.writer.writeAll("[{\"name\":\"package-demo\",\"path\":");
    try std.json.Stringify.value(package_root, .{}, &package_list_json.writer);
    try package_list_json.writer.writeAll("}]");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = packages_json, .data = package_list_json.written() });

    var env = try load(gpa, io, root, .{ .agent_dir = agent_dir, .trust_project = true });
    defer env.deinit();
    try std.testing.expectEqual(@as(usize, 1), env.skills_count);
    try std.testing.expect(std.mem.indexOf(u8, env.system_prompt, "Package manifest skill is active") != null);
}

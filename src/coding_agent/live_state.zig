//! Mutable live REPL state so slash commands affect subsequent agent turns.
const std = @import("std");
const Io = std.Io;
const agent_loop = @import("../agent/loop.zig");
const context_mod = @import("context.zig");
const skills_mod = @import("skills.zig");
const system_prompt = @import("system_prompt.zig");

/// Live knobs shared by the interactive loop and slash handlers.
pub const LiveState = struct {
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    agent_dir: ?[]const u8,
    trust_project: bool = true,
    thinking: ?[]const u8 = null,

    /// Agent loop config used on every turn (updated in place).
    agent_cfg: *agent_loop.AgentConfig,
    /// Heap-owned system/context strings currently referenced by agent_cfg.
    owned_system: *?[]u8,
    owned_context: *?[]u8,

    /// Display copy of model id (may be env-backed or heap-owned).
    model_display: *?[]const u8,
    /// Points at the live ModelClient storage `.model` field so /model takes effect immediately.
    active_model: ?*[]const u8 = null,

    /// Set true when /model allocated model_display (so we free on replace).
    model_display_owned: *bool,
};

/// Apply `/model <id>` to display + live client storage.
pub fn applyModel(state: *LiveState, new_id: []const u8) !void {
    const owned = try state.gpa.dupe(u8, new_id);
    errdefer state.gpa.free(owned);

    if (state.model_display_owned.*) {
        if (state.model_display.*) |old| state.gpa.free(old);
    }
    state.model_display.* = owned;
    state.model_display_owned.* = true;

    if (state.active_model) |am| {
        am.* = owned;
    }
}

/// Re-read context/skills from disk and update agent_cfg for subsequent turns.
/// Returns a short status line (caller frees).
pub fn applyReload(state: *LiveState) ![]u8 {
    var bundle = try context_mod.discoverTrusted(state.gpa, state.io, state.cwd, state.agent_dir, state.trust_project);
    defer bundle.deinit(state.gpa);

    const skills = try skills_mod.discoverTrusted(state.gpa, state.io, state.cwd, state.agent_dir, &.{}, state.trust_project);
    defer {
        for (skills) |*s| {
            var mut = s.*;
            mut.deinit(state.gpa);
        }
        state.gpa.free(skills);
    }
    const skills_summary = try skills_mod.summarize(state.gpa, skills);
    defer state.gpa.free(skills_summary);

    // Context block
    if (state.owned_context.*) |old| state.gpa.free(old);
    const new_ctx = try context_mod.assembleContextPrompt(state.gpa, bundle.files);
    state.owned_context.* = new_ctx;
    state.agent_cfg.context_prompt = new_ctx;

    // System prompt reassembly (keep base from current system unless SYSTEM.md override)
    if (state.owned_system.*) |old| state.gpa.free(old);
    const new_sys = try system_prompt.assemble(state.gpa, .{
        .base_prompt = agent_loop.default_system_prompt,
        .system_override = bundle.system_override,
        .append_system = bundle.append_system,
        .context_prompt = "", // context stays in agent_cfg.context_prompt
        .skills_summary = skills_summary,
        .thinking_level = state.thinking,
    });
    state.owned_system.* = new_sys;
    state.agent_cfg.system_prompt = new_sys;

    return try std.fmt.allocPrint(
        state.gpa,
        "Reloaded: {d} context file(s), {d} skill(s) — applied to subsequent turns",
        .{ bundle.files.len, skills.len },
    );
}

test "applyModel mutates active client model field" {
    const gpa = std.testing.allocator;
    var display: ?[]const u8 = try gpa.dupe(u8, "old-model");
    defer if (display) |d| gpa.free(d);
    var owned_flag = true;
    var client_model: []const u8 = display.?;
    var cfg = agent_loop.AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);

    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .model_display = &display,
        .active_model = &client_model,
        .model_display_owned = &owned_flag,
    };

    try applyModel(&state, "new-model-id");
    try std.testing.expectEqualStrings("new-model-id", display.?);
    try std.testing.expectEqualStrings("new-model-id", client_model);
    // Same pointer so OpenAI/Anthropic client.model field sees the change
    try std.testing.expect(display.? .ptr == client_model.ptr);
}

test "applyReload updates agent_cfg context from AGENTS.md" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const agents_path = try std.fs.path.join(gpa, &.{ root, "AGENTS.md" });
    defer gpa.free(agents_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents_path, .data = "agents-v1-token" });

    var cfg = agent_loop.AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);
    var display: ?[]const u8 = null;
    var owned_flag = false;

    var state = LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .agent_dir = null,
        .trust_project = true,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .model_display = &display,
        .active_model = null,
        .model_display_owned = &owned_flag,
    };

    const msg1 = try applyReload(&state);
    defer gpa.free(msg1);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "agents-v1-token") != null);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents_path, .data = "agents-v2-UNIQUE-TOKEN" });
    const msg2 = try applyReload(&state);
    defer gpa.free(msg2);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "agents-v2-UNIQUE-TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "agents-v1-token") == null);
}

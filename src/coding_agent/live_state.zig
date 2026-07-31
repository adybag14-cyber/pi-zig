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
    /// Last skills summary (owned) so set_thinking_level can reassemble without dropping skills.
    owned_skills_summary: *?[]u8,

    /// Display copy of model id (may be env-backed or heap-owned).
    model_display: *?[]const u8,
    /// Points at the live ModelClient storage `.model` field so /model takes effect immediately.
    active_model: ?*[]const u8 = null,

    /// Set true when /model allocated model_display (so we free on replace).
    model_display_owned: *bool,

    /// Optional live client pool for provider switches (RPC /model).
    client_pool: ?*ClientPool = null,
    provider_name: ?*?[]const u8 = null,
};

/// Holds concrete provider clients and a mutable ModelClient used by agent runs.
pub const ClientPool = struct {
    gpa: std.mem.Allocator,
    io: Io,
    openai: ?@import("../ai/openai.zig").OpenAIClient = null,
    anthropic: ?@import("../ai/anthropic.zig").AnthropicClient = null,
    google: ?@import("../ai/google.zig").GoogleClient = null,
    /// Cached API keys (not owned if from env; owned if from credentials dupe).
    openai_key: ?[]const u8 = null,
    anthropic_key: ?[]const u8 = null,
    google_key: ?[]const u8 = null,
    openai_base: []const u8 = "https://api.openai.com/v1",
    /// Live client handle (updated on switch).
    client: @import("../ai/root.zig").ModelClient = undefined,
    active_provider: @import("../ai/providers.zig").Provider = .openai,
    /// Owned model id string used by the active storage.
    model_owned: ?[]u8 = null,
    /// Provider API thinking budgets (wired into OpenAI/Anthropic request bodies).
    thinking: @import("../ai/root.zig").ThinkingLevel = .off,
    /// Shared cooperative abort flag for mid-HTTP SSE cancel + bash kill.
    abort_flag: ?*bool = null,

    pub fn deinit(self: *ClientPool) void {
        if (self.model_owned) |m| self.gpa.free(m);
        self.* = undefined;
    }

    pub fn setKeys(self: *ClientPool, openai_key: ?[]const u8, anthropic_key: ?[]const u8, google_key: ?[]const u8, openai_base: []const u8) void {
        self.openai_key = openai_key;
        self.anthropic_key = anthropic_key;
        self.google_key = google_key;
        self.openai_base = openai_base;
    }

    pub fn setAbortFlag(self: *ClientPool, flag: ?*bool) void {
        self.abort_flag = flag;
        self.syncClientFields();
    }

    pub fn setThinking(self: *ClientPool, level: @import("../ai/root.zig").ThinkingLevel) void {
        self.thinking = level;
        self.syncClientFields();
    }

    pub fn setThinkingFromString(self: *ClientPool, level: ?[]const u8) void {
        if (level) |s| {
            self.setThinking(@import("../ai/root.zig").ThinkingLevel.fromString(s));
        } else {
            self.setThinking(.off);
        }
    }

    fn syncClientFields(self: *ClientPool) void {
        if (self.openai) |*c| {
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
        }
        if (self.anthropic) |*c| {
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
        }
    }

    /// Switch provider/model and rebuild ModelClient. Returns error if key missing.
    pub fn switchTo(self: *ClientPool, provider: @import("../ai/providers.zig").Provider, model_id: []const u8) !void {
        const providers = @import("../ai/providers.zig");
        if (self.model_owned) |m| self.gpa.free(m);
        self.model_owned = try self.gpa.dupe(u8, model_id);
        const mid = self.model_owned.?;

        const transport = provider.transport();
        switch (transport) {
            .openai, .mock, .openai_compat => {
                // Local Ollama/LM Studio often accept any non-empty key; allow empty → "local"
                const key = self.openai_key orelse "local";
                self.openai = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .api_key = key,
                    .base_url = self.openai_base,
                    .model = mid,
                    .thinking = self.thinking,
                    .abort_flag = self.abort_flag,
                };
                self.client = self.openai.?.client();
                self.active_provider = .openai;
            },
            .anthropic => {
                const key = self.anthropic_key orelse return error.MissingApiKey;
                self.anthropic = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .api_key = key,
                    .base_url = providers.defaultBaseUrl(.anthropic),
                    .model = mid,
                    .thinking = self.thinking,
                    .abort_flag = self.abort_flag,
                };
                self.client = self.anthropic.?.client();
                self.active_provider = .anthropic;
            },
            .google => {
                const key = self.google_key orelse return error.MissingApiKey;
                self.google = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .api_key = key,
                    .base_url = providers.defaultBaseUrl(.google),
                    .model = mid,
                };
                self.client = self.google.?.client();
                self.active_provider = .google;
            },
        }
    }

    pub fn modelPtr(self: *ClientPool) *[]const u8 {
        return switch (self.active_provider) {
            .openai, .mock, .openai_compat => &self.openai.?.model,
            .anthropic => &self.anthropic.?.model,
            .google => &self.google.?.model,
        };
    }
};

/// Apply `/model <id>` to display + live client storage.
/// If id looks like `provider/model` or maps to another provider in catalog, rebuild client.
pub fn applyModel(state: *LiveState, new_id: []const u8) !void {
    const providers = @import("../ai/providers.zig");

    var provider_override: ?providers.Provider = null;
    var model_id = new_id;
    if (std.mem.indexOfScalar(u8, new_id, '/')) |slash| {
        if (providers.Provider.fromString(new_id[0..slash])) |p| {
            provider_override = p;
            model_id = new_id[slash + 1 ..];
        }
    } else {
        // Infer from known catalog
        for (providers.known_models) |m| {
            if (std.mem.eql(u8, m.id, new_id)) {
                provider_override = m.provider;
                break;
            }
        }
    }

    if (state.client_pool) |pool| {
        if (provider_override) |p| {
            // Always rebuild when pool present so model string is owned by pool
            pool.switchTo(p, model_id) catch {
                // Fall through to display-only update if key missing
            };
            // openai_compat transports as openai — compare transport family
            if (pool.active_provider == p.transport()) {
                state.active_model = pool.modelPtr();
                if (state.provider_name) |pn| pn.* = p.name();
            }
        } else {
            // Same provider, update model id on active storage
            if (state.active_model) |am| {
                const owned = try state.gpa.dupe(u8, model_id);
                if (state.model_display_owned.*) {
                    if (state.model_display.*) |old| state.gpa.free(old);
                }
                // Also update pool model
                if (pool.model_owned) |m| state.gpa.free(m);
                pool.model_owned = try state.gpa.dupe(u8, model_id);
                am.* = pool.model_owned.?;
                state.model_display.* = owned;
                state.model_display_owned.* = true;
                return;
            }
        }
    }

    const owned = try state.gpa.dupe(u8, model_id);
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

/// Reassemble system prompt with thinking level, preserving skills/context.
/// Also pushes ThinkingLevel into ClientPool so provider API budgets update.
pub fn applyThinking(state: *LiveState, level: []const u8) !void {
    state.thinking = level;
    if (state.client_pool) |pool| {
        pool.setThinkingFromString(level);
    }
    if (state.owned_system.*) |old| state.gpa.free(old);
    const skills_sum = if (state.owned_skills_summary.*) |s| s else "";
    const new_sys = try system_prompt.assemble(state.gpa, .{
        .base_prompt = agent_loop.default_system_prompt,
        .system_override = null,
        .append_system = "",
        .context_prompt = "", // context stays in agent_cfg.context_prompt
        .skills_summary = skills_sum,
        .thinking_level = level,
    });
    state.owned_system.* = new_sys;
    state.agent_cfg.system_prompt = new_sys;
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
    // Keep owned copy for later set_thinking_level
    if (state.owned_skills_summary.*) |old| state.gpa.free(old);
    state.owned_skills_summary.* = try state.gpa.dupe(u8, skills_summary);
    // assemble takes reference; free temp after assemble
    defer state.gpa.free(skills_summary);

    // Context block
    if (state.owned_context.*) |old| state.gpa.free(old);
    const new_ctx = try context_mod.assembleContextPrompt(state.gpa, bundle.files);
    state.owned_context.* = new_ctx;
    state.agent_cfg.context_prompt = new_ctx;

    // System prompt reassembly (keep base from current system unless SYSTEM.md override)
    if (state.owned_system.*) |old| state.gpa.free(old);
    const skills_for_prompt = if (state.owned_skills_summary.*) |s| s else "";
    const new_sys = try system_prompt.assemble(state.gpa, .{
        .base_prompt = agent_loop.default_system_prompt,
        .system_override = bundle.system_override,
        .append_system = bundle.append_system,
        .context_prompt = "", // context stays in agent_cfg.context_prompt
        .skills_summary = skills_for_prompt,
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
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |s| gpa.free(s);
    var prov: ?[]const u8 = null;

    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .active_model = &client_model,
        .model_display_owned = &owned_flag,
        .provider_name = &prov,
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
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |s| gpa.free(s);
    var display: ?[]const u8 = null;
    var owned_flag = false;
    var prov: ?[]const u8 = null;

    var state = LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .agent_dir = null,
        .trust_project = true,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .active_model = null,
        .model_display_owned = &owned_flag,
        .provider_name = &prov,
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

//! Builtin slash command handlers for interactive REPL.
const std = @import("std");
const Io = std.Io;
const session_mod = @import("../agent/session.zig");
const compaction = @import("../agent/compaction.zig");
const branch_summary = @import("../agent/branch_summary.zig");
const summarization = @import("../agent/summarization.zig");
const ai = @import("../ai/root.zig");
const export_html = @import("export_html.zig");
const session_share = @import("session_share.zig");
const settings_mod = @import("settings.zig");
const context_mod = @import("context.zig");
const skills_mod = @import("skills.zig");
const packages_mod = @import("packages.zig");
const top_level_resources_mod = @import("top_level_resources.zig");
const tui_render = @import("../tui/render.zig");
const live_state = @import("live_state.zig");
const auth_storage = @import("../auth/storage.zig");
const radius_oauth = @import("../auth/radius_oauth.zig");
const codex_oauth = @import("../auth/openai_codex_oauth.zig");
const copilot_oauth = @import("../auth/github_copilot_oauth.zig");
const anthropic_oauth = @import("../auth/anthropic_oauth.zig");
const kimi_oauth = @import("../auth/kimi_coding_oauth.zig");
const openrouter_oauth = @import("../auth/openrouter_oauth.zig");
const shared_pkce = @import("../auth/pkce.zig");
const xai_oauth = @import("../auth/xai_oauth.zig");
const providers_mod = @import("../ai/providers.zig");
const radius_config = @import("../ai/radius_config.zig");
const radius_refresh = @import("radius_refresh.zig");
const models_file_mod = @import("models_file.zig");
const update_mod = @import("update.zig");
const clipboard_mod = @import("clipboard.zig");
const auth_flow_tui = @import("auth_flow_tui.zig");
const provider_oauth = @import("../extensions/provider_oauth.zig");
const js_runtime = @import("../extensions/js_runtime.zig");

pub const LiveState = live_state.LiveState;

pub const SlashResult = enum {
    handled,
    quit,
    not_command,
    run_prompt,
};

pub const TreeSummaryChoice = struct {
    summarize: bool = false,
    cancelled: bool = false,
    custom_instructions: ?[]u8 = null,

    pub fn deinit(self: *TreeSummaryChoice, gpa: std.mem.Allocator) void {
        if (self.custom_instructions) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const TreeSummaryPromptFn = *const fn (
    context: ?*anyopaque,
    gpa: std.mem.Allocator,
) anyerror!TreeSummaryChoice;

pub const TreeTargetChoice = struct {
    target_id: ?[]u8 = null,
    cancelled: bool = true,

    pub fn deinit(self: *TreeTargetChoice, gpa: std.mem.Allocator) void {
        if (self.target_id) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const TreeTargetPromptFn = *const fn (
    context: ?*anyopaque,
    gpa: std.mem.Allocator,
    sess: *session_mod.Session,
) anyerror!TreeTargetChoice;

pub const ModelTargetChoice = struct {
    reference: ?[]u8 = null,
    cancelled: bool = true,
    persist_default: bool = false,

    pub fn deinit(self: *ModelTargetChoice, gpa: std.mem.Allocator) void {
        if (self.reference) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const ModelTargetPromptFn = *const fn (
    context: ?*anyopaque,
    gpa: std.mem.Allocator,
    initial_search: ?[]const u8,
) anyerror!ModelTargetChoice;

pub const ThinkingTargetChoice = struct {
    level: ?ai.thinking.ThinkingLevel = null,
    cancelled: bool = true,
    persist_default: bool = false,
};

pub const ThinkingTargetPromptFn = *const fn (
    context: ?*anyopaque,
    gpa: std.mem.Allocator,
    initial_search: ?[]const u8,
) anyerror!ThinkingTargetChoice;

pub const SessionTargetChoice = struct {
    path: ?[]u8 = null,
    cancelled: bool = true,

    pub fn deinit(self: *SessionTargetChoice, gpa: std.mem.Allocator) void {
        if (self.path) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const SessionTargetPromptFn = *const fn (
    context: ?*anyopaque,
    gpa: std.mem.Allocator,
    initial_search: ?[]const u8,
) anyerror!SessionTargetChoice;

pub const AuthPromptMode = enum { login, logout };
pub const AuthLoginMethod = enum { api_key, browser, device_code };

pub const AuthTargetChoice = struct {
    provider_id: ?[]u8 = null,
    method: ?AuthLoginMethod = null,
    api_key: ?[]u8 = null,
    cancelled: bool = true,

    pub fn deinit(self: *AuthTargetChoice, gpa: std.mem.Allocator) void {
        if (self.provider_id) |value| gpa.free(value);
        if (self.api_key) |value| {
            @memset(value, 0);
            gpa.free(value);
        }
        self.* = undefined;
    }
};

pub const AuthTargetPromptFn = *const fn (
    context: ?*anyopaque,
    gpa: std.mem.Allocator,
    mode: AuthPromptMode,
    initial_search: ?[]const u8,
) anyerror!AuthTargetChoice;

const SummaryRetryDisplay = struct {
    io: Io,

    fn onEvent(raw: ?*anyopaque, event: summarization.Event) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var buf: [384]u8 = undefined;
        const line = switch (event.kind) {
            .retry_scheduled => std.fmt.bufPrint(&buf, "summary retry {d}/{d} in {d}ms: {s}", .{
                event.attempt,
                event.max_attempts,
                event.delay_ms,
                event.error_message,
            }) catch return,
            .retry_attempt_start => if (event.source == .branch_summary)
                std.fmt.bufPrint(&buf, "retrying branch summary", .{}) catch return
            else
                std.fmt.bufPrint(&buf, "retrying {s} compaction", .{event.reason.wireName()}) catch return,
            .retry_finished => return,
        };
        tui_render.printLine(self.io, line) catch {};
    }
};

pub const SettingsTargetChoice = struct {
    changed: bool = false,
    cancelled: bool = false,
};

pub const SettingsTargetPromptFn = *const fn (
    context: ?*anyopaque,
    gpa: std.mem.Allocator,
) anyerror!SettingsTargetChoice;

pub const SlashContext = struct {
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    sess: *session_mod.Session,
    session_path: ?[]const u8,
    session_dir: ?[]const u8,
    agent_dir: ?[]const u8,
    model: *?[]const u8,
    provider: *?[]const u8,
    thinking: ?*?[]const u8 = null,
    settings_text: []const u8,
    clipboard_options: clipboard_mod.Options = .{},
    trust_project: bool = true,
    /// Non-live callers can explicitly disable skill commands. Live callers
    /// read the current reloadable value from AgentConfig.
    enable_skill_commands: bool = true,
    /// When set, /model and /reload mutate live agent/client state for subsequent turns.
    live: ?*live_state.LiveState = null,
    /// Optional model client for LLM compaction on /compact.
    client: ?ai.ModelClient = null,
    /// Interactive branch-summary choice. Machine-readable and test callers
    /// omit this and retain explicit `/tree ... --summary` behavior.
    tree_summary_prompt_ctx: ?*anyopaque = null,
    tree_summary_prompt_fn: ?TreeSummaryPromptFn = null,
    /// Optional retained selector for interactive `/model`. Machine-readable
    /// callers omit it and retain direct textual model switching.
    model_target_prompt_ctx: ?*anyopaque = null,
    model_target_prompt_fn: ?ModelTargetPromptFn = null,
    thinking_target_prompt_ctx: ?*anyopaque = null,
    thinking_target_prompt_fn: ?ThinkingTargetPromptFn = null,
    /// Optional retained selector for interactive `/settings`. The selector
    /// persists global settings atomically; this handler then performs one
    /// transactional live reload before returning to the editor.
    settings_target_prompt_ctx: ?*anyopaque = null,
    settings_target_prompt_fn: ?SettingsTargetPromptFn = null,
    /// Optional retained selector for bare interactive `/tree`. Machine-readable
    /// callers omit it and keep the textual tree summary fallback.
    tree_target_prompt_ctx: ?*anyopaque = null,
    tree_target_prompt_fn: ?TreeTargetPromptFn = null,
    /// Optional retained selector for `/resume`. The actual live-session swap
    /// is performed by the owning interactive loop after this handler returns,
    /// so every long-lived pointer can be rebound transactionally.
    session_target_prompt_ctx: ?*anyopaque = null,
    session_target_prompt_fn: ?SessionTargetPromptFn = null,
    /// Optional retained authentication/account selector for bare `/login` and
    /// `/logout`. Explicit provider/method commands remain scriptable.
    auth_target_prompt_ctx: ?*anyopaque = null,
    auth_target_prompt_fn: ?AuthTargetPromptFn = null,
    /// Optional fullscreen provider-owned login dialog. Explicit noninteractive
    /// commands omit this and retain plain text instructions.
    auth_flow_ui: ?*auth_flow_tui.Controller = null,
    /// Extension-defined provider OAuth lifecycle and callback owner.
    extension_oauth: ?*provider_oauth.Runtime = null,
    resume_path_out: ?*?[]u8 = null,
};

fn skillCommandsEnabled(ctx: SlashContext) bool {
    if (ctx.live) |live| return live.agent_cfg.enable_skill_commands;
    return ctx.enable_skill_commands;
}

fn bootstrapOptions(ctx: SlashContext) ai.bootstrap_http.Options {
    if (ctx.live) |live| {
        if (live.client_pool) |pool| return pool.bootstrapHttpOptions();
    }
    return .{};
}

fn forwardHookMessages(
    gpa: std.mem.Allocator,
    source: *std.ArrayList([]u8),
    destination: ?*std.ArrayList([]const u8),
) !void {
    if (destination) |queue| {
        try queue.ensureUnusedCapacity(gpa, source.items.len);
        for (source.items) |message| queue.appendAssumeCapacity(message);
        source.clearRetainingCapacity();
        return;
    }
    for (source.items) |message| gpa.free(message);
    source.clearRetainingCapacity();
}

/// Apply actions emitted by manual compaction/tree lifecycle hooks before the
/// slash command returns. This mirrors the original awaited extension-runner
/// boundary instead of deferring mutations until a later agent turn.
fn flushHookActions(ctx: SlashContext) !bool {
    const live = ctx.live orelse return false;
    const callback = live.agent_cfg.flush_runtime_actions_fn orelse return false;
    var active_client: ai.ModelClient = ctx.client orelse if (live.client_pool) |pool| pool.client else return false;
    var steering: std.ArrayList([]u8) = .empty;
    defer {
        for (steering.items) |message| ctx.gpa.free(message);
        steering.deinit(ctx.gpa);
    }
    var followups: std.ArrayList([]u8) = .empty;
    defer {
        for (followups.items) |message| ctx.gpa.free(message);
        followups.deinit(ctx.gpa);
    }
    var stop_requested = false;
    try callback(
        live.agent_cfg.flush_runtime_actions_ctx,
        ctx.gpa,
        ctx.sess,
        live.agent_cfg,
        &active_client,
        &steering,
        &followups,
        &stop_requested,
    );
    try forwardHookMessages(ctx.gpa, &steering, live.agent_cfg.steer_queue);
    try forwardHookMessages(ctx.gpa, &followups, live.agent_cfg.follow_up_queue);
    return stop_requested;
}

fn radiusLoginGateway(gpa: std.mem.Allocator, io: Io, agent_dir: ?[]const u8, provider_id: []const u8) !?[]u8 {
    if (agent_dir) |ad| {
        var file = try models_file_mod.load(gpa, io, ad);
        defer file.deinit();
        if (file.findProvider(provider_id)) |provider| {
            if (provider.oauth == .radius) {
                const base = provider.base_url orelse return error.MissingBaseUrl;
                return try radius_config.gatewayFromApiBase(gpa, base);
            }
        }
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "radius"))
        return try radius_config.normalizeGatewayUrl(gpa, radius_config.DEFAULT_GATEWAY);
    return null;
}

fn finishRadiusOAuthLogin(ctx: SlashContext, agent_dir: []const u8, provider_id: []const u8, gateway: []const u8, token: *const radius_oauth.Token) !void {
    try radius_oauth.persistToken(ctx.gpa, ctx.io, agent_dir, provider_id, token);
    if (ctx.live) |live| if (live.client_pool) |pool| {
        try pool.installOAuthCredential(provider_id, token);
        if (std.ascii.eqlIgnoreCase(pool.active_provider_id, provider_id)) {
            const active_model = pool.modelPtr().*;
            try pool.switchToIdentity(pool.active_provider_id, pool.active_provider, active_model);
            live.active_model = pool.modelPtr();
        }
        if (pool.environ) |environ| {
            if (radius_refresh.refreshWithOptions(ctx.gpa, ctx.io, environ, agent_dir, provider_id, gateway, token.access, bootstrapOptions(ctx))) |catalog_value| {
                var catalog = catalog_value;
                catalog.deinit(ctx.gpa);
                live_state.reloadDynamicRadiusCatalog(live) catch |reload_err| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "Radius OAuth credential stored; cache refreshed, but live catalog reload failed ({s}).", .{@errorName(reload_err)});
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                    return;
                };
                try tui_render.printLine(ctx.io, "Radius OAuth credential stored; live model catalog refreshed.");
            } else |err| {
                const msg = try std.fmt.allocPrint(ctx.gpa, "Radius OAuth credential stored; catalog refresh failed ({s}), cached models remain usable.", .{@errorName(err)});
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
            }
            return;
        }
    };
    try tui_render.printLine(ctx.io, "Radius OAuth credential stored in auth.json.");
}

fn finishAnthropicOAuthLogin(ctx: SlashContext, agent_dir: []const u8, token: *const anthropic_oauth.Token) !void {
    try anthropic_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, token);
    if (ctx.live) |live| if (live.client_pool) |pool| {
        try pool.installAnthropicOAuthCredential(token);
        if (std.ascii.eqlIgnoreCase(pool.active_provider_id, "anthropic")) {
            const active_model = pool.modelPtr().*;
            try pool.switchToIdentity("anthropic", .anthropic, active_model);
            live.active_model = pool.modelPtr();
        }
    };
    try tui_render.printLine(ctx.io, "Anthropic OAuth credential stored in auth.json and installed for this process.");
}

fn finishKimiOAuthLogin(ctx: SlashContext, agent_dir: []const u8, token: *const kimi_oauth.Token) !void {
    try kimi_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, token);
    if (ctx.live) |live| if (live.client_pool) |pool| {
        try pool.installKimiOAuthCredential(token);
        if (std.ascii.eqlIgnoreCase(pool.active_provider_id, "kimi-coding")) {
            const active_model = pool.modelPtr().*;
            try pool.switchToIdentity("kimi-coding", .kimi_coding, active_model);
            live.active_model = pool.modelPtr();
        }
    };
    try tui_render.printLine(ctx.io, "Kimi Coding OAuth credential stored in auth.json and installed for this process.");
}

fn finishOpenRouterOAuthLogin(ctx: SlashContext, agent_dir: []const u8, token: *const openrouter_oauth.Token) !void {
    try openrouter_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, token);
    if (ctx.live) |live| if (live.client_pool) |pool| {
        try pool.installOpenRouterOAuthCredential(token);
        if (std.ascii.eqlIgnoreCase(pool.active_provider_id, "openrouter")) {
            const active_model = pool.modelPtr().*;
            try pool.switchToIdentity("openrouter", .openrouter, active_model);
            live.active_model = pool.modelPtr();
        }
    };
    try tui_render.printLine(ctx.io, "OpenRouter OAuth key stored in auth.json and installed for this process.");
}

fn finishXaiOAuthLogin(ctx: SlashContext, agent_dir: []const u8, token: *const xai_oauth.Token) !void {
    try xai_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, token);
    if (ctx.live) |live| if (live.client_pool) |pool| {
        try pool.installXaiOAuthCredential(token);
        if (std.ascii.eqlIgnoreCase(pool.active_provider_id, "xai")) {
            const active_model = pool.modelPtr().*;
            try pool.switchToIdentity("xai", .xai, active_model);
            live.active_model = pool.modelPtr();
        }
    };
    try tui_render.printLine(ctx.io, "xAI OAuth credential stored in auth.json and installed for this process.");
}

fn finishCodexOAuthLogin(ctx: SlashContext, agent_dir: []const u8, token: *const codex_oauth.Token) !void {
    try codex_oauth.persistToken(ctx.gpa, ctx.io, agent_dir, token);
    if (ctx.live) |live| if (live.client_pool) |pool| {
        try pool.installCodexOAuthCredential(token);
        if (std.ascii.eqlIgnoreCase(pool.active_provider_id, "openai-codex")) {
            const active_model = pool.modelPtr().*;
            try pool.switchToIdentity(pool.active_provider_id, pool.active_provider, active_model);
            live.active_model = pool.modelPtr();
        }
    };
    try tui_render.printLine(ctx.io, "OpenAI Codex OAuth credential stored in auth.json and installed for this process.");
}

fn finishGitHubCopilotOAuthLogin(ctx: SlashContext, agent_dir: []const u8, token: *const copilot_oauth.CopilotCredential) !void {
    try copilot_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, token);
    if (ctx.live) |live| if (live.client_pool) |pool| {
        const copilot_was_active = std.ascii.eqlIgnoreCase(pool.active_provider_id, "github-copilot");
        const previous_model = if (copilot_was_active) try ctx.gpa.dupe(u8, pool.modelPtr().*) else null;
        defer if (previous_model) |value| ctx.gpa.free(value);

        try pool.installGitHubCopilotOAuthCredential(token);
        live_state.reloadDynamicAuthCatalog(live) catch |err| {
            const msg = try std.fmt.allocPrint(ctx.gpa, "GitHub Copilot credential stored, but live model filter reload failed ({s}).", .{@errorName(err)});
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
            return;
        };

        if (copilot_was_active) {
            var target: ?providers_mod.ModelInfo = null;
            var fallback: ?providers_mod.ModelInfo = null;
            for (live.model_catalog) |candidate| {
                if (!std.ascii.eqlIgnoreCase(candidate.providerName(), "github-copilot")) continue;
                if (fallback == null) fallback = candidate;
                if (previous_model != null and std.mem.eql(u8, candidate.id, previous_model.?)) {
                    target = candidate;
                    break;
                }
            }
            target = target orelse fallback;
            if (target) |model| {
                const qualified = try std.fmt.allocPrint(ctx.gpa, "github-copilot/{s}", .{model.id});
                defer ctx.gpa.free(qualified);
                try live_state.applyModel(live, qualified);
            } else if (previous_model) |model_id| {
                // Keep the freshly installed token on the existing client even if
                // the account currently advertises no selectable Copilot models.
                try pool.switchToIdentity("github-copilot", pool.active_provider, model_id);
                live.active_model = pool.modelPtr();
            }
        }
    };
    try tui_render.printLine(ctx.io, "GitHub Copilot OAuth credential stored in auth.json and installed for this process.");
}

fn isGitHubCopilotProvider(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "github-copilot");
}

fn isOpenAICodexProvider(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "openai-codex");
}

fn isAnthropicProvider(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "anthropic");
}

fn isKimiCodingProvider(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "kimi-coding");
}

fn isOpenRouterProvider(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "openrouter");
}

fn isXaiProvider(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "xai");
}

fn loginNetworkEnabled(ctx: SlashContext) bool {
    const env = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
    return if (env) |environ| radius_refresh.networkEnabled(environ) else true;
}

fn authDialogBegin(ctx: SlashContext, provider_id: []const u8) bool {
    const ui = ctx.auth_flow_ui orelse return false;
    const title = std.fmt.allocPrint(ctx.gpa, "Login to {s}", .{provider_id}) catch return false;
    defer ctx.gpa.free(title);
    ui.begin(provider_id, title) catch return false;
    return true;
}

fn authDialogClose(ctx: SlashContext) void {
    if (ctx.auth_flow_ui) |ui| ui.close();
}

fn authDialogAbortFlag(ctx: SlashContext) ?*const bool {
    if (ctx.auth_flow_ui) |ui| if (ui.abortFlag()) |flag| return flag;
    return if (ctx.live) |live| live.agent_cfg.abort_flag else null;
}

fn authDialogShowAuth(ctx: SlashContext, active: bool, url: []const u8, instructions: ?[]const u8) !void {
    if (active) {
        try ctx.auth_flow_ui.?.showAuth(url, instructions);
        return;
    }
    try tui_render.printLine(ctx.io, url);
    if (instructions) |line| try tui_render.printLine(ctx.io, line);
}

fn authDialogShowDeviceCode(
    ctx: SlashContext,
    active: bool,
    verification_uri: []const u8,
    user_code: []const u8,
    interval_seconds: ?u64,
    expires_in_seconds: ?u64,
) !void {
    if (active) {
        try ctx.auth_flow_ui.?.showDeviceCode(.{
            .verification_uri = verification_uri,
            .user_code = user_code,
            .interval_seconds = interval_seconds,
            .expires_in_seconds = expires_in_seconds,
        });
        return;
    }
    const line = try std.fmt.allocPrint(ctx.gpa, "Open {s} and enter code {s}.", .{ verification_uri, user_code });
    defer ctx.gpa.free(line);
    try tui_render.printLine(ctx.io, line);
}

fn authDialogWaiting(ctx: SlashContext, active: bool, message: []const u8) !void {
    if (active) {
        try ctx.auth_flow_ui.?.showWaiting(message);
    } else {
        try tui_render.printLine(ctx.io, message);
    }
}

fn authDialogProgress(ctx: SlashContext, active: bool, message: []const u8) !void {
    if (active) {
        try ctx.auth_flow_ui.?.showProgress(message);
    } else {
        try tui_render.printLine(ctx.io, message);
    }
}

fn authDialogPromptWithSecret(ctx: SlashContext, active: bool, message: []const u8, placeholder: ?[]const u8, secret: bool) ![]u8 {
    if (active) return ctx.auth_flow_ui.?.prompt(message, placeholder, secret);
    return error.InteractiveAuthenticationDialogUnavailable;
}

fn authDialogPrompt(ctx: SlashContext, active: bool, message: []const u8, placeholder: ?[]const u8) ![]u8 {
    return authDialogPromptWithSecret(ctx, active, message, placeholder, false);
}

fn authDialogFinish(ctx: SlashContext, active: bool, ok: bool, message: []const u8) void {
    if (active) ctx.auth_flow_ui.?.finish(ok, message);
}

fn authDialogFailMessage(ctx: SlashContext, active: bool, message: []const u8) !void {
    if (active) {
        ctx.auth_flow_ui.?.finish(false, message);
    } else {
        try tui_render.printLine(ctx.io, message);
    }
}

fn authDialogFailure(ctx: SlashContext, active: bool, provider_id: []const u8, err: anyerror) !void {
    if ((active and ctx.auth_flow_ui.?.cancelled()) or err == error.LoginCancelled) {
        try authDialogFailMessage(ctx, active, "Login cancelled.");
        return;
    }
    const message = try std.fmt.allocPrint(ctx.gpa, "{s} login failed: {s}", .{ provider_id, @errorName(err) });
    defer ctx.gpa.free(message);
    try authDialogFailMessage(ctx, active, message);
}

const ExtensionOAuthUiContext = struct {
    slash: SlashContext,
    dialog_active: bool,
};

fn oauthJsonString(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn oauthStringField(object: *const std.json.ObjectMap, key: []const u8, fallback: []const u8) ![]const u8 {
    const value = object.get(key) orelse return fallback;
    if (value != .string) return error.InvalidExtensionOAuthUiPayload;
    return value.string;
}

fn oauthOptionalStringField(object: *const std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value == .null) return null;
    if (value != .string) return error.InvalidExtensionOAuthUiPayload;
    return value.string;
}

fn oauthOptionalU64Field(object: *const std.json.ObjectMap, key: []const u8) !?u64 {
    const value = object.get(key) orelse return null;
    if (value == .null) return null;
    if (value != .integer or value.integer < 0) return error.InvalidExtensionOAuthUiPayload;
    return std.math.cast(u64, value.integer) orelse error.InvalidExtensionOAuthUiPayload;
}

fn extensionOAuthUiRequest(
    raw: ?*anyopaque,
    allocator: std.mem.Allocator,
    method: []const u8,
    args_json: []const u8,
) ![]u8 {
    const state: *ExtensionOAuthUiContext = @ptrCast(@alignCast(raw orelse return error.MissingExtensionOAuthUiContext));
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidExtensionOAuthUiPayload;
    const object = &parsed.value.object;

    if (std.mem.eql(u8, method, "oauth_prompt") or std.mem.eql(u8, method, "oauth_manual_code")) {
        const default_message = if (std.mem.eql(u8, method, "oauth_manual_code")) "Paste the authorization code" else "Enter authentication value";
        const message = try oauthStringField(object, "message", default_message);
        const placeholder = try oauthOptionalStringField(object, "placeholder");
        const secret = if (object.get("secret")) |value| blk: {
            if (value != .bool) return error.InvalidExtensionOAuthUiPayload;
            break :blk value.bool;
        } else false;
        const answer = try authDialogPromptWithSecret(state.slash, state.dialog_active, message, placeholder, secret);
        defer state.slash.gpa.free(answer);
        return oauthJsonString(allocator, answer);
    }

    if (std.mem.eql(u8, method, "oauth_select")) {
        const message = try oauthStringField(object, "message", "Select an authentication option");
        const options_value = object.get("options") orelse return error.InvalidExtensionOAuthUiPayload;
        if (options_value != .array or options_value.array.items.len == 0) return error.InvalidExtensionOAuthUiPayload;

        var prompt: std.Io.Writer.Allocating = .init(state.slash.gpa);
        defer prompt.deinit();
        try prompt.writer.writeAll(message);
        for (options_value.array.items, 0..) |option, index| {
            if (option != .object) return error.InvalidExtensionOAuthUiPayload;
            const label = try oauthStringField(&option.object, "label", "");
            const value = try oauthStringField(&option.object, "value", "");
            if (value.len == 0) return error.InvalidExtensionOAuthUiPayload;
            try prompt.writer.print("\n  {d}. {s}", .{ index + 1, if (label.len > 0) label else value });
            if (try oauthOptionalStringField(&option.object, "description")) |description| {
                if (description.len > 0) try prompt.writer.print(" — {s}", .{description});
            }
        }
        const answer = try authDialogPrompt(state.slash, state.dialog_active, prompt.written(), "Enter a number or value");
        defer state.slash.gpa.free(answer);
        const trimmed = std.mem.trim(u8, answer, " \t\r\n");
        const numeric = std.fmt.parseInt(usize, trimmed, 10) catch 0;
        for (options_value.array.items, 0..) |option, index| {
            const value = (option.object.get("value") orelse unreachable).string;
            const label_value = option.object.get("label");
            const label = if (label_value != null and label_value.? == .string) label_value.?.string else value;
            if ((numeric == index + 1 and numeric != 0) or std.mem.eql(u8, trimmed, value) or std.mem.eql(u8, trimmed, label))
                return oauthJsonString(allocator, value);
        }
        return error.InvalidExtensionOAuthSelection;
    }

    return error.UnsupportedExtensionOAuthUiRequest;
}

fn extensionOAuthUiAction(
    raw: ?*anyopaque,
    allocator: std.mem.Allocator,
    method: []const u8,
    args_json: []const u8,
) !void {
    const state: *ExtensionOAuthUiContext = @ptrCast(@alignCast(raw orelse return error.MissingExtensionOAuthUiContext));
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidExtensionOAuthUiPayload;
    const object = &parsed.value.object;

    if (std.mem.eql(u8, method, "oauth_auth")) {
        const url = try oauthStringField(object, "url", "");
        if (url.len == 0) return error.InvalidExtensionOAuthUiPayload;
        return authDialogShowAuth(state.slash, state.dialog_active, url, try oauthOptionalStringField(object, "instructions"));
    }
    if (std.mem.eql(u8, method, "oauth_device_code")) {
        const verification_uri = try oauthStringField(object, "verificationUri", "");
        const user_code = try oauthStringField(object, "userCode", "");
        if (verification_uri.len == 0 or user_code.len == 0) return error.InvalidExtensionOAuthUiPayload;
        const instructions = try oauthOptionalStringField(object, "instructions");
        const interval_seconds = try oauthOptionalU64Field(object, "intervalSeconds");
        const expires_in_seconds = try oauthOptionalU64Field(object, "expiresInSeconds");
        if (state.dialog_active) {
            try state.slash.auth_flow_ui.?.showDeviceCode(.{
                .verification_uri = verification_uri,
                .user_code = user_code,
                .instructions = instructions,
                .interval_seconds = interval_seconds,
                .expires_in_seconds = expires_in_seconds,
            });
        } else {
            const line = try std.fmt.allocPrint(state.slash.gpa, "Open {s} and enter code {s}.", .{ verification_uri, user_code });
            defer state.slash.gpa.free(line);
            try tui_render.printLine(state.slash.io, line);
            if (instructions) |text| try tui_render.printLine(state.slash.io, text);
        }
        return;
    }
    if (std.mem.eql(u8, method, "oauth_progress")) {
        return authDialogProgress(state.slash, state.dialog_active, try oauthStringField(object, "message", "Working…"));
    }
    return error.UnsupportedExtensionOAuthUiAction;
}

fn extensionOAuthAbortFlag(ctx: SlashContext) ?*bool {
    const flag = authDialogAbortFlag(ctx) orelse return null;
    return @constCast(flag);
}

const TreeArgs = struct {
    target_id: ?[]const u8 = null,
    summarize: bool = false,
    summary_explicit: bool = false,
    custom_instructions: ?[]const u8 = null,
};

fn parseTreeArgs(arg: []const u8) !TreeArgs {
    const trimmed = std.mem.trim(u8, arg, " \t");
    if (trimmed.len == 0) return .{};

    if (std.mem.eql(u8, trimmed, "--summary") or
        (std.mem.startsWith(u8, trimmed, "--summary") and trimmed.len > "--summary".len and
            std.ascii.isWhitespace(trimmed["--summary".len])))
    {
        var rest = std.mem.trimStart(u8, trimmed["--summary".len..], " \t");
        const end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        if (end == 0) return error.MissingTreeTarget;
        const target = rest[0..end];
        rest = std.mem.trimStart(u8, rest[end..], " \t");
        return .{
            .target_id = target,
            .summarize = true,
            .summary_explicit = true,
            .custom_instructions = if (rest.len > 0) rest else null,
        };
    }

    const first_end = std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len;
    const target = trimmed[0..first_end];
    const rest = std.mem.trimStart(u8, trimmed[first_end..], " \t");
    if (rest.len == 0) return .{ .target_id = target };
    if (!(std.mem.eql(u8, rest, "--summary") or
        (std.mem.startsWith(u8, rest, "--summary") and rest.len > "--summary".len and
            std.ascii.isWhitespace(rest["--summary".len])))) return error.InvalidTreeArguments;
    const after = std.mem.trimStart(u8, rest["--summary".len..], " \t");
    return .{
        .target_id = target,
        .summarize = true,
        .summary_explicit = true,
        .custom_instructions = if (after.len > 0) after else null,
    };
}

fn radiusShareToken(ctx: SlashContext) !?[]u8 {
    const agent_dir = ctx.agent_dir orelse return null;
    var store = try auth_storage.AuthStorage.init(ctx.gpa, ctx.io, agent_dir);
    defer store.deinit();
    var credential = (try store.read("radius")) orelse return null;
    defer credential.deinit(ctx.gpa);
    switch (credential) {
        .api_key => return null,
        .oauth => |oauth| {
            const now_ms = std.Io.Clock.real.now(ctx.io).toMilliseconds();
            if (oauth.access.len > 0 and oauth.expires >= now_ms + 5 * 60_000) return try ctx.gpa.dupe(u8, oauth.access);
            if (oauth.refresh.len == 0) return null;
            var token = radius_oauth.refreshWithOptions(ctx.gpa, ctx.io, radius_config.DEFAULT_GATEWAY, oauth.refresh, bootstrapOptions(ctx)) catch return null;
            defer token.deinit(ctx.gpa);
            try radius_oauth.persistToken(ctx.gpa, ctx.io, agent_dir, "radius", &token);
            return try ctx.gpa.dupe(u8, token.access);
        },
    }
}

fn shareTempHtmlPath(ctx: SlashContext) ![]u8 {
    const root = ctx.agent_dir orelse ctx.cwd;
    const directory = try std.fs.path.join(ctx.gpa, &.{ root, "tmp" });
    defer ctx.gpa.free(directory);
    try std.Io.Dir.cwd().createDirPath(ctx.io, directory);
    var random: [8]u8 = undefined;
    try ctx.io.randomSecure(&random);
    const suffix = std.fmt.bytesToHex(random, .lower);
    return std.fmt.allocPrint(ctx.gpa, "{s}{c}session-share-{s}.html", .{ directory, std.fs.path.sep, suffix });
}

fn effectiveShareSystemPrompt(ctx: SlashContext) ![]u8 {
    if (ctx.live) |live| {
        const config = live.agent_cfg;
        if (config.context_prompt.len > 0) return std.fmt.allocPrint(ctx.gpa, "{s}\n\n{s}", .{ config.system_prompt, config.context_prompt });
        return ctx.gpa.dupe(u8, config.system_prompt);
    }
    return ctx.gpa.dupe(u8, @import("../agent/loop.zig").default_system_prompt);
}

fn shareOffline(ctx: SlashContext) bool {
    if (ctx.live) |live| if (live.client_pool) |pool| if (pool.environ) |environ| return update_mod.offline(environ);
    return false;
}

pub fn isBuiltinCommand(line: []const u8) bool {
    if (line.len < 2 or line[0] != '/') return false;
    const rest = line[1..];
    const end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    const command = rest[0..end];
    if (std.mem.startsWith(u8, command, "skill:")) return true;
    const builtin = [_][]const u8{
        "help",    "?",      "skill",  "quit",     "exit",   "session", "new",      "name",    "model",
        "compact", "export", "import", "fork",     "clone",  "tree",    "reload",   "hotkeys", "changelog",
        "copy",    "login",  "logout", "settings", "resume", "share",   "thinking",
    };
    for (builtin) |candidate| if (std.mem.eql(u8, command, candidate)) return true;
    return false;
}

pub fn handle(ctx: SlashContext, line: []const u8) !SlashResult {
    if (line.len == 0 or line[0] != '/') return .not_command;

    const rest = line[1..];
    const space = std.mem.indexOfScalar(u8, rest, ' ');
    const cmd = if (space) |s| rest[0..s] else rest;
    const arg = if (space) |s| std.mem.trim(u8, rest[s + 1 ..], " \t") else "";

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "?")) {
        if (skillCommandsEnabled(ctx)) {
            try tui_render.printLine(ctx.io,
                \\Slash commands:
                \\  /help /quit /exit /session /new /name <n> /model <id> /thinking [level]
                \\  /compact /export [path] /share /import <path> /fork /clone
                \\  /tree [entryId] [--summary [focus]] /skill:<name> /reload /hotkeys /changelog /copy
                \\  /login [provider] [key|browser|device-code] /logout [provider] /settings /resume
            );
        } else {
            try tui_render.printLine(ctx.io,
                \\Slash commands:
                \\  /help /quit /exit /session /new /name <n> /model <id> /thinking [level]
                \\  /compact /export [path] /share /import <path> /fork /clone
                \\  /tree [entryId] [--summary [focus]] /reload /hotkeys /changelog /copy
                \\  /login [provider] [key|browser|device-code] /logout [provider] /settings /resume
            );
        }
        return .handled;
    }

    // /skill:name or /skill name — inject skill body into next prompt (return run_prompt with expanded text is not possible;
    // print body and instruct, OR expand as run_prompt via a special path). We expand by writing into session as user context.
    if (std.mem.startsWith(u8, cmd, "skill:") or std.mem.eql(u8, cmd, "skill")) {
        if (!skillCommandsEnabled(ctx)) {
            try tui_render.printLine(ctx.io, "Skill commands are disabled by enableSkillCommands=false.");
            return .handled;
        }
        const skill_name = if (std.mem.startsWith(u8, cmd, "skill:"))
            cmd["skill:".len..]
        else
            arg;
        if (skill_name.len == 0) {
            try tui_render.printLine(ctx.io, "usage: /skill:<name> or /skill <name>");
            return .handled;
        }
        const skills = try skills_mod.discoverTrusted(ctx.gpa, ctx.io, ctx.cwd, ctx.agent_dir, &.{}, ctx.trust_project);
        defer {
            for (skills) |*s| {
                var mut = s.*;
                mut.deinit(ctx.gpa);
            }
            ctx.gpa.free(skills);
        }
        var found: ?[]const u8 = null;
        var found_body: ?[]const u8 = null;
        for (skills) |s| {
            if (std.mem.eql(u8, s.name, skill_name)) {
                found = s.name;
                found_body = s.content;
                break;
            }
        }
        if (found_body) |body| {
            // Inject as a system-ish user message so the next LLM turn sees full skill body
            const parent = ctx.sess.lastEntryId();
            const injected = try std.fmt.allocPrint(ctx.gpa, "[skill:{s}]\n{s}", .{ skill_name, body });
            defer ctx.gpa.free(injected);
            _ = try ctx.sess.appendMessage(parent, "user", injected, null, null);
            const msg = try std.fmt.allocPrint(ctx.gpa, "Loaded skill `{s}` into session ({d} bytes). Send your request next.", .{ skill_name, body.len });
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        } else {
            const msg = try std.fmt.allocPrint(ctx.gpa, "skill not found: {s}", .{skill_name});
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "quit") or std.mem.eql(u8, cmd, "exit")) {
        return .quit;
    }
    if (std.mem.eql(u8, cmd, "session")) {
        const msg = try std.fmt.allocPrint(ctx.gpa, "session id={s} name={s} messages={d} tip={s}", .{
            ctx.sess.id,
            if (ctx.sess.name.len > 0) ctx.sess.name else "(unnamed)",
            ctx.sess.entries.items.len,
            ctx.sess.lastEntryId() orelse "none",
        });
        defer ctx.gpa.free(msg);
        try tui_render.printLine(ctx.io, msg);
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "new")) {
        for (ctx.sess.entries.items) |*e| e.deinit(ctx.gpa);
        ctx.sess.entries.clearRetainingCapacity();
        ctx.gpa.free(ctx.sess.id);
        ctx.sess.id = try session_mod.generateSessionId(ctx.gpa);
        ctx.sess.next_seq = 1;
        if (ctx.live) |live| if (live.client_pool) |pool| pool.setSessionContext(ctx.sess.id, pool.cache_retention);
        if (ctx.sess.tip_id) |t| {
            ctx.gpa.free(t);
            ctx.sess.tip_id = null;
        }
        try tui_render.printLine(ctx.io, "Started new session.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "name")) {
        if (arg.len == 0) {
            try tui_render.printLine(ctx.io, "usage: /name <session-name>");
            return .handled;
        }
        _ = try ctx.sess.appendSessionInfo(arg);
        try tui_render.printLine(ctx.io, "Session named.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "model")) {
        var target_choice: ?ModelTargetChoice = null;
        defer if (target_choice) |*choice| choice.deinit(ctx.gpa);
        var requested = arg;
        if (ctx.model_target_prompt_fn) |prompt_fn| {
            target_choice = try prompt_fn(
                ctx.model_target_prompt_ctx,
                ctx.gpa,
                if (arg.len > 0) arg else null,
            );
            if (target_choice.?.cancelled or target_choice.?.reference == null) return .handled;
            requested = target_choice.?.reference.?;
        } else if (arg.len == 0) {
            const m = ctx.model.* orelse "(default)";
            const p = ctx.provider.* orelse "";
            const msg = if (p.len > 0)
                try std.fmt.allocPrint(ctx.gpa, "model={s}/{s}", .{ p, m })
            else
                try std.fmt.allocPrint(ctx.gpa, "model={s}", .{m});
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
            return .handled;
        }

        if (ctx.live) |live| {
            live_state.applyModel(live, requested) catch |err| {
                const msg = try std.fmt.allocPrint(ctx.gpa, "Model switch failed: {s}", .{@errorName(err)});
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
                return .handled;
            };
            if (live_state.activeModelInfo(live)) |selected| {
                _ = try ctx.sess.appendModelChange(selected.providerName(), selected.id);
                if (try live_state.applyThinkingForModelSwitch(live, selected, live_state.scopedThinkingForModel(live, selected))) {
                    _ = try ctx.sess.appendThinkingLevelChange(live.thinking orelse "off");
                }
                const msg = try std.fmt.allocPrint(ctx.gpa, "Model switched to {s}/{s}.", .{ selected.providerName(), selected.id });
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
                if (target_choice != null and target_choice.?.persist_default) {
                    const agent_dir = ctx.agent_dir orelse {
                        try tui_render.printLine(ctx.io, "Could not save default model: agent directory is unavailable.");
                        return .handled;
                    };
                    settings_mod.setDefaultModel(ctx.gpa, ctx.io, agent_dir, selected.providerName(), selected.id) catch |err| {
                        const warning = try std.fmt.allocPrint(ctx.gpa, "Could not save default model: {s}", .{@errorName(err)});
                        defer ctx.gpa.free(warning);
                        try tui_render.printLine(ctx.io, warning);
                        return .handled;
                    };
                    try live_state.addPersistedDefaultToScope(live, selected);
                    try tui_render.printLine(ctx.io, "Saved as the global default model.");
                }
            } else {
                const p = ctx.provider.* orelse "";
                const m = ctx.model.* orelse requested;
                if (p.len > 0 and m.len > 0) _ = try ctx.sess.appendModelChange(p, m);
                try tui_render.printLine(ctx.io, "Model updated for subsequent turns.");
            }
        } else {
            // Fallback when no live client is wired (should not happen in main REPL).
            ctx.model.* = try ctx.gpa.dupe(u8, requested);
            try tui_render.printLine(ctx.io, "Model updated for subsequent turns.");
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "thinking")) {
        var target_choice: ?ThinkingTargetChoice = null;
        var parsed: ai.thinking.ThinkingLevel = undefined;
        if (ctx.thinking_target_prompt_fn) |prompt_fn| {
            target_choice = try prompt_fn(ctx.thinking_target_prompt_ctx, ctx.gpa, if (arg.len > 0) arg else null);
            if (target_choice.?.cancelled or target_choice.?.level == null) return .handled;
            parsed = target_choice.?.level.?;
        } else if (arg.len == 0) {
            const current = if (ctx.live) |live| live.thinking orelse "off" else if (ctx.thinking) |value| value.* orelse "off" else "off";
            const message = try std.fmt.allocPrint(ctx.gpa, "thinking={s}", .{current});
            defer ctx.gpa.free(message);
            try tui_render.printLine(ctx.io, message);
            return .handled;
        } else {
            parsed = ai.thinking.ThinkingLevel.parse(arg) orelse {
                try tui_render.printLine(ctx.io, "usage: /thinking off|minimal|low|medium|high|xhigh|max");
                return .handled;
            };
        }
        var effective = parsed;
        if (ctx.live) |live| {
            if (live_state.activeModelInfo(live)) |model| effective = model.clampThinkingLevel(parsed);
            try live_state.applyThinking(live, @tagName(effective));
        }
        _ = try ctx.sess.appendThinkingLevelChange(@tagName(effective));
        if (ctx.thinking) |value| {
            if (value.*) |old| ctx.gpa.free(old);
            value.* = try ctx.gpa.dupe(u8, @tagName(effective));
        }
        const message = try std.fmt.allocPrint(ctx.gpa, "Thinking level set to {s} for this session.", .{@tagName(effective)});
        defer ctx.gpa.free(message);
        try tui_render.printLine(ctx.io, message);
        if (target_choice != null and target_choice.?.persist_default) {
            const agent_dir = ctx.agent_dir orelse {
                try tui_render.printLine(ctx.io, "Could not save default thinking level: agent directory is unavailable.");
                return .handled;
            };
            settings_mod.setEditableScoped(ctx.gpa, ctx.io, agent_dir, ctx.cwd, ctx.trust_project, .global, .thinking_level, .{ .string = @tagName(effective) }) catch |err| {
                const warning = try std.fmt.allocPrint(ctx.gpa, "Could not save default thinking level: {s}", .{@errorName(err)});
                defer ctx.gpa.free(warning);
                try tui_render.printLine(ctx.io, warning);
                return .handled;
            };
            try tui_render.printLine(ctx.io, "Saved as the global default thinking level.");
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "compact")) {
        const compact_settings: compaction.Settings = if (ctx.live) |live| .{
            .enabled = true,
            .reserve_tokens = live.agent_cfg.compaction_reserve_tokens,
            .keep_recent_tokens = live.agent_cfg.compaction_keep_recent_tokens,
        } else .{};
        var retry_display: SummaryRetryDisplay = .{ .io = ctx.io };
        const retry_enabled = if (ctx.live) |live| live.agent_cfg.retry_enabled else true;
        const retry_max_retries = if (ctx.live) |live| live.agent_cfg.retry_max_retries else 3;
        const retry_base_delay_ms = if (ctx.live) |live| live.agent_cfg.retry_base_delay_ms else 2_000;
        const abort_flag = if (ctx.live) |live| live.agent_cfg.abort_flag else null;
        const retry_abort_flag = if (ctx.live) |live| live.agent_cfg.retry_abort_flag else null;
        compaction.compact(ctx.sess, .{
            .io = ctx.io,
            .settings = compact_settings,
            .client = ctx.client,
            .custom_instructions = if (arg.len > 0) arg else null,
            .reason = .manual,
            .retry_enabled = retry_enabled,
            .retry_max_retries = retry_max_retries,
            .retry_base_delay_ms = retry_base_delay_ms,
            .abort_flag = abort_flag,
            .retry_abort_flag = retry_abort_flag,
            .on_retry_event = SummaryRetryDisplay.onEvent,
            .retry_event_ctx = &retry_display,
            .hook_ctx = if (ctx.live) |live| live.agent_cfg.hook_ctx else null,
            .before_hook_fn = if (ctx.live) |live| live.agent_cfg.before_compact_fn else null,
            .after_hook_fn = if (ctx.live) |live| live.agent_cfg.after_compact_fn else null,
            .will_retry = false,
        }) catch |err| {
            const stop_requested = try flushHookActions(ctx);
            const message = if (err == error.CompactionCancelled)
                "Compaction cancelled."
            else
                try std.fmt.allocPrint(ctx.gpa, "Compaction failed: {s}", .{@errorName(err)});
            defer if (err != error.CompactionCancelled) ctx.gpa.free(message);
            try tui_render.printLine(ctx.io, message);
            return if (stop_requested) .quit else .handled;
        };
        if (try flushHookActions(ctx)) return .quit;
        try tui_render.printLine(ctx.io, if (ctx.client != null) "Session compacted (model-assisted when available)." else "Session compacted.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "export")) {
        const path = if (arg.len > 0) arg else "session.html";
        const html = try export_html.exportHtml(ctx.gpa, ctx.sess);
        defer ctx.gpa.free(html);
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = path, .data = html });
        const msg = try std.fmt.allocPrint(ctx.gpa, "Exported to {s}", .{path});
        defer ctx.gpa.free(msg);
        try tui_render.printLine(ctx.io, msg);
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "share")) {
        if (arg.len > 0) {
            try tui_render.printLine(ctx.io, "usage: /share");
            return .handled;
        }
        if (shareOffline(ctx)) {
            try tui_render.printLine(ctx.io, "Session sharing is unavailable while PI_OFFLINE is set.");
            return .handled;
        }
        const system_prompt = try effectiveShareSystemPrompt(ctx);
        defer ctx.gpa.free(system_prompt);
        const filter = if (ctx.live) |live| live.agent_cfg.tool_filter else @import("../agent/tools.zig").ToolFilter{};
        const extras = if (ctx.live) |live| live.agent_cfg.extra_tools_json else "[]";
        const jsonl = session_share.exportForShare(ctx.gpa, ctx.io, ctx.sess, system_prompt, filter, extras) catch |err| {
            const message = try std.fmt.allocPrint(ctx.gpa, "Failed to export session for sharing: {s}", .{@errorName(err)});
            defer ctx.gpa.free(message);
            try tui_render.printLine(ctx.io, message);
            return .handled;
        };
        defer ctx.gpa.free(jsonl);

        const radius_token = radiusShareToken(ctx) catch null;
        defer if (radius_token) |token| {
            @memset(token, 0);
            ctx.gpa.free(token);
        };
        if (radius_token) |token| {
            const url = session_share.uploadRadius(ctx.gpa, ctx.io, token, radius_config.DEFAULT_GATEWAY, jsonl, bootstrapOptions(ctx)) catch |err| {
                const message = try std.fmt.allocPrint(ctx.gpa, "Failed to upload Radius artifact: {s}", .{@errorName(err)});
                defer ctx.gpa.free(message);
                try tui_render.printLine(ctx.io, message);
                return .handled;
            };
            defer ctx.gpa.free(url);
            const message = try std.fmt.allocPrint(ctx.gpa, "Share URL: {s}", .{url});
            defer ctx.gpa.free(message);
            try tui_render.printLine(ctx.io, message);
            return .handled;
        }

        const html = try export_html.exportHtml(ctx.gpa, ctx.sess);
        defer ctx.gpa.free(html);
        const temp_path = try shareTempHtmlPath(ctx);
        defer ctx.gpa.free(temp_path);
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = temp_path, .data = html });
        defer std.Io.Dir.cwd().deleteFile(ctx.io, temp_path) catch {};
        const gist_url = session_share.createPrivateGist(ctx.gpa, ctx.io, ctx.cwd, temp_path) catch |err| {
            const guidance: []const u8 = switch (err) {
                error.GitHubCliNotInstalled => "GitHub CLI is not installed. Install it from https://cli.github.com/",
                error.GitHubCliFailed => "GitHub CLI is not logged in or gist creation failed. Run `gh auth login` first.",
                else => @errorName(err),
            };
            const message = try std.fmt.allocPrint(ctx.gpa, "Failed to create private gist: {s}", .{guidance});
            defer ctx.gpa.free(message);
            try tui_render.printLine(ctx.io, message);
            return .handled;
        };
        defer ctx.gpa.free(gist_url);
        const environ = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
        if (environ) |env| {
            const preview = try session_share.viewerUrl(ctx.gpa, env, gist_url);
            defer ctx.gpa.free(preview);
            const message = try std.fmt.allocPrint(ctx.gpa, "Share URL: {s}\nGist: {s}", .{ preview, gist_url });
            defer ctx.gpa.free(message);
            try tui_render.printLine(ctx.io, message);
        } else {
            const message = try std.fmt.allocPrint(ctx.gpa, "Gist: {s}", .{gist_url});
            defer ctx.gpa.free(message);
            try tui_render.printLine(ctx.io, message);
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "import")) {
        if (arg.len == 0) {
            try tui_render.printLine(ctx.io, "usage: /import <session.jsonl>");
            return .handled;
        }
        const loaded = session_mod.Session.load(ctx.gpa, ctx.io, arg) catch {
            try tui_render.printLine(ctx.io, "import failed");
            return .handled;
        };
        ctx.sess.deinit();
        ctx.sess.* = loaded;
        try tui_render.printLine(ctx.io, "Session imported.");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "fork") or std.mem.eql(u8, cmd, "clone")) {
        const new_id = try session_mod.generateSessionId(ctx.gpa);
        defer ctx.gpa.free(new_id);
        var forked = try ctx.sess.fork(ctx.gpa, new_id);
        if (ctx.session_path) |old_path| try forked.setParentSession(old_path);
        if (ctx.session_dir) |sd| {
            const path = try session_mod.newSessionPath(ctx.gpa, sd, new_id);
            defer ctx.gpa.free(path);
            try forked.save(ctx.io, path);
            const msg = try std.fmt.allocPrint(ctx.gpa, "Forked to {s}", .{path});
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        } else {
            try tui_render.printLine(ctx.io, "Forked in-memory (no session-dir).");
        }
        ctx.sess.deinit();
        ctx.sess.* = forked;
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "tree")) {
        var tree_args = parseTreeArgs(arg) catch {
            try tui_render.printLine(ctx.io, "usage: /tree [entryId] [--summary [focus]]");
            return .handled;
        };
        var prompted_choice: ?TreeSummaryChoice = null;
        defer if (prompted_choice) |*choice| choice.deinit(ctx.gpa);
        var prompted_target: ?TreeTargetChoice = null;
        defer if (prompted_target) |*choice| choice.deinit(ctx.gpa);
        if (tree_args.target_id == null) {
            if (ctx.tree_target_prompt_fn) |prompt_fn| {
                prompted_target = try prompt_fn(ctx.tree_target_prompt_ctx, ctx.gpa, ctx.sess);
                if (prompted_target.?.cancelled or prompted_target.?.target_id == null) {
                    try tui_render.printLine(ctx.io, "Tree navigation cancelled.");
                    return .handled;
                }
                tree_args.target_id = prompted_target.?.target_id.?;
            }
        }
        if (tree_args.target_id) |target_id| {
            const skip_prompt = if (ctx.live) |live| live.agent_cfg.branch_summary_skip_prompt else false;
            if (!tree_args.summary_explicit and !skip_prompt) {
                if (ctx.tree_summary_prompt_fn) |prompt_fn| {
                    prompted_choice = try prompt_fn(ctx.tree_summary_prompt_ctx, ctx.gpa);
                    if (prompted_choice.?.cancelled) {
                        try tui_render.printLine(ctx.io, "Tree navigation cancelled.");
                        return .handled;
                    }
                    tree_args.summarize = prompted_choice.?.summarize;
                    tree_args.custom_instructions = prompted_choice.?.custom_instructions;
                }
            }
            var retry_display: SummaryRetryDisplay = .{ .io = ctx.io };
            const retry_enabled = if (ctx.live) |live| live.agent_cfg.retry_enabled else true;
            const retry_max_retries = if (ctx.live) |live| live.agent_cfg.retry_max_retries else 3;
            const retry_base_delay_ms = if (ctx.live) |live| live.agent_cfg.retry_base_delay_ms else 2_000;
            const abort_flag = if (ctx.live) |live| live.agent_cfg.abort_flag else null;
            const retry_abort_flag = if (ctx.live) |live| live.agent_cfg.retry_abort_flag else null;
            const result = branch_summary.summarizeAndSwitch(ctx.sess, .{
                .io = ctx.io,
                .client = ctx.client,
                .target_id = target_id,
                .summarize = tree_args.summarize,
                .custom_instructions = tree_args.custom_instructions,
                .context_window = if (ctx.live) |live| live.agent_cfg.compaction_context_window else 128_000,
                .reserve_tokens = if (ctx.live) |live| live.agent_cfg.branch_summary_reserve_tokens else 16_384,
                .retry_enabled = retry_enabled,
                .retry_max_retries = retry_max_retries,
                .retry_base_delay_ms = retry_base_delay_ms,
                .abort_flag = abort_flag,
                .retry_abort_flag = retry_abort_flag,
                .on_retry_event = SummaryRetryDisplay.onEvent,
                .retry_event_ctx = &retry_display,
                .hook_ctx = if (ctx.live) |live| live.agent_cfg.hook_ctx else null,
                .before_hook_fn = if (ctx.live) |live| live.agent_cfg.before_tree_fn else null,
                .after_hook_fn = if (ctx.live) |live| live.agent_cfg.after_tree_fn else null,
            }) catch |err| {
                const stop_requested = try flushHookActions(ctx);
                const msg = try std.fmt.allocPrint(ctx.gpa, "Tree navigation failed: {s}", .{@errorName(err)});
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
                return if (stop_requested) .quit else .handled;
            };
            if (try flushHookActions(ctx)) return .quit;
            if (result.cancelled) {
                try tui_render.printLine(ctx.io, "Tree navigation cancelled.");
                return .handled;
            }
            if (result.summary_entry_id) |summary_id| {
                const msg = try std.fmt.allocPrint(ctx.gpa, "Summarized {d} abandoned entries and switched to {s} (summary {s}).", .{
                    result.summarized_entries,
                    target_id,
                    summary_id,
                });
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
            } else if (tree_args.summarize) {
                try tui_render.printLine(ctx.io, "Switched tree position; there was no abandoned content to summarize.");
            } else {
                const msg = try std.fmt.allocPrint(ctx.gpa, "Tip set to {s}", .{ctx.sess.lastEntryId() orelse "root"});
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
            }
            if (result.editor_text) |text| {
                const msg = try std.fmt.allocPrint(ctx.gpa, "Selected user message for re-edit: {s}", .{text});
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
            }
            return .handled;
        }
        const tree = try ctx.sess.treeSummary(ctx.gpa);
        defer ctx.gpa.free(tree);
        try tui_render.writeAll(ctx.io, tree);
        try tui_render.printLine(ctx.io, "(use /tree <id> to set the active tip, or /tree <id> --summary)");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "reload")) {
        if (ctx.live) |live| {
            const msg = try live_state.applyReload(live);
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        } else {
            // Discovery-only fallback (no live agent_cfg) — still reports disk state.
            var bundle = try context_mod.discoverTrusted(ctx.gpa, ctx.io, ctx.cwd, ctx.agent_dir, ctx.trust_project);
            defer bundle.deinit(ctx.gpa);
            var package_resources = packages_mod.Resources.init(ctx.gpa);
            defer package_resources.deinit();
            var top_resources = top_level_resources_mod.Resources.init(ctx.gpa);
            defer top_resources.deinit();
            if (ctx.agent_dir) |agent_dir| {
                const configured = try packages_mod.listConfigured(ctx.gpa, ctx.io, agent_dir, ctx.cwd, ctx.trust_project);
                defer {
                    for (configured) |*package| package.deinit(ctx.gpa);
                    ctx.gpa.free(configured);
                }
                package_resources.deinit();
                package_resources = try packages_mod.resolveResources(ctx.gpa, ctx.io, configured);
                top_resources.deinit();
                top_resources = try top_level_resources_mod.resolve(ctx.gpa, ctx.io, agent_dir, ctx.cwd, ctx.trust_project);
            }
            var resolved_skill_paths: std.ArrayList([]const u8) = .empty;
            defer resolved_skill_paths.deinit(ctx.gpa);
            try resolved_skill_paths.appendSlice(ctx.gpa, top_resources.skills.items);
            try resolved_skill_paths.appendSlice(ctx.gpa, package_resources.skills.items);
            const skills = if (ctx.agent_dir != null)
                try skills_mod.loadTrusted(ctx.gpa, ctx.io, ctx.cwd, ctx.agent_dir, ctx.trust_project, resolved_skill_paths.items, false)
            else
                try skills_mod.discoverTrusted(ctx.gpa, ctx.io, ctx.cwd, ctx.agent_dir, package_resources.skills.items, ctx.trust_project);
            defer {
                for (skills) |*skill| {
                    var mut = skill.*;
                    mut.deinit(ctx.gpa);
                }
                ctx.gpa.free(skills);
            }
            const msg = try std.fmt.allocPrint(
                ctx.gpa,
                "Reloaded (no live agent): {d} context file(s), {d} skill(s)",
                .{ bundle.files.len, skills.len },
            );
            defer ctx.gpa.free(msg);
            try tui_render.printLine(ctx.io, msg);
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "hotkeys")) {
        try tui_render.printLine(ctx.io,
            \\Hotkeys (line REPL):
            \\  Enter — send  |  /quit — exit  |  /help — commands
        );
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "changelog")) {
        // Match the original command: render the bundled upstream changelog,
        // not a hand-maintained Pi-Zig summary that can drift from parity.
        try tui_render.printLine(ctx.io, "What's New");
        try tui_render.printLine(ctx.io, update_mod.bundledChangelog());
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "copy")) {
        const text = ctx.sess.lastAssistantText() orelse {
            try tui_render.printLine(ctx.io, "No agent messages to copy yet.");
            return .handled;
        };
        _ = clipboard_mod.copyText(ctx.gpa, ctx.io, text, ctx.clipboard_options) catch |err| {
            var message_buffer: [160]u8 = undefined;
            const message = std.fmt.bufPrint(&message_buffer, "Failed to copy to clipboard: {s}", .{@errorName(err)}) catch "Failed to copy to clipboard";
            try tui_render.printLine(ctx.io, message);
            return .handled;
        };
        try tui_render.printLine(ctx.io, "Copied last agent message to clipboard");
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "login")) {
        var prompted_choice: ?AuthTargetChoice = null;
        defer if (prompted_choice) |*choice| choice.deinit(ctx.gpa);
        var it = std.mem.tokenizeAny(u8, arg, " \t");
        const explicit_provider = it.next();
        const explicit_method_or_key = it.next();
        var prov: []const u8 = undefined;
        var supplied_method_or_key: ?[]const u8 = explicit_method_or_key;
        if (explicit_provider == null or (explicit_method_or_key == null and ctx.auth_target_prompt_fn != null)) {
            const prompt = ctx.auth_target_prompt_fn orelse {
                try tui_render.printLine(ctx.io, "usage: /login [provider] [api-key|browser|device-code|manual|code]");
                return .handled;
            };
            prompted_choice = try prompt(ctx.auth_target_prompt_ctx, ctx.gpa, .login, explicit_provider);
            if (prompted_choice.?.cancelled or prompted_choice.?.provider_id == null) return .handled;
            prov = prompted_choice.?.provider_id.?;
            supplied_method_or_key = switch (prompted_choice.?.method orelse return .handled) {
                .api_key => prompted_choice.?.api_key orelse return .handled,
                .browser => "browser",
                .device_code => "device-code",
            };
        } else {
            prov = explicit_provider.?;
        }
        const method_or_key: []const u8 = supplied_method_or_key orelse blk: {
            if (ctx.extension_oauth) |runtime| if (runtime.canLogin(prov)) break :blk "browser";
            if (isOpenAICodexProvider(prov) or isAnthropicProvider(prov) or isOpenRouterProvider(prov)) break :blk "browser";
            if (isGitHubCopilotProvider(prov) or isKimiCodingProvider(prov) or isXaiProvider(prov)) break :blk "device-code";
            const maybe_gateway = try radiusLoginGateway(ctx.gpa, ctx.io, ctx.agent_dir, prov);
            if (maybe_gateway) |gateway| {
                ctx.gpa.free(gateway);
                break :blk "browser";
            }
            try tui_render.printLine(ctx.io, "usage: /login [provider] [api-key|browser|device-code|manual|code]");
            return .handled;
        };
        if (std.mem.eql(u8, method_or_key, "manual")) {
            const ad = ctx.agent_dir orelse {
                try tui_render.printLine(ctx.io, "No agent dir; cannot store credentials.");
                return .handled;
            };
            _ = ad;
            if (!isOpenAICodexProvider(prov) and !isAnthropicProvider(prov) and !isOpenRouterProvider(prov)) {
                try tui_render.printLine(ctx.io, "Manual browser-code login is only available for openai-codex, anthropic, or openrouter.");
                return .handled;
            }
            if (isOpenRouterProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try tui_render.printLine(ctx.io, "OpenRouter login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                const pool = if (ctx.live) |live| live.client_pool orelse {
                    try tui_render.printLine(ctx.io, "Manual OpenRouter OAuth requires a live interactive client pool.");
                    return .handled;
                } else {
                    try tui_render.printLine(ctx.io, "Manual OpenRouter OAuth requires a live interactive client pool.");
                    return .handled;
                };
                const env = pool.environ;
                const host = openrouter_oauth.callbackHost(env);
                var callback = openrouter_oauth.startCallbackServer(ctx.gpa, ctx.io, host) catch |err| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "Could not allocate an OpenRouter callback URL: {s}", .{@errorName(err)});
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                    return .handled;
                };
                defer callback.deinit();
                var pair = shared_pkce.generate(ctx.gpa, ctx.io) catch |err| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "Could not generate OpenRouter OAuth PKCE: {s}", .{@errorName(err)});
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                    return .handled;
                };
                defer pair.deinit(ctx.gpa);
                const auth_url = openrouter_oauth.buildAuthorizationUrl(ctx.gpa, callback.callback_url, pair.challenge) catch |err| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "Could not build OpenRouter authorization URL: {s}", .{@errorName(err)});
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                    return .handled;
                };
                defer ctx.gpa.free(auth_url);
                try pool.installOpenRouterPendingFlow(pair.verifier, auth_url);
                openrouter_oauth.openBrowser(ctx.io, auth_url) catch {
                    try tui_render.printLine(ctx.io, "Could not open a browser automatically; open this URL manually:");
                };
                try tui_render.printLine(ctx.io, auth_url);
                try tui_render.printLine(ctx.io, "After authorization, copy the final redirect URL/code and run: /login openrouter code <redirect-url-or-code>");
                return .handled;
            }
            if (isAnthropicProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try tui_render.printLine(ctx.io, "Anthropic login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                const pool = if (ctx.live) |live| live.client_pool orelse {
                    try tui_render.printLine(ctx.io, "Manual Anthropic OAuth requires a live interactive client pool.");
                    return .handled;
                } else {
                    try tui_render.printLine(ctx.io, "Manual Anthropic OAuth requires a live interactive client pool.");
                    return .handled;
                };
                var flow = anthropic_oauth.createAuthorizationFlow(ctx.gpa, ctx.io) catch |err| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "Could not generate Anthropic OAuth flow: {s}", .{@errorName(err)});
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                    return .handled;
                };
                defer flow.deinit(ctx.gpa);
                try pool.installAnthropicPendingFlow(&flow);
                anthropic_oauth.openBrowser(ctx.io, flow.url) catch {
                    try tui_render.printLine(ctx.io, "Could not open a browser automatically; open this URL manually:");
                };
                try tui_render.printLine(ctx.io, flow.url);
                try tui_render.printLine(ctx.io, "After authorization, paste the redirect URL/code with: /login anthropic code <redirect-url-or-code#state>");
                return .handled;
            }
            if (!loginNetworkEnabled(ctx)) {
                try tui_render.printLine(ctx.io, "OpenAI Codex login is unavailable while PI_OFFLINE is set.");
                return .handled;
            }
            const pool = if (ctx.live) |live| live.client_pool orelse {
                try tui_render.printLine(ctx.io, "Manual Codex OAuth requires a live interactive client pool.");
                return .handled;
            } else {
                try tui_render.printLine(ctx.io, "Manual Codex OAuth requires a live interactive client pool.");
                return .handled;
            };
            var flow = codex_oauth.createAuthorizationFlow(ctx.gpa, ctx.io, "pi") catch |err| {
                const msg = try std.fmt.allocPrint(ctx.gpa, "Could not generate OpenAI Codex OAuth flow: {s}", .{@errorName(err)});
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
                return .handled;
            };
            defer flow.deinit(ctx.gpa);
            try pool.installCodexPendingFlow(&flow);
            codex_oauth.openBrowser(ctx.io, flow.url) catch {
                try tui_render.printLine(ctx.io, "Could not open a browser automatically; open this URL manually:");
            };
            try tui_render.printLine(ctx.io, flow.url);
            try tui_render.printLine(ctx.io, "After authorization, paste the redirect URL with: /login openai-codex code <redirect-url-or-code#state>");
            return .handled;
        }
        if (std.mem.eql(u8, method_or_key, "code")) {
            const ad = ctx.agent_dir orelse {
                try tui_render.printLine(ctx.io, "No agent dir; cannot store credentials.");
                return .handled;
            };
            if (!isOpenAICodexProvider(prov) and !isAnthropicProvider(prov) and !isOpenRouterProvider(prov)) {
                try tui_render.printLine(ctx.io, "Pasted authorization-code login is only available for openai-codex, anthropic, or openrouter.");
                return .handled;
            }
            if (isOpenRouterProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try tui_render.printLine(ctx.io, "OpenRouter login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                const input = it.next() orelse {
                    try tui_render.printLine(ctx.io, "usage: /login openrouter code <authorization-code-or-redirect-url>");
                    return .handled;
                };
                const pool = if (ctx.live) |live| live.client_pool orelse {
                    try tui_render.printLine(ctx.io, "No pending OpenRouter OAuth flow. Start with /login openrouter manual.");
                    return .handled;
                } else {
                    try tui_render.printLine(ctx.io, "No pending OpenRouter OAuth flow. Start with /login openrouter manual.");
                    return .handled;
                };
                var outcome = pool.completeOpenRouterPendingFlow(input) catch |err| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "OpenRouter manual-code login failed: {s}", .{@errorName(err)});
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                    return .handled;
                };
                defer outcome.deinit(ctx.gpa);
                switch (outcome) {
                    .failed => |message| {
                        try tui_render.printLine(ctx.io, message);
                        return .handled;
                    },
                    .complete => |*token| {
                        try finishOpenRouterOAuthLogin(ctx, ad, token);
                        return .handled;
                    },
                }
            }
            if (isAnthropicProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try tui_render.printLine(ctx.io, "Anthropic login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                const input = it.next() orelse {
                    try tui_render.printLine(ctx.io, "usage: /login anthropic code <authorization-code-or-redirect-url>");
                    return .handled;
                };
                const pool = if (ctx.live) |live| live.client_pool orelse {
                    try tui_render.printLine(ctx.io, "No pending Anthropic OAuth flow. Start with /login anthropic manual.");
                    return .handled;
                } else {
                    try tui_render.printLine(ctx.io, "No pending Anthropic OAuth flow. Start with /login anthropic manual.");
                    return .handled;
                };
                var token = pool.completeAnthropicPendingFlow(input) catch |err| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "Anthropic manual-code login failed: {s}", .{@errorName(err)});
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                    return .handled;
                };
                defer token.deinit(ctx.gpa);
                try finishAnthropicOAuthLogin(ctx, ad, &token);
                return .handled;
            }
            if (!loginNetworkEnabled(ctx)) {
                try tui_render.printLine(ctx.io, "OpenAI Codex login is unavailable while PI_OFFLINE is set.");
                return .handled;
            }
            const input = it.next() orelse {
                try tui_render.printLine(ctx.io, "usage: /login openai-codex code <authorization-code-or-redirect-url>");
                return .handled;
            };
            const pool = if (ctx.live) |live| live.client_pool orelse {
                try tui_render.printLine(ctx.io, "No pending live Codex OAuth flow. Start with /login openai-codex manual.");
                return .handled;
            } else {
                try tui_render.printLine(ctx.io, "No pending live Codex OAuth flow. Start with /login openai-codex manual.");
                return .handled;
            };
            var token = pool.completeCodexPendingFlow(input) catch |err| {
                const msg = try std.fmt.allocPrint(ctx.gpa, "OpenAI Codex manual-code login failed: {s}", .{@errorName(err)});
                defer ctx.gpa.free(msg);
                try tui_render.printLine(ctx.io, msg);
                return .handled;
            };
            defer token.deinit(ctx.gpa);
            try finishCodexOAuthLogin(ctx, ad, &token);
            return .handled;
        }
        if (std.mem.eql(u8, method_or_key, "browser")) {
            const ad = ctx.agent_dir orelse {
                try tui_render.printLine(ctx.io, "No agent dir; cannot store credentials.");
                return .handled;
            };
            if (ctx.extension_oauth) |runtime| if (runtime.canLogin(prov)) {
                const dialog_active = authDialogBegin(ctx, prov);
                defer if (dialog_active) authDialogClose(ctx);
                var ui_context = ExtensionOAuthUiContext{
                    .slash = ctx,
                    .dialog_active = dialog_active,
                };
                const persisted = runtime.loginAndPersist(
                    prov,
                    extensionOAuthAbortFlag(ctx),
                    .{
                        .context = &ui_context,
                        .request_fn = extensionOAuthUiRequest,
                        .action_fn = extensionOAuthUiAction,
                    },
                ) catch |err| {
                    if (dialog_active and ctx.auth_flow_ui.?.cancelled()) {
                        try authDialogFailure(ctx, dialog_active, prov, error.LoginCancelled);
                    } else if (runtime.lastLoginError(prov)) |details| {
                        const message = try std.fmt.allocPrint(ctx.gpa, "{s} login failed:\n{s}", .{ prov, details });
                        defer ctx.gpa.free(message);
                        try authDialogFailMessage(ctx, dialog_active, message);
                    } else {
                        try authDialogFailure(ctx, dialog_active, prov, err);
                    }
                    return .handled;
                };
                defer ctx.gpa.free(persisted);

                if (ctx.live) |live| if (live.client_pool) |pool| {
                    if (std.ascii.eqlIgnoreCase(pool.active_provider_id, prov)) {
                        const active_model = pool.modelPtr().*;
                        const model_copy = try ctx.gpa.dupe(u8, active_model);
                        defer ctx.gpa.free(model_copy);
                        pool.switchToIdentityAfterOAuthUpdate(prov, pool.active_provider, model_copy) catch |err| {
                            const message = try std.fmt.allocPrint(ctx.gpa, "{s} credential was stored, but the active client could not be rebuilt: {s}", .{ prov, @errorName(err) });
                            defer ctx.gpa.free(message);
                            try authDialogFailMessage(ctx, dialog_active, message);
                            return .handled;
                        };
                        live.active_model = pool.modelPtr();
                    }
                };
                authDialogFinish(ctx, dialog_active, true, "Extension OAuth authentication complete.");
                try tui_render.printLine(ctx.io, "Extension OAuth credential stored in auth.json and activated for this process.");
                return .handled;
            };
            if (isOpenAICodexProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try tui_render.printLine(ctx.io, "OpenAI Codex login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                var flow = codex_oauth.createAuthorizationFlow(ctx.gpa, ctx.io, "pi") catch |err| {
                    try authDialogFailure(ctx, false, prov, err);
                    return .handled;
                };
                defer flow.deinit(ctx.gpa);
                const dialog_active = authDialogBegin(ctx, prov);
                defer if (dialog_active) authDialogClose(ctx);
                const env = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
                const host = codex_oauth.callbackHost(env);
                var callback = codex_oauth.startCallbackServer(ctx.io, host) catch |err| {
                    if (ctx.live) |live| if (live.client_pool) |pool| {
                        try pool.installCodexPendingFlow(&flow);
                        var opened = true;
                        codex_oauth.openBrowser(ctx.io, flow.url) catch {
                            opened = false;
                        };
                        const instructions = if (opened)
                            "Complete authorization in the browser, then paste the final redirect URL or code here."
                        else
                            "The browser could not be opened automatically. Open this URL, authorize, then paste the redirect URL or code here.";
                        try authDialogShowAuth(ctx, dialog_active, flow.url, instructions);
                        if (dialog_active) {
                            const input = authDialogPrompt(ctx, true, "Paste the final redirect URL or authorization code:", "http://localhost:1455/auth/callback?code=…&state=…") catch |prompt_err| {
                                try authDialogFailure(ctx, true, prov, prompt_err);
                                return .handled;
                            };
                            defer ctx.gpa.free(input);
                            var token = pool.completeCodexPendingFlow(input) catch |complete_err| {
                                try authDialogFailure(ctx, true, prov, complete_err);
                                return .handled;
                            };
                            defer token.deinit(ctx.gpa);
                            authDialogFinish(ctx, true, true, "OpenAI Codex authentication complete.");
                            try finishCodexOAuthLogin(ctx, ad, &token);
                            return .handled;
                        }
                        const msg = try std.fmt.allocPrint(ctx.gpa, "Could not listen for OpenAI Codex OAuth callback on {s}:{d} ({s}); keeping this PKCE flow for manual completion.", .{ host, codex_oauth.CALLBACK_PORT, @errorName(err) });
                        defer ctx.gpa.free(msg);
                        try tui_render.printLine(ctx.io, msg);
                        try tui_render.printLine(ctx.io, "After authorization, paste the redirect URL with: /login openai-codex code <redirect-url-or-code#state>");
                        return .handled;
                    };
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer callback.deinit();
                var opened = true;
                codex_oauth.openBrowser(ctx.io, flow.url) catch {
                    opened = false;
                };
                try authDialogShowAuth(
                    ctx,
                    dialog_active,
                    flow.url,
                    if (opened) "Waiting for the browser callback…" else "The browser could not be opened automatically. Open this URL manually; Pi is waiting for the callback.",
                );
                const listening = try std.fmt.allocPrint(ctx.gpa, "Listening on {s}:{d}{s}", .{ host, codex_oauth.CALLBACK_PORT, codex_oauth.CALLBACK_PATH });
                defer ctx.gpa.free(listening);
                try authDialogProgress(ctx, dialog_active, listening);
                var result = callback.wait(ctx.gpa, flow.state, authDialogAbortFlag(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer result.deinit(ctx.gpa);
                const code = switch (result) {
                    .code => |value| value,
                    .oauth_error => |message| {
                        const msg = try std.fmt.allocPrint(ctx.gpa, "OpenAI Codex authorization failed: {s}", .{message});
                        defer ctx.gpa.free(msg);
                        try authDialogFailMessage(ctx, dialog_active, msg);
                        return .handled;
                    },
                };
                try authDialogWaiting(ctx, dialog_active, "Exchanging authorization code…");
                var token = codex_oauth.exchangeAuthorizationCodeWithOptions(ctx.gpa, ctx.io, code, flow.verifier, codex_oauth.REDIRECT_URI, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer token.deinit(ctx.gpa);
                authDialogFinish(ctx, dialog_active, true, "OpenAI Codex authentication complete.");
                try finishCodexOAuthLogin(ctx, ad, &token);
                return .handled;
            }
            if (isAnthropicProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try tui_render.printLine(ctx.io, "Anthropic login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                var flow = anthropic_oauth.createAuthorizationFlow(ctx.gpa, ctx.io) catch |err| {
                    try authDialogFailure(ctx, false, prov, err);
                    return .handled;
                };
                defer flow.deinit(ctx.gpa);
                const dialog_active = authDialogBegin(ctx, prov);
                defer if (dialog_active) authDialogClose(ctx);
                const env = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
                const host = anthropic_oauth.callbackHost(env);
                var callback = anthropic_oauth.startCallbackServer(ctx.io, host) catch |err| {
                    if (ctx.live) |live| if (live.client_pool) |pool| {
                        try pool.installAnthropicPendingFlow(&flow);
                        var opened = true;
                        anthropic_oauth.openBrowser(ctx.io, flow.url) catch {
                            opened = false;
                        };
                        try authDialogShowAuth(
                            ctx,
                            dialog_active,
                            flow.url,
                            if (opened) "Complete authorization, then paste the redirect URL or code here." else "Open this URL manually, authorize, then paste the redirect URL or code here.",
                        );
                        if (dialog_active) {
                            const input = authDialogPrompt(ctx, true, "Paste the redirect URL or authorization code:", "code#state") catch |prompt_err| {
                                try authDialogFailure(ctx, true, prov, prompt_err);
                                return .handled;
                            };
                            defer ctx.gpa.free(input);
                            var token = pool.completeAnthropicPendingFlow(input) catch |complete_err| {
                                try authDialogFailure(ctx, true, prov, complete_err);
                                return .handled;
                            };
                            defer token.deinit(ctx.gpa);
                            authDialogFinish(ctx, true, true, "Anthropic authentication complete.");
                            try finishAnthropicOAuthLogin(ctx, ad, &token);
                            return .handled;
                        }
                        const msg = try std.fmt.allocPrint(ctx.gpa, "Could not listen for Anthropic OAuth callback on {s}:{d} ({s}); keeping this PKCE flow for manual completion.", .{ host, anthropic_oauth.CALLBACK_PORT, @errorName(err) });
                        defer ctx.gpa.free(msg);
                        try tui_render.printLine(ctx.io, msg);
                        try tui_render.printLine(ctx.io, "After authorization, paste the redirect URL/code with: /login anthropic code <redirect-url-or-code#state>");
                        return .handled;
                    };
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer callback.deinit();
                var opened = true;
                anthropic_oauth.openBrowser(ctx.io, flow.url) catch {
                    opened = false;
                };
                try authDialogShowAuth(
                    ctx,
                    dialog_active,
                    flow.url,
                    if (opened) "Waiting for the browser callback…" else "The browser could not be opened automatically. Open this URL manually; Pi is waiting for the callback.",
                );
                const listening = try std.fmt.allocPrint(ctx.gpa, "Listening on {s}:{d}{s}", .{ host, anthropic_oauth.CALLBACK_PORT, anthropic_oauth.CALLBACK_PATH });
                defer ctx.gpa.free(listening);
                try authDialogProgress(ctx, dialog_active, listening);
                var result = callback.wait(ctx.gpa, flow.verifier, authDialogAbortFlag(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer result.deinit(ctx.gpa);
                const code = switch (result) {
                    .code => |value| value,
                    .oauth_error => |message| {
                        const msg = try std.fmt.allocPrint(ctx.gpa, "Anthropic authorization failed: {s}", .{message});
                        defer ctx.gpa.free(msg);
                        try authDialogFailMessage(ctx, dialog_active, msg);
                        return .handled;
                    },
                };
                try authDialogWaiting(ctx, dialog_active, "Exchanging authorization code…");
                var token = anthropic_oauth.exchangeAuthorizationCodeWithOptions(ctx.gpa, ctx.io, code, flow.verifier, flow.verifier, anthropic_oauth.REDIRECT_URI, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer token.deinit(ctx.gpa);
                authDialogFinish(ctx, dialog_active, true, "Anthropic authentication complete.");
                try finishAnthropicOAuthLogin(ctx, ad, &token);
                return .handled;
            }
            if (isOpenRouterProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try tui_render.printLine(ctx.io, "OpenRouter login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                const env = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
                const host = openrouter_oauth.callbackHost(env);
                var callback = openrouter_oauth.startCallbackServer(ctx.gpa, ctx.io, host) catch |err| {
                    try authDialogFailure(ctx, false, prov, err);
                    return .handled;
                };
                defer callback.deinit();
                var pair = shared_pkce.generate(ctx.gpa, ctx.io) catch |err| {
                    try authDialogFailure(ctx, false, prov, err);
                    return .handled;
                };
                defer pair.deinit(ctx.gpa);
                const auth_url = openrouter_oauth.buildAuthorizationUrl(ctx.gpa, callback.callback_url, pair.challenge) catch |err| {
                    try authDialogFailure(ctx, false, prov, err);
                    return .handled;
                };
                defer ctx.gpa.free(auth_url);
                const dialog_active = authDialogBegin(ctx, prov);
                defer if (dialog_active) authDialogClose(ctx);
                var opened = true;
                openrouter_oauth.openBrowser(ctx.io, auth_url) catch {
                    opened = false;
                };
                try authDialogShowAuth(
                    ctx,
                    dialog_active,
                    auth_url,
                    if (opened) "Waiting for the browser callback…" else "The browser could not be opened automatically. Open this URL manually; Pi is waiting for the callback.",
                );
                const listening = try std.fmt.allocPrint(ctx.gpa, "Listening on {s}", .{callback.callback_url});
                defer ctx.gpa.free(listening);
                try authDialogProgress(ctx, dialog_active, listening);
                var result = callback.waitCode(authDialogAbortFlag(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer result.deinit(ctx.gpa);
                const code = switch (result) {
                    .code => |value| value,
                    .oauth_error => |message| {
                        const msg = try std.fmt.allocPrint(ctx.gpa, "OpenRouter authorization failed: {s}", .{message});
                        defer ctx.gpa.free(msg);
                        try authDialogFailMessage(ctx, dialog_active, msg);
                        return .handled;
                    },
                };
                try authDialogWaiting(ctx, dialog_active, "Exchanging authorization code…");
                var exchange = openrouter_oauth.exchangeAuthorizationCodeWithOptions(ctx.gpa, ctx.io, code, pair.verifier, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer exchange.deinit(ctx.gpa);
                switch (exchange) {
                    .failed => |message| {
                        try authDialogFailMessage(ctx, dialog_active, message);
                        return .handled;
                    },
                    .complete => |*token| {
                        authDialogFinish(ctx, dialog_active, true, "OpenRouter authentication complete.");
                        try finishOpenRouterOAuthLogin(ctx, ad, token);
                        return .handled;
                    },
                }
            }
            if (isGitHubCopilotProvider(prov)) {
                try tui_render.printLine(ctx.io, "GitHub Copilot uses device-code login; run /login github-copilot device-code [enterprise-domain].");
                return .handled;
            }
            if (isKimiCodingProvider(prov)) {
                try tui_render.printLine(ctx.io, "Kimi Coding OAuth uses device-code login; run /login kimi-coding device-code.");
                return .handled;
            }
            if (isXaiProvider(prov)) {
                try tui_render.printLine(ctx.io, "xAI OAuth uses device-code login; run /login xai device-code.");
                return .handled;
            }
            const gateway = (try radiusLoginGateway(ctx.gpa, ctx.io, ctx.agent_dir, prov)) orelse {
                try tui_render.printLine(ctx.io, "Browser login is only available for Radius OAuth providers.");
                return .handled;
            };
            defer ctx.gpa.free(gateway);
            const env = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
            if (env) |environ| if (!radius_refresh.networkEnabled(environ)) {
                try tui_render.printLine(ctx.io, "Radius login is unavailable while PI_OFFLINE is set.");
                return .handled;
            };
            var discovery = radius_oauth.loadDiscoveryWithOptions(ctx.gpa, ctx.io, gateway, bootstrapOptions(ctx)) catch |err| {
                try authDialogFailure(ctx, false, prov, err);
                return .handled;
            };
            defer discovery.deinit(ctx.gpa);
            var pkce = radius_oauth.generatePkce(ctx.gpa, ctx.io) catch |err| {
                try authDialogFailure(ctx, false, prov, err);
                return .handled;
            };
            defer pkce.deinit(ctx.gpa);
            const state = try radius_oauth.generateState(ctx.gpa, ctx.io);
            defer ctx.gpa.free(state);
            const auth_url = try radius_oauth.buildAuthorizationUrl(ctx.gpa, discovery.authorization_endpoint, pkce.challenge, state);
            defer ctx.gpa.free(auth_url);
            var callback = radius_oauth.startCallbackServer(ctx.io) catch |err| {
                try authDialogFailure(ctx, false, prov, err);
                return .handled;
            };
            defer callback.deinit();
            const dialog_active = authDialogBegin(ctx, prov);
            defer if (dialog_active) authDialogClose(ctx);
            var opened = true;
            radius_oauth.openBrowser(ctx.io, auth_url) catch {
                opened = false;
            };
            try authDialogShowAuth(
                ctx,
                dialog_active,
                auth_url,
                if (opened) "Waiting for the browser callback…" else "The browser could not be opened automatically. Open this URL manually; Pi is waiting for the callback.",
            );
            try authDialogProgress(ctx, dialog_active, "Listening on http://127.0.0.1:1455/auth/callback");
            var result = callback.wait(ctx.gpa, state, authDialogAbortFlag(ctx)) catch |err| {
                try authDialogFailure(ctx, dialog_active, prov, err);
                return .handled;
            };
            defer result.deinit(ctx.gpa);
            const code = switch (result) {
                .code => |value| value,
                .oauth_error => |message| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "Radius OAuth authorization failed: {s}", .{message});
                    defer ctx.gpa.free(msg);
                    try authDialogFailMessage(ctx, dialog_active, msg);
                    return .handled;
                },
            };
            try authDialogWaiting(ctx, dialog_active, "Exchanging authorization code…");
            var token = radius_oauth.requestAuthorizationCodeTokenWithOptions(ctx.gpa, ctx.io, gateway, code, pkce.verifier, bootstrapOptions(ctx)) catch |err| {
                try authDialogFailure(ctx, dialog_active, prov, err);
                return .handled;
            };
            defer token.deinit(ctx.gpa);
            authDialogFinish(ctx, dialog_active, true, "Authentication complete.");
            try finishRadiusOAuthLogin(ctx, ad, prov, gateway, &token);
            return .handled;
        }
        if (std.mem.eql(u8, method_or_key, "device-code")) {
            const ad = ctx.agent_dir orelse {
                try tui_render.printLine(ctx.io, "No agent dir; cannot store credentials.");
                return .handled;
            };
            const dialog_active = authDialogBegin(ctx, prov);
            defer if (dialog_active) authDialogClose(ctx);

            if (isOpenAICodexProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try authDialogFailMessage(ctx, dialog_active, "OpenAI Codex login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                var device = codex_oauth.requestDeviceAuthorizationWithOptions(ctx.gpa, ctx.io, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer device.deinit(ctx.gpa);
                try authDialogShowDeviceCode(ctx, dialog_active, codex_oauth.DEVICE_VERIFICATION_URI, device.user_code, device.interval_seconds, null);
                try authDialogProgress(ctx, dialog_active, "Waiting for OpenAI authorization…");
                var completed = codex_oauth.pollDeviceCodeWithOptions(ctx.gpa, ctx.io, &device, authDialogAbortFlag(ctx), bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer completed.deinit(ctx.gpa);
                try authDialogWaiting(ctx, dialog_active, "Authorization accepted. Exchanging device code…");
                var token = codex_oauth.exchangeAuthorizationCodeWithOptions(ctx.gpa, ctx.io, completed.authorization_code, completed.code_verifier, codex_oauth.DEVICE_REDIRECT_URI, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer token.deinit(ctx.gpa);
                authDialogFinish(ctx, dialog_active, true, "OpenAI Codex authentication complete.");
                try finishCodexOAuthLogin(ctx, ad, &token);
                return .handled;
            }

            if (isGitHubCopilotProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try authDialogFailMessage(ctx, dialog_active, "GitHub Copilot login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                const enterprise_input = it.next();
                var enterprise_domain: ?[]u8 = null;
                defer if (enterprise_domain) |value| ctx.gpa.free(value);
                if (enterprise_input) |value| {
                    enterprise_domain = copilot_oauth.normalizeDomain(ctx.gpa, value) catch |err| {
                        try authDialogFailure(ctx, dialog_active, prov, err);
                        return .handled;
                    };
                }
                var device = copilot_oauth.requestDeviceCodeWithOptions(ctx.gpa, ctx.io, enterprise_domain, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer device.deinit(ctx.gpa);
                try authDialogShowDeviceCode(ctx, dialog_active, device.verification_uri, device.user_code, device.interval_seconds, device.expires_in_seconds);
                try authDialogProgress(ctx, dialog_active, "Waiting for GitHub authorization…");
                const github_access = copilot_oauth.pollGitHubAccessTokenWithOptions(ctx.gpa, ctx.io, enterprise_domain, &device, authDialogAbortFlag(ctx), bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer ctx.gpa.free(github_access);
                try authDialogWaiting(ctx, dialog_active, "Authorization accepted. Refreshing Copilot credentials…");
                var credential = copilot_oauth.refreshAccessTokenWithOptions(ctx.gpa, ctx.io, github_access, enterprise_domain, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer credential.deinit(ctx.gpa);
                try authDialogProgress(ctx, dialog_active, "Discovering available Copilot models…");
                credential.available_model_ids = copilot_oauth.discoverAndEnableAvailableModelIdsWithOptions(ctx.gpa, ctx.io, credential.access, enterprise_domain, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                authDialogFinish(ctx, dialog_active, true, "GitHub Copilot authentication complete.");
                try finishGitHubCopilotOAuthLogin(ctx, ad, &credential);
                return .handled;
            }

            if (isKimiCodingProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try authDialogFailMessage(ctx, dialog_active, "Kimi Coding login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                const env = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
                const host = kimi_oauth.oauthHost(env);
                var device = kimi_oauth.requestDeviceAuthorizationWithOptions(ctx.gpa, ctx.io, host, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer device.deinit(ctx.gpa);
                try authDialogShowDeviceCode(ctx, dialog_active, device.verification_uri_complete, device.user_code, device.interval_seconds, device.expires_in_seconds);
                try authDialogProgress(ctx, dialog_active, "Waiting for Kimi authorization…");
                var token = kimi_oauth.pollDeviceCodeWithOptions(ctx.gpa, ctx.io, host, &device, authDialogAbortFlag(ctx), bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer token.deinit(ctx.gpa);
                authDialogFinish(ctx, dialog_active, true, "Kimi Coding authentication complete.");
                try finishKimiOAuthLogin(ctx, ad, &token);
                return .handled;
            }

            if (isXaiProvider(prov)) {
                if (!loginNetworkEnabled(ctx)) {
                    try authDialogFailMessage(ctx, dialog_active, "xAI login is unavailable while PI_OFFLINE is set.");
                    return .handled;
                }
                var device = xai_oauth.requestDeviceAuthorizationWithOptions(ctx.gpa, ctx.io, bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer device.deinit(ctx.gpa);
                try authDialogShowDeviceCode(ctx, dialog_active, device.browserUri(), device.user_code, device.interval_seconds, device.expires_in_seconds);
                try authDialogProgress(ctx, dialog_active, "Waiting for xAI authorization…");
                var token = xai_oauth.pollDeviceCodeWithOptions(ctx.gpa, ctx.io, &device, authDialogAbortFlag(ctx), bootstrapOptions(ctx)) catch |err| {
                    try authDialogFailure(ctx, dialog_active, prov, err);
                    return .handled;
                };
                defer token.deinit(ctx.gpa);
                authDialogFinish(ctx, dialog_active, true, "xAI authentication complete.");
                try finishXaiOAuthLogin(ctx, ad, &token);
                return .handled;
            }

            const gateway = (try radiusLoginGateway(ctx.gpa, ctx.io, ctx.agent_dir, prov)) orelse {
                try authDialogFailMessage(ctx, dialog_active, "Device-code login is only available for Radius OAuth providers, OpenAI Codex, GitHub Copilot, Kimi Coding, or xAI.");
                return .handled;
            };
            defer ctx.gpa.free(gateway);
            const env = if (ctx.live) |live| if (live.client_pool) |pool| pool.environ else null else null;
            if (env) |environ| if (!radius_refresh.networkEnabled(environ)) {
                try authDialogFailMessage(ctx, dialog_active, "Radius login is unavailable while PI_OFFLINE is set.");
                return .handled;
            };
            var device = radius_oauth.requestDeviceAuthorizationWithOptions(ctx.gpa, ctx.io, gateway, bootstrapOptions(ctx)) catch |err| {
                try authDialogFailure(ctx, dialog_active, prov, err);
                return .handled;
            };
            defer device.deinit(ctx.gpa);
            try authDialogShowDeviceCode(ctx, dialog_active, device.verification_uri, device.user_code, device.interval, device.expires_in);
            try authDialogProgress(ctx, dialog_active, "Waiting for authorization…");
            var token = radius_oauth.pollDeviceCodeWithOptions(ctx.gpa, ctx.io, gateway, &device, authDialogAbortFlag(ctx), bootstrapOptions(ctx)) catch |err| {
                try authDialogFailure(ctx, dialog_active, prov, err);
                return .handled;
            };
            defer token.deinit(ctx.gpa);
            authDialogFinish(ctx, dialog_active, true, "Authentication complete.");
            try finishRadiusOAuthLogin(ctx, ad, prov, gateway, &token);
            return .handled;
        }
        if (ctx.agent_dir) |ad| {
            var store = try auth_storage.AuthStorage.init(ctx.gpa, ctx.io, ad);
            defer store.deinit();
            try store.setApiKey(prov, method_or_key);
            if (ctx.live) |live| {
                if (live.client_pool) |pool| {
                    try pool.installApiKeyCredential(prov, method_or_key);
                    if (std.ascii.eqlIgnoreCase(pool.active_provider_id, prov)) {
                        const active_model = pool.model_owned orelse ctx.model.* orelse "";
                        if (active_model.len > 0) {
                            // switchToIdentity replaces model_owned, so never pass
                            // a slice borrowed from that allocation back into it.
                            const model_copy = try ctx.gpa.dupe(u8, active_model);
                            defer ctx.gpa.free(model_copy);
                            try pool.switchToIdentity(pool.active_provider_id, pool.active_provider, model_copy);
                            live.active_model = pool.modelPtr();
                        }
                    }
                }
            }
            try tui_render.printLine(ctx.io, "Credential stored in auth.json and activated for this process.");
        } else {
            try tui_render.printLine(ctx.io, "No agent dir; cannot store credentials.");
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "logout")) {
        var prompted_choice: ?AuthTargetChoice = null;
        defer if (prompted_choice) |*choice| choice.deinit(ctx.gpa);
        const explicit_provider = std.mem.trim(u8, arg, " \t");
        const prov: []const u8 = if (explicit_provider.len > 0) explicit_provider else blk: {
            const prompt = ctx.auth_target_prompt_fn orelse {
                try tui_render.printLine(ctx.io, "usage: /logout [provider]");
                return .handled;
            };
            prompted_choice = try prompt(ctx.auth_target_prompt_ctx, ctx.gpa, .logout, null);
            if (prompted_choice.?.cancelled or prompted_choice.?.provider_id == null) return .handled;
            break :blk prompted_choice.?.provider_id.?;
        };
        if (ctx.agent_dir) |ad| {
            var store = try auth_storage.AuthStorage.init(ctx.gpa, ctx.io, ad);
            defer store.deinit();
            try store.delete(prov);
            if (ctx.live) |live| {
                if (live.runtime_reload_fn != null) {
                    // Keep the old in-process credential alive until the
                    // transactional replacement pool has been committed. This
                    // avoids leaving an active provider client with a dangling
                    // API-key pointer while reload is staged.
                    const status = try live_state.applyReload(live);
                    defer ctx.gpa.free(status);
                    const message = try std.fmt.allocPrint(ctx.gpa, "Stored provider credential removed. {s}", .{status});
                    defer ctx.gpa.free(message);
                    try tui_render.printLine(ctx.io, message);
                } else if (live.client_pool) |pool| {
                    if (!std.ascii.eqlIgnoreCase(pool.active_provider_id, prov)) {
                        _ = pool.removeLiveCredential(prov);
                        try tui_render.printLine(ctx.io, "Stored provider credential removed and cleared from this process.");
                    } else {
                        try tui_render.printLine(ctx.io, "Stored provider credential removed. The active provider keeps its current in-memory credential until reload or exit.");
                    }
                } else {
                    try tui_render.printLine(ctx.io, "Stored provider credential removed.");
                }
            } else {
                try tui_render.printLine(ctx.io, "Stored provider credential removed.");
            }
        } else {
            try tui_render.printLine(ctx.io, "No agent dir; cannot remove credentials.");
        }
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "settings")) {
        if (ctx.settings_target_prompt_fn) |prompt| {
            const choice = try prompt(ctx.settings_target_prompt_ctx, ctx.gpa);
            if (choice.changed) {
                if (ctx.live) |live| {
                    const status = try live_state.applyReload(live);
                    defer ctx.gpa.free(status);
                    try tui_render.printLine(ctx.io, status);
                } else {
                    try tui_render.printLine(ctx.io, "Settings saved. Restart or /reload to apply all changes.");
                }
            }
            return .handled;
        }
        try tui_render.printLine(ctx.io, ctx.settings_text);
        return .handled;
    }
    if (std.mem.eql(u8, cmd, "resume")) {
        if (ctx.session_target_prompt_fn) |prompt| {
            var choice = try prompt(ctx.session_target_prompt_ctx, ctx.gpa, if (arg.len > 0) arg else null);
            defer choice.deinit(ctx.gpa);
            if (!choice.cancelled and choice.path != null) {
                if (ctx.resume_path_out) |out| {
                    if (out.*) |old| ctx.gpa.free(old);
                    out.* = choice.path;
                    choice.path = null;
                }
            }
            return .handled;
        }
        if (ctx.session_dir) |sd| {
            const sessions = try session_mod.listSessions(ctx.gpa, ctx.io, sd);
            defer {
                for (sessions) |*info| info.deinit(ctx.gpa);
                ctx.gpa.free(sessions);
            }
            if (sessions.len == 0) {
                try tui_render.printLine(ctx.io, "(no sessions)");
            } else {
                for (sessions) |info| {
                    const msg = try std.fmt.allocPrint(ctx.gpa, "  {s}  {s}  {s}", .{ info.id, info.name, info.path });
                    defer ctx.gpa.free(msg);
                    try tui_render.printLine(ctx.io, msg);
                }
            }
        } else {
            try tui_render.printLine(ctx.io, "No session directory configured.");
        }
        return .handled;
    }

    try tui_render.printLine(ctx.io, "Unknown command. Try /help");
    return .handled;
}

test "disabled skill commands do not mutate session" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    var sess = try session_mod.Session.init(gpa, "disabled-skills", root);
    defer sess.deinit();
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;
    const result = try handle(.{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .enable_skill_commands = false,
    }, "/skill:review");
    try std.testing.expectEqual(SlashResult.handled, result);
    try std.testing.expectEqual(@as(usize, 0), sess.entries.items.len);
}

test "tree arguments support summarized navigation in both orders" {
    const plain = try parseTreeArgs("m4");
    try std.testing.expectEqualStrings("m4", plain.target_id.?);
    try std.testing.expect(!plain.summarize);

    const suffix = try parseTreeArgs("m8 --summary preserve exact paths");
    try std.testing.expectEqualStrings("m8", suffix.target_id.?);
    try std.testing.expect(suffix.summarize);
    try std.testing.expect(suffix.summary_explicit);
    try std.testing.expectEqualStrings("preserve exact paths", suffix.custom_instructions.?);

    const prefix = try parseTreeArgs("--summary m9 focus on failures");
    try std.testing.expectEqualStrings("m9", prefix.target_id.?);
    try std.testing.expect(prefix.summarize);
    try std.testing.expect(prefix.summary_explicit);
    try std.testing.expectEqualStrings("focus on failures", prefix.custom_instructions.?);

    try std.testing.expectError(error.MissingTreeTarget, parseTreeArgs("--summary"));
    try std.testing.expectError(error.InvalidTreeArguments, parseTreeArgs("--summaryfoo m10"));
    try std.testing.expectError(error.InvalidTreeArguments, parseTreeArgs("m10 --summaryfoo"));
}

test "slash session new model quit drive real session state" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var sess = try session_mod.Session.init(gpa, "slash-test", tmp_path);
    defer sess.deinit();
    _ = try sess.appendMessage(null, "user", "hello", null, null);
    _ = try sess.appendMessage(sess.lastEntryId(), "assistant", "hi there", null, null);

    var model: ?[]const u8 = null;
    defer if (model) |m| gpa.free(m);
    var provider: ?[]const u8 = null;
    var model_owned = false;
    var client_model: []const u8 = "initial";
    var cfg = @import("../agent/loop.zig").AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);

    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |s| gpa.free(s);
    var live = live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &model,
        .active_model = &client_model,
        .model_display_owned = &model_owned,
    };

    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "settings:ok",
        .trust_project = true,
        .live = &live,
    };

    try std.testing.expect((try handle(ctx, "/model gpt-test")) == .handled);
    try std.testing.expectEqualStrings("gpt-test", model.?);
    try std.testing.expectEqualStrings("gpt-test", client_model);
    try std.testing.expect((try handle(ctx, "/thinking high")) == .handled);
    try std.testing.expectEqualStrings("high", live.thinking.?);
    try std.testing.expect((try handle(ctx, "/name my-sess")) == .handled);
    try std.testing.expectEqualStrings("my-sess", sess.name);
    try std.testing.expect((try handle(ctx, "/compact")) == .handled);
    try std.testing.expect((try handle(ctx, "/new")) == .handled);
    try std.testing.expectEqual(@as(usize, 0), sess.entries.items.len);
    try std.testing.expect((try handle(ctx, "/quit")) == .quit);
    try std.testing.expect((try handle(ctx, "not a slash")) == .not_command);
    try std.testing.expect(isBuiltinCommand("/model anthropic/test"));
    try std.testing.expect(isBuiltinCommand("/thinking high"));
    try std.testing.expect(isBuiltinCommand("/share"));
    try std.testing.expect(isBuiltinCommand("/skill:review"));
    try std.testing.expect(!isBuiltinCommand("/extension-command arg"));
}

test "interactive tree prompt honors branchSummary skipPrompt" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var sess = try session_mod.Session.init(gpa, "tree-prompt-166", "/tmp");
    defer sess.deinit();
    const root = try sess.appendMessage(null, "user", "root", null, null);
    const shared = try sess.appendMessage(root, "assistant", "shared", null, null);
    const target_user = try sess.appendMessage(shared, "user", "target", null, null);
    const target = try sess.appendMessage(target_user, "assistant", "target answer", null, null);
    try sess.setTip(shared);
    const abandoned_user = try sess.appendMessage(shared, "user", "abandoned", null, null);
    _ = try sess.appendMessage(abandoned_user, "assistant", "abandoned answer", null, null);

    const PromptProbe = struct {
        calls: usize = 0,
        fn prompt(raw: ?*anyopaque, _: std.mem.Allocator) anyerror!TreeSummaryChoice {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return .{};
        }
    };
    var prompt_probe = PromptProbe{};
    var cfg = @import("../agent/loop.zig").AgentConfig{};
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;
    var model_owned = false;
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |value| gpa.free(value);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |value| gpa.free(value);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |value| gpa.free(value);
    var live = live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = "/tmp",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &model,
        .active_model = null,
        .model_display_owned = &model_owned,
    };
    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = "/tmp",
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .live = &live,
        .tree_summary_prompt_ctx = &prompt_probe,
        .tree_summary_prompt_fn = PromptProbe.prompt,
    };

    const command = try std.fmt.allocPrint(gpa, "/tree {s}", .{target});
    defer gpa.free(command);
    try std.testing.expect((try handle(ctx, command)) == .handled);
    try std.testing.expectEqual(@as(usize, 1), prompt_probe.calls);
    try std.testing.expectEqualStrings(target, sess.lastEntryId().?);

    try sess.setTip(shared);
    const second_user = try sess.appendMessage(shared, "user", "second abandoned", null, null);
    _ = try sess.appendMessage(second_user, "assistant", "second answer", null, null);
    cfg.branch_summary_skip_prompt = true;
    try std.testing.expect((try handle(ctx, command)) == .handled);
    try std.testing.expectEqual(@as(usize, 1), prompt_probe.calls);
    try std.testing.expectEqualStrings(target, sess.lastEntryId().?);
}

test "interactive tree selector supplies target for bare command" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var sess = try session_mod.Session.init(gpa, "tree-select-167", "/tmp");
    defer sess.deinit();
    const root = try sess.appendMessage(null, "user", "root", null, null);
    const target = try sess.appendMessage(root, "assistant", "target", null, null);
    try sess.setTip(root);
    const abandoned = try sess.appendMessage(root, "assistant", "abandoned", null, null);
    try std.testing.expectEqualStrings(abandoned, sess.lastEntryId().?);

    const SelectProbe = struct {
        target: []const u8,
        calls: usize = 0,
        cancel: bool = false,

        fn prompt(raw: ?*anyopaque, allocator: std.mem.Allocator, _: *session_mod.Session) anyerror!TreeTargetChoice {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            if (self.cancel) return .{};
            return .{ .target_id = try allocator.dupe(u8, self.target), .cancelled = false };
        }
    };
    var probe = SelectProbe{ .target = target };
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;
    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = "/tmp",
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .tree_target_prompt_ctx = &probe,
        .tree_target_prompt_fn = SelectProbe.prompt,
    };

    try std.testing.expect((try handle(ctx, "/tree")) == .handled);
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqualStrings(target, sess.lastEntryId().?);

    probe.cancel = true;
    try std.testing.expect((try handle(ctx, "/tree")) == .handled);
    try std.testing.expectEqual(@as(usize, 2), probe.calls);
    try std.testing.expectEqualStrings(target, sess.lastEntryId().?);
}

test "handle /reload applies AGENTS.md into live agent_cfg" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const agents = try std.fs.path.join(gpa, &.{ tmp_path, "AGENTS.md" });
    defer gpa.free(agents);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents, .data = "reload-v1" });

    var sess = try session_mod.Session.init(gpa, "reload-test", tmp_path);
    defer sess.deinit();
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;
    var model_owned = false;
    var cfg = @import("../agent/loop.zig").AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);

    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |s| gpa.free(s);
    var live = live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .agent_dir = null,
        .trust_project = true,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &model,
        .active_model = null,
        .model_display_owned = &model_owned,
    };
    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = tmp_path,
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .trust_project = true,
        .live = &live,
    };

    try std.testing.expect((try handle(ctx, "/reload")) == .handled);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "reload-v1") != null);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents, .data = "reload-v2-APPLIED" });
    try std.testing.expect((try handle(ctx, "/reload")) == .handled);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "reload-v2-APPLIED") != null);
}

fn testExtensionProviderConfigFromManifest(
    gpa: std.mem.Allocator,
    manifest_json: []const u8,
    provider_name: []const u8,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.TestProviderNotFound;
    const providers_value = parsed.value.object.get("providers") orelse return error.TestProviderNotFound;
    if (providers_value != .array) return error.TestProviderNotFound;
    for (providers_value.array.items) |entry| {
        if (entry != .object) continue;
        const name = entry.object.get("name") orelse continue;
        const config = entry.object.get("config") orelse continue;
        if (name != .string or !std.mem.eql(u8, name.string, provider_name) or config != .object) continue;
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        try std.json.Stringify.value(config, .{}, &out.writer);
        return out.toOwnedSlice();
    }
    return error.TestProviderNotFound;
}

test "slash login executes extension OAuth and persists complete credentials" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  const common = { name: 'Slash OAuth', baseUrl: 'https://slash.invalid/v1', api: 'openai-completions', apiKey: 'unused', models: [{ id: 'slash-model', name: 'Slash Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }] };
        \\  pi.registerProvider('slash-oauth', { ...common, oauth: {
        \\    async login(callbacks) { if (!(callbacks.signal instanceof AbortSignal)) throw new Error('missing signal'); return { refresh: 'slash-refresh', access: 'slash-access', expires: 9999999999999, tenant: { id: 42 }, preserved: true }; },
        \\    getApiKey(credentials) { return `derived:${credentials.access}`; },
        \\  }});
        \\  pi.registerProvider('slash-oauth-broken', { ...common, oauth: {
        \\    async login() { throw new Error('slash OAuth rejection sentinel'); },
        \\    getApiKey(credentials) { return credentials.access; },
        \\  }});
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "slash-oauth.mjs", .data = source });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const source_path = try std.fs.path.join(gpa, &.{ root, "slash-oauth.mjs" });
    defer gpa.free(source_path);

    var started = try js_runtime.Runtime.start(gpa, io, source_path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const ProviderRegistry = @import("../extensions/provider_registry.zig").Registry;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = ProviderRegistry.init(gpa, io, &env, root, &.{}, &.{});
    defer registry.deinit();
    inline for (.{ "slash-oauth", "slash-oauth-broken" }) |provider_name| {
        const config_json = try testExtensionProviderConfigFromManifest(gpa, started.manifest_json, provider_name);
        defer gpa.free(config_json);
        try registry.registerJsonWithRuntime(provider_name, config_json, started.runtime);
    }
    var oauth_runtime = provider_oauth.Runtime.init(gpa, io, root, &registry);

    var sess = try session_mod.Session.init(gpa, "slash-oauth-182", root);
    defer sess.deinit();
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;
    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = root,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .extension_oauth = &oauth_runtime,
    };

    try std.testing.expectEqual(SlashResult.handled, try handle(ctx, "/login slash-oauth"));
    var store = try auth_storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    const persisted = (try store.readOAuthJson("slash-oauth")).?;
    defer gpa.free(persisted);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "\"preserved\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "\"tenant\":{\"id\":42}") != null);

    try std.testing.expectEqual(SlashResult.handled, try handle(ctx, "/login slash-oauth-broken browser"));
    try std.testing.expect((try store.readOAuthJson("slash-oauth-broken")) == null);
    const rejection = oauth_runtime.lastLoginError("slash-oauth-broken") orelse return error.MissingJavaScriptRejection;
    try std.testing.expect(std.mem.indexOf(u8, rejection, "slash OAuth rejection sentinel") != null);
}

test "Radius login gateway resolves custom OAuth provider and builtin default" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "{\"providers\":{\"radius-dev\":{\"baseUrl\":\"http://localhost:8788/v1\",\"oauth\":\"radius\"},\"corp\":{\"baseUrl\":\"http://corp\",\"api\":\"openai-completions\",\"models\":[]}}}" });
    const custom = (try radiusLoginGateway(gpa, io, root, "radius-dev")).?;
    defer gpa.free(custom);
    try std.testing.expectEqualStrings("http://localhost:8788", custom);
    const builtin = (try radiusLoginGateway(gpa, io, root, "radius")).?;
    defer gpa.free(builtin);
    try std.testing.expectEqualStrings("https://radius.pi.dev", builtin);
    try std.testing.expect((try radiusLoginGateway(gpa, io, root, "corp")) == null);
}

test "Kimi Coding login provider defaults to device-code identity" {
    try std.testing.expect(isKimiCodingProvider("kimi-coding"));
    try std.testing.expect(!isKimiCodingProvider("anthropic"));
}

test "slash copy writes the latest assistant text instead of printing it" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var sess = try session_mod.Session.init(gpa, "copy-176", "/tmp");
    defer sess.deinit();
    const user = try sess.appendMessage(null, "user", "question", null, null);
    _ = try sess.appendMessage(user, "assistant", "latest assistant answer", null, null);

    const Fake = struct {
        copied: std.ArrayList(u8) = .empty,
        fn run(
            raw: *anyopaque,
            _: std.mem.Allocator,
            _: Io,
            argv: []const []const u8,
            input: []const u8,
            _: u64,
            _: ?*const std.process.Environ.Map,
        ) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expectEqualStrings("pbcopy", argv[0]);
            try self.copied.appendSlice(gpa, input);
            return true;
        }
    };
    var fake = Fake{};
    defer fake.copied.deinit(gpa);
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;
    const result = try handle(.{
        .gpa = gpa,
        .io = io,
        .cwd = "/tmp",
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = null,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .clipboard_options = .{
            .platform = .macos,
            .write_runner = .{ .context = &fake, .run_fn = Fake.run },
        },
    }, "/copy");
    try std.testing.expectEqual(SlashResult.handled, result);
    try std.testing.expectEqualStrings("latest assistant answer", fake.copied.items);
}

test "bare login and logout use retained authentication selector choices" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    tui_render.setSilent(true);
    defer tui_render.setSilent(false);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    var sess = try session_mod.Session.init(gpa, "auth-selector-177", root);
    defer sess.deinit();
    var model: ?[]const u8 = null;
    var provider: ?[]const u8 = null;

    const Probe = struct {
        login_calls: usize = 0,
        logout_calls: usize = 0,
        expected_initial_query: ?[]const u8 = null,

        fn prompt(
            raw: ?*anyopaque,
            allocator: std.mem.Allocator,
            mode: AuthPromptMode,
            initial_query: ?[]const u8,
        ) anyerror!AuthTargetChoice {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (self.expected_initial_query) |expected| {
                try std.testing.expect(initial_query != null);
                try std.testing.expectEqualStrings(expected, initial_query.?);
                self.expected_initial_query = null;
            } else {
                try std.testing.expect(initial_query == null);
            }
            switch (mode) {
                .login => {
                    self.login_calls += 1;
                    return .{
                        .provider_id = try allocator.dupe(u8, "openai"),
                        .method = .api_key,
                        .api_key = try allocator.dupe(u8, "selector-secret-177"),
                        .cancelled = false,
                    };
                },
                .logout => {
                    self.logout_calls += 1;
                    return .{
                        .provider_id = try allocator.dupe(u8, "openai"),
                        .method = .api_key,
                        .cancelled = false,
                    };
                },
            }
        }
    };
    var probe = Probe{};
    const ctx = SlashContext{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .sess = &sess,
        .session_path = null,
        .session_dir = null,
        .agent_dir = root,
        .model = &model,
        .provider = &provider,
        .settings_text = "",
        .auth_target_prompt_ctx = &probe,
        .auth_target_prompt_fn = Probe.prompt,
    };

    try std.testing.expectEqual(SlashResult.handled, try handle(ctx, "/login"));
    var store = try auth_storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    var stored = (try store.read("openai")).?;
    defer stored.deinit(gpa);
    try std.testing.expectEqualStrings("selector-secret-177", stored.api_key.key.?);

    try std.testing.expectEqual(SlashResult.handled, try handle(ctx, "/logout"));
    try std.testing.expect((try store.read("openai")) == null);

    probe.expected_initial_query = "anthropic";
    try std.testing.expectEqual(SlashResult.handled, try handle(ctx, "/login anthropic"));
    try std.testing.expect(probe.expected_initial_query == null);
    try std.testing.expectEqual(@as(usize, 2), probe.login_calls);
    try std.testing.expectEqual(@as(usize, 1), probe.logout_calls);
}

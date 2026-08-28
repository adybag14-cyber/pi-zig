//! Retained fullscreen `/settings` selector.
//!
//! The native selector edits both global and trusted-project settings. Project
//! values are tri-state: explicit override or inherited effective value. Every
//! selection is persisted atomically under the shared configuration lock, the
//! menu remains open for further changes, and the caller performs one
//! transactional runtime reload when the selector closes.
const std = @import("std");
const Io = std.Io;
const settings_mod = @import("settings.zig");
const application = @import("../tui/application.zig");
const fuzzy = @import("../tui/fuzzy.zig");
const layout = @import("../tui/layout.zig");
const line_editor = @import("../tui/line_editor.zig");
const mouse = @import("../tui/mouse.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const tui_render = @import("../tui/render.zig");

const accent = "\x1b[36m";
const success = "\x1b[32m";
const warning = "\x1b[33m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reverse = "\x1b[7m";
const reset = "\x1b[0m";

pub const Result = struct {
    changed: bool = false,
    cancelled: bool = false,
};

const Item = struct {
    key: settings_mod.EditableKey,
    label: []const u8,
    description: []const u8,
};

const items = [_]Item{
    .{ .key = .compaction_enabled, .label = "Auto-compact", .description = "Automatically compact context before the active model window fills" },
    .{ .key = .compaction_reserve_tokens, .label = "Compaction reserve", .description = "Output and safety token reserve used to trigger compaction" },
    .{ .key = .compaction_keep_recent_tokens, .label = "Compaction retained tail", .description = "Recent context tokens retained after compaction" },
    .{ .key = .steering_mode, .label = "Steering mode", .description = "Deliver queued steering messages one at a time or all together" },
    .{ .key = .follow_up_mode, .label = "Follow-up mode", .description = "Deliver queued follow-up messages one at a time or all together" },
    .{ .key = .branch_summary_skip_prompt, .label = "Skip branch-summary prompt", .description = "Navigate without prompting unless --summary is explicit" },
    .{ .key = .branch_summary_reserve_tokens, .label = "Branch-summary reserve", .description = "Tokens reserved from the active model window during branch summaries" },
    .{ .key = .retry_enabled, .label = "Automatic retry", .description = "Retry transient assistant-turn failures" },
    .{ .key = .retry_max_retries, .label = "Assistant retry attempts", .description = "Retries after the initial assistant request" },
    .{ .key = .retry_base_delay_ms, .label = "Assistant retry delay", .description = "Base exponential-backoff delay" },
    .{ .key = .retry_provider_timeout_ms, .label = "Provider request timeout", .description = "Hard deadline for each provider request; zero disables it" },
    .{ .key = .retry_provider_max_retries, .label = "Provider retry attempts", .description = "Transport-level retries inside a provider request" },
    .{ .key = .retry_provider_max_retry_delay_ms, .label = "Maximum server retry delay", .description = "Cap for Retry-After; zero disables the cap" },
    .{ .key = .transport, .label = "Codex transport", .description = "Preferred SSE or WebSocket transport for compatible providers" },
    .{ .key = .http_idle_timeout_ms, .label = "HTTP idle timeout", .description = "Maximum idle gap between HTTP headers or body chunks" },
    .{ .key = .websocket_connect_timeout_ms, .label = "WebSocket connect timeout", .description = "Maximum connection/open-handshake time" },
    .{ .key = .thinking_level, .label = "Default thinking level", .description = "Reasoning depth used when a session has no explicit override" },
    .{ .key = .max_turns, .label = "Maximum agent turns", .description = "Hard turn limit for one user request" },
    .{ .key = .theme, .label = "Theme", .description = "Active custom terminal theme" },
    .{ .key = .collapse_changelog, .label = "Collapse changelog", .description = "Show a condensed update notice at startup" },
    .{ .key = .quiet_startup, .label = "Quiet startup", .description = "Suppress the normal interactive startup header" },
    .{ .key = .hide_thinking_block, .label = "Hide thinking block", .description = "Hide reasoning blocks while retaining them in durable history" },
    .{ .key = .show_cache_miss_notices, .label = "Cache-miss notices", .description = "Show transcript notices for significant prompt-cache misses" },
    .{ .key = .double_escape_action, .label = "Double-Escape action", .description = "Action used by an empty editor after two Escape presses" },
    .{ .key = .tree_filter_mode, .label = "Tree filter mode", .description = "Initial entry filter used by bare /tree" },
    .{ .key = .show_images, .label = "Show images", .description = "Render tool and extension images in capable terminals" },
    .{ .key = .image_width_cells, .label = "Image width", .description = "Preferred inline image width in terminal cells" },
    .{ .key = .clear_on_shrink, .label = "Clear on shrink", .description = "Clear stale terminal rows when retained output becomes shorter" },
    .{ .key = .show_terminal_progress, .label = "Terminal progress", .description = "Emit OSC 9;4 progress indicators while the agent is running" },
    .{ .key = .auto_resize_images, .label = "Auto-resize images", .description = "Resize oversized images before provider delivery" },
    .{ .key = .block_images, .label = "Block provider images", .description = "Keep images in session history but never send them to model providers" },
    .{ .key = .enable_skill_commands, .label = "Skill commands", .description = "Register discovered skills as /skill:name commands" },
    .{ .key = .show_hardware_cursor, .label = "Hardware cursor", .description = "Keep the terminal cursor visible for IME positioning" },
    .{ .key = .editor_padding_x, .label = "Editor padding", .description = "Horizontal padding for the interactive input editor" },
    .{ .key = .output_pad, .label = "Output padding", .description = "Horizontal padding for assistant and custom output" },
    .{ .key = .autocomplete_max_visible, .label = "Autocomplete rows", .description = "Maximum visible rows in the autocomplete menu" },
    .{ .key = .mermaid_mode, .label = "Mermaid rendering", .description = "Render Mermaid diagrams off, after completion, or while streaming" },
    .{ .key = .warning_anthropic_extra_usage, .label = "Anthropic usage warning", .description = "Warn about provider-reported extra usage" },
    .{ .key = .tui_mode, .label = "TUI mode", .description = "Use regular output or the alternate-screen fullscreen shell" },
    .{ .key = .fullscreen_exit_output, .label = "Fullscreen exit output", .description = "Print the transcript or only a resume hint when fullscreen exits" },
    .{ .key = .fullscreen_scrollbar, .label = "Fullscreen scrollbar", .description = "Automatic, always-visible, or hidden fullscreen scrollbar" },
    .{ .key = .enable_install_telemetry, .label = "Install telemetry", .description = "Send the anonymous version/update installation ping" },
    .{ .key = .default_project_trust, .label = "Default project trust", .description = "Fallback when no saved or extension trust decision exists" },
};

const Option = struct {
    label: []const u8,
    value: settings_mod.EditableValue,
};

const bool_options = [_]Option{
    .{ .label = "false", .value = .{ .boolean = false } },
    .{ .label = "true", .value = .{ .boolean = true } },
};
const max_turn_options = [_]Option{
    .{ .label = "1", .value = .{ .integer = 1 } },
    .{ .label = "4", .value = .{ .integer = 4 } },
    .{ .label = "8", .value = .{ .integer = 8 } },
    .{ .label = "16", .value = .{ .integer = 16 } },
    .{ .label = "32", .value = .{ .integer = 32 } },
    .{ .label = "64", .value = .{ .integer = 64 } },
    .{ .label = "128", .value = .{ .integer = 128 } },
};
const thinking_options = [_]Option{
    .{ .label = "off", .value = .{ .string = "off" } },
    .{ .label = "minimal", .value = .{ .string = "minimal" } },
    .{ .label = "low", .value = .{ .string = "low" } },
    .{ .label = "medium", .value = .{ .string = "medium" } },
    .{ .label = "high", .value = .{ .string = "high" } },
    .{ .label = "xhigh", .value = .{ .string = "xhigh" } },
    .{ .label = "max", .value = .{ .string = "max" } },
};
const transport_options = [_]Option{
    .{ .label = "auto", .value = .{ .string = "auto" } },
    .{ .label = "sse", .value = .{ .string = "sse" } },
    .{ .label = "websocket", .value = .{ .string = "websocket" } },
    .{ .label = "websocket-cached", .value = .{ .string = "websocket-cached" } },
};
const delivery_options = [_]Option{
    .{ .label = "one-at-a-time", .value = .{ .string = "one-at-a-time" } },
    .{ .label = "all", .value = .{ .string = "all" } },
};
const tree_filter_options = [_]Option{
    .{ .label = "default", .value = .{ .string = "default" } },
    .{ .label = "no-tools", .value = .{ .string = "no-tools" } },
    .{ .label = "user-only", .value = .{ .string = "user-only" } },
    .{ .label = "labeled-only", .value = .{ .string = "labeled-only" } },
    .{ .label = "all", .value = .{ .string = "all" } },
};
const double_escape_options = [_]Option{
    .{ .label = "tree", .value = .{ .string = "tree" } },
    .{ .label = "fork", .value = .{ .string = "fork" } },
    .{ .label = "none", .value = .{ .string = "none" } },
};
const mermaid_options = [_]Option{
    .{ .label = "off", .value = .{ .string = "off" } },
    .{ .label = "final", .value = .{ .string = "final" } },
    .{ .label = "streaming", .value = .{ .string = "streaming" } },
};
const tui_mode_options = [_]Option{
    .{ .label = "regular", .value = .{ .string = "regular" } },
    .{ .label = "fullscreen", .value = .{ .string = "fullscreen" } },
};
const fullscreen_exit_options = [_]Option{
    .{ .label = "transcript", .value = .{ .string = "transcript" } },
    .{ .label = "resume-hint", .value = .{ .string = "resume-hint" } },
};
const scrollbar_options = [_]Option{
    .{ .label = "auto", .value = .{ .string = "auto" } },
    .{ .label = "always", .value = .{ .string = "always" } },
    .{ .label = "hidden", .value = .{ .string = "hidden" } },
};
const padding_options = [_]Option{
    .{ .label = "0", .value = .{ .integer = 0 } },
    .{ .label = "1", .value = .{ .integer = 1 } },
    .{ .label = "2", .value = .{ .integer = 2 } },
    .{ .label = "3", .value = .{ .integer = 3 } },
};
const output_pad_options = [_]Option{
    .{ .label = "0", .value = .{ .integer = 0 } },
    .{ .label = "1", .value = .{ .integer = 1 } },
};
const autocomplete_options = [_]Option{
    .{ .label = "3", .value = .{ .integer = 3 } },
    .{ .label = "5", .value = .{ .integer = 5 } },
    .{ .label = "7", .value = .{ .integer = 7 } },
    .{ .label = "10", .value = .{ .integer = 10 } },
    .{ .label = "15", .value = .{ .integer = 15 } },
    .{ .label = "20", .value = .{ .integer = 20 } },
};
const trust_options = [_]Option{
    .{ .label = "ask", .value = .{ .string = "ask" } },
    .{ .label = "always", .value = .{ .string = "always" } },
    .{ .label = "never", .value = .{ .string = "never" } },
};
const token_reserve_options = [_]Option{
    .{ .label = "4K", .value = .{ .integer = 4_096 } },
    .{ .label = "8K", .value = .{ .integer = 8_192 } },
    .{ .label = "16K", .value = .{ .integer = 16_384 } },
    .{ .label = "32K", .value = .{ .integer = 32_768 } },
    .{ .label = "64K", .value = .{ .integer = 65_536 } },
};
const keep_recent_options = [_]Option{
    .{ .label = "5K", .value = .{ .integer = 5_000 } },
    .{ .label = "10K", .value = .{ .integer = 10_000 } },
    .{ .label = "20K", .value = .{ .integer = 20_000 } },
    .{ .label = "40K", .value = .{ .integer = 40_000 } },
    .{ .label = "80K", .value = .{ .integer = 80_000 } },
};
const image_width_options = [_]Option{
    .{ .label = "30", .value = .{ .integer = 30 } },
    .{ .label = "40", .value = .{ .integer = 40 } },
    .{ .label = "60", .value = .{ .integer = 60 } },
    .{ .label = "80", .value = .{ .integer = 80 } },
    .{ .label = "100", .value = .{ .integer = 100 } },
    .{ .label = "120", .value = .{ .integer = 120 } },
};
const retry_count_options = [_]Option{
    .{ .label = "0", .value = .{ .integer = 0 } },
    .{ .label = "1", .value = .{ .integer = 1 } },
    .{ .label = "2", .value = .{ .integer = 2 } },
    .{ .label = "3", .value = .{ .integer = 3 } },
    .{ .label = "4", .value = .{ .integer = 4 } },
    .{ .label = "5", .value = .{ .integer = 5 } },
    .{ .label = "8", .value = .{ .integer = 8 } },
};
const retry_delay_options = [_]Option{
    .{ .label = "250ms", .value = .{ .integer = 250 } },
    .{ .label = "500ms", .value = .{ .integer = 500 } },
    .{ .label = "1s", .value = .{ .integer = 1_000 } },
    .{ .label = "2s", .value = .{ .integer = 2_000 } },
    .{ .label = "5s", .value = .{ .integer = 5_000 } },
};
const request_timeout_options = [_]Option{
    .{ .label = "disabled", .value = .{ .integer = 0 } },
    .{ .label = "15s", .value = .{ .integer = 15_000 } },
    .{ .label = "30s", .value = .{ .integer = 30_000 } },
    .{ .label = "1m", .value = .{ .integer = 60_000 } },
    .{ .label = "5m", .value = .{ .integer = 300_000 } },
    .{ .label = "15m", .value = .{ .integer = 900_000 } },
};
const connect_timeout_options = [_]Option{
    .{ .label = "disabled", .value = .{ .integer = 0 } },
    .{ .label = "5s", .value = .{ .integer = 5_000 } },
    .{ .label = "15s", .value = .{ .integer = 15_000 } },
    .{ .label = "30s", .value = .{ .integer = 30_000 } },
    .{ .label = "1m", .value = .{ .integer = 60_000 } },
};
const max_retry_delay_options = [_]Option{
    .{ .label = "uncapped", .value = .{ .integer = 0 } },
    .{ .label = "5s", .value = .{ .integer = 5_000 } },
    .{ .label = "15s", .value = .{ .integer = 15_000 } },
    .{ .label = "30s", .value = .{ .integer = 30_000 } },
    .{ .label = "1m", .value = .{ .integer = 60_000 } },
};

fn staticOptions(key: settings_mod.EditableKey) []const Option {
    return switch (key) {
        .compaction_enabled,
        .branch_summary_skip_prompt,
        .retry_enabled,
        .collapse_changelog,
        .quiet_startup,
        .hide_thinking_block,
        .show_cache_miss_notices,
        .show_images,
        .clear_on_shrink,
        .show_terminal_progress,
        .auto_resize_images,
        .block_images,
        .enable_skill_commands,
        .show_hardware_cursor,
        .warning_anthropic_extra_usage,
        .enable_install_telemetry,
        => &bool_options,
        .max_turns => &max_turn_options,
        .thinking_level => &thinking_options,
        .transport => &transport_options,
        .steering_mode, .follow_up_mode => &delivery_options,
        .double_escape_action => &double_escape_options,
        .tree_filter_mode => &tree_filter_options,
        .mermaid_mode => &mermaid_options,
        .tui_mode => &tui_mode_options,
        .fullscreen_exit_output => &fullscreen_exit_options,
        .fullscreen_scrollbar => &scrollbar_options,
        .editor_padding_x => &padding_options,
        .output_pad => &output_pad_options,
        .autocomplete_max_visible => &autocomplete_options,
        .default_project_trust => &trust_options,
        .compaction_reserve_tokens, .branch_summary_reserve_tokens => &token_reserve_options,
        .compaction_keep_recent_tokens => &keep_recent_options,
        .image_width_cells => &image_width_options,
        .retry_max_retries, .retry_provider_max_retries => &retry_count_options,
        .retry_base_delay_ms => &retry_delay_options,
        .retry_provider_timeout_ms, .http_idle_timeout_ms => &request_timeout_options,
        .websocket_connect_timeout_ms => &connect_timeout_options,
        .retry_provider_max_retry_delay_ms => &max_retry_delay_options,
        .theme => &.{},
    };
}

const Ranked = struct { item_index: usize, score: i32 };

const Selector = struct {
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    trust_project: bool,
    theme_names: []const []const u8,
    scope: settings_mod.EditableScope = .global,
    global: settings_mod.Settings,
    project: settings_mod.Settings,
    current: settings_mod.Settings,
    visible: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    selected: usize = 0,
    viewport_rows: usize = 30,
    done: bool = false,
    cancelled: bool = false,
    changed: bool = false,
    status: ?[]u8 = null,
    rendered_start: usize = 0,
    rendered_count: usize = 0,

    fn init(
        gpa: std.mem.Allocator,
        io: Io,
        agent_dir: []const u8,
        cwd: []const u8,
        trust_project: bool,
        theme_names: []const []const u8,
    ) !Selector {
        var global = try loadGlobal(gpa, io, agent_dir);
        errdefer global.deinit(gpa);
        var project = try loadProject(gpa, io, cwd, trust_project);
        errdefer project.deinit(gpa);
        var current = try settings_mod.loadMergeTrusted(gpa, io, agent_dir, cwd, trust_project);
        errdefer current.deinit(gpa);
        var self: Selector = .{
            .gpa = gpa,
            .io = io,
            .agent_dir = agent_dir,
            .cwd = cwd,
            .trust_project = trust_project,
            .theme_names = theme_names,
            .global = global,
            .project = project,
            .current = current,
        };
        try self.rebuildVisible();
        return self;
    }

    fn deinit(self: *Selector) void {
        if (self.status) |value| self.gpa.free(value);
        self.query.deinit(self.gpa);
        self.visible.deinit(self.gpa);
        self.global.deinit(self.gpa);
        self.project.deinit(self.gpa);
        self.current.deinit(self.gpa);
        self.* = undefined;
    }

    fn component(self: *Selector) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    const vtable: layout.Component.VTable = .{
        .render = renderCallback,
        .handle_input = inputCallback,
        .handle_mouse = mouseCallback,
        .set_focus = focusCallback,
    };

    fn renderCallback(context: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Selector = @ptrCast(@alignCast(context));
        return self.render(gpa, width);
    }

    fn inputCallback(context: *anyopaque, data: []const u8) !void {
        const self: *Selector = @ptrCast(@alignCast(context));
        try self.handleInput(data);
    }

    fn mouseCallback(context: *anyopaque, event: mouse.Event) !bool {
        const self: *Selector = @ptrCast(@alignCast(context));
        return self.handleMouse(event);
    }

    fn focusCallback(_: *anyopaque, _: bool) void {}

    fn setStatus(self: *Selector, message: []const u8) !void {
        if (self.status) |old| self.gpa.free(old);
        self.status = try self.gpa.dupe(u8, message);
    }

    fn currentItem(self: *const Selector) ?Item {
        if (self.visible.items.len == 0 or self.selected >= self.visible.items.len) return null;
        return items[self.visible.items[self.selected]];
    }

    fn projectEditable(key: settings_mod.EditableKey) bool {
        return key != .enable_install_telemetry and key != .default_project_trust;
    }

    fn sourceSettings(self: *const Selector, key: settings_mod.EditableKey) *const settings_mod.Settings {
        return switch (self.scope) {
            .global => &self.global,
            .project => if (settings_mod.isEditableExplicit(self.project, key)) &self.project else &self.current,
        };
    }

    fn currentValue(self: *const Selector, key: settings_mod.EditableKey) settings_mod.EditableValue {
        const source = self.sourceSettings(key);
        return switch (key) {
            .max_turns => .{ .integer = @intCast(source.max_turns) },
            .thinking_level => .{ .string = source.thinking_level orelse "off" },
            .theme => .{ .string = source.theme orelse "default" },
            .transport => .{ .string = if (source.transport) |value| switch (value) {
                .sse => "sse",
                .websocket => "websocket",
                .websocket_cached => "websocket-cached",
                .auto => "auto",
            } else "auto" },
            .steering_mode => .{ .string = if (source.steering_mode) |mode| mode.wireName() else "one-at-a-time" },
            .follow_up_mode => .{ .string = if (source.follow_up_mode) |mode| mode.wireName() else "one-at-a-time" },
            .collapse_changelog => .{ .boolean = source.collapse_changelog orelse false },
            .quiet_startup => .{ .boolean = source.quiet_startup orelse false },
            .hide_thinking_block => .{ .boolean = source.hide_thinking_block orelse false },
            .show_cache_miss_notices => .{ .boolean = source.show_cache_miss_notices orelse false },
            .double_escape_action => .{ .string = if (source.double_escape_action) |action| action.wireName() else "tree" },
            .tree_filter_mode => .{ .string = if (source.tree_filter_mode) |mode| mode.wireName() else "default" },
            .show_images => .{ .boolean = source.show_images orelse true },
            .image_width_cells => .{ .integer = @intCast(source.image_width_cells orelse 60) },
            .clear_on_shrink => .{ .boolean = source.clear_on_shrink orelse false },
            .show_terminal_progress => .{ .boolean = source.show_terminal_progress orelse false },
            .auto_resize_images => .{ .boolean = source.auto_resize_images orelse true },
            .block_images => .{ .boolean = source.block_images orelse false },
            .enable_skill_commands => .{ .boolean = source.enable_skill_commands orelse true },
            .editor_padding_x => .{ .integer = @intCast(source.editor_padding_x orelse 0) },
            .output_pad => .{ .integer = @intCast(source.output_pad orelse 1) },
            .autocomplete_max_visible => .{ .integer = @intCast(source.autocomplete_max_visible orelse 5) },
            .show_hardware_cursor => .{ .boolean = source.show_hardware_cursor orelse false },
            .mermaid_mode => .{ .string = if (source.mermaid_mode) |mode| mode.wireName() else "streaming" },
            .warning_anthropic_extra_usage => .{ .boolean = source.warning_anthropic_extra_usage orelse true },
            .tui_mode => .{ .string = if (source.tui_mode) |mode| mode.wireName() else "regular" },
            .fullscreen_exit_output => .{ .string = if (source.fullscreen_exit_output) |mode| mode.wireName() else "transcript" },
            .fullscreen_scrollbar => .{ .string = if (source.fullscreen_scrollbar) |mode| mode.wireName() else "auto" },
            .enable_install_telemetry => .{ .boolean = source.enable_install_telemetry orelse true },
            .http_idle_timeout_ms => .{ .integer = @intCast(source.http_idle_timeout_ms orelse 300_000) },
            .websocket_connect_timeout_ms => .{ .integer = @intCast(source.websocket_connect_timeout_ms orelse 15_000) },
            .compaction_enabled => .{ .boolean = source.compaction_enabled orelse true },
            .compaction_reserve_tokens => .{ .integer = @intCast(source.compaction_reserve_tokens orelse 16_384) },
            .compaction_keep_recent_tokens => .{ .integer = @intCast(source.compaction_keep_recent_tokens orelse 20_000) },
            .branch_summary_reserve_tokens => .{ .integer = @intCast(source.branch_summary_reserve_tokens orelse 16_384) },
            .branch_summary_skip_prompt => .{ .boolean = source.branch_summary_skip_prompt orelse false },
            .retry_enabled => .{ .boolean = source.retry_enabled orelse true },
            .retry_max_retries => .{ .integer = @intCast(source.retry_max_retries orelse 3) },
            .retry_base_delay_ms => .{ .integer = @intCast(source.retry_base_delay_ms orelse 2_000) },
            .retry_provider_timeout_ms => .{ .integer = @intCast(source.retry_provider_timeout_ms orelse source.http_idle_timeout_ms orelse 300_000) },
            .retry_provider_max_retries => .{ .integer = @intCast(source.retry_provider_max_retries orelse 2) },
            .retry_provider_max_retry_delay_ms => .{ .integer = @intCast(source.retry_provider_max_retry_delay_ms orelse 60_000) },
            .default_project_trust => .{ .string = @tagName(source.default_project_trust) },
        };
    }

    fn valueEqual(lhs: settings_mod.EditableValue, rhs: settings_mod.EditableValue) bool {
        return switch (lhs) {
            .boolean => |value| switch (rhs) {
                .boolean => |other| value == other,
                else => false,
            },
            .integer => |value| switch (rhs) {
                .integer => |other| value == other,
                else => false,
            },
            .string => |value| switch (rhs) {
                .string => |other| std.mem.eql(u8, value, other),
                else => false,
            },
        };
    }

    fn valueLabelAlloc(self: *const Selector, key: settings_mod.EditableKey) ![]u8 {
        const value = self.currentValue(key);
        const base = if (key == .theme)
            try self.gpa.dupe(u8, value.string)
        else blk: {
            for (staticOptions(key)) |option| if (valueEqual(value, option.value)) break :blk try self.gpa.dupe(u8, option.label);
            break :blk switch (value) {
                .boolean => |boolean| try self.gpa.dupe(u8, if (boolean) "true" else "false"),
                .integer => |integer| try std.fmt.allocPrint(self.gpa, "{d}", .{integer}),
                .string => |string| try self.gpa.dupe(u8, string),
            };
        };
        if (self.scope != .project or settings_mod.isEditableExplicit(self.project, key)) return base;
        defer self.gpa.free(base);
        return std.fmt.allocPrint(self.gpa, "inherit → {s}", .{base});
    }

    fn scoreItem(self: *const Selector, item: Item) !?i32 {
        if (self.query.items.len == 0) return 0;
        const value = try self.valueLabelAlloc(item.key);
        defer self.gpa.free(value);
        const fields = [_][]const u8{ item.label, item.description, value, @tagName(item.key) };
        return fuzzy.bestScore(&fields, self.query.items);
    }

    fn rebuildVisible(self: *Selector) !void {
        self.visible.clearRetainingCapacity();
        var ranked: std.ArrayList(Ranked) = .empty;
        defer ranked.deinit(self.gpa);
        for (items, 0..) |item, index| {
            if (self.scope == .project and !projectEditable(item.key)) continue;
            const score = (try self.scoreItem(item)) orelse continue;
            try ranked.append(self.gpa, .{ .item_index = index, .score = score });
        }
        std.mem.sort(Ranked, ranked.items, {}, struct {
            fn lessThan(_: void, lhs: Ranked, rhs: Ranked) bool {
                if (lhs.score != rhs.score) return lhs.score > rhs.score;
                return lhs.item_index < rhs.item_index;
            }
        }.lessThan);
        for (ranked.items) |entry| try self.visible.append(self.gpa, entry.item_index);
        if (self.visible.items.len == 0) self.selected = 0 else if (self.selected >= self.visible.items.len) self.selected = self.visible.items.len - 1;
    }

    fn rebuildVisiblePreserving(self: *Selector, preserve: ?settings_mod.EditableKey) !void {
        try self.rebuildVisible();
        const key = preserve orelse return;
        for (self.visible.items, 0..) |item_index, index| {
            if (items[item_index].key == key) {
                self.selected = index;
                return;
            }
        }
    }

    fn moveSelection(self: *Selector, delta: isize) void {
        if (self.visible.items.len == 0) return;
        const count: isize = @intCast(self.visible.items.len);
        const current: isize = @intCast(self.selected);
        self.selected = @intCast(@mod(current + delta, count));
    }

    fn themeValue(self: *const Selector, direction: isize) ?settings_mod.EditableValue {
        if (self.theme_names.len == 0) return null;
        const current = self.currentValue(.theme).string;
        var current_index: ?usize = null;
        for (self.theme_names, 0..) |candidate, index| {
            if (std.mem.eql(u8, current, candidate)) {
                current_index = index;
                break;
            }
        }
        const start: isize = if (current_index) |index| @intCast(index) else if (direction >= 0) -1 else 0;
        const next: usize = @intCast(@mod(start + direction, @as(isize, @intCast(self.theme_names.len))));
        return .{ .string = self.theme_names[next] };
    }

    fn nextValue(self: *const Selector, key: settings_mod.EditableKey, direction: isize) ?settings_mod.EditableValue {
        if (key == .theme) return self.themeValue(direction);
        const options = staticOptions(key);
        if (options.len == 0) return null;
        const current = self.currentValue(key);
        var current_index: ?usize = null;
        for (options, 0..) |option, index| if (valueEqual(current, option.value)) {
            current_index = index;
            break;
        };
        const start: isize = if (current_index) |index| @intCast(index) else if (direction >= 0) -1 else 0;
        const next: usize = @intCast(@mod(start + direction, @as(isize, @intCast(options.len))));
        return options[next].value;
    }

    fn reloadSettings(self: *Selector) !void {
        var next_global = try loadGlobal(self.gpa, self.io, self.agent_dir);
        errdefer next_global.deinit(self.gpa);
        var next_project = try loadProject(self.gpa, self.io, self.cwd, self.trust_project);
        errdefer next_project.deinit(self.gpa);
        var next_current = try settings_mod.loadMergeTrusted(self.gpa, self.io, self.agent_dir, self.cwd, self.trust_project);
        errdefer next_current.deinit(self.gpa);

        self.global.deinit(self.gpa);
        self.project.deinit(self.gpa);
        self.current.deinit(self.gpa);
        self.global = next_global;
        self.project = next_project;
        self.current = next_current;
    }

    fn changeCurrent(self: *Selector, direction: isize) !void {
        const item = self.currentItem() orelse return;
        if (self.scope == .project and !projectEditable(item.key)) {
            try self.setStatus("This setting is global-only");
            return;
        }
        const value = self.nextValue(item.key, direction) orelse {
            try self.setStatus("No custom themes are currently installed");
            return;
        };
        settings_mod.setEditableScoped(
            self.gpa,
            self.io,
            self.agent_dir,
            self.cwd,
            self.trust_project,
            self.scope,
            item.key,
            value,
        ) catch |err| {
            const message = try std.fmt.allocPrint(self.gpa, "Could not save setting: {s}", .{@errorName(err)});
            defer self.gpa.free(message);
            try self.setStatus(message);
            return;
        };
        try self.reloadSettings();
        self.changed = true;
        if (self.status) |old| {
            self.gpa.free(old);
            self.status = null;
        }
        try self.rebuildVisiblePreserving(item.key);
    }

    fn clearCurrentOverride(self: *Selector) !void {
        if (self.scope != .project) return;
        const item = self.currentItem() orelse return;
        if (!settings_mod.isEditableExplicit(self.project, item.key)) {
            try self.setStatus("This project setting already inherits its global value");
            return;
        }
        settings_mod.clearEditableScoped(
            self.gpa,
            self.io,
            self.agent_dir,
            self.cwd,
            self.trust_project,
            .project,
            item.key,
        ) catch |err| {
            const message = try std.fmt.allocPrint(self.gpa, "Could not clear project override: {s}", .{@errorName(err)});
            defer self.gpa.free(message);
            try self.setStatus(message);
            return;
        };
        try self.reloadSettings();
        self.changed = true;
        try self.setStatus("Project override cleared; the global value is inherited");
        try self.rebuildVisiblePreserving(item.key);
    }

    fn toggleScope(self: *Selector) !void {
        if (!self.trust_project) {
            try self.setStatus("Project settings require an approved/trusted project");
            return;
        }
        self.scope = if (self.scope == .global) .project else .global;
        self.selected = 0;
        try self.rebuildVisible();
        if (self.status) |old| {
            self.gpa.free(old);
            self.status = null;
        }
    }

    fn popUtf8(list: *std.ArrayList(u8)) void {
        if (list.items.len == 0) return;
        var index = list.items.len - 1;
        while (index > 0 and (list.items[index] & 0xc0) == 0x80) : (index -= 1) {}
        list.shrinkRetainingCapacity(index);
    }

    fn clearSearchOrClose(self: *Selector) !void {
        if (self.query.items.len > 0) {
            const preserve = if (self.currentItem()) |item| item.key else null;
            self.query.clearRetainingCapacity();
            self.selected = 0;
            try self.rebuildVisiblePreserving(preserve);
            return;
        }
        self.done = true;
    }

    fn handleDecodedKey(self: *Selector, key: terminal.Key) !void {
        switch (key) {
            .up => self.moveSelection(-1),
            .down => self.moveSelection(1),
            .home => self.selected = 0,
            .end => {
                if (self.visible.items.len > 0) self.selected = self.visible.items.len - 1;
            },
            .left => try self.changeCurrent(-1),
            .right, .enter => try self.changeCurrent(1),
            .tab => try self.toggleScope(),
            .backspace => if (self.query.items.len > 0) {
                popUtf8(&self.query);
                self.selected = 0;
                try self.rebuildVisible();
            } else try self.clearCurrentOverride(),
            .delete => if (self.query.items.len > 0) {
                self.query.clearRetainingCapacity();
                self.selected = 0;
                try self.rebuildVisible();
            } else try self.clearCurrentOverride(),
            .escape => try self.clearSearchOrClose(),
            .ctrl_c, .ctrl_d => {
                self.cancelled = true;
                self.done = true;
            },
            .text => |byte| if (byte == ' ' and self.query.items.len == 0) {
                try self.changeCurrent(1);
            } else if (byte >= 0x20) {
                try self.query.append(self.gpa, byte);
                self.selected = 0;
                try self.rebuildVisible();
            },
            else => {},
        }
    }

    fn handleInput(self: *Selector, data: []const u8) !void {
        if (std.mem.eql(u8, data, "\x1b[5~")) {
            self.moveSelection(-@as(isize, @intCast(self.pageSize())));
            return;
        }
        if (std.mem.eql(u8, data, "\x1b[6~")) {
            self.moveSelection(@intCast(self.pageSize()));
            return;
        }
        if (std.mem.eql(u8, data, "\x1b")) return self.clearSearchOrClose();
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                const byte = data[offset];
                if (byte >= 0x20) {
                    try self.query.append(self.gpa, byte);
                    self.selected = 0;
                    try self.rebuildVisible();
                }
                offset += 1;
                continue;
            };
            try self.handleDecodedKey(decoded.key);
            offset += decoded.consumed;
        }
    }

    fn handleMouse(self: *Selector, event: mouse.Event) !bool {
        if (event.kind == .scroll) {
            switch (event.button) {
                .wheel_up => self.moveSelection(-3),
                .wheel_down => self.moveSelection(3),
                else => return false,
            }
            return true;
        }
        if (event.kind != .press or event.button != .left) return false;
        if (event.y < 4 or event.y >= 4 + self.rendered_count) return false;
        const visible_index = self.rendered_start + (event.y - 4);
        if (visible_index >= self.visible.items.len) return false;
        self.selected = visible_index;
        return true;
    }

    fn pageSize(self: *const Selector) usize {
        return @max(@as(usize, 1), self.viewport_rows -| 9);
    }

    fn render(self: *Selector, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        const scope_name = if (self.scope == .global) "GLOBAL" else "PROJECT";
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Settings{s}  {s}{s}{s}  {s}Tab{s} scope  {s}←/→/Enter{s} change  {s}Esc{s} clear/close", .{ bold, reset, accent, scope_name, reset, dim, reset, dim, reset, dim, reset }));
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Project values inherit global settings until explicitly changed; Backspace/Delete clears an override.{s}", .{ dim, reset }));
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Search: {s}{s}_{s}", .{ accent, self.query.items, reset }));
        try lines.append(gpa, try gpa.dupe(u8, ""));

        self.rendered_start = 0;
        self.rendered_count = 0;
        if (self.visible.items.len == 0) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  No matching settings{s}", .{ dim, reset }));
        } else {
            const count = self.pageSize();
            const half = count / 2;
            var start = self.selected -| half;
            if (start + count > self.visible.items.len) start = self.visible.items.len -| count;
            const end = @min(self.visible.items.len, start + count);
            self.rendered_start = start;
            self.rendered_count = end - start;
            for (self.visible.items[start..end], start..) |item_index, visible_index| {
                const item = items[item_index];
                const selected = visible_index == self.selected;
                const value = try self.valueLabelAlloc(item.key);
                defer gpa.free(value);
                var line: std.Io.Writer.Allocating = .init(gpa);
                defer line.deinit();
                if (selected) try line.writer.writeAll(reverse);
                try line.writer.print("{s} {s}{s}{s}", .{ if (selected) ">" else " ", if (selected) accent else "", item.label, if (selected) reset else "" });
                const label_width = terminal_text.visibleWidth(item.label);
                const pad = if (label_width < 32) 32 - label_width else 1;
                for (0..pad) |_| try line.writer.writeByte(' ');
                try line.writer.print("{s}{s}{s}", .{ if (selected) success else dim, value, reset });
                if (selected) try line.writer.writeAll(reset);
                try appendClipped(gpa, &lines, width, try line.toOwnedSlice());
            }
            const current = self.currentItem().?;
            try lines.append(gpa, try gpa.dupe(u8, ""));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {s}{s}", .{ dim, current.description, reset }));
            const inherited = self.scope == .project and !settings_mod.isEditableExplicit(self.project, current.key);
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {d}/{d} settings · {s} · mouse wheel/click supported{s}", .{ dim, self.selected + 1, self.visible.items.len, if (inherited) "inherited" else "explicit", reset }));
        }
        if (self.status) |message| try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ warning, message, reset }));
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }
};

fn appendClipped(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), width: usize, owned: []u8) !void {
    defer gpa.free(owned);
    try lines.append(gpa, try terminal_text.truncateAlloc(gpa, owned, width, .{ .ellipsis = "…", .reset_style = true }));
}

fn loadGlobal(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) !settings_mod.Settings {
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(path);
    return settings_mod.loadFile(gpa, io, path);
}

fn loadProject(gpa: std.mem.Allocator, io: Io, cwd: []const u8, trust_project: bool) !settings_mod.Settings {
    if (!trust_project) return .{};
    const path = try std.fs.path.join(gpa, &.{ cwd, ".pi", "settings.json" });
    defer gpa.free(path);
    return settings_mod.loadFile(gpa, io, path);
}

fn readInputChunk(io: Io, reader: ?*Io.File.Reader, buffer: []u8) !usize {
    if (reader) |buffered| {
        const available = buffered.interface.bufferedLen();
        if (available > 0) {
            const count = @min(available, buffer.len);
            const source = try buffered.interface.take(count);
            @memcpy(buffer[0..count], source);
            return count;
        }
    }
    var slices = [_][]u8{buffer};
    return Io.File.stdin().readStreaming(io, &slices);
}

pub fn run(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    agent_dir: []const u8,
    cwd: []const u8,
    trust_project: bool,
    theme_names: []const []const u8,
    already_fullscreen: bool,
) !Result {
    if (!terminal.supportsFullscreen(io)) return error.UnsupportedTerminal;
    var selector = try Selector.init(gpa, io, agent_dir, cwd, trust_project, theme_names);
    defer selector.deinit();
    var app = application.Application.init(gpa, selector.component());
    defer app.deinit();
    app.setFocus(selector.component());

    var raw = try line_editor.RawMode.enter();
    defer raw.leave();
    if (already_fullscreen) {
        try tui_render.writeAll(io, terminal.clear_screen ++ terminal.hide_cursor ++ terminal.bracketed_paste_enable ++ application.mouse_enable);
        defer tui_render.writeAll(io, application.mouse_disable ++ terminal.bracketed_paste_disable ++ terminal.show_cursor ++ terminal.clear_screen) catch {};
    } else {
        try app.start(io);
        defer app.stop(io) catch {};
    }

    var input_buffer: [4096]u8 = undefined;
    while (!selector.done) {
        const dimensions = terminal.terminalDimensions(environ, .{ .columns = 100, .rows = 30 });
        selector.viewport_rows = dimensions.rows;
        try app.paint(io, dimensions.columns, dimensions.rows);
        const count = readInputChunk(io, reader, input_buffer[0..]) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (count == 0) break;
        try app.handleInput(input_buffer[0..count]);
    }
    return .{ .changed = selector.changed, .cancelled = selector.cancelled };
}

test "settings selector cycles boolean and persists through settings parser" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    var selector = try Selector.init(gpa, io, root, root, true, &.{});
    defer selector.deinit();
    selector.selected = 0;
    try selector.changeCurrent(1);
    try std.testing.expect(selector.changed);
    try std.testing.expectEqual(false, selector.current.compaction_enabled.?);
}

test "settings selector persists media privacy and skill command controls" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    var selector = try Selector.init(gpa, io, root, root, true, &.{});
    defer selector.deinit();

    inline for (.{
        settings_mod.EditableKey.show_images,
        settings_mod.EditableKey.image_width_cells,
        settings_mod.EditableKey.block_images,
        settings_mod.EditableKey.enable_skill_commands,
    }) |wanted| {
        for (items, 0..) |item, index| if (item.key == wanted) {
            selector.visible.clearRetainingCapacity();
            try selector.visible.append(gpa, index);
            selector.selected = 0;
            try selector.changeCurrent(1);
            break;
        };
    }
    try std.testing.expectEqual(@as(?bool, false), selector.current.show_images);
    try std.testing.expectEqual(@as(?u64, 80), selector.current.image_width_cells);
    try std.testing.expectEqual(@as(?bool, true), selector.current.block_images);
    try std.testing.expectEqual(@as(?bool, false), selector.current.enable_skill_commands);
}

test "settings selector fuzzy search ranks retry timeout" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    var selector = try Selector.init(gpa, io, root, root, true, &.{});
    defer selector.deinit();
    try selector.query.appendSlice(gpa, "provider timeout");
    try selector.rebuildVisible();
    try std.testing.expect(selector.visible.items.len > 0);
    try std.testing.expectEqual(settings_mod.EditableKey.retry_provider_timeout_ms, items[selector.visible.items[0]].key);
}

test "settings selector edits and clears trusted project overrides" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const cwd = try std.fs.path.join(gpa, &.{ root, "project" });
    defer gpa.free(cwd);
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    try std.Io.Dir.cwd().createDirPath(io, cwd);
    try settings_mod.setEditableScoped(gpa, io, agent_dir, cwd, true, .global, .show_terminal_progress, .{ .boolean = false });

    var selector = try Selector.init(gpa, io, agent_dir, cwd, true, &.{});
    defer selector.deinit();
    try selector.toggleScope();
    try std.testing.expectEqual(settings_mod.EditableScope.project, selector.scope);
    for (items, 0..) |item, index| if (item.key == .show_terminal_progress) {
        selector.visible.clearRetainingCapacity();
        try selector.visible.append(gpa, index);
        selector.selected = 0;
        break;
    };
    try selector.changeCurrent(1);
    try std.testing.expect(settings_mod.isEditableExplicit(selector.project, .show_terminal_progress));
    try std.testing.expectEqual(@as(?bool, true), selector.current.show_terminal_progress);
    for (selector.visible.items, 0..) |item_index, visible_index| if (items[item_index].key == .show_terminal_progress) {
        selector.selected = visible_index;
        break;
    };
    try selector.clearCurrentOverride();
    try std.testing.expect(!settings_mod.isEditableExplicit(selector.project, .show_terminal_progress));
    try std.testing.expectEqual(@as(?bool, false), selector.current.show_terminal_progress);
}

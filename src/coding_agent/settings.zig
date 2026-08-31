//! settings.json global + project merge.
const std = @import("std");
const Io = std.Io;
const codex_ws = @import("../ai/codex_websocket.zig");
const packages = @import("packages.zig");

pub const DefaultProjectTrust = enum { ask, always, never };

pub const DeliveryMode = enum {
    all,
    one_at_a_time,

    pub fn parse(value: []const u8) ?DeliveryMode {
        if (std.ascii.eqlIgnoreCase(value, "all")) return .all;
        if (std.ascii.eqlIgnoreCase(value, "one-at-a-time") or std.ascii.eqlIgnoreCase(value, "one_at_a_time")) return .one_at_a_time;
        return null;
    }

    pub fn wireName(self: DeliveryMode) []const u8 {
        return switch (self) {
            .all => "all",
            .one_at_a_time => "one-at-a-time",
        };
    }
};

pub const TreeFilterMode = enum {
    default,
    no_tools,
    user_only,
    labeled_only,
    all,

    pub fn parse(value: []const u8) ?TreeFilterMode {
        if (std.ascii.eqlIgnoreCase(value, "default")) return .default;
        if (std.ascii.eqlIgnoreCase(value, "no-tools") or std.ascii.eqlIgnoreCase(value, "no_tools")) return .no_tools;
        if (std.ascii.eqlIgnoreCase(value, "user-only") or std.ascii.eqlIgnoreCase(value, "user_only")) return .user_only;
        if (std.ascii.eqlIgnoreCase(value, "labeled-only") or std.ascii.eqlIgnoreCase(value, "labeled_only")) return .labeled_only;
        if (std.ascii.eqlIgnoreCase(value, "all")) return .all;
        return null;
    }

    pub fn wireName(self: TreeFilterMode) []const u8 {
        return switch (self) {
            .default => "default",
            .no_tools => "no-tools",
            .user_only => "user-only",
            .labeled_only => "labeled-only",
            .all => "all",
        };
    }
};

pub const TuiMode = enum {
    regular,
    fullscreen,

    pub fn parse(value: []const u8) ?TuiMode {
        if (std.ascii.eqlIgnoreCase(value, "regular")) return .regular;
        if (std.ascii.eqlIgnoreCase(value, "fullscreen")) return .fullscreen;
        return null;
    }

    pub fn wireName(self: TuiMode) []const u8 {
        return @tagName(self);
    }
};

pub const FullscreenExitOutput = enum {
    transcript,
    resume_hint,

    pub fn parse(value: []const u8) ?FullscreenExitOutput {
        if (std.ascii.eqlIgnoreCase(value, "transcript")) return .transcript;
        if (std.ascii.eqlIgnoreCase(value, "resume-hint") or std.ascii.eqlIgnoreCase(value, "resume_hint")) return .resume_hint;
        return null;
    }

    pub fn wireName(self: FullscreenExitOutput) []const u8 {
        return switch (self) {
            .transcript => "transcript",
            .resume_hint => "resume-hint",
        };
    }
};

pub const FullscreenScrollbar = enum {
    auto,
    always,
    hidden,

    pub fn parse(value: []const u8) ?FullscreenScrollbar {
        if (std.ascii.eqlIgnoreCase(value, "auto")) return .auto;
        if (std.ascii.eqlIgnoreCase(value, "always")) return .always;
        if (std.ascii.eqlIgnoreCase(value, "hidden")) return .hidden;
        return null;
    }

    pub fn wireName(self: FullscreenScrollbar) []const u8 {
        return @tagName(self);
    }
};

pub const DoubleEscapeAction = enum {
    fork,
    tree,
    none,

    pub fn parse(value: []const u8) ?DoubleEscapeAction {
        if (std.ascii.eqlIgnoreCase(value, "fork")) return .fork;
        if (std.ascii.eqlIgnoreCase(value, "tree")) return .tree;
        if (std.ascii.eqlIgnoreCase(value, "none")) return .none;
        return null;
    }

    pub fn wireName(self: DoubleEscapeAction) []const u8 {
        return @tagName(self);
    }
};

pub const MermaidMode = enum {
    off,
    final,
    streaming,

    pub fn parse(value: []const u8) ?MermaidMode {
        if (std.ascii.eqlIgnoreCase(value, "off")) return .off;
        if (std.ascii.eqlIgnoreCase(value, "final")) return .final;
        if (std.ascii.eqlIgnoreCase(value, "streaming")) return .streaming;
        return null;
    }

    pub fn wireName(self: MermaidMode) []const u8 {
        return @tagName(self);
    }
};

pub const TerminalImageProtocol = enum { kitty, iterm2, none };

pub const Settings = struct {
    model: ?[]const u8 = null,
    provider: ?[]const u8 = null,
    /// Initial native built-in selection. Extension and SDK tools are not
    /// filtered by this list.
    tools: ?[]const []const u8 = null,
    /// Persistent model-cycle scope. CLI --models overrides this list for one
    /// run; Ctrl+S appends a newly persisted default when the scope is non-empty.
    enabled_models: ?[]const []const u8 = null,
    max_turns: usize = 16,
    /// Tracks whether maxTurns was present so a project can explicitly override
    /// a non-default global value back to the upstream default of 16.
    max_turns_explicit: bool = false,
    thinking_level: ?[]const u8 = null,
    /// Active theme name. Custom definitions are resolved by the resource loader.
    theme: ?[]const u8 = null,
    /// Preferred Codex stream transport. Null means upstream default `auto`.
    transport: ?codex_ws.Transport = null,
    /// Original steering/follow-up delivery modes.
    steering_mode: ?DeliveryMode = null,
    follow_up_mode: ?DeliveryMode = null,
    /// Global HTTP(S) proxy URL. Project settings may not override this value.
    http_proxy: ?[]const u8 = null,
    /// Last upstream release whose bundled changelog was acknowledged. This is
    /// global lifecycle state and is never inherited from a project checkout.
    last_changelog_version: ?[]const u8 = null,
    /// Condense startup changelog output to a one-line notice.
    collapse_changelog: ?bool = null,
    /// Suppress the normal startup header.
    quiet_startup: ?bool = null,
    /// Hide assistant reasoning blocks while retaining their durable content.
    hide_thinking_block: ?bool = null,
    /// Show transcript notices for significant prompt-cache misses.
    show_cache_miss_notices: ?bool = null,
    /// Original double-Escape action when the editor is empty.
    double_escape_action: ?DoubleEscapeAction = null,
    /// Initial filter used by bare interactive `/tree`.
    tree_filter_mode: ?TreeFilterMode = null,
    /// Render image content in capable terminals. Defaults to true.
    show_images: ?bool = null,
    /// Preferred inline image width in terminal cells. Defaults to 60.
    image_width_cells: ?u64 = null,
    /// Advanced terminal capability overrides. Null preserves auto-detection.
    terminal_hyperlinks: ?bool = null,
    terminal_image_protocol: ?TerminalImageProtocol = null,
    terminal_true_color: ?bool = null,
    /// Clear stale terminal rows when retained output shrinks.
    clear_on_shrink: ?bool = null,
    /// Emit OSC 9;4 progress while an agent request is active.
    show_terminal_progress: ?bool = null,
    /// Resize oversized images before provider delivery. Defaults to true.
    auto_resize_images: ?bool = null,
    /// Prevent every image block from reaching model-provider requests.
    block_images: ?bool = null,
    /// Register discovered skills as `/skill:name` commands. Defaults to true.
    enable_skill_commands: ?bool = null,
    /// Horizontal input-editor padding (0-3).
    editor_padding_x: ?u64 = null,
    /// Horizontal output padding (0 or 1).
    output_pad: ?u64 = null,
    /// Maximum visible autocomplete rows (3-20).
    autocomplete_max_visible: ?u64 = null,
    /// Keep the hardware cursor visible for IME positioning.
    show_hardware_cursor: ?bool = null,
    /// Mermaid rendering mode inside Markdown.
    mermaid_mode: ?MermaidMode = null,
    /// Anthropic extra-usage warning toggle.
    warning_anthropic_extra_usage: ?bool = null,
    /// Default terminal interface mode and fullscreen exit behavior.
    tui_mode: ?TuiMode = null,
    fullscreen_exit_output: ?FullscreenExitOutput = null,
    fullscreen_scrollbar: ?FullscreenScrollbar = null,
    fullscreen_copy_on_select: ?bool = null,
    /// Anonymous install/update ping. Environment PI_TELEMETRY remains authoritative.
    enable_install_telemetry: ?bool = null,
    /// Command used for npm-compatible package operations. The first element
    /// is the executable and remaining elements are wrapper arguments.
    npm_command: ?[]const []const u8 = null,
    /// HTTP header/body idle timeout. Null inherits the upstream default; zero disables it.
    http_idle_timeout_ms: ?u64 = null,
    /// Codex WebSocket connect timeout. Null inherits 15s default; zero disables it.
    websocket_connect_timeout_ms: ?u64 = null,
    /// Original nested `compaction` policy. Null fields inherit the upstream defaults.
    compaction_enabled: ?bool = null,
    compaction_reserve_tokens: ?u64 = null,
    compaction_keep_recent_tokens: ?u64 = null,
    /// Branch-navigation summarization policy. The reserve is subtracted from
    /// the active model context window; skip_prompt defaults to false.
    branch_summary_reserve_tokens: ?u64 = null,
    branch_summary_skip_prompt: ?bool = null,
    /// Settings-driven outer retry policy. Null fields inherit upstream defaults.
    retry_enabled: ?bool = null,
    retry_max_retries: ?usize = null,
    retry_base_delay_ms: ?u64 = null,
    /// Provider-internal request policy (`retry.provider`). These fields merge
    /// independently so a project can override one value without discarding
    /// the inherited timeout or server-delay cap.
    retry_provider_timeout_ms: ?u64 = null,
    retry_provider_max_retries: ?usize = null,
    retry_provider_max_retry_delay_ms: ?u64 = null,
    /// Global-only project trust policy. Project settings never override this.
    default_project_trust: DefaultProjectTrust = .ask,
    /// Owned storage for parsed strings
    arena_owned: bool = false,

    pub fn deinit(self: *Settings, gpa: std.mem.Allocator) void {
        if (self.model) |m| gpa.free(m);
        if (self.provider) |p| gpa.free(p);
        if (self.thinking_level) |t| gpa.free(t);
        if (self.theme) |t| gpa.free(t);
        if (self.http_proxy) |proxy| gpa.free(proxy);
        if (self.last_changelog_version) |version| gpa.free(version);
        if (self.npm_command) |command| {
            for (command) |part| gpa.free(part);
            gpa.free(command);
        }
        if (self.tools) |t| {
            for (t) |x| gpa.free(x);
            gpa.free(t);
        }
        if (self.enabled_models) |models| {
            for (models) |model| gpa.free(model);
            gpa.free(models);
        }
        self.* = undefined;
    }
};

pub const Diagnostic = struct {
    path: []u8,
    message: []u8,

    pub fn deinit(self: *Diagnostic, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.message);
        self.* = undefined;
    }
};

pub const DiagnosedSettings = struct {
    settings: Settings = .{},
    diagnostics: []Diagnostic = &.{},

    pub fn deinit(self: *DiagnosedSettings, gpa: std.mem.Allocator) void {
        self.settings.deinit(gpa);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(gpa);
        if (self.diagnostics.len > 0) gpa.free(self.diagnostics);
        self.* = undefined;
    }
};

const RetryEnabledMutation = struct {
    enabled: bool,
};

fn persistRetryEnabledLocked(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    mutation: RetryEnabledMutation,
) !void {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);

    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(raw);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var parsed = std.json.parseFromSlice(std.json.Value, arena, raw, .{}) catch return error.InvalidSettingsJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidSettingsJson;

    const retry_value = try parsed.value.object.getOrPut(arena, "retry");
    if (!retry_value.found_existing) {
        retry_value.value_ptr.* = .{ .object = .empty };
    } else if (retry_value.value_ptr.* != .object) {
        // A scalar retry field cannot be merged without silently discarding
        // configuration. Surface the malformed setting instead.
        return error.InvalidRetrySettings;
    }
    try retry_value.value_ptr.object.put(arena, "enabled", .{ .bool = mutation.enabled });

    // Legacy top-level aliases are parsed after the nested object. Remove them
    // so the persisted RPC decision cannot be overridden on the next startup.
    _ = parsed.value.object.orderedRemove("autoRetryEnabled");
    _ = parsed.value.object.orderedRemove("auto_retry_enabled");

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');

    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, settings_path, .{
        .replace = true,
        .make_path = true,
        .permissions = .default_file,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    try atomic.file.sync(io);
    try atomic.replace(io);

    var verified = try loadFile(gpa, io, settings_path);
    defer verified.deinit(gpa);
    if (verified.retry_enabled == null or verified.retry_enabled.? != mutation.enabled)
        return error.SettingsVerificationFailed;
}

/// Persist the RPC/UI automatic-retry toggle in global settings.json. The
/// read/modify/write transaction shares the package configuration advisory
/// lock, preserving unrelated settings and concurrent resource edits.
pub fn setRetryEnabled(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    enabled: bool,
) !void {
    try packages.withScopeConfigurationLock(
        gpa,
        io,
        agent_dir,
        ".",
        .user,
        true,
        RetryEnabledMutation{ .enabled = enabled },
        persistRetryEnabledLocked,
    );
}

const DefaultModelMutation = struct {
    provider: []const u8,
    model: []const u8,
};

fn persistDefaultModelLocked(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    mutation: DefaultModelMutation,
) !void {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(raw);
    const normalized = if (std.mem.startsWith(u8, raw, "\xEF\xBB\xBF")) raw[3..] else raw;

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var parsed = std.json.parseFromSlice(std.json.Value, arena, normalized, .{}) catch return error.InvalidSettingsJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidSettingsJson;
    try parsed.value.object.put(arena, "defaultProvider", .{ .string = try arena.dupe(u8, mutation.provider) });
    try parsed.value.object.put(arena, "defaultModel", .{ .string = try arena.dupe(u8, mutation.model) });
    _ = parsed.value.object.orderedRemove("provider");
    _ = parsed.value.object.orderedRemove("default_provider");
    _ = parsed.value.object.orderedRemove("model");
    _ = parsed.value.object.orderedRemove("default_model");
    const scope_value = parsed.value.object.getPtr("enabledModels") orelse parsed.value.object.getPtr("enabled_models");
    if (scope_value) |scope| {
        if (scope.* != .array) return error.InvalidSettingsShape;
        if (scope.array.items.len > 0) {
            const reference = try std.fmt.allocPrint(arena, "{s}/{s}", .{ mutation.provider, mutation.model });
            var found = false;
            for (scope.array.items) |item| {
                if (item == .string and std.ascii.eqlIgnoreCase(item.string, reference)) {
                    found = true;
                    break;
                }
            }
            if (!found) try scope.array.append(.{ .string = reference });
            if (parsed.value.object.get("enabledModels") == null) {
                try parsed.value.object.put(arena, "enabledModels", scope.*);
                _ = parsed.value.object.orderedRemove("enabled_models");
            }
        }
    }

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, settings_path, .{ .replace = true, .make_path = true, .permissions = .default_file });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    try atomic.file.sync(io);
    try atomic.replace(io);

    var verified = try loadFile(gpa, io, settings_path);
    defer verified.deinit(gpa);
    if (verified.provider == null or verified.model == null or
        !std.mem.eql(u8, verified.provider.?, mutation.provider) or !std.mem.eql(u8, verified.model.?, mutation.model))
        return error.SettingsVerificationFailed;
}

/// Persist a model selector's Ctrl+S choice atomically as the global default.
pub fn setDefaultModel(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, provider: []const u8, model: []const u8) !void {
    if (provider.len == 0 or model.len == 0) return error.InvalidDefaultModel;
    try packages.withScopeConfigurationLock(
        gpa,
        io,
        agent_dir,
        ".",
        .user,
        true,
        DefaultModelMutation{ .provider = provider, .model = model },
        persistDefaultModelLocked,
    );
}

const CompactionEnabledMutation = struct {
    enabled: bool,
};

fn persistCompactionEnabledLocked(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    mutation: CompactionEnabledMutation,
) !void {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);

    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(raw);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var parsed = std.json.parseFromSlice(std.json.Value, arena, raw, .{}) catch return error.InvalidSettingsJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidSettingsJson;

    const compaction_value = try parsed.value.object.getOrPut(arena, "compaction");
    if (!compaction_value.found_existing) {
        compaction_value.value_ptr.* = .{ .object = .empty };
    } else if (compaction_value.value_ptr.* != .object) {
        return error.InvalidCompactionSettings;
    }
    try compaction_value.value_ptr.object.put(arena, "enabled", .{ .bool = mutation.enabled });
    _ = parsed.value.object.orderedRemove("autoCompactionEnabled");
    _ = parsed.value.object.orderedRemove("auto_compaction_enabled");

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');

    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, settings_path, .{
        .replace = true,
        .make_path = true,
        .permissions = .default_file,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    try atomic.file.sync(io);
    try atomic.replace(io);

    var verified = try loadFile(gpa, io, settings_path);
    defer verified.deinit(gpa);
    if (verified.compaction_enabled == null or verified.compaction_enabled.? != mutation.enabled)
        return error.SettingsVerificationFailed;
}

/// Persist the RPC/UI automatic-compaction toggle in global settings.json while
/// retaining token budgets and unrelated settings.
pub fn setCompactionEnabled(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    enabled: bool,
) !void {
    try packages.withScopeConfigurationLock(
        gpa,
        io,
        agent_dir,
        ".",
        .user,
        true,
        CompactionEnabledMutation{ .enabled = enabled },
        persistCompactionEnabledLocked,
    );
}

const ChangelogVersionMutation = struct {
    version: []const u8,
};

fn persistChangelogVersionLocked(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    mutation: ChangelogVersionMutation,
) !void {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);

    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(raw);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var parsed = std.json.parseFromSlice(std.json.Value, arena, raw, .{}) catch return error.InvalidSettingsJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidSettingsJson;

    const normalized = std.mem.trim(u8, mutation.version, " \t\r\n");
    if (normalized.len == 0) return error.InvalidChangelogVersion;
    try parsed.value.object.put(arena, "lastChangelogVersion", .{ .string = try arena.dupe(u8, normalized) });
    _ = parsed.value.object.orderedRemove("last_changelog_version");

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');

    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, settings_path, .{
        .replace = true,
        .make_path = true,
        .permissions = .default_file,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    try atomic.file.sync(io);
    try atomic.replace(io);

    var verified = try loadFile(gpa, io, settings_path);
    defer verified.deinit(gpa);
    if (verified.last_changelog_version == null or !std.mem.eql(u8, verified.last_changelog_version.?, normalized))
        return error.SettingsVerificationFailed;
}

/// Persist lifecycle acknowledgement without replacing unrelated settings.
pub fn setLastChangelogVersion(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    version: []const u8,
) !void {
    try packages.withScopeConfigurationLock(
        gpa,
        io,
        agent_dir,
        ".",
        .user,
        true,
        ChangelogVersionMutation{ .version = version },
        persistChangelogVersionLocked,
    );
}

pub const EditableScope = enum { global, project };

/// Settings exposed by the native fullscreen `/settings` selector. The keys
/// intentionally map to the original upstream JSON spellings so mutations are
/// durable and remain interoperable with the TypeScript implementation.
pub const EditableKey = enum {
    max_turns,
    thinking_level,
    theme,
    transport,
    steering_mode,
    follow_up_mode,
    collapse_changelog,
    quiet_startup,
    hide_thinking_block,
    show_cache_miss_notices,
    double_escape_action,
    tree_filter_mode,
    show_images,
    image_width_cells,
    clear_on_shrink,
    show_terminal_progress,
    auto_resize_images,
    block_images,
    enable_skill_commands,
    editor_padding_x,
    output_pad,
    autocomplete_max_visible,
    show_hardware_cursor,
    mermaid_mode,
    warning_anthropic_extra_usage,
    tui_mode,
    fullscreen_exit_output,
    fullscreen_scrollbar,
    enable_install_telemetry,
    http_idle_timeout_ms,
    websocket_connect_timeout_ms,
    compaction_enabled,
    compaction_reserve_tokens,
    compaction_keep_recent_tokens,
    branch_summary_reserve_tokens,
    branch_summary_skip_prompt,
    retry_enabled,
    retry_max_retries,
    retry_base_delay_ms,
    retry_provider_timeout_ms,
    retry_provider_max_retries,
    retry_provider_max_retry_delay_ms,
    default_project_trust,
};

pub const EditableValue = union(enum) {
    boolean: bool,
    integer: i64,
    string: []const u8,
};

const EditableMutation = struct {
    key: EditableKey,
    value: EditableValue,
};

fn mutationValue(arena: std.mem.Allocator, value: EditableValue) !std.json.Value {
    return switch (value) {
        .boolean => |boolean| .{ .bool = boolean },
        .integer => |integer| .{ .integer = integer },
        .string => |string| .{ .string = try arena.dupe(u8, string) },
    };
}

fn ensureObject(arena: std.mem.Allocator, parent: *std.json.ObjectMap, key: []const u8) !*std.json.ObjectMap {
    const result = try parent.getOrPut(arena, key);
    if (!result.found_existing) {
        result.value_ptr.* = .{ .object = .empty };
    } else if (result.value_ptr.* != .object) {
        return error.InvalidSettingsShape;
    }
    return &result.value_ptr.object;
}

fn applyEditableMutation(arena: std.mem.Allocator, root: *std.json.ObjectMap, mutation: EditableMutation) !void {
    const value = try mutationValue(arena, mutation.value);
    switch (mutation.key) {
        .max_turns => {
            try root.put(arena, "maxTurns", value);
            _ = root.orderedRemove("max_turns");
        },
        .thinking_level => {
            try root.put(arena, "defaultThinkingLevel", value);
            _ = root.orderedRemove("thinkingLevel");
            _ = root.orderedRemove("thinking_level");
        },
        .theme => try root.put(arena, "theme", value),
        .transport => {
            try root.put(arena, "transport", value);
            _ = root.orderedRemove("websockets");
        },
        .steering_mode => {
            try root.put(arena, "steeringMode", value);
            _ = root.orderedRemove("steering_mode");
        },
        .follow_up_mode => {
            try root.put(arena, "followUpMode", value);
            _ = root.orderedRemove("follow_up_mode");
        },
        .collapse_changelog => {
            try root.put(arena, "collapseChangelog", value);
            _ = root.orderedRemove("collapse_changelog");
        },
        .quiet_startup => {
            try root.put(arena, "quietStartup", value);
            _ = root.orderedRemove("quiet_startup");
        },
        .hide_thinking_block => {
            try root.put(arena, "hideThinkingBlock", value);
            _ = root.orderedRemove("hide_thinking_block");
        },
        .show_cache_miss_notices => {
            try root.put(arena, "showCacheMissNotices", value);
            _ = root.orderedRemove("show_cache_miss_notices");
        },
        .double_escape_action => {
            try root.put(arena, "doubleEscapeAction", value);
            _ = root.orderedRemove("double_escape_action");
        },
        .tree_filter_mode => {
            try root.put(arena, "treeFilterMode", value);
            _ = root.orderedRemove("tree_filter_mode");
        },
        .show_images, .image_width_cells, .clear_on_shrink, .show_terminal_progress => {
            const terminal = try ensureObject(arena, root, "terminal");
            const key = switch (mutation.key) {
                .show_images => "showImages",
                .image_width_cells => "imageWidthCells",
                .clear_on_shrink => "clearOnShrink",
                .show_terminal_progress => "showTerminalProgress",
                else => unreachable,
            };
            try terminal.put(arena, key, value);
            _ = terminal.orderedRemove(switch (mutation.key) {
                .show_images => "show_images",
                .image_width_cells => "image_width_cells",
                .clear_on_shrink => "clear_on_shrink",
                .show_terminal_progress => "show_terminal_progress",
                else => unreachable,
            });
        },
        .auto_resize_images, .block_images => {
            const images = try ensureObject(arena, root, "images");
            try images.put(arena, if (mutation.key == .auto_resize_images) "autoResize" else "blockImages", value);
            _ = images.orderedRemove(if (mutation.key == .auto_resize_images) "auto_resize" else "block_images");
        },
        .enable_skill_commands => {
            try root.put(arena, "enableSkillCommands", value);
            _ = root.orderedRemove("enable_skill_commands");
            // Historical nested `skills.enableSkillCommands` was migrated to
            // the top-level setting by upstream Pi. Remove only that key.
            if (root.getPtr("skills")) |skills_value| if (skills_value.* == .object) {
                _ = skills_value.object.orderedRemove("enableSkillCommands");
                _ = skills_value.object.orderedRemove("enable_skill_commands");
            };
        },
        .editor_padding_x => {
            try root.put(arena, "editorPaddingX", value);
            _ = root.orderedRemove("editor_padding_x");
        },
        .output_pad => {
            try root.put(arena, "outputPad", value);
            _ = root.orderedRemove("output_pad");
        },
        .autocomplete_max_visible => {
            try root.put(arena, "autocompleteMaxVisible", value);
            _ = root.orderedRemove("autocomplete_max_visible");
        },
        .show_hardware_cursor => {
            try root.put(arena, "showHardwareCursor", value);
            _ = root.orderedRemove("show_hardware_cursor");
        },
        .mermaid_mode => {
            const markdown = try ensureObject(arena, root, "markdown");
            try markdown.put(arena, "mermaid", value);
        },
        .warning_anthropic_extra_usage => {
            const warnings = try ensureObject(arena, root, "warnings");
            try warnings.put(arena, "anthropicExtraUsage", value);
            _ = warnings.orderedRemove("anthropic_extra_usage");
        },
        .tui_mode => {
            try root.put(arena, "tuiMode", value);
            _ = root.orderedRemove("tui_mode");
        },
        .fullscreen_exit_output => {
            try root.put(arena, "fullscreenExitOutput", value);
            _ = root.orderedRemove("fullscreen_exit_output");
        },
        .fullscreen_scrollbar => {
            try root.put(arena, "fullscreenScrollbar", value);
            _ = root.orderedRemove("fullscreen_scrollbar");
        },
        .enable_install_telemetry => {
            try root.put(arena, "enableInstallTelemetry", value);
            _ = root.orderedRemove("enable_install_telemetry");
        },
        .http_idle_timeout_ms => {
            try root.put(arena, "httpIdleTimeoutMs", value);
            _ = root.orderedRemove("http_idle_timeout_ms");
        },
        .websocket_connect_timeout_ms => {
            try root.put(arena, "websocketConnectTimeoutMs", value);
            _ = root.orderedRemove("websocket_connect_timeout_ms");
        },
        .compaction_enabled, .compaction_reserve_tokens, .compaction_keep_recent_tokens => {
            const object = try ensureObject(arena, root, "compaction");
            const key = switch (mutation.key) {
                .compaction_enabled => "enabled",
                .compaction_reserve_tokens => "reserveTokens",
                .compaction_keep_recent_tokens => "keepRecentTokens",
                else => unreachable,
            };
            try object.put(arena, key, value);
            _ = root.orderedRemove("autoCompactionEnabled");
            _ = root.orderedRemove("auto_compaction_enabled");
        },
        .branch_summary_reserve_tokens, .branch_summary_skip_prompt => {
            const object = try ensureObject(arena, root, "branchSummary");
            try object.put(arena, if (mutation.key == .branch_summary_reserve_tokens) "reserveTokens" else "skipPrompt", value);
            _ = root.orderedRemove("branch_summary_reserve_tokens");
            _ = root.orderedRemove("branch_summary_skip_prompt");
        },
        .retry_enabled, .retry_max_retries, .retry_base_delay_ms => {
            const object = try ensureObject(arena, root, "retry");
            const key = switch (mutation.key) {
                .retry_enabled => "enabled",
                .retry_max_retries => "maxRetries",
                .retry_base_delay_ms => "baseDelayMs",
                else => unreachable,
            };
            try object.put(arena, key, value);
            _ = root.orderedRemove("autoRetryEnabled");
            _ = root.orderedRemove("auto_retry_enabled");
        },
        .retry_provider_timeout_ms, .retry_provider_max_retries, .retry_provider_max_retry_delay_ms => {
            const retry = try ensureObject(arena, root, "retry");
            const provider = try ensureObject(arena, retry, "provider");
            const key = switch (mutation.key) {
                .retry_provider_timeout_ms => "timeoutMs",
                .retry_provider_max_retries => "maxRetries",
                .retry_provider_max_retry_delay_ms => "maxRetryDelayMs",
                else => unreachable,
            };
            try provider.put(arena, key, value);
            _ = retry.orderedRemove("maxDelayMs");
        },
        .default_project_trust => {
            try root.put(arena, "defaultProjectTrust", value);
            _ = root.orderedRemove("default_project_trust");
        },
    }
}

fn editableMatches(settings: Settings, mutation: EditableMutation) bool {
    return switch (mutation.key) {
        .max_turns => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.max_turns == @as(usize, @intCast(v)),
            else => false,
        },
        .thinking_level => switch (mutation.value) {
            .string => |v| settings.thinking_level != null and std.mem.eql(u8, settings.thinking_level.?, v),
            else => false,
        },
        .theme => switch (mutation.value) {
            .string => |v| settings.theme != null and std.mem.eql(u8, settings.theme.?, v),
            else => false,
        },
        .transport => switch (mutation.value) {
            .string => |v| codex_ws.Transport.parse(v) != null and settings.transport != null and settings.transport.? == codex_ws.Transport.parse(v).?,
            else => false,
        },
        .steering_mode => switch (mutation.value) {
            .string => |v| DeliveryMode.parse(v) != null and settings.steering_mode != null and settings.steering_mode.? == DeliveryMode.parse(v).?,
            else => false,
        },
        .follow_up_mode => switch (mutation.value) {
            .string => |v| DeliveryMode.parse(v) != null and settings.follow_up_mode != null and settings.follow_up_mode.? == DeliveryMode.parse(v).?,
            else => false,
        },
        .collapse_changelog => switch (mutation.value) {
            .boolean => |v| settings.collapse_changelog != null and settings.collapse_changelog.? == v,
            else => false,
        },
        .quiet_startup => switch (mutation.value) {
            .boolean => |v| settings.quiet_startup != null and settings.quiet_startup.? == v,
            else => false,
        },
        .hide_thinking_block => switch (mutation.value) {
            .boolean => |v| settings.hide_thinking_block != null and settings.hide_thinking_block.? == v,
            else => false,
        },
        .show_cache_miss_notices => switch (mutation.value) {
            .boolean => |v| settings.show_cache_miss_notices != null and settings.show_cache_miss_notices.? == v,
            else => false,
        },
        .double_escape_action => switch (mutation.value) {
            .string => |v| DoubleEscapeAction.parse(v) != null and settings.double_escape_action != null and settings.double_escape_action.? == DoubleEscapeAction.parse(v).?,
            else => false,
        },
        .tree_filter_mode => switch (mutation.value) {
            .string => |v| TreeFilterMode.parse(v) != null and settings.tree_filter_mode != null and settings.tree_filter_mode.? == TreeFilterMode.parse(v).?,
            else => false,
        },
        .show_images => switch (mutation.value) {
            .boolean => |v| settings.show_images != null and settings.show_images.? == v,
            else => false,
        },
        .image_width_cells => switch (mutation.value) {
            .integer => |v| v >= 1 and settings.image_width_cells != null and settings.image_width_cells.? == @as(u64, @intCast(v)),
            else => false,
        },
        .clear_on_shrink => switch (mutation.value) {
            .boolean => |v| settings.clear_on_shrink != null and settings.clear_on_shrink.? == v,
            else => false,
        },
        .show_terminal_progress => switch (mutation.value) {
            .boolean => |v| settings.show_terminal_progress != null and settings.show_terminal_progress.? == v,
            else => false,
        },
        .auto_resize_images => switch (mutation.value) {
            .boolean => |v| settings.auto_resize_images != null and settings.auto_resize_images.? == v,
            else => false,
        },
        .block_images => switch (mutation.value) {
            .boolean => |v| settings.block_images != null and settings.block_images.? == v,
            else => false,
        },
        .enable_skill_commands => switch (mutation.value) {
            .boolean => |v| settings.enable_skill_commands != null and settings.enable_skill_commands.? == v,
            else => false,
        },
        .editor_padding_x => switch (mutation.value) {
            .integer => |v| v >= 0 and v <= 3 and settings.editor_padding_x != null and settings.editor_padding_x.? == @as(u64, @intCast(v)),
            else => false,
        },
        .output_pad => switch (mutation.value) {
            .integer => |v| (v == 0 or v == 1) and settings.output_pad != null and settings.output_pad.? == @as(u64, @intCast(v)),
            else => false,
        },
        .autocomplete_max_visible => switch (mutation.value) {
            .integer => |v| v >= 3 and v <= 20 and settings.autocomplete_max_visible != null and settings.autocomplete_max_visible.? == @as(u64, @intCast(v)),
            else => false,
        },
        .show_hardware_cursor => switch (mutation.value) {
            .boolean => |v| settings.show_hardware_cursor != null and settings.show_hardware_cursor.? == v,
            else => false,
        },
        .mermaid_mode => switch (mutation.value) {
            .string => |v| MermaidMode.parse(v) != null and settings.mermaid_mode != null and settings.mermaid_mode.? == MermaidMode.parse(v).?,
            else => false,
        },
        .warning_anthropic_extra_usage => switch (mutation.value) {
            .boolean => |v| settings.warning_anthropic_extra_usage != null and settings.warning_anthropic_extra_usage.? == v,
            else => false,
        },
        .tui_mode => switch (mutation.value) {
            .string => |v| TuiMode.parse(v) != null and settings.tui_mode != null and settings.tui_mode.? == TuiMode.parse(v).?,
            else => false,
        },
        .fullscreen_exit_output => switch (mutation.value) {
            .string => |v| FullscreenExitOutput.parse(v) != null and settings.fullscreen_exit_output != null and settings.fullscreen_exit_output.? == FullscreenExitOutput.parse(v).?,
            else => false,
        },
        .fullscreen_scrollbar => switch (mutation.value) {
            .string => |v| FullscreenScrollbar.parse(v) != null and settings.fullscreen_scrollbar != null and settings.fullscreen_scrollbar.? == FullscreenScrollbar.parse(v).?,
            else => false,
        },
        .enable_install_telemetry => switch (mutation.value) {
            .boolean => |v| settings.enable_install_telemetry != null and settings.enable_install_telemetry.? == v,
            else => false,
        },
        .http_idle_timeout_ms => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.http_idle_timeout_ms != null and settings.http_idle_timeout_ms.? == @as(u64, @intCast(v)),
            else => false,
        },
        .websocket_connect_timeout_ms => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.websocket_connect_timeout_ms != null and settings.websocket_connect_timeout_ms.? == @as(u64, @intCast(v)),
            else => false,
        },
        .compaction_enabled => switch (mutation.value) {
            .boolean => |v| settings.compaction_enabled != null and settings.compaction_enabled.? == v,
            else => false,
        },
        .compaction_reserve_tokens => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.compaction_reserve_tokens != null and settings.compaction_reserve_tokens.? == @as(u64, @intCast(v)),
            else => false,
        },
        .compaction_keep_recent_tokens => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.compaction_keep_recent_tokens != null and settings.compaction_keep_recent_tokens.? == @as(u64, @intCast(v)),
            else => false,
        },
        .branch_summary_reserve_tokens => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.branch_summary_reserve_tokens != null and settings.branch_summary_reserve_tokens.? == @as(u64, @intCast(v)),
            else => false,
        },
        .branch_summary_skip_prompt => switch (mutation.value) {
            .boolean => |v| settings.branch_summary_skip_prompt != null and settings.branch_summary_skip_prompt.? == v,
            else => false,
        },
        .retry_enabled => switch (mutation.value) {
            .boolean => |v| settings.retry_enabled != null and settings.retry_enabled.? == v,
            else => false,
        },
        .retry_max_retries => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.retry_max_retries != null and settings.retry_max_retries.? == @as(usize, @intCast(v)),
            else => false,
        },
        .retry_base_delay_ms => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.retry_base_delay_ms != null and settings.retry_base_delay_ms.? == @as(u64, @intCast(v)),
            else => false,
        },
        .retry_provider_timeout_ms => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.retry_provider_timeout_ms != null and settings.retry_provider_timeout_ms.? == @as(u64, @intCast(v)),
            else => false,
        },
        .retry_provider_max_retries => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.retry_provider_max_retries != null and settings.retry_provider_max_retries.? == @as(usize, @intCast(v)),
            else => false,
        },
        .retry_provider_max_retry_delay_ms => switch (mutation.value) {
            .integer => |v| v >= 0 and settings.retry_provider_max_retry_delay_ms != null and settings.retry_provider_max_retry_delay_ms.? == @as(u64, @intCast(v)),
            else => false,
        },
        .default_project_trust => switch (mutation.value) {
            .string => |v| (std.mem.eql(u8, v, "ask") and settings.default_project_trust == .ask) or
                (std.mem.eql(u8, v, "always") and settings.default_project_trust == .always) or
                (std.mem.eql(u8, v, "never") and settings.default_project_trust == .never),
            else => false,
        },
    };
}

pub fn isEditableExplicit(settings: Settings, key: EditableKey) bool {
    return switch (key) {
        .max_turns => settings.max_turns_explicit,
        .thinking_level => settings.thinking_level != null,
        .theme => settings.theme != null,
        .transport => settings.transport != null,
        .steering_mode => settings.steering_mode != null,
        .follow_up_mode => settings.follow_up_mode != null,
        .collapse_changelog => settings.collapse_changelog != null,
        .quiet_startup => settings.quiet_startup != null,
        .hide_thinking_block => settings.hide_thinking_block != null,
        .show_cache_miss_notices => settings.show_cache_miss_notices != null,
        .double_escape_action => settings.double_escape_action != null,
        .tree_filter_mode => settings.tree_filter_mode != null,
        .show_images => settings.show_images != null,
        .image_width_cells => settings.image_width_cells != null,
        .clear_on_shrink => settings.clear_on_shrink != null,
        .show_terminal_progress => settings.show_terminal_progress != null,
        .auto_resize_images => settings.auto_resize_images != null,
        .block_images => settings.block_images != null,
        .enable_skill_commands => settings.enable_skill_commands != null,
        .editor_padding_x => settings.editor_padding_x != null,
        .output_pad => settings.output_pad != null,
        .autocomplete_max_visible => settings.autocomplete_max_visible != null,
        .show_hardware_cursor => settings.show_hardware_cursor != null,
        .mermaid_mode => settings.mermaid_mode != null,
        .warning_anthropic_extra_usage => settings.warning_anthropic_extra_usage != null,
        .tui_mode => settings.tui_mode != null,
        .fullscreen_exit_output => settings.fullscreen_exit_output != null,
        .fullscreen_scrollbar => settings.fullscreen_scrollbar != null,
        .enable_install_telemetry => settings.enable_install_telemetry != null,
        .http_idle_timeout_ms => settings.http_idle_timeout_ms != null,
        .websocket_connect_timeout_ms => settings.websocket_connect_timeout_ms != null,
        .compaction_enabled => settings.compaction_enabled != null,
        .compaction_reserve_tokens => settings.compaction_reserve_tokens != null,
        .compaction_keep_recent_tokens => settings.compaction_keep_recent_tokens != null,
        .branch_summary_reserve_tokens => settings.branch_summary_reserve_tokens != null,
        .branch_summary_skip_prompt => settings.branch_summary_skip_prompt != null,
        .retry_enabled => settings.retry_enabled != null,
        .retry_max_retries => settings.retry_max_retries != null,
        .retry_base_delay_ms => settings.retry_base_delay_ms != null,
        .retry_provider_timeout_ms => settings.retry_provider_timeout_ms != null,
        .retry_provider_max_retries => settings.retry_provider_max_retries != null,
        .retry_provider_max_retry_delay_ms => settings.retry_provider_max_retry_delay_ms != null,
        .default_project_trust => false,
    };
}

fn removeObjectKey(root: *std.json.ObjectMap, object_name: []const u8, key: []const u8, alias: ?[]const u8) void {
    const value = root.getPtr(object_name) orelse return;
    if (value.* != .object) return;
    _ = value.object.orderedRemove(key);
    if (alias) |name| _ = value.object.orderedRemove(name);
    if (value.object.count() == 0) _ = root.orderedRemove(object_name);
}

fn removeEditableMutation(root: *std.json.ObjectMap, key: EditableKey) void {
    switch (key) {
        .max_turns => {
            _ = root.orderedRemove("maxTurns");
            _ = root.orderedRemove("max_turns");
        },
        .thinking_level => {
            _ = root.orderedRemove("defaultThinkingLevel");
            _ = root.orderedRemove("thinkingLevel");
            _ = root.orderedRemove("thinking_level");
        },
        .theme => _ = root.orderedRemove("theme"),
        .transport => {
            _ = root.orderedRemove("transport");
            _ = root.orderedRemove("websockets");
        },
        .steering_mode => {
            _ = root.orderedRemove("steeringMode");
            _ = root.orderedRemove("steering_mode");
        },
        .follow_up_mode => {
            _ = root.orderedRemove("followUpMode");
            _ = root.orderedRemove("follow_up_mode");
        },
        .collapse_changelog => {
            _ = root.orderedRemove("collapseChangelog");
            _ = root.orderedRemove("collapse_changelog");
        },
        .quiet_startup => {
            _ = root.orderedRemove("quietStartup");
            _ = root.orderedRemove("quiet_startup");
        },
        .hide_thinking_block => {
            _ = root.orderedRemove("hideThinkingBlock");
            _ = root.orderedRemove("hide_thinking_block");
        },
        .show_cache_miss_notices => {
            _ = root.orderedRemove("showCacheMissNotices");
            _ = root.orderedRemove("show_cache_miss_notices");
        },
        .double_escape_action => {
            _ = root.orderedRemove("doubleEscapeAction");
            _ = root.orderedRemove("double_escape_action");
        },
        .tree_filter_mode => {
            _ = root.orderedRemove("treeFilterMode");
            _ = root.orderedRemove("tree_filter_mode");
        },
        .show_images => removeObjectKey(root, "terminal", "showImages", "show_images"),
        .image_width_cells => removeObjectKey(root, "terminal", "imageWidthCells", "image_width_cells"),
        .clear_on_shrink => removeObjectKey(root, "terminal", "clearOnShrink", "clear_on_shrink"),
        .show_terminal_progress => removeObjectKey(root, "terminal", "showTerminalProgress", "show_terminal_progress"),
        .auto_resize_images => removeObjectKey(root, "images", "autoResize", "auto_resize"),
        .block_images => removeObjectKey(root, "images", "blockImages", "block_images"),
        .enable_skill_commands => {
            _ = root.orderedRemove("enableSkillCommands");
            _ = root.orderedRemove("enable_skill_commands");
            removeObjectKey(root, "skills", "enableSkillCommands", "enable_skill_commands");
        },
        .editor_padding_x => {
            _ = root.orderedRemove("editorPaddingX");
            _ = root.orderedRemove("editor_padding_x");
        },
        .output_pad => {
            _ = root.orderedRemove("outputPad");
            _ = root.orderedRemove("output_pad");
        },
        .autocomplete_max_visible => {
            _ = root.orderedRemove("autocompleteMaxVisible");
            _ = root.orderedRemove("autocomplete_max_visible");
        },
        .show_hardware_cursor => {
            _ = root.orderedRemove("showHardwareCursor");
            _ = root.orderedRemove("show_hardware_cursor");
        },
        .mermaid_mode => removeObjectKey(root, "markdown", "mermaid", null),
        .warning_anthropic_extra_usage => removeObjectKey(root, "warnings", "anthropicExtraUsage", "anthropic_extra_usage"),
        .tui_mode => {
            _ = root.orderedRemove("tuiMode");
            _ = root.orderedRemove("tui_mode");
        },
        .fullscreen_exit_output => {
            _ = root.orderedRemove("fullscreenExitOutput");
            _ = root.orderedRemove("fullscreen_exit_output");
        },
        .fullscreen_scrollbar => {
            _ = root.orderedRemove("fullscreenScrollbar");
            _ = root.orderedRemove("fullscreen_scrollbar");
        },
        .enable_install_telemetry => {
            _ = root.orderedRemove("enableInstallTelemetry");
            _ = root.orderedRemove("enable_install_telemetry");
        },
        .http_idle_timeout_ms => {
            _ = root.orderedRemove("httpIdleTimeoutMs");
            _ = root.orderedRemove("http_idle_timeout_ms");
        },
        .websocket_connect_timeout_ms => {
            _ = root.orderedRemove("websocketConnectTimeoutMs");
            _ = root.orderedRemove("websocket_connect_timeout_ms");
        },
        .compaction_enabled => {
            removeObjectKey(root, "compaction", "enabled", null);
            _ = root.orderedRemove("autoCompactionEnabled");
            _ = root.orderedRemove("auto_compaction_enabled");
        },
        .compaction_reserve_tokens => {
            removeObjectKey(root, "compaction", "reserveTokens", "reserve_tokens");
            _ = root.orderedRemove("compactionReserveTokens");
            _ = root.orderedRemove("compaction_reserve_tokens");
        },
        .compaction_keep_recent_tokens => {
            removeObjectKey(root, "compaction", "keepRecentTokens", "keep_recent_tokens");
            _ = root.orderedRemove("compactionKeepRecentTokens");
            _ = root.orderedRemove("compaction_keep_recent_tokens");
        },
        .branch_summary_reserve_tokens => {
            removeObjectKey(root, "branchSummary", "reserveTokens", "reserve_tokens");
            removeObjectKey(root, "branch_summary", "reserveTokens", "reserve_tokens");
            _ = root.orderedRemove("branchSummaryReserveTokens");
            _ = root.orderedRemove("branch_summary_reserve_tokens");
        },
        .branch_summary_skip_prompt => {
            removeObjectKey(root, "branchSummary", "skipPrompt", "skip_prompt");
            removeObjectKey(root, "branch_summary", "skipPrompt", "skip_prompt");
            _ = root.orderedRemove("branchSummarySkipPrompt");
            _ = root.orderedRemove("branch_summary_skip_prompt");
        },
        .retry_enabled => {
            removeObjectKey(root, "retry", "enabled", null);
            _ = root.orderedRemove("autoRetryEnabled");
            _ = root.orderedRemove("auto_retry_enabled");
        },
        .retry_max_retries => removeObjectKey(root, "retry", "maxRetries", "max_retries"),
        .retry_base_delay_ms => removeObjectKey(root, "retry", "baseDelayMs", "base_delay_ms"),
        .retry_provider_timeout_ms, .retry_provider_max_retries, .retry_provider_max_retry_delay_ms => {
            const retry_value = root.getPtr("retry") orelse return;
            if (retry_value.* != .object) return;
            const provider_value = retry_value.object.getPtr("provider") orelse return;
            if (provider_value.* != .object) return;
            switch (key) {
                .retry_provider_timeout_ms => {
                    _ = provider_value.object.orderedRemove("timeoutMs");
                    _ = provider_value.object.orderedRemove("timeout_ms");
                },
                .retry_provider_max_retries => {
                    _ = provider_value.object.orderedRemove("maxRetries");
                    _ = provider_value.object.orderedRemove("max_retries");
                },
                .retry_provider_max_retry_delay_ms => {
                    _ = provider_value.object.orderedRemove("maxRetryDelayMs");
                    _ = provider_value.object.orderedRemove("max_retry_delay_ms");
                    _ = retry_value.object.orderedRemove("maxDelayMs");
                    _ = retry_value.object.orderedRemove("max_delay_ms");
                },
                else => unreachable,
            }
            if (provider_value.object.count() == 0) _ = retry_value.object.orderedRemove("provider");
            if (retry_value.object.count() == 0) _ = root.orderedRemove("retry");
        },
        .default_project_trust => {
            _ = root.orderedRemove("defaultProjectTrust");
            _ = root.orderedRemove("default_project_trust");
        },
    }
}

fn persistEditableLocked(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    mutation: EditableMutation,
) !void {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);

    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(raw);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var parsed = std.json.parseFromSlice(std.json.Value, arena, raw, .{}) catch return error.InvalidSettingsJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidSettingsJson;

    try applyEditableMutation(arena, &parsed.value.object, mutation);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');

    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, settings_path, .{
        .replace = true,
        .make_path = true,
        .permissions = .default_file,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    try atomic.file.sync(io);
    try atomic.replace(io);

    var verified = try loadFile(gpa, io, settings_path);
    defer verified.deinit(gpa);
    if (!editableMatches(verified, mutation)) return error.SettingsVerificationFailed;
}

fn clearEditableLocked(
    gpa: std.mem.Allocator,
    io: Io,
    registry_dir: []const u8,
    key: EditableKey,
) !void {
    const settings_path = try std.fs.path.join(gpa, &.{ registry_dir, "settings.json" });
    defer gpa.free(settings_path);

    const raw = std.Io.Dir.cwd().readFileAlloc(io, settings_path, gpa, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer gpa.free(raw);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var parsed = std.json.parseFromSlice(std.json.Value, arena, raw, .{}) catch return error.InvalidSettingsJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidSettingsJson;
    removeEditableMutation(&parsed.value.object, key);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');

    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, settings_path, .{
        .replace = true,
        .make_path = true,
        .permissions = .default_file,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    try atomic.file.sync(io);
    try atomic.replace(io);

    var verified = try loadFile(gpa, io, settings_path);
    defer verified.deinit(gpa);
    if (isEditableExplicit(verified, key)) return error.SettingsVerificationFailed;
}

fn packageScope(scope: EditableScope) packages.Scope {
    return switch (scope) {
        .global => .user,
        .project => .project,
    };
}

/// Atomically persist one native `/settings` selection in either the global
/// agent directory or a trusted project's `.pi/settings.json`.
pub fn setEditableScoped(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    trust_project: bool,
    scope: EditableScope,
    key: EditableKey,
    value: EditableValue,
) !void {
    if (scope == .project and (key == .enable_install_telemetry or key == .default_project_trust))
        return error.GlobalOnlySetting;
    try packages.withScopeConfigurationLock(
        gpa,
        io,
        agent_dir,
        cwd,
        packageScope(scope),
        trust_project,
        EditableMutation{ .key = key, .value = value },
        persistEditableLocked,
    );
}

/// Remove a project or global override, restoring inheritance/default behavior.
pub fn clearEditableScoped(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    trust_project: bool,
    scope: EditableScope,
    key: EditableKey,
) !void {
    if (scope == .project and (key == .enable_install_telemetry or key == .default_project_trust))
        return error.GlobalOnlySetting;
    try packages.withScopeConfigurationLock(
        gpa,
        io,
        agent_dir,
        cwd,
        packageScope(scope),
        trust_project,
        key,
        clearEditableLocked,
    );
}

/// Compatibility wrapper for the original global-only selector API.
pub fn setEditable(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    key: EditableKey,
    value: EditableValue,
) !void {
    return setEditableScoped(gpa, io, agent_dir, ".", true, .global, key, value);
}

pub fn loadFile(gpa: std.mem.Allocator, io: Io, path: []const u8) !Settings {
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer gpa.free(raw);
    return try parse(gpa, raw);
}

pub fn parse(gpa: std.mem.Allocator, raw: []const u8) !Settings {
    const content = if (std.mem.startsWith(u8, raw, "\xEF\xBB\xBF")) raw[3..] else raw;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return .{};

    var s: Settings = .{};
    errdefer s.deinit(gpa);

    // Accept upstream keys (defaultModel/defaultProvider) and short aliases
    if (parsed.value.object.get("model") orelse parsed.value.object.get("defaultModel") orelse parsed.value.object.get("default_model")) |v| {
        if (v == .string) s.model = try gpa.dupe(u8, v.string);
    }
    if (parsed.value.object.get("provider") orelse parsed.value.object.get("defaultProvider") orelse parsed.value.object.get("default_provider")) |v| {
        if (v == .string) s.provider = try gpa.dupe(u8, v.string);
    }
    if (parsed.value.object.get("enabledModels") orelse parsed.value.object.get("enabled_models")) |v| {
        if (v == .array) {
            var models: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (models.items) |model| gpa.free(model);
                models.deinit(gpa);
            }
            for (v.array.items) |item| {
                if (item != .string) continue;
                const value = std.mem.trim(u8, item.string, " \t\r\n");
                if (value.len > 0) try models.append(gpa, try gpa.dupe(u8, value));
            }
            s.enabled_models = try models.toOwnedSlice(gpa);
        }
    }
    if (parsed.value.object.get("max_turns") orelse parsed.value.object.get("maxTurns")) |v| {
        if (v == .integer and v.integer >= 0) {
            s.max_turns = @intCast(v.integer);
            s.max_turns_explicit = true;
        }
    }
    if (parsed.value.object.get("thinkingLevel") orelse parsed.value.object.get("thinking_level") orelse parsed.value.object.get("defaultThinkingLevel")) |v| {
        if (v == .string) s.thinking_level = try gpa.dupe(u8, v.string);
    }
    if (parsed.value.object.get("theme")) |v| {
        if (v == .string and v.string.len > 0) s.theme = try gpa.dupe(u8, v.string);
    }
    if (parsed.value.object.get("transport")) |v| {
        if (v == .string) s.transport = codex_ws.Transport.parse(v.string);
    }
    if (parsed.value.object.get("steeringMode") orelse parsed.value.object.get("steering_mode")) |v| {
        if (v == .string) s.steering_mode = DeliveryMode.parse(v.string);
    }
    if (parsed.value.object.get("followUpMode") orelse parsed.value.object.get("follow_up_mode")) |v| {
        if (v == .string) s.follow_up_mode = DeliveryMode.parse(v.string);
    }
    if (parsed.value.object.get("httpProxy") orelse parsed.value.object.get("http_proxy")) |v| {
        if (v == .string) {
            const trimmed = std.mem.trim(u8, v.string, " \t\r\n");
            if (trimmed.len > 0) s.http_proxy = try gpa.dupe(u8, trimmed);
        }
    }
    if (parsed.value.object.get("lastChangelogVersion") orelse parsed.value.object.get("last_changelog_version")) |v| {
        if (v == .string) {
            const trimmed = std.mem.trim(u8, v.string, " \t\r\n");
            if (trimmed.len > 0) s.last_changelog_version = try gpa.dupe(u8, trimmed);
        }
    }
    if (parsed.value.object.get("collapseChangelog") orelse parsed.value.object.get("collapse_changelog")) |v| {
        if (v == .bool) s.collapse_changelog = v.bool;
    }
    if (parsed.value.object.get("quietStartup") orelse parsed.value.object.get("quiet_startup")) |v| {
        if (v == .bool) s.quiet_startup = v.bool;
    }
    if (parsed.value.object.get("hideThinkingBlock") orelse parsed.value.object.get("hide_thinking_block")) |v| {
        if (v == .bool) s.hide_thinking_block = v.bool;
    }
    if (parsed.value.object.get("showCacheMissNotices") orelse parsed.value.object.get("show_cache_miss_notices")) |v| {
        if (v == .bool) s.show_cache_miss_notices = v.bool;
    }
    if (parsed.value.object.get("doubleEscapeAction") orelse parsed.value.object.get("double_escape_action")) |v| {
        if (v == .string) s.double_escape_action = DoubleEscapeAction.parse(v.string);
    }
    if (parsed.value.object.get("treeFilterMode") orelse parsed.value.object.get("tree_filter_mode")) |v| {
        if (v == .string) s.tree_filter_mode = TreeFilterMode.parse(v.string);
    }
    if (parsed.value.object.get("fullscreenCopyOnSelect") orelse parsed.value.object.get("fullscreen_copy_on_select")) |v| {
        if (v == .bool) s.fullscreen_copy_on_select = v.bool;
    }
    if (parsed.value.object.get("terminal")) |v| {
        if (v == .object) {
            if (v.object.get("showImages") orelse v.object.get("show_images")) |show| {
                if (show == .bool) s.show_images = show.bool;
            }
            if (v.object.get("imageWidthCells") orelse v.object.get("image_width_cells")) |width| {
                if (width == .integer and width.integer >= 1) s.image_width_cells = @intCast(width.integer);
            }
            if (v.object.get("hyperlinks")) |value| switch (value) {
                .bool => |enabled| s.terminal_hyperlinks = enabled,
                .string => {}, // "auto" leaves detection unchanged.
                else => {},
            };
            if (v.object.get("images")) |value| switch (value) {
                .bool => |enabled| if (!enabled) {
                    s.terminal_image_protocol = .none;
                },
                .string => |name| {
                    if (std.ascii.eqlIgnoreCase(name, "kitty")) s.terminal_image_protocol = .kitty else if (std.ascii.eqlIgnoreCase(name, "iterm2")) s.terminal_image_protocol = .iterm2;
                },
                else => {},
            };
            if (v.object.get("trueColor") orelse v.object.get("true_color")) |value| switch (value) {
                .bool => |enabled| s.terminal_true_color = enabled,
                .string => {}, // "auto"
                else => {},
            };
            if (v.object.get("clearOnShrink") orelse v.object.get("clear_on_shrink")) |clear| {
                if (clear == .bool) s.clear_on_shrink = clear.bool;
            }
            if (v.object.get("showTerminalProgress") orelse v.object.get("show_terminal_progress")) |progress| {
                if (progress == .bool) s.show_terminal_progress = progress.bool;
            }
        }
    }
    if (parsed.value.object.get("images")) |v| {
        if (v == .object) {
            if (v.object.get("autoResize") orelse v.object.get("auto_resize")) |resize| {
                if (resize == .bool) s.auto_resize_images = resize.bool;
            }
            if (v.object.get("blockImages") orelse v.object.get("block_images")) |blocked| {
                if (blocked == .bool) s.block_images = blocked.bool;
            }
        }
    }
    if (parsed.value.object.get("enableSkillCommands") orelse parsed.value.object.get("enable_skill_commands")) |v| {
        if (v == .bool) s.enable_skill_commands = v.bool;
    } else if (parsed.value.object.get("skills")) |v| {
        // Upstream migration compatibility for older nested skill settings.
        if (v == .object) if (v.object.get("enableSkillCommands") orelse v.object.get("enable_skill_commands")) |enabled| {
            if (enabled == .bool) s.enable_skill_commands = enabled.bool;
        };
    }
    if (parsed.value.object.get("editorPaddingX") orelse parsed.value.object.get("editor_padding_x")) |v| {
        if (v == .integer and v.integer >= 0) s.editor_padding_x = @intCast(@min(v.integer, 3));
    }
    if (parsed.value.object.get("outputPad") orelse parsed.value.object.get("output_pad")) |v| {
        if (v == .integer) s.output_pad = if (v.integer == 0) 0 else 1;
    }
    if (parsed.value.object.get("autocompleteMaxVisible") orelse parsed.value.object.get("autocomplete_max_visible")) |v| {
        if (v == .integer) s.autocomplete_max_visible = @intCast(@max(@as(i64, 3), @min(v.integer, 20)));
    }
    if (parsed.value.object.get("showHardwareCursor") orelse parsed.value.object.get("show_hardware_cursor")) |v| {
        if (v == .bool) s.show_hardware_cursor = v.bool;
    }
    if (parsed.value.object.get("markdown")) |v| {
        if (v == .object) if (v.object.get("mermaid")) |mode| {
            if (mode == .string) s.mermaid_mode = MermaidMode.parse(mode.string);
        };
    }
    if (parsed.value.object.get("warnings")) |v| {
        if (v == .object) if (v.object.get("anthropicExtraUsage") orelse v.object.get("anthropic_extra_usage")) |enabled| {
            if (enabled == .bool) s.warning_anthropic_extra_usage = enabled.bool;
        };
    }
    if (parsed.value.object.get("tuiMode") orelse parsed.value.object.get("tui_mode")) |v| {
        if (v == .string) s.tui_mode = TuiMode.parse(v.string);
    }
    if (parsed.value.object.get("fullscreenExitOutput") orelse parsed.value.object.get("fullscreen_exit_output")) |v| {
        if (v == .string) s.fullscreen_exit_output = FullscreenExitOutput.parse(v.string);
    }
    if (parsed.value.object.get("fullscreenScrollbar") orelse parsed.value.object.get("fullscreen_scrollbar")) |v| {
        if (v == .string) s.fullscreen_scrollbar = FullscreenScrollbar.parse(v.string);
    }
    if (parsed.value.object.get("enableInstallTelemetry") orelse parsed.value.object.get("enable_install_telemetry")) |v| {
        if (v == .bool) s.enable_install_telemetry = v.bool;
    }
    if (parsed.value.object.get("npmCommand") orelse parsed.value.object.get("npm_command")) |v| {
        if (v == .array and v.array.items.len > 0 and v.array.items.len <= 64) {
            var command: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (command.items) |part| gpa.free(part);
                command.deinit(gpa);
            }
            var valid = true;
            for (v.array.items) |item| {
                if (item != .string or item.string.len == 0 or std.mem.indexOfScalar(u8, item.string, 0) != null) {
                    valid = false;
                    break;
                }
                try command.append(gpa, try gpa.dupe(u8, item.string));
            }
            if (valid and command.items.len > 0) {
                s.npm_command = try command.toOwnedSlice(gpa);
            } else {
                for (command.items) |part| gpa.free(part);
                command.deinit(gpa);
            }
        }
    }
    if (parsed.value.object.get("httpIdleTimeoutMs") orelse parsed.value.object.get("http_idle_timeout_ms")) |v| {
        if (v == .integer and v.integer >= 0) {
            s.http_idle_timeout_ms = @intCast(v.integer);
        } else if (v == .string and std.ascii.eqlIgnoreCase(v.string, "disabled")) {
            s.http_idle_timeout_ms = 0;
        }
    }
    if (parsed.value.object.get("websocketConnectTimeoutMs") orelse parsed.value.object.get("websocket_connect_timeout_ms")) |v| {
        if (v == .integer and v.integer >= 0) {
            s.websocket_connect_timeout_ms = @intCast(v.integer);
        } else if (v == .string and std.ascii.eqlIgnoreCase(v.string, "disabled")) {
            s.websocket_connect_timeout_ms = 0;
        }
    }
    if (parsed.value.object.get("compaction")) |v| {
        if (v == .object) {
            if (v.object.get("enabled")) |enabled| {
                if (enabled == .bool) s.compaction_enabled = enabled.bool;
            }
            if (v.object.get("reserveTokens") orelse v.object.get("reserve_tokens")) |reserve| {
                if (reserve == .integer and reserve.integer >= 0) s.compaction_reserve_tokens = @intCast(reserve.integer);
            }
            if (v.object.get("keepRecentTokens") orelse v.object.get("keep_recent_tokens")) |keep| {
                if (keep == .integer and keep.integer >= 0) s.compaction_keep_recent_tokens = @intCast(keep.integer);
            }
        }
    }
    if (parsed.value.object.get("autoCompactionEnabled") orelse parsed.value.object.get("auto_compaction_enabled")) |v| {
        if (v == .bool) s.compaction_enabled = v.bool;
    }
    if (parsed.value.object.get("branchSummary") orelse parsed.value.object.get("branch_summary")) |v| {
        if (v == .object) {
            if (v.object.get("reserveTokens") orelse v.object.get("reserve_tokens")) |reserve| {
                if (reserve == .integer and reserve.integer >= 0) s.branch_summary_reserve_tokens = @intCast(reserve.integer);
            }
            if (v.object.get("skipPrompt") orelse v.object.get("skip_prompt")) |skip| {
                if (skip == .bool) s.branch_summary_skip_prompt = skip.bool;
            }
        }
    }
    if (parsed.value.object.get("retry")) |v| {
        if (v == .object) {
            if (v.object.get("enabled")) |enabled| {
                if (enabled == .bool) s.retry_enabled = enabled.bool;
            }
            if (v.object.get("maxRetries") orelse v.object.get("max_retries")) |max_retries| {
                if (max_retries == .integer and max_retries.integer >= 0) s.retry_max_retries = @intCast(max_retries.integer);
            }
            if (v.object.get("baseDelayMs") orelse v.object.get("base_delay_ms")) |base_delay| {
                if (base_delay == .integer and base_delay.integer >= 0) s.retry_base_delay_ms = @intCast(base_delay.integer);
            }
            if (v.object.get("provider")) |provider| {
                if (provider == .object) {
                    if (provider.object.get("timeoutMs") orelse provider.object.get("timeout_ms")) |timeout| {
                        if (timeout == .integer and timeout.integer >= 0) s.retry_provider_timeout_ms = @intCast(timeout.integer);
                    }
                    if (provider.object.get("maxRetries") orelse provider.object.get("max_retries")) |max_retries| {
                        if (max_retries == .integer and max_retries.integer >= 0) s.retry_provider_max_retries = @intCast(max_retries.integer);
                    }
                    if (provider.object.get("maxRetryDelayMs") orelse provider.object.get("max_retry_delay_ms")) |max_delay| {
                        if (max_delay == .integer and max_delay.integer >= 0) s.retry_provider_max_retry_delay_ms = @intCast(max_delay.integer);
                    }
                }
            }
            // Upstream migration: retry.maxDelayMs moved under
            // retry.provider.maxRetryDelayMs. The nested value wins.
            if (s.retry_provider_max_retry_delay_ms == null) {
                if (v.object.get("maxDelayMs") orelse v.object.get("max_delay_ms")) |max_delay| {
                    if (max_delay == .integer and max_delay.integer >= 0) s.retry_provider_max_retry_delay_ms = @intCast(max_delay.integer);
                }
            }
        }
    }
    if (parsed.value.object.get("autoRetryEnabled") orelse parsed.value.object.get("auto_retry_enabled")) |v| {
        if (v == .bool) s.retry_enabled = v.bool;
    }
    if (parsed.value.object.get("compactionReserveTokens") orelse parsed.value.object.get("compaction_reserve_tokens")) |v| {
        if (v == .integer and v.integer >= 0) s.compaction_reserve_tokens = @intCast(v.integer);
    }
    if (parsed.value.object.get("compactionKeepRecentTokens") orelse parsed.value.object.get("compaction_keep_recent_tokens")) |v| {
        if (v == .integer and v.integer >= 0) s.compaction_keep_recent_tokens = @intCast(v.integer);
    }
    if (parsed.value.object.get("branchSummaryReserveTokens") orelse parsed.value.object.get("branch_summary_reserve_tokens")) |v| {
        if (v == .integer and v.integer >= 0) s.branch_summary_reserve_tokens = @intCast(v.integer);
    }
    if (parsed.value.object.get("branchSummarySkipPrompt") orelse parsed.value.object.get("branch_summary_skip_prompt")) |v| {
        if (v == .bool) s.branch_summary_skip_prompt = v.bool;
    }
    if (parsed.value.object.get("defaultProjectTrust")) |v| {
        if (v == .string) {
            if (std.mem.eql(u8, v.string, "always")) s.default_project_trust = .always else if (std.mem.eql(u8, v.string, "never")) s.default_project_trust = .never else if (std.mem.eql(u8, v.string, "ask")) s.default_project_trust = .ask;
        }
    }
    if (parsed.value.object.get("defaultTools") orelse parsed.value.object.get("tools")) |v| {
        if (v == .array) {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (list.items) |x| gpa.free(x);
                list.deinit(gpa);
            }
            for (v.array.items) |item| {
                if (item == .string) try list.append(gpa, try gpa.dupe(u8, item.string));
            }
            s.tools = try list.toOwnedSlice(gpa);
        }
    }
    return s;
}

/// Merge global then project (project wins).
/// When `trust_project` is false, project `.pi/settings.json` is skipped (--no-approve).
pub fn loadMerge(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    cwd: []const u8,
) !Settings {
    return loadMergeTrusted(gpa, io, agent_dir, cwd, true);
}

pub fn loadMergeTrusted(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    cwd: []const u8,
    trust_project: bool,
) !Settings {
    var result: Settings = .{};
    errdefer result.deinit(gpa);

    if (agent_dir) |ad| {
        const p = try std.fs.path.join(gpa, &.{ ad, "settings.json" });
        defer gpa.free(p);
        var g = try loadFile(gpa, io, p);
        defer g.deinit(gpa);
        try mergeIntoScoped(gpa, &result, g, true);
        result.default_project_trust = g.default_project_trust;
    }

    // project: .pi/settings.json (only when trusted)
    if (trust_project) {
        const p = try std.fs.path.join(gpa, &.{ cwd, ".pi", "settings.json" });
        defer gpa.free(p);
        var proj = try loadFile(gpa, io, p);
        defer proj.deinit(gpa);
        try mergeIntoScoped(gpa, &result, proj, false);
    }

    return result;
}

/// Tolerant settings load for interactive startup/reload. Invalid scopes are
/// reported with their concrete file path while valid scopes remain usable.
pub fn loadMergeTrustedDiagnosed(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    cwd: []const u8,
    trust_project: bool,
) !DiagnosedSettings {
    var result: DiagnosedSettings = .{};
    errdefer result.deinit(gpa);
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    errdefer {
        for (diagnostics.items) |*diagnostic| diagnostic.deinit(gpa);
        diagnostics.deinit(gpa);
    }

    const Scope = struct {
        fn load(
            allocator: std.mem.Allocator,
            filesystem: Io,
            output: *Settings,
            list: *std.ArrayList(Diagnostic),
            path: []const u8,
            include_global_only: bool,
        ) !void {
            var loaded = loadFile(allocator, filesystem, path) catch |err| {
                const message = try std.fmt.allocPrint(allocator, "settings could not be loaded: {s}", .{@errorName(err)});
                errdefer allocator.free(message);
                try list.append(allocator, .{ .path = try allocator.dupe(u8, path), .message = message });
                return;
            };
            defer loaded.deinit(allocator);
            try mergeIntoScoped(allocator, output, loaded, include_global_only);
            if (include_global_only) output.default_project_trust = loaded.default_project_trust;
        }
    };

    if (agent_dir) |directory| {
        const path = try std.fs.path.join(gpa, &.{ directory, "settings.json" });
        defer gpa.free(path);
        try Scope.load(gpa, io, &result.settings, &diagnostics, path, true);
    }
    if (trust_project) {
        const path = try std.fs.path.join(gpa, &.{ cwd, ".pi", "settings.json" });
        defer gpa.free(path);
        try Scope.load(gpa, io, &result.settings, &diagnostics, path, false);
    }
    result.diagnostics = try diagnostics.toOwnedSlice(gpa);
    return result;
}

fn mergeInto(gpa: std.mem.Allocator, dst: *Settings, src: Settings) !void {
    return mergeIntoScoped(gpa, dst, src, true);
}

fn mergeIntoScoped(gpa: std.mem.Allocator, dst: *Settings, src: Settings, include_global_only: bool) !void {
    if (src.model) |m| {
        if (dst.model) |old| gpa.free(old);
        dst.model = try gpa.dupe(u8, m);
    }
    if (src.provider) |p| {
        if (dst.provider) |old| gpa.free(old);
        dst.provider = try gpa.dupe(u8, p);
    }
    if (src.enabled_models) |models| {
        if (dst.enabled_models) |old| {
            for (old) |model| gpa.free(model);
            gpa.free(old);
        }
        const copied = try gpa.alloc([]const u8, models.len);
        var initialized: usize = 0;
        errdefer {
            for (copied[0..initialized]) |model| gpa.free(model);
            gpa.free(copied);
        }
        for (models, 0..) |model, index| {
            copied[index] = try gpa.dupe(u8, model);
            initialized += 1;
        }
        dst.enabled_models = copied;
    }
    if (src.thinking_level) |t| {
        if (dst.thinking_level) |old| gpa.free(old);
        dst.thinking_level = try gpa.dupe(u8, t);
    }
    if (src.theme) |t| {
        if (dst.theme) |old| gpa.free(old);
        dst.theme = try gpa.dupe(u8, t);
    }
    if (src.transport) |transport| dst.transport = transport;
    if (src.steering_mode) |mode| dst.steering_mode = mode;
    if (src.follow_up_mode) |mode| dst.follow_up_mode = mode;
    if (include_global_only) if (src.http_proxy) |proxy| {
        if (dst.http_proxy) |old| gpa.free(old);
        dst.http_proxy = try gpa.dupe(u8, proxy);
    };
    if (include_global_only) if (src.last_changelog_version) |version| {
        if (dst.last_changelog_version) |old| gpa.free(old);
        dst.last_changelog_version = try gpa.dupe(u8, version);
    };
    if (src.collapse_changelog) |collapse| dst.collapse_changelog = collapse;
    if (src.quiet_startup) |quiet| dst.quiet_startup = quiet;
    if (src.hide_thinking_block) |hide| dst.hide_thinking_block = hide;
    if (src.show_cache_miss_notices) |show| dst.show_cache_miss_notices = show;
    if (src.double_escape_action) |action| dst.double_escape_action = action;
    if (src.tree_filter_mode) |mode| dst.tree_filter_mode = mode;
    if (src.show_images) |show| dst.show_images = show;
    if (src.image_width_cells) |width| dst.image_width_cells = width;
    if (src.terminal_hyperlinks) |enabled| dst.terminal_hyperlinks = enabled;
    if (src.terminal_image_protocol) |protocol| dst.terminal_image_protocol = protocol;
    if (src.terminal_true_color) |enabled| dst.terminal_true_color = enabled;
    if (src.clear_on_shrink) |clear| dst.clear_on_shrink = clear;
    if (src.show_terminal_progress) |show| dst.show_terminal_progress = show;
    if (src.auto_resize_images) |resize| dst.auto_resize_images = resize;
    if (src.block_images) |blocked| dst.block_images = blocked;
    if (src.enable_skill_commands) |enabled| dst.enable_skill_commands = enabled;
    if (src.editor_padding_x) |padding| dst.editor_padding_x = padding;
    if (src.output_pad) |padding| dst.output_pad = padding;
    if (src.autocomplete_max_visible) |count| dst.autocomplete_max_visible = count;
    if (src.show_hardware_cursor) |show| dst.show_hardware_cursor = show;
    if (src.mermaid_mode) |mode| dst.mermaid_mode = mode;
    if (src.warning_anthropic_extra_usage) |enabled| dst.warning_anthropic_extra_usage = enabled;
    if (src.tui_mode) |mode| dst.tui_mode = mode;
    if (src.fullscreen_exit_output) |mode| dst.fullscreen_exit_output = mode;
    if (src.fullscreen_scrollbar) |mode| dst.fullscreen_scrollbar = mode;
    if (src.fullscreen_copy_on_select) |enabled| dst.fullscreen_copy_on_select = enabled;
    if (include_global_only) {
        if (src.enable_install_telemetry) |enabled| dst.enable_install_telemetry = enabled;
    }
    if (src.npm_command) |command| {
        if (dst.npm_command) |old| {
            for (old) |part| gpa.free(part);
            gpa.free(old);
        }
        var copy = try gpa.alloc([]const u8, command.len);
        var initialized: usize = 0;
        errdefer {
            for (copy[0..initialized]) |part| gpa.free(part);
            gpa.free(copy);
        }
        for (command, 0..) |part, index| {
            copy[index] = try gpa.dupe(u8, part);
            initialized += 1;
        }
        dst.npm_command = copy;
    }
    if (src.http_idle_timeout_ms) |timeout_ms| dst.http_idle_timeout_ms = timeout_ms;
    if (src.websocket_connect_timeout_ms) |timeout_ms| dst.websocket_connect_timeout_ms = timeout_ms;
    if (src.compaction_enabled) |enabled| dst.compaction_enabled = enabled;
    if (src.compaction_reserve_tokens) |tokens| dst.compaction_reserve_tokens = tokens;
    if (src.compaction_keep_recent_tokens) |tokens| dst.compaction_keep_recent_tokens = tokens;
    if (src.branch_summary_reserve_tokens) |tokens| dst.branch_summary_reserve_tokens = tokens;
    if (src.branch_summary_skip_prompt) |skip| dst.branch_summary_skip_prompt = skip;
    if (src.retry_enabled) |enabled| dst.retry_enabled = enabled;
    if (src.retry_max_retries) |max_retries| dst.retry_max_retries = max_retries;
    if (src.retry_base_delay_ms) |base_delay_ms| dst.retry_base_delay_ms = base_delay_ms;
    if (src.retry_provider_timeout_ms) |timeout_ms| dst.retry_provider_timeout_ms = timeout_ms;
    if (src.retry_provider_max_retries) |max_retries| dst.retry_provider_max_retries = max_retries;
    if (src.retry_provider_max_retry_delay_ms) |max_delay_ms| dst.retry_provider_max_retry_delay_ms = max_delay_ms;
    if (src.tools) |t| {
        if (dst.tools) |old| {
            for (old) |x| gpa.free(x);
            gpa.free(old);
        }
        var list: std.ArrayList([]const u8) = .empty;
        for (t) |x| try list.append(gpa, try gpa.dupe(u8, x));
        dst.tools = try list.toOwnedSlice(gpa);
    }
    if (src.max_turns_explicit) {
        dst.max_turns = src.max_turns;
        dst.max_turns_explicit = true;
    }
}

pub fn formatSettings(gpa: std.mem.Allocator, s: Settings) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const transport_name: []const u8 = if (s.transport) |transport| switch (transport) {
        .sse => "sse",
        .websocket => "websocket",
        .websocket_cached => "websocket-cached",
        .auto => "auto",
    } else "auto";
    const trust_name: []const u8 = @tagName(s.default_project_trust);
    const steering_name = if (s.steering_mode) |mode| mode.wireName() else "one-at-a-time";
    const follow_up_name = if (s.follow_up_mode) |mode| mode.wireName() else "one-at-a-time";
    const tree_filter_name = if (s.tree_filter_mode) |mode| mode.wireName() else "default";
    const timeout_name = if (s.http_idle_timeout_ms) |value| try std.fmt.allocPrint(gpa, "{d}", .{value}) else try gpa.dupe(u8, "(default)");
    defer gpa.free(timeout_name);
    const ws_connect_timeout_name = if (s.websocket_connect_timeout_ms) |value| try std.fmt.allocPrint(gpa, "{d}", .{value}) else try gpa.dupe(u8, "(default)");
    defer gpa.free(ws_connect_timeout_name);
    var npm_command_text: std.Io.Writer.Allocating = .init(gpa);
    defer npm_command_text.deinit();
    if (s.npm_command) |command| {
        for (command, 0..) |part, index| {
            if (index > 0) try npm_command_text.writer.writeByte(' ');
            try npm_command_text.writer.writeAll(part);
        }
    } else try npm_command_text.writer.writeAll("npm");
    const provider_timeout_name = if (s.retry_provider_timeout_ms) |value| try std.fmt.allocPrint(gpa, "{d}", .{value}) else try gpa.dupe(u8, "(default)");
    defer gpa.free(provider_timeout_name);
    const provider_retries_name = if (s.retry_provider_max_retries) |value| try std.fmt.allocPrint(gpa, "{d}", .{value}) else try gpa.dupe(u8, "(default)");
    defer gpa.free(provider_retries_name);
    const header_identity = try std.fmt.allocPrint(gpa, "model={s}\nprovider={s}\nmax_turns={d}\nthinking={s}\ntheme={s}\ntransport={s}\nsteering_mode={s}\nfollow_up_mode={s}\nhttp_proxy={s}\nlast_changelog_version={s}\ncollapse_changelog={s}\nquiet_startup={s}\ntree_filter_mode={s}\nshow_images={s}\nimage_width_cells={d}\nblock_images={s}\nenable_skill_commands={s}\n", .{
        s.model orelse "(default)",
        s.provider orelse "(default)",
        s.max_turns,
        s.thinking_level orelse "(default)",
        s.theme orelse "(default)",
        transport_name,
        steering_name,
        follow_up_name,
        if (s.http_proxy != null) "(configured)" else "(unset)",
        s.last_changelog_version orelse "(unset)",
        if (s.collapse_changelog orelse false) "true" else "false",
        if (s.quiet_startup orelse false) "true" else "false",
        tree_filter_name,
        if (s.show_images orelse true) "true" else "false",
        s.image_width_cells orelse 60,
        if (s.block_images orelse false) "true" else "false",
        if (s.enable_skill_commands orelse true) "true" else "false",
    });
    defer gpa.free(header_identity);
    try out.appendSlice(gpa, header_identity);

    const header_policy = try std.fmt.allocPrint(gpa, "enable_install_telemetry={s}\nnpm_command={s}\nhttp_idle_timeout_ms={s}\nwebsocket_connect_timeout_ms={s}\ncompaction_enabled={s}\ncompaction_reserve_tokens={d}\ncompaction_keep_recent_tokens={d}\nbranch_summary_reserve_tokens={d}\nbranch_summary_skip_prompt={s}\nretry_enabled={s}\nretry_max_retries={d}\nretry_base_delay_ms={d}\nretry_provider_timeout_ms={s}\nretry_provider_max_retries={s}\nretry_provider_max_retry_delay_ms={d}\ndefault_project_trust={s}\n", .{
        if (s.enable_install_telemetry orelse true) "true" else "false",
        npm_command_text.written(),
        timeout_name,
        ws_connect_timeout_name,
        if (s.compaction_enabled orelse true) "true" else "false",
        s.compaction_reserve_tokens orelse 16_384,
        s.compaction_keep_recent_tokens orelse 20_000,
        s.branch_summary_reserve_tokens orelse 16_384,
        if (s.branch_summary_skip_prompt orelse false) "true" else "false",
        if (s.retry_enabled orelse true) "true" else "false",
        s.retry_max_retries orelse 3,
        s.retry_base_delay_ms orelse 2_000,
        provider_timeout_name,
        provider_retries_name,
        s.retry_provider_max_retry_delay_ms orelse 60_000,
        trust_name,
    });
    defer gpa.free(header_policy);
    try out.appendSlice(gpa, header_policy);

    const extended_ui = try std.fmt.allocPrint(gpa, "hide_thinking_block={s}\nshow_cache_miss_notices={s}\ndouble_escape_action={s}\nclear_on_shrink={s}\nshow_terminal_progress={s}\nauto_resize_images={s}\neditor_padding_x={d}\noutput_pad={d}\nautocomplete_max_visible={d}\nshow_hardware_cursor={s}\nmermaid_mode={s}\nwarning_anthropic_extra_usage={s}\ntui_mode={s}\nfullscreen_exit_output={s}\nfullscreen_scrollbar={s}\n", .{
        if (s.hide_thinking_block orelse false) "true" else "false",
        if (s.show_cache_miss_notices orelse false) "true" else "false",
        if (s.double_escape_action) |action| action.wireName() else "tree",
        if (s.clear_on_shrink orelse false) "true" else "false",
        if (s.show_terminal_progress orelse false) "true" else "false",
        if (s.auto_resize_images orelse true) "true" else "false",
        s.editor_padding_x orelse 0,
        s.output_pad orelse 1,
        s.autocomplete_max_visible orelse 5,
        if (s.show_hardware_cursor orelse false) "true" else "false",
        if (s.mermaid_mode) |mode| mode.wireName() else "streaming",
        if (s.warning_anthropic_extra_usage orelse true) "true" else "false",
        if (s.tui_mode) |mode| mode.wireName() else "regular",
        if (s.fullscreen_exit_output) |mode| mode.wireName() else "transcript",
        if (s.fullscreen_scrollbar) |mode| mode.wireName() else "auto",
    });
    defer gpa.free(extended_ui);
    try out.appendSlice(gpa, extended_ui);
    if (s.tools) |t| {
        try out.appendSlice(gpa, "tools=");
        for (t, 0..) |name, i| {
            if (i > 0) try out.append(gpa, ',');
            try out.appendSlice(gpa, name);
        }
        try out.append(gpa, '\n');
    }
    return try out.toOwnedSlice(gpa);
}

test "media privacy and skill-command settings parse merge format and persist" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var global = try parse(gpa,
        \\{"terminal":{"showImages":false,"imageWidthCells":72},"images":{"blockImages":true},"skills":{"enableSkillCommands":false}}
    );
    defer global.deinit(gpa);
    try std.testing.expectEqual(@as(?bool, false), global.show_images);
    try std.testing.expectEqual(@as(?u64, 72), global.image_width_cells);
    try std.testing.expectEqual(@as(?bool, true), global.block_images);
    try std.testing.expectEqual(@as(?bool, false), global.enable_skill_commands);

    var project = try parse(gpa,
        \\{"terminal":{"show_images":true},"images":{"block_images":false},"enable_skill_commands":true}
    );
    defer project.deinit(gpa);
    try mergeIntoScoped(gpa, &global, project, false);
    try std.testing.expectEqual(@as(?bool, true), global.show_images);
    try std.testing.expectEqual(@as(?u64, 72), global.image_width_cells);
    try std.testing.expectEqual(@as(?bool, false), global.block_images);
    try std.testing.expectEqual(@as(?bool, true), global.enable_skill_commands);

    const formatted = try formatSettings(gpa, global);
    defer gpa.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "show_images=true\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "image_width_cells=72\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "block_images=false\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "enable_skill_commands=true\n") != null);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const settings_path = try std.fs.path.join(gpa, &.{ root, "settings.json" });
    defer gpa.free(settings_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings_path, .data =
        \\{"terminal":{"showImages":true,"imageWidthCells":60},"images":{"blockImages":false},"enableSkillCommands":true,"theme":"keep"}
    });
    try setEditable(gpa, io, root, .show_images, .{ .boolean = false });
    try setEditable(gpa, io, root, .image_width_cells, .{ .integer = 96 });
    try setEditable(gpa, io, root, .block_images, .{ .boolean = true });
    try setEditable(gpa, io, root, .enable_skill_commands, .{ .boolean = false });
    var persisted = try loadFile(gpa, io, settings_path);
    defer persisted.deinit(gpa);
    try std.testing.expectEqual(@as(?bool, false), persisted.show_images);
    try std.testing.expectEqual(@as(?u64, 96), persisted.image_width_cells);
    try std.testing.expectEqual(@as(?bool, true), persisted.block_images);
    try std.testing.expectEqual(@as(?bool, false), persisted.enable_skill_commands);
    try std.testing.expectEqualStrings("keep", persisted.theme.?);
}

test "settings parse and deeply merge retry and compaction policy" {
    const gpa = std.testing.allocator;
    var global = try parse(gpa,
        \\{"compaction":{"enabled":false},"retry":{"enabled":true,"maxRetries":5,"baseDelayMs":125,"provider":{"timeoutMs":9000,"maxRetryDelayMs":45000}}}
    );
    defer global.deinit(gpa);
    try std.testing.expectEqual(@as(?bool, false), global.compaction_enabled);
    try std.testing.expectEqual(@as(?bool, true), global.retry_enabled);
    try std.testing.expectEqual(@as(?usize, 5), global.retry_max_retries);
    try std.testing.expectEqual(@as(?u64, 125), global.retry_base_delay_ms);
    try std.testing.expectEqual(@as(?u64, 9000), global.retry_provider_timeout_ms);
    try std.testing.expectEqual(@as(?u64, 45000), global.retry_provider_max_retry_delay_ms);

    var project = try parse(gpa,
        \\{"compaction":{"enabled":true},"retry":{"maxRetries":2,"provider":{"maxRetries":4}}}
    );
    defer project.deinit(gpa);
    try mergeIntoScoped(gpa, &global, project, false);
    try std.testing.expectEqual(@as(?bool, true), global.compaction_enabled);
    try std.testing.expectEqual(@as(?bool, true), global.retry_enabled);
    try std.testing.expectEqual(@as(?usize, 2), global.retry_max_retries);
    try std.testing.expectEqual(@as(?u64, 125), global.retry_base_delay_ms);
    try std.testing.expectEqual(@as(?u64, 9000), global.retry_provider_timeout_ms);
    try std.testing.expectEqual(@as(?usize, 4), global.retry_provider_max_retries);
    try std.testing.expectEqual(@as(?u64, 45000), global.retry_provider_max_retry_delay_ms);

    const formatted = try formatSettings(gpa, global);
    defer gpa.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "compaction_enabled=true\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "retry_enabled=true\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "retry_max_retries=2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "retry_base_delay_ms=125\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "retry_provider_timeout_ms=9000\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "retry_provider_max_retries=4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "retry_provider_max_retry_delay_ms=45000\n") != null);
}

test "legacy retry maxDelayMs migrates into provider policy unless nested value exists" {
    const gpa = std.testing.allocator;
    var legacy = try parse(gpa, "{\"retry\":{\"maxDelayMs\":1234}}");
    defer legacy.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 1234), legacy.retry_provider_max_retry_delay_ms);

    var nested = try parse(gpa, "{\"retry\":{\"maxDelayMs\":1234,\"provider\":{\"maxRetryDelayMs\":5678}}}");
    defer nested.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 5678), nested.retry_provider_max_retry_delay_ms);
}

test "settings accept RPC-style retry and compaction aliases" {
    const gpa = std.testing.allocator;
    var settings = try parse(gpa,
        \\{"autoCompactionEnabled":false,"autoRetryEnabled":false}
    );
    defer settings.deinit(gpa);
    try std.testing.expectEqual(@as(?bool, false), settings.compaction_enabled);
    try std.testing.expectEqual(@as(?bool, false), settings.retry_enabled);
}

/// Store API keys as simple KEY=value lines in agent_dir/credentials
pub fn credentialsPath(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fs.path.join(gpa, &.{ agent_dir, "credentials" });
}

pub fn saveCredential(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, key: []const u8, value: []const u8) !void {
    _ = gpa;
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    const path = try std.fs.path.join(std.heap.page_allocator, &.{ agent_dir, "credentials" });
    defer std.heap.page_allocator.free(path);
    // Append or write simple file
    const line = try std.fmt.allocPrint(std.heap.page_allocator, "{s}={s}\n", .{ key, value });
    defer std.heap.page_allocator.free(line);
    // Read existing, replace key
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(64 * 1024)) catch "";
    defer if (existing.len > 0) std.heap.page_allocator.free(existing);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.page_allocator);
    var replaced = false;
    var it = std.mem.splitScalar(u8, existing, '\n');
    while (it.next()) |ln| {
        if (ln.len == 0) continue;
        if (std.mem.indexOfScalar(u8, ln, '=')) |eq| {
            if (std.mem.eql(u8, ln[0..eq], key)) {
                try out.appendSlice(std.heap.page_allocator, line);
                replaced = true;
                continue;
            }
        }
        try out.appendSlice(std.heap.page_allocator, ln);
        try out.append(std.heap.page_allocator, '\n');
    }
    if (!replaced) try out.appendSlice(std.heap.page_allocator, line);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
}

pub fn loadCredential(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, key: []const u8) !?[]u8 {
    const path = try credentialsPath(gpa, agent_dir);
    defer gpa.free(path);
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch return null;
    defer gpa.free(existing);
    var it = std.mem.splitScalar(u8, existing, '\n');
    while (it.next()) |ln| {
        if (std.mem.indexOfScalar(u8, ln, '=')) |eq| {
            if (std.mem.eql(u8, ln[0..eq], key)) {
                return try gpa.dupe(u8, ln[eq + 1 ..]);
            }
        }
    }
    return null;
}

pub fn clearCredentials(io: Io, agent_dir: []const u8) !void {
    const path = try std.fs.path.join(std.heap.page_allocator, &.{ agent_dir, "credentials" });
    defer std.heap.page_allocator.free(path);
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "" }) catch {};
}

test "defaultProjectTrust is global only" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    try std.Io.Dir.cwd().createDirPath(io, agent);
    const global_path = try std.fs.path.join(gpa, &.{ agent, "settings.json" });
    defer gpa.free(global_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = global_path, .data = "{\"defaultProjectTrust\":\"always\"}" });
    const project_pi = try std.fs.path.join(gpa, &.{ root, ".pi" });
    defer gpa.free(project_pi);
    try std.Io.Dir.cwd().createDirPath(io, project_pi);
    const project_path = try std.fs.path.join(gpa, &.{ project_pi, "settings.json" });
    defer gpa.free(project_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = project_path, .data = "{\"defaultProjectTrust\":\"never\"}" });
    var settings = try loadMergeTrusted(gpa, io, agent, root, true);
    defer settings.deinit(gpa);
    try std.testing.expectEqual(DefaultProjectTrust.always, settings.default_project_trust);
}

test "loadMergeTrusted skips project when untrusted" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const pi_dir = try std.fs.path.join(gpa, &.{ root, ".pi" });
    defer gpa.free(pi_dir);
    try std.Io.Dir.cwd().createDirPath(io, pi_dir);
    const proj_settings = try std.fs.path.join(gpa, &.{ pi_dir, "settings.json" });
    defer gpa.free(proj_settings);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = proj_settings,
        .data =
        \\{"model":"project-only-model","max_turns":3}
        ,
    });

    var untrusted = try loadMergeTrusted(gpa, io, null, root, false);
    defer untrusted.deinit(gpa);
    try std.testing.expect(untrusted.model == null);

    var trusted = try loadMergeTrusted(gpa, io, null, root, true);
    defer trusted.deinit(gpa);
    try std.testing.expectEqualStrings("project-only-model", trusted.model.?);
    try std.testing.expectEqual(@as(usize, 3), trusted.max_turns);
}

test "diagnosed settings retain valid scope and report invalid file path" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = path_buf[0..try tmp.dir.realPath(io, &path_buf)];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    const global_path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(global_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = global_path, .data = "{\"defaultModel\":\"valid-global\"}" });
    const project_dir = try std.fs.path.join(gpa, &.{ root, ".pi" });
    defer gpa.free(project_dir);
    try std.Io.Dir.cwd().createDirPath(io, project_dir);
    const project_path = try std.fs.path.join(gpa, &.{ project_dir, "settings.json" });
    defer gpa.free(project_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = project_path, .data = "{invalid" });

    var loaded = try loadMergeTrustedDiagnosed(gpa, io, agent_dir, root, true);
    defer loaded.deinit(gpa);
    try std.testing.expectEqualStrings("valid-global", loaded.settings.model.?);
    try std.testing.expectEqual(@as(usize, 1), loaded.diagnostics.len);
    try std.testing.expectEqualStrings(project_path, loaded.diagnostics[0].path);
    try std.testing.expect(std.mem.indexOf(u8, loaded.diagnostics[0].message, "settings could not be loaded") != null);
}

test "parse and merge settings" {
    const gpa = std.testing.allocator;
    var s = try parse(gpa,
        \\{"model":"gpt-4o","provider":"openai","max_turns":8,"tools":["read","bash"]}
    );
    defer s.deinit(gpa);
    try std.testing.expectEqualStrings("gpt-4o", s.model.?);
    try std.testing.expectEqual(@as(usize, 8), s.max_turns);
    try std.testing.expectEqual(@as(usize, 2), s.tools.?.len);
}

test "defaultTools replaces inherited built-in defaults and preserves an empty list" {
    const gpa = std.testing.allocator;
    var global = try parse(gpa, "{\"defaultTools\":[\"read\",\"bash\"]}");
    defer global.deinit(gpa);
    var project = try parse(gpa, "{\"defaultTools\":[\"powershell\"]}");
    defer project.deinit(gpa);
    try mergeInto(gpa, &global, project);
    try std.testing.expectEqual(@as(usize, 1), global.tools.?.len);
    try std.testing.expectEqualStrings("powershell", global.tools.?[0]);

    var empty = try parse(gpa, "{\"defaultTools\":[]}");
    defer empty.deinit(gpa);
    try mergeInto(gpa, &global, empty);
    try std.testing.expectEqual(@as(usize, 0), global.tools.?.len);
}

test "parse accepts upstream defaultModel defaultProvider thinkingLevel keys" {
    const gpa = std.testing.allocator;
    var s = try parse(gpa,
        \\{"defaultModel":"claude-sonnet","defaultProvider":"anthropic","defaultThinkingLevel":"high","compaction":{"reserveTokens":12000,"keepRecentTokens":24000},"branchSummary":{"reserveTokens":9000,"skipPrompt":true}}
    );
    defer s.deinit(gpa);
    try std.testing.expectEqualStrings("claude-sonnet", s.model.?);
    try std.testing.expectEqualStrings("anthropic", s.provider.?);
    try std.testing.expectEqualStrings("high", s.thinking_level.?);
    try std.testing.expectEqual(@as(?u64, 12_000), s.compaction_reserve_tokens);
    try std.testing.expectEqual(@as(?u64, 24_000), s.compaction_keep_recent_tokens);
    try std.testing.expectEqual(@as(?u64, 9_000), s.branch_summary_reserve_tokens);
    try std.testing.expectEqual(@as(?bool, true), s.branch_summary_skip_prompt);
}

test "model selector default persistence updates provider and model atomically" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buf[0..try tmp.dir.realPath(io, &root_buf)];
    try tmp.dir.writeFile(io, .{ .sub_path = "settings.json", .data = "\xEF\xBB\xBF{\"theme\":\"dark\",\"model\":\"old\",\"provider\":\"old-provider\",\"enabledModels\":[\"openai/gpt-old\"]}" });
    try setDefaultModel(gpa, io, root, "anthropic", "claude-opus-4-8");
    const settings_path = try std.fs.path.join(gpa, &.{ root, "settings.json" });
    defer gpa.free(settings_path);
    var loaded = try loadFile(gpa, io, settings_path);
    defer loaded.deinit(gpa);
    try std.testing.expectEqualStrings("anthropic", loaded.provider.?);
    try std.testing.expectEqualStrings("claude-opus-4-8", loaded.model.?);
    try std.testing.expectEqualStrings("dark", loaded.theme.?);
    try std.testing.expectEqual(@as(usize, 2), loaded.enabled_models.?.len);
    try std.testing.expectEqualStrings("anthropic/claude-opus-4-8", loaded.enabled_models.?[1]);
}

test "settings JSON accepts a UTF-8 BOM" {
    var settings = try parse(std.testing.allocator, "\xEF\xBB\xBF{\"defaultModel\":\"bom-model\"}");
    defer settings.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("bom-model", settings.model.?);
}

test "terminal capability settings map explicit values and preserve auto" {
    var explicit = try parse(std.testing.allocator, "{\"terminal\":{\"hyperlinks\":false,\"images\":\"kitty\",\"trueColor\":true}}");
    defer explicit.deinit(std.testing.allocator);
    try std.testing.expectEqual(false, explicit.terminal_hyperlinks.?);
    try std.testing.expect(explicit.terminal_image_protocol.? == .kitty);
    try std.testing.expectEqual(true, explicit.terminal_true_color.?);

    var automatic = try parse(std.testing.allocator, "{\"terminal\":{\"hyperlinks\":\"auto\",\"images\":\"auto\",\"trueColor\":\"auto\"}}");
    defer automatic.deinit(std.testing.allocator);
    try std.testing.expect(automatic.terminal_hyperlinks == null);
    try std.testing.expect(automatic.terminal_image_protocol == null);
    try std.testing.expect(automatic.terminal_true_color == null);
}

test "branch summary settings deep merge independently" {
    const gpa = std.testing.allocator;
    var base = try parse(gpa, "{\"branchSummary\":{\"reserveTokens\":12345,\"skipPrompt\":false}}");
    defer base.deinit(gpa);
    var project = try parse(gpa, "{\"branchSummary\":{\"skipPrompt\":true}}");
    defer project.deinit(gpa);
    try mergeInto(gpa, &base, project);
    try std.testing.expectEqual(@as(?u64, 12_345), base.branch_summary_reserve_tokens);
    try std.testing.expectEqual(@as(?bool, true), base.branch_summary_skip_prompt);

    const formatted = try formatSettings(gpa, base);
    defer gpa.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "branch_summary_reserve_tokens=12345") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "branch_summary_skip_prompt=true") != null);
}

test "settings parses and merges Codex transport" {
    const gpa = std.testing.allocator;
    var base = try parse(gpa, "{\"transport\":\"websocket-cached\"}");
    defer base.deinit(gpa);
    try std.testing.expectEqual(codex_ws.Transport.websocket_cached, base.transport.?);
    var override = try parse(gpa, "{\"transport\":\"sse\"}");
    defer override.deinit(gpa);
    try mergeInto(gpa, &base, override);
    try std.testing.expectEqual(codex_ws.Transport.sse, base.transport.?);
}

test "settings parses Codex HTTP idle timeout and disabled alias" {
    const gpa = std.testing.allocator;
    var timed = try parse(gpa, "{\"httpIdleTimeoutMs\":1234}");
    defer timed.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 1234), timed.http_idle_timeout_ms);

    var disabled = try parse(gpa, "{\"httpIdleTimeoutMs\":\"disabled\"}");
    defer disabled.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 0), disabled.http_idle_timeout_ms);
}

test "settings merge preserves inherited HTTP idle timeout unless overridden" {
    const gpa = std.testing.allocator;
    var base = try parse(gpa, "{\"httpIdleTimeoutMs\":2222}");
    defer base.deinit(gpa);
    var empty = try parse(gpa, "{}");
    defer empty.deinit(gpa);
    try mergeInto(gpa, &base, empty);
    try std.testing.expectEqual(@as(?u64, 2222), base.http_idle_timeout_ms);

    var override = try parse(gpa, "{\"httpIdleTimeoutMs\":0}");
    defer override.deinit(gpa);
    try mergeInto(gpa, &base, override);
    try std.testing.expectEqual(@as(?u64, 0), base.http_idle_timeout_ms);
}

test "settings parses Codex websocket connect timeout and disabled alias" {
    const gpa = std.testing.allocator;
    var timed = try parse(gpa, "{\"websocketConnectTimeoutMs\":4321}");
    defer timed.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 4321), timed.websocket_connect_timeout_ms);

    var disabled = try parse(gpa, "{\"websocket_connect_timeout_ms\":\"disabled\"}");
    defer disabled.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 0), disabled.websocket_connect_timeout_ms);
}

test "settings parses and merges active theme" {
    const gpa = std.testing.allocator;
    var base = try parse(gpa, "{\"theme\":\"dark\"}");
    defer base.deinit(gpa);
    try std.testing.expectEqualStrings("dark", base.theme.?);
    var override = try parse(gpa, "{\"theme\":\"custom\"}");
    defer override.deinit(gpa);
    try mergeInto(gpa, &base, override);
    try std.testing.expectEqualStrings("custom", base.theme.?);
}

test "settings parses global HTTP proxy and keeps it global-only" {
    const gpa = std.testing.allocator;
    var parsed = try parse(gpa, "{\"httpProxy\":\"  http://127.0.0.1:7890  \"}");
    defer parsed.deinit(gpa);
    try std.testing.expectEqualStrings("http://127.0.0.1:7890", parsed.http_proxy.?);

    var base = try parse(gpa, "{\"httpProxy\":\"http://global:8080\"}");
    defer base.deinit(gpa);
    var project = try parse(gpa, "{\"httpProxy\":\"http://project:9090\"}");
    defer project.deinit(gpa);
    try mergeIntoScoped(gpa, &base, project, false);
    try std.testing.expectEqualStrings("http://global:8080", base.http_proxy.?);
}

test "settings parse merge and format argv-style npm command" {
    const gpa = std.testing.allocator;
    var base = try parse(gpa, "{\"npmCommand\":[\"npm\"]}");
    defer base.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), base.npm_command.?.len);
    try std.testing.expectEqualStrings("npm", base.npm_command.?[0]);

    var project = try parse(gpa, "{\"npm_command\":[\"mise\",\"exec\",\"node@22\",\"--\",\"pnpm\"]}");
    defer project.deinit(gpa);
    try mergeIntoScoped(gpa, &base, project, false);
    try std.testing.expectEqual(@as(usize, 5), base.npm_command.?.len);
    try std.testing.expectEqualStrings("pnpm", base.npm_command.?[4]);

    const text = try formatSettings(gpa, base);
    defer gpa.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "npm_command=mise exec node@22 -- pnpm\n") != null);
}

test "settings reject malformed npm command without poisoning defaults" {
    const gpa = std.testing.allocator;
    inline for (.{
        "{\"npmCommand\":[]}",
        "{\"npmCommand\":[\"\"]}",
        "{\"npmCommand\":[\"npm\",42]}",
        "{\"npmCommand\":\"npm\"}",
    }) |raw| {
        var parsed = try parse(gpa, raw);
        defer parsed.deinit(gpa);
        try std.testing.expect(parsed.npm_command == null);
    }
}

test "setCompactionEnabled atomically preserves token budgets and unrelated settings" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = "{\"theme\":\"night\",\"autoCompactionEnabled\":true,\"compaction\":{\"reserveTokens\":12000,\"keepRecentTokens\":24000}}\n",
    });

    try setCompactionEnabled(gpa, io, agent_dir, false);

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    defer gpa.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("night", parsed.value.object.get("theme").?.string);
    try std.testing.expect(parsed.value.object.get("autoCompactionEnabled") == null);
    const compaction = parsed.value.object.get("compaction").?;
    try std.testing.expect(!compaction.object.get("enabled").?.bool);
    try std.testing.expectEqual(@as(i64, 12000), compaction.object.get("reserveTokens").?.integer);
    try std.testing.expectEqual(@as(i64, 24000), compaction.object.get("keepRecentTokens").?.integer);

    var loaded = try loadFile(gpa, io, path);
    defer loaded.deinit(gpa);
    try std.testing.expectEqual(@as(?bool, false), loaded.compaction_enabled);
    try std.testing.expectEqual(@as(?u64, 12000), loaded.compaction_reserve_tokens);
    try std.testing.expectEqual(@as(?u64, 24000), loaded.compaction_keep_recent_tokens);
}

test "setCompactionEnabled rejects malformed compaction without replacing the file" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const path = try std.fs.path.join(gpa, &.{ root, "settings.json" });
    defer gpa.free(path);
    const original = "{\"theme\":\"keep\",\"compaction\":false}\n";
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = original });

    try std.testing.expectError(error.InvalidCompactionSettings, setCompactionEnabled(gpa, io, root, true));
    const after = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    defer gpa.free(after);
    try std.testing.expectEqualStrings(original, after);
}

test "setRetryEnabled atomically preserves nested retry and unrelated settings" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data =
        \\{
        \\  "theme": "night",
        \\  "autoRetryEnabled": true,
        \\  "retry": {
        \\    "maxRetries": 7,
        \\    "baseDelayMs": 99,
        \\    "provider": {"maxRetries": 4}
        \\  }
        \\}
        ,
    });

    try setRetryEnabled(gpa, io, agent_dir, false);

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    defer gpa.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("night", parsed.value.object.get("theme").?.string);
    try std.testing.expect(parsed.value.object.get("autoRetryEnabled") == null);
    const retry = parsed.value.object.get("retry").?;
    try std.testing.expect(!retry.object.get("enabled").?.bool);
    try std.testing.expectEqual(@as(i64, 7), retry.object.get("maxRetries").?.integer);
    try std.testing.expectEqual(@as(i64, 99), retry.object.get("baseDelayMs").?.integer);
    try std.testing.expectEqual(@as(i64, 4), retry.object.get("provider").?.object.get("maxRetries").?.integer);

    var loaded = try loadFile(gpa, io, path);
    defer loaded.deinit(gpa);
    try std.testing.expectEqual(@as(?bool, false), loaded.retry_enabled);
    try std.testing.expectEqual(@as(?usize, 7), loaded.retry_max_retries);
    try std.testing.expectEqual(@as(?u64, 99), loaded.retry_base_delay_ms);
}

test "setRetryEnabled rejects malformed retry without replacing the file" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const path = try std.fs.path.join(gpa, &.{ root, "settings.json" });
    defer gpa.free(path);
    const original = "{\"theme\":\"keep\",\"retry\":false}\n";
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = original });

    try std.testing.expectError(error.InvalidRetrySettings, setRetryEnabled(gpa, io, root, true));
    const after = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    defer gpa.free(after);
    try std.testing.expectEqualStrings(original, after);
}

test "lifecycle settings parse format and durable acknowledgement preserve unrelated fields" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var parsed = try parse(gpa,
        \\{"lastChangelogVersion":"0.84.0","collapseChangelog":true,"enableInstallTelemetry":false,"theme":"night"}
    );
    defer parsed.deinit(gpa);
    try std.testing.expectEqualStrings("0.84.0", parsed.last_changelog_version.?);
    try std.testing.expectEqual(@as(?bool, true), parsed.collapse_changelog);
    try std.testing.expectEqual(@as(?bool, false), parsed.enable_install_telemetry);
    const formatted = try formatSettings(gpa, parsed);
    defer gpa.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "last_changelog_version=0.84.0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "collapse_changelog=true\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "enable_install_telemetry=false\n") != null);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const settings_path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(settings_path);
    {
        const file = try std.Io.Dir.cwd().createFile(io, settings_path, .{ .truncate = true });
        defer file.close(io);
        try file.writePositionalAll(io, "{\"theme\":\"night\",\"enableInstallTelemetry\":false}\n", 0);
    }
    try setLastChangelogVersion(gpa, io, agent_dir, "0.84.1");
    var loaded = try loadFile(gpa, io, settings_path);
    defer loaded.deinit(gpa);
    try std.testing.expectEqualStrings("0.84.1", loaded.last_changelog_version.?);
    try std.testing.expectEqualStrings("night", loaded.theme.?);
    try std.testing.expectEqual(@as(?bool, false), loaded.enable_install_telemetry);
}

test "settings parse merge and format delivery and interactive policy" {
    const gpa = std.testing.allocator;
    var global = try parse(gpa,
        \\{"steeringMode":"all","followUpMode":"one-at-a-time","quietStartup":true,"treeFilterMode":"no-tools"}
    );
    defer global.deinit(gpa);
    try std.testing.expectEqual(@as(?DeliveryMode, .all), global.steering_mode);
    try std.testing.expectEqual(@as(?DeliveryMode, .one_at_a_time), global.follow_up_mode);
    try std.testing.expectEqual(@as(?bool, true), global.quiet_startup);
    try std.testing.expectEqual(@as(?TreeFilterMode, .no_tools), global.tree_filter_mode);

    var project = try parse(gpa,
        \\{"follow_up_mode":"all","quiet_startup":false,"tree_filter_mode":"user_only"}
    );
    defer project.deinit(gpa);
    try mergeIntoScoped(gpa, &global, project, false);
    try std.testing.expectEqual(@as(?DeliveryMode, .all), global.steering_mode);
    try std.testing.expectEqual(@as(?DeliveryMode, .all), global.follow_up_mode);
    try std.testing.expectEqual(@as(?bool, false), global.quiet_startup);
    try std.testing.expectEqual(@as(?TreeFilterMode, .user_only), global.tree_filter_mode);

    const formatted = try formatSettings(gpa, global);
    defer gpa.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "steering_mode=all\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "follow_up_mode=all\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "quiet_startup=false\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "tree_filter_mode=user-only\n") != null);
}

test "extended interactive settings parse merge format and scoped persistence" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var global = try parse(gpa,
        \\{"maxTurns":32,"hideThinkingBlock":true,"showCacheMissNotices":true,"doubleEscapeAction":"fork","terminal":{"clearOnShrink":true,"showTerminalProgress":true},"images":{"autoResize":false},"editorPaddingX":2,"outputPad":0,"autocompleteMaxVisible":10,"showHardwareCursor":true,"markdown":{"mermaid":"final"},"warnings":{"anthropicExtraUsage":false},"tuiMode":"fullscreen","fullscreenExitOutput":"resume-hint","fullscreenScrollbar":"always"}
    );
    defer global.deinit(gpa);
    try std.testing.expect(global.max_turns_explicit);
    try std.testing.expectEqual(@as(usize, 32), global.max_turns);
    try std.testing.expectEqual(@as(?bool, true), global.hide_thinking_block);
    try std.testing.expectEqual(DoubleEscapeAction.fork, global.double_escape_action.?);
    try std.testing.expectEqual(@as(?bool, true), global.show_terminal_progress);
    try std.testing.expectEqual(@as(?bool, false), global.auto_resize_images);
    try std.testing.expectEqual(@as(?u64, 2), global.editor_padding_x);
    try std.testing.expectEqual(@as(?u64, 0), global.output_pad);
    try std.testing.expectEqual(@as(?u64, 10), global.autocomplete_max_visible);
    try std.testing.expectEqual(MermaidMode.final, global.mermaid_mode.?);
    try std.testing.expectEqual(TuiMode.fullscreen, global.tui_mode.?);
    try std.testing.expectEqual(FullscreenExitOutput.resume_hint, global.fullscreen_exit_output.?);
    try std.testing.expectEqual(FullscreenScrollbar.always, global.fullscreen_scrollbar.?);

    var project = try parse(gpa,
        \\{"maxTurns":16,"terminal":{"showTerminalProgress":false},"editorPaddingX":3,"tuiMode":"regular"}
    );
    defer project.deinit(gpa);
    var merged: Settings = .{};
    defer merged.deinit(gpa);
    try mergeIntoScoped(gpa, &merged, global, true);
    try mergeIntoScoped(gpa, &merged, project, false);
    try std.testing.expectEqual(@as(usize, 16), merged.max_turns);
    try std.testing.expectEqual(@as(?bool, false), merged.show_terminal_progress);
    try std.testing.expectEqual(@as(?u64, 3), merged.editor_padding_x);
    try std.testing.expectEqual(TuiMode.regular, merged.tui_mode.?);

    const formatted = try formatSettings(gpa, merged);
    defer gpa.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "hide_thinking_block=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "fullscreen_scrollbar=always") != null);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const cwd = try std.fs.path.join(gpa, &.{ root, "project" });
    defer gpa.free(cwd);
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    try std.Io.Dir.cwd().createDirPath(io, cwd);

    try setEditableScoped(gpa, io, agent_dir, cwd, true, .global, .max_turns, .{ .integer = 32 });
    try setEditableScoped(gpa, io, agent_dir, cwd, true, .project, .max_turns, .{ .integer = 16 });
    try setEditableScoped(gpa, io, agent_dir, cwd, true, .project, .show_terminal_progress, .{ .boolean = true });
    var effective = try loadMergeTrusted(gpa, io, agent_dir, cwd, true);
    defer effective.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 16), effective.max_turns);
    try std.testing.expectEqual(@as(?bool, true), effective.show_terminal_progress);

    try clearEditableScoped(gpa, io, agent_dir, cwd, true, .project, .max_turns);
    var inherited = try loadMergeTrusted(gpa, io, agent_dir, cwd, true);
    defer inherited.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 32), inherited.max_turns);
    try std.testing.expectError(error.ProjectNotTrusted, setEditableScoped(gpa, io, agent_dir, cwd, false, .project, .output_pad, .{ .integer = 0 }));
    try std.testing.expectError(error.GlobalOnlySetting, setEditableScoped(gpa, io, agent_dir, cwd, true, .project, .enable_install_telemetry, .{ .boolean = false }));
}

//! pi-zig CLI: full coding agent (print / interactive / json / rpc).
const std = @import("std");
const build_options = @import("builtin");
const Io = std.Io;
const pi_zig = @import("pi_zig");
const pi_features = @import("pi_features");
const sqlite_persistence = if (pi_features.sqlite_enabled) @import("sqlite_persistence") else struct {};

const config = pi_zig.config;
const ai = pi_zig.ai;
const agent = pi_zig.agent;
const tui = pi_zig.tui;
const coding = pi_zig.coding_agent;
const auth = pi_zig.auth;
const extensions = pi_zig.extensions;

const ReplCompletionContext = struct {
    io: Io,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    live: *coding.live_state.LiveState,
    prompt_templates: *const []coding.prompts.PromptTemplate,
    extension_commands: *const std.ArrayList([]const u8),
    session: *agent.session.Session,
};

fn replComplete(raw_context: *anyopaque, gpa: std.mem.Allocator, line: []const u8, cursor: usize) !?tui.line_editor.Completion {
    const context: *ReplCompletionContext = @ptrCast(@alignCast(raw_context));
    const catalog = if (context.live.model_catalog.len > 0) context.live.model_catalog else &ai.providers.known_models;
    const result = (try coding.repl_completion.complete(
        gpa,
        context.io,
        context.environ,
        context.cwd,
        line,
        cursor,
        catalog,
        context.prompt_templates.*,
        context.extension_commands.items,
        context.session,
        context.live.agent_cfg.enable_skill_commands,
    )) orelse return null;
    // Transfer ownership to the terminal editor's generic completion result.
    return .{ .text = result.text, .cursor = result.cursor };
}

const TreeSummaryPromptContext = struct {
    io: Io,
    reader: *Io.File.Reader,
    editor: *tui.editor.Editor,
    bindings: *const tui.keybindings.Manager,
    use_terminal_editor: bool,

    fn readChoice(self: *@This(), gpa: std.mem.Allocator, prompt_text: []const u8) ![]u8 {
        if (self.use_terminal_editor) {
            return tui.line_editor.readLine(gpa, self.io, self.reader, self.editor, self.bindings, prompt_text);
        }
        try tui.render.writeAll(self.io, prompt_text);
        return readLine(self.reader, gpa);
    }

    fn prompt(raw: ?*anyopaque, gpa: std.mem.Allocator) anyerror!coding.slash.TreeSummaryChoice {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try tui.render.printLine(self.io, "Summarize branch?");
        try tui.render.printLine(self.io, "  [n] No summary  [s] Summarize  [c] Custom prompt  [q] Cancel");
        while (true) {
            const choice_line = try self.readChoice(gpa, "Choice [n]: ");
            defer gpa.free(choice_line);
            const choice = std.mem.trim(u8, choice_line, " \\t\\r\\n");
            if (choice.len == 0 or std.ascii.eqlIgnoreCase(choice, "n") or std.ascii.eqlIgnoreCase(choice, "no") or std.mem.eql(u8, choice, "1")) {
                return .{};
            }
            if (std.ascii.eqlIgnoreCase(choice, "s") or std.ascii.eqlIgnoreCase(choice, "summary") or std.ascii.eqlIgnoreCase(choice, "yes") or std.mem.eql(u8, choice, "2")) {
                return .{ .summarize = true };
            }
            if (std.ascii.eqlIgnoreCase(choice, "q") or std.ascii.eqlIgnoreCase(choice, "cancel")) {
                return .{ .cancelled = true };
            }
            if (std.ascii.eqlIgnoreCase(choice, "c") or std.ascii.eqlIgnoreCase(choice, "custom") or std.mem.eql(u8, choice, "3")) {
                const instructions_line = try self.readChoice(gpa, "Custom summarization instructions: ");
                const instructions = std.mem.trim(u8, instructions_line, " \\t\\r\\n");
                if (instructions.len == 0) {
                    gpa.free(instructions_line);
                    try tui.render.printLine(self.io, "Custom instructions cannot be empty.");
                    continue;
                }
                const owned = try gpa.dupe(u8, instructions);
                gpa.free(instructions_line);
                return .{ .summarize = true, .custom_instructions = owned };
            }
            try tui.render.printLine(self.io, "Choose n, s, c, or q.");
        }
    }
};

fn queueModeFromSettings(mode: ?coding.settings.DeliveryMode) agent.loop.QueueMode {
    return switch (mode orelse .one_at_a_time) {
        .all => .all,
        .one_at_a_time => .one_at_a_time,
    };
}

fn treeFilterFromSettings(mode: ?coding.settings.TreeFilterMode) coding.tree_tui.FilterMode {
    return switch (mode orelse .default) {
        .default => .default,
        .no_tools => .no_tools,
        .user_only => .user_only,
        .labeled_only => .labeled_only,
        .all => .all,
    };
}

const TreeTargetPromptContext = struct {
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: *Io.File.Reader,
    already_fullscreen: bool,
    filter_mode: *coding.tree_tui.FilterMode,

    fn prompt(raw: ?*anyopaque, gpa: std.mem.Allocator, sess: *agent.Session) anyerror!coding.slash.TreeTargetChoice {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const selection = try coding.tree_tui.runWithFilter(gpa, self.io, self.environ, self.reader, sess, self.filter_mode.*, self.already_fullscreen);
        return .{ .target_id = selection.target_id, .cancelled = selection.cancelled };
    }
};

const ModelTargetPromptContext = struct {
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: *Io.File.Reader,
    already_fullscreen: bool,
    live: *coding.live_state.LiveState,
    provider_models: *extensions.provider_models.Runtime,
    abort_flag: *bool,

    fn prompt(raw: ?*anyopaque, gpa: std.mem.Allocator, initial_search: ?[]const u8) anyerror!coding.slash.ModelTargetChoice {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var refresh_result = try self.provider_models.refresh(.{
            .allow_network = true,
            .abort_flag = self.abort_flag,
        });
        defer refresh_result.deinit();
        for (refresh_result.errors) |entry| {
            var warning_buffer: [768]u8 = undefined;
            const warning = std.fmt.bufPrint(&warning_buffer, "warning: provider {s} model refresh failed: {s}", .{ entry.provider_id, entry.message }) catch continue;
            tui.render.printLine(self.io, warning) catch {};
        }
        const catalog = if (self.live.model_catalog.len > 0) self.live.model_catalog else &ai.providers.known_models;
        const current_provider = if (self.live.provider_name) |provider_ptr|
            provider_ptr.* orelse if (self.live.client_pool) |pool| pool.active_provider_id else ""
        else if (self.live.client_pool) |pool|
            pool.active_provider_id
        else
            "";
        const current_model = self.live.model_display.* orelse if (self.live.active_model) |model_ptr| model_ptr.* else "";
        const selection = try coding.model_tui.run(
            gpa,
            self.io,
            self.environ,
            self.reader,
            catalog,
            self.live.model_scope,
            self.live.configured_providers,
            current_provider,
            current_model,
            initial_search,
            self.already_fullscreen,
        );
        return .{ .reference = selection.reference, .cancelled = selection.cancelled };
    }
};

const SettingsTargetPromptContext = struct {
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: *Io.File.Reader,
    already_fullscreen: bool,
    agent_dir: []const u8,
    cwd: []const u8,
    trust_project: bool,
    theme_registry: *pi_zig.themes.Registry,

    fn prompt(raw: ?*anyopaque, gpa: std.mem.Allocator) anyerror!coding.slash.SettingsTargetChoice {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const names = try gpa.alloc([]const u8, self.theme_registry.themes.items.len);
        defer gpa.free(names);
        for (self.theme_registry.themes.items, 0..) |theme, index| names[index] = theme.name;
        const result = try coding.settings_tui.run(
            gpa,
            self.io,
            self.environ,
            self.reader,
            self.agent_dir,
            self.cwd,
            self.trust_project,
            names,
            self.already_fullscreen,
        );
        return .{ .changed = result.changed, .cancelled = result.cancelled };
    }
};

const AuthTargetPromptContext = struct {
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: *Io.File.Reader,
    already_fullscreen: bool,
    agent_dir: []const u8,
    live: *coding.live_state.LiveState,
    extension_oauth: *extensions.provider_oauth.Runtime,

    fn prompt(
        raw: ?*anyopaque,
        gpa: std.mem.Allocator,
        mode: coding.slash.AuthPromptMode,
        initial_search: ?[]const u8,
    ) anyerror!coding.slash.AuthTargetChoice {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const catalog = if (self.live.model_catalog.len > 0) self.live.model_catalog else &ai.providers.known_models;
        const oauth_provider_ids = try self.extension_oauth.loginProviderNames(gpa);
        defer if (oauth_provider_ids.len > 0) gpa.free(oauth_provider_ids);
        var selection = try coding.auth_tui.runWithOAuthProviders(
            gpa,
            self.io,
            self.environ,
            self.reader,
            self.agent_dir,
            catalog,
            oauth_provider_ids,
            switch (mode) {
                .login => .login,
                .logout => .logout,
            },
            initial_search,
            self.already_fullscreen,
        );
        defer selection.deinit(gpa);
        const provider_id = selection.provider_id;
        const api_key = selection.api_key;
        selection.provider_id = null;
        selection.api_key = null;
        return .{
            .provider_id = provider_id,
            .method = if (selection.method) |method| switch (method) {
                .api_key => .api_key,
                .browser => .browser,
                .device_code => .device_code,
            } else null,
            .api_key = api_key,
            .cancelled = selection.cancelled,
        };
    }
};

const SessionTargetPromptContext = struct {
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: *Io.File.Reader,
    already_fullscreen: bool,
    session_dir: []const u8,
    all_sessions_root: []const u8,
    current_session_path: *?[]const u8,
    required_cwd: []const u8,

    fn prompt(raw: ?*anyopaque, gpa: std.mem.Allocator, initial_search: ?[]const u8) anyerror!coding.slash.SessionTargetChoice {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const selection = try coding.session_tui.run(gpa, self.io, self.environ, self.reader, .{
            .session_dir = self.session_dir,
            .all_sessions_root = self.all_sessions_root,
            .current_session_path = self.current_session_path.*,
            .required_cwd = self.required_cwd,
            .initial_query = initial_search,
            .already_fullscreen = self.already_fullscreen,
        });
        return .{ .path = selection.path, .cancelled = selection.cancelled };
    }
};

const SlashInvocation = struct {
    name: []const u8,
    arguments: []const u8,
};

const ServeOptions = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 3141,
    token: []const u8 = "",
    session_dir: ?[]const u8 = null,
    sqlite_path: ?[]const u8 = null,
    sqlite_import_dir: ?[]const u8 = null,
    sqlite_lease_ttl_ms: i64 = 60_000,
    max_frame_length: usize = pi_zig.protocol.framing.DEFAULT_MAX_FRAME_LENGTH,
    handshake_timeout_ms: u64 = 5000,
    unix_socket: ?[]const u8 = null,
    mock_script: ?[]const u8 = null,
    trust_project: bool = false,
    show_help: bool = false,
};

const ServeOptionError = error{
    MissingValue,
    InvalidPort,
    InvalidFrameLength,
    InvalidHandshakeTimeout,
    InvalidLeaseTtl,
    UnknownOption,
    ConflictingPersistence,
    ImportRequiresSqlite,
};

fn parseServeOptions(args: []const []const u8) ServeOptionError!ServeOptions {
    var result = ServeOptions{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.show_help = true;
        } else if (try serveOptionValue(args, &i, arg, "--port")) |value| {
            result.port = std.fmt.parseInt(u16, value, 10) catch return ServeOptionError.InvalidPort;
            if (result.port == 0) return ServeOptionError.InvalidPort;
        } else if (try serveOptionValue(args, &i, arg, "--host")) |value| {
            result.host = value;
        } else if (try serveOptionValue(args, &i, arg, "--token")) |value| {
            result.token = value;
        } else if (try serveOptionValue(args, &i, arg, "--session-dir")) |value| {
            result.session_dir = value;
        } else if (try serveOptionValue(args, &i, arg, "--sqlite")) |value| {
            result.sqlite_path = value;
        } else if (try serveOptionValue(args, &i, arg, "--sqlite-import-dir")) |value| {
            result.sqlite_import_dir = value;
        } else if (try serveOptionValue(args, &i, arg, "--sqlite-lease-ttl-ms")) |value| {
            result.sqlite_lease_ttl_ms = std.fmt.parseInt(i64, value, 10) catch return ServeOptionError.InvalidLeaseTtl;
            if (result.sqlite_lease_ttl_ms <= 0) return ServeOptionError.InvalidLeaseTtl;
        } else if (try serveOptionValue(args, &i, arg, "--max-frame-length")) |value| {
            result.max_frame_length = std.fmt.parseInt(usize, value, 10) catch return ServeOptionError.InvalidFrameLength;
            if (result.max_frame_length == 0) return ServeOptionError.InvalidFrameLength;
        } else if (try serveOptionValue(args, &i, arg, "--handshake-timeout-ms")) |value| {
            result.handshake_timeout_ms = std.fmt.parseInt(u64, value, 10) catch return ServeOptionError.InvalidHandshakeTimeout;
            if (result.handshake_timeout_ms == 0) return ServeOptionError.InvalidHandshakeTimeout;
        } else if (try serveOptionValue(args, &i, arg, "--socket")) |value| {
            result.unix_socket = value;
        } else if (try serveOptionValue(args, &i, arg, "--mock-script")) |value| {
            result.mock_script = value;
        } else if (std.mem.eql(u8, arg, "--approve") or std.mem.eql(u8, arg, "--project-resources")) {
            result.trust_project = true;
        } else if (std.mem.eql(u8, arg, "--no-approve") or std.mem.eql(u8, arg, "--no-project-resources")) {
            result.trust_project = false;
        } else {
            return ServeOptionError.UnknownOption;
        }
    }
    if (result.sqlite_path != null and result.session_dir != null) return ServeOptionError.ConflictingPersistence;
    if (result.sqlite_import_dir != null and result.sqlite_path == null) return ServeOptionError.ImportRequiresSqlite;
    return result;
}

fn serveOptionValue(args: []const []const u8, index: *usize, arg: []const u8, name: []const u8) ServeOptionError!?[]const u8 {
    if (std.mem.eql(u8, arg, name)) {
        if (index.* + 1 >= args.len or args[index.* + 1].len == 0) return ServeOptionError.MissingValue;
        index.* += 1;
        return args[index.*];
    }
    if (arg.len > name.len and std.mem.startsWith(u8, arg, name) and arg[name.len] == '=') {
        const value = arg[name.len + 1 ..];
        if (value.len == 0) return ServeOptionError.MissingValue;
        return value;
    }
    return null;
}

const serve_usage =
    \\usage: pi serve [--host HOST] [--port N] [--socket PATH] [--token TOKEN]
    \\                [--session-dir PATH]
    \\       pi-sqlite-live serve --sqlite PATH [--sqlite-import-dir PATH]
    \\                [--sqlite-lease-ttl-ms N] [other serve options]
    \\                [--max-frame-length N] [--handshake-timeout-ms N]
    \\                [--mock-script PATH] [--approve|--no-approve]
;

fn hasSqliteSessionFlag(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--sqlite") or std.mem.startsWith(u8, arg, "--sqlite=")) return true;
    }
    return false;
}

fn normalizeSqliteSessionArgs(arena: std.mem.Allocator, args: []const []const u8) ![]const []const u8 {
    const normalized = try arena.alloc([]const u8, args.len);
    for (args, 0..) |arg, index| {
        normalized[index] = if (std.mem.eql(u8, arg, "--sqlite"))
            "--db"
        else if (std.mem.startsWith(u8, arg, "--sqlite="))
            try std.fmt.allocPrint(arena, "--db={s}", .{arg["--sqlite=".len..]})
        else
            arg;
    }
    return normalized;
}

fn parseSlashInvocation(line: []const u8) ?SlashInvocation {
    if (line.len < 2 or line[0] != '/') return null;
    const rest = line[1..];
    const end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    if (end == 0) return null;
    var arg_start = end;
    while (arg_start < rest.len and std.ascii.isWhitespace(rest[arg_start])) : (arg_start += 1) {}
    return .{ .name = rest[0..end], .arguments = rest[arg_start..] };
}

fn executeExtensionInvocation(host: *extensions.Host, line: []const u8) !?extensions.host.CommandOutput {
    const invocation = parseSlashInvocation(line) orelse return null;
    if (!host.hasCommand(invocation.name)) return null;
    return try host.executeCommand(invocation.name, invocation.arguments);
}

const ExtensionActionPresence = struct {
    send_message: bool = false,
    send_user_message: bool = false,
    session_name: bool = false,
    entry: bool = false,
    label: bool = false,
    model: bool = false,
    thinking: bool = false,
    tools: bool = false,
    abort_or_shutdown: bool = false,
    reload: bool = false,
};

fn extensionActionPresence(batch: extensions.actions.Batch) ExtensionActionPresence {
    var result = ExtensionActionPresence{};
    for (batch.items) |record| {
        if (std.mem.eql(u8, record.kind, "reload")) {
            result.reload = true;
            break;
        }
        result.send_message = result.send_message or std.mem.eql(u8, record.kind, "send_message");
        result.send_user_message = result.send_user_message or std.mem.eql(u8, record.kind, "send_user_message");
        result.session_name = result.session_name or std.mem.eql(u8, record.kind, "set_session_name");
        result.entry = result.entry or std.mem.eql(u8, record.kind, "append_entry");
        result.label = result.label or std.mem.eql(u8, record.kind, "set_label");
        result.model = result.model or std.mem.eql(u8, record.kind, "set_model");
        result.thinking = result.thinking or std.mem.eql(u8, record.kind, "set_thinking_level");
        result.tools = result.tools or std.mem.eql(u8, record.kind, "set_active_tools");
        result.abort_or_shutdown = result.abort_or_shutdown or
            std.mem.eql(u8, record.kind, "abort") or
            std.mem.eql(u8, record.kind, "shutdown");
    }
    return result;
}

fn applyExtensionSessionActions(sess: *agent.session.Session, output: *const extensions.host.CommandOutput) !void {
    const presence = extensionActionPresence(output.actions);
    if (presence.reload) return;
    if (!presence.session_name) {
        if (output.session_name) |name| try sess.setName(name);
    }
    if (!presence.entry) {
        for (output.entries) |entry| _ = try sess.appendCustomEntry(entry.custom_type, entry.data_json);
    }
    if (!presence.label) {
        for (output.labels) |label| {
            _ = sess.appendLabelChange(label.entry_id, label.label) catch |err| switch (err) {
                // Extension state may reference an entry from another branch or a
                // recently replaced session. Match the upstream runner's isolation
                // guarantee by ignoring only that stale action.
                error.UnknownEntry => continue,
                else => return err,
            };
        }
    }
}

const ExtensionCommandPreview = struct {
    prompt: ?[]u8 = null,
    stop: bool = false,

    fn deinit(self: *ExtensionCommandPreview, gpa: std.mem.Allocator) void {
        if (self.prompt) |value| gpa.free(value);
        self.* = undefined;
    }
};

/// Inspect command actions before the live model/client graph exists. This does
/// not mutate native state; it only chooses the same immediate command prompt
/// that the ordered runtime applier will later enqueue and observes stop actions.
fn previewExtensionCommandActions(gpa: std.mem.Allocator, batch: extensions.actions.Batch) !ExtensionCommandPreview {
    var first_steering: ?[]u8 = null;
    errdefer if (first_steering) |value| gpa.free(value);
    var first_followup: ?[]u8 = null;
    errdefer if (first_followup) |value| gpa.free(value);
    var stop = false;

    for (batch.items) |record| {
        if (std.mem.eql(u8, record.kind, "reload")) break;
        if (std.mem.eql(u8, record.kind, "abort") or std.mem.eql(u8, record.kind, "shutdown")) {
            stop = true;
            continue;
        }
        if (!(std.mem.eql(u8, record.kind, "send_user_message") or std.mem.eql(u8, record.kind, "send_message"))) continue;

        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, record.json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidExtensionAction;
        const object = parsed.value.object;
        var content_value: std.json.Value = undefined;
        var trigger_turn = std.mem.eql(u8, record.kind, "send_user_message");
        var delivery: ?[]const u8 = null;
        if (std.mem.eql(u8, record.kind, "send_user_message")) {
            content_value = object.get("content") orelse return error.InvalidExtensionAction;
        } else {
            const message = object.get("message") orelse return error.InvalidExtensionAction;
            if (message != .object) return error.InvalidExtensionAction;
            content_value = message.object.get("content") orelse std.json.Value{ .string = "" };
        }
        if (object.get("options")) |options| {
            if (options != .object) return error.InvalidExtensionAction;
            if (options.object.get("triggerTurn")) |value| {
                if (value != .bool) return error.InvalidExtensionAction;
                trigger_turn = trigger_turn or value.bool;
            }
            if (options.object.get("deliverAs")) |value| switch (value) {
                .null => {},
                .string => |text| delivery = text,
                else => return error.InvalidExtensionAction,
            };
        }
        if (!trigger_turn and delivery == null) continue;
        const content = try extensionActionContent(gpa, content_value);
        if (delivery) |mode| {
            if (std.ascii.eqlIgnoreCase(mode, "followUp") or std.ascii.eqlIgnoreCase(mode, "follow_up")) {
                if (first_followup == null) first_followup = content else gpa.free(content);
            } else if (std.ascii.eqlIgnoreCase(mode, "steer") or std.ascii.eqlIgnoreCase(mode, "nextTurn") or std.ascii.eqlIgnoreCase(mode, "next_turn")) {
                if (first_steering == null) first_steering = content else gpa.free(content);
            } else {
                gpa.free(content);
                return error.InvalidExtensionDeliveryMode;
            }
        } else if (first_steering == null) {
            first_steering = content;
        } else {
            gpa.free(content);
        }
    }

    if (first_steering) |prompt| {
        if (first_followup) |value| gpa.free(value);
        return .{ .prompt = prompt, .stop = stop };
    }
    return .{ .prompt = first_followup, .stop = stop };
}

fn freeOwnedToolNames(gpa: std.mem.Allocator, names: []const []const u8) void {
    for (names) |name| gpa.free(name);
    gpa.free(names);
}

fn cloneRequestedTools(gpa: std.mem.Allocator, tools: []const []u8) ![][]u8 {
    const owned = try gpa.alloc([]u8, tools.len);
    var initialized: usize = 0;
    errdefer {
        for (owned[0..initialized]) |value| gpa.free(value);
        gpa.free(owned);
    }
    for (tools, 0..) |tool, index| {
        owned[index] = try gpa.dupe(u8, tool);
        initialized += 1;
    }
    return owned;
}

const DeferredExtensionActions = struct {
    model: ?extensions.host.ModelAction = null,
    thinking_level: ?[]u8 = null,
    active_tools: ?[][]u8 = null,
    abort: bool = false,
    batches: std.ArrayList(extensions.actions.Batch) = .empty,
    consumed_action_prompts: std.ArrayList([]u8) = .empty,

    fn deinit(self: *DeferredExtensionActions, gpa: std.mem.Allocator) void {
        if (self.model) |*model| model.deinit(gpa);
        if (self.thinking_level) |value| gpa.free(value);
        if (self.active_tools) |tools| {
            for (tools) |tool| gpa.free(tool);
            gpa.free(tools);
        }
        for (self.batches.items) |*batch| batch.deinit(gpa);
        self.batches.deinit(gpa);
        for (self.consumed_action_prompts.items) |prompt| gpa.free(prompt);
        self.consumed_action_prompts.deinit(gpa);
        self.* = undefined;
    }

    /// Capture startup command effects until the live model/provider graph is
    /// available. Canonical action batches move into this owner; legacy mirrors
    /// are retained only when no equivalent action exists.
    fn capture(
        self: *DeferredExtensionActions,
        gpa: std.mem.Allocator,
        output: *extensions.host.CommandOutput,
        consumed_action_prompt: ?[]const u8,
    ) !void {
        const presence = extensionActionPresence(output.actions);
        if (!presence.reload and !presence.model) if (output.model) |model| {
            const replacement = try model.clone(gpa);
            if (self.model) |*old| old.deinit(gpa);
            self.model = replacement;
        };
        if (!presence.reload and !presence.thinking) if (output.thinking_level) |level| {
            const replacement = try gpa.dupe(u8, level);
            if (self.thinking_level) |old| gpa.free(old);
            self.thinking_level = replacement;
        };
        if (!presence.reload and !presence.tools) if (output.active_tools) |tools| {
            const replacement = try cloneRequestedTools(gpa, tools);
            if (self.active_tools) |old| {
                for (old) |tool| gpa.free(tool);
                gpa.free(old);
            }
            self.active_tools = replacement;
        };
        if (!presence.reload and !presence.abort_or_shutdown) self.abort = self.abort or output.abort;

        if (consumed_action_prompt) |prompt| {
            try self.consumed_action_prompts.append(gpa, try gpa.dupe(u8, prompt));
        }
        if (!output.actions.isEmpty()) {
            try self.batches.append(gpa, output.actions);
            output.actions = .{};
        }
    }
};

fn knownExtensionTool(host: *const extensions.Host, name: []const u8) bool {
    return agent.tools.isBuiltin(name) or host.hasTool(name);
}

fn buildActiveToolSelection(
    gpa: std.mem.Allocator,
    host: *const extensions.Host,
    requested: []const []const u8,
) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |name| gpa.free(name);
        names.deinit(gpa);
    }
    for (requested) |name| {
        if (!knownExtensionTool(host, name)) continue;
        var duplicate = false;
        for (names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) try names.append(gpa, try gpa.dupe(u8, name));
    }
    return try names.toOwnedSlice(gpa);
}

fn printExtensionActionWarning(io: Io, comptime action: []const u8, err: anyerror) void {
    var buffer: [256]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "warning: extension {s} action was ignored: {s}", .{ action, @errorName(err) }) catch return;
    tui.render.printLine(io, message) catch {};
}

fn applyExtensionRuntimeActions(
    gpa: std.mem.Allocator,
    sess: *agent.session.Session,
    model_action: ?*const extensions.host.ModelAction,
    thinking_level: ?[]const u8,
    requested_tools: ?[]const []const u8,
    live: *coding.live_state.LiveState,
    host: *extensions.Host,
    bridge: *extensions.integration.Bridge,
    active_filter: *agent.tools.ToolFilter,
    owned_active_tools: *?[]const []const u8,
    extension_schemas: *[]u8,
) !void {
    var model_changed = false;
    if (model_action) |action| {
        const current_provider = if (live.provider_name) |provider_ptr| provider_ptr.* else null;
        const reference = if (live.client_pool == null and action.provider != null and current_provider != null and
            std.ascii.eqlIgnoreCase(action.provider.?, current_provider.?))
            try gpa.dupe(u8, action.id)
        else
            try action.reference(gpa);
        defer gpa.free(reference);
        var model_applied = true;
        coding.live_state.applyModel(live, reference) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {
                model_applied = false;
                printExtensionActionWarning(live.io, "model", err);
            },
        };
        if (model_applied) {
            if (live.model_display.*) |model_id| {
                const provider = if (live.provider_name) |provider_ptr|
                    provider_ptr.* orelse action.provider orelse ""
                else
                    action.provider orelse "";
                if (provider.len > 0) {
                    _ = try sess.appendModelChange(provider, model_id);
                    model_changed = true;
                }
            }
        }
    }

    if (thinking_level) |raw_level| {
        const parsed = ai.thinking.ThinkingLevel.parse(raw_level) orelse {
            printExtensionActionWarning(live.io, "thinking-level", error.InvalidThinkingLevel);
            return;
        };
        const effective = if (coding.live_state.activeModelInfo(live)) |model|
            model.clampThinkingLevel(parsed)
        else
            parsed;
        const next = @tagName(effective);
        const changed = if (live.thinking) |current| !std.ascii.eqlIgnoreCase(current, next) else true;
        if (changed) {
            try coding.live_state.applyThinking(live, next);
            _ = try sess.appendThinkingLevelChange(next);
        }
    } else if (model_changed) {
        if (coding.live_state.activeModelInfo(live)) |model| {
            if (try coding.live_state.applyThinkingForModelSwitch(live, model, coding.live_state.scopedThinkingForModel(live, model))) {
                _ = try sess.appendThinkingLevelChange(live.thinking orelse "off");
            }
        }
    }

    if (requested_tools) |tools| {
        const next_names = try buildActiveToolSelection(gpa, host, tools);
        errdefer freeOwnedToolNames(gpa, next_names);
        const next_filter = agent.tools.ToolFilter{ .allow = next_names };
        const next_schemas = try bridge.toolSchemasJson(gpa, next_filter);
        errdefer gpa.free(next_schemas);

        const old_schemas = extension_schemas.*;
        const old_names = owned_active_tools.*;
        extension_schemas.* = next_schemas;
        owned_active_tools.* = next_names;
        active_filter.* = next_filter;
        live.agent_cfg.tool_filter = next_filter;
        live.agent_cfg.extra_tools_json = next_schemas;
        gpa.free(old_schemas);
        if (old_names) |names| freeOwnedToolNames(gpa, names);
    }
}

fn applyCommandRuntimeActions(
    gpa: std.mem.Allocator,
    sess: *agent.session.Session,
    output: *const extensions.host.CommandOutput,
    live: *coding.live_state.LiveState,
    host: *extensions.Host,
    bridge: *extensions.integration.Bridge,
    active_filter: *agent.tools.ToolFilter,
    owned_active_tools: *?[]const []const u8,
    extension_schemas: *[]u8,
) !void {
    const model_ptr: ?*const extensions.host.ModelAction = if (output.model) |*model| model else null;
    const tools: ?[]const []const u8 = if (output.active_tools) |values| values else null;
    try applyExtensionRuntimeActions(
        gpa,
        sess,
        model_ptr,
        output.thinking_level,
        tools,
        live,
        host,
        bridge,
        active_filter,
        owned_active_tools,
        extension_schemas,
    );
}

const ExtensionActionRuntime = struct {
    live: *coding.live_state.LiveState,
    host: *extensions.Host,
    bridge: *extensions.integration.Bridge,
    provider_registry: *extensions.provider_registry.Registry,
    provider_models: *extensions.provider_models.Runtime,
    active_filter: *agent.tools.ToolFilter,
    owned_active_tools: *?[]const []const u8,
    extension_schemas: *[]u8,
    mock_client: ?ai.ModelClient = null,
    render_output: bool = false,
    render_width: usize = 100,

    fn flush(
        raw: ?*anyopaque,
        gpa: std.mem.Allocator,
        sess: *agent.session.Session,
        run_config: *agent.AgentConfig,
        active_client: *ai.ModelClient,
        steering: *std.ArrayList([]u8),
        followups: *std.ArrayList([]u8),
        stop_requested: *bool,
    ) anyerror!void {
        const self: *ExtensionActionRuntime = @ptrCast(@alignCast(raw.?));
        const records = try self.bridge.drainActions();
        defer extensions.actions.freeRecords(self.host.gpa, records);
        var reload_applied = false;
        for (records) |record| {
            if (reload_applied) {
                if (self.render_output) printExtensionRecordWarning(self.live.io, record, error.StaleExtensionContext);
                continue;
            }
            self.applyRecord(gpa, sess, run_config, active_client, steering, followups, stop_requested, record) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => {
                    printExtensionRecordWarning(self.live.io, record, err);
                    continue;
                },
            };
            reload_applied = std.mem.eql(u8, record.kind, "reload");
        }
    }

    fn applyRecord(
        self: *ExtensionActionRuntime,
        gpa: std.mem.Allocator,
        sess: *agent.session.Session,
        run_config: *agent.AgentConfig,
        active_client: *ai.ModelClient,
        steering: *std.ArrayList([]u8),
        followups: *std.ArrayList([]u8),
        stop_requested: *bool,
        record: extensions.actions.Record,
    ) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, record.json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidExtensionAction;
        const object = parsed.value.object;

        if (std.mem.eql(u8, record.kind, "set_session_name")) {
            const name = try requiredActionString(object, "name");
            try sess.setName(name);
            return;
        }
        if (std.mem.eql(u8, record.kind, "append_entry")) {
            const custom_type = try requiredActionString(object, "customType");
            const data_json = if (object.get("data")) |value| try stringifyActionValue(gpa, value) else null;
            defer if (data_json) |owned| gpa.free(owned);
            const entry_id = try sess.appendCustomEntry(custom_type, data_json);
            if (self.render_output) {
                const entry = sess.getEntry(entry_id) orelse return;
                var rendered_entry: std.Io.Writer.Allocating = .init(gpa);
                defer rendered_entry.deinit();
                try rendered_entry.writer.writeAll("{\"type\":\"custom\",\"id\":");
                try std.json.Stringify.value(entry.id, .{}, &rendered_entry.writer);
                try rendered_entry.writer.writeAll(",\"parentId\":");
                if (entry.parent_id) |parent| try std.json.Stringify.value(parent, .{}, &rendered_entry.writer) else try rendered_entry.writer.writeAll("null");
                try rendered_entry.writer.writeAll(",\"timestamp\":");
                try std.json.Stringify.value(entry.timestamp, .{}, &rendered_entry.writer);
                try rendered_entry.writer.writeAll(",\"customType\":");
                try std.json.Stringify.value(custom_type, .{}, &rendered_entry.writer);
                if (data_json) |data| {
                    try rendered_entry.writer.writeAll(",\"data\":");
                    try rendered_entry.writer.writeAll(data);
                }
                try rendered_entry.writer.writeByte('}');
                if (self.host.renderEntry(custom_type, rendered_entry.written(), false, self.render_width) catch null) |rendered| {
                    defer self.host.gpa.free(rendered);
                    try writeExtensionRendered(self.live.io, rendered);
                }
            }
            return;
        }
        if (std.mem.eql(u8, record.kind, "set_label")) {
            const entry_id = try requiredActionString(object, "entryId");
            const label: ?[]const u8 = if (object.get("label")) |value| switch (value) {
                .null => null,
                .string => |text| text,
                else => return error.InvalidExtensionAction,
            } else null;
            _ = sess.appendLabelChange(entry_id, label) catch |err| switch (err) {
                error.UnknownEntry => return,
                else => return err,
            };
            return;
        }
        if (std.mem.eql(u8, record.kind, "send_message")) {
            const message_value = object.get("message") orelse return error.InvalidExtensionAction;
            if (message_value != .object) return error.InvalidExtensionAction;
            const custom_type = if (message_value.object.get("customType")) |value| switch (value) {
                .string => |text| text,
                else => return error.InvalidExtensionAction,
            } else "extension";
            const content_value = message_value.object.get("content") orelse std.json.Value{ .string = "" };
            const content = try extensionActionContent(gpa, content_value);
            defer gpa.free(content);
            const display = if (message_value.object.get("display")) |value| switch (value) {
                .bool => |enabled| enabled,
                else => return error.InvalidExtensionAction,
            } else true;
            _ = try sess.appendCustomMessage(custom_type, content, display);
            if (display and self.render_output) {
                const message_json = try stringifyActionValue(gpa, message_value);
                defer gpa.free(message_json);
                if (self.host.renderMessage(custom_type, message_json, false, 1, self.render_width) catch null) |rendered| {
                    defer self.host.gpa.free(rendered);
                    try writeExtensionRendered(self.live.io, rendered);
                } else {
                    try tui.render.printLine(self.live.io, content);
                }
            }

            var trigger_turn = false;
            var delivery: ?[]const u8 = null;
            if (object.get("options")) |options| {
                if (options != .object) return error.InvalidExtensionAction;
                if (options.object.get("triggerTurn")) |value| {
                    if (value != .bool) return error.InvalidExtensionAction;
                    trigger_turn = value.bool;
                }
                if (options.object.get("deliverAs")) |value| switch (value) {
                    .null => {},
                    .string => |text| delivery = text,
                    else => return error.InvalidExtensionAction,
                };
            }
            if (delivery) |mode| {
                if (std.ascii.eqlIgnoreCase(mode, "followUp") or std.ascii.eqlIgnoreCase(mode, "follow_up"))
                    try appendExtensionPending(gpa, followups, content)
                else if (std.ascii.eqlIgnoreCase(mode, "steer") or std.ascii.eqlIgnoreCase(mode, "nextTurn") or std.ascii.eqlIgnoreCase(mode, "next_turn"))
                    try appendExtensionPending(gpa, steering, content)
                else
                    return error.InvalidExtensionDeliveryMode;
            } else if (trigger_turn) {
                try appendExtensionPending(gpa, steering, content);
            }
            return;
        }
        if (std.mem.eql(u8, record.kind, "send_user_message")) {
            const content_value = object.get("content") orelse return error.InvalidExtensionAction;
            const content = try extensionActionContent(gpa, content_value);
            defer gpa.free(content);
            var delivery: ?[]const u8 = null;
            if (object.get("options")) |options| {
                if (options != .object) return error.InvalidExtensionAction;
                if (options.object.get("deliverAs")) |value| switch (value) {
                    .null => {},
                    .string => |text| delivery = text,
                    else => return error.InvalidExtensionAction,
                };
            }
            if (delivery) |mode| {
                if (std.ascii.eqlIgnoreCase(mode, "followUp") or std.ascii.eqlIgnoreCase(mode, "follow_up"))
                    try appendExtensionPending(gpa, followups, content)
                else if (std.ascii.eqlIgnoreCase(mode, "steer") or std.ascii.eqlIgnoreCase(mode, "nextTurn") or std.ascii.eqlIgnoreCase(mode, "next_turn"))
                    try appendExtensionPending(gpa, steering, content)
                else
                    return error.InvalidExtensionDeliveryMode;
            } else {
                try appendExtensionPending(gpa, steering, content);
            }
            return;
        }
        if (std.mem.eql(u8, record.kind, "set_active_tools")) {
            const names_value = object.get("names") orelse return error.InvalidExtensionAction;
            if (names_value != .array) return error.InvalidExtensionAction;
            var requested: std.ArrayList([]const u8) = .empty;
            defer requested.deinit(gpa);
            for (names_value.array.items) |value| {
                if (value != .string or value.string.len == 0) return error.InvalidExtensionAction;
                try requested.append(gpa, value.string);
            }
            try applyExtensionRuntimeActions(
                gpa,
                sess,
                null,
                null,
                requested.items,
                self.live,
                self.host,
                self.bridge,
                self.active_filter,
                self.owned_active_tools,
                self.extension_schemas,
            );
            self.refreshRunState(run_config, active_client);
            return;
        }
        if (std.mem.eql(u8, record.kind, "set_model")) {
            const model_value = object.get("model") orelse return error.InvalidExtensionAction;
            var model_action = try parseRuntimeModelAction(gpa, model_value);
            defer model_action.deinit(gpa);
            try applyExtensionRuntimeActions(
                gpa,
                sess,
                &model_action,
                null,
                null,
                self.live,
                self.host,
                self.bridge,
                self.active_filter,
                self.owned_active_tools,
                self.extension_schemas,
            );
            self.refreshRunState(run_config, active_client);
            return;
        }
        if (std.mem.eql(u8, record.kind, "set_thinking_level")) {
            const level = try requiredActionString(object, "level");
            try applyExtensionRuntimeActions(
                gpa,
                sess,
                null,
                level,
                null,
                self.live,
                self.host,
                self.bridge,
                self.active_filter,
                self.owned_active_tools,
                self.extension_schemas,
            );
            self.refreshRunState(run_config, active_client);
            return;
        }
        if (std.mem.eql(u8, record.kind, "abort")) {
            if (run_config.abort_flag) |flag| @atomicStore(bool, flag, true, .release);
            stop_requested.* = true;
            return;
        }
        if (std.mem.eql(u8, record.kind, "shutdown")) {
            stop_requested.* = true;
            return;
        }
        if (std.mem.eql(u8, record.kind, "register_provider")) {
            const name = try requiredActionString(object, "name");
            const config_value = object.get("config") orelse return error.InvalidExtensionAction;
            if (config_value != .object) return error.InvalidExtensionAction;
            const config_json = try stringifyActionValue(gpa, config_value);
            defer gpa.free(config_json);
            try self.provider_registry.registerJsonWithRuntime(name, config_json, self.host.scriptRuntimeForExtension(record.extension_name));
            var refresh_result = try self.provider_models.registerProvider(name, run_config.abort_flag);
            defer refresh_result.deinit();
            self.reportProviderRefreshErrors(refresh_result.errors);
            try self.publishProviderRegistry(run_config, active_client);
            return;
        }
        if (std.mem.eql(u8, record.kind, "unregister_provider")) {
            const name = try requiredActionString(object, "name");
            if (try self.provider_registry.unregister(name)) try self.provider_models.unregisterProvider(name);
            try self.publishProviderRegistry(run_config, active_client);
            return;
        }
        if (std.mem.eql(u8, record.kind, "reload")) {
            const status = try coding.live_state.applyReload(self.live);
            defer gpa.free(status);
            self.refreshRunState(run_config, active_client);
            if (self.render_output) try tui.render.printLine(self.live.io, status);
            return;
        }
        return error.UnknownExtensionAction;
    }

    fn reportProviderRefreshErrors(self: *ExtensionActionRuntime, errors: []const extensions.provider_models.RefreshError) void {
        if (!self.render_output) return;
        for (errors) |entry| {
            var buffer: [768]u8 = undefined;
            const warning = std.fmt.bufPrint(&buffer, "warning: extension provider {s} model refresh failed: {s}", .{ entry.provider_id, entry.message }) catch continue;
            tui.render.printLine(self.live.io, warning) catch {};
        }
    }

    fn publishProviderRegistry(self: *ExtensionActionRuntime, run_config: *agent.AgentConfig, active_client: *ai.ModelClient) !void {
        self.live.model_catalog = self.provider_registry.catalog();
        if (self.live.client_pool) |pool| {
            pool.invalidateExtensionOAuth();
            pool.setRuntimeProviders(self.provider_registry.runtimes());
            if (self.live.provider_name) |provider_ptr| if (provider_ptr.*) |provider_id| {
                if (self.live.model_display.*) |model_id| {
                    for (self.live.model_catalog) |candidate| {
                        if (!std.ascii.eqlIgnoreCase(candidate.providerName(), provider_id) or
                            !std.mem.eql(u8, candidate.id, model_id)) continue;
                        try pool.switchToIdentity(candidate.providerName(), candidate.provider, candidate.id);
                        break;
                    }
                }
            };
        }
        self.refreshRunState(run_config, active_client);
    }

    fn refreshRunState(self: *ExtensionActionRuntime, run_config: *agent.AgentConfig, active_client: *ai.ModelClient) void {
        run_config.tool_filter = self.active_filter.*;
        run_config.extra_tools_json = self.extension_schemas.*;
        run_config.provider_name = self.live.agent_cfg.provider_name;
        run_config.model_id = self.live.agent_cfg.model_id;
        run_config.reasoning_level = self.live.agent_cfg.reasoning_level;
        run_config.system_prompt = self.live.agent_cfg.system_prompt;
        run_config.context_prompt = self.live.agent_cfg.context_prompt;
        if (self.mock_client) |client|
            active_client.* = client
        else if (self.live.client_pool) |pool|
            active_client.* = pool.client;
    }
};

const AppliedExtensionCommand = struct {
    prompt: ?[]u8 = null,
    terminate: bool = false,
    is_error: bool = false,

    fn deinit(self: *AppliedExtensionCommand, gpa: std.mem.Allocator) void {
        if (self.prompt) |value| gpa.free(value);
        self.* = undefined;
    }
};

fn freeMutableMessages(gpa: std.mem.Allocator, messages: *std.ArrayList([]u8)) void {
    for (messages.items) |message| gpa.free(message);
    messages.deinit(gpa);
}

fn moveMutableMessages(
    gpa: std.mem.Allocator,
    source: *std.ArrayList([]u8),
    destination: *std.ArrayList([]const u8),
) !void {
    try destination.ensureUnusedCapacity(gpa, source.items.len);
    for (source.items) |message| destination.appendAssumeCapacity(message);
    source.clearRetainingCapacity();
}

/// Apply a completed command or shortcut through the same ordered action
/// semantics used by lifecycle hooks and extension tools. Legacy return-object
/// fields remain supported, but an equivalent queued action wins so mirrored
/// bridge fields cannot execute twice.
fn applyExtensionCommandOutput(
    gpa: std.mem.Allocator,
    io: Io,
    runtime: *ExtensionActionRuntime,
    sess: *agent.session.Session,
    output: *const extensions.host.CommandOutput,
    run_config: *agent.AgentConfig,
    active_client: *ai.ModelClient,
    queued_steering: *std.ArrayList([]const u8),
    queued_followups: *std.ArrayList([]const u8),
) !AppliedExtensionCommand {
    var result = AppliedExtensionCommand{ .terminate = output.terminate, .is_error = output.is_error };
    errdefer result.deinit(gpa);

    if (output.actions.isEmpty()) {
        try applyExtensionSessionActions(sess, output);
        try applyCommandRuntimeActions(
            gpa,
            sess,
            output,
            runtime.live,
            runtime.host,
            runtime.bridge,
            runtime.active_filter,
            runtime.owned_active_tools,
            runtime.extension_schemas,
        );
        if (runtime.render_output) if (output.message) |visible| try tui.render.printLine(io, visible);
        if (output.prompt) |prompt| result.prompt = try gpa.dupe(u8, prompt);
        result.terminate = result.terminate or output.abort;
        return result;
    }

    var steering: std.ArrayList([]u8) = .empty;
    defer freeMutableMessages(gpa, &steering);
    var followups: std.ArrayList([]u8) = .empty;
    defer freeMutableMessages(gpa, &followups);
    var stop_requested = false;
    var saw_message = false;
    var saw_session_name = false;
    var saw_entry = false;
    var saw_label = false;
    var saw_model = false;
    var saw_thinking = false;
    var saw_tools = false;
    var saw_abort = false;
    var saw_reload = false;

    for (output.actions.items) |record| {
        if (saw_reload) {
            if (runtime.render_output) printExtensionRecordWarning(io, record, error.StaleExtensionContext);
            continue;
        }
        saw_message = saw_message or std.mem.eql(u8, record.kind, "send_message");
        saw_session_name = saw_session_name or std.mem.eql(u8, record.kind, "set_session_name");
        saw_entry = saw_entry or std.mem.eql(u8, record.kind, "append_entry");
        saw_label = saw_label or std.mem.eql(u8, record.kind, "set_label");
        saw_model = saw_model or std.mem.eql(u8, record.kind, "set_model");
        saw_thinking = saw_thinking or std.mem.eql(u8, record.kind, "set_thinking_level");
        saw_tools = saw_tools or std.mem.eql(u8, record.kind, "set_active_tools");
        saw_abort = saw_abort or std.mem.eql(u8, record.kind, "abort") or std.mem.eql(u8, record.kind, "shutdown");
        runtime.applyRecord(gpa, sess, run_config, active_client, &steering, &followups, &stop_requested, record) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {
                if (runtime.render_output) printExtensionRecordWarning(io, record, err);
                continue;
            },
        };
        saw_reload = std.mem.eql(u8, record.kind, "reload");
    }

    // A successful reload invalidates the producing command/shortcut context.
    // Keep actions ordered before the barrier, but reject every later record and
    // all legacy mirror fields returned by the stale worker.
    if (saw_reload) {
        if (steering.items.len > 0) {
            result.prompt = steering.orderedRemove(0);
        } else if (followups.items.len > 0) {
            result.prompt = followups.orderedRemove(0);
        }
        try moveMutableMessages(gpa, &steering, queued_steering);
        try moveMutableMessages(gpa, &followups, queued_followups);
        result.terminate = stop_requested;
        result.is_error = false;
        return result;
    }

    // Preserve return-object compatibility for fields that were not represented
    // by an ordered action. This also supports native executable extensions.
    if (!saw_session_name) {
        if (output.session_name) |name| try sess.setName(name);
    }
    if (!saw_entry) {
        for (output.entries) |entry| _ = try sess.appendCustomEntry(entry.custom_type, entry.data_json);
    }
    if (!saw_label) {
        for (output.labels) |label| {
            _ = sess.appendLabelChange(label.entry_id, label.label) catch |err| switch (err) {
                error.UnknownEntry => continue,
                else => return err,
            };
        }
    }
    if (!saw_model or !saw_thinking or !saw_tools) {
        const model_ptr: ?*const extensions.host.ModelAction = if (!saw_model) if (output.model) |*model| model else null else null;
        const thinking = if (!saw_thinking) output.thinking_level else null;
        const tools: ?[]const []const u8 = if (!saw_tools) if (output.active_tools) |values| values else null else null;
        try applyExtensionRuntimeActions(
            gpa,
            sess,
            model_ptr,
            thinking,
            tools,
            runtime.live,
            runtime.host,
            runtime.bridge,
            runtime.active_filter,
            runtime.owned_active_tools,
            runtime.extension_schemas,
        );
        runtime.refreshRunState(run_config, active_client);
    }
    if (!saw_message and runtime.render_output) {
        if (output.message) |visible| try tui.render.printLine(io, visible);
    }
    if (!saw_abort and output.abort) stop_requested = true;

    if (steering.items.len > 0) {
        result.prompt = steering.orderedRemove(0);
    } else if (followups.items.len > 0) {
        result.prompt = followups.orderedRemove(0);
    } else if (output.prompt) |prompt| {
        result.prompt = try gpa.dupe(u8, prompt);
    }
    try moveMutableMessages(gpa, &steering, queued_steering);
    try moveMutableMessages(gpa, &followups, queued_followups);
    result.terminate = result.terminate or stop_requested or output.abort;
    return result;
}

fn removeMatchingMutableMessage(
    gpa: std.mem.Allocator,
    messages: *std.ArrayList([]u8),
    needle: []const u8,
) bool {
    for (messages.items, 0..) |message, index| {
        if (!std.mem.eql(u8, message, needle)) continue;
        const removed = messages.orderedRemove(index);
        gpa.free(removed);
        return true;
    }
    return false;
}

/// Replay startup command batches after the live provider/client graph exists.
/// The prompt selected during preflight is removed from the generated queue so
/// the same command does not produce a duplicate user turn.
fn applyDeferredExtensionActions(
    gpa: std.mem.Allocator,
    io: Io,
    deferred: *DeferredExtensionActions,
    runtime: *ExtensionActionRuntime,
    sess: *agent.session.Session,
    run_config: *agent.AgentConfig,
    active_client: *ai.ModelClient,
    queued_steering: *std.ArrayList([]const u8),
    queued_followups: *std.ArrayList([]const u8),
) !bool {
    var steering: std.ArrayList([]u8) = .empty;
    defer freeMutableMessages(gpa, &steering);
    var followups: std.ArrayList([]u8) = .empty;
    defer freeMutableMessages(gpa, &followups);
    var stop_requested = deferred.abort;
    var reload_applied = false;

    for (deferred.batches.items) |*batch| {
        for (batch.items) |record| {
            if (reload_applied) {
                if (runtime.render_output) printExtensionRecordWarning(io, record, error.StaleExtensionContext);
                continue;
            }
            runtime.applyRecord(gpa, sess, run_config, active_client, &steering, &followups, &stop_requested, record) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => {
                    if (runtime.render_output) printExtensionRecordWarning(io, record, err);
                    continue;
                },
            };
            reload_applied = std.mem.eql(u8, record.kind, "reload");
        }
        batch.deinit(gpa);
    }
    deferred.batches.clearRetainingCapacity();

    for (deferred.consumed_action_prompts.items) |prompt| {
        if (!removeMatchingMutableMessage(gpa, &steering, prompt))
            _ = removeMatchingMutableMessage(gpa, &followups, prompt);
    }
    try moveMutableMessages(gpa, &steering, queued_steering);
    try moveMutableMessages(gpa, &followups, queued_followups);
    return stop_requested;
}

/// Apply action records that remain after the final session lifecycle event.
/// This path deliberately needs no model transport, so session_shutdown hooks
/// are durable even when startup terminates before the live client pool exists.
fn flushFinalExtensionActions(
    gpa: std.mem.Allocator,
    io: Io,
    sess: *agent.session.Session,
    bridge: *extensions.integration.Bridge,
) !void {
    const records = try bridge.drainActions();
    defer extensions.actions.freeRecords(gpa, records);
    for (records) |record| {
        applyFinalExtensionRecord(gpa, sess, record) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => printExtensionRecordWarning(io, record, err),
        };
    }
}

fn applyDeferredFinalExtensionActions(
    gpa: std.mem.Allocator,
    io: Io,
    sess: *agent.session.Session,
    deferred: *DeferredExtensionActions,
) !void {
    for (deferred.batches.items) |*batch| {
        for (batch.items) |record| {
            applyFinalExtensionRecord(gpa, sess, record) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => printExtensionRecordWarning(io, record, err),
            };
        }
        batch.deinit(gpa);
    }
    deferred.batches.clearRetainingCapacity();
}

fn applyFinalExtensionRecord(
    gpa: std.mem.Allocator,
    sess: *agent.session.Session,
    record: extensions.actions.Record,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, record.json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidExtensionAction;
    const object = parsed.value.object;

    if (std.mem.eql(u8, record.kind, "set_session_name")) {
        try sess.setName(try requiredActionString(object, "name"));
        return;
    }
    if (std.mem.eql(u8, record.kind, "append_entry")) {
        const custom_type = try requiredActionString(object, "customType");
        const data_json = if (object.get("data")) |value| try stringifyActionValue(gpa, value) else null;
        defer if (data_json) |owned| gpa.free(owned);
        _ = try sess.appendCustomEntry(custom_type, data_json);
        return;
    }
    if (std.mem.eql(u8, record.kind, "set_label")) {
        const entry_id = try requiredActionString(object, "entryId");
        const label: ?[]const u8 = if (object.get("label")) |value| switch (value) {
            .null => null,
            .string => |text| text,
            else => return error.InvalidExtensionAction,
        } else null;
        _ = sess.appendLabelChange(entry_id, label) catch |err| switch (err) {
            error.UnknownEntry => return,
            else => return err,
        };
        return;
    }
    if (std.mem.eql(u8, record.kind, "send_message")) {
        const message_value = object.get("message") orelse return error.InvalidExtensionAction;
        if (message_value != .object) return error.InvalidExtensionAction;
        const custom_type = if (message_value.object.get("customType")) |value| switch (value) {
            .string => |text| text,
            else => return error.InvalidExtensionAction,
        } else "extension";
        const content_value = message_value.object.get("content") orelse std.json.Value{ .string = "" };
        const content = try extensionActionContent(gpa, content_value);
        defer gpa.free(content);
        const display = if (message_value.object.get("display")) |value| switch (value) {
            .bool => |enabled| enabled,
            else => return error.InvalidExtensionAction,
        } else true;
        _ = try sess.appendCustomMessage(custom_type, content, display);
        return;
    }
    if (std.mem.eql(u8, record.kind, "send_user_message")) {
        const content = try extensionActionContent(gpa, object.get("content") orelse return error.InvalidExtensionAction);
        defer gpa.free(content);
        _ = try sess.appendMessage(sess.lastEntryId(), "user", content, null, null);
        return;
    }
    if (std.mem.eql(u8, record.kind, "set_model")) {
        var model_action = try parseRuntimeModelAction(gpa, object.get("model") orelse return error.InvalidExtensionAction);
        defer model_action.deinit(gpa);
        if (model_action.provider) |provider|
            _ = try sess.appendModelChange(provider, model_action.id)
        else {
            const raw = try stringifyActionValue(gpa, parsed.value);
            defer gpa.free(raw);
            _ = try sess.appendCustomEntry("extension-model-action", raw);
        }
        return;
    }
    if (std.mem.eql(u8, record.kind, "set_thinking_level")) {
        _ = try sess.appendThinkingLevelChange(try requiredActionString(object, "level"));
        return;
    }
    if (std.mem.eql(u8, record.kind, "set_active_tools")) {
        const raw = try stringifyActionValue(gpa, parsed.value);
        defer gpa.free(raw);
        _ = try sess.appendCustomEntry("extension-active-tools", raw);
        return;
    }
    if (std.mem.eql(u8, record.kind, "register_provider") or std.mem.eql(u8, record.kind, "unregister_provider")) {
        const raw = try stringifyActionValue(gpa, parsed.value);
        defer gpa.free(raw);
        _ = try sess.appendCustomEntry("extension-provider-action", raw);
        return;
    }
    if (std.mem.eql(u8, record.kind, "reload") or std.mem.eql(u8, record.kind, "abort") or std.mem.eql(u8, record.kind, "shutdown")) return;
    return error.UnknownExtensionAction;
}

fn requiredActionString(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.InvalidExtensionAction;
    if (value != .string or value.string.len == 0) return error.InvalidExtensionAction;
    return value.string;
}

fn appendExtensionPending(gpa: std.mem.Allocator, queue: *std.ArrayList([]u8), text: []const u8) !void {
    const owned = try gpa.dupe(u8, text);
    errdefer gpa.free(owned);
    try queue.append(gpa, owned);
}

fn extensionActionContent(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    if (value == .string) return gpa.dupe(u8, value.string);
    if (value == .array) {
        var writer: std.Io.Writer.Allocating = .init(gpa);
        errdefer writer.deinit();
        var first = true;
        for (value.array.items) |part| {
            if (part == .string) {
                if (!first) try writer.writer.writeByte('\n');
                first = false;
                try writer.writer.writeAll(part.string);
                continue;
            }
            if (part != .object) continue;
            const type_value = part.object.get("type") orelse continue;
            if (type_value != .string) continue;
            if (std.mem.eql(u8, type_value.string, "text")) {
                const text = part.object.get("text") orelse continue;
                if (text != .string) continue;
                if (!first) try writer.writer.writeByte('\n');
                first = false;
                try writer.writer.writeAll(text.string);
            } else if (std.mem.eql(u8, type_value.string, "image")) {
                if (!first) try writer.writer.writeByte('\n');
                first = false;
                try writer.writer.writeAll("[image attachment]");
            }
        }
        if (writer.written().len > 0) return try writer.toOwnedSlice();
        writer.deinit();
    }
    return stringifyActionValue(gpa, value);
}

fn stringifyActionValue(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(gpa);
    errdefer writer.deinit();
    try std.json.Stringify.value(value, .{}, &writer.writer);
    return try writer.toOwnedSlice();
}

fn parseRuntimeModelAction(gpa: std.mem.Allocator, value: std.json.Value) !extensions.host.ModelAction {
    if (value == .string) {
        const trimmed = std.mem.trim(u8, value.string, " \t\r\n");
        if (trimmed.len == 0) return error.InvalidExtensionAction;
        if (std.mem.indexOfScalar(u8, trimmed, '/')) |slash| {
            if (slash == 0 or slash + 1 >= trimmed.len) return error.InvalidExtensionAction;
            const provider = try gpa.dupe(u8, trimmed[0..slash]);
            errdefer gpa.free(provider);
            return .{ .provider = provider, .id = try gpa.dupe(u8, trimmed[slash + 1 ..]) };
        }
        return .{ .id = try gpa.dupe(u8, trimmed) };
    }
    if (value != .object) return error.InvalidExtensionAction;
    const id_value = value.object.get("id") orelse value.object.get("modelId") orelse return error.InvalidExtensionAction;
    if (id_value != .string or id_value.string.len == 0) return error.InvalidExtensionAction;
    const provider = if (value.object.get("provider")) |provider_value| switch (provider_value) {
        .null => null,
        .string => |text| if (text.len > 0) try gpa.dupe(u8, text) else return error.InvalidExtensionAction,
        else => return error.InvalidExtensionAction,
    } else null;
    errdefer if (provider) |owned| gpa.free(owned);
    return .{ .provider = provider, .id = try gpa.dupe(u8, id_value.string) };
}

fn printExtensionRecordWarning(io: Io, record: extensions.actions.Record, err: anyerror) void {
    var buffer: [512]u8 = undefined;
    const message = std.fmt.bufPrint(
        &buffer,
        "warning: extension {s} action {s} from {s} was ignored: {s}",
        .{ record.extension_name, record.kind, record.invocation, @errorName(err) },
    ) catch return;
    tui.render.printLine(io, message) catch {};
}

fn collectExtensionContextTools(
    allocator: std.mem.Allocator,
    host: *const extensions.Host,
    filter: agent.tools.ToolFilter,
    disable_builtin_tools: bool,
    active_only: bool,
) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(allocator);
    if (!disable_builtin_tools or !active_only) {
        for (agent.tools.all_tool_names) |name| {
            if (!active_only or filter.isEnabled(name)) try names.append(allocator, name);
        }
    }
    for (host.extensions.items) |extension| {
        for (extension.tools) |tool| {
            if (active_only and !filter.isEnabled(tool.name)) continue;
            var duplicate = false;
            for (names.items) |existing| {
                if (std.mem.eql(u8, existing, tool.name)) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) try names.append(allocator, tool.name);
        }
    }
    return try names.toOwnedSlice(allocator);
}

fn syncExtensionScriptContext(
    host: *extensions.Host,
    ui_controller: *extensions.ui.Controller,
    mode: []const u8,
    cwd: []const u8,
    sess: *const agent.session.Session,
    provider: ?[]const u8,
    model_id: ?[]const u8,
    thinking_level: ?[]const u8,
    project_trusted: bool,
    editor_text: ?[]const u8,
    tool_filter: agent.tools.ToolFilter,
    disable_builtin_tools: bool,
    model_catalog: []const ai.providers.ModelInfo,
    configured_providers: []const []const u8,
    session_file: ?[]const u8,
    session_dir: ?[]const u8,
) !void {
    if (editor_text) |text| try ui_controller.setEditorSnapshot(text);
    const active_tools = try collectExtensionContextTools(host.gpa, host, tool_filter, disable_builtin_tools, true);
    defer host.gpa.free(active_tools);
    const all_tools = try collectExtensionContextTools(host.gpa, host, tool_filter, disable_builtin_tools, false);
    defer host.gpa.free(all_tools);
    const context = try ui_controller.contextJson(host.gpa, .{
        .mode = mode,
        .cwd = cwd,
        .session_id = sess.id,
        .session_name = if (sess.name.len > 0) sess.name else null,
        .provider = provider,
        .model_id = model_id,
        .thinking_level = thinking_level,
        .project_trusted = project_trusted,
        .active_tools = active_tools,
        .all_tools = all_tools,
        .model_catalog = model_catalog,
        .configured_providers = configured_providers,
        .session = sess,
        .session_file = session_file,
        .session_dir = session_dir,
    });
    defer host.gpa.free(context);
    try host.setScriptContextJson(context);
}

fn deinitPromptTemplateSlice(gpa: std.mem.Allocator, templates: []coding.prompts.PromptTemplate) void {
    for (templates) |*template| template.deinit(gpa);
    if (templates.len > 0) gpa.free(templates);
}

fn collectExtensionCommandMetadata(
    gpa: std.mem.Allocator,
    host: *const extensions.Host,
    names: *std.ArrayList([]const u8),
    infos: *std.ArrayList(coding.rpc_data.ExtensionCommandInfo),
) !void {
    for (host.extensions.items) |extension| {
        for (extension.commands) |command| {
            try names.append(gpa, command.name);
            try infos.append(gpa, .{
                .name = command.name,
                .description = command.description,
                .argument_hint = command.argument_hint,
                .extension_name = extension.name,
                .entry_path = extension.entry,
            });
        }
    }
}

fn configureExtensionCallbacks(
    cfg: *agent.AgentConfig,
    bridge: *extensions.integration.Bridge,
    runtime: *ExtensionActionRuntime,
    schemas: []const u8,
    active: bool,
) void {
    cfg.hook_ctx = if (active) bridge else null;
    cfg.before_prompt_fn = if (active) extensions.integration.Bridge.beforePrompt else null;
    cfg.before_agent_start_fn = if (active) extensions.integration.Bridge.beforeAgentStart else null;
    cfg.transform_context_fn = if (active) extensions.integration.Bridge.transformContext else null;
    cfg.before_tool_fn = if (active) extensions.integration.Bridge.beforeTool else null;
    cfg.after_tool_fn = if (active) extensions.integration.Bridge.afterTool else null;
    cfg.before_compact_fn = if (active) extensions.integration.Bridge.beforeCompact else null;
    cfg.after_compact_fn = if (active) extensions.integration.Bridge.afterCompact else null;
    cfg.before_tree_fn = if (active) extensions.integration.Bridge.beforeTree else null;
    cfg.after_tree_fn = if (active) extensions.integration.Bridge.afterTree else null;
    cfg.event_observer_fn = if (active) extensions.integration.Bridge.onAgentEvent else null;
    cfg.event_observer_ctx = if (active) bridge else null;
    cfg.extra_tools_json = schemas;
    cfg.external_tool_fn = if (active) extensions.integration.Bridge.executeTool else null;
    cfg.external_tool_streaming_fn = if (active) extensions.integration.Bridge.executeToolStreaming else null;
    cfg.external_tool_call_streaming_fn = if (active) extensions.integration.Bridge.executeToolCallStreaming else null;
    cfg.external_tool_exists_fn = if (active) extensions.integration.Bridge.hasExecutableTool else null;
    cfg.external_prepare_arguments_fn = if (active) extensions.integration.Bridge.prepareToolArguments else null;
    cfg.external_tool_mode_fn = if (active) extensions.integration.Bridge.toolExecutionMode else null;
    cfg.flush_runtime_actions_fn = if (active) ExtensionActionRuntime.flush else null;
    cfg.flush_runtime_actions_ctx = if (active) runtime else null;
}

fn catalogContainsIdentity(
    catalog: []const ai.providers.ModelInfo,
    provider_name: []const u8,
    model_id: []const u8,
) bool {
    for (catalog) |candidate| {
        if (std.ascii.eqlIgnoreCase(candidate.providerName(), provider_name) and std.mem.eql(u8, candidate.id, model_id)) return true;
    }
    return false;
}

const ReloadCredentialSet = struct {
    gpa: std.mem.Allocator,
    openai: ?[]u8 = null,
    anthropic: ?[]u8 = null,
    google: ?[]u8 = null,

    fn deinit(self: *ReloadCredentialSet) void {
        if (self.openai) |value| self.gpa.free(value);
        if (self.anthropic) |value| self.gpa.free(value);
        if (self.google) |value| self.gpa.free(value);
        self.* = undefined;
    }
};

fn loadReloadBuiltinCredential(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: ?[]const u8,
    cli: *const coding.args.Args,
    provider: ai.providers.Provider,
) !?[]u8 {
    const explicit = if (cli.provider != null and cli.api_key != null and
        std.ascii.eqlIgnoreCase(cli.provider.?, provider.name()))
        cli.api_key
    else
        null;
    if (ai.providers.resolveApiKey(provider, explicit, environ)) |value| return @as(?[]u8, try gpa.dupe(u8, value));
    const dir = agent_dir orelse return null;
    if (try loadStoredApiKey(gpa, io, environ, dir, provider.name())) |value| return value;
    const legacy_name = ai.providers.credentialEnvName(provider) orelse return null;
    return coding.settings.loadCredential(gpa, io, dir, legacy_name);
}

fn loadReloadCredentialSet(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: ?[]const u8,
    cli: *const coding.args.Args,
) !ReloadCredentialSet {
    var result = ReloadCredentialSet{ .gpa = gpa };
    errdefer result.deinit();
    result.openai = try loadReloadBuiltinCredential(gpa, io, environ, agent_dir, cli, .openai);
    result.anthropic = try loadReloadBuiltinCredential(gpa, io, environ, agent_dir, cli, .anthropic);
    result.google = try loadReloadBuiltinCredential(gpa, io, environ, agent_dir, cli, .google);
    return result;
}

const ClientReloadBackup = struct {
    gpa: std.mem.Allocator,
    openai: ?[]u8 = null,
    anthropic: ?[]u8 = null,
    google: ?[]u8 = null,
    proxy: ?[]u8 = null,
    active_provider: ai.providers.Provider,
    transport: ai.codex_websocket.Transport,
    http_idle_timeout_ms: u64,
    websocket_connect_timeout_ms: u64,
    provider_retry_policy: ai.retry.ProviderPolicy,
    live_credential: coding.live_state.LiveCredentialSnapshot,

    fn capture(gpa: std.mem.Allocator, pool: *const coding.live_state.ClientPool) !ClientReloadBackup {
        var result = ClientReloadBackup{
            .gpa = gpa,
            .active_provider = pool.active_provider,
            .transport = pool.codex_transport,
            .http_idle_timeout_ms = pool.codex_http_idle_timeout_ms,
            .websocket_connect_timeout_ms = pool.codex_websocket_connect_timeout_ms,
            .provider_retry_policy = pool.provider_retry_policy,
            .live_credential = try pool.snapshotLiveCredential(),
        };
        errdefer result.deinit();
        result.openai = if (pool.openai_key) |value| try gpa.dupe(u8, value) else null;
        result.anthropic = if (pool.anthropic_key) |value| try gpa.dupe(u8, value) else null;
        result.google = if (pool.google_key) |value| try gpa.dupe(u8, value) else null;
        result.proxy = if (pool.http_proxy_url) |value| try gpa.dupe(u8, value) else null;
        return result;
    }

    fn restore(self: *ClientReloadBackup, pool: *coding.live_state.ClientPool) !void {
        try pool.setKeysOwned(self.openai, self.anthropic, self.google);
        try pool.setHttpProxyOwned(self.proxy);
        pool.setCodexTransport(self.transport);
        pool.setCodexHttpIdleTimeout(self.http_idle_timeout_ms);
        pool.setCodexWebSocketConnectTimeout(self.websocket_connect_timeout_ms);
        pool.setProviderRetryPolicy(self.provider_retry_policy);
        pool.restoreLiveCredentialSnapshot(&self.live_credential);
    }

    fn deinit(self: *ClientReloadBackup) void {
        if (self.openai) |value| self.gpa.free(value);
        if (self.anthropic) |value| self.gpa.free(value);
        if (self.google) |value| self.gpa.free(value);
        if (self.proxy) |value| self.gpa.free(value);
        self.live_credential.deinit();
        self.* = undefined;
    }
};

fn providerRetryPolicyFromSettings(settings: *const coding.settings.Settings) ai.retry.ProviderPolicy {
    const inherited_timeout_ms = settings.http_idle_timeout_ms orelse ai.openai_responses.DEFAULT_HTTP_IDLE_TIMEOUT_MS;
    return .{
        // Upstream uses the general HTTP idle timeout as the provider-request
        // timeout unless retry.provider.timeoutMs explicitly overrides it. A
        // disabled general timeout maps to no provider deadline, while an
        // explicit provider value of zero remains an immediate timeout.
        .timeout_ms = settings.retry_provider_timeout_ms orelse if (inherited_timeout_ms == 0) null else inherited_timeout_ms,
        .max_retries = settings.retry_provider_max_retries orelse 2,
        .max_retry_delay_ms = settings.retry_provider_max_retry_delay_ms orelse 60_000,
    };
}

fn applyReloadClientSettings(
    pool: *coding.live_state.ClientPool,
    credentials: *const ReloadCredentialSet,
    settings: *const coding.settings.Settings,
) !void {
    try pool.setKeysOwned(credentials.openai, credentials.anthropic, credentials.google);
    try pool.setHttpProxyOwned(settings.http_proxy);
    pool.setCodexTransport(settings.transport orelse .auto);
    pool.setCodexHttpIdleTimeout(settings.http_idle_timeout_ms orelse ai.openai_responses.DEFAULT_HTTP_IDLE_TIMEOUT_MS);
    pool.setCodexWebSocketConnectTimeout(settings.websocket_connect_timeout_ms orelse ai.openai_responses.DEFAULT_WEBSOCKET_CONNECT_TIMEOUT_MS);
    pool.setProviderRetryPolicy(providerRetryPolicyFromSettings(settings));
}

const RuntimeResourceReloadContext = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    agent_dir: ?[]const u8,
    trust_project: bool,
    cli: *const coding.args.Args,
    mode: []const u8,
    ui: *extensions.ui.Controller,
    session: *agent.session.Session,
    provider_name: *?[]const u8,
    model_id: *?[]const u8,
    live: *coding.live_state.LiveState,
    active_filter: *agent.tools.ToolFilter,
    owned_active_tools: *?[]const []const u8,
    disable_builtin_tools: bool,
    session_file: ?[]const u8,
    session_dir: ?[]const u8,
    baseline_catalog: []const ai.providers.ModelInfo,
    baseline_runtimes: []const coding.live_state.RuntimeProviderConfig,
    host: *extensions.Host,
    bridge: *extensions.integration.Bridge,
    provider_registry: *extensions.provider_registry.Registry,
    extension_oauth: *extensions.provider_oauth.Runtime,
    provider_stream: *extensions.provider_stream.Runtime,
    provider_models: *extensions.provider_models.Runtime,
    schemas: *[]u8,
    prompt_templates: *[]coding.prompts.PromptTemplate,
    command_names: *std.ArrayList([]const u8),
    command_infos: *std.ArrayList(coding.rpc_data.ExtensionCommandInfo),
    theme_registry: *pi_zig.themes.Registry,
    action_runtime: *ExtensionActionRuntime,
    steering: *std.ArrayList([]const u8),
    followups: *std.ArrayList([]const u8),
    shared_abort: *bool,
    keybindings: ?*tui.keybindings.Manager = null,
    settings_text: ?*[]u8 = null,
    tree_filter_mode: *coding.tree_tui.FilterMode,
    render_options: ?*InteractiveRenderOptions = null,
    in_progress: bool = false,

    fn loadExplicitExtension(
        self: *RuntimeResourceReloadContext,
        host: *extensions.Host,
        source: []const u8,
        npm_command: ?[]const []const u8,
    ) !void {
        const agent_dir = self.agent_dir orelse {
            const path = try coding.path_utils.resolveReadPath(self.gpa, self.io, self.environ, source, self.cwd);
            defer self.gpa.free(path);
            return host.loadPath(path);
        };

        var package = try coding.packages.installScopedWithOptions(
            self.gpa,
            self.io,
            agent_dir,
            self.cwd,
            source,
            .temporary,
            self.trust_project,
            .{
                .offline = packageOffline(self.environ, self.cli.offline),
                .npm_command = npm_command,
            },
        );
        defer package.deinit(self.gpa);
        const packages = [_]coding.packages.Package{package};
        var resources = try coding.packages.resolveResources(self.gpa, self.io, &packages);
        defer resources.deinit();
        if (resources.extensions.items.len == 0) return error.ExtensionSourceContainsNoExtensions;
        for (resources.extensions.items) |path| try host.loadPath(path);
    }

    fn flushLifecycleActions(self: *RuntimeResourceReloadContext) void {
        var active_client = if (self.action_runtime.mock_client) |client|
            client
        else if (self.live.client_pool) |pool|
            pool.client
        else
            return;
        var steering: std.ArrayList([]u8) = .empty;
        defer freeMutableMessages(self.gpa, &steering);
        var followups: std.ArrayList([]u8) = .empty;
        defer freeMutableMessages(self.gpa, &followups);
        var stop_requested = false;
        ExtensionActionRuntime.flush(
            self.action_runtime,
            self.gpa,
            self.session,
            self.live.agent_cfg,
            &active_client,
            &steering,
            &followups,
            &stop_requested,
        ) catch |err| {
            self.reportActionError(err);
            return;
        };
        moveMutableMessages(self.gpa, &steering, self.steering) catch |err| {
            self.reportActionError(err);
            return;
        };
        moveMutableMessages(self.gpa, &followups, self.followups) catch |err| {
            self.reportActionError(err);
            return;
        };
        if (stop_requested) @atomicStore(bool, self.shared_abort, true, .release);
    }

    fn reportActionError(self: *RuntimeResourceReloadContext, err: anyerror) void {
        var buffer: [256]u8 = undefined;
        const warning = std.fmt.bufPrint(&buffer, "warning: extension reload actions failed: {s}", .{@errorName(err)}) catch return;
        if (std.mem.eql(u8, self.mode, "tui")) tui.render.printLine(self.io, warning) catch {};
    }

    fn reload(raw: ?*anyopaque) anyerror!coding.live_state.RuntimeReloadResult {
        const self: *RuntimeResourceReloadContext = @ptrCast(@alignCast(raw.?));
        if (self.in_progress) return error.ReloadAlreadyInProgress;
        self.in_progress = true;
        defer self.in_progress = false;
        const gpa = self.gpa;

        var fresh_settings = try coding.settings.loadMergeTrusted(gpa, self.io, self.agent_dir, self.cwd, self.trust_project);
        defer fresh_settings.deinit(gpa);
        var fresh_credentials = try loadReloadCredentialSet(gpa, self.io, self.environ, self.agent_dir, self.cli);
        defer fresh_credentials.deinit();

        var fresh_catalog_snapshot: ?coding.live_state.DynamicCatalogSnapshot = null;
        var fresh_catalog_committed = false;
        defer if (!fresh_catalog_committed) if (fresh_catalog_snapshot) |*snapshot| snapshot.deinit();
        if (self.agent_dir) |agent_dir| {
            const explicit_provider = if (self.cli.api_key != null)
                (self.cli.provider orelse self.provider_name.*)
            else
                null;
            fresh_catalog_snapshot = try coding.live_state.loadDynamicAuthCatalogWithOptions(
                gpa,
                self.io,
                self.environ,
                agent_dir,
                self.baseline_runtimes,
                .{
                    .explicit_provider = explicit_provider,
                    .explicit_api_key = self.cli.api_key,
                    .preserve_unmanaged_runtimes = false,
                },
            );
        }
        const replacement_baseline_catalog = if (fresh_catalog_snapshot) |*snapshot| snapshot.model_catalog else self.baseline_catalog;
        const replacement_baseline_runtimes = if (fresh_catalog_snapshot) |*snapshot| snapshot.runtime_configs else self.baseline_runtimes;
        const new_settings_text = if (self.settings_text != null)
            try coding.settings.formatSettings(gpa, fresh_settings)
        else
            null;
        errdefer if (new_settings_text) |text| gpa.free(text);
        var new_keybindings: ?tui.keybindings.Manager = null;
        var keybindings_ready = false;
        if (self.keybindings != null) {
            if (self.agent_dir) |agent_dir| {
                new_keybindings = tui.keybindings.Manager.load(gpa, self.io, agent_dir) catch null;
                keybindings_ready = new_keybindings != null;
            } else {
                new_keybindings = tui.keybindings.Manager.init(gpa);
                keybindings_ready = true;
            }
        }
        errdefer if (new_keybindings) |*manager| manager.deinit();

        const installed = if (self.agent_dir) |agent_dir|
            try coding.packages.listConfigured(gpa, self.io, agent_dir, self.cwd, self.trust_project)
        else
            try gpa.alloc(coding.packages.Package, 0);
        defer {
            for (installed) |*package| package.deinit(gpa);
            if (installed.len > 0) gpa.free(installed);
        }
        var package_resources = try coding.packages.resolveResources(gpa, self.io, installed);
        defer package_resources.deinit();
        var top_resources = if (self.agent_dir) |agent_dir|
            try coding.top_level_resources.resolve(gpa, self.io, agent_dir, self.cwd, self.trust_project)
        else
            coding.top_level_resources.Resources.init(gpa);
        defer top_resources.deinit();

        var new_host = extensions.Host{
            .gpa = gpa,
            .io = self.io,
            .js_runtime_program = self.environ.get("PI_JS_RUNTIME") orelse "node",
            .script_ui_bridge = self.ui.bridge(),
        };
        errdefer new_host.deinit();
        if (!self.cli.no_extensions) for (top_resources.extensions.items) |path| try new_host.loadPath(path);
        if (!self.cli.no_extensions) for (package_resources.extensions.items) |path| try new_host.loadPath(path);
        for (self.cli.extensions.items) |source| try self.loadExplicitExtension(&new_host, source, fresh_settings.npm_command);
        for (self.cli.unknown_flags.items) |flag| try new_host.applyCliFlag(flag.name, flag.value);

        var new_command_names: std.ArrayList([]const u8) = .empty;
        errdefer new_command_names.deinit(gpa);
        var new_command_infos: std.ArrayList(coding.rpc_data.ExtensionCommandInfo) = .empty;
        errdefer new_command_infos.deinit(gpa);
        try collectExtensionCommandMetadata(gpa, &new_host, &new_command_names, &new_command_infos);

        var prompt_paths: std.ArrayList([]const u8) = .empty;
        defer {
            for (prompt_paths.items) |path| gpa.free(path);
            prompt_paths.deinit(gpa);
        }
        if (!self.cli.no_prompt_templates) for (top_resources.prompts.items) |path| try prompt_paths.append(gpa, try gpa.dupe(u8, path));
        if (!self.cli.no_prompt_templates) for (package_resources.prompts.items) |path| try prompt_paths.append(gpa, try gpa.dupe(u8, path));
        for (self.cli.prompt_templates.items) |source| {
            const path = try coding.path_utils.resolveReadPath(gpa, self.io, self.environ, source, self.cwd);
            if (!coding.path_utils.pathExists(self.io, path)) {
                gpa.free(path);
                continue;
            }
            try prompt_paths.append(gpa, path);
        }
        const new_prompts = try coding.prompts.loadTrusted(
            gpa,
            self.io,
            self.cwd,
            self.agent_dir,
            self.trust_project,
            prompt_paths.items,
            false,
        );
        errdefer deinitPromptTemplateSlice(gpa, new_prompts);

        var new_themes = pi_zig.themes.Registry.init(gpa, self.io);
        errdefer new_themes.deinit();
        if (!self.cli.no_themes) for (top_resources.themes.items) |path| try new_themes.loadPath(path);
        if (!self.cli.no_themes) for (package_resources.themes.items) |path| try new_themes.loadPath(path);
        for (self.cli.themes.items) |source| {
            const path = try coding.path_utils.resolveReadPath(gpa, self.io, self.environ, source, self.cwd);
            defer gpa.free(path);
            try new_themes.loadPath(path);
        }

        var new_provider_registry = extensions.provider_registry.Registry.init(
            gpa,
            self.io,
            self.environ,
            self.agent_dir,
            replacement_baseline_catalog,
            replacement_baseline_runtimes,
        );
        errdefer new_provider_registry.deinit();
        for (new_host.extensions.items) |extension| {
            for (extension.providers) |registration| try new_provider_registry.registerJsonWithRuntime(registration.name, registration.config_json, extension.script_runtime);
        }
        var provider_models_preparation = try self.provider_models.prepareRegistry(&new_provider_registry);
        defer provider_models_preparation.deinit();

        var new_owned_active_tools: ?[]const []const u8 = null;
        errdefer if (new_owned_active_tools) |names| freeOwnedToolNames(gpa, names);
        var new_filter = self.active_filter.*;
        if (self.owned_active_tools.*) |old_names| {
            new_owned_active_tools = try buildActiveToolSelection(gpa, &new_host, old_names);
            new_filter.allow = new_owned_active_tools.?;
        } else if (self.cli.tools == null) {
            if (fresh_settings.tools) |configured_tools| {
                new_owned_active_tools = try buildActiveToolSelection(gpa, &new_host, configured_tools);
                new_filter.allow = new_owned_active_tools.?;
            } else {
                new_filter.allow = null;
            }
        }

        var new_bridge = extensions.integration.Bridge.init(&new_host);
        errdefer new_bridge.deinit();
        new_bridge.setAbortFlag(self.shared_abort);
        const new_schemas = if (new_host.extensions.items.len > 0)
            try new_bridge.toolSchemasJson(gpa, new_filter)
        else
            try gpa.dupe(u8, "[]");
        errdefer gpa.free(new_schemas);

        const active_provider = self.provider_name.*;
        const active_model = self.model_id.*;
        if (self.live.client_pool != null and active_provider != null and active_model != null and
            !catalogContainsIdentity(new_provider_registry.catalog(), active_provider.?, active_model.?))
        {
            return error.ActiveModelUnavailableAfterReload;
        }

        try syncExtensionScriptContext(
            &new_host,
            self.ui,
            self.mode,
            self.cwd,
            self.session,
            active_provider,
            active_model,
            self.live.thinking,
            self.trust_project,
            null,
            new_filter,
            self.disable_builtin_tools,
            new_provider_registry.catalog(),
            &.{},
            self.session_file,
            self.session_dir,
        );

        var client_backup: ?ClientReloadBackup = if (self.live.client_pool) |pool|
            try ClientReloadBackup.capture(gpa, pool)
        else
            null;
        defer if (client_backup) |*backup| backup.deinit();

        // All replacement resources are valid. Supersede dynamic model
        // generations before any callback owner or worker can be replaced.
        self.provider_models.supersedeAll();

        // Give the old workers their lifecycle boundary before touching any of
        // their owned memory.
        if (self.host.extensions.items.len > 0) {
            self.bridge.sessionShutdown(gpa, self.cwd, self.session.id, "reload") catch |err| {
                var buffer: [256]u8 = undefined;
                const warning = std.fmt.bufPrint(&buffer, "warning: extension session_shutdown during reload failed: {s}", .{@errorName(err)}) catch "warning: extension session_shutdown during reload failed";
                if (std.mem.eql(u8, self.mode, "tui")) tui.render.printLine(self.io, warning) catch {};
            };
            self.flushLifecycleActions();
        }

        // Route OAuth callbacks to the replacement workers while validating
        // the replacement client. The stable runtime pointer is restored on
        // every rollback path and rebound to the committed stack object below.
        const old_oauth_registry = self.extension_oauth.registry;
        const old_stream_registry = self.provider_stream.registry;
        var provider_runtime_registries_committed = false;
        self.extension_oauth.registry = &new_provider_registry;
        self.provider_stream.registry = &new_provider_registry;
        defer {
            if (!provider_runtime_registries_committed) {
                self.extension_oauth.registry = old_oauth_registry;
                self.provider_stream.registry = old_stream_registry;
            }
        }

        // Rebind any active transport to the replacement provider snapshot
        // before the old provider registry is destroyed.
        if (self.live.client_pool) |pool| {
            const old_runtimes = self.provider_registry.runtimes();
            const old_catalog = self.provider_registry.catalog();
            pool.invalidateExtensionOAuth();
            pool.setModelCatalog(new_provider_registry.catalog());
            pool.setRuntimeProviders(new_provider_registry.runtimes());
            // Make the freshly loaded auth.json/models.json snapshot
            // authoritative for the replacement. A deep copy in
            // ClientReloadBackup restores process-local login state if any
            // subsequent rebind step fails.
            pool.clearLiveCredentialForReload();
            applyReloadClientSettings(pool, &fresh_credentials, &fresh_settings) catch |err| {
                self.extension_oauth.registry = old_oauth_registry;
                self.provider_stream.registry = old_stream_registry;
                pool.setModelCatalog(old_catalog);
                pool.setRuntimeProviders(old_runtimes);
                if (client_backup) |*backup| backup.restore(pool) catch return error.ReloadRollbackFailed;
                if (active_provider != null and active_model != null) {
                    pool.switchToIdentity(active_provider.?, client_backup.?.active_provider, active_model.?) catch return error.ReloadRollbackFailed;
                }
                self.bridge.sessionStart(gpa, self.cwd, self.session.id, "reload_rollback") catch {};
                return err;
            };
            if (active_provider != null and active_model != null) {
                var candidate: ?ai.providers.ModelInfo = null;
                for (new_provider_registry.catalog()) |model| {
                    if (std.ascii.eqlIgnoreCase(model.providerName(), active_provider.?) and std.mem.eql(u8, model.id, active_model.?)) {
                        candidate = model;
                        break;
                    }
                }
                if (candidate) |model| {
                    pool.switchToIdentity(model.providerName(), model.provider, model.id) catch |err| {
                        self.extension_oauth.registry = old_oauth_registry;
                        self.provider_stream.registry = old_stream_registry;
                        pool.setModelCatalog(old_catalog);
                        pool.setRuntimeProviders(old_runtimes);
                        if (client_backup) |*backup| backup.restore(pool) catch return error.ReloadRollbackFailed;
                        pool.switchToIdentity(active_provider.?, client_backup.?.active_provider, active_model.?) catch return error.ReloadRollbackFailed;
                        self.bridge.sessionStart(gpa, self.cwd, self.session.id, "reload_rollback") catch {};
                        return err;
                    };
                }
            }
        }

        self.ui.resetForReload();
        tui.render.resetTheme();

        var old_host = self.host.*;
        var old_bridge = self.bridge.*;
        var old_provider_registry = self.provider_registry.*;
        var old_theme_registry = self.theme_registry.*;
        const old_prompts = self.prompt_templates.*;
        const old_schemas = self.schemas.*;
        var old_command_names = self.command_names.*;
        var old_command_infos = self.command_infos.*;
        const old_owned_active_tools = self.owned_active_tools.*;
        var old_dynamic_catalog = self.live.dynamic_catalog_snapshot;
        self.live.dynamic_catalog_snapshot = null;

        self.host.* = new_host;
        self.bridge.* = new_bridge;
        self.bridge.host = self.host;
        self.provider_registry.* = new_provider_registry;
        self.extension_oauth.registry = self.provider_registry;
        self.provider_stream.registry = self.provider_registry;
        self.provider_models.commitPreparedRegistry(self.provider_registry, &provider_models_preparation);
        var provider_refresh: ?extensions.provider_models.RefreshResult = self.provider_models.refresh(.{
            .allow_network = false,
            .abort_flag = self.shared_abort,
        }) catch |err| blk: {
            if (self.action_runtime.render_output) {
                var warning_buffer: [512]u8 = undefined;
                const warning = std.fmt.bufPrint(&warning_buffer, "warning: cached extension model restore after reload failed: {s}", .{@errorName(err)}) catch null;
                if (warning) |message| tui.render.printLine(self.io, message) catch {};
            }
            break :blk null;
        };
        defer if (provider_refresh) |*result| result.deinit();
        if (provider_refresh) |result| self.action_runtime.reportProviderRefreshErrors(result.errors);
        provider_runtime_registries_committed = true;
        self.theme_registry.* = new_themes;
        self.prompt_templates.* = new_prompts;
        self.schemas.* = new_schemas;
        self.command_names.* = new_command_names;
        self.command_infos.* = new_command_infos;
        self.active_filter.* = new_filter;
        self.owned_active_tools.* = new_owned_active_tools;

        if (fresh_catalog_snapshot) |*snapshot| {
            self.live.dynamic_catalog_snapshot = snapshot.*;
            self.baseline_catalog = self.live.dynamic_catalog_snapshot.?.model_catalog;
            self.baseline_runtimes = self.live.dynamic_catalog_snapshot.?.runtime_configs;
            fresh_catalog_committed = true;
        }

        self.live.model_catalog = self.provider_registry.catalog();
        if (self.live.client_pool) |pool| {
            pool.setModelCatalog(self.provider_registry.catalog());
            pool.setRuntimeProviders(self.provider_registry.runtimes());
        }
        self.live.agent_cfg.tool_filter = self.active_filter.*;
        self.live.agent_cfg.max_turns = fresh_settings.max_turns;
        self.live.agent_cfg.auto_compaction_enabled = fresh_settings.compaction_enabled orelse true;
        self.live.agent_cfg.compaction_reserve_tokens = fresh_settings.compaction_reserve_tokens orelse 16_384;
        self.live.agent_cfg.compaction_keep_recent_tokens = fresh_settings.compaction_keep_recent_tokens orelse 20_000;
        self.live.agent_cfg.branch_summary_reserve_tokens = fresh_settings.branch_summary_reserve_tokens orelse 16_384;
        self.live.agent_cfg.branch_summary_skip_prompt = fresh_settings.branch_summary_skip_prompt orelse false;
        self.live.agent_cfg.auto_resize_images = fresh_settings.auto_resize_images orelse true;
        self.live.agent_cfg.block_images = fresh_settings.block_images orelse false;
        self.live.agent_cfg.enable_skill_commands = fresh_settings.enable_skill_commands orelse true;
        self.live.agent_cfg.compaction_context_window = if (coding.live_state.activeModelInfo(self.live)) |active|
            active.context_window
        else
            0;
        self.live.agent_cfg.retry_enabled = fresh_settings.retry_enabled orelse true;
        self.live.agent_cfg.retry_max_retries = fresh_settings.retry_max_retries orelse 3;
        self.live.agent_cfg.retry_base_delay_ms = fresh_settings.retry_base_delay_ms orelse 2_000;
        self.live.agent_cfg.steering_mode = queueModeFromSettings(fresh_settings.steering_mode);
        self.live.agent_cfg.follow_up_mode = queueModeFromSettings(fresh_settings.follow_up_mode);
        self.tree_filter_mode.* = treeFilterFromSettings(fresh_settings.tree_filter_mode);
        if (self.render_options) |options| {
            options.show_images = fresh_settings.show_images orelse true;
            options.image_width_cells = @intCast(@min(fresh_settings.image_width_cells orelse 60, std.math.maxInt(u32)));
            options.show_terminal_progress = fresh_settings.show_terminal_progress orelse false;
            options.output_pad = @intCast(@min(fresh_settings.output_pad orelse 1, 1));
            options.editor_padding_x = @intCast(@min(fresh_settings.editor_padding_x orelse 0, 3));
            options.show_hardware_cursor = fresh_settings.show_hardware_cursor orelse false;
        }
        configureExtensionCallbacks(
            self.live.agent_cfg,
            self.bridge,
            self.action_runtime,
            self.schemas.*,
            self.host.extensions.items.len > 0,
        );

        // The action runtime points at stable stack variables; replacing their
        // contents is enough, but keep these assignments explicit for embedders.
        self.action_runtime.host = self.host;
        self.action_runtime.bridge = self.bridge;
        self.action_runtime.provider_registry = self.provider_registry;
        self.action_runtime.provider_models = self.provider_models;
        self.action_runtime.active_filter = self.active_filter;
        self.action_runtime.owned_active_tools = self.owned_active_tools;
        self.action_runtime.extension_schemas = self.schemas;

        if (self.settings_text) |slot| {
            const old_text = slot.*;
            slot.* = new_settings_text.?;
            gpa.free(old_text);
        }
        if (keybindings_ready) {
            var old_keybindings = self.keybindings.?.*;
            self.keybindings.?.* = new_keybindings.?;
            new_keybindings = null;
            old_keybindings.deinit();
        }

        old_bridge.deinit();
        old_command_names.deinit(gpa);
        old_command_infos.deinit(gpa);
        deinitPromptTemplateSlice(gpa, old_prompts);
        gpa.free(old_schemas);
        old_provider_registry.deinit();
        old_host.deinit();
        old_theme_registry.deinit();
        if (old_owned_active_tools) |names| freeOwnedToolNames(gpa, names);
        if (old_dynamic_catalog) |*snapshot| snapshot.deinit();

        if (fresh_settings.theme) |theme_name| {
            if (self.theme_registry.find(theme_name)) |theme| tui.render.setTheme(theme);
        }

        if (self.host.extensions.items.len > 0) {
            self.bridge.sessionStart(gpa, self.cwd, self.session.id, "reload") catch |err| {
                var buffer: [256]u8 = undefined;
                const warning = std.fmt.bufPrint(&buffer, "warning: extension session_start after reload failed: {s}", .{@errorName(err)}) catch "warning: extension session_start after reload failed";
                if (std.mem.eql(u8, self.mode, "tui")) tui.render.printLine(self.io, warning) catch {};
            };
            self.flushLifecycleActions();
        }

        return .{
            .extensions = self.host.extensions.items.len,
            .commands = self.command_names.items.len,
            .prompts = self.prompt_templates.*.len,
            .themes = self.theme_registry.themes.items.len,
            .keybindings_reloaded = keybindings_ready,
            .settings_reloaded = true,
            .models_reloaded = fresh_catalog_snapshot != null,
            .credentials_reloaded = self.live.client_pool != null,
        };
    }
};

const ExtensionShortcutContext = struct {
    host: *extensions.Host,
    ui_controller: *extensions.ui.Controller,
    editor: *tui.editor.Editor,
    bindings: *const tui.keybindings.Manager,
    clipboard_store: *coding.clipboard.TempStore,
    io: Io,
    environ: *const std.process.Environ.Map,
    mode: []const u8,
    cwd: []const u8,
    session: *agent.session.Session,
    provider: *?[]const u8,
    model_id: *?[]const u8,
    thinking_level: *?[]const u8,
    project_trusted: bool,
    tool_filter: *agent.tools.ToolFilter,
    disable_builtin_tools: bool,
    model_catalog: []const ai.providers.ModelInfo,
    configured_providers: []const []const u8,
    session_file: ?[]const u8,
    session_dir: ?[]const u8,
    pending: ?extensions.host.CommandOutput = null,

    fn deinit(self: *ExtensionShortcutContext) void {
        if (self.pending) |*output| output.deinit(self.host.gpa);
        self.* = undefined;
    }

    fn take(self: *ExtensionShortcutContext) ?extensions.host.CommandOutput {
        const output = self.pending;
        self.pending = null;
        return output;
    }

    fn handle(raw: *anyopaque, allocator: std.mem.Allocator, key_id: []const u8) !tui.line_editor.ShortcutResult {
        const self: *ExtensionShortcutContext = @ptrCast(@alignCast(raw));

        // Match upstream precedence: extension shortcuts get first refusal.
        if (self.host.hasShortcut(key_id)) {
            try syncExtensionScriptContext(
                self.host,
                self.ui_controller,
                self.mode,
                self.cwd,
                self.session,
                self.provider.*,
                self.model_id.*,
                self.thinking_level.*,
                self.project_trusted,
                self.editor.slice(),
                self.tool_filter.*,
                self.disable_builtin_tools,
                self.model_catalog,
                self.configured_providers,
                self.session_file,
                self.session_dir,
            );
            if (self.pending) |*old| old.deinit(self.host.gpa);
            self.pending = try self.host.executeShortcut(key_id);
            return if (self.pending != null) .handled_interrupt else .not_handled;
        }

        if (!self.bindings.matches(key_id, .clipboard_paste)) return .not_handled;
        return ExtensionShortcutContext.pasteClipboard(self, allocator);
    }

    fn pasteClipboard(raw: *anyopaque, allocator: std.mem.Allocator) !tui.line_editor.ShortcutResult {
        _ = allocator;
        const self: *ExtensionShortcutContext = @ptrCast(@alignCast(raw));
        var paste = coding.clipboard.readPaste(self.host.gpa, self.io, .{
            .environ = self.environ,
        }) catch return .handled_continue;
        if (paste == null) return .handled_continue;
        defer paste.?.deinit(self.host.gpa);

        switch (paste.?) {
            .text => |text| {
                const normalized = tui.line_editor.normalizePasteAlloc(self.host.gpa, text) catch return .handled_continue;
                defer self.host.gpa.free(normalized);
                if (normalized.len > 0) try self.editor.insert(normalized);
            },
            .image => |image| {
                const path = self.clipboard_store.saveImage(image) catch return .handled_continue;
                const reference = coding.clipboard.formatAttachmentReference(self.host.gpa, path) catch return .handled_continue;
                defer self.host.gpa.free(reference);
                const before = self.editor.slice();
                if (self.editor.cursor > 0 and !std.ascii.isWhitespace(before[self.editor.cursor - 1])) try self.editor.insert(" ");
                try self.editor.insert(reference);
                const after = self.editor.slice();
                if (self.editor.cursor == after.len or !std.ascii.isWhitespace(after[self.editor.cursor])) try self.editor.insert(" ");
            },
        }
        return .handled_continue;
    }
};

fn formatExtensionCommandRpcData(
    allocator: std.mem.Allocator,
    name: []const u8,
    output: *const extensions.host.CommandOutput,
) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();
    try writer.writer.writeAll("{\"handled\":true,\"command\":");
    try std.json.Stringify.value(name, .{}, &writer.writer);
    try writer.writer.writeAll(",\"message\":");
    if (output.message) |message| try std.json.Stringify.value(message, .{}, &writer.writer) else try writer.writer.writeAll("null");
    try writer.writer.print(",\"isError\":{s},\"terminate\":{s}}}", .{
        if (output.is_error) "true" else "false",
        if (output.terminate) "true" else "false",
    });
    return try writer.toOwnedSlice();
}

fn loadStoredApiKey(
    allocator: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    provider_id: []const u8,
) !?[]u8 {
    var store = try auth.AuthStorage.init(allocator, io, agent_dir);
    defer store.deinit();
    var credential = (try store.read(provider_id)) orelse return null;
    defer credential.deinit(allocator);
    return switch (credential) {
        .api_key => |api_key| if (api_key.key) |key| blk: {
            var resolver = coding.config_value.Resolver.init(allocator, io, environ);
            defer resolver.deinit();
            break :blk try resolver.resolve(key);
        } else null,
        .oauth => |oauth_credential| try allocator.dupe(u8, oauth_credential.access),
    };
}

const InstallReportThreadContext = struct {
    io: Io,
    environ: *const std.process.Environ.Map,
    version: []u8,
    setting_proxy: ?[]u8,

    fn deinit(self: *@This()) void {
        const allocator = std.heap.page_allocator;
        allocator.free(self.version);
        if (self.setting_proxy) |value| allocator.free(value);
        allocator.destroy(self);
    }

    fn run(self: *@This()) void {
        defer self.deinit();
        _ = coding.update.reportInstall(std.heap.page_allocator, self.io, self.version, .{
            .timeout_ms = coding.update.install_report_timeout_ms,
            .retry = false,
            .environ = self.environ,
            .setting_proxy = self.setting_proxy,
        }) catch false;
    }
};

fn startInstallReport(
    io: Io,
    environ: *const std.process.Environ.Map,
    version: []const u8,
    setting_proxy: ?[]const u8,
) ?std.Thread {
    const allocator = std.heap.page_allocator;
    const context = allocator.create(InstallReportThreadContext) catch return null;
    context.* = .{
        .io = io,
        .environ = environ,
        .version = allocator.dupe(u8, version) catch {
            allocator.destroy(context);
            return null;
        },
        .setting_proxy = null,
    };
    if (setting_proxy) |value| {
        context.setting_proxy = allocator.dupe(u8, value) catch {
            allocator.free(context.version);
            allocator.destroy(context);
            return null;
        };
    }
    return std.Thread.spawn(.{}, InstallReportThreadContext.run, .{context}) catch {
        context.deinit();
        return null;
    };
}

fn runInteractiveReleaseLifecycle(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: ?[]const u8,
    settings: *const coding.settings.Settings,
    resumed: bool,
    explicit_offline: bool,
    install_report_thread: *?std.Thread,
) !void {
    var lifecycle = try coding.update.startupLifecycle(
        gpa,
        settings.last_changelog_version,
        config.upstream_version,
        resumed,
    );
    defer lifecycle.deinit(gpa);

    if (lifecycle.changelog) |changelog| {
        if (settings.collapse_changelog orelse false) {
            const notice = try std.fmt.allocPrint(gpa, "Updated to upstream Pi v{s}. Use /changelog to view the full changelog.", .{config.upstream_version});
            defer gpa.free(notice);
            try tui.render.printLine(io, notice);
        } else {
            try tui.render.printLine(io, "What's New");
            try tui.render.printLine(io, changelog);
        }
    }

    if (lifecycle.recorded_version) if (agent_dir) |dir| {
        coding.settings.setLastChangelogVersion(gpa, io, dir, config.upstream_version) catch {};
    };

    if (!explicit_offline and lifecycle.report_install and coding.update.telemetryEnabled(environ, settings.enable_install_telemetry) and !coding.update.offline(environ)) {
        install_report_thread.* = startInstallReport(io, environ, config.upstream_version, settings.http_proxy);
    }

    if (explicit_offline or !coding.update.shouldCheckVersion(environ)) return;
    var release = coding.update.getLatestRelease(gpa, io, config.upstream_version, .{
        .timeout_ms = coding.update.startup_version_timeout_ms,
        .retry = false,
        .environ = environ,
        .setting_proxy = settings.http_proxy,
    }) catch return;
    if (release) |*latest| {
        defer latest.deinit(gpa);
        if (!coding.update.isNewerPackageVersion(latest.version, config.upstream_version)) return;
        const notice = try std.fmt.allocPrint(
            gpa,
            "Upstream Pi update available: v{s} (this Zig port targets v{s}).",
            .{ latest.version, config.upstream_version },
        );
        defer gpa.free(notice);
        try tui.render.printLine(io, notice);
        if (latest.note) |note| try tui.render.printLine(io, note);
        try tui.render.printLine(io, "Changelog: https://pi.dev/changelog");
    }
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;
    const environ: *const std.process.Environ.Map = init.environ_map;

    const raw_args = try init.minimal.args.toSlice(arena);
    var cli = coding.args.parseArgs(arena, raw_args) catch |err| {
        const message = switch (err) {
            error.MissingArg => "error: an option is missing its required value",
            error.InvalidTuiMode => "error: --tui-mode requires regular or fullscreen",
            error.UnknownOption => "error: unknown short option",
            else => "error: invalid command-line arguments",
        };
        try tui.render.printLine(io, message);
        std.process.exit(2);
    };

    const explicit_cli_model = cli.model != null;
    const explicit_cli_thinking = cli.thinking != null;

    // Match the original CLI: redirected stdin supplies the initial prompt and
    // switches otherwise-interactive text mode to one-shot output. RPC owns
    // stdin as its JSONL transport and must never consume it here.
    const has_piped_stdin = cli.mode != .rpc and !(Io.File.stdin().isTty(io) catch true);
    if (has_piped_stdin and cli.mode == .text and !cli.print) cli.print = true;

    if (cli.help) {
        var buf: [64]u8 = undefined;
        var stdout: Io.File.Writer = .init(.stdout(), io, &buf);
        try coding.args.printHelp(&stdout.interface);
        try stdout.interface.flush();
        return;
    }
    if (cli.version) {
        try tui.render.printLine(io, config.identity);
        return;
    }

    // Run the original one-time compatibility migrations before any command
    // reads settings, sessions or credentials. They are deliberately silent
    // for machine-readable subcommands; interactive startup reports warnings
    // after the renderer is initialized below.
    const cwd = try std.process.currentPathAlloc(io, arena);
    const agent_dir: ?[]const u8 = config.agentDir(arena, environ) catch null;
    var startup_migrations: ?coding.migrations.Result = null;
    defer if (startup_migrations) |*migration_result| migration_result.deinit();
    if (agent_dir) |ad| startup_migrations = coding.migrations.run(gpa, io, ad, cwd) catch null;

    // Package / monorepo C subcommands
    if (cli.command) |cmd| {
        if (std.mem.eql(u8, cmd, "install") or std.mem.eql(u8, cmd, "list") or
            std.mem.eql(u8, cmd, "update") or std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "uninstall") or
            std.mem.eql(u8, cmd, "repair") or std.mem.eql(u8, cmd, "config"))
        {
            try runPackageCommand(gpa, io, environ, arena, cmd, cli.command_args.items);
            return;
        }
        try runSurfaceCommand(gpa, io, environ, arena, cmd, cli.command_args.items);
        return;
    }

    // Resolve project trust before loading any project-local executable/config resource.
    // Only global settings may choose the default trust policy.
    var startup_settings = try coding.settings.loadMergeTrusted(gpa, io, agent_dir, cwd, false);
    defer startup_settings.deinit(gpa);
    const trust_project = try resolveStartupProjectTrust(gpa, io, environ, agent_dir, cwd, cli.approve, startup_settings.default_project_trust, !cli.print and cli.mode == .text);

    // Settings
    var settings = try coding.settings.loadMergeTrusted(gpa, io, agent_dir, cwd, trust_project);
    defer settings.deinit(gpa);

    // Resolve installed package resources once for the whole startup. Package
    // resources intentionally follow local global/project resources in
    // precedence, matching the original package manager's ordering.
    const installed_packages = if (agent_dir) |ad|
        try coding.packages.listConfigured(gpa, io, ad, cwd, trust_project)
    else
        try gpa.alloc(coding.packages.Package, 0);
    defer {
        for (installed_packages) |*package| package.deinit(gpa);
        gpa.free(installed_packages);
    }
    var package_resources = try coding.packages.resolveResources(gpa, io, installed_packages);
    defer package_resources.deinit();
    var top_level_resources = if (agent_dir) |ad|
        try coding.top_level_resources.resolve(gpa, io, ad, cwd, trust_project)
    else
        coding.top_level_resources.Resources.init(gpa);
    defer top_level_resources.deinit();

    if (!cli.print and cli.mode == .text) if (agent_dir) |ad| {
        var user_health = coding.packages.inspectScopeHealth(gpa, io, ad, cwd, .user, trust_project) catch null;
        if (user_health) |*health| {
            defer health.deinit();
            try reportPackageHealthWarning(io, arena, .user, health);
        }
        if (trust_project) {
            var project_health = coding.packages.inspectScopeHealth(gpa, io, ad, cwd, .project, true) catch null;
            if (project_health) |*health| {
                defer health.deinit();
                try reportPackageHealthWarning(io, arena, .project, health);
            }
        }
    };

    if (!cli.print and cli.mode == .text) if (startup_migrations) |migration_result| {
        if (migration_result.migrated_auth_providers.items.len > 0) {
            var joined: Io.Writer.Allocating = .init(arena);
            for (migration_result.migrated_auth_providers.items, 0..) |provider_name, index| {
                if (index > 0) try joined.writer.writeAll(", ");
                try joined.writer.writeAll(provider_name);
            }
            const message = try std.fmt.allocPrint(arena, "Migrated credentials to auth.json: {s}", .{joined.written()});
            try tui.render.printLine(io, message);
        }
        for (migration_result.warnings.items) |warning| {
            const message = try std.fmt.allocPrint(arena, "warning: {s}", .{warning});
            try tui.render.printLine(io, message);
        }
    };

    // Theme resources use the same global-then-trusted-project precedence as the
    // original loader. `--no-themes` disables discovery but explicit --theme
    // paths remain enabled. The selected settings theme feeds the native renderer.
    var theme_registry = pi_zig.themes.Registry.init(gpa, io);
    defer theme_registry.deinit();
    defer tui.render.resetTheme();
    if (!cli.no_themes) for (top_level_resources.themes.items) |theme_path| {
        theme_registry.loadPath(theme_path) catch |err| {
            const warning = try std.fmt.allocPrint(arena, "warning: top-level theme {s} could not be loaded: {s}", .{ theme_path, @errorName(err) });
            try tui.render.printLine(io, warning);
        };
    };
    if (!cli.no_themes) for (package_resources.themes.items) |theme_path| {
        theme_registry.loadPath(theme_path) catch |err| {
            const warning = try std.fmt.allocPrint(arena, "warning: package theme {s} could not be loaded: {s}", .{ theme_path, @errorName(err) });
            try tui.render.printLine(io, warning);
        };
    };
    for (cli.themes.items) |theme_arg| {
        const theme_path = try coding.path_utils.resolveReadPath(gpa, io, environ, theme_arg, cwd);
        defer gpa.free(theme_path);
        theme_registry.loadPath(theme_path) catch |err| {
            const message = switch (err) {
                error.ThemePathNotFound => "warning: explicit theme path was not found",
                error.UnsupportedThemePath => "warning: theme paths must be JSON files or directories",
                else => "warning: could not load explicit theme path",
            };
            try tui.render.printLine(io, message);
        };
    }
    for (theme_registry.diagnostics.items) |diagnostic| {
        const message = try std.fmt.allocPrint(arena, "warning: {s}: {s}", .{ diagnostic.path, diagnostic.message });
        try tui.render.printLine(io, message);
    }
    if (settings.theme) |theme_name| {
        if (theme_registry.find(theme_name)) |active_theme| {
            tui.render.setTheme(active_theme);
        } else if (!std.mem.eql(u8, theme_name, "default") and !std.mem.eql(u8, theme_name, "dark") and std.mem.indexOfScalar(u8, theme_name, '/') == null) {
            const message = try std.fmt.allocPrint(arena, "warning: configured theme was not found: {s}", .{theme_name});
            try tui.render.printLine(io, message);
        }
    }

    // Upstream models.json: arbitrary provider IDs mapped to a native transport.
    var models_file: coding.models_file.ModelsFile = if (agent_dir) |ad|
        try coding.models_file.load(arena, io, ad)
    else
        .{ .gpa = arena };
    defer models_file.deinit();

    // Restore persisted Radius catalogs without network access, then compose one
    // credential-blind effective catalog. Keep the owned dynamic catalogs alive
    // for as long as their ModelInfo slices are referenced by the runtime.
    var radius_cached_catalogs: coding.radius_cached_catalogs.Set = if (agent_dir) |ad|
        try coding.radius_cached_catalogs.load(gpa, io, ad, &models_file)
    else
        .{};
    defer radius_cached_catalogs.deinit(gpa);
    const unfiltered_model_catalog = try coding.effective_catalog.buildWithExtras(arena, &models_file, radius_cached_catalogs.infos);
    var copilot_catalog = try coding.copilot_catalog_filter.load(arena, io, agent_dir, unfiltered_model_catalog);
    defer copilot_catalog.deinit();
    const model_catalog = copilot_catalog.infos;

    if (cli.list_models) {
        try listModels(arena, io, cli.list_models_query, model_catalog);
        return;
    }

    // `--models` scopes interactive/RPC model cycling without restricting an
    // explicitly selected startup model. Empty scopes fall back to the full
    // catalog, matching the original selector behavior.
    var cycling_model_catalog: []const ai.providers.ModelInfo = model_catalog;
    var model_scope_storage: ?coding.model_resolver.ScopeResult = null;
    defer if (model_scope_storage) |*scope| scope.deinit(gpa);
    if (cli.models) |patterns| {
        model_scope_storage = try coding.model_resolver.resolveModelScopeFromModels(gpa, patterns, model_catalog);
        const scope = &model_scope_storage.?;
        for (scope.diagnostics) |diagnostic| {
            const warning = switch (diagnostic.code) {
                .no_match => try std.fmt.allocPrint(arena, "warning: --models pattern matched no model: {s}", .{diagnostic.pattern}),
                .invalid_thinking_level => try std.fmt.allocPrint(arena, "warning: invalid thinking suffix in --models pattern: {s}", .{diagnostic.pattern}),
            };
            try tui.render.printLine(io, warning);
        }
        if (scope.scoped_models.len > 0) {
            const scoped_infos = try arena.alloc(ai.providers.ModelInfo, scope.scoped_models.len);
            for (scope.scoped_models, 0..) |scoped, index| scoped_infos[index] = scoped.model;
            cycling_model_catalog = scoped_infos;
        }
    }

    // Resolve provider / model / keys. Public provider identity is kept
    // separately from the native transport so custom IDs never collapse to
    // "openai"/"anthropic"/"google".
    var provider = ai.resolveProvider(cli.provider orelse settings.provider, environ);
    var provider_id: []const u8 = provider.name();
    const requested_provider = cli.provider orelse settings.provider orelse environ.get(config.ENV_PROVIDER);
    if (requested_provider) |raw_provider| {
        if (models_file.findProvider(raw_provider)) |configured_provider| {
            provider_id = configured_provider.id;
            if (configured_provider.models.len > 0) {
                provider = configured_provider.models[0].info.provider;
            } else if (configured_provider.api) |api| {
                provider = api.nativeProvider();
            } else if (ai.Provider.fromString(raw_provider)) |builtin| {
                provider = builtin;
            }
        }
    }

    if (cli.model) |cli_model| {
        var configured_list: std.ArrayList([]const u8) = .empty;
        defer configured_list.deinit(arena);

        var explicit_key_provider_id: ?[]const u8 = null;
        if (cli.api_key != null) {
            if (cli.provider) |pname| {
                explicit_key_provider_id = pname;
            } else if (std.mem.indexOfScalar(u8, cli_model, '/')) |slash| {
                explicit_key_provider_id = cli_model[0..slash];
            }
        }

        inline for (std.meta.fields(ai.Provider)) |field| {
            const candidate: ai.Provider = @enumFromInt(field.value);
            var configured = switch (candidate) {
                .ollama, .lmstudio, .vllm, .mock => true,
                else => ai.providers.hasUsableCredential(
                    candidate,
                    if (explicit_key_provider_id != null and std.ascii.eqlIgnoreCase(explicit_key_provider_id.?, candidate.name())) cli.api_key else null,
                    environ,
                ),
            };
            if (!configured and agent_dir != null) {
                configured = (try loadStoredApiKey(arena, io, environ, agent_dir.?, candidate.name())) != null;
                // Legacy KEY=value credentials remain read-only migration fallback.
                if (!configured) {
                    if (ai.providers.credentialEnvName(candidate)) |key_name| {
                        configured = (try coding.settings.loadCredential(arena, io, agent_dir.?, key_name)) != null;
                    }
                }
            }
            if (configured) try configured_list.append(arena, candidate.name());
        }

        // Dynamic providers are configured by CLI key, auth.json, or models.json apiKey.
        for (models_file.providers) |configured_provider| {
            var configured = explicit_key_provider_id != null and
                std.ascii.eqlIgnoreCase(explicit_key_provider_id.?, configured_provider.id) and cli.api_key != null;
            if (!configured and agent_dir != null) {
                configured = (try loadStoredApiKey(arena, io, environ, agent_dir.?, configured_provider.id)) != null;
            }
            if (!configured) {
                if (configured_provider.api_key) |key_config| {
                    var resolver = coding.config_value.Resolver.init(arena, io, environ);
                    defer resolver.deinit();
                    configured = (try resolver.resolve(key_config)) != null;
                }
            }
            if (configured) try configured_list.append(arena, configured_provider.id);
        }

        const requested_thinking = if (cli.thinking) |level| coding.model_resolver.parseThinkingLevel(level) else null;
        const resolved = coding.model_resolver.resolveCliModel(
            cli.provider,
            cli.model,
            requested_thinking,
            model_catalog,
            configured_list.items,
        );
        if (resolved.err) |resolve_err| {
            const msg = switch (resolve_err) {
                .no_models => "error: no models available",
                .unknown_provider => "error: unknown provider; use --list-models",
                .ambiguous_model => "error: model id is ambiguous across providers; use --provider or provider/model",
                .model_not_found => "error: model not found; use --list-models",
            };
            try tui.render.printLine(io, msg);
            std.process.exit(2);
        }
        if (resolved.model) |resolved_model| {
            provider = resolved_model.provider;
            provider_id = resolved_model.providerName();
            cli.model = resolved_model.id;
        }
        if (cli.thinking == null) {
            if (resolved.thinking_level) |level| cli.thinking = @tagName(level);
        }
        if (resolved.warning == .custom_model_id) {
            try tui.render.printLine(io, "warning: model is not in the catalog; using the explicit custom model id");
        }
    }

    if (cli.mock_script == null) {
        if (environ.get(config.ENV_MOCK_SCRIPT)) |p| cli.mock_script = p;
    }
    if (cli.mock_script != null) {
        provider = .mock;
        provider_id = "mock";
    }
    if (cli.offline and cli.mock_script == null) {
        try tui.render.printLine(io, "error: --offline requires --mock-script <file> or PI_MOCK_SCRIPT");
        std.process.exit(2);
    }

    const selected_provider_config = models_file.findProvider(provider_id);
    var model: ?[]const u8 = cli.model orelse settings.model orelse environ.get(config.ENV_MODEL);
    if (model == null) {
        if (selected_provider_config) |configured_provider| {
            if (configured_provider.models.len > 0) model = configured_provider.models[0].info.id;
        }
    }
    // Dynamic Radius providers intentionally have no static models array. Prefer
    // their restored provider catalog before falling back to a transport default.
    if (model == null) {
        for (model_catalog) |candidate| {
            if (std.ascii.eqlIgnoreCase(candidate.providerName(), provider_id)) {
                model = candidate.id;
                break;
            }
        }
    }
    if (model == null) model = ai.providers.defaultModel(provider);

    const selected_model_config = if (selected_provider_config != null and model != null)
        models_file.findModel(provider_id, model.?)
    else
        null;
    if (selected_model_config) |configured_model| {
        if (!configured_model.api.runtimeSupported()) {
            try tui.render.printLine(io, "error: selected models.json API is recognized but its native transport is not ported yet");
            std.process.exit(2);
        }
    }

    var provider_name: ?[]const u8 = try arena.dupe(u8, provider_id);

    // Resolve the selected effective model through the same owned runtime
    // configuration path used by the server. Explicit unknown built-in model
    // IDs remain supported by synthesizing only their identity/transport.
    var selected_model_info = ai.providers.ModelInfo{
        .provider = provider,
        .provider_id = if (ai.Provider.fromString(provider_id) == null) provider_id else null,
        .id = model.?,
        .display = model.?,
    };
    for (model_catalog) |candidate| {
        if (std.ascii.eqlIgnoreCase(candidate.providerName(), provider_id) and std.mem.eql(u8, candidate.id, model.?)) {
            selected_model_info = candidate;
            break;
        }
    }
    // Public providers such as GitHub Copilot can mix native transports under a
    // single identity. Dispatch the selected catalog model through its actual
    // wire provider rather than the identity provider's default transport.
    provider = selected_model_info.provider;
    var primary_runtime = try coding.runtime_config.resolveForModel(gpa, io, environ, &models_file, selected_model_info, .{
        .agent_dir = agent_dir,
        .explicit_api_key = cli.api_key,
        .explicit_base_url = cli.base_url,
    });
    defer primary_runtime.deinit();
    var api_key: ?[]const u8 = primary_runtime.api_key;
    var base_url: []const u8 = primary_runtime.base_url;

    // Session directory
    const session_dir = try config.sessionDirForCwd(arena, environ, cwd, cli.session_dir);
    if (!cli.no_session) {
        config.ensureDir(io, session_dir) catch {};
    }

    if (cli.fork != null and (cli.session != null or cli.continue_session or cli.resume_session or cli.no_session)) {
        try tui.render.printLine(io, "error: --fork cannot be combined with --session, --continue, --resume, or --no-session");
        std.process.exit(2);
    }
    if (cli.session_id) |explicit_id| {
        if (cli.session != null or cli.continue_session or cli.resume_session) {
            try tui.render.printLine(io, "error: --session-id cannot be combined with --session, --continue, or --resume");
            std.process.exit(2);
        }
        agent.session.validateSessionId(explicit_id) catch {
            try tui.render.printLine(io, "error: session id must use alphanumeric characters with '.', '_', or '-' only, and begin/end alphanumerically");
            std.process.exit(2);
        };
    }

    // Session load / create
    var sess = try agent.session.Session.init(gpa, "pending", cwd);
    defer sess.deinit();
    var session_path: ?[]const u8 = null;

    if (cli.fork) |fork_src| {
        const src_path = try resolveSessionPath(arena, io, session_dir, fork_src);
        var loaded = agent.session.Session.load(gpa, io, src_path) catch {
            try tui.render.printLine(io, "error: could not fork session");
            std.process.exit(2);
        };
        defer loaded.deinit();
        if (cli.session_id) |target_id| {
            if (try agent.session.findExactSessionPath(gpa, io, session_dir, target_id)) |existing| {
                gpa.free(existing);
                try tui.render.printLine(io, "error: a session already exists with the requested --session-id");
                std.process.exit(2);
            }
        }
        sess.deinit();
        const new_id = cli.session_id orelse try agent.session.generateSessionId(arena);
        sess = try loaded.fork(gpa, new_id);
        try sess.setParentSession(src_path);
        session_path = try agent.session.newSessionPath(arena, session_dir, new_id);
    } else if (cli.session) |sp| {
        const path = try resolveSessionPath(arena, io, session_dir, sp);
        if (agent.session.Session.load(gpa, io, path)) |loaded| {
            sess.deinit();
            sess = loaded;
            session_path = path;
        } else |_| {
            // new session at path
            const id = try agent.session.generateSessionId(arena);
            gpa.free(sess.id);
            sess.id = try gpa.dupe(u8, id);
            session_path = path;
        }
    } else if (cli.session_id) |explicit_id| {
        if (cli.no_session) {
            gpa.free(sess.id);
            sess.id = try gpa.dupe(u8, explicit_id);
        } else if (try agent.session.findExactSessionPath(gpa, io, session_dir, explicit_id)) |exact_path| {
            defer gpa.free(exact_path);
            const loaded = agent.session.Session.load(gpa, io, exact_path) catch {
                try tui.render.printLine(io, "error: could not open the exact --session-id session");
                std.process.exit(2);
            };
            sess.deinit();
            sess = loaded;
            session_path = try arena.dupe(u8, exact_path);
        } else {
            try tui.render.printLine(io, "warning: no project session has the requested id; creating it");
            gpa.free(sess.id);
            sess.id = try gpa.dupe(u8, explicit_id);
            session_path = try agent.session.newSessionPath(arena, session_dir, explicit_id);
        }
    } else if (cli.continue_session) {
        if (try agent.session.mostRecentSessionPath(arena, io, session_dir)) |path| {
            if (agent.session.Session.load(gpa, io, path)) |loaded| {
                sess.deinit();
                sess = loaded;
                session_path = path;
            } else |_| {}
        }
    } else if (cli.resume_session) {
        const sessions = try agent.session.listSessions(gpa, io, session_dir);
        defer {
            for (sessions) |*info| info.deinit(gpa);
            gpa.free(sessions);
        }
        if (sessions.len > 0) {
            var selected_path: ?[]u8 = null;
            defer if (selected_path) |value| gpa.free(value);
            const can_select = !cli.print and cli.mode == .text and !has_piped_stdin and
                (Io.File.stdin().isTty(io) catch false) and (Io.File.stdout().isTty(io) catch false);
            if (can_select) {
                const all_sessions_root = if (cli.session_dir != null)
                    session_dir
                else if (agent_dir) |ad|
                    try std.fs.path.join(arena, &.{ ad, "sessions" })
                else
                    session_dir;
                var selection = try coding.session_tui.run(gpa, io, environ, null, .{
                    .session_dir = session_dir,
                    .all_sessions_root = all_sessions_root,
                    .required_cwd = null,
                });
                defer selection.deinit(gpa);
                if (selection.cancelled or selection.path == null) return;
                selected_path = try gpa.dupe(u8, selection.path.?);
            } else {
                selected_path = try gpa.dupe(u8, sessions[0].path);
            }
            const loaded = agent.session.Session.load(gpa, io, selected_path.?) catch {
                try tui.render.printLine(io, "error: selected session could not be loaded");
                std.process.exit(2);
            };
            sess.deinit();
            sess = loaded;
            session_path = try arena.dupe(u8, selected_path.?);
        } else if (!cli.no_session) {
            const id = try agent.session.generateSessionId(arena);
            gpa.free(sess.id);
            sess.id = try gpa.dupe(u8, id);
            session_path = try agent.session.newSessionPath(arena, session_dir, id);
        }
    } else if (!cli.no_session) {
        const id = try agent.session.generateSessionId(arena);
        gpa.free(sess.id);
        sess.id = try gpa.dupe(u8, id);
        session_path = try agent.session.newSessionPath(arena, session_dir, id);
    } else {
        // Ephemeral session still needs a real id for JSON/RPC session headers.
        const id = try agent.session.generateSessionId(arena);
        gpa.free(sess.id);
        sess.id = try gpa.dupe(u8, id);
    }

    if (cli.name) |n| try sess.setName(n);

    // Restore the model and thinking level from the active session branch when
    // the user did not explicitly override them. For a genuinely new session,
    // --models chooses the saved default when in scope, otherwise the first
    // scoped model and its optional thinking suffix.
    const saved_session_settings = try sess.activeSettings(arena);
    var startup_scoped_thinking: ?ai.thinking.ThinkingLevel = null;
    var startup_candidate: ?ai.providers.ModelInfo = null;

    if (!explicit_cli_model and cli.mock_script == null and saved_session_settings.has_messages) {
        if (saved_session_settings.provider != null and saved_session_settings.model_id != null) {
            for (model_catalog) |candidate| {
                if (std.ascii.eqlIgnoreCase(candidate.providerName(), saved_session_settings.provider.?) and
                    std.mem.eql(u8, candidate.id, saved_session_settings.model_id.?))
                {
                    startup_candidate = candidate;
                    break;
                }
            }
            if (startup_candidate == null) {
                const warning = try std.fmt.allocPrint(arena, "warning: could not restore session model {s}/{s}; using {s}/{s}", .{
                    saved_session_settings.provider.?,
                    saved_session_settings.model_id.?,
                    provider_id,
                    model.?,
                });
                try tui.render.printLine(io, warning);
            }
        }
    } else if (!explicit_cli_model and !saved_session_settings.has_messages and model_scope_storage != null and model_scope_storage.?.scoped_models.len > 0) {
        const scope = model_scope_storage.?.scoped_models;
        for (scope) |scoped| {
            if (std.ascii.eqlIgnoreCase(scoped.model.providerName(), provider_id) and std.mem.eql(u8, scoped.model.id, model.?)) {
                startup_candidate = scoped.model;
                startup_scoped_thinking = scoped.thinking_level;
                break;
            }
        }
        if (startup_candidate == null) {
            startup_candidate = scope[0].model;
            startup_scoped_thinking = scope[0].thinking_level;
        }
    }

    if (startup_candidate) |candidate| {
        primary_runtime.deinit();
        selected_model_info = candidate;
        provider = candidate.provider;
        provider_id = candidate.providerName();
        model = candidate.id;
        provider_name = try arena.dupe(u8, provider_id);
        primary_runtime = try coding.runtime_config.resolveForModel(gpa, io, environ, &models_file, candidate, .{
            .agent_dir = agent_dir,
            .explicit_api_key = cli.api_key,
            .explicit_base_url = cli.base_url,
        });
        api_key = primary_runtime.api_key;
        base_url = primary_runtime.base_url;
    }

    if (!explicit_cli_thinking) {
        if (saved_session_settings.has_messages) {
            const restored_level = if (saved_session_settings.has_thinking_entry)
                ai.thinking.ThinkingLevel.parse(saved_session_settings.thinking_level orelse "off") orelse .off
            else if (settings.thinking_level) |configured|
                ai.thinking.ThinkingLevel.parse(configured) orelse .off
            else
                .off;
            cli.thinking = @tagName(selected_model_info.clampThinkingLevel(restored_level));
        } else if (startup_scoped_thinking) |scoped_level| {
            cli.thinking = @tagName(selected_model_info.clampThinkingLevel(scoped_level));
        }
    }

    // Extensions: native executable manifests and upstream JavaScript/TypeScript
    // modules are globally discoverable. Project extensions are executable
    // resources and therefore remain gated by project trust.
    const extension_mode: []const u8 = if (cli.mode == .rpc)
        "rpc"
    else if (cli.mode == .json)
        "json"
    else if (cli.print)
        "print"
    else
        "tui";
    const extension_has_ui = std.mem.eql(u8, extension_mode, "tui") and tui.line_editor.available(io);
    var extension_ui = try extensions.ui.Controller.init(
        gpa,
        io,
        extension_has_ui,
        tui.terminal.columnsFromEnvironment(environ, 100),
    );
    defer extension_ui.deinit();
    extension_ui.bindClipboardEnvironment(environ);
    var extension_stdin_buf: [4096]u8 = undefined;
    var extension_stdin_reader: Io.File.Reader = .init(.stdin(), io, &extension_stdin_buf);
    if (extension_has_ui) extension_ui.bindReader(&extension_stdin_reader);

    var extension_host = extensions.Host{
        .gpa = gpa,
        .io = io,
        .js_runtime_program = environ.get("PI_JS_RUNTIME") orelse "node",
        .script_ui_bridge = extension_ui.bridge(),
    };
    defer extension_host.deinit();
    if (!cli.no_extensions) for (top_level_resources.extensions.items) |extension_path| {
        extension_host.loadPath(extension_path) catch |err| {
            const warning = try std.fmt.allocPrint(arena, "warning: top-level extension {s} could not be loaded: {s}", .{ extension_path, @errorName(err) });
            try tui.render.printLine(io, warning);
        };
    };
    if (!cli.no_extensions) for (package_resources.extensions.items) |extension_path| {
        extension_host.loadPath(extension_path) catch |err| {
            const warning = try std.fmt.allocPrint(arena, "warning: package extension {s} could not be loaded: {s}", .{ extension_path, @errorName(err) });
            try tui.render.printLine(io, warning);
        };
    };
    for (cli.extensions.items) |extension_arg| {
        // The original --extension surface accepts local paths, npm specs and
        // Git URLs. Resolve every source through the temporary package scope so
        // managed network sources are cached for this process without mutating
        // user or project package configuration.
        const temporary_agent_dir = agent_dir orelse {
            const extension_path = try coding.path_utils.resolveReadPath(gpa, io, environ, extension_arg, cwd);
            defer gpa.free(extension_path);
            extension_host.loadPath(extension_path) catch |err| {
                const message = switch (err) {
                    error.ExtensionPathNotFound => "error: explicit extension path was not found",
                    error.ManifestNotFound => "error: explicit extension manifest was not found",
                    error.ManifestTooLarge => "error: explicit extension manifest exceeds 256 KiB",
                    error.UnsupportedExtensionPath => "error: extensions require a directory, JSON manifest, or JavaScript/TypeScript module",
                    else => "error: explicit extension is invalid or could not be loaded",
                };
                try tui.render.printLine(io, message);
                std.process.exit(2);
            };
            continue;
        };
        var temporary_package = coding.packages.installScopedWithOptions(
            gpa,
            io,
            temporary_agent_dir,
            cwd,
            extension_arg,
            .temporary,
            trust_project,
            .{
                .offline = packageOffline(environ, false),
                .npm_command = settings.npm_command,
            },
        ) catch |err| {
            const message = switch (err) {
                error.PackageNetworkDisabled => "error: explicit npm/Git extension is unavailable in offline mode",
                error.PackageCommandTimedOut => "error: explicit extension package command timed out",
                error.PackageCommandFailed => "error: explicit extension package command failed",
                error.PackageNotFound, error.PackageNotFoundAfterInstall => "error: explicit extension source was not found",
                error.InvalidPackageSource, error.InvalidGitPackageSource => "error: explicit extension source is invalid",
                else => "error: explicit extension source could not be resolved",
            };
            try tui.render.printLine(io, message);
            std.process.exit(2);
        };
        defer temporary_package.deinit(gpa);
        const temporary_packages = [_]coding.packages.Package{temporary_package};
        var temporary_resources = try coding.packages.resolveResources(gpa, io, &temporary_packages);
        defer temporary_resources.deinit();
        if (temporary_resources.extensions.items.len == 0) {
            try tui.render.printLine(io, "error: explicit extension source contains no loadable extensions");
            std.process.exit(2);
        }
        for (temporary_resources.extensions.items) |extension_path| {
            extension_host.loadPath(extension_path) catch |err| {
                const message = switch (err) {
                    error.ExtensionPathNotFound => "error: explicit extension path was not found",
                    error.ManifestNotFound => "error: explicit extension manifest was not found",
                    error.ManifestTooLarge => "error: explicit extension manifest exceeds 256 KiB",
                    error.UnsupportedExtensionPath => "error: extensions require a directory, JSON manifest, or JavaScript/TypeScript module",
                    error.DuplicateToolName => "error: explicit extension registers a duplicate tool name",
                    error.DuplicateCommandName => "error: explicit extension registers a duplicate slash command",
                    error.DuplicateFlagName => "error: explicit extension registers a duplicate CLI flag",
                    error.JavaScriptRuntimeNotFound => "error: Node.js is required to run JavaScript/TypeScript extensions",
                    error.InvalidJavaScriptExtensionHandshake => "error: JavaScript/TypeScript extension failed during registration",
                    error.JavaScriptExtensionTimeout => "error: JavaScript/TypeScript extension exceeded its startup deadline",
                    error.JavaScriptExtensionOutputTooLarge => "error: JavaScript/TypeScript extension wrote too much startup output",
                    else => "error: explicit extension is invalid or could not be loaded",
                };
                try tui.render.printLine(io, message);
                std.process.exit(2);
            };
        }
    }
    for (cli.unknown_flags.items) |flag| {
        extension_host.applyCliFlag(flag.name, flag.value) catch |err| {
            const message = switch (err) {
                error.UnknownExtensionFlag => try std.fmt.allocPrint(arena, "error: unknown option --{s}", .{flag.name}),
                error.ExtensionFlagRequiresValue => try std.fmt.allocPrint(arena, "error: extension flag --{s} requires a value", .{flag.name}),
                else => try std.fmt.allocPrint(arena, "error: could not apply extension flag --{s}", .{flag.name}),
            };
            try tui.render.printLine(io, message);
            std.process.exit(2);
        };
    }
    var extension_command_names: std.ArrayList([]const u8) = .empty;
    defer extension_command_names.deinit(gpa);
    var extension_command_infos: std.ArrayList(coding.rpc_data.ExtensionCommandInfo) = .empty;
    defer extension_command_infos.deinit(gpa);
    for (extension_host.extensions.items) |extension| {
        for (extension.commands) |command| {
            try extension_command_names.append(gpa, command.name);
            try extension_command_infos.append(gpa, .{
                .name = command.name,
                .description = command.description,
                .argument_hint = command.argument_hint,
                .extension_name = extension.name,
                .entry_path = extension.entry,
            });
        }
    }

    var explicit_prompt_paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (explicit_prompt_paths.items) |path| gpa.free(path);
        explicit_prompt_paths.deinit(gpa);
    }
    if (!cli.no_prompt_templates) for (top_level_resources.prompts.items) |top_prompt_path| {
        try explicit_prompt_paths.append(gpa, try gpa.dupe(u8, top_prompt_path));
    };
    if (!cli.no_prompt_templates) for (package_resources.prompts.items) |package_prompt_path| {
        try explicit_prompt_paths.append(gpa, try gpa.dupe(u8, package_prompt_path));
    };
    for (cli.prompt_templates.items) |prompt_path_arg| {
        const prompt_path = try coding.path_utils.resolveReadPath(gpa, io, environ, prompt_path_arg, cwd);
        if (!coding.path_utils.pathExists(io, prompt_path)) {
            const warning = try std.fmt.allocPrint(arena, "warning: explicit prompt-template path was not found: {s}", .{prompt_path_arg});
            try tui.render.printLine(io, warning);
            gpa.free(prompt_path);
            continue;
        }
        try explicit_prompt_paths.append(gpa, prompt_path);
    }
    var prompt_templates = try coding.prompts.loadTrusted(
        gpa,
        io,
        cwd,
        agent_dir,
        trust_project,
        explicit_prompt_paths.items,
        false,
    );
    defer {
        for (prompt_templates) |*template| template.deinit(gpa);
        gpa.free(prompt_templates);
    }

    var extension_bridge = extensions.integration.Bridge.init(&extension_host);
    defer extension_bridge.deinit();
    const extensions_active = extension_host.extensions.items.len > 0;
    // This filter is mutable because script extensions may change the active
    // tool set between turns through pi.setActiveTools().
    var active_tool_filter = agent.tools.ToolFilter{
        .allow = cli.tools orelse settings.tools,
        .exclude = cli.exclude_tools,
        .no_tools = cli.no_tools,
    };
    try syncExtensionScriptContext(
        &extension_host,
        &extension_ui,
        extension_mode,
        cwd,
        &sess,
        provider_name,
        model,
        cli.thinking orelse settings.thinking_level,
        trust_project,
        "",
        active_tool_filter,
        cli.no_builtin_tools,
        cycling_model_catalog,
        &.{},
        session_path,
        session_dir,
    );
    if (extensions_active) try extension_bridge.sessionStart(gpa, cwd, sess.id, "startup");
    defer {
        if (extension_host.extensions.items.len > 0) extension_bridge.sessionShutdown(gpa, cwd, sess.id, "quit") catch |err| {
            var buffer: [256]u8 = undefined;
            const warning = std.fmt.bufPrint(&buffer, "warning: extension session_shutdown failed: {s}", .{@errorName(err)}) catch "warning: extension session_shutdown failed";
            tui.render.printLine(io, warning) catch {};
        };
        flushFinalExtensionActions(gpa, io, &sess, &extension_bridge) catch |err| {
            var buffer: [256]u8 = undefined;
            const warning = std.fmt.bufPrint(&buffer, "warning: final extension actions failed: {s}", .{@errorName(err)}) catch "warning: final extension actions failed";
            tui.render.printLine(io, warning) catch {};
        };
        if (session_path) |sp| if (!cli.no_session) sess.save(io, sp) catch |err| {
            var buffer: [256]u8 = undefined;
            const warning = std.fmt.bufPrint(&buffer, "warning: session save after extension shutdown failed: {s}", .{@errorName(err)}) catch "warning: session save after extension shutdown failed";
            tui.render.printLine(io, warning) catch {};
        };
    }

    // Context / skills / prompts
    var context_count: usize = 0;
    var skills_count: usize = 0;
    var system_body: []const u8 = agent.default_system_prompt;
    var context_prompt: []const u8 = "";
    var owned_system: ?[]u8 = null;
    defer if (owned_system) |s| gpa.free(s);
    var owned_system_base: ?[]u8 = null;
    defer if (owned_system_base) |s| gpa.free(s);
    var owned_thinking: ?[]u8 = null;
    defer if (owned_thinking) |s| gpa.free(s);
    var owned_context: ?[]u8 = null;
    defer if (owned_context) |c| gpa.free(c);
    var owned_skills_summary: ?[]u8 = null;
    defer if (owned_skills_summary) |s| gpa.free(s);

    if (!cli.no_context_files) {
        var bundle = try coding.context.discoverTrusted(gpa, io, cwd, agent_dir, trust_project);
        defer bundle.deinit(gpa);
        context_count = bundle.files.len;
        owned_context = try coding.context.assembleContextPrompt(gpa, bundle.files);
        context_prompt = owned_context.?;

        var skills_summary: []const u8 = "";
        if (!cli.no_skills) {
            var resolved_skill_paths: std.ArrayList([]const u8) = .empty;
            defer resolved_skill_paths.deinit(gpa);
            try resolved_skill_paths.appendSlice(gpa, top_level_resources.skills.items);
            try resolved_skill_paths.appendSlice(gpa, package_resources.skills.items);
            var skills_list = try coding.skills.loadTrusted(gpa, io, cwd, agent_dir, trust_project, resolved_skill_paths.items, false);
            if (cli.skills.items.len > 0) skills_list = try coding.skills.filterByNames(gpa, skills_list, cli.skills.items);
            defer {
                for (skills_list) |*skill| skill.deinit(gpa);
                gpa.free(skills_list);
            }
            skills_count = skills_list.len;
            owned_skills_summary = try coding.skills.summarize(gpa, skills_list);
            skills_summary = owned_skills_summary.?;
        }

        const base = cli.system_prompt orelse bundle.system_override orelse agent.default_system_prompt;
        owned_system_base = try coding.system_prompt.assemble(gpa, .{
            .base_prompt = base,
            .system_override = cli.system_prompt orelse bundle.system_override,
            .append_system = bundle.append_system,
            .skills_summary = skills_summary,
            .extra_appends = cli.append_system_prompt.items,
        });
    } else {
        // --no-context-files disables discovery but never drops explicit CLI
        // system prompt/appends.
        owned_system_base = try coding.system_prompt.assemble(gpa, .{
            .system_override = cli.system_prompt,
            .extra_appends = cli.append_system_prompt.items,
        });
    }

    const thinking_eff_early = cli.thinking orelse settings.thinking_level;
    owned_system = try coding.system_prompt.assemble(gpa, .{
        .system_override = owned_system_base.?,
        .thinking_level = thinking_eff_early,
    });
    system_body = owned_system.?;

    var pending_extension_actions: DeferredExtensionActions = .{};
    defer pending_extension_actions.deinit(gpa);

    // Extension commands execute before prompt templates, matching the original
    // AgentSession dispatch order. Commands may consume a CLI turn immediately
    // or replace it with a prompt that continues into the native agent loop.
    var handled_initial_extension_command = false;
    var extension_requested_termination = false;
    var cli_message_index: usize = 0;
    while (cli_message_index < cli.messages.items.len) {
        const message = cli.messages.items[cli_message_index];
        if (message.len > 0 and message[0] == '/' and !coding.slash.isBuiltinCommand(message)) {
            if (try executeExtensionInvocation(&extension_host, message)) |output_value| {
                var output = output_value;
                defer output.deinit(gpa);
                var preview = try previewExtensionCommandActions(gpa, output.actions);
                defer preview.deinit(gpa);
                const presence = extensionActionPresence(output.actions);
                try applyExtensionSessionActions(&sess, &output);
                const action_prompt: ?[]const u8 = if (preview.prompt) |value| value else null;
                const effective_prompt: ?[]const u8 = action_prompt orelse if (presence.reload) null else output.prompt;
                const effective_stop = preview.stop or (!presence.reload and (output.terminate or output.abort));
                try pending_extension_actions.capture(gpa, &output, action_prompt);
                handled_initial_extension_command = true;
                if (!presence.send_message) if (output.message) |visible| try tui.render.printLine(io, visible);
                if (effective_stop) extension_requested_termination = true;
                if (output.is_error or effective_prompt == null or effective_stop) {
                    _ = cli.messages.orderedRemove(cli_message_index);
                    continue;
                }
                cli.messages.items[cli_message_index] = try arena.dupe(u8, effective_prompt.?);
                cli_message_index += 1;
                continue;
            }
        }
        if (try coding.prompts.expandInvocation(arena, message, prompt_templates)) |expanded| cli.messages.items[cli_message_index] = expanded;
        cli_message_index += 1;
    }

    // Binary-safe @file processing and original-compatible initial-message
    // composition. These allocations remain alive through every initial/follow-up
    // turn so provider adapters can borrow their base64 attachment slices.
    var processed_files = coding.file_processor.processFileArguments(gpa, io, environ, cwd, cli.file_args.items, .{
        .auto_resize_images = settings.auto_resize_images orelse true,
    }) catch |err| {
        const message = switch (err) {
            error.FileNotFound => "error: an @file input was not found",
            error.FileTooLarge => "error: an @file input exceeds the 32 MiB limit",
            error.TotalInputTooLarge => "error: combined @file input exceeds the 64 MiB limit",
            else => "error: could not process an @file input",
        };
        try tui.render.printLine(io, message);
        std.process.exit(2);
    };
    defer processed_files.deinit(gpa);

    var piped_stdin: ?[]u8 = null;
    defer if (piped_stdin) |input| gpa.free(input);
    if (has_piped_stdin) {
        piped_stdin = readPipedStdin(gpa, io, 64 * 1024 * 1024) catch |err| {
            const message = if (err == error.StreamTooLong)
                "error: piped stdin exceeds the 64 MiB limit"
            else
                "error: could not read piped stdin";
            try tui.render.printLine(io, message);
            std.process.exit(2);
        };
    }

    var initial_input = try coding.initial_message.build(gpa, piped_stdin, processed_files.text, cli.messages.items);
    defer initial_input.deinit(gpa);
    if (initial_input.message) |combined_message| {
        var command_replaced = false;
        if (combined_message.len > 0 and combined_message[0] == '/' and !coding.slash.isBuiltinCommand(combined_message)) {
            if (try executeExtensionInvocation(&extension_host, combined_message)) |output_value| {
                var output = output_value;
                defer output.deinit(gpa);
                var preview = try previewExtensionCommandActions(gpa, output.actions);
                defer preview.deinit(gpa);
                const presence = extensionActionPresence(output.actions);
                try applyExtensionSessionActions(&sess, &output);
                const action_prompt: ?[]const u8 = if (preview.prompt) |value| value else null;
                const effective_prompt: ?[]const u8 = action_prompt orelse if (presence.reload) null else output.prompt;
                const effective_stop = preview.stop or (!presence.reload and (output.terminate or output.abort));
                try pending_extension_actions.capture(gpa, &output, action_prompt);
                handled_initial_extension_command = true;
                if (!presence.send_message) if (output.message) |visible| try tui.render.printLine(io, visible);
                if (effective_stop) extension_requested_termination = true;
                gpa.free(combined_message);
                if (!output.is_error and !effective_stop and effective_prompt != null) {
                    initial_input.message = try gpa.dupe(u8, effective_prompt.?);
                } else {
                    initial_input.message = null;
                }
                command_replaced = true;
            }
        }
        if (!command_replaced) {
            if (try coding.prompts.expandInvocation(gpa, combined_message, prompt_templates)) |expanded| {
                gpa.free(combined_message);
                initial_input.message = expanded;
            }
        }
    }
    if (extension_requested_termination) {
        try applyDeferredFinalExtensionActions(gpa, io, &sess, &pending_extension_actions);
        if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);
        return;
    }
    const follow_up_messages = cli.messages.items[initial_input.consumed_messages..];
    const initial_images = try arena.alloc(agent.UserImage, processed_files.images.len);
    for (processed_files.images, 0..) |image, index| {
        initial_images[index] = .{ .data_b64 = image.data_b64, .mime_type = image.mime_type };
    }

    // Build extension schemas from the same mutable filter supplied to the
    // worker-side ExtensionContext.
    var extension_tool_schemas = if (extensions_active)
        try extension_bridge.toolSchemasJson(gpa, active_tool_filter)
    else
        try gpa.dupe(u8, "[]");
    defer gpa.free(extension_tool_schemas);
    var extension_active_tools_owned: ?[]const []const u8 = null;
    defer if (extension_active_tools_owned) |names| freeOwnedToolNames(gpa, names);

    const max_turns = settings.max_turns;

    // Resolve every configured effective model independently so hot switching
    // preserves per-model transport and endpoint rather than treating the first
    // model in a provider as representative of all models.
    var runtime_resolutions: std.ArrayList(coding.runtime_config.ResolvedRuntime) = .empty;
    defer {
        for (runtime_resolutions.items) |*runtime| runtime.deinit();
        runtime_resolutions.deinit(gpa);
    }
    var runtime_provider_list: std.ArrayList(coding.live_state.RuntimeProviderConfig) = .empty;
    defer runtime_provider_list.deinit(arena);
    for (model_catalog) |runtime_model| {
        // models.json providers need per-model runtime state, and GitHub
        // Copilot does too because one public provider mixes three native APIs.
        const configured_provider = models_file.findProvider(runtime_model.providerName()) != null;
        const mixed_builtin_provider = std.ascii.eqlIgnoreCase(runtime_model.providerName(), "github-copilot");
        if (!configured_provider and !mixed_builtin_provider) continue;
        const resolved_runtime = try coding.runtime_config.resolveForModel(gpa, io, environ, &models_file, runtime_model, .{
            .agent_dir = agent_dir,
            .explicit_api_key = if (cli.provider != null and cli.api_key != null and std.ascii.eqlIgnoreCase(cli.provider.?, runtime_model.providerName())) cli.api_key else null,
        });
        try runtime_resolutions.append(gpa, resolved_runtime);
        const stored = &runtime_resolutions.items[runtime_resolutions.items.len - 1];
        try runtime_provider_list.append(arena, .{
            .id = runtime_model.providerName(),
            .model_id = runtime_model.id,
            .transport = stored.transport,
            .api = stored.api,
            .model_cost = stored.model_cost,
            .api_key = stored.api_key,
            .oauth_refresh = stored.oauth_refresh,
            .oauth_expires_ms = stored.oauth_expires_ms,
            .oauth_enterprise_url = stored.oauth_enterprise_url,
            .base_url = stored.base_url,
            .headers = stored.headers,
            .sampling_params = stored.sampling_params,
            .compat = stored.compat,
            .reasoning = stored.reasoning,
            .input_image = stored.input_image,
            .thinking_level_map = stored.thinking_level_map,
            .max_tokens = stored.max_tokens,
            .context_window = stored.context_window,
        });
    }

    // Declarative providers registered while script modules initialize share
    // the models.json parser and runtime resolver. Later hook/tool registrations
    // update this same in-memory registry through the ordered action channel.
    var extension_provider_registry = extensions.provider_registry.Registry.init(
        gpa,
        io,
        environ,
        agent_dir,
        model_catalog,
        runtime_provider_list.items,
    );
    defer extension_provider_registry.deinit();
    for (extension_host.extensions.items) |extension| {
        for (extension.providers) |registration| {
            extension_provider_registry.registerJsonWithRuntime(registration.name, registration.config_json, extension.script_runtime) catch |err| {
                var warning_buffer: [512]u8 = undefined;
                const warning = std.fmt.bufPrint(&warning_buffer, "warning: extension {s} provider {s} was not registered: {s}", .{
                    extension.name,
                    registration.name,
                    @errorName(err),
                }) catch "warning: an extension provider was not registered";
                try tui.render.printLine(io, warning);
            };
        }
    }
    var extension_oauth_runtime = extensions.provider_oauth.Runtime.init(
        gpa,
        io,
        agent_dir,
        &extension_provider_registry,
    );
    var extension_models_runtime = try extensions.provider_models.Runtime.init(
        gpa,
        io,
        agent_dir,
        &extension_provider_registry,
        &extension_oauth_runtime,
    );
    defer extension_models_runtime.deinit();
    var extension_stream_runtime = extensions.provider_stream.Runtime.init(gpa, &extension_provider_registry);
    var initial_extension_models = try extension_models_runtime.refresh(.{ .allow_network = false });
    defer initial_extension_models.deinit();
    for (initial_extension_models.errors) |entry| {
        var warning_buffer: [768]u8 = undefined;
        const warning = std.fmt.bufPrint(&warning_buffer, "warning: extension provider {s} cached model restore failed: {s}", .{ entry.provider_id, entry.message }) catch continue;
        try tui.render.printLine(io, warning);
    }

    if (model_scope_storage == null or model_scope_storage.?.scoped_models.len == 0)
        cycling_model_catalog = extension_provider_registry.catalog();

    // Model client pool (rebuildable on provider switch)
    var mock_storage: ?ai.mock.MockModel = null;
    defer if (mock_storage) |*m| m.deinit(gpa);
    var client_pool: coding.live_state.ClientPool = .{
        .gpa = gpa,
        .io = io,
    };
    defer client_pool.deinit();
    extension_oauth_runtime.bindClientPool(&client_pool);
    extension_models_runtime.bindClientPool(&client_pool);
    client_pool.setExtensionOAuthBridge(extension_oauth_runtime.bridge());
    client_pool.setExtensionStreamBridge(extension_stream_runtime.bridge());
    var active_model_field: ?*[]const u8 = null;
    var model_display_owned: bool = false;
    defer if (model_display_owned) if (model) |owned_model_display| gpa.free(owned_model_display);

    // Resolve keys for pool (env/credentials already in api_key for primary provider)
    // Never leak a public-provider CLI key into a native transport's generic
    // fallback slot. GitHub Copilot can dispatch through OpenAI or Anthropic,
    // but its token must remain scoped to the `github-copilot` identity.
    const openai_key = ai.providers.resolveApiKey(.openai, if (std.ascii.eqlIgnoreCase(provider_id, "openai")) cli.api_key else null, environ) orelse
        (if (agent_dir) |ad| (loadStoredApiKey(arena, io, environ, ad, "openai") catch null) orelse (coding.settings.loadCredential(arena, io, ad, "OPENAI_API_KEY") catch null) else null);
    const anthropic_key = ai.providers.resolveApiKey(.anthropic, if (std.ascii.eqlIgnoreCase(provider_id, "anthropic")) cli.api_key else null, environ) orelse
        (if (agent_dir) |ad| (loadStoredApiKey(arena, io, environ, ad, "anthropic") catch null) orelse (coding.settings.loadCredential(arena, io, ad, "ANTHROPIC_API_KEY") catch null) else null);
    const google_key = ai.providers.resolveApiKey(.google, if (std.ascii.eqlIgnoreCase(provider_id, "google")) cli.api_key else null, environ) orelse
        (if (agent_dir) |ad| (loadStoredApiKey(arena, io, environ, ad, "google") catch null) orelse (coding.settings.loadCredential(arena, io, ad, "GOOGLE_API_KEY") catch null) else null);
    client_pool.setKeys(openai_key, anthropic_key, google_key, ai.providers.defaultBaseUrl(.openai));
    client_pool.setRuntimeConfig(environ, primary_runtime.transport, primary_runtime.provider_id, api_key, base_url);
    client_pool.setHttpProxy(settings.http_proxy);
    client_pool.setAuthAgentDir(agent_dir);
    client_pool.setPrimaryOAuthMetadata(primary_runtime.oauth_refresh, primary_runtime.oauth_expires_ms, primary_runtime.oauth_enterprise_url);
    client_pool.setPrimaryRequestMetadata(primary_runtime.headers, primary_runtime.sampling_params, primary_runtime.compat, primary_runtime.max_tokens, primary_runtime.context_window, primary_runtime.input_image);
    client_pool.setPrimaryModelRuntime(primary_runtime.api, primary_runtime.model_cost);
    client_pool.setPrimaryThinkingMetadata(primary_runtime.reasoning, primary_runtime.thinking_level_map);
    client_pool.setModelCatalog(model_catalog);
    client_pool.setRuntimeProviders(extension_provider_registry.runtimes());
    const cache_retention = if (environ.get("PI_CACHE_RETENTION")) |value|
        (ai.request_metadata.CacheRetention.parse(value) orelse .short)
    else
        .short;
    client_pool.setSessionContext(sess.id, cache_retention);
    client_pool.setCodexTransport(settings.transport orelse .auto);
    client_pool.setCodexHttpIdleTimeout(settings.http_idle_timeout_ms orelse ai.openai_responses.DEFAULT_HTTP_IDLE_TIMEOUT_MS);
    client_pool.setCodexWebSocketConnectTimeout(settings.websocket_connect_timeout_ms orelse ai.openai_responses.DEFAULT_WEBSOCKET_CONNECT_TIMEOUT_MS);
    client_pool.setProviderRetryPolicy(providerRetryPolicyFromSettings(&settings));
    // Thinking API budgets applied before first switchTo so request bodies include them.
    const thinking_eff_early_pool = cli.thinking orelse settings.thinking_level;
    client_pool.setThinkingFromString(thinking_eff_early_pool);

    const use_mock = cli.mock_script != null;
    if (cli.mock_script) |path| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024));
        defer gpa.free(raw);
        mock_storage = try ai.mock.MockModel.loadFromJson(gpa, raw);
    } else {
        client_pool.switchToIdentity(provider_id, provider, model.?) catch {
            try tui.render.printLine(io, "error: no model configured. Set OPENAI_API_KEY / ANTHROPIC_API_KEY / GOOGLE_API_KEY or --mock-script.");
            try tui.render.printLine(io, "See `pi --help`.");
            std.process.exit(2);
        };
        active_model_field = client_pool.modelPtr();
    }
    // Always re-read live client (after /model provider switch rebuilds pool)
    const getClient = struct {
        fn call(mock: ?*ai.mock.MockModel, pool: *coding.live_state.ClientPool, is_mock: bool) ai.ModelClient {
            if (is_mock) return mock.?.client();
            return pool.client;
        }
    }.call;

    // Shared cooperative abort for mid-bash kill + mid-HTTP cancel (all modes).
    var shared_abort: bool = false;
    client_pool.setAbortFlag(&shared_abort);
    extension_bridge.setAbortFlag(&shared_abort);

    // Mutable agent config so /reload can update prompts for subsequent turns
    var agent_cfg = agent.AgentConfig{
        .max_turns = max_turns,
        .system_prompt = system_body,
        .context_prompt = context_prompt,
        .tool_filter = active_tool_filter,
        .verbose = cli.verbose,
        .auto_compaction_enabled = settings.compaction_enabled orelse true,
        .compaction_context_window = primary_runtime.context_window,
        .compaction_reserve_tokens = settings.compaction_reserve_tokens orelse 16_384,
        .compaction_keep_recent_tokens = settings.compaction_keep_recent_tokens orelse 20_000,
        .branch_summary_reserve_tokens = settings.branch_summary_reserve_tokens orelse 16_384,
        .branch_summary_skip_prompt = settings.branch_summary_skip_prompt orelse false,
        .auto_resize_images = settings.auto_resize_images orelse true,
        .block_images = settings.block_images orelse false,
        .enable_skill_commands = settings.enable_skill_commands orelse true,
        .retry_enabled = settings.retry_enabled orelse true,
        .retry_max_retries = settings.retry_max_retries orelse 3,
        .retry_base_delay_ms = settings.retry_base_delay_ms orelse 2_000,
        .steering_mode = queueModeFromSettings(settings.steering_mode),
        .follow_up_mode = queueModeFromSettings(settings.follow_up_mode),
        .process_environ = environ,
        .session_id = sess.id,
        .session_file = session_path,
        .provider_name = provider_name,
        .model_id = model,
        .reasoning_level = thinking_eff_early_pool orelse "off",
        .abort_flag = &shared_abort,
        .hook_ctx = if (extensions_active) &extension_bridge else null,
        .before_prompt_fn = if (extensions_active) extensions.integration.Bridge.beforePrompt else null,
        .before_agent_start_fn = if (extensions_active) extensions.integration.Bridge.beforeAgentStart else null,
        .transform_context_fn = if (extensions_active) extensions.integration.Bridge.transformContext else null,
        .before_tool_fn = if (extensions_active) extensions.integration.Bridge.beforeTool else null,
        .after_tool_fn = if (extensions_active) extensions.integration.Bridge.afterTool else null,
        .before_compact_fn = if (extensions_active) extensions.integration.Bridge.beforeCompact else null,
        .after_compact_fn = if (extensions_active) extensions.integration.Bridge.afterCompact else null,
        .before_tree_fn = if (extensions_active) extensions.integration.Bridge.beforeTree else null,
        .after_tree_fn = if (extensions_active) extensions.integration.Bridge.afterTree else null,
        .event_observer_fn = if (extensions_active) extensions.integration.Bridge.onAgentEvent else null,
        .event_observer_ctx = if (extensions_active) &extension_bridge else null,
        .extra_tools_json = extension_tool_schemas,
        .external_tool_fn = if (extensions_active) extensions.integration.Bridge.executeTool else null,
        .external_tool_streaming_fn = if (extensions_active) extensions.integration.Bridge.executeToolStreaming else null,
        .external_tool_call_streaming_fn = if (extensions_active) extensions.integration.Bridge.executeToolCallStreaming else null,
        .external_tool_exists_fn = if (extensions_active) extensions.integration.Bridge.hasExecutableTool else null,
        .external_prepare_arguments_fn = if (extensions_active) extensions.integration.Bridge.prepareToolArguments else null,
        .external_tool_mode_fn = if (extensions_active) extensions.integration.Bridge.toolExecutionMode else null,
        .disable_builtin_tools = cli.no_builtin_tools,
    };

    const thinking_eff = cli.thinking orelse settings.thinking_level;

    var live = coding.live_state.LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = cwd,
        .agent_dir = agent_dir,
        .trust_project = trust_project,
        .thinking = thinking_eff,
        .agent_cfg = &agent_cfg,
        .owned_system = &owned_system,
        .owned_context = &owned_context,
        .owned_system_base = &owned_system_base,
        .owned_thinking = &owned_thinking,
        .owned_skills_summary = &owned_skills_summary,
        .cli_system_override = cli.system_prompt,
        .cli_system_appends = cli.append_system_prompt.items,
        .include_context_files = !cli.no_context_files,
        .include_skills = !cli.no_skills,
        .selected_skill_names = cli.skills.items,
        .model_display = &model,
        .active_model = active_model_field,
        .model_display_owned = &model_display_owned,
        .client_pool = if (cli.mock_script == null) &client_pool else null,
        .provider_name = &provider_name,
        .model_catalog = extension_provider_registry.catalog(),
        .model_scope = if (model_scope_storage) |scope| scope.scoped_models else &.{},
    };
    _ = &live;
    extension_oauth_runtime.bindLiveState(&live);
    extension_models_runtime.bindLiveState(&live);
    defer live.deinitDynamicCatalog();

    var extension_command_steering: std.ArrayList([]const u8) = .empty;
    defer {
        for (extension_command_steering.items) |message| gpa.free(message);
        extension_command_steering.deinit(gpa);
    }
    var extension_command_followups: std.ArrayList([]const u8) = .empty;
    defer {
        for (extension_command_followups.items) |message| gpa.free(message);
        extension_command_followups.deinit(gpa);
    }
    agent_cfg.steer_queue = &extension_command_steering;
    agent_cfg.follow_up_queue = &extension_command_followups;

    var extension_action_runtime = ExtensionActionRuntime{
        .live = &live,
        .host = &extension_host,
        .bridge = &extension_bridge,
        .provider_registry = &extension_provider_registry,
        .provider_models = &extension_models_runtime,
        .active_filter = &active_tool_filter,
        .owned_active_tools = &extension_active_tools_owned,
        .extension_schemas = &extension_tool_schemas,
        .mock_client = if (mock_storage) |*mock| mock.client() else null,
        .render_output = std.mem.eql(u8, extension_mode, "tui"),
        .render_width = tui.terminal.columnsFromEnvironment(environ, 100),
    };
    if (extensions_active) {
        agent_cfg.flush_runtime_actions_fn = ExtensionActionRuntime.flush;
        agent_cfg.flush_runtime_actions_ctx = &extension_action_runtime;
    }

    var tree_filter_mode = treeFilterFromSettings(settings.tree_filter_mode);
    var runtime_reload_context = RuntimeResourceReloadContext{
        .gpa = gpa,
        .io = io,
        .environ = environ,
        .cwd = cwd,
        .agent_dir = agent_dir,
        .trust_project = trust_project,
        .cli = &cli,
        .mode = extension_mode,
        .ui = &extension_ui,
        .session = &sess,
        .provider_name = &provider_name,
        .model_id = &model,
        .live = &live,
        .active_filter = &active_tool_filter,
        .owned_active_tools = &extension_active_tools_owned,
        .disable_builtin_tools = cli.no_builtin_tools,
        .session_file = session_path,
        .session_dir = session_dir,
        .baseline_catalog = model_catalog,
        .baseline_runtimes = runtime_provider_list.items,
        .host = &extension_host,
        .bridge = &extension_bridge,
        .provider_registry = &extension_provider_registry,
        .extension_oauth = &extension_oauth_runtime,
        .provider_stream = &extension_stream_runtime,
        .provider_models = &extension_models_runtime,
        .schemas = &extension_tool_schemas,
        .prompt_templates = &prompt_templates,
        .command_names = &extension_command_names,
        .command_infos = &extension_command_infos,
        .theme_registry = &theme_registry,
        .action_runtime = &extension_action_runtime,
        .steering = &extension_command_steering,
        .followups = &extension_command_followups,
        .shared_abort = &shared_abort,
        .tree_filter_mode = &tree_filter_mode,
    };
    live.runtime_reload_ctx = &runtime_reload_context;
    live.runtime_reload_fn = RuntimeResourceReloadContext.reload;

    const pending_model: ?*const extensions.host.ModelAction = if (pending_extension_actions.model) |*model_action| model_action else null;
    const pending_tools: ?[]const []const u8 = if (pending_extension_actions.active_tools) |tools| tools else null;
    try applyExtensionRuntimeActions(
        gpa,
        &sess,
        pending_model,
        pending_extension_actions.thinking_level,
        pending_tools,
        &live,
        &extension_host,
        &extension_bridge,
        &active_tool_filter,
        &extension_active_tools_owned,
        &extension_tool_schemas,
    );
    var deferred_client = getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock);
    if (try applyDeferredExtensionActions(
        gpa,
        io,
        &pending_extension_actions,
        &extension_action_runtime,
        &sess,
        &agent_cfg,
        &deferred_client,
        &extension_command_steering,
        &extension_command_followups,
    )) {
        if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);
        return;
    }
    if (extensions_active) try syncExtensionScriptContext(
        &extension_host,
        &extension_ui,
        extension_mode,
        cwd,
        &sess,
        provider_name,
        model,
        live.thinking,
        trust_project,
        "",
        active_tool_filter,
        cli.no_builtin_tools,
        live.model_catalog,
        &.{},
        session_path,
        session_dir,
    );

    // Export only mode
    if (cli.export_path) |ep| {
        if (initial_input.message) |prompt| {
            var result = try agent.runWithImages(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, initial_images, agent_cfg, null, null);
            result.deinit(gpa);
        }
        for (follow_up_messages) |prompt| {
            var result = try agent.run(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, null, null);
            result.deinit(gpa);
        }
        const html = try coding.export_html.exportHtml(gpa, &sess);
        defer gpa.free(html);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = ep, .data = html });
        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
        return;
    }

    // RPC mode
    if (cli.mode == .rpc) {
        try runRpcMode(
            gpa,
            io,
            arena,
            cwd,
            &client_pool,
            &sess,
            &agent_cfg,
            &live,
            &provider_name,
            &extension_host,
            &extension_action_runtime,
            &extension_command_steering,
            &extension_command_followups,
            &extension_command_infos,
            &prompt_templates,
            session_path,
            cli.no_session,
            use_mock,
            if (mock_storage) |*m| m else null,
        );
        return;
    }

    // Print / one-shot. The original sends the first composed prompt and every
    // remaining positional message as distinct agent turns, then prints only
    // the final assistant response in text mode.
    if (cli.print or cli.mode == .json) {
        const prompt_count = @as(usize, @intFromBool(initial_input.message != null)) + follow_up_messages.len;
        if (prompt_count == 0) {
            if (handled_initial_extension_command) {
                if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);
                return;
            }
            try tui.render.printLine(io, "error: print mode requires a prompt message");
            std.process.exit(2);
        }

        var completed_prompts: usize = 0;
        if (cli.mode == .json) {
            var emitter = coding.modes.JsonEmitter{
                .io = io,
                .session_id = sess.id,
                .cwd = cwd,
            };
            if (initial_input.message) |prompt| {
                var result = try agent.runWithImages(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, initial_images, agent_cfg, coding.modes.JsonEmitter.onEvent, &emitter);
                result.deinit(gpa);
                completed_prompts += 1;
            }
            for (follow_up_messages) |prompt| {
                var result = try agent.run(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, coding.modes.JsonEmitter.onEvent, &emitter);
                result.deinit(gpa);
                completed_prompts += 1;
            }
        } else {
            var emitter = coding.modes.PrintEmitter{ .io = io, .verbose = cli.verbose };
            if (initial_input.message) |prompt| {
                var result = try agent.runWithImages(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, initial_images, agent_cfg, coding.modes.PrintEmitter.onEvent, &emitter);
                completed_prompts += 1;
                if (!cli.verbose and completed_prompts == prompt_count) try tui.render.printLine(io, result.final_text);
                result.deinit(gpa);
            }
            for (follow_up_messages) |prompt| {
                var result = try agent.run(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, coding.modes.PrintEmitter.onEvent, &emitter);
                completed_prompts += 1;
                if (!cli.verbose and completed_prompts == prompt_count) try tui.render.printLine(io, result.final_text);
                result.deinit(gpa);
            }
        }
        std.debug.assert(completed_prompts == prompt_count);

        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
        return;
    }

    // Interactive REPL. Fullscreen uses the terminal's alternate-screen buffer
    // and always restores the caller's screen on normal/error unwinding.
    const effective_tui_mode: coding.settings.TuiMode = if (cli.tui_mode) |mode| switch (mode) {
        .regular => .regular,
        .fullscreen => .fullscreen,
    } else settings.tui_mode orelse .regular;
    var fullscreen_active = false;
    if (effective_tui_mode == .fullscreen and tui.terminal.supportsFullscreen(io)) {
        try tui.terminal.enterAlternateScreen(io);
        fullscreen_active = true;
        if (settings.show_hardware_cursor orelse false) try tui.render.writeAll(io, tui.terminal.show_cursor);
    }
    defer if (fullscreen_active) tui.terminal.leaveAlternateScreen(io) catch {};

    var interactive_render = InteractiveRenderOptions{
        .width = tui.terminal.columnsFromEnvironment(environ, 100),
        .capabilities = tui.terminal_image.detectCapabilities(
            tui.terminal_image.environmentFromMap(environ),
            build_options.os.tag == .windows,
            false,
        ),
        .show_images = settings.show_images orelse true,
        .image_width_cells = @intCast(@min(settings.image_width_cells orelse 60, std.math.maxInt(u32))),
        .show_terminal_progress = settings.show_terminal_progress orelse false,
        .output_pad = @intCast(@min(settings.output_pad orelse 1, 1)),
        .editor_padding_x = @intCast(@min(settings.editor_padding_x orelse 0, 3)),
        .show_hardware_cursor = settings.show_hardware_cursor orelse false,
    };
    runtime_reload_context.render_options = &interactive_render;

    if (!(settings.quiet_startup orelse false)) {
        if (!try extension_ui.renderCustomHeader()) try tui.render.renderHeader(io, config.version, context_count, skills_count);
        try extension_ui.flush();
    }
    var install_report_thread: ?std.Thread = null;
    defer if (install_report_thread) |thread| thread.join();
    try runInteractiveReleaseLifecycle(gpa, io, environ, agent_dir, &settings, sess.entries.items.len > 0, cli.offline, &install_report_thread);
    try tui.render.printLine(io, "Type a prompt and press Enter. Commands: /help /quit /session");

    var settings_text = try coding.settings.formatSettings(gpa, settings);
    defer gpa.free(settings_text);
    runtime_reload_context.settings_text = &settings_text;

    if (initial_input.message) |prompt| {
        try runOneWithImages(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, initial_images, agent_cfg, cli.verbose, interactive_render, &extension_host);
    }
    for (follow_up_messages) |prompt| {
        try runOne(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, agent_cfg, cli.verbose, interactive_render, &extension_host);
    }
    if (initial_input.message != null or follow_up_messages.len > 0) {
        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
    }

    const use_terminal_editor = tui.line_editor.available(io);
    var terminal_editor = tui.editor.Editor.init(gpa);
    defer terminal_editor.deinit();
    var terminal_keybindings = if (agent_dir) |dir| tui.keybindings.Manager.load(gpa, io, dir) catch tui.keybindings.Manager.init(gpa) else tui.keybindings.Manager.init(gpa);
    defer terminal_keybindings.deinit();
    runtime_reload_context.keybindings = &terminal_keybindings;
    var clipboard_store = coding.clipboard.TempStore.init(gpa, io, environ);
    defer clipboard_store.deinit();
    var tree_summary_prompt_context = TreeSummaryPromptContext{
        .io = io,
        .reader = &extension_stdin_reader,
        .editor = &terminal_editor,
        .bindings = &terminal_keybindings,
        .use_terminal_editor = use_terminal_editor,
    };
    var tree_target_prompt_context = TreeTargetPromptContext{
        .io = io,
        .environ = environ,
        .reader = &extension_stdin_reader,
        .already_fullscreen = fullscreen_active,
        .filter_mode = &tree_filter_mode,
    };
    var model_target_prompt_context = ModelTargetPromptContext{
        .io = io,
        .environ = environ,
        .reader = &extension_stdin_reader,
        .already_fullscreen = fullscreen_active,
        .live = &live,
        .provider_models = &extension_models_runtime,
        .abort_flag = &shared_abort,
    };
    var settings_target_prompt_context: ?SettingsTargetPromptContext = if (agent_dir) |ad| .{
        .io = io,
        .environ = environ,
        .reader = &extension_stdin_reader,
        .already_fullscreen = fullscreen_active,
        .agent_dir = ad,
        .cwd = cwd,
        .trust_project = trust_project,
        .theme_registry = &theme_registry,
    } else null;
    var auth_target_prompt_context: ?AuthTargetPromptContext = if (agent_dir) |ad| .{
        .io = io,
        .environ = environ,
        .reader = &extension_stdin_reader,
        .already_fullscreen = fullscreen_active,
        .agent_dir = ad,
        .live = &live,
        .extension_oauth = &extension_oauth_runtime,
    } else null;
    var auth_flow_controller = coding.auth_flow_tui.Controller.init(
        gpa,
        io,
        environ,
        &extension_stdin_reader,
        fullscreen_active,
    );
    defer auth_flow_controller.deinit();
    const all_sessions_root = if (cli.session_dir != null)
        session_dir
    else if (agent_dir) |ad|
        try std.fs.path.join(arena, &.{ ad, "sessions" })
    else
        session_dir;
    var session_target_prompt_context = SessionTargetPromptContext{
        .io = io,
        .environ = environ,
        .reader = &extension_stdin_reader,
        .already_fullscreen = fullscreen_active,
        .session_dir = session_dir,
        .all_sessions_root = all_sessions_root,
        .current_session_path = &session_path,
        .required_cwd = cwd,
    };
    const tree_target_prompt_available = tui.terminal.supportsFullscreen(io);
    const model_target_prompt_available = tui.terminal.supportsFullscreen(io);
    const settings_target_prompt_available = settings_target_prompt_context != null and tui.terminal.supportsFullscreen(io);
    const auth_target_prompt_available = auth_target_prompt_context != null and tui.terminal.supportsFullscreen(io);
    const session_target_prompt_available = tui.terminal.supportsFullscreen(io);
    var completion_context = ReplCompletionContext{
        .io = io,
        .environ = environ,
        .cwd = cwd,
        .live = &live,
        .prompt_templates = &prompt_templates,
        .extension_commands = &extension_command_names,
        .session = &sess,
    };
    const terminal_completer = tui.line_editor.Completer{
        .context = &completion_context,
        .complete_fn = replComplete,
    };
    var extension_shortcut_context = ExtensionShortcutContext{
        .host = &extension_host,
        .ui_controller = &extension_ui,
        .editor = &terminal_editor,
        .bindings = &terminal_keybindings,
        .clipboard_store = &clipboard_store,
        .io = io,
        .environ = environ,
        .mode = extension_mode,
        .cwd = cwd,
        .session = &sess,
        .provider = &provider_name,
        .model_id = &model,
        .thinking_level = &live.thinking,
        .project_trusted = trust_project,
        .tool_filter = &active_tool_filter,
        .disable_builtin_tools = cli.no_builtin_tools,
        .model_catalog = live.model_catalog,
        .configured_providers = &.{},
        .session_file = session_path,
        .session_dir = session_dir,
    };
    defer extension_shortcut_context.deinit();
    const terminal_shortcut_handler = tui.line_editor.ShortcutHandler{
        .context = &extension_shortcut_context,
        .handle_fn = ExtensionShortcutContext.handle,
        .clipboard_paste_fn = ExtensionShortcutContext.pasteClipboard,
    };
    while (true) {
        extension_shortcut_context.model_catalog = live.model_catalog;
        const pending_editor_text = extension_ui.takePendingEditorText();
        defer if (pending_editor_text) |value| gpa.free(value);
        const editor_prefill = pending_editor_text orelse "";
        try syncExtensionScriptContext(
            &extension_host,
            &extension_ui,
            extension_mode,
            cwd,
            &sess,
            provider_name,
            model,
            live.thinking,
            trust_project,
            editor_prefill,
            active_tool_filter,
            cli.no_builtin_tools,
            live.model_catalog,
            &.{},
            session_path,
            session_dir,
        );
        try extension_ui.flush();
        var prompt_buffer: [5]u8 = .{ ' ', ' ', ' ', '>', ' ' };
        const prompt_start: usize = 3 - @min(@as(usize, interactive_render.editor_padding_x), 3);
        const prompt_text = prompt_buffer[prompt_start..];
        const line = if (use_terminal_editor)
            tui.line_editor.readLineWithCompleterAndShortcutsPrefill(arena, io, &extension_stdin_reader, &terminal_editor, &terminal_keybindings, prompt_text, terminal_completer, terminal_shortcut_handler, editor_prefill) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        else blk: {
            try tui.render.writeAll(io, prompt_text);
            if (editor_prefill.len > 0) {
                try tui.render.printLine(io, editor_prefill);
                break :blk try arena.dupe(u8, editor_prefill);
            }
            break :blk readLine(&extension_stdin_reader, arena) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
        };
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        var expanded_template: ?[]u8 = null;
        defer if (expanded_template) |value| gpa.free(value);
        var extension_command_output = extension_shortcut_context.take();
        defer if (extension_command_output) |*output| output.deinit(gpa);
        var applied_extension_command: ?AppliedExtensionCommand = null;
        defer if (applied_extension_command) |*applied| applied.deinit(gpa);
        var effective_input: []const u8 = trimmed;

        if (extension_command_output) |*output| {
            var command_client = getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock);
            applied_extension_command = try applyExtensionCommandOutput(
                gpa,
                io,
                &extension_action_runtime,
                &sess,
                output,
                &agent_cfg,
                &command_client,
                &extension_command_steering,
                &extension_command_followups,
            );
            try extension_ui.flush();
            if (applied_extension_command.?.terminate) break;
            if (applied_extension_command.?.is_error or applied_extension_command.?.prompt == null) {
                if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);
                continue;
            }
            effective_input = applied_extension_command.?.prompt.?;
        } else {
            if (trimmed.len == 0) continue;
        }

        var requested_session_path: ?[]u8 = null;
        defer if (requested_session_path) |value| gpa.free(value);

        if (extension_command_output == null and trimmed[0] == '/') {
            if (coding.slash.isBuiltinCommand(trimmed)) {
                const slash_ctx = coding.slash.SlashContext{
                    .gpa = gpa,
                    .io = io,
                    .cwd = cwd,
                    .sess = &sess,
                    .session_path = session_path,
                    .session_dir = session_dir,
                    .agent_dir = agent_dir,
                    .model = &model,
                    .provider = &provider_name,
                    .settings_text = settings_text,
                    .clipboard_options = .{ .environ = environ },
                    .trust_project = trust_project,
                    .live = &live,
                    .client = getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock),
                    .model_target_prompt_ctx = if (model_target_prompt_available) &model_target_prompt_context else null,
                    .model_target_prompt_fn = if (model_target_prompt_available) ModelTargetPromptContext.prompt else null,
                    .settings_target_prompt_ctx = if (settings_target_prompt_available) &settings_target_prompt_context.? else null,
                    .settings_target_prompt_fn = if (settings_target_prompt_available) SettingsTargetPromptContext.prompt else null,
                    .auth_target_prompt_ctx = if (auth_target_prompt_available) &auth_target_prompt_context.? else null,
                    .auth_target_prompt_fn = if (auth_target_prompt_available) AuthTargetPromptContext.prompt else null,
                    .auth_flow_ui = if (auth_target_prompt_available) &auth_flow_controller else null,
                    .extension_oauth = &extension_oauth_runtime,
                    .tree_summary_prompt_ctx = &tree_summary_prompt_context,
                    .tree_summary_prompt_fn = TreeSummaryPromptContext.prompt,
                    .tree_target_prompt_ctx = if (tree_target_prompt_available) &tree_target_prompt_context else null,
                    .tree_target_prompt_fn = if (tree_target_prompt_available) TreeTargetPromptContext.prompt else null,
                    .session_target_prompt_ctx = if (session_target_prompt_available) &session_target_prompt_context else null,
                    .session_target_prompt_fn = if (session_target_prompt_available) SessionTargetPromptContext.prompt else null,
                    .resume_path_out = &requested_session_path,
                };
                const sr = try coding.slash.handle(slash_ctx, trimmed);
                switch (sr) {
                    .quit => break,
                    .handled => {
                        if (requested_session_path) |resume_path| {
                            if (session_path) |current_path| {
                                if (std.mem.eql(u8, current_path, resume_path)) {
                                    try tui.render.printLine(io, "That session is already active.");
                                    continue;
                                }
                            }
                            var loaded = agent.session.Session.load(gpa, io, resume_path) catch |err| {
                                const warning = try std.fmt.allocPrint(arena, "Could not resume selected session: {s}", .{@errorName(err)});
                                try tui.render.printLine(io, warning);
                                continue;
                            };
                            var loaded_owned = true;
                            defer if (loaded_owned) loaded.deinit();
                            if (loaded.cwd.len > 0 and !std.mem.eql(u8, loaded.cwd, cwd)) {
                                try tui.render.printLine(io, "The selected session belongs to a different working directory.");
                                continue;
                            }

                            if (extensions_active) {
                                try extension_bridge.sessionShutdown(gpa, cwd, sess.id, "resume");
                                try flushFinalExtensionActions(gpa, io, &sess, &extension_bridge);
                            }
                            if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);

                            sess.deinit();
                            sess = loaded;
                            loaded_owned = false;
                            session_path = try arena.dupe(u8, resume_path);
                            agent_cfg.session_id = sess.id;
                            agent_cfg.session_file = session_path;
                            client_pool.setSessionContext(sess.id, client_pool.cache_retention);
                            extension_shortcut_context.session_file = session_path;

                            const resumed_settings = try sess.activeSettings(arena);
                            if (resumed_settings.provider != null and resumed_settings.model_id != null) {
                                const reference = try std.fmt.allocPrint(arena, "{s}/{s}", .{ resumed_settings.provider.?, resumed_settings.model_id.? });
                                coding.live_state.applyModel(&live, reference) catch |err| {
                                    const warning = try std.fmt.allocPrint(arena, "warning: resumed session model could not be restored ({s}); keeping the current model", .{@errorName(err)});
                                    try tui.render.printLine(io, warning);
                                };
                            }
                            if (resumed_settings.thinking_level) |level| {
                                coding.live_state.applyThinking(&live, level) catch |err| {
                                    const warning = try std.fmt.allocPrint(arena, "warning: resumed thinking level could not be restored ({s})", .{@errorName(err)});
                                    try tui.render.printLine(io, warning);
                                };
                            }

                            try syncExtensionScriptContext(
                                &extension_host,
                                &extension_ui,
                                extension_mode,
                                cwd,
                                &sess,
                                provider_name,
                                model,
                                live.thinking,
                                trust_project,
                                "",
                                active_tool_filter,
                                cli.no_builtin_tools,
                                live.model_catalog,
                                &.{},
                                session_path,
                                session_dir,
                            );
                            if (extensions_active) {
                                try extension_bridge.sessionStart(gpa, cwd, sess.id, "resume");
                                try flushFinalExtensionActions(gpa, io, &sess, &extension_bridge);
                            }
                            if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);
                            const display_name = if (sess.name.len > 0) sess.name else sess.id;
                            const message = try std.fmt.allocPrint(arena, "Resumed session {s} ({s}).", .{ sess.id, display_name });
                            try tui.render.printLine(io, message);
                            continue;
                        }
                        if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);
                        continue;
                    },
                    .not_command, .run_prompt => {},
                }
            } else if (try executeExtensionInvocation(&extension_host, trimmed)) |output| {
                extension_command_output = output;
                var command_client = getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock);
                applied_extension_command = try applyExtensionCommandOutput(
                    gpa,
                    io,
                    &extension_action_runtime,
                    &sess,
                    &extension_command_output.?,
                    &agent_cfg,
                    &command_client,
                    &extension_command_steering,
                    &extension_command_followups,
                );
                try extension_ui.flush();
                if (applied_extension_command.?.terminate) break;
                if (applied_extension_command.?.is_error or applied_extension_command.?.prompt == null) {
                    if (session_path) |sp| if (!cli.no_session) try sess.save(io, sp);
                    continue;
                }
                effective_input = applied_extension_command.?.prompt.?;
            } else if (try coding.prompts.expandInvocation(gpa, trimmed, prompt_templates)) |expanded| {
                expanded_template = expanded;
                effective_input = expanded;
            } else {
                const slash_ctx = coding.slash.SlashContext{
                    .gpa = gpa,
                    .io = io,
                    .cwd = cwd,
                    .sess = &sess,
                    .session_path = session_path,
                    .session_dir = session_dir,
                    .agent_dir = agent_dir,
                    .model = &model,
                    .provider = &provider_name,
                    .settings_text = settings_text,
                    .clipboard_options = .{ .environ = environ },
                    .trust_project = trust_project,
                    .live = &live,
                    .client = getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock),
                    .model_target_prompt_ctx = if (model_target_prompt_available) &model_target_prompt_context else null,
                    .model_target_prompt_fn = if (model_target_prompt_available) ModelTargetPromptContext.prompt else null,
                    .settings_target_prompt_ctx = if (settings_target_prompt_available) &settings_target_prompt_context.? else null,
                    .settings_target_prompt_fn = if (settings_target_prompt_available) SettingsTargetPromptContext.prompt else null,
                    .auth_target_prompt_ctx = if (auth_target_prompt_available) &auth_target_prompt_context.? else null,
                    .auth_target_prompt_fn = if (auth_target_prompt_available) AuthTargetPromptContext.prompt else null,
                    .auth_flow_ui = if (auth_target_prompt_available) &auth_flow_controller else null,
                    .extension_oauth = &extension_oauth_runtime,
                    .tree_summary_prompt_ctx = &tree_summary_prompt_context,
                    .tree_summary_prompt_fn = TreeSummaryPromptContext.prompt,
                    .tree_target_prompt_ctx = if (tree_target_prompt_available) &tree_target_prompt_context else null,
                    .tree_target_prompt_fn = if (tree_target_prompt_available) TreeTargetPromptContext.prompt else null,
                };
                _ = try coding.slash.handle(slash_ctx, trimmed);
                continue;
            }
        }

        // Interactive @file references use the same binary-safe multimodal
        // pipeline as startup CLI arguments. Missing @mentions stay verbatim.
        var inline_input = try coding.inline_files.extract(gpa, io, environ, cwd, effective_input);
        defer inline_input.deinit(gpa);
        try syncExtensionScriptContext(
            &extension_host,
            &extension_ui,
            extension_mode,
            cwd,
            &sess,
            provider_name,
            model,
            live.thinking,
            trust_project,
            "",
            active_tool_filter,
            cli.no_builtin_tools,
            live.model_catalog,
            &.{},
            session_path,
            session_dir,
        );
        if (inline_input.paths.len > 0) {
            var inline_files = coding.file_processor.processFileArguments(gpa, io, environ, cwd, inline_input.paths, .{
                .auto_resize_images = agent_cfg.auto_resize_images,
            }) catch |err| {
                const message = switch (err) {
                    error.FileTooLarge => "attachment exceeds the 32 MiB file limit",
                    error.TotalInputTooLarge => "attachments exceed the 64 MiB turn limit",
                    else => "attachment could not be read",
                };
                try tui.render.printLine(io, message);
                continue;
            };
            defer inline_files.deinit(gpa);
            const prompt_parts = if (inline_input.message.len > 0) &[_][]const u8{inline_input.message} else &[_][]const u8{};
            var combined = try coding.initial_message.build(gpa, null, inline_files.text, prompt_parts);
            defer combined.deinit(gpa);
            const prompt = combined.message orelse "Please inspect the attached image.";
            const turn_images = try arena.alloc(agent.UserImage, inline_files.images.len);
            for (inline_files.images, 0..) |image, index| {
                turn_images[index] = .{ .data_b64 = image.data_b64, .mime_type = image.mime_type };
            }
            try runOneWithImages(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, prompt, turn_images, agent_cfg, cli.verbose, interactive_render, &extension_host);
        } else {
            // agent_cfg is var; by-value copy picks up /reload and /model side effects.
            try runOne(gpa, io, cwd, getClient(if (mock_storage) |*m| m else null, &client_pool, use_mock), &sess, inline_input.message, agent_cfg, cli.verbose, interactive_render, &extension_host);
        }
        try extension_ui.flush();
        if (session_path) |sp| {
            if (!cli.no_session) try sess.save(io, sp);
        }
    }

    if (session_path) |sp| {
        if (!cli.no_session) try sess.save(io, sp);
    }
}

const InteractiveRenderOptions = struct {
    width: usize,
    capabilities: tui.terminal_image.TerminalCapabilities,
    show_images: bool = true,
    image_width_cells: u32 = 60,
    show_terminal_progress: bool = false,
    output_pad: u8 = 1,
    editor_padding_x: u8 = 0,
    show_hardware_cursor: bool = false,
};

fn writeExtensionRendered(io: Io, rendered: []const u8) !void {
    if (rendered.len == 0) return;
    try tui.render.writeAll(io, rendered);
    if (rendered[rendered.len - 1] != '\n') try tui.render.writeAll(io, "\n");
}

fn renderOneToolImage(
    gpa: std.mem.Allocator,
    io: Io,
    capabilities: tui.terminal_image.TerminalCapabilities,
    show_images: bool,
    max_width_cells: u32,
    data_b64: []const u8,
    mime_type: []const u8,
) void {
    const dimensions = tui.terminal_image.getImageDimensionsBase64(gpa, data_b64, mime_type) catch null;
    if (show_images and capabilities.images != null and dimensions != null) {
        if (tui.terminal_image.renderImage(
            gpa,
            capabilities,
            .{},
            null,
            data_b64,
            dimensions.?,
            .{ .max_width_cells = @max(1, max_width_cells) },
        ) catch null) |value| {
            var rendered = value;
            defer rendered.deinit(gpa);
            tui.render.writeAll(io, rendered.sequence) catch return;
            tui.render.writeAll(io, "\n") catch {};
            return;
        }
    }

    // Match the original TUI: hidden images and terminals without an image
    // protocol retain a visible MIME/dimension indicator instead of silently
    // dropping result content.
    const fallback = tui.terminal_image.imageFallback(gpa, capabilities, mime_type, dimensions, null, null) catch return;
    defer gpa.free(fallback);
    tui.render.printLine(io, fallback) catch {};
}

fn renderToolEventImages(
    gpa: std.mem.Allocator,
    io: Io,
    capabilities: tui.terminal_image.TerminalCapabilities,
    show_images: bool,
    max_width_cells: u32,
    legacy_data: ?[]const u8,
    legacy_mime: ?[]const u8,
    images: []const agent.tools.ToolImage,
) void {
    if (legacy_data) |data| renderOneToolImage(gpa, io, capabilities, show_images, max_width_cells, data, legacy_mime orelse "image/png");
    for (images) |image| renderOneToolImage(gpa, io, capabilities, show_images, max_width_cells, image.data_b64, image.mime_type);
}

/// Interactive event sink that preserves the native renderer fallback while
/// allowing extension-owned tool rows to use their original renderCall and
/// renderResult components through the persistent compatibility worker.
const ExtensionPrintEmitter = struct {
    io: Io,
    verbose: bool,
    width: usize,
    capabilities: tui.terminal_image.TerminalCapabilities,
    show_images: bool,
    image_width_cells: u32,
    host: *extensions.Host,

    fn onEvent(raw: ?*anyopaque, event: agent.AgentEvent) void {
        const self: *ExtensionPrintEmitter = @ptrCast(@alignCast(raw.?));
        switch (event.kind) {
            .message_update => {
                if (self.verbose) tui.render.writeAll(self.io, event.text) catch {};
            },
            .assistant => {
                if (self.verbose) tui.render.renderAssistant(self.io, event.text) catch {};
            },
            // The loop emits both canonical execution events and legacy
            // aliases. Render only the canonical pair so extension components
            // retain one state transition per real tool invocation.
            .tool_execution_start => {
                if (!self.verbose) return;
                const arguments = if (event.args_json.len > 0) event.args_json else if (event.text.len > 0) event.text else "{}";
                if (self.host.renderToolCall(event.name, event.id, arguments, false, self.width) catch null) |rendered| {
                    defer self.host.gpa.free(rendered);
                    writeExtensionRendered(self.io, rendered) catch {};
                } else {
                    tui.render.renderToolCall(self.io, event.name, event.text) catch {};
                }
            },
            .tool_execution_update, .tool_execution_end => {
                if (!self.verbose) return;
                const image_count: usize = @intFromBool(event.image_b64 != null) + event.images.len;
                const render_images = self.host.gpa.alloc(extensions.host.ToolImage, image_count) catch return;
                defer if (render_images.len > 0) self.host.gpa.free(render_images);
                var image_index: usize = 0;
                if (event.image_b64) |data| {
                    render_images[0] = .{
                        .data_b64 = @constCast(data),
                        .mime_type = @constCast(event.image_mime orelse "image/png"),
                    };
                    image_index = 1;
                }
                for (event.images) |image| {
                    render_images[image_index] = .{
                        .data_b64 = image.data_b64,
                        .mime_type = image.mime_type,
                    };
                    image_index += 1;
                }
                if (self.host.renderToolResultRichImages(
                    event.name,
                    event.id,
                    event.text,
                    event.is_error,
                    event.details_json,
                    render_images,
                    false,
                    event.kind == .tool_execution_update,
                    self.show_images and self.capabilities.images != null,
                    self.width,
                ) catch null) |rendered| {
                    defer self.host.gpa.free(rendered);
                    writeExtensionRendered(self.io, rendered) catch {};
                } else {
                    tui.render.renderToolResult(self.io, event.name, event.text, event.is_error) catch {};
                    renderToolEventImages(
                        self.host.gpa,
                        self.io,
                        self.capabilities,
                        self.show_images,
                        self.image_width_cells,
                        event.image_b64,
                        event.image_mime,
                        event.images,
                    );
                }
            },
            .auto_retry_start => {
                var buf: [320]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "retry {d}/{d} in {d}ms: {s}", .{
                    event.attempt,
                    event.max_attempts,
                    event.delay_ms,
                    event.error_message orelse event.text,
                }) catch return;
                tui.render.printLine(self.io, line) catch {};
            },
            .auto_retry_end => {
                var buf: [256]u8 = undefined;
                const line = if (event.success)
                    std.fmt.bufPrint(&buf, "retry succeeded after attempt {d}", .{event.attempt}) catch return
                else
                    std.fmt.bufPrint(&buf, "retry ended after attempt {d}: {s}", .{ event.attempt, event.final_error orelse event.text }) catch return;
                tui.render.printLine(self.io, line) catch {};
            },
            .summarization_retry_scheduled => {
                var buf: [320]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "summary retry {d}/{d} in {d}ms: {s}", .{
                    event.attempt,
                    event.max_attempts,
                    event.delay_ms,
                    event.error_message orelse event.text,
                }) catch return;
                tui.render.printLine(self.io, line) catch {};
            },
            .summarization_retry_attempt_start => {
                var buf: [192]u8 = undefined;
                const line = if (std.mem.eql(u8, event.source, "branchSummary"))
                    std.fmt.bufPrint(&buf, "retrying branch summary", .{}) catch return
                else
                    std.fmt.bufPrint(&buf, "retrying {s} compaction", .{event.reason}) catch return;
                tui.render.printLine(self.io, line) catch {};
            },
            .summarization_retry_finished => {},
            .tool_call, .tool_result => {},
            else => {},
        }
    }
};

fn runOneWithImages(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    client: ai.ModelClient,
    sess: *agent.session.Session,
    prompt: []const u8,
    images: []const agent.UserImage,
    agent_cfg: agent.AgentConfig,
    verbose: bool,
    render_options: InteractiveRenderOptions,
    extension_host: *extensions.Host,
) !void {
    var emitter = ExtensionPrintEmitter{
        .io = io,
        .verbose = verbose,
        .width = render_options.width,
        .capabilities = render_options.capabilities,
        .show_images = render_options.show_images,
        .image_width_cells = render_options.image_width_cells,
        .host = extension_host,
    };
    if (render_options.show_terminal_progress) try tui.render.writeAll(io, tui.terminal.progress_active_sequence);
    defer if (render_options.show_terminal_progress) tui.render.writeAll(io, tui.terminal.progress_clear_sequence) catch {};
    var result = try agent.runWithImages(gpa, io, cwd, client, sess, prompt, images, agent_cfg, ExtensionPrintEmitter.onEvent, &emitter);
    defer result.deinit(gpa);
    if (!verbose) {
        const transformed = extension_host.transformMarkdown(result.final_text, "assistant", false, render_options.width) catch try gpa.dupe(u8, result.final_text);
        defer gpa.free(transformed);
        try tui.render.renderAssistantMarkdownPadded(gpa, io, transformed, render_options.width, render_options.capabilities, render_options.output_pad);
    }
}

fn runOne(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    client: ai.ModelClient,
    sess: *agent.session.Session,
    prompt: []const u8,
    agent_cfg: agent.AgentConfig,
    verbose: bool,
    render_options: InteractiveRenderOptions,
    extension_host: *extensions.Host,
) !void {
    var emitter = ExtensionPrintEmitter{
        .io = io,
        .verbose = verbose,
        .width = render_options.width,
        .capabilities = render_options.capabilities,
        .show_images = render_options.show_images,
        .image_width_cells = render_options.image_width_cells,
        .host = extension_host,
    };
    if (render_options.show_terminal_progress) try tui.render.writeAll(io, tui.terminal.progress_active_sequence);
    defer if (render_options.show_terminal_progress) tui.render.writeAll(io, tui.terminal.progress_clear_sequence) catch {};
    var result = try agent.run(gpa, io, cwd, client, sess, prompt, agent_cfg, ExtensionPrintEmitter.onEvent, &emitter);
    defer result.deinit(gpa);
    if (!verbose) {
        const transformed = extension_host.transformMarkdown(result.final_text, "assistant", false, render_options.width) catch try gpa.dupe(u8, result.final_text);
        defer gpa.free(transformed);
        try tui.render.renderAssistantMarkdownPadded(gpa, io, transformed, render_options.width, render_options.capabilities, render_options.output_pad);
    }
}

const RpcSummarizationEmitter = struct {
    io: Io,

    fn onEvent(raw: ?*anyopaque, event: agent.summarization.Event) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var out: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer out.deinit();
        switch (event.kind) {
            .retry_scheduled => {
                out.writer.print("{{\"type\":\"summarization_retry_scheduled\",\"attempt\":{d},\"maxAttempts\":{d},\"delayMs\":{d},\"errorMessage\":", .{
                    event.attempt,
                    event.max_attempts,
                    event.delay_ms,
                }) catch return;
                std.json.Stringify.value(event.error_message, .{}, &out.writer) catch return;
                out.writer.writeAll("}\n") catch return;
            },
            .retry_attempt_start => {
                out.writer.writeAll("{\"type\":\"summarization_retry_attempt_start\",\"source\":") catch return;
                std.json.Stringify.value(event.source.wireName(), .{}, &out.writer) catch return;
                if (event.source == .compaction) {
                    out.writer.writeAll(",\"reason\":") catch return;
                    std.json.Stringify.value(event.reason.wireName(), .{}, &out.writer) catch return;
                }
                out.writer.writeAll("}\n") catch return;
            },
            .retry_finished => out.writer.writeAll("{\"type\":\"summarization_retry_finished\"}\n") catch return,
        }
        tui.render.writeAll(self.io, out.written()) catch {};
    }
};

fn flushRpcHookActions(
    gpa: std.mem.Allocator,
    runtime: *ExtensionActionRuntime,
    sess: *agent.session.Session,
    run_config: *agent.AgentConfig,
    active_client: *ai.ModelClient,
    steering_queue: *coding.rpc_queue.MessageQueue,
    follow_up_queue: *coding.rpc_queue.MessageQueue,
) !bool {
    const callback = run_config.flush_runtime_actions_fn orelse return false;
    var steering: std.ArrayList([]u8) = .empty;
    defer {
        for (steering.items) |message| gpa.free(message);
        steering.deinit(gpa);
    }
    var followups: std.ArrayList([]u8) = .empty;
    defer {
        for (followups.items) |message| gpa.free(message);
        followups.deinit(gpa);
    }
    var stop_requested = false;
    try callback(
        run_config.flush_runtime_actions_ctx orelse runtime,
        gpa,
        sess,
        run_config,
        active_client,
        &steering,
        &followups,
        &stop_requested,
    );
    for (steering.items) |message| try steering_queue.push(message);
    for (followups.items) |message| try follow_up_queue.push(message);
    return stop_requested;
}

fn runRpcMode(
    gpa: std.mem.Allocator,
    io: Io,
    arena: std.mem.Allocator,
    cwd: []const u8,
    client_pool: *coding.live_state.ClientPool,
    sess: *agent.session.Session,
    agent_cfg: *agent.AgentConfig,
    live: *coding.live_state.LiveState,
    provider_name: *?[]const u8,
    extension_host: *extensions.Host,
    extension_action_runtime: *ExtensionActionRuntime,
    initial_steering: *std.ArrayList([]const u8),
    initial_followups: *std.ArrayList([]const u8),
    extension_commands: *const std.ArrayList(coding.rpc_data.ExtensionCommandInfo),
    prompt_templates: *const []coding.prompts.PromptTemplate,
    session_path: ?[]const u8,
    no_session: bool,
    use_mock: bool,
    mock_storage: ?*ai.mock.MockModel,
) !void {
    var active_session_path: ?[]const u8 = session_path;
    var configured_auto_compaction_enabled = agent_cfg.auto_compaction_enabled;
    var auto_compaction_enabled = configured_auto_compaction_enabled;
    var auto_retry_enabled = agent_cfg.retry_enabled;
    var retry_abort_requested = false;
    var abort_flag: bool = false;
    var bash_abort_flag: bool = false;
    var steer_queue = coding.rpc_queue.MessageQueue.init(gpa, io);
    defer steer_queue.deinit();
    var follow_up_queue = coding.rpc_queue.MessageQueue.init(gpa, io);
    defer follow_up_queue.deinit();
    for (initial_steering.items) |message| try steer_queue.push(message);
    for (initial_followups.items) |message| try follow_up_queue.push(message);
    for (initial_steering.items) |message| gpa.free(message);
    initial_steering.clearRetainingCapacity();
    for (initial_followups.items) |message| gpa.free(message);
    initial_followups.clearRetainingCapacity();
    agent_cfg.abort_flag = &abort_flag;
    agent_cfg.retry_abort_flag = &retry_abort_requested;
    // Mid-HTTP cancel: live OpenAI/Anthropic SSE writers poll this flag.
    client_pool.setAbortFlag(&abort_flag);
    agent_cfg.steer_queue = null;
    agent_cfg.take_steer_fn = coding.rpc_queue.MessageQueue.take;
    agent_cfg.take_steer_ctx = &steer_queue;
    agent_cfg.follow_up_queue = null;
    agent_cfg.take_follow_up_fn = coding.rpc_queue.MessageQueue.take;
    agent_cfg.take_follow_up_ctx = &follow_up_queue;
    agent_cfg.session_file = active_session_path;

    // Always-on stdin inbox thread so abort/steer work while agent.run is in flight.
    const Inbox = struct {
        mutex: std.Io.Mutex = .init,
        cond: std.Io.Condition = .init,
        lines: std.ArrayList([]u8) = .empty,
        closed: bool = false,
    };
    const inbox_allocator = std.heap.page_allocator;
    const inbox = try gpa.create(Inbox);
    inbox.* = .{};

    const StdinCtx = struct {
        io: Io,
        guard: std.Io.Mutex = .init,
        inbox: ?*Inbox,
    };
    // The reader may remain blocked in the process stdin syscall after an RPC
    // `quit`. Keep only this tiny synchronization context process-lifetime and
    // detach it from all DebugAllocator-owned state before returning. The OS
    // reclaims it with the detached reader at process exit.
    const sctx = try inbox_allocator.create(StdinCtx);
    sctx.* = .{ .io = io, .inbox = inbox };
    var stdin_started = false;
    errdefer if (!stdin_started) inbox_allocator.destroy(sctx);
    const stdin_thread = try std.Thread.spawn(.{}, struct {
        fn closeInbox(ctx: *StdinCtx) void {
            ctx.guard.lockUncancelable(ctx.io);
            defer ctx.guard.unlock(ctx.io);
            const target = ctx.inbox orelse return;
            target.mutex.lockUncancelable(ctx.io);
            target.closed = true;
            target.cond.broadcast(ctx.io);
            target.mutex.unlock(ctx.io);
        }

        fn run(ctx: *StdinCtx) void {
            var buf: [8192]u8 = undefined;
            var reader: Io.File.Reader = .init(.stdin(), ctx.io, &buf);
            while (true) {
                const line = readLine(&reader, inbox_allocator) catch {
                    closeInbox(ctx);
                    return;
                };

                ctx.guard.lockUncancelable(ctx.io);
                const target = ctx.inbox orelse {
                    ctx.guard.unlock(ctx.io);
                    inbox_allocator.free(line);
                    return;
                };
                target.mutex.lockUncancelable(ctx.io);
                target.lines.append(inbox_allocator, line) catch {
                    inbox_allocator.free(line);
                };
                target.cond.signal(ctx.io);
                target.mutex.unlock(ctx.io);
                ctx.guard.unlock(ctx.io);
            }
        }
    }.run, .{sctx});
    stdin_started = true;
    // Detach: the read may remain blocked until process exit. The cleanup below
    // first severs its guarded Inbox pointer, so it cannot touch freed state.
    stdin_thread.detach();
    defer {
        sctx.guard.lockUncancelable(io);
        sctx.inbox = null;
        sctx.guard.unlock(io);
        for (inbox.lines.items) |l| inbox_allocator.free(l);
        inbox.lines.deinit(inbox_allocator);
        gpa.destroy(inbox);
    }

    // Emit session header once so clients can correlate (json.md / rpc.md)
    {
        var hdr = coding.modes.JsonEmitter{
            .io = io,
            .session_id = sess.id,
            .cwd = cwd,
        };
        hdr.emitHeader();
    }

    // Agent busy state for concurrent control commands
    var agent_busy = std.atomic.Value(bool).init(false);

    while (true) {
        // Wait for a line
        inbox.mutex.lockUncancelable(io);
        while (inbox.lines.items.len == 0 and !inbox.closed) {
            inbox.cond.waitUncancelable(io, &inbox.mutex);
        }
        if (inbox.lines.items.len == 0 and inbox.closed) {
            inbox.mutex.unlock(io);
            break;
        }
        const line = inbox.lines.orderedRemove(0);
        inbox.mutex.unlock(io);
        defer inbox_allocator.free(line);

        // Strict JSONL: strip optional CR only
        var trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
            trimmed = trimmed[0 .. trimmed.len - 1];
        }
        trimmed = std.mem.trim(u8, trimmed, " \t");
        if (trimmed.len == 0) continue;

        var req = coding.modes.parseRpcLine(gpa, trimmed) catch {
            try coding.modes.writeRpcResponse(io, "", "error", false, "{\"error\":\"invalid request\"}");
            continue;
        };
        defer coding.modes.freeRpcRequest(gpa, &req);

        // Concurrent commands always allowed
        if (std.mem.eql(u8, req.method, "abort")) {
            @atomicStore(bool, &abort_flag, true, .release);
            @atomicStore(bool, &bash_abort_flag, true, .release);
            try coding.modes.writeRpcResponse(io, req.id, "abort", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "abort_bash")) {
            @atomicStore(bool, &bash_abort_flag, true, .release);
            try coding.modes.writeRpcResponse(io, req.id, "abort_bash", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "steer")) {
            const p = req.params_prompt orelse "";
            try steer_queue.push(p);
            try coding.modes.writeRpcResponse(io, req.id, "steer", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "follow_up")) {
            // Delivered only when agent would stop (idle), not mid tool-batch
            const p = req.params_prompt orelse "";
            try follow_up_queue.push(p);
            try coding.modes.writeRpcResponse(io, req.id, "follow_up", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "ping")) {
            try coding.modes.writeRpcResponse(io, req.id, "ping", true, "\"pong\"");
            continue;
        }

        // While agent is busy, only concurrent commands above are accepted for other methods
        if (agent_busy.load(.acquire)) {
            try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"agent busy; use abort/steer/follow_up/ping\"}");
            continue;
        }

        if (std.mem.eql(u8, req.method, "quit") or std.mem.eql(u8, req.method, "exit")) {
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, null);
            break;
        }
        if (std.mem.eql(u8, req.method, "new_session")) {
            const new_id = try agent.session.generateSessionId(gpa);
            defer gpa.free(new_id);
            var fresh = try agent.session.Session.init(gpa, new_id, cwd);
            errdefer fresh.deinit();
            sess.deinit();
            sess.* = fresh;
            if (!no_session) {
                if (active_session_path) |old_path| {
                    const dir = std.fs.path.dirname(old_path) orelse ".";
                    active_session_path = try agent.session.newSessionPath(arena, dir, new_id);
                }
            } else active_session_path = null;
            agent_cfg.session_id = sess.id;
            agent_cfg.session_file = active_session_path;
            client_pool.setSessionContext(sess.id, client_pool.cache_retention);
            try coding.modes.writeRpcResponse(io, req.id, "new_session", true, "{\"cancelled\":false}");
            continue;
        }
        if (std.mem.eql(u8, req.method, "reload")) {
            const status = coding.live_state.applyReload(live) catch |err| {
                const data = try std.fmt.allocPrint(arena, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
                try coding.modes.writeRpcResponse(io, req.id, "reload", false, data);
                continue;
            };
            defer gpa.free(status);
            configured_auto_compaction_enabled = agent_cfg.auto_compaction_enabled;
            auto_compaction_enabled = configured_auto_compaction_enabled;
            auto_retry_enabled = agent_cfg.retry_enabled;
            if (auto_retry_enabled) @atomicStore(bool, &retry_abort_requested, false, .release);
            var data_writer: std.Io.Writer.Allocating = .init(arena);
            try data_writer.writer.writeAll("{\"message\":");
            try std.json.Stringify.value(status, .{}, &data_writer.writer);
            try data_writer.writer.writeByte('}');
            try coding.modes.writeRpcResponse(io, req.id, "reload", true, data_writer.written());
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_available_models")) {
            const catalog = if (live.model_catalog.len > 0) live.model_catalog else &ai.providers.known_models;
            const data = try formatAvailableModelsJson(arena, catalog);
            try coding.modes.writeRpcResponse(io, req.id, "get_available_models", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_model")) {
            const mid = req.model_id orelse {
                try coding.modes.writeRpcResponse(io, req.id, "set_model", false, "{\"error\":\"modelId required\"}");
                continue;
            };
            const reference = if (req.provider) |public_provider|
                try std.fmt.allocPrint(arena, "{s}/{s}", .{ public_provider, mid })
            else
                mid;
            coding.live_state.applyModel(live, reference) catch |err| {
                const data = try std.fmt.allocPrint(arena, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
                try coding.modes.writeRpcResponse(io, req.id, "set_model", false, data);
                continue;
            };
            const active = findActiveModelInfo(live, provider_name.*) orelse {
                try coding.modes.writeRpcResponse(io, req.id, "set_model", false, "{\"error\":\"model metadata unavailable\"}");
                continue;
            };
            const thinking_changed = try coding.live_state.applyThinkingForModelSwitch(live, active, null);
            _ = try sess.appendModelChange(active.providerName(), active.id);
            if (thinking_changed) _ = try sess.appendThinkingLevelChange(live.thinking orelse "off");
            if (active_session_path) |sp| if (!no_session) try sess.save(io, sp);
            const data = try formatModelJson(arena, active);
            try coding.modes.writeRpcResponse(io, req.id, "set_model", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "cycle_model")) {
            const current = live.model_display.* orelse "mock";
            const catalog = if (live.model_catalog.len > 0) live.model_catalog else &ai.providers.known_models;
            const next = nextKnownModel(catalog, current, provider_name.*);
            if (next) |n| {
                const combined = try std.fmt.allocPrint(arena, "{s}/{s}", .{ n.providerName(), n.id });
                coding.live_state.applyModel(live, combined) catch |err| {
                    const data = try std.fmt.allocPrint(arena, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
                    try coding.modes.writeRpcResponse(io, req.id, "cycle_model", false, data);
                    continue;
                };
                const scoped_thinking = coding.live_state.scopedThinkingForModel(live, n);
                const thinking_changed = try coding.live_state.applyThinkingForModelSwitch(live, n, scoped_thinking);
                _ = try sess.appendModelChange(n.providerName(), n.id);
                if (thinking_changed) _ = try sess.appendThinkingLevelChange(live.thinking orelse "off");
                if (active_session_path) |sp| if (!no_session) try sess.save(io, sp);
                var data_writer: std.Io.Writer.Allocating = .init(arena);
                try data_writer.writer.writeAll("{\"model\":");
                try writeModelJson(&data_writer.writer, n);
                try data_writer.writer.writeAll(",\"thinkingLevel\":");
                if (live.thinking) |level| try std.json.Stringify.value(level, .{}, &data_writer.writer) else try data_writer.writer.writeAll("null");
                try data_writer.writer.print(",\"isScoped\":{s}}}", .{if (live.model_scope.len > 0) "true" else "false"});
                try coding.modes.writeRpcResponse(io, req.id, "cycle_model", true, data_writer.written());
            } else {
                try coding.modes.writeRpcResponse(io, req.id, "cycle_model", true, "null");
            }
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_thinking_level")) {
            const level = req.thinking_level orelse {
                try coding.modes.writeRpcResponse(io, req.id, "set_thinking_level", false, "{\"error\":\"thinkingLevel required\"}");
                continue;
            };
            const requested_level = ai.thinking.ThinkingLevel.parse(level) orelse {
                try coding.modes.writeRpcResponse(io, req.id, "set_thinking_level", false, "{\"error\":\"invalid thinkingLevel\"}");
                continue;
            };
            const effective_level = if (coding.live_state.activeModelInfo(live)) |active|
                active.clampThinkingLevel(requested_level)
            else
                requested_level;
            const level_name = @tagName(effective_level);
            try coding.live_state.applyThinking(live, level_name);
            _ = try sess.appendThinkingLevelChange(level_name);
            if (active_session_path) |sp| if (!no_session) try sess.save(io, sp);
            try coding.modes.writeRpcResponse(io, req.id, "set_thinking_level", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "cycle_thinking_level")) {
            var levels_buf: [7]ai.thinking.ThinkingLevel = undefined;
            const levels = availableThinkingLevels(live, provider_name.*, &levels_buf);
            if (levels.len <= 1) {
                try coding.modes.writeRpcResponse(io, req.id, "cycle_thinking_level", true, "null");
                continue;
            }
            const current = if (live.thinking) |value| ai.thinking.ThinkingLevel.parse(value) else null;
            var current_index: ?usize = null;
            if (current) |value| {
                for (levels, 0..) |candidate, i| {
                    if (candidate == value) {
                        current_index = i;
                        break;
                    }
                }
            }
            const next_index = if (current_index) |i| (i + 1) % levels.len else 0;
            const next_level = @tagName(levels[next_index]);
            try coding.live_state.applyThinking(live, next_level);
            _ = try sess.appendThinkingLevelChange(next_level);
            if (active_session_path) |sp| if (!no_session) try sess.save(io, sp);
            const data = try std.fmt.allocPrint(arena, "{{\"level\":{s}}}", .{try jsonString(arena, next_level)});
            try coding.modes.writeRpcResponse(io, req.id, "cycle_thinking_level", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_available_thinking_levels")) {
            var levels_buf: [7]ai.thinking.ThinkingLevel = undefined;
            const levels = availableThinkingLevels(live, provider_name.*, &levels_buf);
            const data = try formatThinkingLevelsJson(arena, levels);
            try coding.modes.writeRpcResponse(io, req.id, "get_available_thinking_levels", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_steering_mode") or std.mem.eql(u8, req.method, "set_follow_up_mode")) {
            const mode_text = req.mode orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"mode required\"}");
                continue;
            };
            const queue_mode = agent.loop.QueueMode.parse(mode_text) orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"mode must be all or one-at-a-time\"}");
                continue;
            };
            if (std.mem.eql(u8, req.method, "set_steering_mode")) agent_cfg.steering_mode = queue_mode else agent_cfg.follow_up_mode = queue_mode;
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_auto_compaction")) {
            const enabled = req.enabled orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"enabled required\"}");
                continue;
            };
            if (live.agent_dir) |agent_dir| {
                coding.settings.setCompactionEnabled(gpa, io, agent_dir, enabled) catch |err| {
                    var failure: std.Io.Writer.Allocating = .init(arena);
                    try failure.writer.writeAll("{\"error\":");
                    try std.json.Stringify.value(@errorName(err), .{}, &failure.writer);
                    try failure.writer.writeByte('}');
                    try coding.modes.writeRpcResponse(io, req.id, req.method, false, failure.written());
                    continue;
                };
            }
            auto_compaction_enabled = enabled;
            agent_cfg.auto_compaction_enabled = enabled;
            configured_auto_compaction_enabled = enabled;
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_auto_retry")) {
            const requested = req.enabled orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"enabled required\"}");
                continue;
            };
            if (live.agent_dir) |agent_dir| {
                coding.settings.setRetryEnabled(gpa, io, agent_dir, requested) catch |err| {
                    var failure: std.Io.Writer.Allocating = .init(arena);
                    try failure.writer.writeAll("{\"error\":");
                    try std.json.Stringify.value(@errorName(err), .{}, &failure.writer);
                    try failure.writer.writeByte('}');
                    try coding.modes.writeRpcResponse(io, req.id, req.method, false, failure.written());
                    continue;
                };
            }
            auto_retry_enabled = requested;
            agent_cfg.retry_enabled = requested;
            if (requested) @atomicStore(bool, &retry_abort_requested, false, .release);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "abort_retry")) {
            @atomicStore(bool, &retry_abort_requested, true, .release);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_state")) {
            const pending = steer_queue.count() + follow_up_queue.count();
            const streaming = agent_busy.load(.acquire);
            var aw: std.Io.Writer.Allocating = .init(arena);
            try aw.writer.writeAll("{\"model\":");
            if (findActiveModelInfo(live, provider_name.*)) |active_model| {
                try writeModelJson(&aw.writer, active_model);
            } else {
                try aw.writer.writeAll("null");
            }
            try aw.writer.writeAll(",\"thinkingLevel\":");
            if (live.thinking) |thinking| try std.json.Stringify.value(thinking, .{}, &aw.writer) else try aw.writer.writeAll("null");
            try aw.writer.print(",\"isStreaming\":{s},\"isCompacting\":false", .{if (streaming) "true" else "false"});
            try aw.writer.writeAll(",\"steeringMode\":");
            try std.json.Stringify.value(agent_cfg.steering_mode.wireName(), .{}, &aw.writer);
            try aw.writer.writeAll(",\"followUpMode\":");
            try std.json.Stringify.value(agent_cfg.follow_up_mode.wireName(), .{}, &aw.writer);
            try aw.writer.writeAll(",\"sessionFile\":");
            if (active_session_path) |path| try std.json.Stringify.value(path, .{}, &aw.writer) else try aw.writer.writeAll("null");
            try aw.writer.writeAll(",\"sessionId\":");
            try std.json.Stringify.value(sess.id, .{}, &aw.writer);
            try aw.writer.writeAll(",\"sessionName\":");
            if (sess.name.len > 0) try std.json.Stringify.value(sess.name, .{}, &aw.writer) else try aw.writer.writeAll("null");
            try aw.writer.print(",\"autoCompactionEnabled\":{s},\"autoRetryEnabled\":{s},\"retryAbortRequested\":{s},\"messageCount\":{d},\"pendingMessageCount\":{d}}}", .{
                if (auto_compaction_enabled) "true" else "false",
                if (auto_retry_enabled) "true" else "false",
                if (@atomicLoad(bool, &retry_abort_requested, .acquire)) "true" else "false",
                sess.entries.items.len,
                pending,
            });
            try coding.modes.writeRpcResponse(io, req.id, "get_state", true, aw.written());
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_messages")) {
            const data = try formatSessionMessagesJson(arena, sess);
            try coding.modes.writeRpcResponse(io, req.id, "get_messages", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "compact")) {
            var live_client: ai.ModelClient = if (use_mock) mock_storage.?.client() else client_pool.client;
            var retry_emitter: RpcSummarizationEmitter = .{ .io = io };
            agent.compaction.compact(sess, .{
                .io = io,
                .settings = .{
                    .enabled = true,
                    .reserve_tokens = agent_cfg.compaction_reserve_tokens,
                    .keep_recent_tokens = agent_cfg.compaction_keep_recent_tokens,
                },
                .client = live_client,
                .custom_instructions = req.custom_instructions,
                .reason = .manual,
                .retry_enabled = agent_cfg.retry_enabled,
                .retry_max_retries = agent_cfg.retry_max_retries,
                .retry_base_delay_ms = agent_cfg.retry_base_delay_ms,
                .retry_abort_flag = &retry_abort_requested,
                .on_retry_event = RpcSummarizationEmitter.onEvent,
                .retry_event_ctx = &retry_emitter,
                .hook_ctx = agent_cfg.hook_ctx,
                .before_hook_fn = agent_cfg.before_compact_fn,
                .after_hook_fn = agent_cfg.after_compact_fn,
                .will_retry = false,
            }) catch |err| {
                const stop_requested = try flushRpcHookActions(
                    gpa,
                    extension_action_runtime,
                    sess,
                    agent_cfg,
                    &live_client,
                    &steer_queue,
                    &follow_up_queue,
                );
                var failure: std.Io.Writer.Allocating = .init(arena);
                try failure.writer.writeAll("{\"error\":");
                try std.json.Stringify.value(if (err == error.CompactionCancelled) "Compaction cancelled" else @errorName(err), .{}, &failure.writer);
                try failure.writer.writeByte('}');
                try coding.modes.writeRpcResponse(io, req.id, "compact", false, failure.written());
                if (active_session_path) |sp| if (!no_session) try sess.save(io, sp);
                if (stop_requested) break;
                continue;
            };
            const after_context = try sess.contextEntries(gpa);
            defer gpa.free(after_context);
            var chars_after: u64 = 0;
            for (after_context) |entry| chars_after +|= @intCast(entry.content.len + entry.meta.thinking.len);
            const boundary = if (sess.entries.items.len > 0 and sess.entries.items[sess.entries.items.len - 1].entry_type == .compaction)
                &sess.entries.items[sess.entries.items.len - 1]
            else
                null;
            var data_writer: std.Io.Writer.Allocating = .init(arena);
            try data_writer.writer.writeAll("{\"summary\":");
            try std.json.Stringify.value(if (boundary) |entry| entry.content else "", .{}, &data_writer.writer);
            try data_writer.writer.writeAll(",\"firstKeptEntryId\":");
            if (boundary) |entry| {
                if (entry.first_kept_entry_id) |value| try std.json.Stringify.value(value, .{}, &data_writer.writer) else try data_writer.writer.writeAll("null");
            } else try data_writer.writer.writeAll("null");
            try data_writer.writer.print(",\"tokensBefore\":{d},\"estimatedTokensAfter\":{d},\"details\":", .{
                if (boundary) |entry| entry.tokens_before else 0,
                @divFloor(chars_after + 3, 4),
            });
            if (boundary) |entry| {
                if (entry.data_json) |details| try data_writer.writer.writeAll(details) else try data_writer.writer.writeAll("{}");
            } else try data_writer.writer.writeAll("{}");
            try data_writer.writer.writeByte('}');
            const stop_requested = try flushRpcHookActions(
                gpa,
                extension_action_runtime,
                sess,
                agent_cfg,
                &live_client,
                &steer_queue,
                &follow_up_queue,
            );
            try coding.modes.writeRpcResponse(io, req.id, "compact", true, data_writer.written());
            if (active_session_path) |sp| {
                if (!no_session) try sess.save(io, sp);
            }
            if (stop_requested) break;
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_entries")) {
            const data = coding.rpc_data.formatEntriesJson(gpa, sess, req.since) catch |err| {
                if (err == coding.rpc_data.Error.UnknownEntry) {
                    try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"entry cursor not found\"}");
                    continue;
                }
                return err;
            };
            defer gpa.free(data);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_tree")) {
            const data = try coding.rpc_data.formatTreeJson(gpa, sess);
            defer gpa.free(data);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_fork_messages")) {
            const data = try coding.rpc_data.formatForkMessagesJson(gpa, sess);
            defer gpa.free(data);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_last_assistant_text")) {
            const data = try coding.rpc_data.formatLastAssistantTextJson(gpa, sess);
            defer gpa.free(data);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_session_stats")) {
            const model_info = findActiveModelInfo(live, provider_name.*);
            const data = try coding.rpc_data.formatSessionStatsJson(gpa, sess, active_session_path, coding.rpc_data.activeContextWindow(model_info));
            defer gpa.free(data);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "set_session_name")) {
            const raw_name = req.name orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"name required\"}");
                continue;
            };
            const name = std.mem.trim(u8, raw_name, " \t\r\n");
            if (name.len == 0) {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"name must not be empty\"}");
                continue;
            }
            _ = try sess.appendSessionInfo(name);
            if (active_session_path) |sp| if (!no_session) try sess.save(io, sp);
            try coding.modes.writeRpcResponse(io, req.id, "set_session_name", true, null);
            continue;
        }
        if (std.mem.eql(u8, req.method, "export_html") or std.mem.eql(u8, req.method, "export")) {
            const path = req.output_path orelse "session.html";
            const html = try coding.export_html.exportHtml(gpa, sess);
            defer gpa.free(html);
            std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = html }) catch {
                try coding.modes.writeRpcResponse(io, req.id, "export_html", false, "{\"error\":\"write failed\"}");
                continue;
            };
            const data = try std.fmt.allocPrint(arena, "{{\"path\":{s}}}", .{try jsonString(arena, path)});
            try coding.modes.writeRpcResponse(io, req.id, "export_html", true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "switch_session")) {
            const path = req.session_path orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"sessionPath required\"}");
                continue;
            };
            const loaded = agent.session.Session.load(gpa, io, path) catch {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"could not load session\"}");
                continue;
            };
            sess.deinit();
            sess.* = loaded;
            active_session_path = try arena.dupe(u8, path);
            agent_cfg.session_id = sess.id;
            agent_cfg.session_file = active_session_path;
            client_pool.setSessionContext(sess.id, client_pool.cache_retention);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, "{\"cancelled\":false}");
            continue;
        }
        if (std.mem.eql(u8, req.method, "fork")) {
            const entry_id = req.entry_id orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"entryId required\"}");
                continue;
            };
            const branch = try sess.branchEntries(gpa);
            defer gpa.free(branch);
            var selected: ?*const agent.session.SessionEntry = null;
            for (branch) |entry| if (std.mem.eql(u8, entry.id, entry_id)) {
                selected = entry;
                break;
            };
            const entry = selected orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"entryId is not on the active branch\"}");
                continue;
            };
            if (!std.mem.eql(u8, entry.role, "user")) {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"entryId must identify a user message\"}");
                continue;
            }
            const editable_text = try gpa.dupe(u8, entry.content);
            defer gpa.free(editable_text);
            const parent_id = if (entry.parent_id) |parent| try gpa.dupe(u8, parent) else null;
            defer if (parent_id) |parent| gpa.free(parent);
            const new_id = try agent.session.generateSessionId(gpa);
            defer gpa.free(new_id);
            var forked = try sess.fork(gpa, new_id);
            errdefer forked.deinit();
            if (active_session_path) |old_path| try forked.setParentSession(old_path);
            if (parent_id) |parent| try forked.setTip(parent) else forked.resetTip();
            var new_path: ?[]const u8 = null;
            if (!no_session) if (active_session_path) |old_path| {
                const dir = std.fs.path.dirname(old_path) orelse ".";
                new_path = try agent.session.newSessionPath(arena, dir, new_id);
                try forked.save(io, new_path.?);
            };
            sess.deinit();
            sess.* = forked;
            active_session_path = new_path;
            agent_cfg.session_id = sess.id;
            agent_cfg.session_file = active_session_path;
            client_pool.setSessionContext(sess.id, client_pool.cache_retention);
            var data_writer: std.Io.Writer.Allocating = .init(arena);
            try data_writer.writer.writeAll("{\"text\":");
            try std.json.Stringify.value(editable_text, .{}, &data_writer.writer);
            try data_writer.writer.writeAll(",\"cancelled\":false}");
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data_writer.written());
            continue;
        }
        if (std.mem.eql(u8, req.method, "clone")) {
            const new_id = try agent.session.generateSessionId(gpa);
            defer gpa.free(new_id);
            var cloned = try sess.fork(gpa, new_id);
            errdefer cloned.deinit();
            if (active_session_path) |old_path| try cloned.setParentSession(old_path);
            var new_path: ?[]const u8 = null;
            if (!no_session) if (active_session_path) |old_path| {
                const dir = std.fs.path.dirname(old_path) orelse ".";
                new_path = try agent.session.newSessionPath(arena, dir, new_id);
                try cloned.save(io, new_path.?);
            };
            sess.deinit();
            sess.* = cloned;
            active_session_path = new_path;
            agent_cfg.session_id = sess.id;
            agent_cfg.session_file = active_session_path;
            client_pool.setSessionContext(sess.id, client_pool.cache_retention);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, "{\"cancelled\":false}");
            continue;
        }
        if (std.mem.eql(u8, req.method, "get_commands")) {
            var package_resources = coding.packages.Resources.init(gpa);
            defer package_resources.deinit();
            var top_resources = coding.top_level_resources.Resources.init(gpa);
            defer top_resources.deinit();
            if (live.agent_dir) |agent_dir| {
                const installed = try coding.packages.listConfigured(gpa, io, agent_dir, cwd, live.trust_project);
                defer {
                    for (installed) |*package| {
                        var owned = package.*;
                        owned.deinit(gpa);
                    }
                    gpa.free(installed);
                }
                package_resources.deinit();
                package_resources = try coding.packages.resolveResources(gpa, io, installed);
                top_resources.deinit();
                top_resources = try coding.top_level_resources.resolve(gpa, io, agent_dir, cwd, live.trust_project);
            }
            var resolved_skill_paths: std.ArrayList([]const u8) = .empty;
            defer resolved_skill_paths.deinit(gpa);
            const skills = if (agent_cfg.enable_skill_commands) skills_block: {
                try resolved_skill_paths.appendSlice(gpa, top_resources.skills.items);
                try resolved_skill_paths.appendSlice(gpa, package_resources.skills.items);
                break :skills_block if (live.agent_dir != null)
                    try coding.skills.loadTrusted(gpa, io, cwd, live.agent_dir, live.trust_project, resolved_skill_paths.items, false)
                else
                    try coding.skills.discoverTrusted(gpa, io, cwd, live.agent_dir, package_resources.skills.items, live.trust_project);
            } else try gpa.alloc(coding.skills.Skill, 0);
            defer {
                for (skills) |*skill| {
                    var owned = skill.*;
                    owned.deinit(gpa);
                }
                gpa.free(skills);
            }
            const data = try coding.rpc_data.formatCommandsJson(gpa, extension_commands.items, prompt_templates.*, skills, cwd, live.agent_dir);
            defer gpa.free(data);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, data);
            continue;
        }
        if (std.mem.eql(u8, req.method, "bash")) {
            const command = req.shell_command orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"command required\"}");
                continue;
            };
            @atomicStore(bool, &bash_abort_flag, false, .release);

            var args_writer: std.Io.Writer.Allocating = .init(gpa);
            defer args_writer.deinit();
            try args_writer.writer.writeAll("{\"command\":");
            try std.json.Stringify.value(command, .{}, &args_writer.writer);
            try args_writer.writer.writeByte('}');

            const BashProgressCtx = struct {
                io: Io,
                id: []const u8,
                mutex: std.Io.Mutex = .init,

                fn onProgress(ptr: ?*anyopaque, delta: []const u8) void {
                    const self: *@This() = @ptrCast(@alignCast(ptr.?));
                    self.mutex.lockUncancelable(self.io);
                    defer self.mutex.unlock(self.io);
                    coding.modes.writeBashExecutionUpdate(self.io, self.id, delta) catch {};
                }
            };
            var progress_ctx = BashProgressCtx{ .io = io, .id = req.id };

            const BashRunCtx = struct {
                tool_ctx: agent.ToolContext,
                arguments_json: []const u8,
                result: ?agent.ToolResult = null,
                err: ?anyerror = null,
                done: std.atomic.Value(bool) = .init(false),

                fn run(self: *@This()) void {
                    defer self.done.store(true, .release);
                    self.result = agent.execute(self.tool_ctx, "bash", self.arguments_json) catch |err| {
                        self.err = err;
                        return;
                    };
                }
            };
            var bash_ctx = BashRunCtx{
                .tool_ctx = .{
                    .gpa = gpa,
                    .io = io,
                    .cwd = cwd,
                    .environ = agent_cfg.process_environ,
                    .session_id = sess.id,
                    .session_file = active_session_path,
                    .provider_name = provider_name.*,
                    .model_id = live.model_display.*,
                    .reasoning_level = live.thinking,
                    .auto_resize_images = agent_cfg.auto_resize_images,
                    .abort_flag = &bash_abort_flag,
                    .progress_fn = BashProgressCtx.onProgress,
                    .progress_ctx = &progress_ctx,
                },
                .arguments_json = args_writer.written(),
            };
            const bash_thread = try std.Thread.spawn(.{}, BashRunCtx.run, .{&bash_ctx});

            var deferred_lines: std.ArrayList([]u8) = .empty;
            defer {
                for (deferred_lines.items) |queued| inbox_allocator.free(queued);
                deferred_lines.deinit(gpa);
            }
            while (!bash_ctx.done.load(.acquire)) {
                inbox.mutex.lockUncancelable(io);
                while (inbox.lines.items.len > 0) {
                    const queued_line = inbox.lines.orderedRemove(0);
                    inbox.mutex.unlock(io);
                    const queued_trimmed = std.mem.trim(u8, queued_line, " \t\r");
                    if (queued_trimmed.len == 0) {
                        inbox_allocator.free(queued_line);
                        inbox.mutex.lockUncancelable(io);
                        continue;
                    }
                    var queued_req = coding.modes.parseRpcLine(gpa, queued_trimmed) catch {
                        inbox_allocator.free(queued_line);
                        inbox.mutex.lockUncancelable(io);
                        continue;
                    };
                    if (std.mem.eql(u8, queued_req.method, "abort_bash")) {
                        @atomicStore(bool, &bash_abort_flag, true, .release);
                        coding.modes.writeRpcResponse(io, queued_req.id, queued_req.method, true, null) catch {};
                        inbox_allocator.free(queued_line);
                    } else if (std.mem.eql(u8, queued_req.method, "abort")) {
                        @atomicStore(bool, &bash_abort_flag, true, .release);
                        @atomicStore(bool, &abort_flag, true, .release);
                        coding.modes.writeRpcResponse(io, queued_req.id, queued_req.method, true, null) catch {};
                        inbox_allocator.free(queued_line);
                    } else if (std.mem.eql(u8, queued_req.method, "ping")) {
                        coding.modes.writeRpcResponse(io, queued_req.id, queued_req.method, true, "\"pong\"") catch {};
                        inbox_allocator.free(queued_line);
                    } else {
                        deferred_lines.append(gpa, queued_line) catch inbox_allocator.free(queued_line);
                    }
                    coding.modes.freeRpcRequest(gpa, &queued_req);
                    inbox.mutex.lockUncancelable(io);
                }
                inbox.mutex.unlock(io);
                if (!bash_ctx.done.load(.acquire)) {
                    const sleep: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .real } };
                    sleep.sleep(io) catch {};
                }
            }
            bash_thread.join();

            if (deferred_lines.items.len > 0) {
                inbox.mutex.lockUncancelable(io);
                var index = deferred_lines.items.len;
                while (index > 0) {
                    index -= 1;
                    inbox.lines.insert(inbox_allocator, 0, deferred_lines.items[index]) catch inbox_allocator.free(deferred_lines.items[index]);
                }
                deferred_lines.clearRetainingCapacity();
                inbox.mutex.unlock(io);
            }

            if (bash_ctx.err) |err| {
                const error_data = try std.fmt.allocPrint(arena, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, error_data);
                continue;
            }
            var tool_result = bash_ctx.result orelse {
                try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"bash produced no result\"}");
                continue;
            };
            defer tool_result.deinit(gpa);
            var parsed_result = try coding.rpc_bash.parse(gpa, tool_result.content, tool_result.is_error);
            defer parsed_result.deinit(gpa);
            const response_data = try coding.rpc_bash.formatJson(gpa, parsed_result);
            defer gpa.free(response_data);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, response_data);

            _ = try sess.appendBashExecution(
                sess.lastEntryId(),
                command,
                parsed_result.output,
                parsed_result.exit_code,
                parsed_result.cancelled,
                parsed_result.truncated,
                null,
                req.exclude_from_context orelse false,
            );
            if (active_session_path) |sp| if (!no_session) try sess.save(io, sp);
            continue;
        }
        if (std.mem.eql(u8, req.method, "prompt")) {
            var prompt: []const u8 = req.params_prompt orelse "";
            var prompt_owned: ?[]u8 = null;
            defer if (prompt_owned) |value| gpa.free(value);
            var command_output: ?extensions.host.CommandOutput = null;
            defer if (command_output) |*output| output.deinit(gpa);
            var response_data: ?[]u8 = null;
            defer if (response_data) |value| gpa.free(value);

            if (prompt.len > 0 and prompt[0] == '/' and !coding.slash.isBuiltinCommand(prompt)) {
                if (try executeExtensionInvocation(extension_host, prompt)) |output| {
                    command_output = output;
                    var command_steering: std.ArrayList([]const u8) = .empty;
                    defer {
                        for (command_steering.items) |message| gpa.free(message);
                        command_steering.deinit(gpa);
                    }
                    var command_followups: std.ArrayList([]const u8) = .empty;
                    defer {
                        for (command_followups.items) |message| gpa.free(message);
                        command_followups.deinit(gpa);
                    }
                    var command_client: ai.ModelClient = if (use_mock) mock_storage.?.client() else client_pool.client;
                    var applied = try applyExtensionCommandOutput(
                        gpa,
                        io,
                        extension_action_runtime,
                        sess,
                        &command_output.?,
                        agent_cfg,
                        &command_client,
                        &command_steering,
                        &command_followups,
                    );
                    defer applied.deinit(gpa);
                    for (command_steering.items) |message| try steer_queue.push(message);
                    for (command_followups.items) |message| try follow_up_queue.push(message);

                    const invocation = parseSlashInvocation(prompt).?;
                    response_data = try formatExtensionCommandRpcData(gpa, invocation.name, &command_output.?);
                    if (applied.terminate or applied.is_error or applied.prompt == null) {
                        try coding.modes.writeRpcResponse(io, req.id, req.method, !applied.is_error, response_data.?);
                        if (applied.terminate) break;
                        continue;
                    }
                    prompt_owned = applied.prompt;
                    applied.prompt = null;
                    prompt = prompt_owned.?;
                } else if (try coding.prompts.expandInvocation(gpa, prompt, prompt_templates.*)) |expanded| {
                    prompt_owned = expanded;
                    prompt = expanded;
                }
            }

            @atomicStore(bool, &abort_flag, false, .release);
            @atomicStore(bool, &retry_abort_requested, false, .release);
            try coding.modes.writeRpcResponse(io, req.id, req.method, true, if (response_data) |data| data else null);

            // Run agent on background thread; main loop continues draining inbox for abort/steer.
            const RunCtx = struct {
                gpa: std.mem.Allocator,
                io: Io,
                cwd: []const u8,
                client: ai.ModelClient,
                sess: *agent.session.Session,
                agent_cfg: agent.AgentConfig,
                prompt: []const u8,
                session_id: []const u8,
                busy: *std.atomic.Value(bool),
                err: ?anyerror = null,
            };
            const rctx = try gpa.create(RunCtx);
            const live_client: ai.ModelClient = if (use_mock) mock_storage.?.client() else client_pool.client;
            rctx.* = .{
                .gpa = gpa,
                .io = io,
                .cwd = cwd,
                .client = live_client,
                .sess = sess,
                .agent_cfg = agent_cfg.*,
                .prompt = try gpa.dupe(u8, prompt),
                .session_id = sess.id,
                .busy = &agent_busy,
            };
            agent_busy.store(true, .release);
            const agent_thread = try std.Thread.spawn(.{}, struct {
                fn run(ctx: *RunCtx) void {
                    defer {
                        ctx.gpa.free(ctx.prompt);
                        ctx.busy.store(false, .release);
                        ctx.gpa.destroy(ctx);
                    }
                    var emitter = coding.modes.RpcEventEmitter.init(ctx.io);
                    emitter.json.session_id = ctx.session_id;
                    emitter.json.cwd = ctx.cwd;
                    emitter.json.emitted_header = true;
                    var result = agent.run(ctx.gpa, ctx.io, ctx.cwd, ctx.client, ctx.sess, ctx.prompt, ctx.agent_cfg, coding.modes.RpcEventEmitter.onEvent, &emitter) catch {
                        return;
                    };
                    result.deinit(ctx.gpa);
                }
            }.run, .{rctx});
            // Detach: main continues reading inbox; next non-concurrent command waits via agent_busy
            agent_thread.detach();
            // Keep servicing the protocol while the agent is running. Commands that
            // cannot run concurrently are held aside exactly once and restored in
            // arrival order after the turn; this avoids the old pop/requeue spin.
            var deferred_prompt_lines: std.ArrayList([]u8) = .empty;
            defer {
                for (deferred_prompt_lines.items) |queued| inbox_allocator.free(queued);
                deferred_prompt_lines.deinit(gpa);
            }
            while (agent_busy.load(.acquire)) {
                inbox.mutex.lockUncancelable(io);
                while (inbox.lines.items.len > 0) {
                    const concurrent_line = inbox.lines.orderedRemove(0);
                    inbox.mutex.unlock(io);
                    var retain_line = false;
                    const concurrent_trimmed = std.mem.trim(u8, concurrent_line, " \t\r");
                    if (concurrent_trimmed.len > 0) {
                        var concurrent_req = coding.modes.parseRpcLine(gpa, concurrent_trimmed) catch {
                            coding.modes.writeRpcResponse(io, "", "error", false, "{\"error\":\"invalid request\"}") catch {};
                            inbox_allocator.free(concurrent_line);
                            inbox.mutex.lockUncancelable(io);
                            continue;
                        };

                        if (std.mem.eql(u8, concurrent_req.method, "abort")) {
                            @atomicStore(bool, &abort_flag, true, .release);
                            coding.modes.writeRpcResponse(io, concurrent_req.id, "abort", true, null) catch {};
                        } else if (std.mem.eql(u8, concurrent_req.method, "abort_bash")) {
                            @atomicStore(bool, &bash_abort_flag, true, .release);
                            coding.modes.writeRpcResponse(io, concurrent_req.id, "abort_bash", true, null) catch {};
                        } else if (std.mem.eql(u8, concurrent_req.method, "abort_retry")) {
                            @atomicStore(bool, &retry_abort_requested, true, .release);
                            coding.modes.writeRpcResponse(io, concurrent_req.id, "abort_retry", true, null) catch {};
                        } else if (std.mem.eql(u8, concurrent_req.method, "steer")) {
                            const queued_prompt = concurrent_req.params_prompt orelse "";
                            if (steer_queue.push(queued_prompt)) |_| {
                                coding.modes.writeRpcResponse(io, concurrent_req.id, "steer", true, null) catch {};
                            } else |_| {
                                coding.modes.writeRpcResponse(io, concurrent_req.id, "steer", false, "{\"error\":\"could not queue message\"}") catch {};
                            }
                        } else if (std.mem.eql(u8, concurrent_req.method, "follow_up")) {
                            const queued_prompt = concurrent_req.params_prompt orelse "";
                            if (follow_up_queue.push(queued_prompt)) |_| {
                                coding.modes.writeRpcResponse(io, concurrent_req.id, "follow_up", true, null) catch {};
                            } else |_| {
                                coding.modes.writeRpcResponse(io, concurrent_req.id, "follow_up", false, "{\"error\":\"could not queue message\"}") catch {};
                            }
                        } else if (std.mem.eql(u8, concurrent_req.method, "prompt")) {
                            const behavior = concurrent_req.streaming_behavior;
                            if (behavior == null) {
                                coding.modes.writeRpcResponse(io, concurrent_req.id, "prompt", false, "{\"error\":\"streamingBehavior required while agent is streaming\"}") catch {};
                            } else if (std.ascii.eqlIgnoreCase(behavior.?, "steer")) {
                                const queued_prompt = concurrent_req.params_prompt orelse "";
                                if (steer_queue.push(queued_prompt)) |_| {
                                    coding.modes.writeRpcResponse(io, concurrent_req.id, "prompt", true, null) catch {};
                                } else |_| {
                                    coding.modes.writeRpcResponse(io, concurrent_req.id, "prompt", false, "{\"error\":\"could not queue message\"}") catch {};
                                }
                            } else if (std.ascii.eqlIgnoreCase(behavior.?, "followUp") or std.ascii.eqlIgnoreCase(behavior.?, "follow_up")) {
                                const queued_prompt = concurrent_req.params_prompt orelse "";
                                if (follow_up_queue.push(queued_prompt)) |_| {
                                    coding.modes.writeRpcResponse(io, concurrent_req.id, "prompt", true, null) catch {};
                                } else |_| {
                                    coding.modes.writeRpcResponse(io, concurrent_req.id, "prompt", false, "{\"error\":\"could not queue message\"}") catch {};
                                }
                            } else {
                                coding.modes.writeRpcResponse(io, concurrent_req.id, "prompt", false, "{\"error\":\"streamingBehavior must be steer or followUp\"}") catch {};
                            }
                        } else if (std.mem.eql(u8, concurrent_req.method, "ping")) {
                            coding.modes.writeRpcResponse(io, concurrent_req.id, "ping", true, "\"pong\"") catch {};
                        } else {
                            deferred_prompt_lines.append(gpa, concurrent_line) catch inbox_allocator.free(concurrent_line);
                            retain_line = true;
                        }
                        coding.modes.freeRpcRequest(gpa, &concurrent_req);
                    }
                    if (!retain_line) inbox_allocator.free(concurrent_line);
                    inbox.mutex.lockUncancelable(io);
                }
                inbox.mutex.unlock(io);
                if (!agent_busy.load(.acquire)) break;
                const st: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .real } };
                st.sleep(io) catch {};
            }

            if (deferred_prompt_lines.items.len > 0) {
                inbox.mutex.lockUncancelable(io);
                var deferred_index = deferred_prompt_lines.items.len;
                while (deferred_index > 0) {
                    deferred_index -= 1;
                    inbox.lines.insert(inbox_allocator, 0, deferred_prompt_lines.items[deferred_index]) catch inbox_allocator.free(deferred_prompt_lines.items[deferred_index]);
                }
                deferred_prompt_lines.clearRetainingCapacity();
                inbox.mutex.unlock(io);
            }
            if (active_session_path) |sp| {
                if (!no_session) try sess.save(io, sp);
            }
            continue;
        }
        try coding.modes.writeRpcResponse(io, req.id, req.method, false, "{\"error\":\"unknown command\"}");
    }
}

fn findActiveModelInfo(live: *const coding.live_state.LiveState, provider_name: ?[]const u8) ?ai.providers.ModelInfo {
    const model_id = live.model_display.* orelse return null;
    const provider_id = provider_name orelse if (live.client_pool) |pool| pool.active_provider_id else "";
    const catalog = if (live.model_catalog.len > 0) live.model_catalog else &ai.providers.known_models;
    for (catalog) |model| {
        if (std.mem.eql(u8, model.id, model_id) and std.ascii.eqlIgnoreCase(model.providerName(), provider_id)) return model;
    }
    // Preserve useful behavior when a caller changed only the model ID and provider
    // metadata is unavailable. Accept a unique model ID, but never guess across
    // duplicate IDs from different providers.
    var match: ?ai.providers.ModelInfo = null;
    for (catalog) |model| {
        if (!std.mem.eql(u8, model.id, model_id)) continue;
        if (match != null) return null;
        match = model;
    }
    return match;
}

fn availableThinkingLevels(
    live: *const coding.live_state.LiveState,
    provider_name: ?[]const u8,
    out: *[7]ai.thinking.ThinkingLevel,
) []const ai.thinking.ThinkingLevel {
    if (findActiveModelInfo(live, provider_name)) |model| return model.supportedThinkingLevels(out);
    out[0] = .off;
    return out[0..1];
}

fn formatThinkingLevelsJson(arena: std.mem.Allocator, levels: []const ai.thinking.ThinkingLevel) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll("{\"levels\":[");
    for (levels, 0..) |level, i| {
        if (i > 0) try aw.writer.writeByte(',');
        try std.json.Stringify.value(@tagName(level), .{}, &aw.writer);
    }
    try aw.writer.writeAll("]}");
    return try aw.toOwnedSlice();
}

fn writeModelJson(writer: *std.Io.Writer, model: ai.providers.ModelInfo) !void {
    try writer.writeAll("{\"id\":");
    try std.json.Stringify.value(model.id, .{}, writer);
    try writer.writeAll(",\"name\":");
    try std.json.Stringify.value(model.display, .{}, writer);
    try writer.writeAll(",\"api\":");
    try std.json.Stringify.value(model.apiKind().name(), .{}, writer);
    try writer.writeAll(",\"provider\":");
    try std.json.Stringify.value(model.providerName(), .{}, writer);
    try writer.writeAll(",\"baseUrl\":");
    const public_provider = ai.providers.Provider.fromString(model.providerName());
    const base_url = model.base_url orelse if (public_provider) |provider|
        ai.providers.defaultBaseUrl(provider)
    else
        ai.providers.defaultBaseUrl(model.provider);
    try std.json.Stringify.value(base_url, .{}, writer);
    try writer.writeAll(",\"reasoning\":");
    try writer.writeAll(if (model.reasoning) "true" else "false");
    try writer.writeAll(",\"input\":[");
    var wrote_input = false;
    if (model.input_text) {
        try writer.writeAll("\"text\"");
        wrote_input = true;
    }
    if (model.input_image) {
        if (wrote_input) try writer.writeByte(',');
        try writer.writeAll("\"image\"");
    }
    try writer.print("],\"contextWindow\":{d},\"maxTokens\":{d}", .{ model.context_window, model.max_tokens });
    try writer.writeAll(",\"cost\":{\"input\":");
    try writer.print("{d}", .{model.cost.input});
    try writer.writeAll(",\"output\":");
    try writer.print("{d}", .{model.cost.output});
    try writer.writeAll(",\"cacheRead\":");
    try writer.print("{d}", .{model.cost.cache_read});
    try writer.writeAll(",\"cacheWrite\":");
    try writer.print("{d}", .{model.cost.cache_write});
    try writer.writeAll("}}");
}

fn formatModelJson(arena: std.mem.Allocator, model: ai.providers.ModelInfo) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    try writeModelJson(&aw.writer, model);
    return aw.written();
}

fn formatAvailableModelsJson(arena: std.mem.Allocator, models: []const ai.providers.ModelInfo) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll("{\"models\":[");
    for (models, 0..) |model, i| {
        if (i > 0) try aw.writer.writeByte(',');
        try writeModelJson(&aw.writer, model);
    }
    try aw.writer.writeAll("]}");
    return aw.written();
}

fn nextKnownModel(models: []const ai.providers.ModelInfo, current_id: []const u8, current_provider: ?[]const u8) ?ai.providers.ModelInfo {
    var idx: ?usize = null;
    for (models, 0..) |m, i| {
        if (std.mem.eql(u8, m.id, current_id) and (current_provider == null or std.ascii.eqlIgnoreCase(m.providerName(), current_provider.?))) {
            idx = i;
            break;
        }
    }
    if (idx) |i| {
        if (models.len <= 1) return null;
        return models[(i + 1) % models.len];
    }
    // Unknown current — start at first
    if (models.len == 0) return null;
    return models[0];
}

fn formatSessionMessagesJson(arena: std.mem.Allocator, sess: *const agent.session.Session) ![]const u8 {
    const entries = try sess.contextEntries(arena);
    defer arena.free(entries);
    var aw: std.Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll("{\"messages\":[");
    var emitted: usize = 0;
    for (entries) |e| {
        if (sess.isEntryExcludedFromActiveContext(e.id)) continue;
        switch (e.entry_type) {
            .compaction => {
                if (emitted > 0) try aw.writer.writeByte(',');
                emitted += 1;
                try aw.writer.writeAll("{\"role\":\"compactionSummary\",\"summary\":");
                try std.json.Stringify.value(e.content, .{}, &aw.writer);
                try aw.writer.print(",\"tokensBefore\":{d}", .{e.tokens_before});
                if (e.timestamp.len > 0) {
                    try aw.writer.writeAll(",\"timestamp\":");
                    try std.json.Stringify.value(e.timestamp, .{}, &aw.writer);
                }
                try aw.writer.writeByte('}');
            },
            .branch_summary => {
                if (emitted > 0) try aw.writer.writeByte(',');
                emitted += 1;
                try aw.writer.writeAll("{\"role\":\"branchSummary\",\"summary\":");
                try std.json.Stringify.value(e.content, .{}, &aw.writer);
                try aw.writer.writeAll(",\"fromId\":");
                try std.json.Stringify.value(e.target_id orelse e.parent_id orelse "root", .{}, &aw.writer);
                if (e.timestamp.len > 0) {
                    try aw.writer.writeAll(",\"timestamp\":");
                    try std.json.Stringify.value(e.timestamp, .{}, &aw.writer);
                }
                try aw.writer.writeByte('}');
            },
            .custom_message => {
                if (emitted > 0) try aw.writer.writeByte(',');
                emitted += 1;
                try aw.writer.writeAll("{\"role\":\"custom\",\"customType\":");
                try std.json.Stringify.value(e.custom_type orelse "", .{}, &aw.writer);
                try aw.writer.writeAll(",\"content\":");
                try std.json.Stringify.value(e.content, .{}, &aw.writer);
                try aw.writer.writeAll(",\"display\":");
                try aw.writer.writeAll(if (e.display) "true" else "false");
                try aw.writer.writeByte('}');
            },
            .message => {
                if (emitted > 0) try aw.writer.writeByte(',');
                emitted += 1;
                try aw.writer.writeAll("{\"role\":");
                try std.json.Stringify.value(e.role, .{}, &aw.writer);
                if (std.mem.eql(u8, e.role, "bashExecution")) {
                    try aw.writer.writeAll(",\"command\":");
                    try std.json.Stringify.value(e.bash_command orelse "", .{}, &aw.writer);
                    try aw.writer.writeAll(",\"output\":");
                    try std.json.Stringify.value(e.bash_output orelse "", .{}, &aw.writer);
                    if (e.bash_exit_code) |code| try aw.writer.print(",\"exitCode\":{d}", .{code});
                    try aw.writer.writeAll(",\"cancelled\":");
                    try aw.writer.writeAll(if (e.bash_cancelled) "true" else "false");
                    try aw.writer.writeAll(",\"truncated\":");
                    try aw.writer.writeAll(if (e.bash_truncated) "true" else "false");
                    if (e.bash_full_output_path) |path| {
                        try aw.writer.writeAll(",\"fullOutputPath\":");
                        try std.json.Stringify.value(path, .{}, &aw.writer);
                    }
                    if (e.bash_exclude_from_context) try aw.writer.writeAll(",\"excludeFromContext\":true");
                    try aw.writer.print(",\"timestamp\":{d}", .{e.bash_timestamp_ms});
                } else {
                    try aw.writer.writeAll(",\"content\":");
                    try std.json.Stringify.value(e.content, .{}, &aw.writer);
                    if (e.meta.provider.len > 0) {
                        try aw.writer.writeAll(",\"provider\":");
                        try std.json.Stringify.value(e.meta.provider, .{}, &aw.writer);
                    }
                    if (e.meta.model.len > 0) {
                        try aw.writer.writeAll(",\"model\":");
                        try std.json.Stringify.value(e.meta.model, .{}, &aw.writer);
                    }
                    if (e.meta.stop_reason.len > 0) {
                        try aw.writer.writeAll(",\"stopReason\":");
                        try std.json.Stringify.value(e.meta.stop_reason, .{}, &aw.writer);
                    }
                }
                try aw.writer.writeByte('}');
            },
            else => {},
        }
    }
    try aw.writer.writeAll("]}");
    return try aw.toOwnedSlice();
}

fn jsonString(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    try std.json.Stringify.value(s, .{}, &aw.writer);
    return aw.written();
}

fn packageOffline(environ: *const std.process.Environ.Map, explicit: bool) bool {
    if (explicit) return true;
    const value = environ.get("PI_OFFLINE") orelse return false;
    return std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes");
}

fn packageJsonLine(io: Io, value: anytype) !void {
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    try std.json.Stringify.value(value, .{}, &aw.writer);
    try tui.render.printLine(io, aw.written());
}

fn reportPackageHealthWarning(
    io: Io,
    arena: std.mem.Allocator,
    scope: coding.packages.Scope,
    health: *const coding.packages.ScopeHealth,
) !void {
    if (health.operation.active) {
        const message = try std.fmt.allocPrint(arena, "warning: {s} package configuration is locked by pid {d} ({s}, started {d}); package mutations will wait briefly then fail safely", .{
            @tagName(scope),
            health.operation.pid,
            if (health.operation.operation.len > 0) health.operation.operation else "unknown operation",
            health.operation.started_ms,
        });
        try tui.render.printLine(io, message);
    } else if (health.operation.stale_metadata) {
        const message = try std.fmt.allocPrint(arena, "warning: {s} package lock contains stale owner metadata from pid {d}; run `pi repair{s}` to clear and verify package state", .{
            @tagName(scope),
            health.operation.pid,
            if (scope == .project) " --local --approve" else "",
        });
        try tui.render.printLine(io, message);
    }
    if (health.repair_markers > 0) {
        const message = try std.fmt.allocPrint(arena, "warning: {s} package scope has {d} interrupted update marker(s); run `pi repair{s}` before updating packages", .{
            @tagName(scope),
            health.repair_markers,
            if (scope == .project) " --local --approve" else "",
        });
        try tui.render.printLine(io, message);
    }
    if (health.legacy_packages_pending) {
        const message = try std.fmt.allocPrint(arena, "warning: {s} package configuration still uses legacy settings.json storage; `pi repair{s}` will migrate it atomically", .{
            @tagName(scope),
            if (scope == .project) " --local --approve" else "",
        });
        try tui.render.printLine(io, message);
    }
}

fn writePackageConfigInventoryJson(io: Io, gpa: std.mem.Allocator, inventory: *const coding.package_config.Inventory) !void {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try out.writer.writeAll("{\"scope\":");
    try std.json.Stringify.value(@tagName(inventory.write_scope), .{}, &out.writer);
    try out.writer.writeAll(",\"resources\":[");
    for (inventory.resources, 0..) |resource, index| {
        if (index > 0) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"package\":");
        try std.json.Stringify.value(resource.package_name, .{}, &out.writer);
        try out.writer.writeAll(",\"source\":");
        try std.json.Stringify.value(resource.package_source, .{}, &out.writer);
        try out.writer.writeAll(",\"packagePath\":");
        try std.json.Stringify.value(resource.package_path, .{}, &out.writer);
        try out.writer.writeAll(",\"packageScope\":");
        try std.json.Stringify.value(@tagName(resource.package_scope), .{}, &out.writer);
        try out.writer.writeAll(",\"origin\":");
        try std.json.Stringify.value(@tagName(resource.origin), .{}, &out.writer);
        try out.writer.writeAll(",\"selector\":");
        try std.json.Stringify.value(resource.selector, .{}, &out.writer);
        try out.writer.writeAll(",\"type\":");
        try std.json.Stringify.value(@tagName(resource.resource_type), .{}, &out.writer);
        try out.writer.writeAll(",\"path\":");
        try std.json.Stringify.value(resource.path, .{}, &out.writer);
        try out.writer.writeAll(",\"relativePath\":");
        try std.json.Stringify.value(resource.relative_path, .{}, &out.writer);
        try out.writer.writeAll(",\"displayName\":");
        try std.json.Stringify.value(resource.display_name, .{}, &out.writer);
        try out.writer.print(",\"enabled\":{},\"inheritedEnabled\":{}", .{ resource.enabled, resource.inherited_enabled });
        try out.writer.writeAll(",\"override\":");
        try std.json.Stringify.value(@tagName(resource.override_state), .{}, &out.writer);
        try out.writer.writeByte('}');
    }
    try out.writer.writeAll("]}");
    try tui.render.printLine(io, out.written());
}

fn printPackageConfigInventory(io: Io, arena: std.mem.Allocator, inventory: *const coding.package_config.Inventory) !void {
    if (inventory.resources.len == 0) {
        try tui.render.printLine(io, "(no configurable resources)");
        return;
    }
    var previous_selector: []const u8 = "";
    var previous_type: ?coding.package_config.ResourceType = null;
    for (inventory.resources) |resource| {
        if (!std.mem.eql(u8, previous_selector, resource.selector)) {
            const header = try std.fmt.allocPrint(arena, "\n{s} ({s}, {s})", .{ resource.package_name, @tagName(resource.package_scope), @tagName(resource.origin) });
            try tui.render.printLine(io, header);
            previous_selector = resource.selector;
            previous_type = null;
        }
        if (previous_type == null or previous_type.? != resource.resource_type) {
            const type_line = try std.fmt.allocPrint(arena, "  {s}", .{@tagName(resource.resource_type)});
            try tui.render.printLine(io, type_line);
            previous_type = resource.resource_type;
        }
        const marker = if (inventory.write_scope == .project) switch (resource.override_state) {
            .load => "[+]",
            .unload => "[-]",
            .inherit => if (resource.enabled) "[x]" else "[ ]",
        } else if (resource.enabled) "[x]" else "[ ]";
        const suffix = if (inventory.write_scope == .project and resource.override_state == .inherit)
            if (resource.inherited_enabled) " (inherited on)" else " (inherited off)"
        else
            "";
        const line = try std.fmt.allocPrint(arena, "    {s} {s}{s}", .{ marker, resource.relative_path, suffix });
        try tui.render.printLine(io, line);
    }
}

fn updateBootstrapOptions(
    environ: *const std.process.Environ.Map,
    settings: coding.settings.Settings,
) ai.bootstrap_http.Options {
    return .{
        .policy = .{
            .timeout_ms = settings.retry_provider_timeout_ms orelse 15_000,
            .max_retries = settings.retry_provider_max_retries orelse 2,
            .max_retry_delay_ms = settings.retry_provider_max_retry_delay_ms orelse 60_000,
        },
        .proxy = .{
            .environ = environ,
            .setting = settings.http_proxy,
        },
    };
}

const ModelRefreshSummary = struct {
    providers_matched: usize = 0,
    providers_refreshed: usize = 0,
    models_discovered: usize = 0,
    providers_skipped: usize = 0,
};

fn refreshModelCatalogsForCommand(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    settings: coding.settings.Settings,
) !ModelRefreshSummary {
    if (packageOffline(environ, false)) return error.ModelNetworkDisabled;
    var summary: ModelRefreshSummary = .{};
    var models_file = try coding.models_file.load(gpa, io, agent_dir);
    defer models_file.deinit();
    var store = try auth.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    const request_options = updateBootstrapOptions(environ, settings);
    const now_ms = std.Io.Clock.real.now(io).toMilliseconds();

    for (models_file.providers) |provider| {
        if (provider.oauth != .radius) continue;
        summary.providers_matched += 1;
        const base_url = provider.base_url orelse {
            summary.providers_skipped += 1;
            continue;
        };
        var credential = (try store.read(provider.id)) orelse {
            summary.providers_skipped += 1;
            continue;
        };
        defer credential.deinit(gpa);
        if (credential != .oauth) {
            summary.providers_skipped += 1;
            continue;
        }
        const gateway = try ai.radius_config.gatewayFromApiBase(gpa, base_url);
        defer gpa.free(gateway);
        if (credential.oauth.expires <= now_ms + 60_000 and credential.oauth.refresh.len > 0) {
            var refreshed = try auth.radius_oauth.refreshWithOptions(gpa, io, gateway, credential.oauth.refresh, request_options);
            defer refreshed.deinit(gpa);
            try store.setOAuth(provider.id, .{
                .refresh = refreshed.refresh,
                .access = refreshed.access,
                .expires = refreshed.expires_ms,
                .scope = refreshed.scope,
            });
            credential.deinit(gpa);
            credential = (try store.read(provider.id)).?;
        }
        var catalog = try coding.radius_refresh.refreshWithOptions(
            gpa,
            io,
            environ,
            agent_dir,
            provider.id,
            gateway,
            credential.oauth.access,
            request_options,
        );
        defer catalog.deinit(gpa);
        summary.providers_refreshed += 1;
        summary.models_discovered += catalog.entries.len;
    }

    if (try store.read("github-copilot")) |credential_value| {
        var credential = credential_value;
        defer credential.deinit(gpa);
        if (credential == .oauth and credential.oauth.refresh.len > 0) {
            summary.providers_matched += 1;
            var refreshed = auth.github_copilot_oauth.refreshCredentialWithOptions(
                gpa,
                io,
                credential.oauth.refresh,
                credential.oauth.enterprise_url,
                request_options,
            ) catch |err| switch (err) {
                error.ProviderRequestAborted, error.ProviderRequestTimeout => return err,
                else => {
                    summary.providers_skipped += 1;
                    return summary;
                },
            };
            defer refreshed.deinit(gpa);
            try store.setOAuth("github-copilot", .{
                .refresh = refreshed.refresh,
                .access = refreshed.access,
                .expires = refreshed.expires_ms,
                .enterprise_url = refreshed.enterprise_domain,
                .available_model_ids = refreshed.available_model_ids,
                .available_model_ids_present = true,
            });
            summary.providers_refreshed += 1;
            summary.models_discovered += refreshed.available_model_ids.len;
        }
    }
    return summary;
}

fn updateConfiguredPackagesForCommand(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    query: ?[]const u8,
    project_trusted: bool,
    runtime_options: coding.packages.RuntimeOptions,
) !coding.packages.UpdateResult {
    var result: coding.packages.UpdateResult = .{};
    const user_result = coding.packages.updateScopedWithOptions(gpa, io, agent_dir, cwd, query, .user, project_trusted, runtime_options) catch |err| switch (err) {
        error.PackageNotFound => coding.packages.UpdateResult{},
        else => return err,
    };
    result.add(user_result);
    if (project_trusted) {
        const project_result = coding.packages.updateScopedWithOptions(gpa, io, agent_dir, cwd, query, .project, true, runtime_options) catch |err| switch (err) {
            error.PackageNotFound => coding.packages.UpdateResult{},
            else => return err,
        };
        result.add(project_result);
    }
    if (query != null and result.matched == 0) return error.PackageNotFound;
    return result;
}

fn printUpdateUsage(io: Io) !void {
    try tui.render.printLine(io,
        \\Usage: pi update [source|self|pi] [--self|--extensions|--models|--all]
        \\                 [--extension SOURCE] [--approve|--no-approve]
        \\                 [--force] [--check] [--offline] [--json]
        \\
        \\Without an explicit target, updates Pi itself. --check resolves the
        \\latest release and update command without modifying the installation.
    );
}

fn runUpdateCommand(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    arena: std.mem.Allocator,
    cmd_args: []const []const u8,
) !void {
    const options = coding.update.parseCommandOptions(cmd_args) catch |err| {
        const message = switch (err) {
            error.MissingOptionValue => "error: --extension requires a source",
            error.ConflictingOptions => "error: conflicting update targets",
            error.TooManyArguments => "error: too many update arguments",
            error.UnknownOption => "error: unknown update option",
        };
        try tui.render.printLine(io, message);
        try printUpdateUsage(io);
        std.process.exit(2);
    };
    if (options.help) {
        try printUpdateUsage(io);
        return;
    }

    const agent_dir = config.agentDir(arena, environ) catch {
        try tui.render.printLine(io, "error: cannot resolve agent dir (set HOME/USERPROFILE or PI_AGENT_DIR)");
        std.process.exit(2);
    };
    config.ensureDir(io, agent_dir) catch {};
    const cwd = try std.process.currentPathAlloc(io, arena);
    var startup_settings = try coding.settings.loadMergeTrusted(gpa, io, agent_dir, cwd, false);
    defer startup_settings.deinit(gpa);
    const project_trusted = try resolveStartupProjectTrust(
        gpa,
        io,
        environ,
        agent_dir,
        cwd,
        options.trust_override,
        startup_settings.default_project_trust,
        false,
    );
    var runtime_settings = try coding.settings.loadMergeTrusted(gpa, io, agent_dir, cwd, project_trusted);
    defer runtime_settings.deinit(gpa);
    const offline = packageOffline(environ, options.offline);
    const runtime_options: coding.packages.RuntimeOptions = .{
        .offline = offline,
        .npm_command = runtime_settings.npm_command,
    };

    const includes_extensions = switch (options.target) {
        .all, .extensions => true,
        else => false,
    };
    const includes_self = switch (options.target) {
        .all, .self => true,
        else => false,
    };

    if (options.show_extensions_skipped_note and !options.json) {
        try tui.render.printLine(io, "Extensions are skipped. Run `pi update --extensions` to update installed packages.");
    }

    if (options.target == .models) {
        const summary = try refreshModelCatalogsForCommand(gpa, io, environ, agent_dir, runtime_settings);
        if (options.json) {
            try packageJsonLine(io, .{
                .target = "models",
                .providersMatched = summary.providers_matched,
                .providersRefreshed = summary.providers_refreshed,
                .modelsDiscovered = summary.models_discovered,
                .providersSkipped = summary.providers_skipped,
            });
        } else {
            const message = try std.fmt.allocPrint(arena, "Model catalogs: {d} provider(s) refreshed, {d} model identity/identities discovered, {d} skipped.", .{
                summary.providers_refreshed,
                summary.models_discovered,
                summary.providers_skipped,
            });
            try tui.render.printLine(io, message);
        }
        return;
    }

    if (includes_extensions) {
        const query = switch (options.target) {
            .extensions => |source| source,
            else => null,
        };
        const result = try updateConfiguredPackagesForCommand(gpa, io, agent_dir, cwd, query, project_trusted, runtime_options);
        if (options.json) {
            try packageJsonLine(io, .{
                .target = "extensions",
                .matched = result.matched,
                .updated = result.updated,
                .skippedLocal = result.skipped_local,
                .skippedPinned = result.skipped_pinned,
                .offline = offline,
            });
        } else {
            const message = try std.fmt.allocPrint(arena, "Packages: {d} matched, {d} updated, {d} local, {d} pinned{s}", .{
                result.matched,
                result.updated,
                result.skipped_local,
                result.skipped_pinned,
                if (offline) " (offline)" else "",
            });
            try tui.render.printLine(io, message);
        }
    }

    if (!includes_self) return;
    if (offline) return error.UpdateNetworkDisabled;
    var release = (try coding.update.getLatestRelease(gpa, io, config.upstream_version, .{
        .timeout_ms = runtime_settings.retry_provider_timeout_ms orelse coding.update.explicit_version_timeout_ms,
        .retry = true,
        .environ = environ,
        .setting_proxy = runtime_settings.http_proxy,
    })) orelse return error.LatestVersionUnavailable;
    defer release.deinit(gpa);
    const package_name = release.package_name orelse config.upstream_package_name;
    const available = options.force or !std.mem.eql(u8, package_name, config.upstream_package_name) or coding.update.isNewerPackageVersion(release.version, config.upstream_version);

    const executable_path_z = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(executable_path_z);
    const executable_path: []const u8 = executable_path_z;
    const method = coding.update.detectInstallMethod(executable_path, runtime_settings.npm_command);
    const npm_prefix = if (method == .npm and runtime_settings.npm_command == null)
        try coding.update.inferNpmPrefix(gpa, executable_path)
    else
        null;
    defer if (npm_prefix) |value| gpa.free(value);
    const pnpm_global_bin_dir = if (method == .pnpm)
        try coding.update.inferPnpmGlobalBinDir(gpa, executable_path)
    else
        null;
    defer if (pnpm_global_bin_dir) |value| gpa.free(value);
    const install_spec = try std.fmt.allocPrint(arena, "{s}@{s}", .{ package_name, release.version });
    var command_opt = try coding.update.buildSelfUpdateCommand(gpa, .{
        .method = method,
        .configured_command = if (method == .npm) runtime_settings.npm_command else null,
        .npm_prefix = npm_prefix,
        .pnpm_global_bin_dir = pnpm_global_bin_dir,
        .target = .{
            .installed_package_name = config.upstream_package_name,
            .package_name = package_name,
            .install_spec = install_spec,
        },
    });
    defer if (command_opt) |*command| command.deinit();
    const display: ?[]const u8 = if (command_opt) |*command| try command.display(arena) else null;
    const managed_install = coding.update.isSafeManagedInstallPath(method, executable_path);
    const writable_install = managed_install and coding.update.isSelfUpdatePathWritable(io, executable_path);
    const platform_supported = build_options.os.tag != .windows or method == .npm or method == .pnpm;
    const can_self_update = command_opt != null and managed_install and writable_install and platform_supported;

    if (options.json) {
        try packageJsonLine(io, .{
            .target = "self",
            .currentVersion = config.upstream_version,
            .latestVersion = release.version,
            .packageName = package_name,
            .installSpec = install_spec,
            .updateAvailable = available,
            .forced = options.force,
            .installMethod = @tagName(method),
            .managedInstall = managed_install,
            .writableInstall = writable_install,
            .platformSupported = platform_supported,
            .canSelfUpdate = can_self_update,
            .command = display,
            .note = release.note,
        });
    } else if (options.check) {
        const status = if (!available)
            "up to date"
        else if (can_self_update)
            "self-update available"
        else
            "manual update required";
        const summary = try std.fmt.allocPrint(arena, "pi v{s} -> v{s}: {s} ({s})", .{ config.upstream_version, release.version, status, @tagName(method) });
        try tui.render.printLine(io, summary);
        if (display) |value| {
            const plan = try std.fmt.allocPrint(arena, "Command: {s}", .{value});
            try tui.render.printLine(io, plan);
        }
        if (release.note) |note| {
            try tui.render.printLine(io, "Update note:");
            try tui.render.printLine(io, note);
        }
    }
    if (options.check) return;

    if (!available) {
        if (!options.json) {
            const message = try std.fmt.allocPrint(arena, "pi is already up to date (v{s}).", .{config.upstream_version});
            try tui.render.printLine(io, message);
        }
        return;
    }
    if (!can_self_update) {
        if (options.json) {
            try packageJsonLine(io, .{
                .target = "self",
                .success = false,
                .@"error" = "self_update_unavailable",
                .installMethod = @tagName(method),
                .command = display,
                .executablePath = executable_path,
            });
        } else {
            try tui.render.printLine(io, "error: this Pi installation cannot be self-updated safely.");
            if (!platform_supported) {
                try tui.render.printLine(io, "Windows self-update is supported only for npm and pnpm installations.");
            } else if (method == .unknown or command_opt == null) {
                const instruction = try std.fmt.allocPrint(arena, "Update {s} using the package manager, wrapper, or source checkout that installed {s}.", .{ install_spec, executable_path });
                try tui.render.printLine(io, instruction);
            } else if (!managed_install) {
                const instruction = try std.fmt.allocPrint(arena, "This executable is not inside a recognized global {s} installation. Update it with the package manager, wrapper, or source checkout that provides it.", .{@tagName(method)});
                try tui.render.printLine(io, instruction);
            } else if (!writable_install) {
                const instruction = try std.fmt.allocPrint(arena, "The global {s} installation is not writable. Run this command with the appropriate permissions: {s}", .{ @tagName(method), display.? });
                try tui.render.printLine(io, instruction);
            }
            const location = try std.fmt.allocPrint(arena, "Location of pi executable: {s}", .{executable_path});
            try tui.render.printLine(io, location);
        }
        return error.SelfUpdateMethodUnavailable;
    }

    const command = &(command_opt.?);
    if (!options.json) {
        if (release.note) |note| {
            try tui.render.printLine(io, "Update note:");
            try tui.render.printLine(io, note);
        }
        const message = try std.fmt.allocPrint(arena, "Updating pi with {s}...", .{display.?});
        try tui.render.printLine(io, message);
    }
    coding.update.executeSelfUpdate(gpa, io, command) catch |err| {
        if (options.json) {
            try packageJsonLine(io, .{
                .target = "self",
                .success = false,
                .@"error" = @errorName(err),
                .command = display,
            });
        } else {
            const message = try std.fmt.allocPrint(arena, "error: self-update failed: {s}", .{@errorName(err)});
            try tui.render.printLine(io, message);
            if (method == .pnpm) {
                try tui.render.printLine(io, "If pnpm reports missing package versions, run `pnpm store prune` and retry `pi update --self`.");
            }
            const fallback = try std.fmt.allocPrint(arena, "If this keeps failing, run this command yourself: {s}", .{display.?});
            try tui.render.printLine(io, fallback);
        }
        return err;
    };
    if (options.json) {
        try packageJsonLine(io, .{
            .target = "self",
            .success = true,
            .previousVersion = config.upstream_version,
            .version = release.version,
            .packageName = package_name,
        });
    } else {
        const message = try std.fmt.allocPrint(arena, "Updated pi from {s} to {s}.", .{ config.upstream_version, release.version });
        try tui.render.printLine(io, message);
    }
}

fn runPackageCommand(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    arena: std.mem.Allocator,
    cmd: []const u8,
    cmd_args: []const []const u8,
) !void {
    if (std.mem.eql(u8, cmd, "update")) return runUpdateCommand(gpa, io, environ, arena, cmd_args);
    const agent_dir = config.agentDir(arena, environ) catch {
        try tui.render.printLine(io, "error: cannot resolve agent dir (set HOME/USERPROFILE or PI_AGENT_DIR)");
        std.process.exit(2);
    };
    config.ensureDir(io, agent_dir) catch {};
    const cwd = try std.process.currentPathAlloc(io, arena);

    var json = false;
    var explicit_offline = false;
    var local = false;
    var config_set = false;
    var repair_check = false;
    var trust_override: ?bool = null;
    var positional: std.ArrayList([]const u8) = .empty;
    defer positional.deinit(arena);
    for (cmd_args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.eql(u8, arg, "--offline")) {
            explicit_offline = true;
        } else if (std.mem.eql(u8, arg, "--local") or std.mem.eql(u8, arg, "-l")) {
            local = true;
        } else if (std.mem.eql(u8, arg, "--set")) {
            config_set = true;
        } else if (std.mem.eql(u8, arg, "--check")) {
            repair_check = true;
        } else if (std.mem.eql(u8, arg, "--approve") or std.mem.eql(u8, arg, "-a")) {
            trust_override = true;
        } else if (std.mem.eql(u8, arg, "--no-approve") or std.mem.eql(u8, arg, "-na")) {
            trust_override = false;
        } else {
            try positional.append(arena, arg);
        }
    }
    const offline = packageOffline(environ, explicit_offline);
    var startup_settings = try coding.settings.loadMergeTrusted(gpa, io, agent_dir, cwd, false);
    defer startup_settings.deinit(gpa);
    const project_trusted = try resolveStartupProjectTrust(
        gpa,
        io,
        environ,
        agent_dir,
        cwd,
        trust_override,
        startup_settings.default_project_trust,
        false,
    );
    if (local and !project_trusted) {
        try tui.render.printLine(io, "error: project is not trusted; use --approve to modify local package configuration");
        std.process.exit(2);
    }
    var runtime_settings = try coding.settings.loadMergeTrusted(gpa, io, agent_dir, cwd, project_trusted);
    defer runtime_settings.deinit(gpa);
    const runtime_options: coding.packages.RuntimeOptions = .{
        .offline = offline,
        .npm_command = runtime_settings.npm_command,
    };
    const scope: coding.packages.Scope = if (local) .project else .user;

    if (std.mem.eql(u8, cmd, "config")) {
        if (repair_check or explicit_offline) {
            try tui.render.printLine(io, "usage: pi config [-l|--local] [--approve|--no-approve] [--json] [--set SELECTOR TYPE PATH STATE]");
            std.process.exit(2);
        }
        if (config_set) {
            if (positional.items.len != 4) {
                try tui.render.printLine(io, "usage: pi config [-l|--local] [--json] --set SELECTOR TYPE PATH <load|unload|inherit>");
                std.process.exit(2);
            }
            const resource_type = coding.package_config.parseResourceType(positional.items[1]) orelse {
                try tui.render.printLine(io, "error: resource TYPE must be extensions, skills, prompts, or themes");
                std.process.exit(2);
            };
            const state = coding.package_config.parseOverrideState(positional.items[3]) orelse {
                try tui.render.printLine(io, "error: STATE must be load, unload, or inherit");
                std.process.exit(2);
            };
            try coding.package_config.setResource(
                gpa,
                io,
                agent_dir,
                cwd,
                scope,
                project_trusted,
                positional.items[0],
                resource_type,
                positional.items[2],
                state,
            );
        } else if (positional.items.len != 0) {
            try tui.render.printLine(io, "usage: pi config [-l|--local] [--approve|--no-approve] [--json] [--set SELECTOR TYPE PATH STATE]");
            std.process.exit(2);
        }

        if (!json and !config_set and tui.terminal.supportsFullscreen(io)) {
            try coding.package_config_tui.run(gpa, io, environ, agent_dir, cwd, scope, project_trusted);
            return;
        }
        var inventory = try coding.package_config.discover(gpa, io, agent_dir, cwd, scope, project_trusted);
        defer inventory.deinit();
        if (json) {
            try writePackageConfigInventoryJson(io, gpa, &inventory);
        } else {
            try printPackageConfigInventory(io, arena, &inventory);
        }
    } else if (std.mem.eql(u8, cmd, "repair")) {
        if (positional.items.len != 0) {
            try tui.render.printLine(io, "usage: pi repair [-l|--local] [--approve|--no-approve] [--check] [--json]");
            std.process.exit(2);
        }
        if (repair_check) {
            var health = try coding.packages.inspectScopeHealth(gpa, io, agent_dir, cwd, scope, project_trusted);
            defer health.deinit();
            if (json) {
                try packageJsonLine(io, .{
                    .scope = @tagName(scope),
                    .operationActive = health.operation.active,
                    .operationMetadataPresent = health.operation.metadata_present,
                    .staleOperationMetadata = health.operation.stale_metadata,
                    .operationPid = health.operation.pid,
                    .operation = health.operation.operation,
                    .operationStartedMs = health.operation.started_ms,
                    .operationRegistryDir = health.operation.registry_dir,
                    .repairMarkers = health.repair_markers,
                    .legacyPackagesPending = health.legacy_packages_pending,
                    .nativeRegistryPresent = health.native_registry_present,
                });
            } else {
                const operation_label = if (health.operation.active)
                    try std.fmt.allocPrint(arena, "active {s} by pid {d}", .{ if (health.operation.operation.len > 0) health.operation.operation else "package operation", health.operation.pid })
                else if (health.operation.stale_metadata)
                    try std.fmt.allocPrint(arena, "stale {s} metadata from pid {d}", .{ if (health.operation.operation.len > 0) health.operation.operation else "package operation", health.operation.pid })
                else
                    "idle";
                const msg = try std.fmt.allocPrint(arena, "Package health ({s}): {s}; {d} repair marker(s); legacy migration {s}; native registry {s}", .{
                    @tagName(scope),
                    operation_label,
                    health.repair_markers,
                    if (health.legacy_packages_pending) "pending" else "not pending",
                    if (health.native_registry_present) "present" else "absent",
                });
                try tui.render.printLine(io, msg);
            }
            return;
        }
        const result = try coding.packages.repairScope(gpa, io, agent_dir, cwd, scope, project_trusted);
        if (json) {
            try packageJsonLine(io, .{
                .scope = @tagName(scope),
                .markersFound = result.markers_found,
                .committedPreparedUpdates = result.committed_prepared_updates,
                .restoredBackups = result.restored_backups,
                .cleanedArtifacts = result.cleaned_artifacts,
                .removedMarkers = result.removed_markers,
                .migratedLegacyPackages = result.migrated_legacy_packages,
                .cleanedLegacySettings = result.cleaned_legacy_settings,
            });
        } else {
            const msg = try std.fmt.allocPrint(arena, "Package repair ({s}): {d} marker(s), {d} prepared commit(s), {d} backup restore(s), {d} artifact(s) cleaned, {d} legacy package(s) migrated{s}", .{
                @tagName(scope),
                result.markers_found,
                result.committed_prepared_updates,
                result.restored_backups,
                result.cleaned_artifacts,
                result.migrated_legacy_packages,
                if (result.cleaned_legacy_settings) ", legacy settings cleaned" else "",
            });
            try tui.render.printLine(io, msg);
        }
    } else if (std.mem.eql(u8, cmd, "install")) {
        if (positional.items.len != 1) {
            try tui.render.printLine(io, "usage: pi install <path:PATH|npm:SPEC|GIT-URL> [-l|--local] [--offline] [--json]");
            std.process.exit(2);
        }
        var installed = try coding.packages.installScopedWithOptions(gpa, io, agent_dir, cwd, positional.items[0], scope, project_trusted, runtime_options);
        defer installed.deinit(gpa);
        if (json) {
            try packageJsonLine(io, .{ .installed = true, .scope = @tagName(installed.scope), .name = installed.name, .path = installed.path, .source = installed.source });
        } else {
            const msg = try std.fmt.allocPrint(arena, "Installed {s} package {s} -> {s}", .{ @tagName(installed.scope), installed.name, installed.path });
            try tui.render.printLine(io, msg);
        }
    } else if (std.mem.eql(u8, cmd, "list")) {
        if (positional.items.len != 0) {
            try tui.render.printLine(io, "usage: pi list [--json]");
            std.process.exit(2);
        }
        const installed = try coding.packages.listConfigured(gpa, io, agent_dir, cwd, project_trusted);
        defer {
            for (installed) |*package| package.deinit(gpa);
            gpa.free(installed);
        }
        if (json) {
            var aw: std.Io.Writer.Allocating = .init(gpa);
            defer aw.deinit();
            try aw.writer.writeByte('[');
            for (installed, 0..) |package, index| {
                if (index > 0) try aw.writer.writeByte(',');
                try aw.writer.writeAll("{\"name\":");
                try std.json.Stringify.value(package.name, .{}, &aw.writer);
                try aw.writer.writeAll(",\"path\":");
                try std.json.Stringify.value(package.path, .{}, &aw.writer);
                try aw.writer.writeAll(",\"source\":");
                if (package.source) |source| try std.json.Stringify.value(source, .{}, &aw.writer) else try aw.writer.writeAll("null");
                try aw.writer.writeAll(",\"scope\":");
                try std.json.Stringify.value(@tagName(package.scope), .{}, &aw.writer);
                try aw.writer.print(",\"autoload\":{}", .{package.autoload});
                try aw.writer.writeByte('}');
            }
            try aw.writer.writeByte(']');
            try tui.render.printLine(io, aw.written());
        } else if (installed.len == 0) {
            try tui.render.printLine(io, "(no packages)");
        } else {
            for (installed) |package| {
                const source = package.source orelse package.path;
                const msg = try std.fmt.allocPrint(arena, "{s}\t{s}\t{s}\t{s}", .{ @tagName(package.scope), package.name, source, package.path });
                try tui.render.printLine(io, msg);
            }
        }
    } else if (std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "uninstall")) {
        if (positional.items.len != 1) {
            try tui.render.printLine(io, "usage: pi remove <name|source> [-l|--local] [--json]");
            std.process.exit(2);
        }
        const removed = try coding.packages.removeScopedWithOptions(gpa, io, agent_dir, cwd, positional.items[0], scope, project_trusted, runtime_options);
        if (json) {
            try packageJsonLine(io, .{ .removed = removed, .scope = @tagName(scope), .query = positional.items[0] });
        } else if (removed) {
            try tui.render.printLine(io, "Removed.");
        } else {
            try tui.render.printLine(io, "Package not found.");
        }
    }
}

fn runProtocolServer(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    arena: std.mem.Allocator,
    options: ServeOptions,
    server_agent_dir: ?[]const u8,
    server_models_file: *const coding.models_file.ModelsFile,
    server_model_catalog: []const ai.providers.ModelInfo,
    persistence: ?pi_zig.server.session_store.PersistenceBackend,
    persistence_label: []const u8,
) !void {
    var srv = pi_zig.server.Server{
        .gpa = gpa,
        .io = io,
        .config = .{
            .host = options.host,
            .port = options.port,
            .auth_token = options.token,
            .session_dir = options.session_dir,
            .persistence = persistence,
            .max_frame_length = options.max_frame_length,
            .handshake_timeout_ms = options.handshake_timeout_ms,
            .unix_socket = options.unix_socket,
            .environ = environ,
            .agent_dir = server_agent_dir,
            .trust_project = options.trust_project,
            .model_catalog = server_model_catalog,
            .models_file = server_models_file,
            .mock_script = options.mock_script,
        },
    };
    defer srv.deinit();
    const endpoint = if (options.unix_socket) |path|
        try std.fmt.allocPrint(arena, "unix:{s}", .{path})
    else
        try std.fmt.allocPrint(arena, "http://{s}:{d}", .{ options.host, options.port });
    const info = try std.fmt.allocPrint(arena, "pi serve listening on {s}; persistence={s}; GET /health, POST /rpc", .{ endpoint, persistence_label });
    try tui.render.printLine(io, info);
    try srv.serveLoop();
}

/// Native package/service commands.  Every command below is backed by a real
/// implementation; synthetic "surface"/shard commands were intentionally removed.
fn runSurfaceCommand(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    arena: std.mem.Allocator,
    cmd: []const u8,
    cmd_args: []const []const u8,
) !void {
    if (std.mem.eql(u8, cmd, "auth")) {
        const auth_agent_dir = config.agentDir(arena, environ) catch null;
        var result = try coding.auth_commands.execute(gpa, io, environ, auth_agent_dir, cmd_args);
        defer result.deinit(gpa);
        try tui.render.printLine(io, result.output);
        if (result.exit_code != 0) std.process.exit(result.exit_code);
        return;
    }

    if (std.mem.eql(u8, cmd, "sessions")) {
        var buffer: [4096]u8 = undefined;
        var stdout: Io.File.Writer = .init(.stdout(), io, &buffer);
        if (hasSqliteSessionFlag(cmd_args)) {
            if (!pi_features.sqlite_enabled) {
                try stdout.interface.writeAll("this self-contained pi build has no SQLite linkage; use pi-sqlite-live sessions --sqlite PATH ...\n");
                try stdout.interface.flush();
                std.process.exit(2);
            }
            if (pi_features.sqlite_enabled) {
                const sqlite_args = try normalizeSqliteSessionArgs(arena, cmd_args);
                const result = pi_zig.storage.sqlite_cli.execute(gpa, io, sqlite_args, &stdout.interface) catch |err| {
                    try stdout.interface.print("SQLite sessions failed: {s}\n", .{@errorName(err)});
                    try stdout.interface.flush();
                    std.process.exit(1);
                };
                try stdout.interface.flush();
                if (result.exit_code != 0) std.process.exit(result.exit_code);
                return;
            }
        }

        const cwd = try std.process.currentPathAlloc(io, arena);
        const session_dir = try config.sessionDirForCwd(arena, environ, cwd, null);
        const result = coding.session_commands.execute(gpa, io, session_dir, cmd_args, &stdout.interface) catch |err| {
            try stdout.interface.print("sessions failed: {s}\n", .{@errorName(err)});
            try stdout.interface.flush();
            std.process.exit(1);
        };
        try stdout.interface.flush();
        if (result.exit_code != 0) std.process.exit(result.exit_code);
        return;
    }

    if (std.mem.eql(u8, cmd, "remote")) {
        var buffer: [4096]u8 = undefined;
        var stdout: Io.File.Writer = .init(.stdout(), io, &buffer);
        const result = coding.remote_cli.execute(gpa, io, cmd_args, &stdout.interface) catch |err| {
            try stdout.interface.print("remote failed: {s}\n", .{@errorName(err)});
            try stdout.interface.flush();
            std.process.exit(1);
        };
        try stdout.interface.flush();
        if (result.exit_code != 0) std.process.exit(result.exit_code);
        return;
    }

    if (std.mem.eql(u8, cmd, "serve")) {
        const options = parseServeOptions(cmd_args) catch |err| {
            const message = try std.fmt.allocPrint(arena, "serve option error: {s}\n{s}", .{ @errorName(err), serve_usage });
            try tui.render.printLine(io, message);
            std.process.exit(2);
        };
        if (options.show_help) {
            try tui.render.printLine(io, serve_usage);
            return;
        }
        if (options.sqlite_path != null and !pi_features.sqlite_enabled) {
            try tui.render.printLine(io, "this self-contained pi build has no SQLite linkage; use the pi-sqlite-live executable");
            std.process.exit(2);
        }

        const server_agent_dir = config.agentDir(arena, environ) catch null;
        var server_models_file: coding.models_file.ModelsFile = if (server_agent_dir) |ad|
            try coding.models_file.load(gpa, io, ad)
        else
            .{ .gpa = gpa };
        defer server_models_file.deinit();
        var server_radius_catalogs: coding.radius_cached_catalogs.Set = if (server_agent_dir) |ad|
            try coding.radius_cached_catalogs.load(gpa, io, ad, &server_models_file)
        else
            .{};
        defer server_radius_catalogs.deinit(gpa);
        const server_unfiltered_catalog = try coding.effective_catalog.buildWithExtras(gpa, &server_models_file, server_radius_catalogs.infos);
        defer gpa.free(server_unfiltered_catalog);
        var server_copilot_catalog = try coding.copilot_catalog_filter.load(gpa, io, server_agent_dir, server_unfiltered_catalog);
        defer server_copilot_catalog.deinit();
        const server_model_catalog = server_copilot_catalog.infos;

        if (pi_features.sqlite_enabled) {
            if (options.sqlite_path) |db_path| {
                var adapter = try sqlite_persistence.Adapter.initWithLeaseTtl(gpa, io, db_path, options.sqlite_lease_ttl_ms);
                defer adapter.deinit();
                if (options.sqlite_import_dir) |source_dir| {
                    const report = try adapter.importJsonDirectory(source_dir);
                    const line = try std.fmt.allocPrint(arena, "SQLite import: loaded={d} imported={d} unchanged={d}", .{ report.loaded, report.imported, report.unchanged });
                    try tui.render.printLine(io, line);
                }
                try runProtocolServer(gpa, io, environ, arena, options, server_agent_dir, &server_models_file, server_model_catalog, adapter.backend(), "sqlite");
                return;
            }
        }

        try runProtocolServer(
            gpa,
            io,
            environ,
            arena,
            options,
            server_agent_dir,
            &server_models_file,
            server_model_catalog,
            null,
            if (options.session_dir != null) "jsonl" else "memory",
        );
        return;
    }

    if (std.mem.eql(u8, cmd, "mcp")) {
        if (cmd_args.len == 0) {
            try tui.render.printLine(io, "usage: pi mcp <server-command> [args...]");
            std.process.exit(2);
        }
        var client = pi_zig.mcp.McpClient{ .gpa = gpa, .io = io };
        defer client.deinit();
        client.connect(cmd_args) catch |err| {
            const m = try std.fmt.allocPrint(arena, "mcp connect failed: {s}", .{@errorName(err)});
            try tui.render.printLine(io, m);
            std.process.exit(2);
        };
        client.listTools() catch |err| {
            const m = try std.fmt.allocPrint(arena, "mcp tools/list failed: {s}", .{@errorName(err)});
            try tui.render.printLine(io, m);
            std.process.exit(2);
        };
        if (client.tools.items.len == 0) {
            try tui.render.printLine(io, "(no MCP tools reported)");
        } else {
            for (client.tools.items) |t| {
                const line = try std.fmt.allocPrint(arena, "{s}\t{s}", .{ t.name, t.description });
                try tui.render.printLine(io, line);
            }
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "eval")) {
        var script_path: ?[]const u8 = null;
        var expect: []const u8 = "ok";
        var prompt_parts: std.ArrayList([]const u8) = .empty;
        defer prompt_parts.deinit(arena);
        var i: usize = 0;
        while (i < cmd_args.len) : (i += 1) {
            if (std.mem.eql(u8, cmd_args[i], "--script") and i + 1 < cmd_args.len) {
                i += 1;
                script_path = cmd_args[i];
            } else if (std.mem.eql(u8, cmd_args[i], "--expect") and i + 1 < cmd_args.len) {
                i += 1;
                expect = cmd_args[i];
            } else try prompt_parts.append(arena, cmd_args[i]);
        }
        const sp = script_path orelse {
            try tui.render.printLine(io, "usage: pi eval --script mock.json --expect TEXT [prompt]");
            std.process.exit(2);
        };
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, sp, gpa, .limited(4 * 1024 * 1024));
        defer gpa.free(raw);
        const prompt = if (prompt_parts.items.len > 0) try joinMessages(arena, prompt_parts.items) else "eval";
        const cwd = try std.process.currentPathAlloc(io, arena);
        var result = try pi_zig.evals.runCase(gpa, io, cwd, .{ .name = "cli", .prompt = prompt, .expect_contains = expect }, raw);
        defer result.deinit(gpa);
        const line = try std.fmt.allocPrint(arena, "eval {s}: {s}", .{ if (result.passed) "PASS" else "FAIL", result.detail });
        try tui.render.printLine(io, line);
        if (!result.passed) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, cmd, "oauth")) {
        if (cmd_args.len < 2 or !std.mem.eql(u8, cmd_args[0], "parse-device")) {
            try tui.render.printLine(io, "usage: pi oauth parse-device <json-file>");
            std.process.exit(2);
        }
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, cmd_args[1], gpa, .limited(256 * 1024));
        defer gpa.free(raw);
        var dc = try pi_zig.auth.parseDeviceCodeResponse(gpa, raw);
        defer dc.deinit(gpa);
        const line = try std.fmt.allocPrint(arena, "user_code={s}\nverification_uri={s}\nexpires_in={d}", .{ dc.user_code, dc.verification_uri, dc.expires_in });
        try tui.render.printLine(io, line);
        return;
    }

    if (std.mem.eql(u8, cmd, "theme")) {
        if (cmd_args.len == 0) {
            try tui.render.printLine(io, "usage: pi theme <theme.json>");
            std.process.exit(2);
        }
        var th = try pi_zig.themes.loadFile(gpa, io, cmd_args[0]);
        defer th.deinit(gpa);
        const sample = try pi_zig.themes.wrap(th.accent_sgr, th.name, arena);
        try tui.render.printLine(io, sample);
        return;
    }

    if (std.mem.eql(u8, cmd, "index")) {
        const cwd = try std.process.currentPathAlloc(io, arena);
        const session_dir = if (cmd_args.len > 0) cmd_args[0] else try config.sessionDirForCwd(arena, environ, cwd, null);
        const index_path = try std.fs.path.join(arena, &.{ session_dir, "index.jsonl" });
        var idx = try pi_zig.storage.SessionIndex.open(gpa, io, index_path);
        defer idx.deinit();
        const sessions = try agent.session.listSessions(gpa, io, session_dir);
        defer {
            for (sessions) |*entry| {
                var mut = entry.*;
                mut.deinit(gpa);
            }
            gpa.free(sessions);
        }
        for (sessions) |entry| try idx.upsert(entry.id, entry.path, entry.id, 0, "");
        try idx.save();
        const msg = try std.fmt.allocPrint(arena, "indexed {d} session(s) -> {s}", .{ sessions.len, index_path });
        try tui.render.printLine(io, msg);
        return;
    }

    if (std.mem.eql(u8, cmd, "skills-list")) {
        const cwd = try std.process.currentPathAlloc(io, arena);
        const agent_dir = config.agentDir(arena, environ) catch null;
        const list = try coding.skills.discoverTrusted(gpa, io, cwd, agent_dir, &.{}, true);
        defer {
            for (list) |*skill| skill.deinit(gpa);
            gpa.free(list);
        }
        if (list.len == 0) {
            try tui.render.printLine(io, "(no skills discovered)");
        } else {
            for (list) |skill| {
                const line = try std.fmt.allocPrint(arena, "{s}\t{s}", .{ skill.name, skill.path });
                try tui.render.printLine(io, line);
            }
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "routes")) {
        try tui.render.printLine(io, "GET /health");
        try tui.render.printLine(io, "POST /rpc");
        return;
    }

    if (std.mem.eql(u8, cmd, "protocol-check")) {
        if (cmd_args.len == 0) {
            try tui.render.printLine(io, "usage: pi protocol-check '<json-message>'");
            std.process.exit(2);
        }
        var message = pi_zig.protocol.json.parseClientMessage(gpa, cmd_args[0]) catch |err| {
            const line = try std.fmt.allocPrint(arena, "invalid protocol message: {s}", .{@errorName(err)});
            try tui.render.printLine(io, line);
            std.process.exit(1);
        };
        defer pi_zig.protocol.json.deinitClientMessage(gpa, &message);
        switch (message) {
            .hello => |h| {
                const line = try std.fmt.allocPrint(arena, "hello version={d} supported={s}", .{ h.version, if (pi_zig.protocol.messages.isSupportedProtocolVersion(h.version)) "yes" else "no" });
                try tui.render.printLine(io, line);
            },
            .request => |r| {
                const line = try std.fmt.allocPrint(arena, "request id={s} command={s}", .{ r.id, pi_zig.protocol.messages.commandName(r.request) });
                try tui.render.printLine(io, line);
            },
        }
        return;
    }

    const unknown = try std.fmt.allocPrint(arena, "unknown command: {s}", .{cmd});
    try tui.render.printLine(io, unknown);
    std.process.exit(2);
}

fn listModels(gpa: std.mem.Allocator, io: Io, query: ?[]const u8, models: []const ai.providers.ModelInfo) !void {
    const RankedModel = struct { model: ai.providers.ModelInfo, score: i32, order: usize };
    var ranked: std.ArrayList(RankedModel) = .empty;
    defer ranked.deinit(gpa);

    for (models, 0..) |model_info, order| {
        const fields = [_][]const u8{ model_info.providerName(), model_info.id, model_info.display };
        const match_score = if (query) |needle| tui.fuzzy.bestScore(&fields, needle) orelse continue else 0;
        try ranked.append(gpa, .{ .model = model_info, .score = match_score, .order = order });
    }
    std.mem.sort(RankedModel, ranked.items, {}, struct {
        fn lessThan(_: void, lhs: RankedModel, rhs: RankedModel) bool {
            if (lhs.score != rhs.score) return lhs.score > rhs.score;
            return lhs.order < rhs.order;
        }
    }.lessThan);

    for (ranked.items) |item| {
        var buf: [512]u8 = undefined;
        const model_info = item.model;
        const line = try std.fmt.bufPrint(&buf, "{s}/{s}\t{s}", .{ model_info.providerName(), model_info.id, model_info.display });
        try tui.render.printLine(io, line);
    }
    var buf: [96]u8 = undefined;
    const summary = try std.fmt.bufPrint(&buf, "# catalog_total={d} listed={d}", .{ models.len, ranked.items.len });
    try tui.render.printLine(io, summary);
}

fn resolveSessionPath(arena: std.mem.Allocator, io: Io, session_dir: []const u8, path_or_id: []const u8) ![]const u8 {
    // Absolute or exists as path
    if (std.mem.indexOfScalar(u8, path_or_id, '/') != null or std.mem.indexOfScalar(u8, path_or_id, '\\') != null or std.mem.endsWith(u8, path_or_id, ".jsonl")) {
        return path_or_id;
    }
    // try as file in session dir
    const candidate = try agent.session.newSessionPath(arena, session_dir, path_or_id);
    std.Io.Dir.cwd().access(io, candidate, .{}) catch {
        // partial id match
        const sessions = try agent.session.listSessions(arena, io, session_dir);
        for (sessions) |s| {
            if (std.mem.indexOf(u8, s.id, path_or_id) != null or std.mem.startsWith(u8, s.id, path_or_id)) {
                return s.path;
            }
        }
        return candidate;
    };
    return candidate;
}

fn resolveStartupProjectTrust(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: ?[]const u8,
    cwd: []const u8,
    override: ?bool,
    default_policy: coding.settings.DefaultProjectTrust,
    interactive_mode: bool,
) !bool {
    const home = config.homeDir(environ) orelse cwd;
    const has_resources = try coding.trust.hasTrustRequiringProjectResources(gpa, io, cwd, home);

    var store_opt: ?coding.trust.Store = if (agent_dir) |ad| try coding.trust.Store.init(gpa, io, ad) else null;
    defer if (store_opt) |*store| store.deinit();
    const stored = if (store_opt) |*store| try store.get(cwd) else null;
    const has_ui = interactive_mode and tui.line_editor.available(io);
    const policy = coding.trust.resolvePolicy(.{
        .override = override,
        .has_resources = has_resources,
        .stored = stored,
        .default_policy = default_policy,
        .has_ui = has_ui,
    });
    switch (policy) {
        .resolved => |value| return value,
        .ask_ui => {},
    }

    var options = try coding.trust.getOptions(gpa, cwd, true);
    defer {
        for (options) |*option| option.deinit(gpa);
        gpa.free(options);
    }
    try tui.render.printLine(io, "Trust project folder?");
    try tui.render.printLine(io, cwd);
    try tui.render.printLine(io, "This allows project .pi settings/resources, packages, and extensions.");
    for (options, 0..) |option, i| {
        const line = try std.fmt.allocPrint(gpa, "  {d}) {s}", .{ i + 1, option.label });
        defer gpa.free(line);
        try tui.render.printLine(io, line);
    }
    try tui.render.printLine(io, "Choose a number:");
    var buf: [256]u8 = undefined;
    var reader: Io.File.Reader = .init(.stdin(), io, &buf);
    const line = readLine(&reader, gpa) catch return false;
    defer gpa.free(line);
    const selected = std.fmt.parseInt(usize, std.mem.trim(u8, line, " \t\r\n"), 10) catch return false;
    if (selected == 0 or selected > options.len) return false;
    const choice = &options[selected - 1];
    if (choice.updates.len > 0) {
        if (store_opt) |*store| try store.setMany(choice.updates);
    }
    return choice.trusted;
}

fn joinMessages(arena: std.mem.Allocator, msgs: []const []const u8) ![]const u8 {
    if (msgs.len == 0) return "";
    if (msgs.len == 1) return msgs[0];
    var out: std.ArrayList(u8) = .empty;
    for (msgs, 0..) |m, i| {
        if (i > 0) try out.append(arena, ' ');
        try out.appendSlice(arena, m);
    }
    return try out.toOwnedSlice(arena);
}

fn readPipedStdin(gpa: std.mem.Allocator, io: Io, max_bytes: usize) ![]u8 {
    var buffer: [8192]u8 = undefined;
    // stdin may be an anonymous Windows pipe. Starting in positional mode
    // probes file metadata first, which produces INVALID_INFO_CLASS before the
    // standard library falls back. Pipes are streams by definition, so select
    // that mode up front and keep one-shot output free of spurious diagnostics.
    var reader: Io.File.Reader = .initStreaming(.stdin(), io, &buffer);
    return reader.interface.allocRemaining(gpa, .limited(max_bytes));
}

fn readLine(reader: *Io.File.Reader, arena: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(arena);
    while (true) {
        const n = reader.interface.takeByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (list.items.len == 0) return error.EndOfStream;
                break;
            },
            else => return err,
        };
        if (n == '\n') break;
        if (n == '\r') continue;
        try list.append(arena, n);
    }
    return try list.toOwnedSlice(arena);
}

test "SQLite session command flags normalize without changing operands" {
    const allocator = std.testing.allocator;
    const args = try normalizeSqliteSessionArgs(allocator, &.{ "search", "--sqlite=/tmp/a.db", "hello", "world" });
    defer {
        allocator.free(args[1]);
        allocator.free(args);
    }
    try std.testing.expectEqualStrings("search", args[0]);
    try std.testing.expectEqualStrings("--db=/tmp/a.db", args[1]);
    try std.testing.expectEqualStrings("hello", args[2]);
    try std.testing.expect(hasSqliteSessionFlag(&.{ "list", "--sqlite", "x.db" }));
    try std.testing.expect(!hasSqliteSessionFlag(&.{ "list", "--json" }));
}

test "serve options parse SQLite production backend and equals forms" {
    const options = try parseServeOptions(&.{
        "--host=0.0.0.0",
        "--port",
        "43141",
        "--sqlite=/tmp/pi.db",
        "--sqlite-import-dir",
        "/tmp/json-sessions",
        "--sqlite-lease-ttl-ms=90000",
        "--max-frame-length",
        "1048576",
        "--approve",
    });
    try std.testing.expectEqualStrings("0.0.0.0", options.host);
    try std.testing.expectEqual(@as(u16, 43141), options.port);
    try std.testing.expectEqualStrings("/tmp/pi.db", options.sqlite_path.?);
    try std.testing.expectEqualStrings("/tmp/json-sessions", options.sqlite_import_dir.?);
    try std.testing.expectEqual(@as(i64, 90_000), options.sqlite_lease_ttl_ms);
    try std.testing.expectEqual(@as(usize, 1_048_576), options.max_frame_length);
    try std.testing.expect(options.trust_project);
}

test "serve options reject ambiguous persistence and unsafe numeric values" {
    try std.testing.expectError(ServeOptionError.ConflictingPersistence, parseServeOptions(&.{ "--session-dir", "json", "--sqlite", "sessions.db" }));
    try std.testing.expectError(ServeOptionError.ImportRequiresSqlite, parseServeOptions(&.{ "--sqlite-import-dir", "json" }));
    try std.testing.expectError(ServeOptionError.InvalidPort, parseServeOptions(&.{ "--port", "0" }));
    try std.testing.expectError(ServeOptionError.InvalidLeaseTtl, parseServeOptions(&.{ "--sqlite", "x.db", "--sqlite-lease-ttl-ms", "-1" }));
    try std.testing.expectError(ServeOptionError.MissingValue, parseServeOptions(&.{"--token"}));
    try std.testing.expectError(ServeOptionError.UnknownOption, parseServeOptions(&.{"--mystery"}));
}

test "startup extension action preview preserves delivery priority and stop state" {
    const gpa = std.testing.allocator;
    var batch = try extensions.actions.Batch.parse(
        gpa,
        "preview",
        "command",
        "{\"actionQueue\":[{\"type\":\"send_user_message\",\"content\":\"later\",\"options\":{\"deliverAs\":\"followUp\"}},{\"type\":\"send_message\",\"message\":{\"customType\":\"notice\",\"content\":\"now\",\"display\":true},\"options\":{\"triggerTurn\":true}},{\"type\":\"set_session_name\",\"name\":\"renamed\"},{\"type\":\"shutdown\"}]}\n",
    );
    defer batch.deinit(gpa);
    const presence = extensionActionPresence(batch);
    try std.testing.expect(presence.send_message);
    try std.testing.expect(presence.send_user_message);
    try std.testing.expect(presence.session_name);
    try std.testing.expect(presence.abort_or_shutdown);

    var preview = try previewExtensionCommandActions(gpa, batch);
    defer preview.deinit(gpa);
    try std.testing.expectEqualStrings("now", preview.prompt.?);
    try std.testing.expect(preview.stop);
}

test "RPC get_messages uses the compaction-aware AgentMessage projection" {
    const gpa = std.testing.allocator;
    var sess = try agent.session.Session.init(gpa, "rpc-compaction-messages", "/tmp");
    defer sess.deinit();
    const old_user = try sess.appendMessage(null, "user", "old-user-should-be-hidden", null, null);
    const old_assistant = try sess.appendMessage(old_user, "assistant", "old-assistant-should-be-hidden", null, null);
    const kept = try sess.appendMessage(old_assistant, "user", "kept-user-162", null, null);
    _ = try sess.appendCompaction("summary-162", kept, 777, "{}", false, .{});

    const raw = try formatSessionMessagesJson(gpa, &sess);
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"role\":\"compactionSummary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"summary\":\"summary-162\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"tokensBefore\":777") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "kept-user-162") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "old-user-should-be-hidden") == null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "old-assistant-should-be-hidden") == null);
}

test "reload action is a terminal barrier for startup preview and legacy mirrors" {
    const gpa = std.testing.allocator;
    var batch = try extensions.actions.Batch.parse(
        gpa,
        "reload-barrier",
        "command",
        "{\"actionQueue\":[{\"type\":\"send_user_message\",\"content\":\"before\"},{\"type\":\"reload\"},{\"type\":\"send_user_message\",\"content\":\"after\"},{\"type\":\"shutdown\"}]}",
    );
    defer batch.deinit(gpa);

    const presence = extensionActionPresence(batch);
    try std.testing.expect(presence.reload);
    try std.testing.expect(presence.send_user_message);
    try std.testing.expect(!presence.abort_or_shutdown);

    var preview = try previewExtensionCommandActions(gpa, batch);
    defer preview.deinit(gpa);
    try std.testing.expectEqualStrings("before", preview.prompt.?);
    try std.testing.expect(!preview.stop);
}

test "provider retry policy inherits HTTP timeout and preserves explicit zero" {
    var settings: coding.settings.Settings = .{};
    var policy = providerRetryPolicyFromSettings(&settings);
    try std.testing.expectEqual(@as(?u64, ai.openai_responses.DEFAULT_HTTP_IDLE_TIMEOUT_MS), policy.timeout_ms);
    try std.testing.expectEqual(@as(usize, 2), policy.max_retries);
    try std.testing.expectEqual(@as(u64, 60_000), policy.max_retry_delay_ms);

    settings.http_idle_timeout_ms = 0;
    policy = providerRetryPolicyFromSettings(&settings);
    try std.testing.expect(policy.timeout_ms == null);

    settings.retry_provider_timeout_ms = 0;
    policy = providerRetryPolicyFromSettings(&settings);
    try std.testing.expectEqual(@as(?u64, 0), policy.timeout_ms);
}

test "reload client settings publish and roll back provider retry policy" {
    const gpa = std.testing.allocator;
    var pool = coding.live_state.ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    const credentials = ReloadCredentialSet{ .gpa = gpa };
    const configured = coding.settings.Settings{
        .retry_provider_timeout_ms = 321,
        .retry_provider_max_retries = 4,
        .retry_provider_max_retry_delay_ms = 654,
    };
    try applyReloadClientSettings(&pool, &credentials, &configured);
    try std.testing.expectEqual(@as(?u64, 321), pool.provider_retry_policy.timeout_ms);
    try std.testing.expectEqual(@as(usize, 4), pool.provider_retry_policy.max_retries);
    try std.testing.expectEqual(@as(u64, 654), pool.provider_retry_policy.max_retry_delay_ms);

    try pool.installApiKeyCredential("openai", "rollback-live-key-177");
    var backup = try ClientReloadBackup.capture(gpa, &pool);
    defer backup.deinit();
    pool.setProviderRetryPolicy(.{ .timeout_ms = 1, .max_retries = 0, .max_retry_delay_ms = 2 });
    pool.clearLiveCredentialForReload();
    try backup.restore(&pool);
    try std.testing.expectEqual(@as(?u64, 321), pool.provider_retry_policy.timeout_ms);
    try std.testing.expectEqual(@as(usize, 4), pool.provider_retry_policy.max_retries);
    try std.testing.expectEqual(@as(u64, 654), pool.provider_retry_policy.max_retry_delay_ms);
    try pool.switchToIdentity("openai", .openai, "gpt-test");
    try std.testing.expectEqualStrings("rollback-live-key-177", pool.openai.?.api_key);
}

test "identity stable" {
    try std.testing.expect(std.mem.indexOf(u8, pi_zig.identity, "pi") != null);
}

test "settings delivery and tree filter mapping" {
    try std.testing.expectEqual(agent.loop.QueueMode.one_at_a_time, queueModeFromSettings(null));
    try std.testing.expectEqual(agent.loop.QueueMode.all, queueModeFromSettings(.all));
    try std.testing.expectEqual(coding.tree_tui.FilterMode.default, treeFilterFromSettings(null));
    try std.testing.expectEqual(coding.tree_tui.FilterMode.labeled_only, treeFilterFromSettings(.labeled_only));
}

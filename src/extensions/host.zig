//! Native extension host.
//!
//! Native extensions remain explicit out-of-process executables described by
//! `extension.json`. Upstream JavaScript and TypeScript extensions are also
//! supported through a persistent, isolated Node compatibility runtime owned
//! by this Zig host. A native entry receives:
//!   <entry> --pi-hook <hook-name> <payload-json> <flags-json>
//!   <entry> --pi-tool <tool-name> <arguments-json> <flags-json>
//!   <entry> --pi-command <command-name> <raw-arguments> <flags-json>
//! The final object contains only flags registered by that extension, including
//! manifest defaults and command-line overrides. Hook stdout may contain one
//! JSON result. Tool stdout must be a JSON object
//! with `content` and optional `isError`, `imageBase64`, and `imageMime`.
const std = @import("std");
const Io = std.Io;
const js_runtime = @import("js_runtime.zig");
const actions_mod = @import("actions.zig");
const file_permissions = @import("../file_permissions.zig");

pub const ToolCost = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    total: f64 = 0,
};

pub const ToolUsage = struct {
    input: u64 = 0,
    output: u64 = 0,
    cache_read: u64 = 0,
    cache_write: u64 = 0,
    cache_write_1h: ?u64 = null,
    reasoning: ?u64 = null,
    total_tokens: u64 = 0,
    cost: ToolCost = .{},
};

pub const ToolImage = struct {
    data_b64: []u8,
    mime_type: []u8,

    pub fn deinit(self: *ToolImage, gpa: std.mem.Allocator) void {
        gpa.free(self.data_b64);
        gpa.free(self.mime_type);
        self.* = undefined;
    }
};

fn deinitToolImages(gpa: std.mem.Allocator, images: []ToolImage) void {
    for (images) |*image| image.deinit(gpa);
    if (images.len > 0) gpa.free(images);
}

pub const ToolExecutionMode = enum { parallel, sequential };
const InvocationKind = enum { hook, tool, command, shortcut };

pub const ExtensionFlagKind = enum { boolean, string };

pub const ExtensionFlagValue = union(enum) {
    boolean: bool,
    string: []const u8,
};

pub const ExtensionFlag = struct {
    name: []const u8,
    description: []const u8,
    kind: ExtensionFlagKind,
    value: ?ExtensionFlagValue = null,

    pub fn deinit(self: *ExtensionFlag, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.description);
        if (self.value) |value| switch (value) {
            .boolean => {},
            .string => |text| gpa.free(text),
        };
        self.* = undefined;
    }

    pub fn setCliValue(self: *ExtensionFlag, gpa: std.mem.Allocator, raw: ?[]const u8) !void {
        switch (self.kind) {
            // Match the original extension runtime: the presence of a boolean
            // option sets it to true, even if the generic parser captured a
            // following token as a string value.
            .boolean => {
                if (self.value) |old| switch (old) {
                    .boolean => {},
                    .string => |text| gpa.free(text),
                };
                self.value = .{ .boolean = true };
            },
            .string => {
                const value = raw orelse return error.ExtensionFlagRequiresValue;
                const owned = try gpa.dupe(u8, value);
                if (self.value) |old| switch (old) {
                    .boolean => {},
                    .string => |text| gpa.free(text),
                };
                self.value = .{ .string = owned };
            },
        }
    }
};

pub const ExtensionCommand = struct {
    name: []const u8,
    description: []const u8,
    argument_hint: ?[]const u8 = null,

    pub fn deinit(self: *ExtensionCommand, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.description);
        if (self.argument_hint) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const ExtensionShortcut = struct {
    key: []const u8,
    description: []const u8,

    pub fn deinit(self: *ExtensionShortcut, gpa: std.mem.Allocator) void {
        gpa.free(self.key);
        gpa.free(self.description);
        self.* = undefined;
    }
};

pub const ExtensionProviderRegistration = struct {
    name: []const u8,
    config_json: []const u8,

    pub fn deinit(self: *ExtensionProviderRegistration, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.config_json);
        self.* = undefined;
    }
};

pub const ExtensionTool = struct {
    name: []const u8,
    description: []const u8,
    parameters_json: []const u8,
    execution_mode: ToolExecutionMode = .parallel,
    has_render_call: bool = false,
    has_render_result: bool = false,
    has_prepare_arguments: bool = false,
    render_shell_self: bool = false,

    pub fn deinit(self: *ExtensionTool, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.description);
        gpa.free(self.parameters_json);
        self.* = undefined;
    }
};

pub const EntryAction = struct {
    custom_type: []u8,
    data_json: ?[]u8 = null,

    pub fn deinit(self: *EntryAction, gpa: std.mem.Allocator) void {
        gpa.free(self.custom_type);
        if (self.data_json) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const LabelAction = struct {
    entry_id: []u8,
    label: ?[]u8 = null,

    pub fn deinit(self: *LabelAction, gpa: std.mem.Allocator) void {
        gpa.free(self.entry_id);
        if (self.label) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const ModelAction = struct {
    provider: ?[]u8 = null,
    id: []u8,

    pub fn deinit(self: *ModelAction, gpa: std.mem.Allocator) void {
        if (self.provider) |value| gpa.free(value);
        gpa.free(self.id);
        self.* = undefined;
    }

    pub fn reference(self: ModelAction, allocator: std.mem.Allocator) ![]u8 {
        if (self.provider) |provider| return std.fmt.allocPrint(allocator, "{s}/{s}", .{ provider, self.id });
        return allocator.dupe(u8, self.id);
    }

    pub fn clone(self: ModelAction, allocator: std.mem.Allocator) !ModelAction {
        const provider = if (self.provider) |value| try allocator.dupe(u8, value) else null;
        errdefer if (provider) |value| allocator.free(value);
        return .{ .provider = provider, .id = try allocator.dupe(u8, self.id) };
    }
};

pub const PromptDelivery = enum { next_turn, steer, follow_up };

pub const CommandOutput = struct {
    message: ?[]u8 = null,
    prompt: ?[]u8 = null,
    prompt_delivery: PromptDelivery = .next_turn,
    session_name: ?[]u8 = null,
    entries: []EntryAction = &.{},
    labels: []LabelAction = &.{},
    active_tools: ?[][]u8 = null,
    model: ?ModelAction = null,
    thinking_level: ?[]u8 = null,
    abort: bool = false,
    is_error: bool = false,
    terminate: bool = false,
    actions: actions_mod.Batch = .{},

    pub fn deinit(self: *CommandOutput, gpa: std.mem.Allocator) void {
        if (self.message) |value| gpa.free(value);
        if (self.prompt) |value| gpa.free(value);
        if (self.session_name) |value| gpa.free(value);
        for (self.entries) |*entry| entry.deinit(gpa);
        if (self.entries.len > 0) gpa.free(self.entries);
        for (self.labels) |*label| label.deinit(gpa);
        if (self.labels.len > 0) gpa.free(self.labels);
        if (self.active_tools) |tools| {
            for (tools) |tool| gpa.free(tool);
            gpa.free(tools);
        }
        if (self.model) |*model| model.deinit(gpa);
        if (self.thinking_level) |value| gpa.free(value);
        self.actions.deinit(gpa);
        self.* = undefined;
    }
};

pub const ToolUpdate = struct {
    content: []u8,
    is_error: bool = false,
    image_b64: ?[]u8 = null,
    image_mime: ?[]u8 = null,
    /// Ordered complete image content. Legacy singular fields retain the first
    /// image for compatibility with older native callers.
    images: []ToolImage = &.{},
    details_json: ?[]u8 = null,
    usage: ?ToolUsage = null,
    added_tool_names: []const []const u8 = &.{},
    observer_deferred: bool = false,

    pub fn deinit(self: *ToolUpdate, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        if (self.image_b64) |v| gpa.free(v);
        if (self.image_mime) |v| gpa.free(v);
        deinitToolImages(gpa, self.images);
        if (self.details_json) |v| gpa.free(v);
        deinitStringList(gpa, self.added_tool_names);
        self.* = undefined;
    }
};

/// Borrowed live-update callback. The update and all of its fields remain valid
/// only for the duration of the callback.
pub const ToolUpdateFn = *const fn (?*anyopaque, *const ToolUpdate) anyerror!void;

pub const ToolOutput = struct {
    content: []u8,
    is_error: bool = false,
    image_b64: ?[]u8 = null,
    image_mime: ?[]u8 = null,
    /// Ordered complete image content. Legacy singular fields retain the first
    /// image for compatibility with older native callers.
    images: []ToolImage = &.{},
    details_json: ?[]u8 = null,
    usage: ?ToolUsage = null,
    added_tool_names: []const []const u8 = &.{},
    updates: []ToolUpdate = &.{},
    /// Script helpers such as createReadTool() can explicitly hand execution
    /// back to the native Zig built-in while retaining extension renderers.
    delegate_builtin: bool = false,
    terminate: bool = false,
    actions: actions_mod.Batch = .{},

    pub fn deinit(self: *ToolOutput, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        if (self.image_b64) |v| gpa.free(v);
        if (self.image_mime) |v| gpa.free(v);
        deinitToolImages(gpa, self.images);
        if (self.details_json) |v| gpa.free(v);
        deinitStringList(gpa, self.added_tool_names);
        for (self.updates) |*update| update.deinit(gpa);
        if (self.updates.len > 0) gpa.free(self.updates);
        self.actions.deinit(gpa);
        self.* = undefined;
    }
};

pub const ExtensionManifest = struct {
    name: []const u8,
    version: []const u8 = "0.0.0",
    hooks: []const []const u8 = &.{},
    tools: []ExtensionTool = &.{},
    commands: []ExtensionCommand = &.{},
    shortcuts: []ExtensionShortcut = &.{},
    flags: []ExtensionFlag = &.{},
    providers: []ExtensionProviderRegistration = &.{},
    message_renderers: []const []const u8 = &.{},
    entry_renderers: []const []const u8 = &.{},
    has_markdown_transformer: bool = false,
    entry: []const u8 = "",
    script_runtime: ?*js_runtime.Runtime = null,

    pub fn deinit(self: *ExtensionManifest, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.version);
        for (self.hooks) |h| gpa.free(h);
        gpa.free(self.hooks);
        for (self.tools) |*tool| tool.deinit(gpa);
        gpa.free(self.tools);
        for (self.commands) |*command| command.deinit(gpa);
        gpa.free(self.commands);
        for (self.shortcuts) |*shortcut| shortcut.deinit(gpa);
        gpa.free(self.shortcuts);
        for (self.flags) |*flag| flag.deinit(gpa);
        gpa.free(self.flags);
        for (self.providers) |*provider| provider.deinit(gpa);
        gpa.free(self.providers);
        for (self.message_renderers) |renderer| gpa.free(renderer);
        gpa.free(self.message_renderers);
        for (self.entry_renderers) |renderer| gpa.free(renderer);
        gpa.free(self.entry_renderers);
        if (self.entry.len > 0) gpa.free(self.entry);
        if (self.script_runtime) |runtime| runtime.deinit();
        self.* = undefined;
    }

    pub fn handles(self: *const ExtensionManifest, hook: []const u8) bool {
        for (self.hooks) |candidate| if (std.mem.eql(u8, candidate, hook)) return true;
        return false;
    }
};

pub const HookResponse = struct {
    extension_name: []u8,
    json: []u8,
    actions: actions_mod.Batch = .{},

    pub fn deinit(self: *HookResponse, gpa: std.mem.Allocator) void {
        gpa.free(self.extension_name);
        gpa.free(self.json);
        self.actions.deinit(gpa);
        self.* = undefined;
    }
};

pub const HookError = struct {
    extension_name: []u8,
    message: []u8,

    pub fn deinit(self: *HookError, gpa: std.mem.Allocator) void {
        gpa.free(self.extension_name);
        gpa.free(self.message);
        self.* = undefined;
    }
};

pub const EmitResult = struct {
    responses: []HookResponse,
    errors: []HookError,

    pub fn deinit(self: *EmitResult, gpa: std.mem.Allocator) void {
        for (self.responses) |*item| item.deinit(gpa);
        for (self.errors) |*item| item.deinit(gpa);
        gpa.free(self.responses);
        gpa.free(self.errors);
        self.* = undefined;
    }
};

pub const Host = struct {
    gpa: std.mem.Allocator,
    io: Io,
    extensions: std.ArrayList(ExtensionManifest) = .empty,
    last_hook: []const u8 = "",
    hook_timeout_seconds: i64 = 15,
    max_stdout_bytes: usize = 1024 * 1024,
    max_stderr_bytes: usize = 64 * 1024,
    /// Program used for upstream JavaScript/TypeScript extension execution.
    /// The default resolves through PATH and can be replaced by embedders.
    js_runtime_program: []const u8 = "node",
    /// Shared native UI bridge and invocation-context snapshot propagated to
    /// every persistent script worker, including workers loaded later.
    script_ui_bridge: ?js_runtime.UiBridge = null,
    script_context_json: ?[]u8 = null,

    pub fn deinit(self: *Host) void {
        for (self.extensions.items) |*e| e.deinit(self.gpa);
        self.extensions.deinit(self.gpa);
        if (self.last_hook.len > 0) self.gpa.free(self.last_hook);
        if (self.script_context_json) |context| self.gpa.free(context);
        self.* = undefined;
    }

    pub fn setScriptUiBridge(self: *Host, bridge: ?js_runtime.UiBridge) void {
        self.script_ui_bridge = bridge;
        for (self.extensions.items) |*extension| if (extension.script_runtime) |runtime| runtime.setUiBridge(bridge);
    }

    /// Return the persistent JavaScript worker that owns an extension action.
    /// Native manifest extensions intentionally return null.
    pub fn scriptRuntimeForExtension(self: *Host, extension_name: []const u8) ?*js_runtime.Runtime {
        for (self.extensions.items) |*extension| {
            if (std.mem.eql(u8, extension.name, extension_name)) return extension.script_runtime;
        }
        return null;
    }

    /// Replace the ExtensionContext snapshot supplied to every later script
    /// hook/tool/command invocation. Native extensions are unaffected.
    pub fn setScriptContextJson(self: *Host, raw: []const u8) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidJavaScriptExtensionContext;
        const owned = try self.gpa.dupe(u8, raw);
        errdefer self.gpa.free(owned);
        for (self.extensions.items) |*extension| if (extension.script_runtime) |runtime| try runtime.setContextJson(raw);
        if (self.script_context_json) |old| self.gpa.free(old);
        self.script_context_json = owned;
    }

    /// Load an explicitly requested extension. Native manifest directories and
    /// files keep their existing behavior; upstream `.js`/`.ts` modules and
    /// directories containing a conventional index module use the persistent
    /// compatibility runtime. Explicit paths report failures.
    pub fn loadPath(self: *Host, path: []const u8) !void {
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return error.ExtensionPathNotFound;
        switch (stat.kind) {
            .directory => return self.loadDirExplicit(path),
            .file => {
                if (endsWithAsciiIgnoreCase(path, ".json")) return self.loadManifestFile(path);
                if (js_runtime.isScriptPath(path)) return self.loadScript(path);
                return error.UnsupportedExtensionPath;
            },
            else => return error.UnsupportedExtensionPath,
        }
    }

    fn loadDirExplicit(self: *Host, dir_path: []const u8) !void {
        const manifest_path = try std.fs.path.join(self.gpa, &.{ dir_path, "extension.json" });
        defer self.gpa.free(manifest_path);
        if (std.Io.Dir.cwd().statFile(self.io, manifest_path, .{})) |stat| {
            if (stat.kind == .file) return self.loadManifestFile(manifest_path);
        } else |_| {}

        // Match upstream explicit-directory behavior: first resolve the
        // directory itself as a package/index extension, then (when it has no
        // entry point) scan its direct children using the ordinary one-level
        // discovery rules. An empty explicit directory is valid and simply
        // contributes no extensions.
        var entries = try resolveScriptEntries(self.gpa, self.io, dir_path);
        defer entries.deinit(self.gpa);
        if (entries.items.items.len > 0) {
            for (entries.items.items) |source_path| try self.loadScript(source_path);
            return;
        }
        try self.scanRoot(dir_path);
    }

    fn loadManifestFile(self: *Host, manifest_path: []const u8) !void {
        const raw = std.Io.Dir.cwd().readFileAlloc(self.io, manifest_path, self.gpa, .limited(256 * 1024)) catch |err| switch (err) {
            error.StreamTooLong => return error.ManifestTooLarge,
            else => return error.ManifestNotFound,
        };
        defer self.gpa.free(raw);
        const base_dir = std.fs.path.dirname(manifest_path) orelse ".";
        try self.loadJson(raw, base_dir);
    }

    pub fn loadDir(self: *Host, dir_path: []const u8) !void {
        const man_path = try std.fs.path.join(self.gpa, &.{ dir_path, "extension.json" });
        defer self.gpa.free(man_path);
        if (std.Io.Dir.cwd().readFileAlloc(self.io, man_path, self.gpa, .limited(256 * 1024))) |raw| {
            defer self.gpa.free(raw);
            try self.loadJson(raw, dir_path);
            return;
        } else |_| {}

        var entries = try resolveScriptEntries(self.gpa, self.io, dir_path);
        defer entries.deinit(self.gpa);
        for (entries.items.items) |source_path| self.loadScript(source_path) catch {};
    }

    fn loadScript(self: *Host, source_path: []const u8) !void {
        var started = try js_runtime.Runtime.start(self.gpa, self.io, source_path, self.js_runtime_program);
        errdefer started.runtime.deinit();
        started.runtime.timeout_ms = if (self.hook_timeout_seconds <= 0)
            0
        else
            @as(u64, @intCast(self.hook_timeout_seconds)) *| 1000;
        started.runtime.setUiBridge(self.script_ui_bridge);
        if (self.script_context_json) |context| try started.runtime.setContextJson(context);
        defer self.gpa.free(started.manifest_json);
        const previous_len = self.extensions.items.len;
        try self.loadJson(started.manifest_json, std.fs.path.dirname(source_path) orelse ".");
        if (self.extensions.items.len != previous_len + 1) return error.InvalidJavaScriptExtensionHandshake;
        self.extensions.items[previous_len].script_runtime = started.runtime;
    }

    pub fn loadJson(self: *Host, raw: []const u8, base_dir: []const u8) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidManifest;
        const name_value = parsed.value.object.get("name") orelse return error.InvalidManifest;
        if (name_value != .string or name_value.string.len == 0) return error.InvalidManifest;
        const version = if (parsed.value.object.get("version")) |v| (if (v == .string) v.string else return error.InvalidManifest) else "0.0.0";

        var hooks_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (hooks_list.items) |h| self.gpa.free(h);
            hooks_list.deinit(self.gpa);
        }
        if (parsed.value.object.get("hooks")) |h| {
            if (h != .array) return error.InvalidManifest;
            for (h.array.items) |item| {
                if (item != .string or item.string.len == 0) return error.InvalidManifest;
                if (!containsString(hooks_list.items, item.string)) try hooks_list.append(self.gpa, try self.gpa.dupe(u8, item.string));
            }
        }

        var tools_list: std.ArrayList(ExtensionTool) = .empty;
        errdefer {
            for (tools_list.items) |*tool| tool.deinit(self.gpa);
            tools_list.deinit(self.gpa);
        }
        if (parsed.value.object.get("tools")) |tools_value| {
            if (tools_value != .array) return error.InvalidManifest;
            for (tools_value.array.items) |tool_value| {
                if (tool_value != .object) return error.InvalidManifest;
                const tool_name = tool_value.object.get("name") orelse return error.InvalidManifest;
                if (tool_name != .string or tool_name.string.len == 0) return error.InvalidManifest;
                if (containsTool(tools_list.items, tool_name.string) or self.hasTool(tool_name.string)) return error.DuplicateToolName;
                const description_value = tool_value.object.get("description");
                const description = if (description_value) |value|
                    (if (value == .string) value.string else return error.InvalidManifest)
                else
                    "";
                const parameters = tool_value.object.get("parameters") orelse tool_value.object.get("inputSchema");
                const parameters_json = if (parameters) |value| blk: {
                    if (value != .object) return error.InvalidManifest;
                    break :blk try stringifyValue(self.gpa, value);
                } else try self.gpa.dupe(u8, "{\"type\":\"object\",\"properties\":{}}");
                errdefer self.gpa.free(parameters_json);
                const execution_mode: ToolExecutionMode = if (tool_value.object.get("executionMode")) |mode| blk: {
                    if (mode != .string) return error.InvalidManifest;
                    if (std.mem.eql(u8, mode.string, "sequential")) break :blk .sequential;
                    if (std.mem.eql(u8, mode.string, "parallel")) break :blk .parallel;
                    return error.InvalidManifest;
                } else .parallel;
                const has_render_call = try optionalBoolean(tool_value.object, "hasRenderCall", false);
                const has_render_result = try optionalBoolean(tool_value.object, "hasRenderResult", false);
                const has_prepare_arguments = try optionalBoolean(tool_value.object, "hasPrepareArguments", false);
                const render_shell_self = if (tool_value.object.get("renderShell")) |shell| blk: {
                    if (shell != .string) return error.InvalidManifest;
                    if (std.mem.eql(u8, shell.string, "self")) break :blk true;
                    if (std.mem.eql(u8, shell.string, "default")) break :blk false;
                    return error.InvalidManifest;
                } else false;
                try tools_list.append(self.gpa, .{
                    .name = try self.gpa.dupe(u8, tool_name.string),
                    .description = try self.gpa.dupe(u8, description),
                    .parameters_json = parameters_json,
                    .execution_mode = execution_mode,
                    .has_render_call = has_render_call,
                    .has_render_result = has_render_result,
                    .has_prepare_arguments = has_prepare_arguments,
                    .render_shell_self = render_shell_self,
                });
            }
        }

        var commands_list: std.ArrayList(ExtensionCommand) = .empty;
        errdefer {
            for (commands_list.items) |*command| command.deinit(self.gpa);
            commands_list.deinit(self.gpa);
        }
        if (parsed.value.object.get("commands")) |commands_value| {
            if (commands_value != .array) return error.InvalidManifest;
            for (commands_value.array.items) |command_value| {
                if (command_value != .object) return error.InvalidManifest;
                const command_name = command_value.object.get("name") orelse return error.InvalidManifest;
                if (command_name != .string or command_name.string.len == 0) return error.InvalidManifest;
                if (containsCommand(commands_list.items, command_name.string) or self.hasCommand(command_name.string)) return error.DuplicateCommandName;
                const description_value = command_value.object.get("description");
                const description = if (description_value) |value|
                    (if (value == .string) value.string else return error.InvalidManifest)
                else
                    "";
                const hint_value = command_value.object.get("argumentHint") orelse command_value.object.get("argument-hint");
                const argument_hint = if (hint_value) |value| blk: {
                    if (value != .string) return error.InvalidManifest;
                    break :blk try self.gpa.dupe(u8, value.string);
                } else null;
                errdefer if (argument_hint) |value| self.gpa.free(value);
                try commands_list.append(self.gpa, .{
                    .name = try self.gpa.dupe(u8, command_name.string),
                    .description = try self.gpa.dupe(u8, description),
                    .argument_hint = argument_hint,
                });
            }
        }

        var shortcuts_list: std.ArrayList(ExtensionShortcut) = .empty;
        errdefer {
            for (shortcuts_list.items) |*shortcut| shortcut.deinit(self.gpa);
            shortcuts_list.deinit(self.gpa);
        }
        if (parsed.value.object.get("shortcuts")) |shortcuts_value| {
            if (shortcuts_value != .array) return error.InvalidManifest;
            for (shortcuts_value.array.items) |shortcut_value| {
                if (shortcut_value != .object) return error.InvalidManifest;
                const key_value = shortcut_value.object.get("key") orelse shortcut_value.object.get("shortcut") orelse return error.InvalidManifest;
                if (key_value != .string or key_value.string.len == 0) return error.InvalidManifest;
                if (containsShortcut(shortcuts_list.items, key_value.string)) return error.DuplicateShortcutKey;
                const description_value = shortcut_value.object.get("description");
                const description = if (description_value) |value|
                    (if (value == .string) value.string else return error.InvalidManifest)
                else
                    "";
                try shortcuts_list.append(self.gpa, .{
                    .key = try self.gpa.dupe(u8, key_value.string),
                    .description = try self.gpa.dupe(u8, description),
                });
            }
        }

        var flags_list: std.ArrayList(ExtensionFlag) = .empty;
        errdefer {
            for (flags_list.items) |*flag| flag.deinit(self.gpa);
            flags_list.deinit(self.gpa);
        }
        if (parsed.value.object.get("flags")) |flags_value| {
            if (flags_value != .array) return error.InvalidManifest;
            for (flags_value.array.items) |flag_value| {
                if (flag_value != .object) return error.InvalidManifest;
                const flag_name = flag_value.object.get("name") orelse return error.InvalidManifest;
                const flag_type = flag_value.object.get("type") orelse return error.InvalidManifest;
                if (flag_name != .string or flag_name.string.len == 0 or flag_type != .string) return error.InvalidManifest;
                if (containsFlag(flags_list.items, flag_name.string) or self.hasFlag(flag_name.string)) return error.DuplicateFlagName;
                const kind: ExtensionFlagKind = if (std.mem.eql(u8, flag_type.string, "boolean"))
                    .boolean
                else if (std.mem.eql(u8, flag_type.string, "string"))
                    .string
                else
                    return error.InvalidManifest;
                const description_value = flag_value.object.get("description");
                const description = if (description_value) |value|
                    (if (value == .string) value.string else return error.InvalidManifest)
                else
                    "";

                var parsed_flag = ExtensionFlag{
                    .name = try self.gpa.dupe(u8, flag_name.string),
                    .description = try self.gpa.dupe(u8, description),
                    .kind = kind,
                };
                errdefer parsed_flag.deinit(self.gpa);
                if (flag_value.object.get("default")) |default| {
                    parsed_flag.value = switch (kind) {
                        .boolean => if (default == .bool)
                            ExtensionFlagValue{ .boolean = default.bool }
                        else
                            return error.InvalidManifest,
                        .string => if (default == .string)
                            ExtensionFlagValue{ .string = try self.gpa.dupe(u8, default.string) }
                        else
                            return error.InvalidManifest,
                    };
                }
                try flags_list.append(self.gpa, parsed_flag);
            }
        }

        var providers_list: std.ArrayList(ExtensionProviderRegistration) = .empty;
        errdefer {
            for (providers_list.items) |*provider| provider.deinit(self.gpa);
            providers_list.deinit(self.gpa);
        }
        if (parsed.value.object.get("providers")) |providers_value| {
            if (providers_value != .array) return error.InvalidManifest;
            for (providers_value.array.items) |provider_value| {
                if (provider_value != .object) return error.InvalidManifest;
                const provider_name = provider_value.object.get("name") orelse return error.InvalidManifest;
                const provider_config = provider_value.object.get("config") orelse return error.InvalidManifest;
                if (provider_name != .string or provider_name.string.len == 0 or provider_config != .object)
                    return error.InvalidManifest;
                for (providers_list.items) |existing| {
                    if (std.ascii.eqlIgnoreCase(existing.name, provider_name.string)) return error.DuplicateProviderName;
                }
                const config_json = try stringifyValue(self.gpa, provider_config);
                errdefer self.gpa.free(config_json);
                try providers_list.append(self.gpa, .{
                    .name = try self.gpa.dupe(u8, provider_name.string),
                    .config_json = config_json,
                });
            }
        }

        var message_renderers_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (message_renderers_list.items) |renderer| self.gpa.free(renderer);
            message_renderers_list.deinit(self.gpa);
        }
        try parseUniqueStringArray(self.gpa, parsed.value.object, "messageRenderers", &message_renderers_list);

        var entry_renderers_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (entry_renderers_list.items) |renderer| self.gpa.free(renderer);
            entry_renderers_list.deinit(self.gpa);
        }
        try parseUniqueStringArray(self.gpa, parsed.value.object, "entryRenderers", &entry_renderers_list);
        const has_markdown_transformer = try optionalBoolean(parsed.value.object, "hasMarkdownTransformer", false);

        var entry: []const u8 = "";
        if (parsed.value.object.get("entry")) |e| {
            if (e != .string) return error.InvalidManifest;
            if (e.string.len > 0) {
                entry = if (std.fs.path.isAbsolute(e.string))
                    try self.gpa.dupe(u8, e.string)
                else
                    try std.fs.path.join(self.gpa, &.{ base_dir, e.string });
            }
        }
        try self.extensions.append(self.gpa, .{
            .name = try self.gpa.dupe(u8, name_value.string),
            .version = try self.gpa.dupe(u8, version),
            .hooks = try hooks_list.toOwnedSlice(self.gpa),
            .tools = try tools_list.toOwnedSlice(self.gpa),
            .commands = try commands_list.toOwnedSlice(self.gpa),
            .shortcuts = try shortcuts_list.toOwnedSlice(self.gpa),
            .flags = try flags_list.toOwnedSlice(self.gpa),
            .providers = try providers_list.toOwnedSlice(self.gpa),
            .message_renderers = try message_renderers_list.toOwnedSlice(self.gpa),
            .entry_renderers = try entry_renderers_list.toOwnedSlice(self.gpa),
            .has_markdown_transformer = has_markdown_transformer,
            .entry = entry,
            .script_runtime = null,
        });
    }

    /// Discover `<root>/*/extension.json`, global first and project second.
    /// Project discovery is entirely skipped when `trust_project` is false.
    pub fn discover(self: *Host, cwd: []const u8, agent_dir: ?[]const u8, trust_project: bool) !void {
        if (agent_dir) |agent| {
            const root = try std.fs.path.join(self.gpa, &.{ agent, "extensions" });
            defer self.gpa.free(root);
            try self.scanRoot(root);
        }
        if (trust_project) {
            const root = try std.fs.path.join(self.gpa, &.{ cwd, ".pi", "extensions" });
            defer self.gpa.free(root);
            try self.scanRoot(root);
        }
    }

    fn scanRoot(self: *Host, root: []const u8) !void {
        var dir = std.Io.Dir.cwd().openDir(self.io, root, .{ .iterate = true }) catch return;
        defer dir.close(self.io);
        var it = dir.iterate();
        while (try it.next(self.io)) |entry| {
            const child = try std.fs.path.join(self.gpa, &.{ root, entry.name });
            defer self.gpa.free(child);
            const kind = if (entry.kind == .sym_link)
                (std.Io.Dir.cwd().statFile(self.io, child, .{}) catch continue).kind
            else
                entry.kind;
            switch (kind) {
                .directory => try self.loadDir(child),
                .file => if (isUpstreamScriptPath(entry.name)) self.loadScript(child) catch {},
                else => {},
            }
        }
    }

    /// Record an event without executing entries. Useful for observability and
    /// callers that deliberately disable executable extensions.
    pub fn emit(self: *Host, hook: []const u8, payload_json: []const u8) !void {
        try validateJson(self.gpa, payload_json);
        if (self.last_hook.len > 0) self.gpa.free(self.last_hook);
        self.last_hook = try std.fmt.allocPrint(self.gpa, "{s}:{s}", .{ hook, payload_json });
    }

    /// Execute every handler for `hook` independently. A failing extension is
    /// reported but never prevents later extensions from running.
    pub fn executeHook(self: *Host, hook: []const u8, payload_json: []const u8) !EmitResult {
        return self.executeHookWithAbort(hook, payload_json, null);
    }

    /// Execute lifecycle handlers with the active agent abort signal. Script
    /// runtimes receive a real AbortSignal; native process extensions retain
    /// their existing isolated process contract.
    pub fn executeHookWithAbort(self: *Host, hook: []const u8, payload_json: []const u8, abort_flag: ?*bool) !EmitResult {
        try self.emit(hook, payload_json);
        var responses: std.ArrayList(HookResponse) = .empty;
        var errors: std.ArrayList(HookError) = .empty;
        errdefer {
            for (responses.items) |*item| item.deinit(self.gpa);
            for (errors.items) |*item| item.deinit(self.gpa);
            responses.deinit(self.gpa);
            errors.deinit(self.gpa);
        }

        for (self.extensions.items) |*ext| {
            if (!ext.handles(hook) or (ext.entry.len == 0 and ext.script_runtime == null)) continue;
            const flags_json = try self.flagsJson(ext);
            defer self.gpa.free(flags_json);
            const raw = (if (ext.script_runtime) |runtime|
                runtime.invokeHookWithAbort(hook, payload_json, flags_json, abort_flag)
            else
                self.runExtension(ext, .hook, hook, payload_json, flags_json)) catch |err| {
                try errors.append(self.gpa, .{
                    .extension_name = try self.gpa.dupe(u8, ext.name),
                    .message = try std.fmt.allocPrint(self.gpa, "extension execution failed: {s}", .{@errorName(err)}),
                });
                continue;
            };
            defer self.gpa.free(raw);
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len == 0) continue;
            validateJson(self.gpa, trimmed) catch {
                try errors.append(self.gpa, .{
                    .extension_name = try self.gpa.dupe(u8, ext.name),
                    .message = try self.gpa.dupe(u8, "extension returned invalid JSON"),
                });
                continue;
            };
            var action_batch = actions_mod.Batch.parse(self.gpa, ext.name, hook, trimmed) catch |err| {
                try errors.append(self.gpa, .{
                    .extension_name = try self.gpa.dupe(u8, ext.name),
                    .message = try std.fmt.allocPrint(self.gpa, "extension returned invalid action queue: {s}", .{@errorName(err)}),
                });
                continue;
            };
            errdefer action_batch.deinit(self.gpa);
            try responses.append(self.gpa, .{
                .extension_name = try self.gpa.dupe(u8, ext.name),
                .json = try self.gpa.dupe(u8, trimmed),
                .actions = action_batch,
            });
        }
        return .{
            .responses = try responses.toOwnedSlice(self.gpa),
            .errors = try errors.toOwnedSlice(self.gpa),
        };
    }

    fn runExtension(
        self: *Host,
        ext: *ExtensionManifest,
        kind: InvocationKind,
        name: []const u8,
        argument: []const u8,
        flags_json: []const u8,
    ) ![]u8 {
        if (ext.script_runtime) |runtime| {
            return switch (kind) {
                .hook => runtime.invokeHook(name, argument, flags_json),
                .tool => runtime.invokeTool(name, argument, flags_json),
                .command => runtime.invokeCommand(name, argument, flags_json),
                .shortcut => runtime.invokeShortcut(name, flags_json),
            };
        }
        if (ext.entry.len == 0) return error.ExtensionHasNoExecutableEntry;
        const mode = switch (kind) {
            .hook => "--pi-hook",
            .tool => "--pi-tool",
            .command => "--pi-command",
            .shortcut => "--pi-shortcut",
        };
        const argv = [_][]const u8{ ext.entry, mode, name, argument, flags_json };
        const result = try std.process.run(self.gpa, self.io, .{
            .argv = &argv,
            .stdout_limit = .limited(self.max_stdout_bytes),
            .stderr_limit = .limited(self.max_stderr_bytes),
            .timeout = .{ .duration = .{ .raw = .fromSeconds(self.hook_timeout_seconds), .clock = .real } },
        });
        defer self.gpa.free(result.stdout);
        defer self.gpa.free(result.stderr);
        const ok = switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        };
        if (!ok) return error.ExtensionProcessFailed;
        return self.gpa.dupe(u8, std.mem.trim(u8, result.stdout, " \t\r\n"));
    }

    pub fn hasCommand(self: *const Host, name: []const u8) bool {
        for (self.extensions.items) |ext| {
            for (ext.commands) |command| if (std.mem.eql(u8, command.name, name)) return true;
        }
        return false;
    }

    /// Execute an extension-owned slash command. Commands are immediate native
    /// actions: they may emit a user-visible message, provide a prompt for the
    /// agent, request termination, or combine those actions in one JSON result.
    pub fn executeCommand(self: *Host, name: []const u8, raw_arguments: []const u8) !?CommandOutput {
        for (self.extensions.items) |*ext| {
            var owns = false;
            for (ext.commands) |command| {
                if (std.mem.eql(u8, command.name, name)) {
                    owns = true;
                    break;
                }
            }
            if (!owns) continue;
            if (ext.entry.len == 0 and ext.script_runtime == null) return try errorCommandOutput(self.gpa, "extension command has no executable entry");
            const flags_json = try self.flagsJson(ext);
            defer self.gpa.free(flags_json);
            const raw = self.runExtension(ext, .command, name, raw_arguments, flags_json) catch |err|
                return try errorCommandOutputFmt(self.gpa, "extension command execution failed: {s}", .{@errorName(err)});
            defer self.gpa.free(raw);
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len == 0) return CommandOutput{};
            return parseCommandOutput(self.gpa, ext.name, name, trimmed) catch try errorCommandOutput(self.gpa, "extension command returned invalid JSON result");
        }
        return null;
    }

    pub fn hasShortcut(self: *const Host, key: []const u8) bool {
        // Later extensions win, matching the original extension runner.
        var index = self.extensions.items.len;
        while (index > 0) {
            index -= 1;
            for (self.extensions.items[index].shortcuts) |shortcut| {
                if (std.ascii.eqlIgnoreCase(shortcut.key, key)) return true;
            }
        }
        return false;
    }

    pub fn executeShortcut(self: *Host, key: []const u8) !?CommandOutput {
        var index = self.extensions.items.len;
        while (index > 0) {
            index -= 1;
            const ext = &self.extensions.items[index];
            var owns = false;
            for (ext.shortcuts) |shortcut| {
                if (std.ascii.eqlIgnoreCase(shortcut.key, key)) {
                    owns = true;
                    break;
                }
            }
            if (!owns) continue;
            if (ext.entry.len == 0 and ext.script_runtime == null) return try errorCommandOutput(self.gpa, "extension shortcut has no executable entry");
            const flags_json = try self.flagsJson(ext);
            defer self.gpa.free(flags_json);
            const raw = self.runExtension(ext, .shortcut, key, "{}", flags_json) catch |err|
                return try errorCommandOutputFmt(self.gpa, "extension shortcut execution failed: {s}", .{@errorName(err)});
            defer self.gpa.free(raw);
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len == 0) return CommandOutput{};
            return parseCommandOutput(self.gpa, ext.name, key, trimmed) catch try errorCommandOutput(self.gpa, "extension shortcut returned invalid JSON result");
        }
        return null;
    }

    pub fn hasTool(self: *const Host, name: []const u8) bool {
        for (self.extensions.items) |ext| {
            for (ext.tools) |tool| if (std.mem.eql(u8, tool.name, name)) return true;
        }
        return false;
    }

    /// Execute an extension-owned tool. Process/validation failures become a
    /// normal error tool result so one extension cannot abort the agent loop.
    pub fn executeTool(self: *Host, name: []const u8, arguments_json: []const u8) !?ToolOutput {
        return self.executeToolWithUpdates("pi-zig-host", name, arguments_json, null, null, null);
    }

    /// Execute a script tool while forwarding each upstream `onUpdate()` value
    /// immediately. Native executable extensions retain their existing batched
    /// result format because they do not expose the persistent worker protocol.
    pub fn executeToolStreaming(
        self: *Host,
        name: []const u8,
        arguments_json: []const u8,
        update_fn: ToolUpdateFn,
        update_ctx: ?*anyopaque,
    ) !?ToolOutput {
        return self.executeToolWithUpdates("pi-zig-host", name, arguments_json, null, update_fn, update_ctx);
    }

    /// Execute a script tool with the real agent call identity and cooperative
    /// abort flag. Native executable extensions keep the compatibility path.
    pub fn executeToolCallStreaming(
        self: *Host,
        tool_call_id: []const u8,
        name: []const u8,
        arguments_json: []const u8,
        abort_flag: ?*bool,
        update_fn: ToolUpdateFn,
        update_ctx: ?*anyopaque,
    ) !?ToolOutput {
        return self.executeToolWithUpdates(tool_call_id, name, arguments_json, abort_flag, update_fn, update_ctx);
    }

    fn executeToolWithUpdates(
        self: *Host,
        tool_call_id: []const u8,
        name: []const u8,
        arguments_json: []const u8,
        abort_flag: ?*bool,
        update_fn: ?ToolUpdateFn,
        update_ctx: ?*anyopaque,
    ) !?ToolOutput {
        try validateJson(self.gpa, arguments_json);
        for (self.extensions.items) |*ext| {
            var owns = false;
            for (ext.tools) |tool| {
                if (std.mem.eql(u8, tool.name, name)) {
                    owns = true;
                    break;
                }
            }
            if (!owns) continue;
            if (ext.entry.len == 0 and ext.script_runtime == null) return try errorToolOutput(self.gpa, "extension tool has no executable entry");
            const flags_json = try self.flagsJson(ext);
            defer self.gpa.free(flags_json);

            var captured_updates: std.ArrayList(ToolUpdate) = .empty;
            defer {
                for (captured_updates.items) |*update| update.deinit(self.gpa);
                captured_updates.deinit(self.gpa);
            }

            const raw = if (ext.script_runtime) |runtime| blk: {
                if (update_fn) |callback| {
                    var adapter = LiveUpdateAdapter{
                        .host = self,
                        .callback = callback,
                        .context = update_ctx,
                        .captured = &captured_updates,
                    };
                    break :blk runtime.invokeToolCallStreaming(tool_call_id, name, arguments_json, flags_json, abort_flag, LiveUpdateAdapter.forward, &adapter) catch |err|
                        return try errorToolOutputFmt(self.gpa, "extension tool execution failed: {s}", .{@errorName(err)});
                }
                break :blk runtime.invokeTool(name, arguments_json, flags_json) catch |err|
                    return try errorToolOutputFmt(self.gpa, "extension tool execution failed: {s}", .{@errorName(err)});
            } else self.runExtension(ext, .tool, name, arguments_json, flags_json) catch |err|
                return try errorToolOutputFmt(self.gpa, "extension tool execution failed: {s}", .{@errorName(err)});
            defer self.gpa.free(raw);
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len == 0) return try errorToolOutput(self.gpa, "extension tool returned no result");
            var output = parseToolOutput(self.gpa, ext.name, name, trimmed) catch
                return try errorToolOutput(self.gpa, "extension tool returned invalid JSON result");
            errdefer output.deinit(self.gpa);
            if (captured_updates.items.len > 0) {
                const merged = try self.gpa.alloc(ToolUpdate, captured_updates.items.len + output.updates.len);
                @memcpy(merged[0..captured_updates.items.len], captured_updates.items);
                @memcpy(merged[captured_updates.items.len..], output.updates);
                captured_updates.items.len = 0;
                if (output.updates.len > 0) self.gpa.free(output.updates);
                output.updates = merged;
            }
            return output;
        }
        return null;
    }

    /// Render a durable custom message using the first upstream-compatible
    /// renderer registered for its custom type. `null` means no extension owns
    /// the renderer; an empty owned slice means the renderer intentionally
    /// produced no visible rows.
    pub fn renderMessage(
        self: *Host,
        custom_type: []const u8,
        message_json: []const u8,
        expanded: bool,
        output_pad: usize,
        width: usize,
    ) !?[]u8 {
        try validateObjectJson(self.gpa, message_json);
        for (self.extensions.items) |*ext| {
            if (!containsString(ext.message_renderers, custom_type)) continue;
            const runtime = ext.script_runtime orelse return null;
            var payload: std.Io.Writer.Allocating = .init(self.gpa);
            defer payload.deinit();
            try payload.writer.writeAll("{\"message\":");
            try payload.writer.writeAll(message_json);
            try payload.writer.print(",\"expanded\":{},\"outputPad\":{d},\"width\":{d}}}", .{ expanded, output_pad, width });
            const raw = try runtime.invokeRenderer("render_message", custom_type, payload.written());
            defer self.gpa.free(raw);
            return try parseRenderedLines(self.gpa, raw);
        }
        return null;
    }

    /// Render a durable custom session entry. Entry renderers are display-only:
    /// their output never enters provider context or rewrites append-only data.
    pub fn renderEntry(
        self: *Host,
        custom_type: []const u8,
        entry_json: []const u8,
        expanded: bool,
        width: usize,
    ) !?[]u8 {
        try validateObjectJson(self.gpa, entry_json);
        for (self.extensions.items) |*ext| {
            if (!containsString(ext.entry_renderers, custom_type)) continue;
            const runtime = ext.script_runtime orelse return null;
            var payload: std.Io.Writer.Allocating = .init(self.gpa);
            defer payload.deinit();
            try payload.writer.writeAll("{\"entry\":");
            try payload.writer.writeAll(entry_json);
            try payload.writer.print(",\"expanded\":{},\"width\":{d}}}", .{ expanded, width });
            const raw = try runtime.invokeRenderer("render_entry", custom_type, payload.written());
            defer self.gpa.free(raw);
            return try parseRenderedLines(self.gpa, raw);
        }
        return null;
    }

    /// Apply markdown transformers in extension load order, matching the
    /// original runner. A failing transformer is isolated and leaves the text
    /// from the preceding transformer intact.
    pub fn transformMarkdown(
        self: *Host,
        markdown: []const u8,
        message_type: []const u8,
        is_streaming: bool,
        available_width: usize,
    ) ![]u8 {
        if (!(std.mem.eql(u8, message_type, "user") or
            std.mem.eql(u8, message_type, "assistant") or
            std.mem.eql(u8, message_type, "assistant-thinking"))) return error.InvalidMarkdownMessageType;
        var current = try self.gpa.dupe(u8, markdown);
        errdefer self.gpa.free(current);
        for (self.extensions.items) |*ext| {
            if (!ext.has_markdown_transformer) continue;
            const runtime = ext.script_runtime orelse continue;
            var payload: std.Io.Writer.Allocating = .init(self.gpa);
            defer payload.deinit();
            try payload.writer.writeAll("{\"markdown\":");
            try std.json.Stringify.value(current, .{}, &payload.writer);
            try payload.writer.writeAll(",\"messageType\":");
            try std.json.Stringify.value(message_type, .{}, &payload.writer);
            try payload.writer.print(",\"isStreaming\":{},\"availableWidth\":{d}}}", .{ is_streaming, available_width });
            const raw = runtime.invokeRenderer("transform_markdown", "", payload.written()) catch continue;
            defer self.gpa.free(raw);
            const next = parseTransformedMarkdown(self.gpa, raw) catch continue;
            self.gpa.free(current);
            current = next;
        }
        return current;
    }

    /// Apply an upstream extension tool's prepareArguments compatibility shim
    /// before JSON-schema validation. The returned object is owned by the host
    /// allocator; null means the extension did not register a preparer.
    pub fn prepareToolArguments(self: *Host, tool_name: []const u8, arguments_json: []const u8) !?[]u8 {
        try validateObjectJson(self.gpa, arguments_json);
        for (self.extensions.items) |*ext| {
            const tool = findTool(ext.tools, tool_name) orelse continue;
            if (!tool.has_prepare_arguments) return null;
            const runtime = ext.script_runtime orelse return error.ExtensionToolNotExecutable;
            var payload: std.Io.Writer.Allocating = .init(self.gpa);
            defer payload.deinit();
            try payload.writer.writeAll("{\"args\":");
            try payload.writer.writeAll(arguments_json);
            try payload.writer.writeByte('}');
            const raw = try runtime.invokeRenderer("prepare_tool_arguments", tool_name, payload.written());
            defer self.gpa.free(raw);
            var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{});
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidPreparedToolArguments;
            const found = parsed.value.object.get("found") orelse return error.InvalidPreparedToolArguments;
            if (found != .bool) return error.InvalidPreparedToolArguments;
            if (!found.bool) return null;
            const value = parsed.value.object.get("arguments") orelse return error.InvalidPreparedToolArguments;
            if (value != .object) return error.InvalidPreparedToolArguments;
            return try stringifyValue(self.gpa, value);
        }
        return null;
    }

    pub fn renderToolCall(
        self: *Host,
        tool_name: []const u8,
        tool_call_id: []const u8,
        arguments_json: []const u8,
        expanded: bool,
        width: usize,
    ) !?[]u8 {
        try validateObjectJson(self.gpa, arguments_json);
        for (self.extensions.items) |*ext| {
            const tool = findTool(ext.tools, tool_name) orelse continue;
            if (!tool.has_render_call) return null;
            const runtime = ext.script_runtime orelse return null;
            var payload: std.Io.Writer.Allocating = .init(self.gpa);
            defer payload.deinit();
            try payload.writer.writeAll("{\"toolCallId\":");
            try std.json.Stringify.value(tool_call_id, .{}, &payload.writer);
            try payload.writer.writeAll(",\"args\":");
            try payload.writer.writeAll(arguments_json);
            try payload.writer.print(",\"expanded\":{},\"isPartial\":false,\"executionStarted\":true,\"argsComplete\":true,\"width\":{d}}}", .{ expanded, width });
            const raw = try runtime.invokeRenderer("render_tool_call", tool_name, payload.written());
            defer self.gpa.free(raw);
            return try parseRenderedLines(self.gpa, raw);
        }
        return null;
    }

    pub fn renderToolResult(
        self: *Host,
        tool_name: []const u8,
        tool_call_id: []const u8,
        content: []const u8,
        is_error: bool,
        expanded: bool,
        is_partial: bool,
        width: usize,
    ) !?[]u8 {
        return self.renderToolResultRich(
            tool_name,
            tool_call_id,
            content,
            is_error,
            null,
            null,
            null,
            expanded,
            is_partial,
            true,
            width,
        );
    }

    pub fn renderToolResultRich(
        self: *Host,
        tool_name: []const u8,
        tool_call_id: []const u8,
        content: []const u8,
        is_error: bool,
        details_json: ?[]const u8,
        image_b64: ?[]const u8,
        image_mime: ?[]const u8,
        expanded: bool,
        is_partial: bool,
        show_images: bool,
        width: usize,
    ) !?[]u8 {
        var legacy: [1]ToolImage = undefined;
        const images: []const ToolImage = if (image_b64) |data| blk: {
            legacy[0] = .{
                .data_b64 = @constCast(data),
                .mime_type = @constCast(image_mime orelse "image/png"),
            };
            break :blk &legacy;
        } else &.{};
        return self.renderToolResultRichImages(
            tool_name,
            tool_call_id,
            content,
            is_error,
            details_json,
            images,
            expanded,
            is_partial,
            show_images,
            width,
        );
    }

    pub fn renderToolResultRichImages(
        self: *Host,
        tool_name: []const u8,
        tool_call_id: []const u8,
        content: []const u8,
        is_error: bool,
        details_json: ?[]const u8,
        images: []const ToolImage,
        expanded: bool,
        is_partial: bool,
        show_images: bool,
        width: usize,
    ) !?[]u8 {
        if (details_json) |details| try validateJson(self.gpa, details);
        for (self.extensions.items) |*ext| {
            const tool = findTool(ext.tools, tool_name) orelse continue;
            if (!tool.has_render_result) return null;
            const runtime = ext.script_runtime orelse return null;
            var payload: std.Io.Writer.Allocating = .init(self.gpa);
            defer payload.deinit();
            try payload.writer.writeAll("{\"toolCallId\":");
            try std.json.Stringify.value(tool_call_id, .{}, &payload.writer);
            try payload.writer.writeAll(",\"result\":{\"content\":[");
            var wrote_content = false;
            if (content.len > 0 or images.len == 0) {
                try payload.writer.writeAll("{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(content, .{}, &payload.writer);
                try payload.writer.writeByte('}');
                wrote_content = true;
            }
            for (images) |image| {
                if (wrote_content) try payload.writer.writeByte(',');
                try payload.writer.writeAll("{\"type\":\"image\",\"data\":");
                try std.json.Stringify.value(image.data_b64, .{}, &payload.writer);
                try payload.writer.writeAll(",\"mimeType\":");
                try std.json.Stringify.value(image.mime_type, .{}, &payload.writer);
                try payload.writer.writeByte('}');
                wrote_content = true;
            }
            try payload.writer.writeAll("],\"details\":");
            if (details_json) |details|
                try payload.writer.writeAll(details)
            else
                try payload.writer.writeAll("null");
            try payload.writer.print(",\"isError\":{}}},\"isError\":{},\"expanded\":{},\"isPartial\":{},\"showImages\":{},\"executionStarted\":true,\"argsComplete\":true,\"width\":{d}}}", .{ is_error, is_error, expanded, is_partial, show_images, width });
            const raw = try runtime.invokeRenderer("render_tool_result", tool_name, payload.written());
            defer self.gpa.free(raw);
            return try parseRenderedLines(self.gpa, raw);
        }
        return null;
    }

    pub fn hasFlag(self: *const Host, name: []const u8) bool {
        for (self.extensions.items) |ext| {
            for (ext.flags) |flag| if (std.mem.eql(u8, flag.name, name)) return true;
        }
        return false;
    }

    pub fn applyCliFlag(self: *Host, name: []const u8, value: ?[]const u8) !void {
        for (self.extensions.items) |*ext| {
            for (ext.flags) |*flag| {
                if (!std.mem.eql(u8, flag.name, name)) continue;
                try flag.setCliValue(self.gpa, value);
                return;
            }
        }
        return error.UnknownExtensionFlag;
    }

    pub fn flagsJson(self: *Host, ext: *const ExtensionManifest) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.writeByte('{');
        var wrote = false;
        for (ext.flags) |flag| {
            const value = flag.value orelse continue;
            if (wrote) try out.writer.writeByte(',');
            wrote = true;
            try std.json.Stringify.value(flag.name, .{}, &out.writer);
            try out.writer.writeByte(':');
            switch (value) {
                .boolean => |boolean| try out.writer.writeAll(if (boolean) "true" else "false"),
                .string => |text| try std.json.Stringify.value(text, .{}, &out.writer),
            }
        }
        try out.writer.writeByte('}');
        return try out.toOwnedSlice();
    }

    pub fn hasHook(self: *const Host, hook: []const u8) bool {
        for (self.extensions.items) |ext| if (ext.handles(hook)) return true;
        return false;
    }
};

const ScriptEntries = struct {
    items: std.ArrayList([]u8) = .empty,

    fn deinit(self: *ScriptEntries, gpa: std.mem.Allocator) void {
        for (self.items.items) |item| gpa.free(item);
        self.items.deinit(gpa);
        self.* = undefined;
    }
};

/// Resolve a package directory using the original Pi precedence:
/// `package.json` `pi.extensions` entries first, then `index.ts`, then
/// `index.js`. Missing package entries are skipped; when every declared entry
/// is missing, index fallback remains available just like the TypeScript host.
fn resolveScriptEntries(gpa: std.mem.Allocator, io: Io, dir_path: []const u8) !ScriptEntries {
    var result = ScriptEntries{};
    errdefer result.deinit(gpa);

    const package_path = try std.fs.path.join(gpa, &.{ dir_path, "package.json" });
    defer gpa.free(package_path);
    if (std.Io.Dir.cwd().readFileAlloc(io, package_path, gpa, .limited(1024 * 1024))) |raw| {
        defer gpa.free(raw);
        if (std.json.parseFromSlice(std.json.Value, gpa, raw, .{})) |parsed_value| {
            var parsed = parsed_value;
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("pi")) |pi_value| if (pi_value == .object) {
                    if (pi_value.object.get("extensions")) |extensions_value| if (extensions_value == .array) {
                        for (extensions_value.array.items) |entry_value| {
                            if (entry_value != .string or entry_value.string.len == 0) continue;
                            const source_path = try std.fs.path.resolve(gpa, &.{ dir_path, entry_value.string });
                            errdefer gpa.free(source_path);
                            const stat = std.Io.Dir.cwd().statFile(io, source_path, .{}) catch {
                                gpa.free(source_path);
                                continue;
                            };
                            if (stat.kind == .file) {
                                try result.items.append(gpa, source_path);
                            } else {
                                gpa.free(source_path);
                            }
                        }
                        if (result.items.items.len > 0) return result;
                    };
                };
            }
        } else |_| {}
    } else |_| {}

    const candidates = [_][]const u8{ "index.ts", "index.js" };
    for (candidates) |candidate| {
        const source_path = try std.fs.path.join(gpa, &.{ dir_path, candidate });
        errdefer gpa.free(source_path);
        const stat = std.Io.Dir.cwd().statFile(io, source_path, .{}) catch {
            gpa.free(source_path);
            continue;
        };
        if (stat.kind == .file) {
            try result.items.append(gpa, source_path);
            return result;
        }
        gpa.free(source_path);
    }
    return result;
}

fn isUpstreamScriptPath(path: []const u8) bool {
    return endsWithAsciiIgnoreCase(path, ".ts") or endsWithAsciiIgnoreCase(path, ".js");
}

fn endsWithAsciiIgnoreCase(input: []const u8, suffix: []const u8) bool {
    if (suffix.len > input.len) return false;
    const tail = input[input.len - suffix.len ..];
    for (tail, suffix) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

fn containsCommand(items: []const ExtensionCommand, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.name, needle)) return true;
    return false;
}

fn containsShortcut(items: []const ExtensionShortcut, needle: []const u8) bool {
    for (items) |item| if (std.ascii.eqlIgnoreCase(item.key, needle)) return true;
    return false;
}

fn containsFlag(items: []const ExtensionFlag, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.name, needle)) return true;
    return false;
}

fn containsTool(items: []const ExtensionTool, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item.name, needle)) return true;
    return false;
}

fn stringifyValue(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

fn parseCommandOutput(gpa: std.mem.Allocator, extension_name: []const u8, invocation: []const u8, raw: []const u8) !CommandOutput {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCommandOutput;
    const message = try parseOptionalOwnedString(gpa, parsed.value.object.get("message"));
    errdefer if (message) |value| gpa.free(value);
    const prompt = try parseOptionalOwnedString(gpa, parsed.value.object.get("prompt"));
    errdefer if (prompt) |value| gpa.free(value);
    const session_name = try parseOptionalOwnedString(gpa, parsed.value.object.get("sessionName"));
    errdefer if (session_name) |value| gpa.free(value);

    var entries: []EntryAction = &.{};
    if (parsed.value.object.get("entries")) |value| entries = try parseEntryActions(gpa, value);
    errdefer freeEntryActions(gpa, entries);

    var labels: []LabelAction = &.{};
    if (parsed.value.object.get("labels")) |value| labels = try parseLabelActions(gpa, value);
    errdefer freeLabelActions(gpa, labels);

    const active_tools = if (parsed.value.object.get("activeTools")) |value|
        try parseOwnedStringArray(gpa, value)
    else
        null;
    errdefer if (active_tools) |tools| freeOwnedStrings(gpa, tools);

    var model = if (parsed.value.object.get("model")) |value|
        try parseModelAction(gpa, value)
    else
        null;
    errdefer if (model) |*action| action.deinit(gpa);

    const thinking_level = try parseOptionalOwnedString(gpa, parsed.value.object.get("thinkingLevel"));
    errdefer if (thinking_level) |value| gpa.free(value);

    const prompt_delivery = if (parsed.value.object.get("promptMode")) |value| blk: {
        if (value != .string) return error.InvalidCommandOutput;
        if (std.mem.eql(u8, value.string, "steer")) break :blk PromptDelivery.steer;
        if (std.mem.eql(u8, value.string, "followUp") or std.mem.eql(u8, value.string, "follow_up")) break :blk PromptDelivery.follow_up;
        if (std.mem.eql(u8, value.string, "nextTurn") or std.mem.eql(u8, value.string, "next_turn")) break :blk PromptDelivery.next_turn;
        return error.InvalidCommandOutput;
    } else .next_turn;

    const abort = try parseOptionalBool(parsed.value.object.get("abort"), false);
    const is_error = try parseOptionalBool(parsed.value.object.get("isError"), false);
    const terminate = try parseOptionalBool(parsed.value.object.get("terminate"), false);
    var action_batch = try actions_mod.Batch.parse(gpa, extension_name, invocation, raw);
    errdefer action_batch.deinit(gpa);
    return .{
        .message = message,
        .prompt = prompt,
        .prompt_delivery = prompt_delivery,
        .session_name = session_name,
        .entries = entries,
        .labels = labels,
        .active_tools = active_tools,
        .model = model,
        .thinking_level = thinking_level,
        .abort = abort,
        .is_error = is_error,
        .terminate = terminate,
        .actions = action_batch,
    };
}

fn parseOptionalOwnedString(gpa: std.mem.Allocator, value: ?std.json.Value) !?[]u8 {
    const present = value orelse return null;
    if (present != .string) return error.InvalidCommandOutput;
    return try gpa.dupe(u8, present.string);
}

fn parseOptionalBool(value: ?std.json.Value, fallback: bool) !bool {
    const present = value orelse return fallback;
    if (present != .bool) return error.InvalidCommandOutput;
    return present.bool;
}

fn freeEntryActions(gpa: std.mem.Allocator, entries: []EntryAction) void {
    for (entries) |*entry| entry.deinit(gpa);
    if (entries.len > 0) gpa.free(entries);
}

fn freeLabelActions(gpa: std.mem.Allocator, labels: []LabelAction) void {
    for (labels) |*label| label.deinit(gpa);
    if (labels.len > 0) gpa.free(labels);
}

fn freeOwnedStrings(gpa: std.mem.Allocator, values: [][]u8) void {
    for (values) |value| gpa.free(value);
    gpa.free(values);
}

fn parseOwnedStringArray(gpa: std.mem.Allocator, value: std.json.Value) ![][]u8 {
    if (value != .array) return error.InvalidCommandOutput;
    var values: std.ArrayList([]u8) = .empty;
    errdefer {
        for (values.items) |item| gpa.free(item);
        values.deinit(gpa);
    }
    for (value.array.items) |item| {
        if (item != .string or item.string.len == 0) return error.InvalidCommandOutput;
        for (values.items) |existing| if (std.mem.eql(u8, existing, item.string)) return error.InvalidCommandOutput;
        try values.append(gpa, try gpa.dupe(u8, item.string));
    }
    return try values.toOwnedSlice(gpa);
}

fn parseLabelActions(gpa: std.mem.Allocator, value: std.json.Value) ![]LabelAction {
    if (value != .array) return error.InvalidCommandOutput;
    var labels: std.ArrayList(LabelAction) = .empty;
    errdefer {
        for (labels.items) |*label| label.deinit(gpa);
        labels.deinit(gpa);
    }
    for (value.array.items) |item| {
        if (item != .object) return error.InvalidCommandOutput;
        const id_value = item.object.get("entryId") orelse return error.InvalidCommandOutput;
        if (id_value != .string or id_value.string.len == 0) return error.InvalidCommandOutput;
        const entry_id = try gpa.dupe(u8, id_value.string);
        errdefer gpa.free(entry_id);
        const label = if (item.object.get("label")) |label_value| blk: {
            if (label_value == .null) break :blk null;
            if (label_value != .string) return error.InvalidCommandOutput;
            break :blk try gpa.dupe(u8, label_value.string);
        } else null;
        errdefer if (label) |owned| gpa.free(owned);
        try labels.append(gpa, .{ .entry_id = entry_id, .label = label });
    }
    return try labels.toOwnedSlice(gpa);
}

fn parseModelAction(gpa: std.mem.Allocator, value: std.json.Value) !?ModelAction {
    if (value == .null) return null;
    if (value == .string) {
        const trimmed = std.mem.trim(u8, value.string, " \t\r\n");
        if (trimmed.len == 0) return error.InvalidCommandOutput;
        if (std.mem.indexOfScalar(u8, trimmed, '/')) |slash| {
            if (slash == 0 or slash + 1 >= trimmed.len) return error.InvalidCommandOutput;
            const provider = try gpa.dupe(u8, trimmed[0..slash]);
            errdefer gpa.free(provider);
            return .{
                .provider = provider,
                .id = try gpa.dupe(u8, trimmed[slash + 1 ..]),
            };
        }
        return .{ .id = try gpa.dupe(u8, trimmed) };
    }
    if (value != .object) return error.InvalidCommandOutput;
    const id_value = value.object.get("id") orelse value.object.get("modelId") orelse return error.InvalidCommandOutput;
    if (id_value != .string or id_value.string.len == 0) return error.InvalidCommandOutput;
    const provider = if (value.object.get("provider")) |provider_value| blk: {
        if (provider_value == .null) break :blk null;
        if (provider_value != .string or provider_value.string.len == 0) return error.InvalidCommandOutput;
        break :blk try gpa.dupe(u8, provider_value.string);
    } else null;
    errdefer if (provider) |owned| gpa.free(owned);
    return .{ .provider = provider, .id = try gpa.dupe(u8, id_value.string) };
}

fn parseEntryActions(gpa: std.mem.Allocator, value: std.json.Value) ![]EntryAction {
    if (value != .array) return error.InvalidCommandOutput;
    var entries: std.ArrayList(EntryAction) = .empty;
    errdefer {
        for (entries.items) |*entry| entry.deinit(gpa);
        entries.deinit(gpa);
    }
    for (value.array.items) |item| {
        if (item != .object) return error.InvalidCommandOutput;
        const type_value = item.object.get("type") orelse return error.InvalidCommandOutput;
        if (type_value != .string or type_value.string.len == 0) return error.InvalidCommandOutput;
        const custom_type = try gpa.dupe(u8, type_value.string);
        errdefer gpa.free(custom_type);
        const data_json = if (item.object.get("data")) |data| try stringifyValue(gpa, data) else null;
        errdefer if (data_json) |owned| gpa.free(owned);
        try entries.append(gpa, .{ .custom_type = custom_type, .data_json = data_json });
    }
    return try entries.toOwnedSlice(gpa);
}

fn errorCommandOutput(gpa: std.mem.Allocator, message: []const u8) !CommandOutput {
    return .{ .message = try gpa.dupe(u8, message), .is_error = true };
}

fn errorCommandOutputFmt(gpa: std.mem.Allocator, comptime format: []const u8, args: anytype) !CommandOutput {
    return .{ .message = try std.fmt.allocPrint(gpa, format, args), .is_error = true };
}

const LiveUpdateAdapter = struct {
    host: *Host,
    callback: ToolUpdateFn,
    context: ?*anyopaque,
    captured: *std.ArrayList(ToolUpdate),

    fn forward(raw_ctx: ?*anyopaque, raw_json: []const u8) anyerror!void {
        const self: *LiveUpdateAdapter = @ptrCast(@alignCast(raw_ctx.?));
        var parsed = try std.json.parseFromSlice(std.json.Value, self.host.gpa, raw_json, .{});
        defer parsed.deinit();
        var update = try parseToolUpdate(self.host.gpa, parsed.value);
        errdefer update.deinit(self.host.gpa);
        update.observer_deferred = true;
        try self.callback(self.context, &update);
        try self.captured.append(self.host.gpa, update);
    }
};

fn parseToolImages(gpa: std.mem.Allocator, value: ?std.json.Value) ![]ToolImage {
    const raw = value orelse return &.{};
    if (raw == .null) return &.{};
    if (raw != .array or raw.array.items.len > 64) return error.InvalidToolOutput;
    var images: std.ArrayList(ToolImage) = .empty;
    errdefer {
        for (images.items) |*image| image.deinit(gpa);
        images.deinit(gpa);
    }
    for (raw.array.items) |item| {
        if (item != .object) return error.InvalidToolOutput;
        const data_value = item.object.get("dataBase64") orelse item.object.get("data") orelse item.object.get("base64") orelse return error.InvalidToolOutput;
        if (data_value != .string or data_value.string.len == 0) return error.InvalidToolOutput;
        const mime_value = item.object.get("mimeType") orelse item.object.get("mime") orelse item.object.get("mime_type");
        if (mime_value) |mime| if (mime != .string or mime.string.len == 0) return error.InvalidToolOutput;
        const data_b64 = try gpa.dupe(u8, data_value.string);
        errdefer gpa.free(data_b64);
        const mime_type = try gpa.dupe(u8, if (mime_value) |mime| mime.string else "image/png");
        errdefer gpa.free(mime_type);
        try images.append(gpa, .{ .data_b64 = data_b64, .mime_type = mime_type });
    }
    return try images.toOwnedSlice(gpa);
}

fn parseToolOutput(gpa: std.mem.Allocator, extension_name: []const u8, invocation: []const u8, raw: []const u8) !ToolOutput {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidToolOutput;
    const content_value = parsed.value.object.get("content") orelse return error.InvalidToolOutput;
    if (content_value != .string) return error.InvalidToolOutput;
    const is_error = if (parsed.value.object.get("isError")) |value| blk: {
        if (value != .bool) return error.InvalidToolOutput;
        break :blk value.bool;
    } else false;
    const image_b64 = if (parsed.value.object.get("imageBase64")) |value| blk: {
        if (value != .string) return error.InvalidToolOutput;
        break :blk try gpa.dupe(u8, value.string);
    } else null;
    errdefer if (image_b64) |v| gpa.free(v);
    const image_mime = if (parsed.value.object.get("imageMime")) |value| blk: {
        if (value != .string) return error.InvalidToolOutput;
        break :blk try gpa.dupe(u8, value.string);
    } else null;
    errdefer if (image_mime) |v| gpa.free(v);
    const images = try parseToolImages(gpa, parsed.value.object.get("images"));
    errdefer deinitToolImages(gpa, images);
    const details_json = if (parsed.value.object.get("details")) |value| blk: {
        if (value == .null) break :blk null;
        break :blk try stringifyValue(gpa, value);
    } else null;
    errdefer if (details_json) |v| gpa.free(v);
    const usage = try parseToolUsage(parsed.value.object.get("usage"));
    const added_tool_names = try parseOwnedStringList(gpa, parsed.value.object.get("addedToolNames"));
    errdefer deinitStringList(gpa, added_tool_names);
    const updates: []ToolUpdate = if (parsed.value.object.get("updates")) |value| blk: {
        if (value != .array or value.array.items.len > 4096) return error.InvalidToolOutput;
        var list: std.ArrayList(ToolUpdate) = .empty;
        errdefer {
            for (list.items) |*update| update.deinit(gpa);
            list.deinit(gpa);
        }
        for (value.array.items) |item| try list.append(gpa, try parseToolUpdate(gpa, item));
        break :blk try list.toOwnedSlice(gpa);
    } else &.{};
    errdefer {
        for (updates) |*update| update.deinit(gpa);
        if (updates.len > 0) gpa.free(updates);
    }
    const terminate = if (parsed.value.object.get("terminate")) |value| blk: {
        if (value != .bool) return error.InvalidToolOutput;
        break :blk value.bool;
    } else false;
    const delegate_builtin = if (parsed.value.object.get("delegateBuiltin")) |value| blk: {
        if (value != .bool) return error.InvalidToolOutput;
        break :blk value.bool;
    } else false;
    var action_batch = try actions_mod.Batch.parse(gpa, extension_name, invocation, raw);
    errdefer action_batch.deinit(gpa);
    return .{
        .content = try gpa.dupe(u8, content_value.string),
        .is_error = is_error,
        .image_b64 = image_b64,
        .image_mime = image_mime,
        .images = images,
        .details_json = details_json,
        .usage = usage,
        .added_tool_names = added_tool_names,
        .updates = updates,
        .delegate_builtin = delegate_builtin,
        .terminate = terminate,
        .actions = action_batch,
    };
}

fn parseToolUpdate(gpa: std.mem.Allocator, value: std.json.Value) !ToolUpdate {
    if (value != .object) return error.InvalidToolOutput;
    const content_value = value.object.get("content") orelse return error.InvalidToolOutput;
    if (content_value != .string) return error.InvalidToolOutput;
    const content = try gpa.dupe(u8, content_value.string);
    errdefer gpa.free(content);
    const image_b64 = if (value.object.get("imageBase64")) |item| blk: {
        if (item != .string) return error.InvalidToolOutput;
        break :blk try gpa.dupe(u8, item.string);
    } else null;
    errdefer if (image_b64) |v| gpa.free(v);
    const image_mime = if (value.object.get("imageMime")) |item| blk: {
        if (item != .string) return error.InvalidToolOutput;
        break :blk try gpa.dupe(u8, item.string);
    } else null;
    errdefer if (image_mime) |v| gpa.free(v);
    const images = try parseToolImages(gpa, value.object.get("images"));
    errdefer deinitToolImages(gpa, images);
    const details_json = if (value.object.get("details")) |item| blk: {
        if (item == .null) break :blk null;
        break :blk try stringifyValue(gpa, item);
    } else null;
    errdefer if (details_json) |v| gpa.free(v);
    const usage = try parseToolUsage(value.object.get("usage"));
    const added_tool_names = try parseOwnedStringList(gpa, value.object.get("addedToolNames"));
    errdefer deinitStringList(gpa, added_tool_names);
    const is_error = if (value.object.get("isError")) |item| blk: {
        if (item != .bool) return error.InvalidToolOutput;
        break :blk item.bool;
    } else false;
    return .{
        .content = content,
        .is_error = is_error,
        .image_b64 = image_b64,
        .image_mime = image_mime,
        .images = images,
        .details_json = details_json,
        .usage = usage,
        .added_tool_names = added_tool_names,
    };
}

fn parseToolUsage(value: ?std.json.Value) !?ToolUsage {
    const raw = value orelse return null;
    if (raw == .null) return null;
    if (raw != .object) return error.InvalidToolOutput;
    var usage: ToolUsage = .{
        .input = try objectU64(&raw.object, "input"),
        .output = try objectU64(&raw.object, "output"),
        .cache_read = try objectU64(&raw.object, "cacheRead"),
        .cache_write = try objectU64(&raw.object, "cacheWrite"),
        .cache_write_1h = try objectOptionalU64(&raw.object, "cacheWrite1h"),
        .reasoning = try objectOptionalU64(&raw.object, "reasoning"),
        .total_tokens = try objectU64(&raw.object, "totalTokens"),
    };
    if (raw.object.get("cost")) |cost_value| {
        if (cost_value != .object) return error.InvalidToolOutput;
        usage.cost = .{
            .input = try objectF64(&cost_value.object, "input"),
            .output = try objectF64(&cost_value.object, "output"),
            .cache_read = try objectF64(&cost_value.object, "cacheRead"),
            .cache_write = try objectF64(&cost_value.object, "cacheWrite"),
            .total = try objectF64(&cost_value.object, "total"),
        };
    }
    return usage;
}

fn objectU64(object: *const std.json.ObjectMap, key: []const u8) !u64 {
    return (try objectOptionalU64(object, key)) orelse 0;
}

fn objectOptionalU64(object: *const std.json.ObjectMap, key: []const u8) !?u64 {
    const value = object.get(key) orelse return null;
    if (value == .null) return null;
    if (value != .integer or value.integer < 0) return error.InvalidToolOutput;
    return @intCast(value.integer);
}

fn objectF64(object: *const std.json.ObjectMap, key: []const u8) !f64 {
    const value = object.get(key) orelse return 0;
    const number: f64 = switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        else => return error.InvalidToolOutput,
    };
    if (!std.math.isFinite(number) or number < 0) return error.InvalidToolOutput;
    return number;
}

fn parseOwnedStringList(gpa: std.mem.Allocator, value: ?std.json.Value) ![]const []const u8 {
    const raw = value orelse return &.{};
    if (raw == .null) return &.{};
    if (raw != .array or raw.array.items.len > 4096) return error.InvalidToolOutput;
    if (raw.array.items.len == 0) return &.{};
    const out = try gpa.alloc([]const u8, raw.array.items.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |item| gpa.free(item);
        gpa.free(out);
    }
    for (raw.array.items, 0..) |item, index| {
        if (item != .string or item.string.len == 0) return error.InvalidToolOutput;
        out[index] = try gpa.dupe(u8, item.string);
        initialized += 1;
    }
    return out;
}

fn deinitStringList(gpa: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| gpa.free(value);
    gpa.free(values);
}

fn errorToolOutput(gpa: std.mem.Allocator, message: []const u8) !ToolOutput {
    return .{ .content = try gpa.dupe(u8, message), .is_error = true };
}

fn errorToolOutputFmt(gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !ToolOutput {
    return .{ .content = try std.fmt.allocPrint(gpa, fmt, args), .is_error = true };
}

fn findTool(items: []const ExtensionTool, name: []const u8) ?*const ExtensionTool {
    for (items) |*tool| if (std.mem.eql(u8, tool.name, name)) return tool;
    return null;
}

fn parseRenderedLines(gpa: std.mem.Allocator, raw: []const u8) !?[]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidJavaScriptRendererResponse;
    const found_value = parsed.value.object.get("found") orelse return error.InvalidJavaScriptRendererResponse;
    if (found_value != .bool) return error.InvalidJavaScriptRendererResponse;
    if (!found_value.bool) return null;
    const lines_value = parsed.value.object.get("lines") orelse return error.InvalidJavaScriptRendererResponse;
    if (lines_value != .array or lines_value.array.items.len > 16_384) return error.InvalidJavaScriptRendererResponse;

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    for (lines_value.array.items, 0..) |line, index| {
        if (line != .string) return error.InvalidJavaScriptRendererResponse;
        if (index > 0) try out.writer.writeByte('\n');
        try out.writer.writeAll(line.string);
        if (out.written().len > 4 * 1024 * 1024) return error.JavaScriptRendererOutputTooLarge;
    }
    return try out.toOwnedSlice();
}

fn parseTransformedMarkdown(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidJavaScriptRendererResponse;
    const value = parsed.value.object.get("markdown") orelse return error.InvalidJavaScriptRendererResponse;
    if (value != .string or value.string.len > 4 * 1024 * 1024) return error.InvalidJavaScriptRendererResponse;
    return try gpa.dupe(u8, value.string);
}

fn optionalBoolean(object: std.json.ObjectMap, key: []const u8, default: bool) !bool {
    const value = object.get(key) orelse return default;
    if (value != .bool) return error.InvalidManifest;
    return value.bool;
}

fn parseUniqueStringArray(
    gpa: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
    output: *std.ArrayList([]const u8),
) !void {
    const value = object.get(key) orelse return;
    if (value != .array) return error.InvalidManifest;
    for (value.array.items) |item| {
        if (item != .string or item.string.len == 0) return error.InvalidManifest;
        if (!containsString(output.items, item.string)) try output.append(gpa, try gpa.dupe(u8, item.string));
    }
}

fn containsString(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, needle)) return true;
    return false;
}

fn validateObjectJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidHookJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidHookJson;
}

fn validateJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidHookJson;
    defer parsed.deinit();
}

test "load extension manifest and record hook" {
    const gpa = std.testing.allocator;
    var host = Host{ .gpa = gpa, .io = std.testing.io };
    defer host.deinit();
    try host.loadJson(
        \\{"name":"demo","version":"1.0.0","hooks":["before_prompt","after_tool","before_prompt"],"entry":"plugin"}
    , "/ext/demo");
    try std.testing.expectEqual(@as(usize, 1), host.extensions.items.len);
    try std.testing.expectEqual(@as(usize, 2), host.extensions.items[0].hooks.len);
    try std.testing.expect(host.hasHook("before_prompt"));
    try host.emit("before_prompt", "{\"text\":\"hi\"}");
    try std.testing.expect(std.mem.indexOf(u8, host.last_hook, "before_prompt") != null);
}

test "extension manifests retain declarative provider registrations" {
    const gpa = std.testing.allocator;
    var host = Host{ .gpa = gpa, .io = std.testing.io };
    defer host.deinit();
    try host.loadJson(
        \\{"name":"provider-demo","providers":[{"name":"corp","config":{"name":"Corp","baseUrl":"https://corp.example/v1","api":"openai-completions","apiKey":"secret","models":[{"id":"fast","contextWindow":1000,"maxTokens":100}]}}]}
    , ".");
    try std.testing.expectEqual(@as(usize, 1), host.extensions.items.len);
    try std.testing.expectEqual(@as(usize, 1), host.extensions.items[0].providers.len);
    const registration = host.extensions.items[0].providers[0];
    try std.testing.expectEqualStrings("corp", registration.name);
    try std.testing.expect(std.mem.indexOf(u8, registration.config_json, "\"baseUrl\":\"https://corp.example/v1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, registration.config_json, "\"id\":\"fast\"") != null);
    try std.testing.expectError(
        error.DuplicateProviderName,
        host.loadJson(
            \\{"name":"duplicate","providers":[{"name":"corp","config":{}},{"name":"CORP","config":{}}]}
        , "."),
    );
}

test "extension discovery is trust gated" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    const global = try std.fs.path.join(gpa, &.{ agent, "extensions", "global" });
    defer gpa.free(global);
    try std.Io.Dir.cwd().createDirPath(io, global);
    const global_manifest = try std.fs.path.join(gpa, &.{ global, "extension.json" });
    defer gpa.free(global_manifest);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = global_manifest, .data = "{\"name\":\"global\",\"hooks\":[\"before_prompt\"]}" });
    const project = try std.fs.path.join(gpa, &.{ root, ".pi", "extensions", "project" });
    defer gpa.free(project);
    try std.Io.Dir.cwd().createDirPath(io, project);
    const project_manifest = try std.fs.path.join(gpa, &.{ project, "extension.json" });
    defer gpa.free(project_manifest);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = project_manifest, .data = "{\"name\":\"project\",\"hooks\":[\"before_prompt\"]}" });

    var untrusted = Host{ .gpa = gpa, .io = io };
    defer untrusted.deinit();
    try untrusted.discover(root, agent, false);
    try std.testing.expectEqual(@as(usize, 1), untrusted.extensions.items.len);
    try std.testing.expectEqualStrings("global", untrusted.extensions.items[0].name);

    var trusted = Host{ .gpa = gpa, .io = io };
    defer trusted.deinit();
    try trusted.discover(root, agent, true);
    try std.testing.expectEqual(@as(usize, 2), trusted.extensions.items.len);
}

test "extension executable hook returns JSON and failures are isolated" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "good.sh", .data =
        \\#!/bin/sh
        \\printf '{"hook":"%s","payload":%s}\n' "$2" "$3"
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "good.sh");
    try tmp.dir.writeFile(io, .{ .sub_path = "bad.sh", .data = "#!/bin/sh\nexit 7\n" });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "bad.sh");
    const good = try tmp.dir.realPathFileAlloc(io, "good.sh", gpa);
    defer gpa.free(good);
    const bad = try tmp.dir.realPathFileAlloc(io, "bad.sh", gpa);
    defer gpa.free(bad);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const good_json = try std.fmt.allocPrint(gpa, "{{\"name\":\"good\",\"hooks\":[\"before_prompt\"],\"entry\":\"{s}\"}}", .{good});
    defer gpa.free(good_json);
    const bad_json = try std.fmt.allocPrint(gpa, "{{\"name\":\"bad\",\"hooks\":[\"before_prompt\"],\"entry\":\"{s}\"}}", .{bad});
    defer gpa.free(bad_json);
    try host.loadJson(good_json, ".");
    try host.loadJson(bad_json, ".");
    var result = try host.executeHook("before_prompt", "{\"text\":\"hi\"}");
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), result.responses.len);
    try std.testing.expectEqual(@as(usize, 1), result.errors.len);
    try std.testing.expectEqualStrings("good", result.responses[0].extension_name);
    try std.testing.expect(std.mem.indexOf(u8, result.responses[0].json, "before_prompt") != null);
    try std.testing.expectEqualStrings("bad", result.errors[0].extension_name);
}

test "extension manifest declares tools and executes them" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "tool.sh", .data =
        \\#!/bin/sh
        \\if [ "$1" = "--pi-tool" ]; then printf '%s\n' '{"content":"extension-ok","isError":false}'; fi
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "tool.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "tool.sh", gpa);
    defer gpa.free(entry);
    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(gpa, "{{\"name\":\"tools\",\"entry\":\"{s}\",\"tools\":[{{\"name\":\"hello_ext\",\"description\":\"Hello\",\"parameters\":{{\"type\":\"object\",\"properties\":{{}}}}}}]}}", .{entry});
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    try std.testing.expect(host.hasTool("hello_ext"));
    var output = (try host.executeTool("hello_ext", "{}")).?;
    defer output.deinit(gpa);
    try std.testing.expectEqualStrings("extension-ok", output.content);
    try std.testing.expect(!output.is_error);
}

test "duplicate extension tool names are rejected" {
    const gpa = std.testing.allocator;
    var host = Host{ .gpa = gpa, .io = std.testing.io };
    defer host.deinit();
    try host.loadJson("{\"name\":\"a\",\"tools\":[{\"name\":\"same\"}]}", ".");
    try std.testing.expectError(error.DuplicateToolName, host.loadJson("{\"name\":\"b\",\"tools\":[{\"name\":\"same\"}]}", "."));
}

test "explicit extension paths load directories and manifest files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "one");
    try tmp.dir.writeFile(io, .{ .sub_path = "one/extension.json", .data = "{\"name\":\"one\"}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "two.json", .data = "{\"name\":\"two\"}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "not-an-extension.sh", .data = "#!/bin/sh\n" });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const one = try std.fs.path.join(gpa, &.{ root, "one" });
    defer gpa.free(one);
    const two = try std.fs.path.join(gpa, &.{ root, "two.json" });
    defer gpa.free(two);
    const unsupported = try std.fs.path.join(gpa, &.{ root, "not-an-extension.sh" });
    defer gpa.free(unsupported);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(one);
    try host.loadPath(two);
    try std.testing.expectEqual(@as(usize, 2), host.extensions.items.len);
    try std.testing.expectEqualStrings("one", host.extensions.items[0].name);
    try std.testing.expectEqualStrings("two", host.extensions.items[1].name);
    try std.testing.expectError(error.UnsupportedExtensionPath, host.loadPath(unsupported));
}

test "explicit empty extension directory is a valid no-op source" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "empty");
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const empty = try std.fs.path.join(gpa, &.{ root, "empty" });
    defer gpa.free(empty);
    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(empty);
    try std.testing.expectEqual(@as(usize, 0), host.extensions.items.len);
}

test "extension flags validate defaults and command-line overrides" {
    const gpa = std.testing.allocator;
    var host = Host{ .gpa = gpa, .io = std.testing.io };
    defer host.deinit();
    try host.loadJson(
        \\{"name":"flags","flags":[
        \\  {"name":"plan","type":"boolean","description":"Plan first","default":false},
        \\  {"name":"workspace","type":"string","default":"src"}
        \\]}
    , ".");
    try host.applyCliFlag("plan", null);
    try host.applyCliFlag("workspace", "tests");
    const ext = &host.extensions.items[0];
    const json = try host.flagsJson(ext);
    defer gpa.free(json);
    try std.testing.expectEqualStrings("{\"plan\":true,\"workspace\":\"tests\"}", json);
    try std.testing.expectError(error.UnknownExtensionFlag, host.applyCliFlag("missing", null));
}

test "string extension flag requires a value and duplicate names fail" {
    const gpa = std.testing.allocator;
    var host = Host{ .gpa = gpa, .io = std.testing.io };
    defer host.deinit();
    try host.loadJson("{\"name\":\"one\",\"flags\":[{\"name\":\"mode\",\"type\":\"string\"}]}", ".");
    try std.testing.expectError(error.ExtensionFlagRequiresValue, host.applyCliFlag("mode", null));
    try std.testing.expectError(error.DuplicateFlagName, host.loadJson("{\"name\":\"two\",\"flags\":[{\"name\":\"mode\",\"type\":\"boolean\"}]}", "."));
}

test "hook receives extension-local flag JSON as final argument" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "flags.sh", .data =
        \\#!/bin/sh
        \\printf '{"flags":%s}\n' "$4"
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "flags.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "flags.sh", gpa);
    defer gpa.free(entry);
    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(gpa, "{{\"name\":\"flag-hook\",\"hooks\":[\"before_prompt\"],\"entry\":\"{s}\",\"flags\":[{{\"name\":\"plan\",\"type\":\"boolean\"}}]}}", .{entry});
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    try host.applyCliFlag("plan", null);
    var emitted = try host.executeHook("before_prompt", "{}");
    defer emitted.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), emitted.responses.len);
    try std.testing.expectEqualStrings("{\"flags\":{\"plan\":true}}", emitted.responses[0].json);
}

test "extension commands execute with raw arguments and scoped flags" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "command.sh", .data =
        \\#!/bin/sh
        \\printf '{"message":"command:%s","prompt":"agent:%s:%s","terminate":false}\n' "$2" "$2" "$3"
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "command.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "command.sh", gpa);
    defer gpa.free(entry);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const manifest = try std.fmt.allocPrint(
        gpa,
        "{{\"name\":\"commands\",\"entry\":\"{s}\",\"commands\":[{{\"name\":\"review\",\"description\":\"Review files\",\"argumentHint\":\"<path>\"}}],\"flags\":[{{\"name\":\"plan\",\"type\":\"boolean\"}}]}}",
        .{entry},
    );
    defer gpa.free(manifest);
    try host.loadJson(manifest, ".");
    try host.applyCliFlag("plan", null);
    try std.testing.expect(host.hasCommand("review"));
    var output = (try host.executeCommand("review", "src/main.zig extra")).?;
    defer output.deinit(gpa);
    try std.testing.expectEqualStrings("command:review", output.message.?);
    try std.testing.expectEqualStrings("agent:review:src/main.zig extra", output.prompt.?);
    try std.testing.expect(!output.is_error);
    try std.testing.expect((try host.executeCommand("missing", "")) == null);
}

test "extension shortcuts register and later extensions take precedence" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "shortcut.sh", .data =
        \\#!/bin/sh
        \\case "$4" in *'"enabled":true'*) state=enabled ;; *) state=disabled ;; esac
        \\printf '{"message":"shortcut:%s:%s"}\n' "$2" "$state"
    });
    try file_permissions.setOwnerExecutable(tmp.dir, io, "shortcut.sh");
    const entry = try tmp.dir.realPathFileAlloc(io, "shortcut.sh", gpa);
    defer gpa.free(entry);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    const first = try std.fmt.allocPrint(
        gpa,
        "{{\"name\":\"first\",\"entry\":\"{s}\",\"shortcuts\":[{{\"key\":\"ctrl+shift+u\",\"description\":\"first\"}}]}}",
        .{entry},
    );
    defer gpa.free(first);
    const second = try std.fmt.allocPrint(
        gpa,
        "{{\"name\":\"second\",\"entry\":\"{s}\",\"shortcuts\":[{{\"key\":\"CTRL+SHIFT+U\",\"description\":\"second\"}}],\"flags\":[{{\"name\":\"enabled\",\"type\":\"boolean\",\"default\":true}}]}}",
        .{entry},
    );
    defer gpa.free(second);
    try host.loadJson(first, ".");
    try host.loadJson(second, ".");
    try std.testing.expect(host.hasShortcut("ctrl+shift+u"));
    var output = (try host.executeShortcut("ctrl+shift+u")).?;
    defer output.deinit(gpa);
    try std.testing.expectEqualStrings("shortcut:ctrl+shift+u:enabled", output.message.?);
    try std.testing.expectError(error.DuplicateShortcutKey, host.loadJson(
        "{\"name\":\"bad\",\"shortcuts\":[{\"key\":\"ctrl+x\"},{\"key\":\"CTRL+X\"}]}",
        ".",
    ));
}

test "extension command names are unique and command output is validated" {
    const gpa = std.testing.allocator;
    var host = Host{ .gpa = gpa, .io = std.testing.io };
    defer host.deinit();
    try host.loadJson("{\"name\":\"one\",\"commands\":[{\"name\":\"inspect\"}]}", ".");
    try std.testing.expectError(error.DuplicateCommandName, host.loadJson("{\"name\":\"two\",\"commands\":[{\"name\":\"inspect\"}]}", "."));

    var parsed = try parseCommandOutput(gpa, "test", "command", "{\"message\":\"done\",\"prompt\":\"continue\",\"promptMode\":\"followUp\",\"sessionName\":\"renamed\",\"entries\":[{\"type\":\"bookmark\",\"data\":{\"line\":7}}],\"labels\":[{\"entryId\":\"m1\",\"label\":\"saved\"},{\"entryId\":\"m2\",\"label\":null}],\"activeTools\":[\"read\",\"review\"],\"model\":{\"provider\":\"openai\",\"id\":\"gpt-test\"},\"thinkingLevel\":\"high\",\"abort\":true,\"isError\":true,\"terminate\":true}");
    defer parsed.deinit(gpa);
    try std.testing.expectEqualStrings("done", parsed.message.?);
    try std.testing.expect(parsed.is_error);
    try std.testing.expect(parsed.terminate);
    try std.testing.expectEqualStrings("renamed", parsed.session_name.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.entries.len);
    try std.testing.expectEqualStrings("bookmark", parsed.entries[0].custom_type);
    try std.testing.expectEqualStrings("{\"line\":7}", parsed.entries[0].data_json.?);
    try std.testing.expectEqualStrings("continue", parsed.prompt.?);
    try std.testing.expectEqual(PromptDelivery.follow_up, parsed.prompt_delivery);
    try std.testing.expectEqual(@as(usize, 2), parsed.labels.len);
    try std.testing.expectEqualStrings("saved", parsed.labels[0].label.?);
    try std.testing.expect(parsed.labels[1].label == null);
    try std.testing.expectEqual(@as(usize, 2), parsed.active_tools.?.len);
    try std.testing.expectEqualStrings("openai", parsed.model.?.provider.?);
    try std.testing.expectEqualStrings("gpt-test", parsed.model.?.id);
    try std.testing.expectEqualStrings("high", parsed.thinking_level.?);
    try std.testing.expect(parsed.abort);
    try std.testing.expectError(error.InvalidCommandOutput, parseCommandOutput(gpa, "test", "command", "{\"message\":1}"));
    try std.testing.expectError(error.InvalidCommandOutput, parseCommandOutput(gpa, "test", "command", "{\"entries\":[{\"type\":\"\"}]}"));
    try std.testing.expectError(error.InvalidCommandOutput, parseCommandOutput(gpa, "test", "command", "{\"labels\":[{\"entryId\":1}]}"));
    try std.testing.expectError(error.InvalidCommandOutput, parseCommandOutput(gpa, "test", "command", "{\"activeTools\":[\"read\",\"read\"]}"));
    try std.testing.expectError(error.InvalidCommandOutput, parseCommandOutput(gpa, "test", "command", "{\"model\":{\"provider\":\"openai\"}}"));
    try std.testing.expectError(error.InvalidCommandOutput, parseCommandOutput(gpa, "test", "command", "{\"promptMode\":\"later\"}"));
}

test "JavaScript package manifest declares multiple extension entries ahead of index" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!jsRuntimeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "package");
    const one =
        \\export default function(pi) { pi.registerCommand('pkg_one', { description: 'one', handler: async () => ({ message: 'one' }) }); }
    ;
    const two =
        \\export default function(pi) { pi.registerCommand('pkg_two', { description: 'two', handler: async () => ({ message: 'two' }) }); }
    ;
    const ignored =
        \\export default function(pi) { pi.registerCommand('from_index', { handler: async () => ({ message: 'index' }) }); }
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "package/one.ts", .data = one });
    try tmp.dir.writeFile(io, .{ .sub_path = "package/two.js", .data = two });
    try tmp.dir.writeFile(io, .{ .sub_path = "package/index.ts", .data = ignored });
    try tmp.dir.writeFile(io, .{ .sub_path = "package/package.json", .data =
        \\{"name":"pkg","pi":{"extensions":["./one.ts","./missing.ts","./two.js"]}}
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const package_path = try std.fs.path.join(gpa, &.{ path_buf[0..n], "package" });
    defer gpa.free(package_path);
    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(package_path);
    try std.testing.expectEqual(@as(usize, 2), host.extensions.items.len);
    try std.testing.expect(host.hasCommand("pkg_one"));
    try std.testing.expect(host.hasCommand("pkg_two"));
    try std.testing.expect(!host.hasCommand("from_index"));

    var output = (try host.executeCommand("pkg_two", "")).?;
    defer output.deinit(gpa);
    try std.testing.expectEqualStrings("two", output.message.?);
}

test "explicit extension directory scans direct scripts and one-level packages" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!jsRuntimeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "extensions/nested");
    try tmp.dir.createDirPath(io, "extensions/deeper/ignored");
    const direct =
        \\export default function(pi) { pi.registerCommand('direct_cmd', { handler: async () => ({ message: 'direct' }) }); }
    ;
    const nested =
        \\export default function(pi) { pi.registerCommand('nested_cmd', { handler: async () => ({ message: 'nested' }) }); }
    ;
    const ignored =
        \\export default function(pi) { pi.registerCommand('too_deep', { handler: async () => ({ message: 'bad' }) }); }
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "extensions/direct.ts", .data = direct });
    try tmp.dir.writeFile(io, .{ .sub_path = "extensions/nested/index.js", .data = nested });
    try tmp.dir.writeFile(io, .{ .sub_path = "extensions/deeper/ignored/index.ts", .data = ignored });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const extensions_path = try std.fs.path.join(gpa, &.{ path_buf[0..n], "extensions" });
    defer gpa.free(extensions_path);
    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(extensions_path);
    try std.testing.expect(host.hasCommand("direct_cmd"));
    try std.testing.expect(host.hasCommand("nested_cmd"));
    try std.testing.expect(!host.hasCommand("too_deep"));
}

test "JavaScript renderers retain original component and tool state semantics" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!jsRuntimeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { Type } from '@earendil-works/pi-ai';
        \\import { Box, Text } from '@earendil-works/pi-tui';
        \\export default function(pi) {
        \\  pi.registerMessageRenderer('status-update', (message, { expanded, outputPad }, theme) => {
        \\    const box = new Box(outputPad, 0, (line) => theme.bg('customMessageBg', line));
        \\    box.addChild(new Text(`${theme.bold('MESSAGE')}|${message.content}|${expanded}|${outputPad}`));
        \\    return box;
        \\  });
        \\  pi.registerEntryRenderer('status-card', (entry, { expanded }, theme) => {
        \\    const box = new Box(0, 0);
        \\    box.addChild(new Text(`${theme.fg('accent', 'ENTRY')}|${entry.data.message}|${expanded}`));
        \\    return box;
        \\  });
        \\  pi.registerMarkdownTransformer((markdown, options) => `[${options.messageType}:${options.isStreaming}:${options.availableWidth}] ${markdown}`);
        \\  pi.registerTool({
        \\    name: 'paint', label: 'Paint', description: 'Paint a value',
        \\    parameters: Type.Object({ value: Type.String() }), renderShell: 'self',
        \\    async execute(_id, params) { return { content: [{ type: 'text', text: `done:${params.value}` }], details: {} }; },
        \\    renderCall(args, _theme, context) {
        \\      context.state.value = args.value;
        \\      return new Text(`CALL|${args.value}|${context.toolCallId}|${context.executionStarted}`);
        \\    },
        \\    renderResult(result, { expanded, isPartial }, _theme, context) {
        \\      return new Text(`RESULT|${context.state.value}|${result.content[0].text}|${expanded}|${isPartial}`);
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "renderers.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "renderers.ts" });
    defer gpa.free(path);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(path);
    try std.testing.expectEqual(@as(usize, 1), host.extensions.items.len);
    const ext = host.extensions.items[0];
    try std.testing.expect(containsString(ext.message_renderers, "status-update"));
    try std.testing.expect(containsString(ext.entry_renderers, "status-card"));
    try std.testing.expect(ext.has_markdown_transformer);
    const tool = findTool(ext.tools, "paint") orelse return error.TestExpectedEqual;
    try std.testing.expect(tool.has_render_call);
    try std.testing.expect(tool.has_render_result);
    try std.testing.expect(tool.render_shell_self);

    const message = (try host.renderMessage(
        "status-update",
        "{\"role\":\"custom\",\"customType\":\"status-update\",\"content\":\"ready\"}",
        true,
        2,
        72,
    )).?;
    defer gpa.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "MESSAGE") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "|ready|true|2") != null);

    const entry = (try host.renderEntry(
        "status-card",
        "{\"type\":\"custom\",\"customType\":\"status-card\",\"data\":{\"message\":\"saved\"}}",
        false,
        72,
    )).?;
    defer gpa.free(entry);
    try std.testing.expect(std.mem.indexOf(u8, entry, "ENTRY") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry, "|saved|false") != null);

    const markdown = try host.transformMarkdown("hello", "assistant", true, 67);
    defer gpa.free(markdown);
    try std.testing.expectEqualStrings("[assistant:true:67] hello", markdown);

    const call = (try host.renderToolCall("paint", "tool-17", "{\"value\":\"blue\"}", false, 72)).?;
    defer gpa.free(call);
    try std.testing.expectEqualStrings("CALL|blue|tool-17|true", call);

    const result = (try host.renderToolResult("paint", "tool-17", "done:blue", false, true, false, 72)).?;
    defer gpa.free(result);
    try std.testing.expectEqualStrings("RESULT|blue|done:blue|true|false", result);

    try std.testing.expect((try host.renderMessage("unowned", "{}", false, 0, 72)) == null);
    try std.testing.expectError(error.InvalidMarkdownMessageType, host.transformMarkdown("x", "tool", false, 72));
}

fn jsRuntimeAvailable(gpa: std.mem.Allocator, io: Io) bool {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ "node", "--version" },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch return false;
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    return switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "JavaScript tools retain ordered partial updates details and images" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!jsRuntimeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { Type } from '@earendil-works/pi-ai';
        \\import { Text } from '@earendil-works/pi-tui';
        \\export default function(pi) {
        \\  pi.registerTool({
        \\    name: 'stream-rich', label: 'Stream rich', description: 'stream',
        \\    parameters: Type.Object({ value: Type.String() }),
        \\    async execute(_id, params, _signal, onUpdate) {
        \\      onUpdate({
        \\        content: [{ type: 'text', text: `phase:${params.value}` }], details: { phase: 1 },
        \\        usage: { input: 1, output: 2, cacheRead: 3, cacheWrite: 4, cacheWrite1h: 1, reasoning: 2, totalTokens: 10, cost: { input: 0.1, output: 0.2, cacheRead: 0.3, cacheWrite: 0.4, total: 1 } },
        \\        addedToolNames: ['partial_tool'],
        \\      });
        \\      onUpdate({ content: [{ type: 'image', data: 'aGVsbG8=', mimeType: 'image/png' }, { type: 'image', data: 'd29ybGQ=', mimeType: 'image/webp' }], details: { phase: 2 } });
        \\      return {
        \\        content: [{ type: 'text', text: 'complete' }, { type: 'image', data: 'ZmluYWw=', mimeType: 'image/jpeg' }, { type: 'image', data: 'c2Vjb25k', mimeType: 'image/png' }], details: { phase: 3, ok: true },
        \\        usage: { input: 10, output: 20, cacheRead: 30, cacheWrite: 40, reasoning: 5, totalTokens: 100, cost: { input: 1, output: 2, cacheRead: 3, cacheWrite: 4, total: 10 } },
        \\        addedToolNames: ['late_tool', 'other_tool'],
        \\      };
        \\    },
        \\    renderResult(result, { isPartial }, _theme, context) {
        \\      const kinds = result.content.map((item) => item.type).join(',');
        \\      return new Text(`RICH|${context.toolCallId}|${isPartial}|${context.showImages}|${result.details.phase}|${kinds}`);
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "rich.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "rich.ts" });
    defer gpa.free(path);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(path);

    var output = (try host.executeTool("stream-rich", "{\"value\":\"blue\"}")).?;
    defer output.deinit(gpa);
    try std.testing.expectEqualStrings("complete", output.content);
    try std.testing.expectEqualStrings("ZmluYWw=", output.image_b64.?);
    try std.testing.expectEqualStrings("image/jpeg", output.image_mime.?);
    try std.testing.expectEqual(@as(usize, 2), output.images.len);
    try std.testing.expectEqualStrings("c2Vjb25k", output.images[1].data_b64);
    try std.testing.expectEqualStrings("image/png", output.images[1].mime_type);
    try std.testing.expect(std.mem.indexOf(u8, output.details_json.?, "\"phase\":3") != null);
    try std.testing.expectEqual(@as(u64, 100), output.usage.?.total_tokens);
    try std.testing.expectEqual(@as(?u64, 5), output.usage.?.reasoning);
    try std.testing.expectApproxEqAbs(@as(f64, 10), output.usage.?.cost.total, 1e-12);
    try std.testing.expectEqual(@as(usize, 2), output.added_tool_names.len);
    try std.testing.expectEqualStrings("late_tool", output.added_tool_names[0]);
    try std.testing.expectEqual(@as(usize, 2), output.updates.len);
    try std.testing.expectEqualStrings("phase:blue", output.updates[0].content);
    try std.testing.expect(std.mem.indexOf(u8, output.updates[0].details_json.?, "\"phase\":1") != null);
    try std.testing.expectEqual(@as(u64, 10), output.updates[0].usage.?.total_tokens);
    try std.testing.expectEqual(@as(usize, 1), output.updates[0].added_tool_names.len);
    try std.testing.expectEqualStrings("partial_tool", output.updates[0].added_tool_names[0]);
    try std.testing.expectEqualStrings("", output.updates[1].content);
    try std.testing.expectEqualStrings("aGVsbG8=", output.updates[1].image_b64.?);
    try std.testing.expectEqualStrings("image/png", output.updates[1].image_mime.?);
    try std.testing.expectEqual(@as(usize, 2), output.updates[1].images.len);
    try std.testing.expectEqualStrings("d29ybGQ=", output.updates[1].images[1].data_b64);

    const partial = (try host.renderToolResultRichImages(
        "stream-rich",
        "call-rich",
        output.updates[1].content,
        output.updates[1].is_error,
        output.updates[1].details_json,
        output.updates[1].images,
        false,
        true,
        false,
        80,
    )).?;
    defer gpa.free(partial);
    try std.testing.expectEqualStrings("RICH|call-rich|true|false|2|image,image", partial);

    const final = (try host.renderToolResultRichImages(
        "stream-rich",
        "call-rich",
        output.content,
        output.is_error,
        output.details_json,
        output.images,
        true,
        false,
        true,
        80,
    )).?;
    defer gpa.free(final);
    try std.testing.expectEqualStrings("RICH|call-rich|false|true|3|text,image,image", final);
}

test "JavaScript host forwards live updates before resolution and retains observer replay" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!jsRuntimeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { writeFileSync } from 'node:fs';
        \\export default function(pi) {
        \\  pi.registerTool({
        \\    name: 'live-host', description: 'live host', parameters: { type: 'object', properties: { marker: { type: 'string' } }, required: ['marker'] },
        \\    async execute(_id, params, _signal, onUpdate) {
        \\      onUpdate({ content: [{ type: 'text', text: 'host-live' }], details: { phase: 1 } });
        \\      await new Promise(resolve => setTimeout(resolve, 120));
        \\      writeFileSync(params.marker, 'done');
        \\      return { content: [{ type: 'text', text: 'host-complete' }], details: { phase: 2 } };
        \\    }
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "live-host.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "live-host.ts" });
    defer gpa.free(path);
    const marker = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "resolved.marker" });
    defer gpa.free(marker);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(path);

    const Probe = struct {
        io: Io,
        marker: []const u8,
        count: usize = 0,
        before_resolution: bool = false,

        fn update(raw_ctx: ?*anyopaque, value: *const ToolUpdate) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw_ctx.?));
            try std.testing.expectEqualStrings("host-live", value.content);
            try std.testing.expect(std.mem.indexOf(u8, value.details_json.?, "\"phase\":1") != null);
            var resolved = true;
            std.Io.Dir.cwd().access(self.io, self.marker, .{}) catch {
                resolved = false;
            };
            self.before_resolution = !resolved;
            self.count += 1;
        }
    };
    var probe = Probe{ .io = io, .marker = marker };
    var args: std.Io.Writer.Allocating = .init(gpa);
    defer args.deinit();
    try args.writer.writeAll("{\"marker\":");
    try std.json.Stringify.value(marker, .{}, &args.writer);
    try args.writer.writeByte('}');

    var output = (try host.executeToolStreaming("live-host", args.written(), Probe.update, &probe)).?;
    defer output.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), probe.count);
    try std.testing.expect(probe.before_resolution);
    try std.testing.expectEqualStrings("host-complete", output.content);
    try std.testing.expectEqual(@as(usize, 1), output.updates.len);
    try std.testing.expectEqualStrings("host-live", output.updates[0].content);
    try std.testing.expect(output.updates[0].observer_deferred);
    try std.Io.Dir.cwd().access(io, marker, .{});
}

test "JavaScript extension prepareArguments transforms raw tool input" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!jsRuntimeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { Type } from '@earendil-works/pi-ai';
        \\export default function(pi) {
        \\  pi.registerTool({
        \\    name: 'prepared-tool', label: 'Prepared', description: 'prepare',
        \\    parameters: Type.Object({ value: Type.String(), count: Type.Number() }),
        \\    prepareArguments(args) { return { value: String(args.legacy ?? ''), count: Number(args.count ?? 1) }; },
        \\    async execute(_id, params) { return { content: [{ type: 'text', text: `${params.value}:${params.count}` }], details: {} }; },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "prepare.ts", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "prepare.ts" });
    defer gpa.free(path);

    var host = Host{ .gpa = gpa, .io = io };
    defer host.deinit();
    try host.loadPath(path);
    const tool = findTool(host.extensions.items[0].tools, "prepared-tool").?;
    try std.testing.expect(tool.has_prepare_arguments);

    const prepared = (try host.prepareToolArguments("prepared-tool", "{\"legacy\":\"converted\",\"count\":4}")).?;
    defer gpa.free(prepared);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, prepared, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("converted", parsed.value.object.get("value").?.string);
    try std.testing.expectEqual(@as(i64, 4), parsed.value.object.get("count").?.integer);

    var output = (try host.executeTool("prepared-tool", prepared)).?;
    defer output.deinit(gpa);
    try std.testing.expectEqualStrings("converted:4", output.content);
    try std.testing.expect((try host.prepareToolArguments("unknown", "{}")) == null);
}

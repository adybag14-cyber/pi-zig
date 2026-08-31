//! Native implementation of the public extension UI boundary.
//!
//! JavaScript/TypeScript workers send framed `ui_request` records for dialogs
//! and `ui_action` records for retained UI mutations. This controller owns all
//! strings after the worker callback returns, serializes dialogs, and projects
//! retained state into the current terminal frontend. Non-interactive modes
//! preserve state but return deterministic dialog fallbacks.
const std = @import("std");
const Io = std.Io;
const js_runtime = @import("js_runtime.zig");
const providers = @import("../ai/providers.zig");
const coding_clipboard = @import("../coding_agent/clipboard.zig");
const agent_session = @import("../agent/session.zig");
const render = @import("../tui/render.zig");
const line_editor = @import("../tui/line_editor.zig");
const Editor = @import("../tui/editor.zig").Editor;
const Keybindings = @import("../tui/keybindings.zig").Manager;

pub const NotificationKind = enum { info, warning, error_message };
pub const WidgetPlacement = enum { above_editor, below_editor };
pub const PromptEvent = enum { start, end };
pub const PromptEventFn = *const fn (?*anyopaque, PromptEvent, []const u8) void;

pub const Notification = struct {
    message: []u8,
    kind: NotificationKind,

    fn deinit(self: *Notification, gpa: std.mem.Allocator) void {
        gpa.free(self.message);
        self.* = undefined;
    }
};

pub const Status = struct {
    key: []u8,
    text: []u8,

    fn deinit(self: *Status, gpa: std.mem.Allocator) void {
        gpa.free(self.key);
        gpa.free(self.text);
        self.* = undefined;
    }
};

pub const Widget = struct {
    key: []u8,
    lines: [][]u8,
    placement: WidgetPlacement,

    fn deinit(self: *Widget, gpa: std.mem.Allocator) void {
        gpa.free(self.key);
        freeLines(gpa, self.lines);
        self.* = undefined;
    }
};

pub const WorkingIndicator = struct {
    frames: ?[][]u8 = null,
    interval_ms: ?u64 = null,

    fn deinit(self: *WorkingIndicator, gpa: std.mem.Allocator) void {
        if (self.frames) |frames| freeLines(gpa, frames);
        self.* = undefined;
    }
};

pub const ContextOptions = struct {
    mode: []const u8,
    cwd: []const u8,
    session_id: []const u8,
    session_name: ?[]const u8 = null,
    provider: ?[]const u8 = null,
    model_id: ?[]const u8 = null,
    thinking_level: ?[]const u8 = null,
    project_trusted: bool = false,
    idle: bool = true,
    active_tools: []const []const u8 = &.{},
    all_tools: []const []const u8 = &.{},
    model_catalog: []const providers.ModelInfo = &.{},
    configured_providers: []const []const u8 = &.{},
    session: ?*const agent_session.Session = null,
    session_file: ?[]const u8 = null,
    session_dir: ?[]const u8 = null,
};

pub const Controller = struct {
    gpa: std.mem.Allocator,
    io: Io,
    has_ui: bool,
    width: usize = 80,
    reader: ?*Io.File.Reader = null,
    clipboard_options: coding_clipboard.Options = .{},
    prompt_event_fn: ?PromptEventFn = null,
    prompt_event_ctx: ?*anyopaque = null,

    state_mutex: Io.Mutex = .init,
    dialog_mutex: Io.Mutex = .init,

    notifications: std.ArrayList(Notification) = .empty,
    statuses: std.ArrayList(Status) = .empty,
    widgets: std.ArrayList(Widget) = .empty,
    header_lines: ?[][]u8 = null,
    footer_lines: ?[][]u8 = null,
    custom_lines: ?[][]u8 = null,
    title: ?[]u8 = null,
    working_message: ?[]u8 = null,
    working_visible: bool = true,
    working_indicator: WorkingIndicator = .{},
    hidden_thinking_label: ?[]u8 = null,
    theme_name: ?[]u8 = null,
    editor_snapshot: []u8,
    pending_editor_text: ?[]u8 = null,
    custom_editor_enabled: bool = false,
    autocomplete_requested: bool = false,

    header_dirty: bool = false,
    footer_dirty: bool = false,
    surface_dirty: bool = false,
    title_dirty: bool = false,
    custom_dirty: bool = false,

    pub fn init(gpa: std.mem.Allocator, io: Io, has_ui: bool, width: usize) !Controller {
        return .{
            .gpa = gpa,
            .io = io,
            .has_ui = has_ui,
            .width = @max(width, 20),
            .editor_snapshot = try gpa.dupe(u8, ""),
        };
    }

    pub fn deinit(self: *Controller) void {
        for (self.notifications.items) |*item| item.deinit(self.gpa);
        self.notifications.deinit(self.gpa);
        for (self.statuses.items) |*item| item.deinit(self.gpa);
        self.statuses.deinit(self.gpa);
        for (self.widgets.items) |*item| item.deinit(self.gpa);
        self.widgets.deinit(self.gpa);
        if (self.header_lines) |lines| freeLines(self.gpa, lines);
        if (self.footer_lines) |lines| freeLines(self.gpa, lines);
        if (self.custom_lines) |lines| freeLines(self.gpa, lines);
        if (self.title) |value| self.gpa.free(value);
        if (self.working_message) |value| self.gpa.free(value);
        self.working_indicator.deinit(self.gpa);
        if (self.hidden_thinking_label) |value| self.gpa.free(value);
        if (self.theme_name) |value| self.gpa.free(value);
        self.gpa.free(self.editor_snapshot);
        if (self.pending_editor_text) |value| self.gpa.free(value);
        self.* = undefined;
    }

    pub fn bindPromptEvents(self: *Controller, callback: ?PromptEventFn, context: ?*anyopaque) void {
        self.prompt_event_fn = callback;
        self.prompt_event_ctx = context;
    }

    /// Drop all state owned by the previous extension runtime while preserving
    /// the terminal binding and current editor snapshot. `/reload` calls this
    /// only after a replacement runtime has been prepared successfully.
    pub fn resetForReload(self: *Controller) void {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);

        for (self.notifications.items) |*item| item.deinit(self.gpa);
        self.notifications.clearRetainingCapacity();
        for (self.statuses.items) |*item| item.deinit(self.gpa);
        self.statuses.clearRetainingCapacity();
        for (self.widgets.items) |*item| item.deinit(self.gpa);
        self.widgets.clearRetainingCapacity();
        if (self.header_lines) |lines| freeLines(self.gpa, lines);
        self.header_lines = null;
        if (self.footer_lines) |lines| freeLines(self.gpa, lines);
        self.footer_lines = null;
        if (self.custom_lines) |lines| freeLines(self.gpa, lines);
        self.custom_lines = null;
        if (self.title) |value| self.gpa.free(value);
        self.title = null;
        if (self.working_message) |value| self.gpa.free(value);
        self.working_message = null;
        self.working_indicator.deinit(self.gpa);
        self.working_indicator = .{};
        if (self.hidden_thinking_label) |value| self.gpa.free(value);
        self.hidden_thinking_label = null;
        if (self.theme_name) |value| self.gpa.free(value);
        self.theme_name = null;
        if (self.pending_editor_text) |value| self.gpa.free(value);
        self.pending_editor_text = null;
        self.working_visible = true;
        self.custom_editor_enabled = false;
        self.autocomplete_requested = false;
        // Mark every retained surface dirty so the next flush erases visual
        // state left by the retired runtime even when the replacement installs
        // no header, footer, widgets, title, or custom component.
        self.header_dirty = true;
        self.footer_dirty = true;
        self.surface_dirty = true;
        self.title_dirty = true;
        self.custom_dirty = true;
    }

    pub fn bridge(self: *Controller) js_runtime.UiBridge {
        return .{
            .context = self,
            .request_fn = requestThunk,
            .action_fn = actionThunk,
        };
    }

    pub fn bindClipboardEnvironment(self: *Controller, environ: ?*const std.process.Environ.Map) void {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        self.clipboard_options.environ = environ;
        self.clipboard_options.osc52_fallback = self.has_ui;
    }

    pub fn bindReader(self: *Controller, reader: ?*Io.File.Reader) void {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        self.reader = reader;
    }

    pub fn setHasUi(self: *Controller, value: bool) void {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        self.has_ui = value;
        self.clipboard_options.osc52_fallback = value;
    }

    pub fn setEditorSnapshot(self: *Controller, text: []const u8) !void {
        const owned = try self.gpa.dupe(u8, text);
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        self.gpa.free(self.editor_snapshot);
        self.editor_snapshot = owned;
    }

    /// Transfer the next editor prefill to the caller. Ownership follows the
    /// controller allocator and the caller must free the returned slice.
    pub fn takePendingEditorText(self: *Controller) ?[]u8 {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        const value = self.pending_editor_text;
        self.pending_editor_text = null;
        return value;
    }

    pub fn editorText(self: *Controller, allocator: std.mem.Allocator) ![]u8 {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        return allocator.dupe(u8, self.pending_editor_text orelse self.editor_snapshot);
    }

    /// Build the worker-side ExtensionContext snapshot from live native state.
    /// The returned JSON is self-contained and can outlive this controller.
    pub fn contextJson(self: *Controller, allocator: std.mem.Allocator, options: ContextOptions) ![]u8 {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);

        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try out.writer.writeAll("{\"mode\":");
        try std.json.Stringify.value(options.mode, .{}, &out.writer);
        try out.writer.print(",\"hasUI\":{s},\"cwd\":", .{if (self.has_ui) "true" else "false"});
        try std.json.Stringify.value(options.cwd, .{}, &out.writer);
        try out.writer.print(",\"width\":{d},\"editorText\":", .{self.width});
        try std.json.Stringify.value(self.pending_editor_text orelse self.editor_snapshot, .{}, &out.writer);
        try out.writer.writeAll(",\"thinkingLevel\":");
        if (options.thinking_level) |value| try std.json.Stringify.value(value, .{}, &out.writer) else try out.writer.writeAll("\"off\"");
        try out.writer.print(",\"projectTrusted\":{s},\"idle\":{s},\"sessionId\":", .{
            if (options.project_trusted) "true" else "false",
            if (options.idle) "true" else "false",
        });
        try std.json.Stringify.value(options.session_id, .{}, &out.writer);
        try out.writer.writeAll(",\"sessionName\":");
        if (options.session_name) |value| try std.json.Stringify.value(value, .{}, &out.writer) else try out.writer.writeAll("null");
        try out.writer.writeAll(",\"sessionFile\":");
        if (options.session_file) |value| try std.json.Stringify.value(value, .{}, &out.writer) else try out.writer.writeAll("null");
        try out.writer.writeAll(",\"sessionDir\":");
        if (options.session_dir) |value| try std.json.Stringify.value(value, .{}, &out.writer) else try out.writer.writeAll("null");
        if (options.session) |session| try writeSessionSnapshot(allocator, &out.writer, session) else try out.writer.writeAll(",\"sessionHeader\":null,\"sessionEntries\":[],\"sessionBranch\":[],\"sessionLeafId\":null");
        try out.writer.writeAll(",\"model\":");
        if (options.model_id) |model_id| {
            try out.writer.writeAll("{\"id\":");
            try std.json.Stringify.value(model_id, .{}, &out.writer);
            try out.writer.writeAll(",\"provider\":");
            if (options.provider) |provider| try std.json.Stringify.value(provider, .{}, &out.writer) else try out.writer.writeAll("null");
            try out.writer.writeByte('}');
        } else try out.writer.writeAll("null");
        try out.writer.writeAll(",\"activeTools\":[");
        for (options.active_tools, 0..) |tool, index| {
            if (index > 0) try out.writer.writeByte(',');
            try std.json.Stringify.value(tool, .{}, &out.writer);
        }
        try out.writer.writeAll("],\"allTools\":[");
        for (options.all_tools, 0..) |tool, index| {
            if (index > 0) try out.writer.writeByte(',');
            try out.writer.writeAll("{\"name\":");
            try std.json.Stringify.value(tool, .{}, &out.writer);
            try out.writer.writeByte('}');
        }
        try out.writer.writeAll("],\"models\":[");
        for (options.model_catalog, 0..) |model, index| {
            if (index > 0) try out.writer.writeByte(',');
            try out.writer.writeAll("{\"id\":");
            try std.json.Stringify.value(model.id, .{}, &out.writer);
            try out.writer.writeAll(",\"name\":");
            try std.json.Stringify.value(model.display, .{}, &out.writer);
            try out.writer.writeAll(",\"provider\":");
            try std.json.Stringify.value(model.providerName(), .{}, &out.writer);
            try out.writer.writeAll(",\"api\":");
            try std.json.Stringify.value(@tagName(model.apiKind()), .{}, &out.writer);
            try out.writer.writeAll(",\"baseUrl\":");
            if (model.base_url) |base_url| try std.json.Stringify.value(base_url, .{}, &out.writer) else try out.writer.writeAll("null");
            try out.writer.print(",\"reasoning\":{s},\"input\":[", .{if (model.reasoning) "true" else "false"});
            if (model.input_text) try out.writer.writeAll("\"text\"");
            if (model.input_image) {
                if (model.input_text) try out.writer.writeByte(',');
                try out.writer.writeAll("\"image\"");
            }
            try out.writer.print("],\"contextWindow\":{d},\"maxTokens\":{d},\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}}}}}", .{
                model.context_window,
                model.max_tokens,
                model.cost.input,
                model.cost.output,
                model.cost.cache_read,
                model.cost.cache_write,
            });
        }
        try out.writer.writeAll("],\"configuredProviders\":[");
        for (options.configured_providers, 0..) |provider, index| {
            if (index > 0) try out.writer.writeByte(',');
            try std.json.Stringify.value(provider, .{}, &out.writer);
        }
        try out.writer.writeAll("],\"statuses\":{");
        for (self.statuses.items, 0..) |status, index| {
            if (index > 0) try out.writer.writeByte(',');
            try std.json.Stringify.value(status.key, .{}, &out.writer);
            try out.writer.writeByte(':');
            try std.json.Stringify.value(status.text, .{}, &out.writer);
        }
        try out.writer.writeAll("}}");
        return out.toOwnedSlice();
    }

    pub fn applyAction(self: *Controller, method: []const u8, args_json: []const u8) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, args_json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidExtensionUiAction;
        const object = &parsed.value.object;

        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);

        if (std.mem.eql(u8, method, "notify")) {
            const message = try requiredString(object, "message");
            const kind_text = optionalString(object, "type") orelse "info";
            try self.notifications.append(self.gpa, .{
                .message = try self.gpa.dupe(u8, message),
                .kind = if (std.mem.eql(u8, kind_text, "warning")) .warning else if (std.mem.eql(u8, kind_text, "error")) .error_message else .info,
            });
            return;
        }
        if (std.mem.eql(u8, method, "setStatus")) {
            const key = try requiredString(object, "key");
            const text_value = object.get("text");
            if (text_value == null or text_value.? == .null) {
                self.removeStatus(key);
            } else {
                if (text_value.? != .string) return error.InvalidExtensionUiAction;
                try self.putStatus(key, text_value.?.string);
            }
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setWorkingMessage")) {
            try replaceNullableString(self.gpa, &self.working_message, object.get("message"));
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setWorkingVisible")) {
            self.working_visible = try requiredBool(object, "visible");
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setWorkingIndicator")) {
            self.working_indicator.deinit(self.gpa);
            if (object.get("options")) |options| {
                if (options == .null) {
                    self.working_indicator = .{};
                } else {
                    if (options != .object) return error.InvalidExtensionUiAction;
                    var indicator: WorkingIndicator = .{};
                    errdefer indicator.deinit(self.gpa);
                    if (options.object.get("frames")) |frames| {
                        if (frames != .null) indicator.frames = try cloneStringArray(self.gpa, frames);
                    }
                    if (options.object.get("intervalMs")) |interval| {
                        if (interval != .null) {
                            if (interval != .integer or interval.integer < 0) return error.InvalidExtensionUiAction;
                            indicator.interval_ms = @intCast(interval.integer);
                        }
                    }
                    self.working_indicator = indicator;
                }
            } else self.working_indicator = .{};
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setHiddenThinkingLabel")) {
            try replaceNullableString(self.gpa, &self.hidden_thinking_label, object.get("label"));
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setWidget")) {
            const key = try requiredString(object, "key");
            const lines_value = object.get("lines");
            if (lines_value == null or lines_value.? == .null) {
                self.removeWidget(key);
            } else {
                const lines = try cloneStringArray(self.gpa, lines_value.?);
                errdefer freeLines(self.gpa, lines);
                const placement_text = optionalString(object, "placement") orelse "aboveEditor";
                const placement: WidgetPlacement = if (std.mem.eql(u8, placement_text, "belowEditor")) .below_editor else .above_editor;
                try self.putWidget(key, lines, placement);
            }
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setHeader")) {
            try replaceNullableLines(self.gpa, &self.header_lines, object.get("lines"));
            self.header_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setFooter")) {
            try replaceNullableLines(self.gpa, &self.footer_lines, object.get("lines"));
            self.footer_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setTitle")) {
            const title_value = try requiredString(object, "title");
            try replaceOwnedString(self.gpa, &self.title, title_value);
            self.title_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "pasteToEditor")) {
            const text = try requiredString(object, "text");
            const base = self.pending_editor_text orelse self.editor_snapshot;
            const joined = try std.mem.concat(self.gpa, u8, &.{ base, text });
            if (self.pending_editor_text) |old| self.gpa.free(old);
            self.pending_editor_text = joined;
            return;
        }
        if (std.mem.eql(u8, method, "setEditorText")) {
            const text = try requiredString(object, "text");
            const owned = try self.gpa.dupe(u8, text);
            if (self.pending_editor_text) |old| self.gpa.free(old);
            self.pending_editor_text = owned;
            return;
        }
        if (std.mem.eql(u8, method, "setTheme")) {
            const name = try requiredString(object, "name");
            try replaceOwnedString(self.gpa, &self.theme_name, name);
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "showCustom")) {
            try replaceNullableLines(self.gpa, &self.custom_lines, object.get("lines"));
            self.custom_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "hideCustom")) {
            if (self.custom_lines) |lines| freeLines(self.gpa, lines);
            self.custom_lines = null;
            self.custom_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "setEditorComponent")) {
            self.custom_editor_enabled = optionalBool(object, "enabled") orelse false;
            self.surface_dirty = true;
            return;
        }
        if (std.mem.eql(u8, method, "autocompleteProvider")) {
            self.autocomplete_requested = true;
            self.surface_dirty = true;
            return;
        }
        // Newer extension runtimes may introduce advisory UI actions. Unknown
        // actions are intentionally ignored so one extension cannot terminate
        // the host merely because it targets a newer Pi minor release.
    }

    pub fn request(self: *Controller, allocator: std.mem.Allocator, method: []const u8, args_json: []const u8) ![]u8 {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, args_json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidExtensionUiRequest;

        self.dialog_mutex.lockUncancelable(self.io);
        defer self.dialog_mutex.unlock(self.io);

        if (std.mem.eql(u8, method, "copyToClipboard")) {
            const text = try requiredString(&parsed.value.object, "text");
            self.state_mutex.lockUncancelable(self.io);
            const clipboard_options = self.clipboard_options;
            self.state_mutex.unlock(self.io);
            _ = try coding_clipboard.copyText(self.gpa, self.io, text, clipboard_options);
            return allocator.dupe(u8, "true");
        }

        self.state_mutex.lockUncancelable(self.io);
        const ui_available = self.has_ui and self.reader != null;
        const reader = self.reader;
        self.state_mutex.unlock(self.io);
        if (!ui_available) return allocator.dupe(u8, if (std.mem.eql(u8, method, "confirm")) "false" else "null");
        if (self.prompt_event_fn) |callback| callback(self.prompt_event_ctx, .start, method);
        defer if (self.prompt_event_fn) |callback| callback(self.prompt_event_ctx, .end, method);

        if (std.mem.eql(u8, method, "select")) return self.requestSelect(allocator, reader.?, &parsed.value.object);
        if (std.mem.eql(u8, method, "confirm")) return self.requestConfirm(allocator, reader.?, &parsed.value.object);
        if (std.mem.eql(u8, method, "input")) return self.requestInput(allocator, reader.?, &parsed.value.object);
        if (std.mem.eql(u8, method, "editor")) return self.requestEditor(allocator, reader.?, &parsed.value.object);
        if (std.mem.eql(u8, method, "custom")) return self.requestCustom(allocator, reader.?, &parsed.value.object);
        return allocator.dupe(u8, "null");
    }

    /// Render and acknowledge the extension-owned header. Returns false when
    /// the built-in header should be used instead.
    pub fn renderCustomHeader(self: *Controller) !bool {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        if (!self.has_ui or self.header_lines == null) return false;
        try printLines(self.io, self.header_lines.?);
        self.header_dirty = false;
        return true;
    }

    /// Render queued notifications and changed retained surfaces. The state is
    /// preserved across invocations; only transient notifications are cleared.
    pub fn flush(self: *Controller) !void {
        self.state_mutex.lockUncancelable(self.io);
        defer self.state_mutex.unlock(self.io);
        if (!self.has_ui) return;

        if (self.title_dirty) {
            if (self.title) |value| try writeTerminalTitle(self.io, value);
            self.title_dirty = false;
        }
        if (self.header_dirty) {
            if (self.header_lines) |lines| try printLines(self.io, lines);
            self.header_dirty = false;
        }
        for (self.notifications.items) |*notification| {
            var prefix_buf: [32]u8 = undefined;
            const prefix = switch (notification.kind) {
                .info => "extension",
                .warning => "extension warning",
                .error_message => "extension error",
            };
            const styled = try std.fmt.bufPrint(&prefix_buf, "[{s}]", .{prefix});
            var line: std.Io.Writer.Allocating = .init(self.gpa);
            defer line.deinit();
            try line.writer.print("{s} {s}", .{ styled, notification.message });
            try render.printLine(self.io, line.written());
            notification.deinit(self.gpa);
        }
        self.notifications.clearRetainingCapacity();

        if (self.surface_dirty) {
            for (self.widgets.items) |widget| if (widget.placement == .above_editor) try printLines(self.io, widget.lines);
            if (self.statuses.items.len > 0) {
                var status_line: std.Io.Writer.Allocating = .init(self.gpa);
                defer status_line.deinit();
                try status_line.writer.writeAll("[status]");
                for (self.statuses.items) |status| try status_line.writer.print(" {s}={s}", .{ status.key, status.text });
                try render.printLine(self.io, status_line.written());
            }
            if (self.working_visible and (self.working_message != null or self.working_indicator.frames != null)) {
                var working_line: std.Io.Writer.Allocating = .init(self.gpa);
                defer working_line.deinit();
                if (self.working_indicator.frames) |frames| if (frames.len > 0) try working_line.writer.print("{s} ", .{frames[0]});
                try working_line.writer.writeAll(self.working_message orelse "Working…");
                try render.printLine(self.io, working_line.written());
            }
            if (self.hidden_thinking_label) |label| {
                var line: std.Io.Writer.Allocating = .init(self.gpa);
                defer line.deinit();
                try line.writer.print("[thinking label] {s}", .{label});
                try render.printLine(self.io, line.written());
            }
            if (self.theme_name) |name| {
                var line: std.Io.Writer.Allocating = .init(self.gpa);
                defer line.deinit();
                try line.writer.print("[theme] {s}", .{name});
                try render.printLine(self.io, line.written());
            }
            if (self.custom_editor_enabled) try render.printLine(self.io, "[extension editor component active: compatibility projection]");
            if (self.autocomplete_requested) try render.printLine(self.io, "[extension autocomplete provider registered: compatibility projection]");
            for (self.widgets.items) |widget| if (widget.placement == .below_editor) try printLines(self.io, widget.lines);
            self.surface_dirty = false;
        }
        if (self.custom_dirty) {
            if (self.custom_lines) |lines| try printLines(self.io, lines);
            self.custom_dirty = false;
        }
        if (self.footer_dirty) {
            if (self.footer_lines) |lines| try printLines(self.io, lines);
            self.footer_dirty = false;
        }
    }

    fn requestSelect(self: *Controller, allocator: std.mem.Allocator, reader: *Io.File.Reader, object: *const std.json.ObjectMap) ![]u8 {
        const title = try requiredString(object, "title");
        const options_value = object.get("options") orelse return error.InvalidExtensionUiRequest;
        if (options_value != .array) return error.InvalidExtensionUiRequest;
        try render.printLine(self.io, title);
        for (options_value.array.items, 0..) |item, index| {
            if (item != .string) return error.InvalidExtensionUiRequest;
            var line: std.Io.Writer.Allocating = .init(self.gpa);
            defer line.deinit();
            try line.writer.print("  {d}. {s}", .{ index + 1, item.string });
            try render.printLine(self.io, line.written());
        }
        if (options_value.array.items.len == 0) return allocator.dupe(u8, "null");

        while (true) {
            const answer = try self.readDialogLine(reader, "Select (blank cancels): ", "");
            defer self.gpa.free(answer);
            const trimmed = std.mem.trim(u8, answer, " \t\r\n");
            if (trimmed.len == 0) return allocator.dupe(u8, "null");
            if (std.fmt.parseUnsigned(usize, trimmed, 10)) |choice| {
                if (choice >= 1 and choice <= options_value.array.items.len) return jsonString(allocator, options_value.array.items[choice - 1].string);
            } else |_| {}
            for (options_value.array.items) |item| if (std.ascii.eqlIgnoreCase(trimmed, item.string)) return jsonString(allocator, item.string);
            try render.printLine(self.io, "Choose an option number or press Enter to cancel.");
        }
    }

    fn requestConfirm(self: *Controller, allocator: std.mem.Allocator, reader: *Io.File.Reader, object: *const std.json.ObjectMap) ![]u8 {
        const title = try requiredString(object, "title");
        const message = try requiredString(object, "message");
        try render.printLine(self.io, title);
        try render.printLine(self.io, message);
        const answer = try self.readDialogLine(reader, "Confirm [y/N]: ", "");
        defer self.gpa.free(answer);
        const trimmed = std.mem.trim(u8, answer, " \t\r\n");
        const yes = std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes");
        return allocator.dupe(u8, if (yes) "true" else "false");
    }

    fn requestInput(self: *Controller, allocator: std.mem.Allocator, reader: *Io.File.Reader, object: *const std.json.ObjectMap) ![]u8 {
        const title = try requiredString(object, "title");
        const placeholder = optionalString(object, "placeholder") orelse "";
        try render.printLine(self.io, title);
        if (placeholder.len > 0) {
            var line: std.Io.Writer.Allocating = .init(self.gpa);
            defer line.deinit();
            try line.writer.print("({s})", .{placeholder});
            try render.printLine(self.io, line.written());
        }
        const answer = try self.readDialogLine(reader, "> ", "");
        defer self.gpa.free(answer);
        if (answer.len == 0) return allocator.dupe(u8, "null");
        return jsonString(allocator, answer);
    }

    fn requestEditor(self: *Controller, allocator: std.mem.Allocator, reader: *Io.File.Reader, object: *const std.json.ObjectMap) ![]u8 {
        const title = try requiredString(object, "title");
        const prefill = optionalString(object, "prefill") orelse "";
        try render.printLine(self.io, title);
        try render.printLine(self.io, "Shift+Enter/Ctrl+J inserts a newline; Enter submits.");
        const answer = try self.readDialogLine(reader, "> ", prefill);
        defer self.gpa.free(answer);
        if (answer.len == 0) return allocator.dupe(u8, "null");
        return jsonString(allocator, answer);
    }

    fn requestCustom(self: *Controller, allocator: std.mem.Allocator, reader: *Io.File.Reader, object: *const std.json.ObjectMap) ![]u8 {
        if (object.get("lines")) |lines_value| {
            const lines = try cloneStringArray(self.gpa, lines_value);
            defer freeLines(self.gpa, lines);
            try printLines(self.io, lines);
        }
        const answer = try self.readDialogLine(reader, "Press Enter to close (optional result): ", "");
        defer self.gpa.free(answer);
        if (answer.len == 0) return allocator.dupe(u8, "null");
        return jsonString(allocator, answer);
    }

    fn readDialogLine(self: *Controller, reader: *Io.File.Reader, prompt: []const u8, prefill: []const u8) ![]u8 {
        var editor = Editor.init(self.gpa);
        defer editor.deinit();
        var bindings = Keybindings.init(self.gpa);
        defer bindings.deinit();
        return line_editor.readLineWithCompleterAndShortcutsPrefill(self.gpa, self.io, reader, &editor, &bindings, prompt, null, null, prefill);
    }

    fn putStatus(self: *Controller, key: []const u8, text: []const u8) !void {
        for (self.statuses.items) |*status| {
            if (!std.mem.eql(u8, status.key, key)) continue;
            const owned = try self.gpa.dupe(u8, text);
            self.gpa.free(status.text);
            status.text = owned;
            return;
        }
        try self.statuses.append(self.gpa, .{ .key = try self.gpa.dupe(u8, key), .text = try self.gpa.dupe(u8, text) });
    }

    fn removeStatus(self: *Controller, key: []const u8) void {
        var index: usize = 0;
        while (index < self.statuses.items.len) : (index += 1) {
            if (!std.mem.eql(u8, self.statuses.items[index].key, key)) continue;
            var removed = self.statuses.orderedRemove(index);
            removed.deinit(self.gpa);
            return;
        }
    }

    fn putWidget(self: *Controller, key: []const u8, lines: [][]u8, placement: WidgetPlacement) !void {
        for (self.widgets.items) |*widget| {
            if (!std.mem.eql(u8, widget.key, key)) continue;
            freeLines(self.gpa, widget.lines);
            widget.lines = lines;
            widget.placement = placement;
            return;
        }
        try self.widgets.append(self.gpa, .{ .key = try self.gpa.dupe(u8, key), .lines = lines, .placement = placement });
    }

    fn removeWidget(self: *Controller, key: []const u8) void {
        var index: usize = 0;
        while (index < self.widgets.items.len) : (index += 1) {
            if (!std.mem.eql(u8, self.widgets.items[index].key, key)) continue;
            var removed = self.widgets.orderedRemove(index);
            removed.deinit(self.gpa);
            return;
        }
    }
};

fn writeSessionSnapshot(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    session: *const agent_session.Session,
) !void {
    const jsonl = try session.toJsonl(allocator);
    defer allocator.free(jsonl);
    const branch = try session.branchEntries(allocator);
    defer allocator.free(branch);

    var branch_index = std.StringHashMap(usize).init(allocator);
    defer branch_index.deinit();
    for (branch, 0..) |entry, index| try branch_index.put(entry.id, index);
    const branch_lines = try allocator.alloc(?[]const u8, branch.len);
    defer allocator.free(branch_lines);
    @memset(branch_lines, null);

    var header: ?[]const u8 = null;
    var entries: std.ArrayList([]const u8) = .empty;
    defer entries.deinit(allocator);
    var lines = std.mem.splitScalar(u8, jsonl, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (header == null) {
            header = line;
            continue;
        }
        try entries.append(allocator, line);
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const id = parsed.value.object.get("id") orelse continue;
        if (id != .string) continue;
        if (branch_index.get(id.string)) |index| branch_lines[index] = line;
    }

    try writer.writeAll(",\"sessionHeader\":");
    if (header) |value| try writer.writeAll(value) else try writer.writeAll("null");
    try writer.writeAll(",\"sessionEntries\":[");
    for (entries.items, 0..) |line, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll(line);
    }
    try writer.writeAll("],\"sessionBranch\":[");
    var wrote_branch = false;
    for (branch_lines) |maybe_line| {
        const line = maybe_line orelse continue;
        if (wrote_branch) try writer.writeByte(',');
        wrote_branch = true;
        try writer.writeAll(line);
    }
    try writer.writeAll("],\"sessionLeafId\":");
    if (session.lastEntryId()) |leaf_id| try std.json.Stringify.value(leaf_id, .{}, writer) else try writer.writeAll("null");
}

fn requestThunk(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args_json: []const u8) anyerror![]u8 {
    const self: *Controller = @ptrCast(@alignCast(raw orelse return error.MissingExtensionUiController));
    return self.request(allocator, method, args_json);
}

fn actionThunk(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args_json: []const u8) anyerror!void {
    _ = allocator;
    const self: *Controller = @ptrCast(@alignCast(raw orelse return error.MissingExtensionUiController));
    return self.applyAction(method, args_json);
}

fn requiredString(object: *const std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidExtensionUiPayload;
    if (value != .string) return error.InvalidExtensionUiPayload;
    return value.string;
}

fn optionalString(object: *const std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn requiredBool(object: *const std.json.ObjectMap, key: []const u8) !bool {
    const value = object.get(key) orelse return error.InvalidExtensionUiPayload;
    if (value != .bool) return error.InvalidExtensionUiPayload;
    return value.bool;
}

fn optionalBool(object: *const std.json.ObjectMap, key: []const u8) ?bool {
    const value = object.get(key) orelse return null;
    if (value != .bool) return null;
    return value.bool;
}

fn replaceOwnedString(gpa: std.mem.Allocator, target: *?[]u8, value: []const u8) !void {
    const owned = try gpa.dupe(u8, value);
    if (target.*) |old| gpa.free(old);
    target.* = owned;
}

fn replaceNullableString(gpa: std.mem.Allocator, target: *?[]u8, value: ?std.json.Value) !void {
    if (value == null or value.? == .null) {
        if (target.*) |old| gpa.free(old);
        target.* = null;
        return;
    }
    if (value.? != .string) return error.InvalidExtensionUiPayload;
    try replaceOwnedString(gpa, target, value.?.string);
}

fn cloneStringArray(gpa: std.mem.Allocator, value: std.json.Value) ![][]u8 {
    if (value != .array) return error.InvalidExtensionUiPayload;
    const result = try gpa.alloc([]u8, value.array.items.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |line| gpa.free(line);
        gpa.free(result);
    }
    for (value.array.items, 0..) |item, index| {
        if (item != .string) return error.InvalidExtensionUiPayload;
        result[index] = try gpa.dupe(u8, item.string);
        initialized += 1;
    }
    return result;
}

fn replaceNullableLines(gpa: std.mem.Allocator, target: *?[][]u8, value: ?std.json.Value) !void {
    if (value == null or value.? == .null) {
        if (target.*) |old| freeLines(gpa, old);
        target.* = null;
        return;
    }
    const owned = try cloneStringArray(gpa, value.?);
    if (target.*) |old| freeLines(gpa, old);
    target.* = owned;
}

fn freeLines(gpa: std.mem.Allocator, lines: [][]u8) void {
    for (lines) |line| gpa.free(line);
    gpa.free(lines);
}

fn jsonString(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();
    try std.json.Stringify.value(value, .{}, &writer.writer);
    return writer.toOwnedSlice();
}

fn printLines(io: Io, lines: [][]u8) !void {
    for (lines) |line| try render.printLine(io, line);
}

fn writeTerminalTitle(io: Io, title: []const u8) !void {
    var sanitized: [512]u8 = undefined;
    var length: usize = 0;
    for (title) |byte| {
        if (length == sanitized.len) break;
        if (byte == 0x1b or byte == 0x07 or byte < 0x20) continue;
        sanitized[length] = byte;
        length += 1;
    }
    try render.writeAll(io, "\x1b]0;");
    try render.writeAll(io, sanitized[0..length]);
    try render.writeAll(io, "\x07");
}

test "extension UI actions retain status widgets editor and title state" {
    var controller = try Controller.init(std.testing.allocator, std.testing.io, false, 100);
    defer controller.deinit();

    try controller.applyAction("setStatus", "{\"key\":\"mode\",\"text\":\"plan\"}");
    try controller.applyAction("setWidget", "{\"key\":\"todo\",\"lines\":[\"one\",\"two\"],\"placement\":\"belowEditor\"}");
    try controller.applyAction("setEditorText", "{\"text\":\"hello\"}");
    try controller.applyAction("pasteToEditor", "{\"text\":\" world\"}");
    try controller.applyAction("setTitle", "{\"title\":\"Pi extension\"}");
    try controller.applyAction("setWorkingIndicator", "{\"options\":{\"frames\":[\"A\",\"B\"],\"intervalMs\":40}}");

    try std.testing.expectEqual(@as(usize, 1), controller.statuses.items.len);
    try std.testing.expectEqualStrings("plan", controller.statuses.items[0].text);
    try std.testing.expectEqual(@as(usize, 1), controller.widgets.items.len);
    try std.testing.expect(controller.widgets.items[0].placement == .below_editor);
    try std.testing.expectEqualStrings("Pi extension", controller.title.?);
    try std.testing.expectEqualStrings("A", controller.working_indicator.frames.?[0]);
    const pending = controller.takePendingEditorText().?;
    defer std.testing.allocator.free(pending);
    try std.testing.expectEqualStrings("hello world", pending);
}

test "extension UI context snapshot owns live editor model and status data" {
    var controller = try Controller.init(std.testing.allocator, std.testing.io, true, 96);
    defer controller.deinit();
    try controller.setEditorSnapshot("draft");
    try controller.applyAction("setStatus", "{\"key\":\"branch\",\"text\":\"main\"}");
    const raw = try controller.contextJson(std.testing.allocator, .{
        .mode = "tui",
        .cwd = "/work",
        .session_id = "session-1",
        .session_name = "demo",
        .provider = "mock",
        .model_id = "tiny",
        .thinking_level = "medium",
        .project_trusted = true,
        .active_tools = &.{"read"},
        .all_tools = &.{ "read", "write" },
    });
    defer std.testing.allocator.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("hasUI").?.bool);
    try std.testing.expectEqualStrings("draft", parsed.value.object.get("editorText").?.string);
    try std.testing.expectEqualStrings("tiny", parsed.value.object.get("model").?.object.get("id").?.string);
    try std.testing.expectEqualStrings("main", parsed.value.object.get("statuses").?.object.get("branch").?.string);
}

test "extension UI clears retained surfaces and returns noninteractive fallbacks" {
    var controller = try Controller.init(std.testing.allocator, std.testing.io, false, 80);
    defer controller.deinit();
    try controller.applyAction("setStatus", "{\"key\":\"x\",\"text\":\"y\"}");
    try controller.applyAction("setStatus", "{\"key\":\"x\",\"text\":null}");
    try controller.applyAction("setHeader", "{\"lines\":[\"header\"]}");
    try controller.applyAction("setHeader", "{\"lines\":null}");
    try std.testing.expectEqual(@as(usize, 0), controller.statuses.items.len);
    try std.testing.expect(controller.header_lines == null);

    const confirm = try controller.request(std.testing.allocator, "confirm", "{\"title\":\"t\",\"message\":\"m\"}");
    defer std.testing.allocator.free(confirm);
    try std.testing.expectEqualStrings("false", confirm);
    const input = try controller.request(std.testing.allocator, "input", "{\"title\":\"t\"}");
    defer std.testing.allocator.free(input);
    try std.testing.expectEqualStrings("null", input);
}

test "extension UI reset for reload clears worker-owned state but preserves editor binding" {
    var controller = try Controller.init(std.testing.allocator, std.testing.io, true, 111);
    defer controller.deinit();
    try controller.setEditorSnapshot("draft survives");
    try controller.applyAction("notify", "{\"message\":\"old\"}");
    try controller.applyAction("setStatus", "{\"key\":\"mode\",\"text\":\"old\"}");
    try controller.applyAction("setWidget", "{\"key\":\"w\",\"lines\":[\"old\"]}");
    try controller.applyAction("setHeader", "{\"lines\":[\"header\"]}");
    try controller.applyAction("setFooter", "{\"lines\":[\"footer\"]}");
    try controller.applyAction("setTitle", "{\"title\":\"old title\"}");
    try controller.applyAction("setWorkingMessage", "{\"message\":\"old work\"}");
    try controller.applyAction("setHiddenThinkingLabel", "{\"label\":\"old think\"}");
    try controller.applyAction("setTheme", "{\"name\":\"old theme\"}");
    try controller.applyAction("setEditorText", "{\"text\":\"pending old\"}");

    controller.resetForReload();

    try std.testing.expectEqual(@as(usize, 0), controller.notifications.items.len);
    try std.testing.expectEqual(@as(usize, 0), controller.statuses.items.len);
    try std.testing.expectEqual(@as(usize, 0), controller.widgets.items.len);
    try std.testing.expect(controller.header_lines == null);
    try std.testing.expect(controller.footer_lines == null);
    try std.testing.expect(controller.title == null);
    try std.testing.expect(controller.working_message == null);
    try std.testing.expect(controller.hidden_thinking_label == null);
    try std.testing.expect(controller.theme_name == null);
    try std.testing.expect(controller.pending_editor_text == null);
    try std.testing.expect(controller.header_dirty);
    try std.testing.expect(controller.footer_dirty);
    try std.testing.expect(controller.surface_dirty);
    try std.testing.expect(controller.title_dirty);
    try std.testing.expect(controller.custom_dirty);
    try std.testing.expect(controller.has_ui);
    try std.testing.expectEqual(@as(usize, 111), controller.width);
    const editor = try controller.editorText(std.testing.allocator);
    defer std.testing.allocator.free(editor);
    try std.testing.expectEqualStrings("draft survives", editor);
}

test "extension copyToClipboard request uses the native clipboard without requiring a dialog UI" {
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
            try self.copied.appendSlice(std.testing.allocator, input);
            return true;
        }
    };
    var controller = try Controller.init(std.testing.allocator, std.testing.io, false, 80);
    defer controller.deinit();
    var fake = Fake{};
    defer fake.copied.deinit(std.testing.allocator);
    controller.clipboard_options = .{
        .platform = .macos,
        .write_runner = .{ .context = &fake, .run_fn = Fake.run },
        .osc52_fallback = false,
    };
    const result = try controller.request(std.testing.allocator, "copyToClipboard", "{\"text\":\"extension copy\"}");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("true", result);
    try std.testing.expectEqualStrings("extension copy", fake.copied.items);
}

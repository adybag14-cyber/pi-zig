//! Persistent fullscreen owner. Main retains Session/Host; this thread owns TTY.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const application = @import("../tui/application.zig");
const layout = @import("../tui/layout.zig");
const terminal = @import("../tui/terminal.zig");
const keys = @import("../tui/keys.zig");
const keybindings = @import("../tui/keybindings.zig");
const line_editor = @import("../tui/line_editor.zig");
const Editor = @import("../tui/editor.zig").Editor;
const session = @import("../agent/session.zig");
const agent_loop = @import("../agent/loop.zig");
const ui = @import("../extensions/ui.zig");
const transcript_mod = @import("transcript_view.zig");

pub const CommandKind = enum { submit, complete, shortcut, clipboard, quit };
pub const Command = struct {
    kind: CommandKind,
    text: []u8,
    key: []u8 = &.{},
    cursor: usize,
    revision: u64,
    pub fn deinit(self: *Command, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        gpa.free(self.key);
    }
};

fn ownershipCase(gpa: std.mem.Allocator) !void {
    const io = std.testing.io;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    try environ.put("TERM", "xterm-256color");
    var bindings = keybindings.Manager.init(gpa);
    defer bindings.deinit();
    bindings.parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"tui.altScreen.top\":\"alt+home\"}", .{ .allocate = .alloc_always });
    var buffer: [128]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(.stdin(), io, &buffer);
    const scene = try Frontend.create(gpa, io, &environ, &reader, &bindings, .{ .header = "native header", .status = "native footer" });
    defer scene.deinit();
    try scene.postEvent(.{ .kind = .message_start, .name = "assistant" });
    try scene.postEvent(.{ .kind = .message_update, .text = "owned update" });
    try scene.setEditorText("draft Ω", null, null);
    try scene.setStatus("provider/model");
    try scene.updateConfigPadded(&bindings, &.{"alt+x"}, 2);
    try scene.applyUpdates();
    try std.testing.expectEqual(@as(u8, 2), scene.editor_padding_x);
    const snapshot = try scene.snapshotEditor(gpa);
    defer gpa.free(snapshot.text);
    try std.testing.expectEqualStrings("draft Ω", snapshot.text);
    try scene.queueCommand(.complete, "tab");
    var command = try scene.readCommand();
    defer command.deinit(gpa);
    try std.testing.expectEqualStrings("draft Ω", command.text);
}

test "fullscreen owner construction event mailboxes and editor snapshots release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ownershipCase, .{});
}

test "fullscreen retained Controller surfaces compose header widgets editor status working frames and footer" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var bindings = keybindings.Manager.init(gpa);
    defer bindings.deinit();
    var buffer: [128]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(.stdin(), io, &buffer);
    const scene = try Frontend.create(gpa, io, &environ, &reader, &bindings, .{});
    defer scene.deinit();
    var controller = try ui.Controller.init(gpa, io, true, 60);
    defer controller.deinit();
    try controller.applyAction("setHeader", "{\"lines\":[\"retained-header\"]}");
    try controller.applyAction("setFooter", "{\"lines\":[\"retained-footer\"]}");
    try controller.applyAction("setWidget", "{\"key\":\"above\",\"lines\":[\"retained-above\"],\"placement\":\"aboveEditor\"}");
    try controller.applyAction("setWidget", "{\"key\":\"below\",\"lines\":[\"retained-below\"],\"placement\":\"belowEditor\"}");
    try controller.applyAction("setStatus", "{\"key\":\"mode\",\"text\":\"plan\"}");
    try controller.applyAction("setWorkingMessage", "{\"message\":\"retained-working\"}");
    try controller.applyAction("setWorkingIndicator", "{\"options\":{\"frames\":[\"A\",\"B\"],\"intervalMs\":40}}");
    try controller.applyAction("setTitle", "{\"title\":\"retained-title\"}");
    controller.bindFrontend(Frontend.surfaceSink, null, scene);
    try controller.flush();
    try scene.setEditorText("retained-draft", null, null);
    try scene.setBusy(true);
    try scene.applyUpdates();
    try scene.draw(.{ .columns = 60, .rows = 20 }, false);
    const lines = scene.app.current_frame.?.lines.items;
    var all: std.ArrayList(u8) = .empty;
    defer all.deinit(gpa);
    for (lines) |line| {
        try all.appendSlice(gpa, line);
        try all.append(gpa, '\n');
    }
    for ([_][]const u8{ "retained-header", "retained-above", "> retained-draft", "retained-below", "mode=plan", "retained-working", "retained-footer" }) |marker| try std.testing.expect(std.mem.indexOf(u8, all.items, marker) != null);
    try std.testing.expectEqualStrings("retained-title", scene.surfaces.title.?);
    try std.testing.expectEqual(@as(usize, 2), scene.surfaces.working_frames.len);
    try std.testing.expect(scene.title_dirty);
}
pub const EditorSnapshot = struct { text: []u8, cursor: usize, revision: u64 };
const OwnedEvent = struct {
    value: agent_loop.AgentEvent,
    preformatted: bool = false,
    fn init(gpa: std.mem.Allocator, event: agent_loop.AgentEvent) !OwnedEvent {
        var owned = event;
        owned.text = try gpa.dupe(u8, event.text);
        errdefer gpa.free(owned.text);
        owned.name = try gpa.dupe(u8, event.name);
        errdefer gpa.free(owned.name);
        owned.id = try gpa.dupe(u8, event.id);
        errdefer gpa.free(owned.id);
        owned.args_json = try gpa.dupe(u8, event.args_json);
        errdefer gpa.free(owned.args_json);
        owned.error_message = if (event.error_message) |value| try gpa.dupe(u8, value) else null;
        owned.final_error = null;
        owned.images = &.{};
        owned.image_b64 = null;
        owned.image_mime = null;
        owned.details_json = null;
        return .{ .value = owned };
    }
    fn deinit(self: *OwnedEvent, gpa: std.mem.Allocator) void {
        gpa.free(self.value.text);
        gpa.free(self.value.name);
        gpa.free(self.value.id);
        gpa.free(self.value.args_json);
        if (self.value.error_message) |value| gpa.free(value);
    }
};
const TextUpdate = struct { text: []u8, cursor: ?usize = null, revision: ?u64 = null };
const ConfigUpdate = struct { bindings_json: ?[]u8, shortcuts: [][]u8, editor_padding_x: ?u8 = null };
const Update = union(enum) {
    event: OwnedEvent,
    branch: []session.SessionEntry,
    surface: ui.SurfaceSnapshot,
    text: TextUpdate,
    status: []u8,
    notice: []u8,
    busy: bool,
    config: ConfigUpdate,
    fn deinit(self: *Update, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .event => |*value| value.deinit(gpa),
            .branch => |entries| {
                for (entries) |*entry| entry.deinit(gpa);
                gpa.free(entries);
            },
            .surface => |*value| value.deinit(),
            .text => |value| gpa.free(value.text),
            .status, .notice => |value| gpa.free(value),
            .busy => {},
            .config => |value| {
                if (value.bindings_json) |json| gpa.free(json);
                for (value.shortcuts) |key| gpa.free(key);
                gpa.free(value.shortcuts);
            },
        }
    }
};
pub const Options = struct {
    header: []const u8 = "pi (pi-zig)",
    status: []const u8 = "idle",
    show_hardware_cursor: bool = false,
    editor_padding_x: u8 = 0,
};

pub const Frontend = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: std.process.Environ.Map,
    reader: *Io.File.Reader,
    bindings: keybindings.Manager,
    editor: Editor,
    decoder: line_editor.InputDecoder,
    transcript: transcript_mod.Transcript,
    scroll: layout.ScrollView,
    app: application.Application,
    root_entries: [7]layout.StackEntry = undefined,
    stack: layout.Stack = undefined,
    thread: ?std.Thread = null,
    mutex: Io.Mutex = .init,
    changed: Io.Condition = .init,
    updates: std.ArrayList(Update) = .empty,
    commands: std.ArrayList(Command) = .empty,
    stopping: bool = false,
    ready: bool = false,
    pause_depth: usize = 0,
    paused: bool = false,
    failure: ?anyerror = null,
    editor_text: []u8 = &.{},
    editor_cursor: usize = 0,
    editor_revision: u64 = 0,
    editor_padding_x: u8 = 0,
    revision: u64 = 0,
    header: []u8,
    status: []u8,
    surfaces: ui.SurfaceSnapshot,
    header_lines: layout.StaticLines = .{ .lines = &.{} },
    above_lines: layout.StaticLines = .{ .lines = &.{} },
    below_lines: layout.StaticLines = .{ .lines = &.{} },
    status_lines: layout.StaticLines = .{ .lines = &.{} },
    footer_lines: layout.StaticLines = .{ .lines = &.{} },
    busy: bool = false,
    abort_flag: bool = false,
    dirty: bool = true,
    anchor: ?transcript_mod.Anchor = null,
    escape_started_ms: ?i64 = null,
    shortcuts: [][]u8 = &.{},
    working_frame: usize = 0,
    title_dirty: bool = false,

    fn create(gpa: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, reader: *Io.File.Reader, bindings: *const keybindings.Manager, options: Options) !*Frontend {
        const self = try gpa.create(Frontend);
        var transferred = false;
        errdefer if (!transferred) gpa.destroy(self);
        const copied_environment = try environ.clone(gpa);
        errdefer if (!transferred) {
            var owned = copied_environment;
            owned.deinit();
        };
        var copied_bindings = keybindings.Manager.init(gpa);
        errdefer if (!transferred) copied_bindings.deinit();
        if (bindings.parsed) |parsed| {
            const encoded = try std.json.Stringify.valueAlloc(gpa, parsed.value, .{});
            defer gpa.free(encoded);
            copied_bindings.parsed = try std.json.parseFromSlice(std.json.Value, gpa, encoded, .{ .allocate = .alloc_always });
        }
        const header = try gpa.dupe(u8, options.header);
        errdefer if (!transferred) gpa.free(header);
        const status = try gpa.dupe(u8, options.status);
        errdefer if (!transferred) gpa.free(status);
        self.* = .{
            .gpa = gpa,
            .io = io,
            .environ = copied_environment,
            .reader = reader,
            .bindings = copied_bindings,
            .editor = Editor.init(gpa),
            .editor_padding_x = @min(options.editor_padding_x, 3),
            .decoder = line_editor.InputDecoder.init(gpa),
            .transcript = transcript_mod.Transcript.init(gpa),
            .scroll = undefined,
            .app = undefined,
            .header = header,
            .status = status,
            .surfaces = .{ .gpa = gpa },
        };
        self.scroll = layout.ScrollView.init(self.transcript.component(), true);
        self.scroll.primary = true;
        self.stack = .{ .axis = .vertical, .entries = &self.root_entries };
        self.app = application.Application.init(gpa, self.stack.component());
        self.app.bindings = &self.bindings;
        self.app.show_hardware_cursor = options.show_hardware_cursor;
        self.app.setFocus(self.editorComponent());
        transferred = true;
        return self;
    }

    pub fn start(gpa: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, reader: *Io.File.Reader, bindings: *const keybindings.Manager, options: Options) !*Frontend {
        if (comptime builtin.os.tag != .linux) return error.UnsupportedTerminal;
        const self = try create(gpa, io, environ, reader, bindings, options);
        errdefer self.deinit();
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        while (!self.ready and self.failure == null) self.changed.waitUncancelable(io, &self.mutex);
        if (self.failure) |err| {
            if (self.thread) |thread| thread.join();
            self.thread = null;
            return err;
        }
        return self;
    }

    fn post(self: *Frontend, update: Update) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |err| return err;
        if (self.updates.items.len >= 4096) return error.FrontendQueueLimit;
        try self.updates.append(self.gpa, update);
        self.changed.broadcast(self.io);
    }
    pub fn postEvent(self: *Frontend, event: agent_loop.AgentEvent) !void {
        var owned = try OwnedEvent.init(self.gpa, event);
        errdefer owned.deinit(self.gpa);
        try self.post(.{ .event = owned });
    }
    pub fn postRenderedToolEvent(self: *Frontend, event: agent_loop.AgentEvent, rendered: []const u8) !void {
        var projected = event;
        projected.text = rendered;
        var owned = try OwnedEvent.init(self.gpa, projected);
        errdefer owned.deinit(self.gpa);
        owned.preformatted = true;
        try self.post(.{ .event = owned });
    }
    pub fn recordFailure(self: *Frontend, err: anyerror) void {
        self.mutex.lockUncancelable(self.io);
        if (self.failure == null) self.failure = err;
        self.stopping = true;
        @atomicStore(bool, &self.abort_flag, true, .release);
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
    }
    pub fn syncBranch(self: *Frontend, source: *const session.Session) !void {
        const branch = try source.branchEntries(self.gpa);
        defer self.gpa.free(branch);
        const copied = try self.gpa.alloc(session.SessionEntry, branch.len);
        var initialized: usize = 0;
        errdefer {
            for (copied[0..initialized]) |*entry| entry.deinit(self.gpa);
            self.gpa.free(copied);
        }
        for (copied, branch) |*entry, original| {
            entry.* = try original.dupe(self.gpa);
            initialized += 1;
        }
        try self.post(.{ .branch = copied });
    }
    pub fn setBusy(self: *Frontend, busy: bool) !void {
        if (busy) @atomicStore(bool, &self.abort_flag, false, .release);
        try self.post(.{ .busy = busy });
    }
    pub fn setStatus(self: *Frontend, status: []const u8) !void {
        const text = try self.gpa.dupe(u8, status);
        errdefer self.gpa.free(text);
        try self.post(.{ .status = text });
    }
    pub fn updateConfig(self: *Frontend, bindings: *const keybindings.Manager, shortcuts: []const []const u8) !void {
        return self.updateConfigPadded(bindings, shortcuts, null);
    }
    pub fn updateConfigPadded(self: *Frontend, bindings: *const keybindings.Manager, shortcuts: []const []const u8, editor_padding_x: ?u8) !void {
        const json = if (bindings.parsed) |parsed| try std.json.Stringify.valueAlloc(self.gpa, parsed.value, .{}) else null;
        errdefer if (json) |value| self.gpa.free(value);
        const copied = try self.gpa.alloc([]u8, shortcuts.len);
        var count: usize = 0;
        errdefer {
            for (copied[0..count]) |key| self.gpa.free(key);
            self.gpa.free(copied);
        }
        for (copied, shortcuts) |*key, source| {
            key.* = try self.gpa.dupe(u8, source);
            count += 1;
        }
        try self.post(.{ .config = .{ .bindings_json = json, .shortcuts = copied, .editor_padding_x = editor_padding_x } });
    }
    pub fn setEditorText(self: *Frontend, text: []const u8, cursor: ?usize, revision: ?u64) !void {
        const owned = try self.gpa.dupe(u8, text);
        errdefer self.gpa.free(owned);
        try self.post(.{ .text = .{ .text = owned, .cursor = cursor, .revision = revision } });
    }
    pub fn snapshotEditor(self: *Frontend, gpa: std.mem.Allocator) !EditorSnapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{ .text = try gpa.dupe(u8, self.editor_text), .cursor = self.editor_cursor, .revision = self.editor_revision };
    }
    pub fn readCommand(self: *Frontend) !Command {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.commands.items.len == 0 and self.failure == null and !self.stopping) self.changed.waitUncancelable(self.io, &self.mutex);
        if (self.failure) |err| return err;
        if (self.commands.items.len == 0) return error.EndOfStream;
        return self.commands.orderedRemove(0);
    }
    pub fn pauseModal(self: *Frontend) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.pause_depth += 1;
        while (!self.paused and self.failure == null) self.changed.waitUncancelable(self.io, &self.mutex);
        if (self.failure) |err| return err;
    }
    pub fn resumeModal(self: *Frontend, outcome: ?anyerror) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (outcome) |err| if (err == error.DeadTerminal) {
            self.failure = error.DeadTerminal;
            self.stopping = true;
        };
        self.pause_depth -|= 1;
        self.changed.broadcast(self.io);
    }
    pub fn modalObserver(raw: ?*anyopaque, event: ui.PromptEvent, outcome: ?anyerror) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        if (event == .start) try self.pauseModal() else try self.resumeModal(outcome);
    }
    pub fn renderModalObserver(raw: ?*anyopaque, start_modal: bool) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        if (start_modal) try self.pauseModal() else try self.resumeModal(null);
    }
    pub fn surfaceSink(raw: ?*anyopaque, surface: ui.SurfaceSnapshot) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        try self.post(.{ .surface = surface });
    }
    pub fn noticeSink(raw: ?*anyopaque, bytes: []const u8) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        const paused = self.paused;
        self.mutex.unlock(self.io);
        if (paused) return Io.File.stdout().writeStreamingAll(self.io, bytes);
        const text = try self.gpa.dupe(u8, bytes);
        errdefer self.gpa.free(text);
        try self.post(.{ .notice = text });
    }
    pub fn stop(self: *Frontend) void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
        if (self.thread) |thread| thread.join();
        self.thread = null;
    }
    pub fn deinit(self: *Frontend) void {
        self.stop();
        for (self.updates.items) |*update| update.deinit(self.gpa);
        self.updates.deinit(self.gpa);
        for (self.commands.items) |*command| command.deinit(self.gpa);
        self.commands.deinit(self.gpa);
        if (self.anchor) |value| self.gpa.free(value.key);
        self.app.deinit();
        self.transcript.deinit();
        self.decoder.deinit();
        self.editor.deinit();
        self.bindings.deinit();
        self.environ.deinit();
        self.surfaces.deinit();
        self.gpa.free(self.editor_text);
        self.gpa.free(self.header);
        self.gpa.free(self.status);
        for (self.shortcuts) |key| self.gpa.free(key);
        self.gpa.free(self.shortcuts);
        const allocator = self.gpa;
        allocator.destroy(self);
    }

    fn publishEditor(self: *Frontend) !void {
        const text = try self.gpa.dupe(u8, self.editor.slice());
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.gpa.free(self.editor_text);
        self.editor_text = text;
        self.editor_cursor = self.editor.cursor;
        self.editor_revision = self.revision;
    }
    fn queueCommand(self: *Frontend, kind: CommandKind, key: []const u8) !void {
        var command: Command = .{ .kind = kind, .text = try self.gpa.dupe(u8, self.editor.slice()), .cursor = self.editor.cursor, .revision = self.revision };
        errdefer self.gpa.free(command.text);
        command.key = try self.gpa.dupe(u8, key);
        errdefer self.gpa.free(command.key);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.commands.append(self.gpa, command);
        self.changed.broadcast(self.io);
    }
    fn editorComponent(self: *Frontend) layout.Component {
        return .{ .context = self, .vtable = &.{ .render = renderEditor, .handle_input = editorInput, .handle_paste = editorPaste } };
    }
    fn renderEditor(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Frontend = @ptrCast(@alignCast(raw));
        return line_editor.renderEditorLinesPadded(gpa, &self.editor, width, self.editor_padding_x);
    }
    fn editorPaste(raw: *anyopaque, bytes: []const u8) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw));
        const normalized = try line_editor.normalizePasteAlloc(self.gpa, bytes);
        defer self.gpa.free(normalized);
        try self.editor.insert(normalized);
        self.revision += 1;
        try self.publishEditor();
        self.dirty = true;
    }
    fn editorInput(raw: *anyopaque, bytes: []const u8) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw));
        if (std.mem.eql(u8, bytes, "\x1b") and self.busy) {
            @atomicStore(bool, &self.abort_flag, true, .release);
            return;
        }
        if (std.mem.eql(u8, bytes, "\t")) {
            try self.queueCommand(.complete, "tab");
            return;
        }
        const disposition = try line_editor.applyInputSequence(self.gpa, &self.editor, &self.bindings, bytes, null);
        switch (disposition) {
            .submit => {
                try self.queueCommand(.submit, "");
                if (self.editor.slice().len > 0) try self.editor.addHistory(self.editor.slice());
                try self.editor.setText("");
            },
            .cancel => if (self.busy) {
                @atomicStore(bool, &self.abort_flag, true, .release);
            } else try self.editor.setText(""),
            .exit => try self.queueCommand(.quit, ""),
            .interrupt, .keep_editing => {},
        }
        self.revision += 1;
        try self.publishEditor();
        self.dirty = true;
    }
    fn applyUpdates(self: *Frontend) !void {
        self.mutex.lockUncancelable(self.io);
        var updates = self.updates;
        self.updates = .empty;
        self.mutex.unlock(self.io);
        defer {
            for (updates.items) |*update| update.deinit(self.gpa);
            updates.deinit(self.gpa);
        }
        if (updates.items.len > 0 and !self.scroll.following_end and self.anchor == null) self.anchor = try self.transcript.anchor(self.scroll.scroll_top);
        for (updates.items) |*update| switch (update.*) {
            .event => |event| try self.transcript.eventWithRendered(event.value, event.preformatted),
            .branch => |entries| try self.transcript.syncBranch(entries, if (self.anchor) |*value| value else null),
            .surface => |snapshot| {
                self.title_dirty = if (snapshot.title) |title| if (self.surfaces.title) |previous| !std.mem.eql(u8, title, previous) else true else false;
                self.surfaces.deinit();
                self.surfaces = snapshot;
                update.* = .{ .busy = self.busy };
                for (snapshot.notifications) |value| try self.transcript.notice(value);
            },
            .notice => |value| if (std.mem.trim(u8, value, " \r\n").len > 0) try self.transcript.notice(std.mem.trim(u8, value, "\r\n")),
            .status => |value| {
                const text = try self.gpa.dupe(u8, value);
                self.gpa.free(self.status);
                self.status = text;
            },
            .text => |value| {
                if (value.revision == null or value.revision.? == self.revision) {
                    try self.editor.setTextAt(value.text, value.cursor orelse value.text.len);
                    self.revision += 1;
                    try self.publishEditor();
                }
            },
            .busy => |value| self.busy = value,
            .config => |value| {
                var bindings = keybindings.Manager.init(self.gpa);
                if (value.bindings_json) |json| bindings.parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, json, .{ .allocate = .alloc_always });
                self.bindings.deinit();
                self.bindings = bindings;
                if (value.editor_padding_x) |padding| self.editor_padding_x = @min(padding, 3);
                for (self.shortcuts) |key| self.gpa.free(key);
                self.gpa.free(self.shortcuts);
                self.shortcuts = value.shortcuts;
                if (value.bindings_json) |json| self.gpa.free(json);
                update.* = .{ .busy = self.busy };
            },
        };
        if (updates.items.len > 0) self.dirty = true;
    }

    fn paint(self: *Frontend) !void {
        const dimensions = terminal.terminalDimensions(&self.environ, .{ .columns = 80, .rows = 24 });
        try self.draw(dimensions, true);
    }
    fn draw(self: *Frontend, dimensions: terminal.Dimensions, write: bool) !void {
        var editor_lines = try line_editor.renderEditorLinesPadded(self.gpa, &self.editor, dimensions.columns, self.editor_padding_x);
        defer editor_lines.deinit(self.gpa);
        const fallback_header = [_][]const u8{self.header};
        const header = if (self.surfaces.header) |lines| lines else &fallback_header;
        const fallback_footer = [_][]const u8{self.status};
        const footer = if (self.surfaces.footer) |lines| lines else &fallback_footer;
        const working = self.busy and self.surfaces.working_visible;
        const frame = self.currentWorkingFrame();
        self.working_frame = frame;
        const glyph = if (working and self.surfaces.working_frames.len > 0) self.surfaces.working_frames[frame] else "";
        const status = try std.fmt.allocPrint(self.gpa, "{s}{s}{s}{s}{s}", .{ glyph, if (glyph.len > 0) " " else "", if (working) self.surfaces.working orelse "Working…" else "", if (working and self.surfaces.status.len > 0) "  " else "", self.surfaces.status });
        defer self.gpa.free(status);
        const statuses = [_][]const u8{status};
        self.header_lines.lines = header;
        self.above_lines.lines = self.surfaces.above;
        self.below_lines.lines = self.surfaces.below;
        self.status_lines.lines = if (status.len > 0) &statuses else &.{};
        self.footer_lines.lines = footer;
        self.root_entries = .{
            .{ .component = self.header_lines.component(), .basis = header.len, .shrink = 0 },
            .{ .component = self.scroll.component(), .grow = 1, .min_size = 1 },
            .{ .component = self.above_lines.component(), .basis = self.surfaces.above.len },
            .{ .component = self.editorComponent(), .basis = @min(editor_lines.items.len, @max(@as(usize, 1), dimensions.rows / 2)), .shrink = 0 },
            .{ .component = self.below_lines.component(), .basis = self.surfaces.below.len },
            .{ .component = self.status_lines.component(), .basis = self.status_lines.lines.len },
            .{ .component = self.footer_lines.component(), .basis = footer.len, .shrink = 0 },
        };
        if (self.anchor) |value| {
            var projected = try self.transcript.component().render(self.gpa, dimensions.columns);
            projected.deinit(self.gpa);
            self.scroll.scrollTo(self.transcript.anchorRow(value), true);
            self.gpa.free(value.key);
            self.anchor = null;
        }
        if (write and self.title_dirty) {
            if (self.surfaces.title) |title| {
                const bytes = try ui.terminalTitleAlloc(self.gpa, title);
                defer self.gpa.free(bytes);
                try application.writeAll(self.io, bytes);
            }
            self.title_dirty = false;
        }
        const bytes = try self.app.renderAnsi(dimensions.columns, dimensions.rows);
        defer self.gpa.free(bytes);
        if (write) try application.writeAll(self.io, bytes);
        self.dirty = false;
    }
    fn currentWorkingFrame(self: *Frontend) usize {
        if (self.surfaces.working_frames.len == 0) return 0;
        const now: u64 = @intCast(@max(@as(i64, 0), Io.Clock.awake.now(self.io).toMilliseconds()));
        return @intCast((now / self.surfaces.working_interval_ms) % self.surfaces.working_frames.len);
    }

    fn run(self: *Frontend) void {
        self.runLoop() catch |err| {
            self.mutex.lockUncancelable(self.io);
            self.failure = err;
            self.ready = true;
            self.changed.broadcast(self.io);
            self.mutex.unlock(self.io);
        };
    }
    fn input(self: *Frontend, packet: line_editor.InputDecoder.Input) !void {
        switch (packet) {
            .paste => |value| try self.app.handlePaste(value),
            .key => |sequence| {
                if (keys.parseKeyWithOptions(sequence, .{ .kitty_active = true })) |key| {
                    if (key.event_type == .release) return;
                    const name = try key.formatAlloc(self.gpa);
                    defer self.gpa.free(name);
                    for (self.shortcuts) |shortcut| if (std.ascii.eqlIgnoreCase(shortcut, name)) {
                        try self.queueCommand(.shortcut, name);
                        return;
                    };
                    if (self.bindings.matches(name, .clipboard_paste)) {
                        try self.queueCommand(.clipboard, name);
                        return;
                    }
                }
                try self.app.handleInput(sequence);
            },
        }
        self.dirty = true;
    }
    fn runLoop(self: *Frontend) !void {
        var raw = try line_editor.RawMode.enter();
        var raw_active = true;
        defer if (raw_active) raw.leave();
        try self.app.start(self.io);
        var terminal_alive = true;
        defer if (terminal_alive) self.app.stop(self.io) catch {};
        self.mutex.lockUncancelable(self.io);
        self.ready = true;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
        try self.publishEditor();
        while (true) {
            self.mutex.lockUncancelable(self.io);
            const stopping = self.stopping;
            const wanted_pause = self.pause_depth > 0;
            self.mutex.unlock(self.io);
            if (stopping) break;
            if (wanted_pause and !self.paused) {
                try self.app.stop(self.io);
                raw.leave();
                raw_active = false;
                self.mutex.lockUncancelable(self.io);
                self.paused = true;
                self.changed.broadcast(self.io);
                self.mutex.unlock(self.io);
            } else if (!wanted_pause and self.paused) {
                raw = try line_editor.RawMode.enter();
                raw_active = true;
                try self.app.start(self.io);
                self.app.invalidatePaint();
                self.mutex.lockUncancelable(self.io);
                self.paused = false;
                self.mutex.unlock(self.io);
                self.dirty = true;
            }
            try self.applyUpdates();
            if (wanted_pause) {
                try self.io.sleep(.fromMilliseconds(10), .awake);
                continue;
            }
            const size = terminal.terminalDimensions(&self.environ, .{ .columns = 80, .rows = 24 });
            if (size.columns != self.app.painted_width or size.rows != self.app.painted_height) self.dirty = true;
            if (self.busy and self.surfaces.working_visible and self.currentWorkingFrame() != self.working_frame) self.dirty = true;
            if (self.dirty) try self.paint();
            var descriptor: std.os.linux.pollfd = .{ .fd = Io.File.stdin().handle, .events = std.os.linux.POLL.IN, .revents = 0 };
            const buffered = self.reader.interface.seek < self.reader.interface.end;
            const result = std.os.linux.poll(@ptrCast(&descriptor), 1, if (buffered) 0 else 10);
            if (std.os.linux.errno(result) != .SUCCESS and std.os.linux.errno(result) != .INTR) return error.TerminalPollFailed;
            if (descriptor.revents & (std.os.linux.POLL.HUP | std.os.linux.POLL.ERR) != 0) {
                terminal_alive = false;
                raw.restore = false;
                return error.DeadTerminal;
            }
            if (descriptor.revents & std.os.linux.POLL.IN != 0 or self.reader.interface.seek < self.reader.interface.end) {
                const byte = self.reader.interface.takeByte() catch |err| {
                    const actual = line_editor.terminalInputError(err, self.reader.err);
                    if (actual == error.DeadTerminal) {
                        terminal_alive = false;
                        raw.restore = false;
                        return error.DeadTerminal;
                    }
                    return err;
                };
                if (byte == 0x1b and (self.decoder.pending.items.len == 0 or self.decoder.delivered)) self.escape_started_ms = Io.Clock.awake.now(self.io).toMilliseconds();
                if (try self.decoder.feed(byte)) |packet| {
                    try self.input(packet);
                    self.escape_started_ms = null;
                }
            } else if (self.escape_started_ms) |started| {
                if (Io.Clock.awake.now(self.io).toMilliseconds() - started >= 30) {
                    if (self.decoder.flushEscape()) |packet| try self.input(packet);
                    self.escape_started_ms = null;
                }
            }
        }
    }
};

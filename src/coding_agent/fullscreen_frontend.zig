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
const platform = @import("../tui/platform_terminal.zig");
const component_protocol = @import("../extensions/component_protocol.zig");
pub const renderer_protocol = @import("../extensions/renderer_protocol.zig");

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

fn rendererOwnershipCase(gpa: std.mem.Allocator) !void {
    const io = std.testing.io;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var bindings = keybindings.Manager.init(gpa);
    defer bindings.deinit();
    var buffer: [128]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(.stdin(), io, &buffer);
    const owner = try Frontend.create(gpa, io, &environ, &reader, &bindings, .{});
    defer owner.deinit();
    var queue = renderer_protocol.ControlQueue.init(gpa, io, 1);
    var queue_alive = true;
    defer if (queue_alive) queue.deinit();
    const prefix = "\"version\":1,\"ownerGeneration\":\"1\",\"extensionId\":\"2\",\"rowGeneration\":\"3\",\"toolCallId\":\"owned-tool\",\"width\":80";
    const records = [_][]const u8{
        "{" ++ prefix ++ ",\"type\":\"renderer_register\",\"toolName\":\"paint\"}",
        "{" ++ prefix ++ ",\"type\":\"renderer_frame\",\"slot\":\"call\",\"sequence\":\"1\",\"revision\":\"1\",\"lines\":[\"old-renderer\"]}",
        "{" ++ prefix ++ ",\"type\":\"renderer_frame\",\"slot\":\"call\",\"sequence\":\"2\",\"revision\":\"2\",\"lines\":[\"new-renderer\"]}",
    };
    try owner.postEvent(.{ .kind = .tool_execution_start, .id = "owned-tool", .name = "paint", .args_json = "canonical-call" });
    for (records) |source| {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, source, .{});
        defer parsed.deinit();
        var record = try renderer_protocol.read(gpa, &parsed.value.object);
        var transferred = false;
        defer if (!transferred) record.deinit();
        try Frontend.rendererSink(owner, record, &queue);
        transferred = true;
    }
    try std.testing.expectEqual(@as(usize, 2), owner.renderer_record_count);
    try owner.applyUpdates();
    try std.testing.expectEqualStrings("new-renderer", owner.transcript.renderers.find("owned-tool").?.lines(.call, 80).?[0]);
    try owner.draw(.{ .columns = 70, .rows = 24 }, false);
    try std.testing.expectEqual(@as(usize, 1), queue.controls.items.len);
    try std.testing.expectEqual(@as(usize, 70), queue.controls.items[0].kind.resize);
    try Frontend.rendererClosed(owner, 1);
    try std.testing.expect(owner.renderer_owners.items[0].controls == null);
    queue.deinit();
    queue_alive = false;
    // The borrowed queue is already gone before the paint owner consumes the
    // retirement; pending owned DTOs and canonical fallback remain safe.
    try owner.applyUpdates();
    try std.testing.expect(owner.transcript.renderers.find("owned-tool").?.retired);
    try owner.draw(.{ .columns = 70, .rows = 24 }, false);
}

test "fullscreen renderer mailbox coalesces slots sends resize and detaches before queue free under every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, rendererOwnershipCase, .{});
}

fn componentOwnershipCase(gpa: std.mem.Allocator) !void {
    const io = std.testing.io;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var bindings = keybindings.Manager.init(gpa);
    defer bindings.deinit();
    var buffer: [128]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(.stdin(), io, &buffer);
    var queue = component_protocol.ControlQueue.init(gpa, io);
    defer queue.deinit();
    var controller = try ui.Controller.init(gpa, io, true, 80);
    defer controller.deinit();
    const frontend = try Frontend.create(gpa, io, &environ, &reader, &bindings, .{});
    defer frontend.deinit();
    controller.bindEditorFrontend(Frontend.editorSink, frontend);
    frontend.bindEditorObserver(ui.Controller.frontendEditorSnapshot, &controller);
    try controller.applyAction("setEditorText", "{\"text\":\"saved component draft\"}");
    try frontend.applyUpdates();
    try std.testing.expect(controller.pending_editor_text == null);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, "{\"version\":1,\"token\":1,\"generation\":2,\"invocationId\":3,\"componentId\":4,\"width\":80,\"height\":24,\"lines\":[\"component owned bytes\"],\"overlay\":null}", .{});
    defer parsed.deinit();
    var dto = try component_protocol.readScene(gpa, &parsed.value.object);
    var transferred = false;
    defer if (!transferred) dto.deinit();
    queue.reset(dto.fence);
    try Frontend.componentSink(frontend, dto, &queue);
    transferred = true;
    try frontend.applyUpdates();
    try frontend.draw(.{ .columns = 80, .rows = 24 }, false);
    try std.testing.expect(std.mem.indexOf(u8, frontend.app.current_frame.?.lines.items[0], "component owned bytes") != null);
    try frontend.input(.{ .key = "owned input" });
    // The real dimensions may first produce a resize; consume through input.
    while (try queue.next()) |control| {
        var owned = control;
        defer owned.deinit();
        if (owned.kind == .input) {
            try std.testing.expectEqualStrings("owned input", owned.kind.input);
            break;
        }
    }
    try std.testing.expectEqualStrings("saved component draft", frontend.editor.slice());
    var stale = dto.fence;
    stale.invocation_id += 1;
    try std.testing.expectError(error.StaleNativeComponentScene, frontend.removeCustomComponent(stale));
    try frontend.removeCustomComponent(dto.fence);
    try std.testing.expect(frontend.component_controls == null);
    try std.testing.expect(frontend.closed_component == null);
    try frontend.draw(.{ .columns = 80, .rows = 24 }, false);
    try std.testing.expect(frontend.closed_component.?.matches(dto.fence));
    try std.testing.expectEqualStrings("saved component draft", frontend.editor.slice());
}

test "fullscreen native component scene input and restored frame release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, componentOwnershipCase, .{});
}

test "fullscreen startup failure joins owner without holding its cleanup mutex" {
    const io = std.testing.io;
    if (try Io.File.stdin().isTty(io)) return error.SkipZigTest;
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    var buffer: [128]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(.stdin(), io, &buffer);
    try std.testing.expectError(error.DeadTerminal, Frontend.start(std.testing.allocator, io, &environ, &reader, &bindings, .{}));
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
    component: struct { scene: component_protocol.Scene, controls: *component_protocol.ControlQueue },
    component_close: component_protocol.Fence,
    renderer: renderer_protocol.Record,
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
            .component => |*value| value.scene.deinit(),
            .renderer => |*record| record.deinit(),
            .component_close => {},
        }
    }
};
pub const Options = struct {
    header: []const u8 = "pi (pi-zig)",
    status: []const u8 = "idle",
    show_hardware_cursor: bool = false,
    editor_padding_x: u8 = 0,
};

const RendererOwner = struct {
    generation: u64,
    controls: ?*renderer_protocol.ControlQueue,
    closed: bool = false,
    retired: bool = false,
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
    input_batch_active: bool = false,
    renderer_owners: std.ArrayList(RendererOwner) = .empty,
    renderer_record_count: usize = 0,
    renderer_record_bytes: usize = 0,
    renderer_retire_pending: bool = false,
    renderer_width: std.atomic.Value(usize) = .init(80),
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
    component: ?component_protocol.Scene = null,
    component_controls: ?*component_protocol.ControlQueue = null,
    component_overlay_id: ?u64 = null,
    close_pending: ?component_protocol.Fence = null,
    closed_component: ?component_protocol.Fence = null,
    component_close_request: ?component_protocol.Fence = null,
    component_dimensions: ?terminal.Dimensions = null,
    observed_dimensions: terminal.Dimensions = .{ .columns = 0, .rows = 0 },
    editor_observer: ?ui.EditorSinkFn = null,
    editor_observer_context: ?*anyopaque = null,
    worker_finished: bool = false,

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
        if (comptime builtin.os.tag != .linux and builtin.os.tag != .windows and builtin.os.tag != .macos) return error.UnsupportedTerminal;
        const self = try create(gpa, io, environ, reader, bindings, options);
        errdefer self.deinit();
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        self.mutex.lockUncancelable(io);
        while (!self.ready and self.failure == null) self.changed.waitUncancelable(io, &self.mutex);
        const startup_failure = self.failure;
        self.mutex.unlock(io);
        if (startup_failure) |err| {
            // The owner finishes detaching borrowed channels under this mutex.
            // Never join while holding the lock it needs for terminal cleanup.
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
        if (self.stopping) return error.EndOfStream;
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
        while ((self.commands.items.len == 0 or self.input_batch_active) and self.failure == null and !self.stopping) self.changed.waitUncancelable(self.io, &self.mutex);
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
    pub fn editorSink(raw: ?*anyopaque, text: []const u8) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        try self.setEditorText(text, null, null);
    }
    pub fn bindEditorObserver(self: *Frontend, callback: ?ui.EditorSinkFn, context: ?*anyopaque) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.editor_observer = callback;
        self.editor_observer_context = context;
    }
    pub fn componentSink(raw: ?*anyopaque, scene: component_protocol.Scene, controls: *component_protocol.ControlQueue) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        try self.post(.{ .component = .{ .scene = scene, .controls = controls } });
    }
    pub fn rendererWidth(self: *Frontend) usize {
        return self.renderer_width.load(.acquire);
    }
    pub fn rendererSink(raw: ?*anyopaque, record: renderer_protocol.Record, controls: *renderer_protocol.ControlQueue) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |err| return err;
        if (self.stopping or self.worker_finished) return error.RendererFrontendStopped;
        if (controls.owner_generation != record.fence.owner_generation) return error.StaleRendererOwner;
        var owner: ?*RendererOwner = null;
        for (self.renderer_owners.items) |*value| if (value.generation == record.fence.owner_generation) {
            owner = value;
            break;
        };
        if (owner) |value| if (value.closed or value.controls != controls) return error.RendererOwnerClosed;
        var added_owner = false;
        if (owner == null) {
            if (self.renderer_owners.items.len >= renderer_protocol.maximum_records) return error.RendererOwnerLimit;
            try self.renderer_owners.append(self.gpa, .{ .generation = record.fence.owner_generation, .controls = controls });
            added_owner = true;
        }
        errdefer if (added_owner) {
            _ = self.renderer_owners.pop();
        };
        if (record.kind == .frame) {
            var index = self.updates.items.len;
            while (index > 0) {
                index -= 1;
                if (self.updates.items[index] != .renderer) continue;
                const old = &self.updates.items[index].renderer;
                if (!renderer_protocol.Fence.matches(old.fence, record.fence)) continue;
                if (old.kind != .frame) break;
                if (old.kind.frame.slot != record.kind.frame.slot) continue;
                if (old.kind.frame.sequence >= record.kind.frame.sequence or old.kind.frame.revision > record.kind.frame.revision) return error.StaleRendererFrame;
                const kept = self.renderer_record_bytes - old.bytes();
                if (record.bytes() > renderer_protocol.maximum_queue_bytes - kept) return error.RendererMailboxLimit;
                old.deinit();
                old.* = record;
                self.renderer_record_bytes = kept + record.bytes();
                return;
            }
        }
        if (self.renderer_record_count >= renderer_protocol.maximum_records or record.bytes() > renderer_protocol.maximum_queue_bytes - self.renderer_record_bytes) return error.RendererMailboxLimit;
        try self.updates.append(self.gpa, .{ .renderer = record });
        self.renderer_record_count += 1;
        self.renderer_record_bytes += record.bytes();
        self.changed.broadcast(self.io);
    }
    pub fn rendererClosed(raw: ?*anyopaque, generation: u64) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        // This registry is the only borrowed queue location. Pending records
        // and transcript frames own their data. Detach before ACK even after
        // paint failure or while a standard modal owns terminal output.
        for (self.renderer_owners.items) |*owner| if (owner.generation == generation) {
            owner.controls = null;
            owner.closed = true;
            self.renderer_retire_pending = true;
            self.changed.broadcast(self.io);
            return;
        };
    }
    fn rendererOwnerActive(self: *Frontend, generation: u64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.renderer_owners.items) |owner| if (owner.generation == generation) return !owner.closed;
        return false;
    }
    fn resizeRenderers(self: *Frontend, width: usize) !void {
        for (self.transcript.renderers.rows.items) |*row| {
            if (row.retired and !row.needs_retire) continue;
            if (!row.needs_retire and (row.requested_width == width or !self.transcript.hasToolRow(row.fence.tool_call_id))) continue;
            var needs_width = row.width != width;
            for (row.slots) |slot| if (slot) |value| {
                if (value.width != width) needs_width = true;
            };
            if (!needs_width and !row.needs_retire) continue;
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            const controls = for (self.renderer_owners.items) |owner| {
                if (owner.generation == row.fence.owner_generation and !owner.closed) break owner.controls;
            } else null;
            const queue = controls orelse continue;
            var control: renderer_protocol.Control = .{ .gpa = self.gpa, .fence = row.fence, .kind = if (row.needs_retire) .retire else .{ .resize = width } };
            control.fence.tool_call_id = try self.gpa.dupe(u8, row.fence.tool_call_id);
            queue.send(control) catch |err| {
                control.deinit();
                if (err == error.RendererMailboxStopped) continue;
                return err;
            };
            row.requested_width = width;
            row.needs_retire = false;
        }
    }
    pub fn componentClose(raw: ?*anyopaque, fence: component_protocol.Fence) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        // Allocation-free close admission also works under mailbox OOM/full.
        self.component_close_request = fence;
        self.changed.broadcast(self.io);
        while (true) {
            if (self.closed_component) |closed| if (closed.matches(fence)) {
                if (self.failure) |err| return err;
                return;
            };
            // A terminal failure still requires the UI owner to detach the
            // borrowed queue before Runtime can release the custom session.
            if (self.worker_finished) return error.NativeComponentFrontendStopped;
            self.changed.waitUncancelable(self.io, &self.mutex);
        }
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
        self.renderer_owners.deinit(self.gpa);
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
        if (self.component) |*scene| scene.deinit();
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
        self.gpa.free(self.editor_text);
        self.editor_text = text;
        self.editor_cursor = self.editor.cursor;
        self.editor_revision = self.revision;
        const callback = self.editor_observer;
        const context = self.editor_observer_context;
        self.mutex.unlock(self.io);
        // Pure owned-state publication, never a Session/Host or JS callback.
        // Release the owner mutex first to avoid the Controller→mailbox inverse.
        if (callback) |notify| try notify(context, self.editor.slice());
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
    fn customComponent(self: *Frontend) layout.Component {
        return .{ .context = self, .vtable = &.{ .render = renderCustomComponent } };
    }
    fn renderCustomComponent(raw: *anyopaque, gpa: std.mem.Allocator, _: usize) !layout.RenderedLines {
        const self: *Frontend = @ptrCast(@alignCast(raw));
        const scene = self.component orelse return .{};
        return layout.RenderedLines.clone(gpa, scene.frame.lines);
    }
    fn removeCustomComponent(self: *Frontend, fence: component_protocol.Fence) !void {
        if (self.component) |scene| {
            if (!scene.fence.matches(fence)) return error.StaleNativeComponentScene;
            if (self.component_overlay_id) |id| _ = self.app.removeOverlay(id);
            self.component_overlay_id = null;
            self.app.root = self.stack.component();
            self.app.setFocus(self.editorComponent());
            var owned = scene;
            owned.deinit();
            self.component = null;
        }
        self.mutex.lockUncancelable(self.io);
        self.component_controls = null;
        self.component_dimensions = null;
        self.close_pending = fence;
        self.mutex.unlock(self.io);
        self.app.invalidatePaint();
        self.dirty = true;
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
        self.renderer_record_count = 0;
        self.renderer_record_bytes = 0;
        const retire_renderers = self.renderer_retire_pending;
        self.renderer_retire_pending = false;
        const requested_close = self.component_close_request;
        self.component_close_request = null;
        self.mutex.unlock(self.io);
        defer {
            for (updates.items) |*update| update.deinit(self.gpa);
            updates.deinit(self.gpa);
        }
        if ((updates.items.len > 0 or retire_renderers) and !self.scroll.following_end and self.anchor == null) self.anchor = try self.transcript.anchor(self.scroll.scroll_top);
        if (retire_renderers) {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            for (self.renderer_owners.items) |*owner| if (owner.closed and !owner.retired) {
                if (self.transcript.closeRendererOwner(owner.generation)) self.dirty = true;
                owner.retired = true;
            };
        }
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
            .component => |value| {
                if (self.component) |scene| if (!scene.fence.matches(value.scene.fence)) return error.StaleNativeComponentScene;
                if (self.component_overlay_id) |id| _ = self.app.removeOverlay(id);
                self.component_overlay_id = null;
                if (self.component) |*scene| scene.deinit();
                self.component = value.scene;
                self.mutex.lockUncancelable(self.io);
                self.component_controls = value.controls;
                self.closed_component = null;
                self.mutex.unlock(self.io);
                update.* = .{ .busy = self.busy };
                if (value.scene.overlay) |overlay| {
                    self.app.root = self.stack.component();
                    self.app.setFocus(if (value.scene.focus_mode == .none) null else self.editorComponent());
                    if (!overlay.hidden) self.component_overlay_id = try self.app.pushOverlay(self.customComponent(), .{ .width = overlay.width, .height = overlay.height, .placement = .{ .absolute = .{ .x = @intCast(overlay.column), .y = @intCast(overlay.row) } }, .modal = value.scene.focused });
                } else {
                    self.app.root = self.customComponent();
                    self.app.setFocus(switch (value.scene.focus_mode) {
                        .custom => self.customComponent(),
                        .editor => self.editorComponent(),
                        .none => null,
                    });
                }
                self.app.invalidatePaint();
                try self.resizeComponent(terminal.terminalDimensions(&self.environ, .{ .columns = 80, .rows = 24 }));
            },
            .component_close => |fence| try self.removeCustomComponent(fence),
            .renderer => |*record| {
                if (self.rendererOwnerActive(record.fence.owner_generation)) _ = try self.transcript.adoptRenderer(record);
            },
        };
        if (requested_close) |fence| try self.removeCustomComponent(fence);
        if (updates.items.len > 0) self.dirty = true;
    }

    fn paint(self: *Frontend) !void {
        const dimensions = terminal.terminalDimensions(&self.environ, .{ .columns = 80, .rows = 24 });
        try self.draw(dimensions, true);
    }
    fn resizeComponent(self: *Frontend, size: terminal.Dimensions) !void {
        const scene = self.component orelse return;
        const queue = self.component_controls orelse return;
        if (self.component_dimensions) |previous| {
            if (previous.columns == size.columns and previous.rows == size.rows) return;
        } else if (scene.width == size.columns and scene.height == size.rows) {
            self.component_dimensions = size;
            return;
        }
        try queue.send(.{ .gpa = self.gpa, .fence = scene.fence, .kind = .{ .resize = .{ .width = size.columns, .height = size.rows } } });
        self.component_dimensions = size;
    }
    fn draw(self: *Frontend, dimensions: terminal.Dimensions, write: bool) !void {
        self.renderer_width.store(dimensions.columns, .release);
        try self.resizeRenderers(dimensions.columns);
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
            .{ .component = self.scroll.component(), .basis = 1, .grow = 1, .min_size = 1 },
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
        self.mutex.lockUncancelable(self.io);
        if (self.close_pending) |fence| {
            self.closed_component = fence;
            self.close_pending = null;
            self.changed.broadcast(self.io);
        }
        self.mutex.unlock(self.io);
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
        if (self.component) |scene| self.removeCustomComponent(scene.fence) catch {};
        self.mutex.lockUncancelable(self.io);
        // No borrowed Runtime queue survives a worker stop, including a frame
        // admitted immediately before shutdown but not yet presented.
        for (self.updates.items) |*update| if (update.* == .component) {
            update.deinit(self.gpa);
            update.* = .{ .busy = false };
        };
        self.component_controls = null;
        for (self.renderer_owners.items) |*owner| {
            owner.controls = null;
            owner.closed = true;
        }
        if (self.close_pending) |fence| {
            self.closed_component = fence;
            self.close_pending = null;
        }
        self.worker_finished = true;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
    }
    fn input(self: *Frontend, packet: line_editor.InputDecoder.Input) !void {
        if (self.component) |scene| if (scene.focus_mode == .none) return;
        if (self.component) |scene| if (scene.focused and (scene.overlay == null or !scene.overlay.?.hidden)) {
            const queue = self.component_controls orelse return error.NativeComponentChannelClosed;
            const owned = switch (packet) {
                .key => |value| blk: {
                    if (keys.parseKeyWithOptions(value, .{ .kitty_active = true })) |key| {
                        if (key.event_type == .release) {
                            const wants_release = if (comptime @hasField(component_protocol.Scene, "wants_key_release")) scene.wants_key_release else false;
                            if (!wants_release) return;
                        }
                    }
                    break :blk try self.gpa.dupe(u8, value);
                },
                .paste => |value| try std.fmt.allocPrint(self.gpa, "\x1b[200~{s}\x1b[201~", .{value}),
            };
            errdefer self.gpa.free(owned);
            try queue.send(.{ .gpa = self.gpa, .fence = scene.fence, .target_id = scene.target_id, .target_generation = scene.target_generation, .kind = .{ .input = owned } });
            return;
        };
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
    fn finishInputBatch(self: *Frontend) void {
        self.mutex.lockUncancelable(self.io);
        self.input_batch_active = false;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
    }
    fn readInputBatch(self: *Frontend) !void {
        // Publish commands only after consuming the bytes already ready for
        // this keyboard burst. Otherwise Main can open a modal at CR and steal
        // its trailing draft bytes from the shared reader. Bound a transaction
        // so a continuous input producer cannot starve shutdown or resize.
        self.mutex.lockUncancelable(self.io);
        self.input_batch_active = true;
        self.mutex.unlock(self.io);
        defer self.finishInputBatch();
        var count: usize = 0;
        while (count < 256) : (count += 1) {
            const byte = (platform.pollByte(self.reader) catch |err| {
                return line_editor.terminalInputError(err, self.reader.err);
            }) orelse break;
            if (byte == 0x1b and (self.decoder.pending.items.len == 0 or self.decoder.delivered)) self.escape_started_ms = Io.Clock.awake.now(self.io).toMilliseconds();
            if (try self.decoder.feed(byte)) |packet| {
                try self.input(packet);
                self.escape_started_ms = null;
            }
            if (!platform.inputBuffered(self.reader) and try platform.waitInput(0) != .input) break;
        }
        if (self.dirty) try self.paint();
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
            if (size.columns != self.observed_dimensions.columns or size.rows != self.observed_dimensions.rows) {
                self.observed_dimensions = size;
                self.dirty = true;
                try self.resizeComponent(size);
            }
            if (self.busy and self.surfaces.working_visible and self.currentWorkingFrame() != self.working_frame) self.dirty = true;
            if (self.dirty) try self.paint();
            const buffered = platform.inputBuffered(self.reader);
            const ready = try platform.waitInput(if (buffered) 0 else 10);
            if (ready == .dead) {
                terminal_alive = false;
                raw.restore = false;
                return error.DeadTerminal;
            }
            if (ready == .input or platform.inputBuffered(self.reader)) {
                self.readInputBatch() catch |err| {
                    const actual = line_editor.terminalInputError(err, self.reader.err);
                    if (actual == error.DeadTerminal) {
                        terminal_alive = false;
                        raw.restore = false;
                        return error.DeadTerminal;
                    }
                    return err;
                };
            } else if (self.escape_started_ms) |started| {
                if (Io.Clock.awake.now(self.io).toMilliseconds() - started >= 30) {
                    if (self.decoder.flushEscape()) |packet| try self.input(packet);
                    self.escape_started_ms = null;
                }
            }
        }
    }
};

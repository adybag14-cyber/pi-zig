//! Persistent fullscreen owner. Main retains Session/Host; this thread owns TTY.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const application = @import("../tui/application.zig");
const layout = @import("../tui/layout.zig");
const terminal = @import("../tui/terminal.zig");
const keys = @import("../tui/keys.zig");
const mouse_input = @import("../tui/mouse.zig");
const wheel_scroll = @import("../tui/wheel_scroll.zig");
const keybindings = @import("../tui/keybindings.zig");
const line_editor = @import("../tui/line_editor.zig");
const Editor = @import("../tui/editor.zig").Editor;
const session = @import("../agent/session.zig");
const agent_loop = @import("../agent/loop.zig");
const status_reporter = @import("program_status_reporter.zig");
const ui = @import("../extensions/ui.zig");
const transcript_mod = @import("transcript_view.zig");
const platform = @import("../tui/platform_terminal.zig");
const component_protocol = @import("../extensions/component_protocol.zig");
pub const renderer_protocol = @import("../extensions/renderer_protocol.zig");

pub const CommandKind = enum { submit, complete, shortcut, clipboard, presentation, quit };
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
    try Frontend.dialogStatus(scene, .start, "confirm", "Owned title Ω");
    try Frontend.dialogStatus(scene, .end, "confirm", "Owned title Ω");
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

fn customEditorOwnershipCase(gpa: std.mem.Allocator) !void {
    const io = std.testing.io;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var bindings = keybindings.Manager.init(gpa);
    defer bindings.deinit();
    var buffer: [128]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(.stdin(), io, &buffer);
    const scene = try Frontend.create(gpa, io, &environ, &reader, &bindings, .{});
    defer scene.deinit();
    var controls = editor_protocol.ControlQueue.init(gpa, io, 3);
    defer controls.deinit();
    const prefix = "\"version\":1,\"ownerGeneration\":\"3\",\"extensionId\":\"2\",\"editorGeneration\":\"1\"";
    const records = [_][]const u8{
        "{" ++ prefix ++ ",\"type\":\"editor_frame\",\"sequence\":\"1\",\"width\":55,\"text\":\"draft Ω\",\"lines\":[\"CUSTOM:55\",\"draft Ω\"]}",
        "{" ++ prefix ++ ",\"type\":\"editor_submit\",\"sequence\":\"2\",\"text\":\"submitted Ω🦊\"}",
    };
    for (records) |raw| {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
        defer parsed.deinit();
        var record = try editor_protocol.read(gpa, &parsed.value.object);
        var transferred = false;
        defer if (!transferred) record.deinit();
        try Frontend.editorRecordSink(scene, record, &controls);
        transferred = true;
        try scene.applyUpdates();
    }
    var rendered = try Frontend.renderEditor(scene, gpa, 55);
    defer rendered.deinit(gpa);
    try std.testing.expectEqualStrings("CUSTOM:55", rendered.items[0]);
    var submitted = try scene.readCommand();
    defer submitted.deinit(gpa);
    try std.testing.expectEqualStrings("submitted Ω🦊", submitted.text);
    try std.testing.expectEqual(CommandKind.submit, submitted.kind);
    try Frontend.editorInput(scene, "🦊");
    var received = (try controls.next()).?;
    defer received.deinit();
    try std.testing.expectEqualStrings("🦊", received.kind.input);
    try Frontend.editorClosed(scene, 3);
    controls.stop();
    try std.testing.expect(scene.custom_editor_controls == null);
    try scene.applyUpdates();
    try std.testing.expect(scene.custom_editor_frame == null);
    const snapshot = try scene.snapshotEditor(gpa);
    defer gpa.free(snapshot.text);
    try std.testing.expectEqualStrings("submitted Ω🦊", snapshot.text);
}
test "custom editor frontend owns frames submission snapshots and all failed allocations while detaching borrowed close channels" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, customEditorOwnershipCase, .{});
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

fn widgetFrontendOwnershipCase(gpa: std.mem.Allocator) !void {
    const io = std.testing.io;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var bindings = keybindings.Manager.init(gpa);
    defer bindings.deinit();
    var buffer: [128]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(.stdin(), io, &buffer);
    const owner = try Frontend.create(gpa, io, &environ, &reader, &bindings, .{});
    defer owner.deinit();
    var controls: widget_protocol.ControlQueue = .{ .io = io };
    defer controls.stop();
    var value = try std.json.parseFromSlice(std.json.Value, gpa, "{\"type\":\"widget_record\",\"version\":1,\"ownerGeneration\":\"3\",\"generation\":\"1\",\"sequence\":\"1\",\"width\":80,\"placement\":\"belowEditor\",\"key\":\"owned\",\"lines\":[\"ACTUAL_WIDGET:80\"]}", .{});
    defer value.deinit();
    var record = try widget_protocol.read(gpa, &value.value.object);
    var transferred = false;
    defer if (!transferred) record.deinit();
    try Frontend.widgetRecordSink(owner, record, &controls);
    transferred = true;
    try owner.applyUpdates();
    try std.testing.expectEqual(@as(usize, 1), owner.widgets.items.len);
    try owner.draw(.{ .columns = 70, .rows = 24 }, false);
    try std.testing.expectEqual(@as(usize, 70), controls.pending.?.width);
    try Frontend.widgetClosed(owner, 3);
    try std.testing.expect(owner.widget_owners.items[0].controls == null);
    controls.stop();
    try owner.applyUpdates();
    try std.testing.expectEqual(@as(usize, 0), owner.widgets.items.len);
    try owner.draw(.{ .columns = 70, .rows = 24 }, false);
}
test "native widget frontend frames resizing and borrowed owner retirement release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, widgetFrontendOwnershipCase, .{});
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
const editor_protocol = @import("../extensions/editor_protocol.zig");
const widget_protocol = @import("../extensions/widget_protocol.zig");
const script_runtime = @import("../extensions/js_runtime.zig");
const Update = union(enum) {
    event: OwnedEvent,
    branch: []session.SessionEntry,
    surface: ui.SurfaceSnapshot,
    text: TextUpdate,
    status: []u8,
    notice: []u8,
    busy: bool,
    wheel_lines: wheel_scroll.Lines,
    program_session_name: []u8,
    program_settled: bool,
    program_dialog: struct { title: []u8, kind: ?@import("../tui/program_status.zig").Kind },
    config: ConfigUpdate,
    component: struct { scene: component_protocol.Scene, controls: *component_protocol.ControlQueue },
    component_close: component_protocol.Fence,
    renderer: renderer_protocol.Record,
    custom_editor: editor_protocol.Record,
    widget: widget_protocol.Record,
    fn deinit(self: *Update, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .event => |*value| value.deinit(gpa),
            .branch => |entries| {
                for (entries) |*entry| entry.deinit(gpa);
                gpa.free(entries);
            },
            .surface => |*value| value.deinit(),
            .text => |value| gpa.free(value.text),
            .status, .notice, .program_session_name => |value| gpa.free(value),
            .busy, .program_settled, .wheel_lines => {},
            .program_dialog => |value| gpa.free(value.title),
            .config => |value| {
                if (value.bindings_json) |json| gpa.free(json);
                for (value.shortcuts) |key| gpa.free(key);
                gpa.free(value.shortcuts);
            },
            .component => |*value| value.scene.deinit(),
            .renderer => |*record| record.deinit(),
            .custom_editor => |*record| record.deinit(),
            .widget => |*record| record.deinit(),
            .component_close => {},
        }
    }
};
pub const Options = struct {
    fullscreen_wheel_scroll_lines: wheel_scroll.Lines = .auto,
    header: []const u8 = "pi (pi-zig)",
    status: []const u8 = "idle",
    show_hardware_cursor: bool = false,
    editor_padding_x: u8 = 0,
    alternate_screen: bool = true,
};

const RendererOwner = struct {
    generation: u64,
    controls: ?*renderer_protocol.ControlQueue,
    closed: bool = false,
    retired: bool = false,
};
const WidgetOwner = struct { generation: u64, controls: ?*widget_protocol.ControlQueue, closed: bool = false, width: usize = 0, height: usize = 0 };
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
    program_status: status_reporter.Reporter,
    program_session_name: ?[]u8 = null,
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
    widget_dimensions: std.atomic.Value(u64) = .init(80 | (@as(u64, 24) << 32)),
    widget_owners: std.ArrayList(WidgetOwner) = .empty,
    widgets: std.ArrayList(widget_protocol.Record) = .empty,
    widget_record_bytes: usize = 0,
    terminal_input_bridge: ?script_runtime.TerminalInputBridge = null,
    terminal_input_generation: u64 = 0,
    terminal_input_calls: usize = 0,
    terminal_report_fn: ?*const fn (?*anyopaque, []const u8) anyerror!bool = null,
    terminal_report_context: ?*anyopaque = null,
    terminal_report_calls: usize = 0,
    terminal_report_pump: ?*const fn (?*anyopaque) anyerror!bool = null,
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
    custom_editor_frame: ?editor_protocol.Record = null,
    custom_editor_fence: ?editor_protocol.Fence = null,
    custom_editor_sequence: u64 = 0,
    custom_editor_controls: ?*editor_protocol.ControlQueue = null,
    custom_editor_owner: u64 = 0,
    custom_editor_closed: bool = false,
    custom_editor_retire_pending: ?u64 = null,
    custom_editor_record_count: usize = 0,
    custom_editor_record_bytes: usize = 0,
    custom_editor_width: usize = 0,
    custom_editor_focused: bool = true,
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
    mouse_sequence: u64 = 0,
    mouse_gesture_active: bool = false,
    wheel: wheel_scroll.Accelerator = .{},
    component_overlay_id: ?u64 = null,
    close_pending: ?component_protocol.Fence = null,
    closed_component: ?component_protocol.Fence = null,
    custom_alternate_screen: bool = false,
    alternate_transition: enum { none, enter, leave } = .none,
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
            .program_status = status_reporter.Reporter.init(gpa),
            .header = header,
            .status = status,
            .surfaces = .{ .gpa = gpa },
        };
        self.scroll = layout.ScrollView.init(self.transcript.component(), true);
        self.scroll.primary = true;
        self.stack = .{ .axis = .vertical, .entries = &self.root_entries };
        self.app = application.Application.init(gpa, self.stack.component());
        self.app.alternate_screen = options.alternate_screen;
        self.wheel.lines = if (options.alternate_screen) options.fullscreen_wheel_scroll_lines else .{ .fixed = 1 };
        self.wheel.accelerate = !(builtin.os.tag == .macos and !self.environ.contains("SSH_CONNECTION") and !self.environ.contains("SSH_CLIENT") and !self.environ.contains("SSH_TTY"));
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
    pub fn setProgramSessionName(self: *Frontend, name: []const u8) !void {
        const copied = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(copied);
        try self.post(.{ .program_session_name = copied });
    }
    pub fn settleProgramStatus(self: *Frontend, aborted: bool) !void {
        try self.post(.{ .program_settled = aborted });
    }
    pub fn dialogStatus(raw: ?*anyopaque, event: ui.PromptEvent, method: []const u8, title: []const u8) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        const copied = try self.gpa.dupe(u8, title);
        errdefer self.gpa.free(copied);
        try self.post(.{ .program_dialog = .{
            .title = copied,
            .kind = if (event == .end) null else if (std.mem.eql(u8, method, "confirm")) .permission else .question,
        } });
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
    pub fn bindTerminalReports(self: *Frontend, callback: ?*const fn (?*anyopaque, []const u8) anyerror!bool, context: ?*anyopaque) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.terminal_report_calls != 0) self.changed.waitUncancelable(self.io, &self.mutex);
        self.terminal_report_fn = callback;
        self.terminal_report_context = context;
    }
    pub fn bindTerminalReportPump(self: *Frontend, callback: ?*const fn (?*anyopaque) anyerror!bool) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.terminal_report_calls != 0) self.changed.waitUncancelable(self.io, &self.mutex);
        self.terminal_report_pump = callback;
    }
    fn pumpTerminalReports(self: *Frontend) !void {
        self.mutex.lockUncancelable(self.io);
        const callback = self.terminal_report_pump;
        const context = self.terminal_report_context;
        if (callback != null) self.terminal_report_calls += 1;
        self.mutex.unlock(self.io);
        if (callback) |pump| {
            defer {
                self.mutex.lockUncancelable(self.io);
                self.terminal_report_calls -= 1;
                self.changed.broadcast(self.io);
                self.mutex.unlock(self.io);
            }
            if (try pump(context)) try self.queueCommand(.presentation, "");
        }
    }
    pub fn componentSink(raw: ?*anyopaque, scene: component_protocol.Scene, controls: *component_protocol.ControlQueue) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        try self.post(.{ .component = .{ .scene = scene, .controls = controls } });
    }
    pub fn rendererWidth(self: *Frontend) usize {
        return self.renderer_width.load(.acquire);
    }
    pub fn editorRecordSink(raw: ?*anyopaque, record: editor_protocol.Record, controls: *editor_protocol.ControlQueue) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure) |err| return err;
        if (self.stopping or self.worker_finished) return error.EditorFrontendStopped;
        if (record.fence.owner_generation != controls.owner_generation) return error.StaleEditorOwner;
        if (self.custom_editor_owner == record.fence.owner_generation and self.custom_editor_closed) return error.EditorOwnerClosed;
        if (self.custom_editor_owner != record.fence.owner_generation) {
            self.custom_editor_owner = record.fence.owner_generation;
            self.custom_editor_closed = false;
        }
        if (self.custom_editor_record_count >= editor_protocol.maximum_records or record.bytes() > editor_protocol.maximum_bytes - self.custom_editor_record_bytes) return error.EditorMailboxLimit;
        try self.updates.append(self.gpa, .{ .custom_editor = record });
        self.custom_editor_controls = controls;
        self.custom_editor_record_count += 1;
        self.custom_editor_record_bytes += record.bytes();
        self.changed.broadcast(self.io);
    }
    pub fn editorClosed(raw: ?*anyopaque, generation: u64) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.custom_editor_owner != generation) return;
        // The borrowed queue is used only under this mutex, including modal
        // and stopped frontend paths. Returning ACK permits its destruction.
        self.custom_editor_controls = null;
        self.custom_editor_closed = true;
        self.custom_editor_retire_pending = generation;
        self.changed.broadcast(self.io);
    }
    fn sendEditorControl(self: *Frontend, kind: @FieldType(editor_protocol.Control, "kind")) !bool {
        var control: editor_protocol.Control = .{ .gpa = self.gpa, .fence = self.custom_editor_fence orelse {
            var discarded: editor_protocol.Control = .{ .gpa = self.gpa, .fence = undefined, .kind = kind };
            discarded.deinit();
            return false;
        }, .kind = kind };
        var transferred = false;
        defer if (!transferred) control.deinit();
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.custom_editor_closed or self.custom_editor_owner != control.fence.owner_generation) return false;
        const queue = self.custom_editor_controls orelse return false;
        try queue.send(control);
        transferred = true;
        return true;
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
        const paused = self.paused and self.pause_depth > 0;
        self.mutex.unlock(self.io);
        if (paused) return Io.File.stdout().writeStreamingAll(self.io, bytes);
        const text = try self.gpa.dupe(u8, bytes);
        errdefer self.gpa.free(text);
        try self.post(.{ .notice = text });
    }
    pub fn widgetRecordSink(raw: ?*anyopaque, record: widget_protocol.Record, controls: *widget_protocol.ControlQueue) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.EndOfStream;
        const bytes = record.key.len + if (record.frame) |frame| frame.bytes else @as(usize, 0);
        if (bytes > 4 * 1024 * 1024 - self.widget_record_bytes) return error.FrontendWidgetQueueLimit;
        var found = false;
        for (self.widget_owners.items) |owner| if (owner.generation == record.owner_generation) {
            if (owner.closed) {
                var owned = record;
                owned.deinit();
                return;
            }
            if (owner.controls != controls) return error.StaleWidgetChannel;
            found = true;
            break;
        };
        if (!found) {
            if (self.widget_owners.items.len >= 256) return error.FrontendWidgetOwnerLimit;
            try self.widget_owners.append(self.gpa, .{ .generation = record.owner_generation, .controls = controls });
        }
        for (self.updates.items) |*update| if (update.* == .widget and update.widget.slot == record.slot and update.widget.owner_generation == record.owner_generation and std.mem.eql(u8, update.widget.key, record.key)) {
            const old = update.widget;
            if (old.sequence >= record.sequence) {
                var owned = record;
                owned.deinit();
                return;
            }
            self.widget_record_bytes -= old.key.len + if (old.frame) |frame| frame.bytes else @as(usize, 0);
            update.widget.deinit();
            update.* = .{ .widget = record };
            self.widget_record_bytes += bytes;
            self.changed.broadcast(self.io);
            return;
        };
        if (self.updates.items.len >= 4096) return error.FrontendQueueLimit;
        try self.updates.append(self.gpa, .{ .widget = record });
        self.widget_record_bytes += bytes;
        self.changed.broadcast(self.io);
    }
    pub fn widgetDimensions(raw: ?*anyopaque) widget_protocol.Dimensions {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        const dimensions = self.widget_dimensions.load(.acquire);
        return .{ .width = @intCast(dimensions & 0xffffffff), .height = @intCast(dimensions >> 32) };
    }
    pub fn terminalInputAttached(raw: ?*anyopaque, bridge: script_runtime.TerminalInputBridge, generation: u64) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.terminal_input_calls > 0) self.changed.waitUncancelable(self.io, &self.mutex);
        self.terminal_input_bridge = bridge;
        self.terminal_input_generation = generation;
    }
    pub fn widgetClosed(raw: ?*anyopaque, generation: u64) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.terminal_input_generation == generation) {
            self.terminal_input_bridge = null;
            while (self.terminal_input_calls > 0) self.changed.waitUncancelable(self.io, &self.mutex);
        }
        for (self.widget_owners.items) |*owner| if (owner.generation == generation) {
            owner.controls = null;
            owner.closed = true;
        };
        self.changed.broadcast(self.io);
    }
    fn applyWidget(self: *Frontend, record: *widget_protocol.Record) !void {
        self.mutex.lockUncancelable(self.io);
        const closed = for (self.widget_owners.items) |owner| {
            if (owner.generation == record.owner_generation) break owner.closed;
        } else true;
        self.mutex.unlock(self.io);
        if (closed) return;
        var index: usize = 0;
        while (index < self.widgets.items.len) : (index += 1) {
            if (self.widgets.items[index].slot != record.slot or !std.mem.eql(u8, self.widgets.items[index].key, record.key)) continue;
            if (self.widgets.items[index].owner_generation == record.owner_generation and self.widgets.items[index].sequence >= record.sequence) return;
            var old = self.widgets.orderedRemove(index);
            old.deinit();
            break;
        }
        if (record.frame != null) {
            if (self.widgets.items.len >= 256) return error.FrontendWidgetLimit;
            var owned = try record.clone(self.gpa);
            errdefer owned.deinit();
            try self.widgets.append(self.gpa, owned);
        }
        self.dirty = true;
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
        self.widget_owners.deinit(self.gpa);
        for (self.widgets.items) |*record| record.deinit();
        self.widgets.deinit(self.gpa);
        for (self.commands.items) |*command| command.deinit(self.gpa);
        self.commands.deinit(self.gpa);
        if (self.anchor) |value| self.gpa.free(value.key);
        self.app.deinit();
        self.program_status.deinit();
        if (self.program_session_name) |name| self.gpa.free(name);
        self.transcript.deinit();
        self.decoder.deinit();
        self.editor.deinit();
        if (self.custom_editor_frame) |*frame| frame.deinit();
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
            self.app.setFocus(if (self.custom_editor_frame != null and !self.custom_editor_focused) null else self.editorComponent());
            var owned = scene;
            owned.deinit();
            self.component = null;
            self.mouse_gesture_active = false;
            if (self.custom_alternate_screen) {
                self.app.alternate_screen = false;
                self.custom_alternate_screen = false;
                self.alternate_transition = .leave;
            }
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
        if (self.custom_editor_frame) |record| return layout.RenderedLines.clone(gpa, record.kind.frame.frame.lines);
        return line_editor.renderEditorLinesPadded(gpa, &self.editor, width, self.editor_padding_x);
    }
    fn editorPaste(raw: *anyopaque, bytes: []const u8) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw));
        const normalized = try line_editor.normalizePasteAlloc(self.gpa, bytes);
        defer self.gpa.free(normalized);
        if (self.custom_editor_frame != null) {
            if (!self.custom_editor_focused) return;
            _ = try self.sendEditorControl(.{ .paste = try self.gpa.dupe(u8, normalized) });
            return;
        }
        try self.editor.insert(normalized);
        self.revision += 1;
        try self.publishEditor();
        self.dirty = true;
    }
    fn editorInput(raw: *anyopaque, bytes: []const u8) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw));
        if (self.custom_editor_frame != null) {
            if (!self.custom_editor_focused) return;
            _ = try self.sendEditorControl(.{ .input = try self.gpa.dupe(u8, bytes) });
            return;
        }
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
        self.widget_record_bytes = 0;
        self.custom_editor_record_count = 0;
        self.custom_editor_record_bytes = 0;
        const retire_editor = self.custom_editor_retire_pending;
        self.custom_editor_retire_pending = null;
        const retire_renderers = self.renderer_retire_pending;
        self.renderer_retire_pending = false;
        const requested_close = self.component_close_request;
        self.component_close_request = null;
        self.mutex.unlock(self.io);
        defer {
            for (updates.items) |*update| update.deinit(self.gpa);
            updates.deinit(self.gpa);
        }
        self.mutex.lockUncancelable(self.io);
        var widget_index: usize = 0;
        while (widget_index < self.widgets.items.len) {
            const closed = for (self.widget_owners.items) |owner| {
                if (owner.generation == self.widgets.items[widget_index].owner_generation) break owner.closed;
            } else true;
            if (closed) {
                var old = self.widgets.orderedRemove(widget_index);
                old.deinit();
                self.dirty = true;
            } else widget_index += 1;
        }
        self.mutex.unlock(self.io);
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
            .event => |event| {
                try self.transcript.eventWithRendered(event.value, event.preformatted);
                if (event.value.kind == .agent_start) try self.program_status.handle(.agent_start);
                if (event.value.kind == .message_end and std.mem.eql(u8, event.value.name, "assistant")) {
                    try self.program_status.handle(.{ .assistant_end = .{ .failed = event.value.is_error, .error_message = event.value.error_message } });
                }
                try self.publishProgramStatus();
            },
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
                    if (self.custom_editor_frame != null) _ = try self.sendEditorControl(.{ .set_text = try self.gpa.dupe(u8, value.text) });
                    try self.editor.setTextAt(value.text, value.cursor orelse value.text.len);
                    self.revision += 1;
                    try self.publishEditor();
                }
            },
            .busy => |value| self.busy = value,
            .wheel_lines => |value| if (!std.meta.eql(self.wheel.lines, value)) self.wheel.setLines(value),
            .program_session_name => |value| {
                if (self.program_session_name) |name| self.gpa.free(name);
                self.program_session_name = value;
                update.* = .{ .busy = self.busy };
            },
            .program_settled => |aborted| {
                try self.program_status.handle(.{ .agent_settled = aborted });
                try self.publishProgramStatus();
            },
            .program_dialog => |value| {
                try self.program_status.setBlocked("extension-dialog", if (value.kind) |kind| .{ .kind = kind, .message = value.title } else null);
                try self.publishProgramStatus();
            },
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
                // A custom regular-mode session keeps the established private
                // alternate buffer while the continuous base stays primary.
                if (!self.app.alternate_screen) {
                    self.app.alternate_screen = true;
                    self.custom_alternate_screen = true;
                    self.alternate_transition = .enter;
                }
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
            .widget => |*record| try self.applyWidget(record),
            .renderer => |*record| {
                if (self.rendererOwnerActive(record.fence.owner_generation)) _ = try self.transcript.adoptRenderer(record);
            },
            .custom_editor => |record| {
                self.mutex.lockUncancelable(self.io);
                const active = !self.custom_editor_closed and self.custom_editor_owner == record.fence.owner_generation;
                self.mutex.unlock(self.io);
                if (!active) continue;
                if (self.custom_editor_fence) |current| {
                    if (current.owner_generation == record.fence.owner_generation and record.fence.editor_generation < current.editor_generation) continue;
                    if (current.matches(record.fence) and record.sequence <= self.custom_editor_sequence) continue;
                }
                self.custom_editor_fence = record.fence;
                self.custom_editor_sequence = record.sequence;
                switch (record.kind) {
                    .frame => |value| {
                        if (self.custom_editor_frame) |*old| old.deinit();
                        self.custom_editor_frame = record;
                        update.* = .{ .busy = self.busy };
                        // Repainting a dropdown/focus/border does not edit the
                        // document. In particular it must not invalidate the
                        // core Tab completion queued by this same owner frame.
                        if (!std.mem.eql(u8, self.editor.slice(), value.text) or self.editor.cursor != value.cursor) {
                            try self.editor.setTextAt(value.text, value.cursor);
                            self.revision += 1;
                            try self.publishEditor();
                        }
                        self.custom_editor_width = value.width;
                        self.custom_editor_focused = value.focused;
                        if (self.component == null) self.app.setFocus(if (value.focused) self.editorComponent() else null);
                    },
                    .submit => |value| {
                        try self.editor.setText(value);
                        self.revision += 1;
                        try self.queueCommand(.submit, "");
                    },
                    .action => |action| switch (action) {
                        .interrupt => if (self.busy) {
                            @atomicStore(bool, &self.abort_flag, true, .release);
                        },
                        .exit => try self.queueCommand(.quit, ""),
                        .paste_image => try self.queueCommand(.clipboard, ""),
                        .complete => try self.queueCommand(.complete, "tab"),
                    },
                    .retire => |value| {
                        if (self.custom_editor_frame) |*old| old.deinit();
                        self.custom_editor_frame = null;
                        self.custom_editor_focused = true;
                        if (self.component == null) self.app.setFocus(self.editorComponent());
                        try self.editor.setText(value);
                        self.revision += 1;
                        try self.publishEditor();
                    },
                    .failure => |value| try self.transcript.notice(value),
                }
            },
        };
        if (retire_editor) |generation| if (self.custom_editor_frame == null or self.custom_editor_frame.?.fence.owner_generation == generation) {
            if (self.custom_editor_frame) |*old| old.deinit();
            self.custom_editor_frame = null;
            self.custom_editor_focused = true;
            if (self.component == null) self.app.setFocus(self.editorComponent());
            self.custom_editor_fence = null;
            self.revision += 1;
            try self.publishEditor();
        };
        if (requested_close) |fence| try self.removeCustomComponent(fence);
        try self.publishProgramStatus();
        if (updates.items.len > 0) self.dirty = true;
    }
    fn publishProgramStatus(self: *Frontend) !void {
        if (try self.program_status.report(self.program_session_name)) |encoded| {
            defer self.gpa.free(encoded);
            const status = self.program_status.current(self.program_session_name);
            try self.app.setProgramStatus(self.io, status);
        }
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
        self.widget_dimensions.store(@as(u64, @intCast(@min(dimensions.columns, 16384))) | (@as(u64, @intCast(@min(dimensions.rows, 16384))) << 32), .release);
        self.mutex.lockUncancelable(self.io);
        for (self.widget_owners.items) |*owner| {
            if (owner.closed or (owner.width == dimensions.columns and owner.height == dimensions.rows)) continue;
            if (owner.controls) |controls| controls.send(.{ .owner_generation = owner.generation, .width = dimensions.columns, .height = dimensions.rows }) catch {};
            owner.width = dimensions.columns;
            owner.height = dimensions.rows;
        }
        self.mutex.unlock(self.io);
        self.renderer_width.store(dimensions.columns, .release);
        try self.resizeRenderers(dimensions.columns);
        if (self.custom_editor_frame != null and self.custom_editor_width != dimensions.columns) {
            if (try self.sendEditorControl(.{ .resize = dimensions.columns })) self.custom_editor_width = dimensions.columns;
        }
        var editor_lines = try renderEditor(self, self.gpa, dimensions.columns);
        defer editor_lines.deinit(self.gpa);
        const fallback_header = [_][]const u8{self.header};
        var header: []const []const u8 = if (self.surfaces.header) |lines| lines else &fallback_header;
        const fallback_footer = [_][]const u8{self.status};
        var footer: []const []const u8 = if (self.surfaces.footer) |lines| lines else &fallback_footer;
        const working = self.busy and self.surfaces.working_visible;
        const frame = self.currentWorkingFrame();
        self.working_frame = frame;
        const glyph = if (working and self.surfaces.working_frames.len > 0) self.surfaces.working_frames[frame] else "";
        const status = try std.fmt.allocPrint(self.gpa, "{s}{s}{s}{s}{s}", .{ glyph, if (glyph.len > 0) " " else "", if (working) self.surfaces.working orelse "Working…" else "", if (working and self.surfaces.status.len > 0) "  " else "", self.surfaces.status });
        defer self.gpa.free(status);
        const statuses = [_][]const u8{status};
        var above: std.ArrayList([]const u8) = .empty;
        defer above.deinit(self.gpa);
        var below: std.ArrayList([]const u8) = .empty;
        defer below.deinit(self.gpa);
        try above.appendSlice(self.gpa, self.surfaces.above);
        try below.appendSlice(self.gpa, self.surfaces.below);
        for (self.widgets.items) |record| {
            if (record.frame) |widget_frame| switch (record.slot) {
                .widget => try (if (record.placement == .aboveEditor) &above else &below).appendSlice(self.gpa, widget_frame.lines),
                .header => header = widget_frame.lines,
                .footer => footer = widget_frame.lines,
            };
        }
        self.header_lines.lines = header;
        self.above_lines.lines = above.items;
        self.below_lines.lines = below.items;
        self.status_lines.lines = if (status.len > 0) &statuses else &.{};
        self.footer_lines.lines = footer;
        self.root_entries = .{
            .{ .component = self.header_lines.component(), .basis = header.len, .shrink = 0 },
            .{ .component = self.scroll.component(), .basis = 1, .grow = 1, .min_size = 1 },
            .{ .component = self.above_lines.component(), .basis = above.items.len },
            .{ .component = self.editorComponent(), .basis = @min(editor_lines.items.len, @max(@as(usize, 1), dimensions.rows / 2)), .shrink = 0 },
            .{ .component = self.below_lines.component(), .basis = below.items.len },
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
        if (write) {
            switch (self.alternate_transition) {
                .none => {},
                .enter => try application.writeAll(self.io, terminal.alternate_screen_enter),
                .leave => try application.writeAll(self.io, terminal.alternate_screen_leave),
            }
            self.alternate_transition = .none;
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
        self.custom_editor_controls = null;
        self.custom_editor_closed = true;
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
        if (packet == .key and try self.app.consumeProgramStatusReply(self.io, packet.key)) return;
        if (packet == .key) {
            self.mutex.lockUncancelable(self.io);
            const report = self.terminal_report_fn;
            const report_context = self.terminal_report_context;
            if (report != null) self.terminal_report_calls += 1;
            self.mutex.unlock(self.io);
            if (report) |callback| {
                defer {
                    self.mutex.lockUncancelable(self.io);
                    self.terminal_report_calls -= 1;
                    self.changed.broadcast(self.io);
                    self.mutex.unlock(self.io);
                }
                if (try callback(report_context, packet.key)) {
                    try self.queueCommand(.presentation, "");
                    return;
                }
            }
        }
        self.mutex.lockUncancelable(self.io);
        const input_bridge = self.terminal_input_bridge;
        if (input_bridge != null) self.terminal_input_calls += 1;
        self.mutex.unlock(self.io);
        if (input_bridge) |bridge| {
            defer {
                self.mutex.lockUncancelable(self.io);
                self.terminal_input_calls -= 1;
                self.changed.broadcast(self.io);
                self.mutex.unlock(self.io);
            }
            var owned_raw: ?[]u8 = null;
            defer if (owned_raw) |value| self.gpa.free(value);
            const raw_data = switch (packet) {
                .key => |data| data,
                // ProcessTerminal re-wraps StdinBuffer paste events before
                // calling TUI listeners. Preserve that same observable input.
                .paste => |data| blk: {
                    owned_raw = try std.fmt.allocPrint(self.gpa, "\x1b[200~{s}\x1b[201~", .{data});
                    break :blk owned_raw.?;
                },
            };
            const result = bridge.input_fn(bridge.context, raw_data) catch |err| {
                if (err == error.TerminalInputChannelClosed or err == error.JavaScriptExtensionClosed) return self.inputFiltered(packet);
                return err;
            };
            defer std.heap.page_allocator.free(result.data);
            if (result.consume or result.data.len == 0) return;
            const bracketed = result.data.len >= 12 and std.mem.startsWith(u8, result.data, "\x1b[200~") and std.mem.endsWith(u8, result.data, "\x1b[201~");
            return self.inputFiltered(if (bracketed) .{ .paste = result.data[6 .. result.data.len - 6] } else .{ .key = result.data });
        }
        return self.inputFiltered(packet);
    }
    fn inputFiltered(self: *Frontend, packet: line_editor.InputDecoder.Input) !void {
        if (packet == .key) if (mouse_input.parse(packet.key)) |event| {
            if (self.component != null) return self.componentMouse(event, packet.key);
        };
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
    fn componentMouse(self: *Frontend, raw: mouse_input.Event, bytes: []const u8) !void {
        const scene = self.component orelse return;
        const queue = self.component_controls orelse return error.NativeComponentChannelClosed;
        var row: i64 = 0;
        var column: i64 = 0;
        var width = scene.width;
        var height = scene.height;
        var overlay_hit = false;
        if (scene.overlay) |overlay| {
            row = @intCast(overlay.row);
            column = @intCast(overlay.column);
            width = overlay.width;
            height = overlay.height;
            const visible = !overlay.hidden and raw.x >= overlay.column and raw.y >= overlay.row and raw.x - overlay.column < overlay.width and raw.y - overlay.row < overlay.height;
            overlay_hit = visible;
            if (!self.mouse_gesture_active and !visible) {
                try self.app.handleInput(bytes);
                self.dirty = true;
                return;
            }
        }
        if (self.mouse_sequence == std.math.maxInt(u64)) return error.NativeMouseSequenceLimit;
        self.mouse_sequence += 1;
        var event: component_protocol.Mouse = .{
            .kind = switch (raw.kind) {
                .press => .press,
                .release => .release,
                .drag => .drag,
                .move => .move,
                .scroll => .wheel,
            },
            .button = switch (raw.button) {
                .left => .left,
                .middle => .middle,
                .right => .right,
                else => .none,
            },
            .x = @as(i64, @intCast(raw.x)) - column,
            .y = @as(i64, @intCast(raw.y)) - row,
            .screen_x = @intCast(raw.x),
            .screen_y = @intCast(raw.y),
            .width = width,
            .height = height,
            .shift = raw.modifiers.shift,
            .alt = raw.modifiers.alt,
            .ctrl = raw.modifiers.ctrl,
            .wheel_delta = null,
        };
        if (raw.kind == .scroll) {
            const direction: i8 = if (raw.button == .wheel_up) -1 else 1;
            const lines = self.wheel.next(direction, @floatFromInt(Io.Clock.awake.now(self.io).toMilliseconds()));
            // The actual settings admission bounds fixed values to 1..100.
            event.wheel_delta = @as(i64, @intFromFloat(@min(lines, 100))) * @as(i64, if (raw.modifiers.alt) 5 else 1) * direction;
        }
        // Source distinguishes a no-button motion from a button release.
        if (std.mem.startsWith(u8, bytes, "\x1b[<") and bytes[bytes.len - 1] == 'M') {
            var codes = std.mem.splitScalar(u8, bytes[3 .. bytes.len - 1], ';');
            const code = std.fmt.parseUnsigned(u32, codes.next() orelse "", 10) catch 0;
            if (code & 32 != 0 and code & 3 == 3 and code & 64 == 0) event.kind = .move;
        }
        try queue.send(.{ .gpa = self.gpa, .fence = scene.fence, .mouse_sequence = self.mouse_sequence, .kind = .{ .mouse = event } });
        const deadline = Io.Clock.awake.now(self.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(self.io).toMilliseconds() < deadline) {
            // Close callbacks may wait for this owner to remove their scene.
            // Drain them while the pointer ACK is pending, without retaining a
            // borrowed queue after that scene's lifetime boundary completes.
            try self.applyUpdates();
            const active = self.component orelse return;
            if (!active.fence.matches(scene.fence)) return;
            const outcome = queue.takeMouseOutcome(scene.fence, self.mouse_sequence) catch |err| {
                if (err == error.NativeComponentChannelClosed) return;
                return err;
            };
            if (outcome) |value| {
                self.mouse_gesture_active = value.capture;
                self.component.?.focus_mode = value.focus_mode;
                self.component.?.focused = value.focus_mode == .custom;
                self.component.?.target_id = value.target_id;
                self.component.?.target_generation = value.target_generation;
                if (!value.handled and !overlay_hit) try self.app.handleInput(bytes);
                self.dirty = self.dirty or value.render or (!value.handled and !overlay_hit);
                return;
            }
            try self.io.sleep(.fromMilliseconds(1), .awake);
        }
        return error.NativeMouseOutcomeTimedOut;
    }
    /// Caller supplies the actual admitted settings value; changing it resets
    /// acceleration as Source does. This setter performs no terminal query.
    pub fn setWheelScrollLines(self: *Frontend, value: wheel_scroll.Lines) !void {
        try self.post(.{ .wheel_lines = value });
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
            } else if (!self.decoder.paste) {
                self.escape_started_ms = Io.Clock.awake.now(self.io).toMilliseconds();
            }
            if (!platform.inputBuffered(self.reader) and try platform.waitInput(0) != .input) break;
        }
        if (self.dirty) try self.paint();
    }
    fn runLoop(self: *Frontend) !void {
        self.app.program_status_owner = true;
        self.app.program_status_override = self.environ.get("PI_PROGRAM_STATUS");
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
                try self.app.suspendPresentation(self.io);
                raw.leave();
                raw_active = false;
                self.mutex.lockUncancelable(self.io);
                self.paused = true;
                self.changed.broadcast(self.io);
                self.mutex.unlock(self.io);
            } else if (!wanted_pause and self.paused) {
                raw = try line_editor.RawMode.enter();
                raw_active = true;
                try self.app.resumePresentation(self.io);
                self.app.invalidatePaint();
                self.mutex.lockUncancelable(self.io);
                self.paused = false;
                self.mutex.unlock(self.io);
                self.dirty = true;
            }
            try self.applyUpdates();
            try self.pumpTerminalReports();
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
                if (Io.Clock.awake.now(self.io).toMilliseconds() - started >= self.decoder.pendingTimeoutMs()) {
                    if (self.decoder.flushPending()) |packet| try self.input(packet);
                    self.escape_started_ms = null;
                }
            }
        }
    }
};

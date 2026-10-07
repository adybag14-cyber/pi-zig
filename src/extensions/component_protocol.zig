//! Owned native component transport DTOs. No QuickJS or frontend dependency.
const std = @import("std");
pub const version: u32 = 1;
pub const maximum_lines = 4096;
pub const maximum_frame_bytes = 1024 * 1024;
pub const maximum_dimension = 16384;
pub const Frame = struct {
    gpa: std.mem.Allocator,
    lines: [][]u8,
    bytes: usize,
    pub fn deinit(self: *Frame) void {
        for (self.lines) |line| self.gpa.free(line);
        self.gpa.free(self.lines);
        self.* = undefined;
    }

    pub fn clone(self: *const Frame, gpa: std.mem.Allocator) !Frame {
        const lines = try gpa.alloc([]u8, self.lines.len);
        var copied: usize = 0;
        errdefer {
            for (lines[0..copied]) |line| gpa.free(line);
            gpa.free(lines);
        }
        for (self.lines, lines) |source, *line| {
            line.* = try gpa.dupe(u8, source);
            copied += 1;
        }
        return .{ .gpa = gpa, .lines = lines, .bytes = self.bytes };
    }
};
pub const Fence = struct {
    token: u64,
    generation: u64,
    invocation_id: u64,
    component_id: u64,

    pub fn matches(a: Fence, b: Fence) bool {
        return a.token == b.token and a.generation == b.generation and a.invocation_id == b.invocation_id and a.component_id == b.component_id;
    }
};
pub const OverlayLayout = struct { row: usize, column: usize, width: usize, height: usize, hidden: bool = false, capture_input: bool = true };
pub const Mouse = struct {
    kind: enum { press, release, move, drag, click, wheel },
    button: enum { left, middle, right, none },
    x: i64,
    y: i64,
    screen_x: i64,
    screen_y: i64,
    width: usize,
    height: usize,
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    wheel_delta: ?i64 = null,
    click_count: ?u32 = null,
};
pub fn writeMouse(writer: *std.Io.Writer, value: Mouse) !void {
    try writer.print("{{\"type\":\"{s}\",\"button\":\"{s}\",\"x\":{d},\"y\":{d},\"screenX\":{d},\"screenY\":{d},\"width\":{d},\"height\":{d},\"shift\":{},\"alt\":{},\"ctrl\":{}", .{ @tagName(value.kind), @tagName(value.button), value.x, value.y, value.screen_x, value.screen_y, value.width, value.height, value.shift, value.alt, value.ctrl });
    if (value.wheel_delta) |delta| try writer.print(",\"wheelDelta\":{d}", .{delta});
    if (value.click_count) |count| try writer.print(",\"clickCount\":{d}", .{count});
    try writer.writeByte('}');
}
fn mouseInteger(object: *const std.json.ObjectMap, name: []const u8) !i64 {
    const value = object.get(name) orelse return error.InvalidComponentMouse;
    if (value != .integer) return error.InvalidComponentMouse;
    return value.integer;
}
fn mouseFlag(object: *const std.json.ObjectMap, name: []const u8) !bool {
    const value = object.get(name) orelse return false;
    if (value != .bool) return error.InvalidComponentMouse;
    return value.bool;
}
pub fn readMouse(value: std.json.Value) !Mouse {
    if (value != .object) return error.InvalidComponentMouse;
    const object = &value.object;
    const kind = object.get("type") orelse return error.InvalidComponentMouse;
    const button = object.get("button") orelse return error.InvalidComponentMouse;
    if (kind != .string or button != .string) return error.InvalidComponentMouse;
    var result: Mouse = .{ .kind = std.meta.stringToEnum(@FieldType(Mouse, "kind"), kind.string) orelse return error.InvalidComponentMouse, .button = std.meta.stringToEnum(@FieldType(Mouse, "button"), button.string) orelse return error.InvalidComponentMouse, .x = try mouseInteger(object, "x"), .y = try mouseInteger(object, "y"), .screen_x = try mouseInteger(object, "screenX"), .screen_y = try mouseInteger(object, "screenY"), .width = try dimension(object, "width"), .height = try dimension(object, "height"), .shift = try mouseFlag(object, "shift"), .alt = try mouseFlag(object, "alt"), .ctrl = try mouseFlag(object, "ctrl") };
    if (object.contains("wheelDelta")) result.wheel_delta = try mouseInteger(object, "wheelDelta");
    if (object.contains("clickCount")) {
        const count = try mouseInteger(object, "clickCount");
        if (count < 0 or count > std.math.maxInt(u32)) return error.InvalidComponentMouse;
        result.click_count = @intCast(count);
    }
    return result;
}
pub const FocusMode = enum { custom, editor, none };
pub const MouseOutcome = struct {
    fence: Fence,
    sequence: u64,
    handled: bool,
    render: bool,
    capture: bool = false,
    focus_mode: FocusMode = .custom,
    target_id: u64 = 0,
    target_generation: u64 = 0,
};
pub fn writeMouseOutcome(writer: *std.Io.Writer, value: MouseOutcome) !void {
    try writer.writeAll("{\"type\":\"component_mouse_outcome\",");
    try writeFence(writer, value.fence);
    try writer.print(",\"mouseSequence\":\"{d}\",\"handled\":{},\"render\":{},\"capture\":{},\"focusMode\":\"{s}\",\"targetId\":\"{d}\",\"targetGeneration\":\"{d}\"}}", .{ value.sequence, value.handled, value.render, value.capture, @tagName(value.focus_mode), value.target_id, value.target_generation });
}
pub fn readMouseOutcome(object: *const std.json.ObjectMap) !MouseOutcome {
    const focus = object.get("focusMode") orelse return error.InvalidComponentMouse;
    if (focus != .string) return error.InvalidComponentMouse;
    return .{ .fence = try readFence(object), .sequence = try optionalCapability(object, "mouseSequence"), .handled = try mouseFlag(object, "handled"), .render = try mouseFlag(object, "render"), .capture = try mouseFlag(object, "capture"), .focus_mode = std.meta.stringToEnum(FocusMode, focus.string) orelse return error.InvalidComponentMouse, .target_id = try optionalCapability(object, "targetId"), .target_generation = try optionalCapability(object, "targetGeneration") };
}
pub const Scene = struct {
    fence: Fence,
    width: usize,
    height: usize,
    frame: Frame,
    overlay: ?OverlayLayout = null,
    focused: bool = true,
    wants_key_release: bool = false,
    focus_mode: FocusMode = .custom,
    target_id: u64 = 0,
    target_generation: u64 = 0,
    pub fn deinit(self: *Scene) void {
        self.frame.deinit();
    }
    pub fn clone(self: *const Scene, gpa: std.mem.Allocator) !Scene {
        var result = self.*;
        result.frame = try self.frame.clone(gpa);
        return result;
    }
};
pub const Control = struct {
    gpa: std.mem.Allocator,
    fence: Fence,
    error_message: ?[]u8 = null,
    target_id: u64 = 0,
    target_generation: u64 = 0,
    mouse_sequence: u64 = 0,
    kind: union(enum) {
        input: []u8,
        resize: struct { width: usize, height: usize },
        mouse: Mouse,
        invalidate,
        close,
        cancel,
        close_ack: bool,
    },
    pub fn deinit(self: *Control) void {
        if (self.kind == .input) self.gpa.free(self.kind.input);
        if (self.error_message) |message| self.gpa.free(message);
    }
    pub fn bytes(self: *const Control) usize {
        return (if (self.kind == .input) self.kind.input.len else 0) + (if (self.error_message) |message| message.len else 0);
    }
};

pub fn identifier(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => if (value.integer > 0) @intCast(value.integer) else error.InvalidComponentIdentity,
        .string => blk: {
            if (value.string.len == 0 or value.string.len > 20) return error.InvalidComponentIdentity;
            const parsed = std.fmt.parseUnsigned(u64, value.string, 10) catch return error.InvalidComponentIdentity;
            if (parsed == 0) return error.InvalidComponentIdentity;
            break :blk parsed;
        },
        else => error.InvalidComponentIdentity,
    };
}

pub fn readFence(object: *const std.json.ObjectMap) !Fence {
    const actual_version = object.get("version") orelse return error.InvalidComponentVersion;
    if (actual_version != .integer or actual_version.integer != version) return error.InvalidComponentVersion;
    return .{
        .token = try identifier(object.get("token") orelse return error.InvalidComponentIdentity),
        .generation = try identifier(object.get("generation") orelse return error.InvalidComponentIdentity),
        .invocation_id = try identifier(object.get("invocationId") orelse return error.InvalidComponentIdentity),
        .component_id = try identifier(object.get("componentId") orelse return error.InvalidComponentIdentity),
    };
}

pub fn writeFence(writer: *std.Io.Writer, fence: Fence) !void {
    try writer.print("\"version\":{d},\"token\":\"{d}\",\"generation\":\"{d}\",\"invocationId\":\"{d}\",\"componentId\":\"{d}\"", .{ version, fence.token, fence.generation, fence.invocation_id, fence.component_id });
}

pub fn writeScene(writer: *std.Io.Writer, scene: *const Scene) !void {
    try writer.writeAll("{\"type\":\"component_scene\",");
    try writeFence(writer, scene.fence);
    try writer.print(",\"width\":{d},\"height\":{d},\"focused\":{s},\"wantsKeyRelease\":{s},\"lines\":", .{ scene.width, scene.height, if (scene.focused) "true" else "false", if (scene.wants_key_release) "true" else "false" });
    try std.json.Stringify.value(scene.frame.lines, .{}, writer);
    try writer.writeAll(",\"overlay\":");
    if (scene.overlay) |overlay| try writer.print("{{\"row\":{d},\"column\":{d},\"width\":{d},\"height\":{d},\"hidden\":{s},\"captureInput\":{s}}}", .{ overlay.row, overlay.column, overlay.width, overlay.height, if (overlay.hidden) "true" else "false", if (overlay.capture_input) "true" else "false" }) else try writer.writeAll("null");
    try writer.print(",\"focusMode\":\"{s}\",\"targetId\":\"{d}\",\"targetGeneration\":\"{d}\"}}", .{ @tagName(scene.focus_mode), scene.target_id, scene.target_generation });
}

fn dimension(object: *const std.json.ObjectMap, name: []const u8) !usize {
    const value = object.get(name) orelse return error.InvalidComponentViewport;
    if (value != .integer or value.integer < 0 or value.integer > maximum_dimension) return error.InvalidComponentViewport;
    return @intCast(value.integer);
}

pub fn readScene(gpa: std.mem.Allocator, object: *const std.json.ObjectMap) !Scene {
    const fence = try readFence(object);
    const width = try dimension(object, "width");
    const height = try dimension(object, "height");
    const values = object.get("lines") orelse return error.InvalidComponentFrame;
    if (values != .array or values.array.items.len > maximum_lines) return error.InvalidComponentFrame;
    const lines = try gpa.alloc([]u8, values.array.items.len);
    var copied: usize = 0;
    errdefer {
        for (lines[0..copied]) |line| gpa.free(line);
        gpa.free(lines);
    }
    var bytes: usize = 0;
    for (values.array.items, lines) |value, *line| {
        if (value != .string or !std.unicode.utf8ValidateSlice(value.string) or value.string.len > maximum_frame_bytes - bytes) return error.InvalidComponentFrame;
        line.* = try gpa.dupe(u8, value.string);
        bytes += value.string.len;
        copied += 1;
    }
    var overlay: ?OverlayLayout = null;
    if (object.get("overlay")) |value| if (value != .null) {
        if (value != .object) return error.InvalidComponentOverlay;
        overlay = .{ .row = try dimension(&value.object, "row"), .column = try dimension(&value.object, "column"), .width = try dimension(&value.object, "width"), .height = try dimension(&value.object, "height") };
        if (value.object.get("hidden")) |hidden| {
            if (hidden != .bool) return error.InvalidComponentOverlay;
            overlay.?.hidden = hidden.bool;
        }
        if (value.object.get("captureInput")) |capture| {
            if (capture != .bool) return error.InvalidComponentOverlay;
            overlay.?.capture_input = capture.bool;
        }
    };
    const focused = object.get("focused") orelse std.json.Value{ .bool = true };
    if (focused != .bool) return error.InvalidComponentFrame;
    const releases = object.get("wantsKeyRelease") orelse std.json.Value{ .bool = false };
    if (releases != .bool) return error.InvalidComponentFrame;
    var scene: Scene = .{ .fence = fence, .width = width, .height = height, .frame = .{ .gpa = gpa, .lines = lines, .bytes = bytes }, .overlay = overlay, .focused = focused.bool, .wants_key_release = releases.bool, .focus_mode = if (focused.bool) .custom else .editor };
    if (object.get("focusMode")) |mode| {
        if (mode != .string) return error.InvalidComponentFocus;
        scene.focus_mode = std.meta.stringToEnum(@TypeOf(scene.focus_mode), mode.string) orelse return error.InvalidComponentFocus;
    }
    scene.target_id = try optionalCapability(object, "targetId");
    scene.target_generation = try optionalCapability(object, "targetGeneration");
    return scene;
}

fn optionalCapability(object: *const std.json.ObjectMap, name: []const u8) !u64 {
    const value = object.get(name) orelse return 0;
    if (value == .integer and value.integer == 0) return 0;
    if (value == .string and std.mem.eql(u8, value.string, "0")) return 0;
    return identifier(value);
}

pub fn readControl(gpa: std.mem.Allocator, object: *const std.json.ObjectMap) !Control {
    const fence = try readFence(object);
    const kind = object.get("control") orelse return error.InvalidComponentControl;
    if (kind != .string) return error.InvalidComponentControl;
    var value: Control = .{ .gpa = gpa, .fence = fence, .kind = .invalidate };
    value.target_id = try optionalCapability(object, "targetId");
    value.target_generation = try optionalCapability(object, "targetGeneration");
    value.mouse_sequence = try optionalCapability(object, "mouseSequence");
    if (std.mem.eql(u8, kind.string, "input")) {
        const data = object.get("data") orelse return error.InvalidComponentControl;
        if (data != .string or data.string.len > 64 * 1024 or !std.unicode.utf8ValidateSlice(data.string)) return error.InvalidComponentControl;
        value.kind = .{ .input = try gpa.dupe(u8, data.string) };
    } else if (std.mem.eql(u8, kind.string, "mouse")) value.kind = .{ .mouse = try readMouse(object.get("mouse") orelse return error.InvalidComponentMouse) } else if (std.mem.eql(u8, kind.string, "resize")) value.kind = .{ .resize = .{ .width = try dimension(object, "width"), .height = try dimension(object, "height") } } else if (std.mem.eql(u8, kind.string, "invalidate")) value.kind = .invalidate else if (std.mem.eql(u8, kind.string, "close")) value.kind = .close else if (std.mem.eql(u8, kind.string, "cancel")) value.kind = .cancel else if (std.mem.eql(u8, kind.string, "close_ack")) {
        const success = object.get("ok") orelse return error.InvalidComponentControl;
        if (success != .bool) return error.InvalidComponentControl;
        value.kind = .{ .close_ack = success.bool };
        if (object.get("error")) |message| {
            if (message != .string or message.string.len > 16 * 1024 or !std.unicode.utf8ValidateSlice(message.string)) return error.InvalidComponentControl;
            value.error_message = try gpa.dupe(u8, message.string);
        }
    } else return error.InvalidComponentControl;
    return value;
}

pub fn writeControl(writer: *std.Io.Writer, value: *const Control) !void {
    try writer.writeAll("{\"kind\":\"component_control\",");
    try writeFence(writer, value.fence);
    try writer.print(",\"targetId\":\"{d}\",\"targetGeneration\":\"{d}\"", .{ value.target_id, value.target_generation });
    if (value.kind == .mouse) try writer.print(",\"mouseSequence\":\"{d}\"", .{value.mouse_sequence});
    try writer.writeAll(",\"control\":");
    try std.json.Stringify.value(@tagName(value.kind), .{}, writer);
    switch (value.kind) {
        .input => |input| {
            try writer.writeAll(",\"data\":");
            try std.json.Stringify.value(input, .{}, writer);
        },
        .resize => |size| try writer.print(",\"width\":{d},\"height\":{d}", .{ size.width, size.height }),
        .close_ack => |ok| try writer.print(",\"ok\":{s}", .{if (ok) "true" else "false"}),
        .mouse => |mouse| {
            try writer.writeAll(",\"mouse\":");
            try writeMouse(writer, mouse);
        },
        else => {},
    }
    if (value.error_message) |message| {
        try writer.writeAll(",\"error\":");
        try std.json.Stringify.value(message, .{}, writer);
    }
    try writer.writeByte('}');
}
pub const SceneSink = *const fn (?*anyopaque, Scene) anyerror!void;

/// Ownership transfers only on successful send. Every fence is checked before
/// admission; reset drops stale pending controls before a new scene can start.
pub const ControlQueue = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    available: std.Io.Condition = .init,
    active: ?Fence = null,
    stopped: bool = false,
    closing: bool = false,
    queued_bytes: usize = 0,
    items: std.ArrayList(Control) = .empty,
    mouse_outcomes: std.ArrayList(MouseOutcome) = .empty,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) ControlQueue {
        return .{ .gpa = gpa, .io = io };
    }
    pub fn deinit(self: *ControlQueue) void {
        self.stop();
        for (self.items.items) |*item| item.deinit();
        self.items.deinit(self.gpa);
        self.mouse_outcomes.deinit(self.gpa);
    }
    pub fn reset(self: *ControlQueue, fence: ?Fence) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.items.items) |*item| item.deinit();
        self.items.clearRetainingCapacity();
        self.mouse_outcomes.clearRetainingCapacity();
        self.queued_bytes = 0;
        self.active = fence;
        self.closing = false;
        self.available.broadcast(self.io);
    }
    pub fn send(self: *ControlQueue, control: Control) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopped) return error.NativeComponentChannelClosed;
        if (!Fence.matches(self.active orelse return error.StaleNativeComponentControl, control.fence)) return error.StaleNativeComponentControl;
        if (self.closing) return error.NativeComponentChannelClosing;
        const teardown = control.kind == .close or control.kind == .cancel;
        if (teardown) {
            for (self.items.items) |*item| item.deinit();
            self.items.clearRetainingCapacity();
            self.queued_bytes = 0;
        }
        if (self.items.items.len >= 128 or control.bytes() > 1024 * 1024 - self.queued_bytes) return error.NativeComponentControlLimit;
        try self.items.append(self.gpa, control);
        self.queued_bytes += control.bytes();
        self.closing = teardown;
        self.available.signal(self.io);
    }
    pub fn next(self: *ControlQueue) std.Io.Cancelable!?Control {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        while (!self.stopped and self.items.items.len == 0) try self.available.wait(self.io, &self.mutex);
        if (self.items.items.len == 0) return null;
        const value = self.items.orderedRemove(0);
        self.queued_bytes -= value.bytes();
        return value;
    }
    pub fn publishMouseOutcome(self: *ControlQueue, value: MouseOutcome) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopped or self.active == null or !value.fence.matches(self.active.?)) return error.StaleNativeComponentControl;
        if (self.mouse_outcomes.items.len >= 128) return error.NativeComponentControlLimit;
        try self.mouse_outcomes.append(self.gpa, value);
        self.available.broadcast(self.io);
    }
    pub fn takeMouseOutcome(self: *ControlQueue, fence: Fence, sequence: u64) !?MouseOutcome {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopped or self.active == null or !fence.matches(self.active.?)) return error.NativeComponentChannelClosed;
        for (self.mouse_outcomes.items, 0..) |value, index| if (value.sequence == sequence and value.fence.matches(fence)) return self.mouse_outcomes.orderedRemove(index);
        return null;
    }
    pub fn stop(self: *ControlQueue) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.stopped = true;
        self.active = null;
        self.mouse_outcomes.clearRetainingCapacity();
        self.available.broadcast(self.io);
    }
};

test "component protocol validates version identities unknown controls and independently owned scene bytes" {
    const gpa = std.testing.allocator;
    const frame_json = "{\"version\":1,\"token\":\"9007199254740993\",\"generation\":2,\"invocationId\":\"3\",\"componentId\":4,\"width\":80,\"height\":24,\"lines\":[\"owned\"],\"overlay\":null}";
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, frame_json, .{});
    defer parsed.deinit();
    var scene = try readScene(gpa, &parsed.value.object);
    defer scene.deinit();
    try std.testing.expectEqual(@as(u64, 9007199254740993), scene.fence.token);
    var copied = try scene.clone(gpa);
    defer copied.deinit();
    scene.frame.lines[0][0] = 'X';
    try std.testing.expectEqualStrings("owned", copied.frame.lines[0]);
    try std.testing.expectError(error.InvalidComponentIdentity, identifier(.{ .float = 3 }));
    try std.testing.expectError(error.InvalidComponentIdentity, identifier(.{ .string = "0" }));
    var record: std.Io.Writer.Allocating = .init(gpa);
    defer record.deinit();
    const control: Control = .{ .gpa = gpa, .fence = copied.fence, .kind = .{ .resize = .{ .width = 22, .height = 11 } } };
    try writeControl(&record.writer, &control);
    var wire = try std.json.parseFromSlice(std.json.Value, gpa, record.written(), .{});
    defer wire.deinit();
    var decoded = try readControl(gpa, &wire.value.object);
    defer decoded.deinit();
    try std.testing.expect(Fence.matches(decoded.fence, control.fence));
    try std.testing.expectEqual(@as(usize, 22), decoded.kind.resize.width);
    try wire.value.object.put(gpa, "control", .{ .string = "unknown" });
    try std.testing.expectError(error.InvalidComponentControl, readControl(gpa, &wire.value.object));
    try wire.value.object.put(gpa, "version", .{ .integer = 2 });
    try std.testing.expectError(error.InvalidComponentVersion, readControl(gpa, &wire.value.object));
}
test "mouse controls preserve Source event fields and exact sequence identities while outcomes fence reset and close" {
    const gpa = std.testing.allocator;
    const fence: Fence = .{ .token = 1, .generation = 2, .invocation_id = 3, .component_id = 4 };
    const control: Control = .{ .gpa = gpa, .fence = fence, .mouse_sequence = std.math.maxInt(u64), .kind = .{ .mouse = .{ .kind = .wheel, .button = .none, .x = -2, .y = 3, .screen_x = 40, .screen_y = 50, .width = 80, .height = 20, .shift = true, .alt = true, .wheel_delta = -5 } } };
    var writer: std.Io.Writer.Allocating = .init(gpa);
    defer writer.deinit();
    try writeControl(&writer.writer, &control);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, writer.written(), .{});
    defer parsed.deinit();
    var decoded = try readControl(gpa, &parsed.value.object);
    defer decoded.deinit();
    try std.testing.expectEqual(control.mouse_sequence, decoded.mouse_sequence);
    try std.testing.expectEqualDeep(control.kind.mouse, decoded.kind.mouse);
    var queue = ControlQueue.init(gpa, std.testing.io);
    defer queue.deinit();
    queue.reset(fence);
    const value: MouseOutcome = .{ .fence = fence, .sequence = control.mouse_sequence, .handled = true, .render = false, .capture = true, .target_generation = 7 };
    try queue.publishMouseOutcome(value);
    try std.testing.expect((try queue.takeMouseOutcome(fence, 5)) == null);
    try std.testing.expectEqualDeep(value, (try queue.takeMouseOutcome(fence, control.mouse_sequence)).?);
    try queue.publishMouseOutcome(value);
    queue.reset(null);
    try std.testing.expectError(error.StaleNativeComponentControl, queue.publishMouseOutcome(value));
    try std.testing.expectError(error.NativeComponentChannelClosed, queue.takeMouseOutcome(fence, control.mouse_sequence));
}

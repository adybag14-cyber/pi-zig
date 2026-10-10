//! Owned widget frames and bounded resize controls. No VM values cross threads.
const std = @import("std");
const component = @import("component_protocol.zig");
pub const Placement = enum { aboveEditor, belowEditor };
pub const Slot = enum { widget, header, footer };
pub const Dimensions = struct { width: usize, height: usize };
pub const Record = struct {
    gpa: std.mem.Allocator,
    owner_generation: u64,
    generation: u64,
    sequence: u64,
    key: []u8,
    placement: Placement,
    width: usize,
    frame: ?component.Frame,
    slot: Slot = .widget,
    pub fn deinit(self: *Record) void {
        self.gpa.free(self.key);
        if (self.frame) |*frame| frame.deinit();
    }
    pub fn clone(self: Record, gpa: std.mem.Allocator) !Record {
        var result = self;
        result.gpa = gpa;
        result.key = try gpa.dupe(u8, self.key);
        errdefer gpa.free(result.key);
        if (self.frame) |frame| result.frame = try frame.clone(gpa);
        return result;
    }
};
fn integer(object: *const std.json.ObjectMap, name: []const u8) !u64 {
    return component.identifier(object.get(name) orelse return error.InvalidWidgetRecord);
}
pub fn write(writer: *std.Io.Writer, record: Record) !void {
    try writer.print("{{\"type\":\"widget_record\",\"version\":1,\"ownerGeneration\":\"{d}\",\"generation\":\"{d}\",\"sequence\":\"{d}\",\"width\":{d},\"slot\":\"{s}\",\"placement\":\"{s}\",\"key\":", .{ record.owner_generation, record.generation, record.sequence, record.width, @tagName(record.slot), @tagName(record.placement) });
    try std.json.Stringify.value(record.key, .{}, writer);
    try writer.writeAll(",\"lines\":");
    if (record.frame) |frame| try std.json.Stringify.value(frame.lines, .{}, writer) else try writer.writeAll("null");
    try writer.writeByte('}');
}
pub fn read(gpa: std.mem.Allocator, object: *const std.json.ObjectMap) !Record {
    const version = object.get("version") orelse return error.InvalidWidgetRecord;
    if (version != .integer or version.integer != 1) return error.InvalidWidgetRecord;
    const key = object.get("key") orelse return error.InvalidWidgetRecord;
    const place = object.get("placement") orelse return error.InvalidWidgetRecord;
    if (key != .string or key.string.len > 65536 or place != .string) return error.InvalidWidgetRecord;
    const placement = std.meta.stringToEnum(Placement, place.string) orelse return error.InvalidWidgetRecord;
    const width = try integer(object, "width");
    if (width > component.maximum_dimension) return error.InvalidWidgetRecord;
    var record: Record = .{ .gpa = gpa, .owner_generation = try integer(object, "ownerGeneration"), .generation = try integer(object, "generation"), .sequence = try integer(object, "sequence"), .key = try gpa.dupe(u8, key.string), .placement = placement, .width = @intCast(width), .frame = null };
    errdefer record.deinit();
    if (object.get("slot")) |slot| {
        if (slot != .string) return error.InvalidWidgetRecord;
        record.slot = std.meta.stringToEnum(Slot, slot.string) orelse return error.InvalidWidgetRecord;
    }
    const values = object.get("lines") orelse return error.InvalidWidgetRecord;
    if (values == .null) return record;
    if (values != .array or values.array.items.len > component.maximum_lines) return error.InvalidWidgetRecord;
    const lines = try gpa.alloc([]u8, values.array.items.len);
    var count: usize = 0;
    var bytes: usize = 0;
    errdefer {
        for (lines[0..count]) |line| gpa.free(line);
        gpa.free(lines);
    }
    for (values.array.items, lines) |value, *line| {
        if (value != .string or value.string.len > component.maximum_frame_bytes - bytes) return error.InvalidWidgetRecord;
        line.* = try gpa.dupe(u8, value.string);
        bytes += value.string.len;
        count += 1;
    }
    record.frame = .{ .gpa = gpa, .lines = lines, .bytes = bytes };
    return record;
}
pub const Control = struct { owner_generation: u64, width: usize, height: usize };
pub fn writeControl(writer: *std.Io.Writer, control: Control) !void {
    try writer.print("{{\"kind\":\"widget_control\",\"version\":1,\"ownerGeneration\":\"{d}\",\"width\":{d},\"height\":{d}}}", .{ control.owner_generation, control.width, control.height });
}
pub fn readControl(object: *const std.json.ObjectMap) !Control {
    const version = object.get("version") orelse return error.InvalidWidgetControl;
    if (version != .integer or version.integer != 1) return error.InvalidWidgetControl;
    const width = try integer(object, "width");
    const height = try integer(object, "height");
    if (width > component.maximum_dimension or height > component.maximum_dimension) return error.InvalidWidgetControl;
    return .{ .owner_generation = try integer(object, "ownerGeneration"), .width = @intCast(width), .height = @intCast(height) };
}
pub const ControlQueue = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    wake: std.Io.Event = .unset,
    pending: ?Control = null,
    stopped: bool = false,
    pub fn send(self: *ControlQueue, control: Control) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopped) return error.WidgetMailboxStopped;
        self.pending = control;
        self.wake.set(self.io);
    }
    pub fn next(self: *ControlQueue) std.Io.Cancelable!?Control {
        while (true) {
            self.mutex.lockUncancelable(self.io);
            self.wake.reset();
            if (self.pending) |control| {
                self.pending = null;
                self.mutex.unlock(self.io);
                return control;
            }
            const stopped = self.stopped;
            self.mutex.unlock(self.io);
            if (stopped) return null;
            try self.wake.wait(self.io);
        }
    }
    pub fn stop(self: *ControlQueue) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.stopped = true;
        self.wake.set(self.io);
    }
};

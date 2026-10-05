//! Pure owned custom-editor records and controls. No VM values cross threads.
const std = @import("std");
const component = @import("component_protocol.zig");
pub const version = 1;
pub const maximum_records = 256;
pub const maximum_bytes = 4 * 1024 * 1024;
pub const Frame = component.Frame;
pub const Fence = struct {
    owner_generation: u64,
    extension_id: u64,
    editor_generation: u64,
    pub fn matches(a: Fence, b: Fence) bool {
        return std.meta.eql(a, b);
    }
};
pub const Record = struct {
    gpa: std.mem.Allocator,
    fence: Fence,
    sequence: u64,
    kind: union(enum) {
        frame: struct { width: usize, text: []u8, frame: Frame, focused: bool = true, cursor: usize = 0 },
        submit: []u8,
        action: enum { interrupt, exit, paste_image, complete },
        retire: []u8,
        failure: []u8,
    },
    pub fn deinit(self: *Record) void {
        switch (self.kind) {
            .frame => |*value| {
                self.gpa.free(value.text);
                value.frame.deinit();
            },
            .submit, .retire, .failure => |value| self.gpa.free(value),
            .action => {},
        }
    }
    pub fn bytes(self: Record) usize {
        return switch (self.kind) {
            .frame => |v| v.text.len + v.frame.bytes,
            .submit, .retire, .failure => |v| v.len,
            .action => 0,
        };
    }
    pub fn clone(self: Record, gpa: std.mem.Allocator) !Record {
        var result = self;
        result.gpa = gpa;
        switch (self.kind) {
            .frame => |v| {
                const contents = try gpa.dupe(u8, v.text);
                errdefer gpa.free(contents);
                result.kind = .{ .frame = .{ .text = contents, .width = v.width, .frame = try v.frame.clone(gpa), .focused = v.focused, .cursor = v.cursor } };
            },
            .submit => |v| result.kind = .{ .submit = try gpa.dupe(u8, v) },
            .retire => |v| result.kind = .{ .retire = try gpa.dupe(u8, v) },
            .failure => |v| result.kind = .{ .failure = try gpa.dupe(u8, v) },
            .action => {},
        }
        return result;
    }
};
fn identifier(value: std.json.Value) !u64 {
    const id = try component.identifier(value);
    if (id == 0 or id > 9_007_199_254_740_991) return error.InvalidEditorIdentity;
    return id;
}
fn readFence(object: *const std.json.ObjectMap) !Fence {
    return .{ .owner_generation = try identifier(object.get("ownerGeneration") orelse return error.InvalidEditorIdentity), .extension_id = try identifier(object.get("extensionId") orelse return error.InvalidEditorIdentity), .editor_generation = try identifier(object.get("editorGeneration") orelse return error.InvalidEditorIdentity) };
}
fn checkVersion(object: *const std.json.ObjectMap) !void {
    const value = object.get("version") orelse return error.InvalidEditorVersion;
    if (value != .integer or value.integer != version) return error.InvalidEditorVersion;
}
fn text(object: *const std.json.ObjectMap, field: []const u8) ![]const u8 {
    const value = object.get(field) orelse return error.InvalidEditorText;
    if (value != .string or value.string.len > maximum_bytes) return error.InvalidEditorText;
    return value.string;
}
fn dimension(object: *const std.json.ObjectMap) !usize {
    const value = object.get("width") orelse return error.InvalidEditorDimension;
    if (value != .integer or value.integer < 0 or value.integer > component.maximum_dimension) return error.InvalidEditorDimension;
    return @intCast(value.integer);
}
pub fn read(gpa: std.mem.Allocator, object: *const std.json.ObjectMap) !Record {
    try checkVersion(object);
    var result: Record = .{ .gpa = gpa, .fence = try readFence(object), .sequence = try identifier(object.get("sequence") orelse return error.InvalidEditorIdentity), .kind = .{ .action = .interrupt } };
    const kind = try text(object, "type");
    if (std.mem.eql(u8, kind, "editor_frame")) {
        const width = try dimension(object);
        const contents = try gpa.dupe(u8, try text(object, "text"));
        errdefer gpa.free(contents);
        const values = object.get("lines") orelse return error.InvalidEditorFrame;
        if (values != .array or values.array.items.len > component.maximum_lines) return error.InvalidEditorFrame;
        const lines = try gpa.alloc([]u8, values.array.items.len);
        var count: usize = 0;
        var bytes: usize = 0;
        errdefer {
            for (lines[0..count]) |line| gpa.free(line);
            gpa.free(lines);
        }
        for (values.array.items, lines) |value, *line| {
            if (value != .string or value.string.len > component.maximum_frame_bytes - bytes) return error.InvalidEditorFrame;
            line.* = try gpa.dupe(u8, value.string);
            count += 1;
            bytes += value.string.len;
        }
        const focused = object.get("focused") orelse std.json.Value{ .bool = true };
        if (focused != .bool) return error.InvalidEditorFocus;
        const cursor = object.get("cursor") orelse std.json.Value{ .integer = @intCast(contents.len) };
        if (cursor != .integer or cursor.integer < 0 or cursor.integer > @as(i64, @intCast(contents.len))) return error.InvalidEditorCursor;
        const cursor_offset: usize = @intCast(cursor.integer);
        if (cursor_offset < contents.len and contents[cursor_offset] & 0xc0 == 0x80) return error.InvalidEditorCursor;
        result.kind = .{ .frame = .{ .width = width, .text = contents, .frame = .{ .gpa = gpa, .lines = lines, .bytes = bytes }, .focused = focused.bool, .cursor = @intCast(cursor.integer) } };
    } else if (std.mem.eql(u8, kind, "editor_submit")) result.kind = .{ .submit = try gpa.dupe(u8, try text(object, "text")) } else if (std.mem.eql(u8, kind, "editor_retire")) result.kind = .{ .retire = try gpa.dupe(u8, try text(object, "text")) } else if (std.mem.eql(u8, kind, "editor_failure")) result.kind = .{ .failure = try gpa.dupe(u8, try text(object, "text")) } else if (std.mem.eql(u8, kind, "editor_action")) result.kind = .{ .action = std.meta.stringToEnum(@FieldType(@FieldType(Record, "kind"), "action"), try text(object, "action")) orelse return error.InvalidEditorAction } else return error.InvalidEditorRecord;
    return result;
}
fn writeFence(writer: *std.Io.Writer, fence: Fence) !void {
    try writer.print("\"version\":1,\"ownerGeneration\":\"{d}\",\"extensionId\":\"{d}\",\"editorGeneration\":\"{d}\"", .{ fence.owner_generation, fence.extension_id, fence.editor_generation });
}
pub fn write(writer: *std.Io.Writer, record: Record) !void {
    try writer.print("{{\"type\":\"editor_{s}\",", .{@tagName(record.kind)});
    try writeFence(writer, record.fence);
    try writer.print(",\"sequence\":\"{d}\"", .{record.sequence});
    switch (record.kind) {
        .frame => |v| {
            try writer.print(",\"width\":{d},\"focused\":{},\"cursor\":{d},\"text\":", .{ v.width, v.focused, v.cursor });
            try std.json.Stringify.value(v.text, .{}, writer);
            try writer.writeAll(",\"lines\":");
            try std.json.Stringify.value(v.frame.lines, .{}, writer);
        },
        .submit, .retire, .failure => |v| {
            try writer.writeAll(",\"text\":");
            try std.json.Stringify.value(v, .{}, writer);
        },
        .action => |v| {
            try writer.writeAll(",\"action\":");
            try std.json.Stringify.value(@tagName(v), .{}, writer);
        },
    }
    try writer.writeByte('}');
}
pub const Control = struct {
    gpa: std.mem.Allocator,
    fence: Fence,
    kind: union(enum) { input: []u8, paste: []u8, set_text: []u8, resize: usize, retire },
    pub fn deinit(self: *Control) void {
        switch (self.kind) {
            .input, .paste, .set_text => |v| self.gpa.free(v),
            else => {},
        }
    }
    pub fn bytes(self: Control) usize {
        return switch (self.kind) {
            .input, .paste, .set_text => |v| v.len,
            else => 0,
        };
    }
};
pub fn readControl(gpa: std.mem.Allocator, object: *const std.json.ObjectMap) !Control {
    try checkVersion(object);
    const fence = try readFence(object);
    const kind = try text(object, "control");
    const result: Control = .{ .gpa = gpa, .fence = fence, .kind = if (std.mem.eql(u8, kind, "input")) .{ .input = try gpa.dupe(u8, try text(object, "text")) } else if (std.mem.eql(u8, kind, "paste")) .{ .paste = try gpa.dupe(u8, try text(object, "text")) } else if (std.mem.eql(u8, kind, "set_text")) .{ .set_text = try gpa.dupe(u8, try text(object, "text")) } else if (std.mem.eql(u8, kind, "resize")) .{ .resize = try dimension(object) } else if (std.mem.eql(u8, kind, "retire")) .retire else return error.InvalidEditorControl };
    return result;
}
pub fn writeControl(writer: *std.Io.Writer, control: Control) !void {
    try writer.writeAll("{\"kind\":\"editor_control\",");
    try writeFence(writer, control.fence);
    try writer.print(",\"control\":\"{s}\"", .{@tagName(control.kind)});
    switch (control.kind) {
        .input, .paste, .set_text => |v| {
            try writer.writeAll(",\"text\":");
            try std.json.Stringify.value(v, .{}, writer);
        },
        .resize => |v| try writer.print(",\"width\":{d}", .{v}),
        .retire => {},
    }
    try writer.writeByte('}');
}
pub const ControlQueue = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    wake: std.Io.Event = .unset,
    controls: std.ArrayList(Control) = .empty,
    owner_generation: u64,
    bytes: usize = 0,
    stopped: bool = false,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, generation: u64) ControlQueue {
        return .{ .gpa = gpa, .io = io, .owner_generation = generation };
    }
    pub fn deinit(self: *ControlQueue) void {
        for (self.controls.items) |*control| control.deinit();
        self.controls.deinit(self.gpa);
    }
    pub fn send(self: *ControlQueue, control: Control) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopped) return error.EditorMailboxStopped;
        if (control.fence.owner_generation != self.owner_generation) return error.StaleEditorOwner;
        if (self.controls.items.len >= maximum_records or control.bytes() > maximum_bytes - self.bytes) return error.EditorMailboxLimit;
        try self.controls.append(self.gpa, control);
        self.bytes += control.bytes();
        self.wake.set(self.io);
    }
    pub fn next(self: *ControlQueue) std.Io.Cancelable!?Control {
        while (true) {
            self.mutex.lockUncancelable(self.io);
            self.wake.reset();
            if (self.controls.items.len > 0) {
                const control = self.controls.orderedRemove(0);
                self.bytes -= control.bytes();
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

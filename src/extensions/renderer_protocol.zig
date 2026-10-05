//! Owned renderer mailbox records. This boundary uses no QuickJS values.
const std = @import("std");
const component_protocol = @import("component_protocol.zig");

pub const version: u32 = 1;
pub const maximum_rows = 16_384;
pub const maximum_records = 512;
pub const maximum_queue_bytes = 8 * 1024 * 1024;
pub const Frame = component_protocol.Frame;
pub const Slot = enum { call, result };
pub const Fence = struct {
    owner_generation: u64,
    extension_id: u64,
    row_generation: u64,
    tool_call_id: []const u8,

    pub fn matches(a: Fence, b: Fence) bool {
        return a.owner_generation == b.owner_generation and a.extension_id == b.extension_id and a.row_generation == b.row_generation and std.mem.eql(u8, a.tool_call_id, b.tool_call_id);
    }
};

pub const Record = struct {
    gpa: std.mem.Allocator,
    fence: Fence,
    kind: union(enum) {
        register: struct { tool_name: []u8, width: usize },
        frame: struct { sequence: u64, revision: u64, slot: Slot, width: usize, frame: Frame },
        retire,
        failure: []u8,
    },

    pub fn deinit(self: *Record) void {
        self.gpa.free(self.fence.tool_call_id);
        switch (self.kind) {
            .register => |value| self.gpa.free(value.tool_name),
            .frame => |*value| value.frame.deinit(),
            .failure => |value| self.gpa.free(value),
            .retire => {},
        }
        self.* = undefined;
    }

    pub fn bytes(self: *const Record) usize {
        return self.fence.tool_call_id.len + switch (self.kind) {
            .register => |value| value.tool_name.len,
            .frame => |value| value.frame.bytes,
            .failure => |value| value.len,
            .retire => 0,
        };
    }

    pub fn clone(self: *const Record, gpa: std.mem.Allocator) !Record {
        var copied = self.*;
        copied.gpa = gpa;
        copied.fence.tool_call_id = try gpa.dupe(u8, self.fence.tool_call_id);
        errdefer gpa.free(copied.fence.tool_call_id);
        switch (self.kind) {
            .register => |value| copied.kind = .{ .register = .{ .tool_name = try gpa.dupe(u8, value.tool_name), .width = value.width } },
            .frame => |value| copied.kind = .{ .frame = .{ .sequence = value.sequence, .revision = value.revision, .slot = value.slot, .width = value.width, .frame = try value.frame.clone(gpa) } },
            .failure => |value| copied.kind = .{ .failure = try gpa.dupe(u8, value) },
            .retire => {},
        }
        return copied;
    }
};

fn identity(value: std.json.Value) !u64 {
    const parsed = component_protocol.identifier(value) catch return error.InvalidRendererIdentity;
    if (parsed > 9_007_199_254_740_991) return error.InvalidRendererIdentity;
    return parsed;
}

fn dimension(value: std.json.Value) !usize {
    if (value != .integer or value.integer < 0 or value.integer > component_protocol.maximum_dimension) return error.InvalidRendererDimension;
    return @intCast(value.integer);
}

pub fn read(gpa: std.mem.Allocator, object: *const std.json.ObjectMap) !Record {
    const actual_version = object.get("version") orelse return error.InvalidRendererVersion;
    if (actual_version != .integer or actual_version.integer != version) return error.InvalidRendererVersion;
    const kind = object.get("type") orelse return error.InvalidRendererRecord;
    if (kind != .string) return error.InvalidRendererRecord;
    const row_id = object.get("toolCallId") orelse return error.InvalidRendererIdentity;
    if (row_id != .string or row_id.string.len == 0 or row_id.string.len > 4096) return error.InvalidRendererIdentity;
    var result: Record = .{ .gpa = gpa, .fence = .{
        .owner_generation = try identity(object.get("ownerGeneration") orelse return error.InvalidRendererIdentity),
        .extension_id = try identity(object.get("extensionId") orelse return error.InvalidRendererIdentity),
        .row_generation = try identity(object.get("rowGeneration") orelse return error.InvalidRendererIdentity),
        .tool_call_id = try gpa.dupe(u8, row_id.string),
    }, .kind = .retire };
    errdefer result.deinit();
    if (std.mem.eql(u8, kind.string, "renderer_register")) {
        const name = object.get("toolName") orelse return error.InvalidRendererRecord;
        if (name != .string or name.string.len == 0 or name.string.len > 4096) return error.InvalidRendererRecord;
        const width = try dimension(object.get("width") orelse return error.InvalidRendererDimension);
        const owned_name = try gpa.dupe(u8, name.string);
        result.kind = .{ .register = .{ .tool_name = owned_name, .width = width } };
    } else if (std.mem.eql(u8, kind.string, "renderer_frame")) {
        const width = try dimension(object.get("width") orelse return error.InvalidRendererDimension);
        const sequence = try identity(object.get("sequence") orelse return error.InvalidRendererIdentity);
        const revision = try identity(object.get("revision") orelse return error.InvalidRendererIdentity);
        const slot_value = object.get("slot") orelse return error.InvalidRendererRecord;
        if (slot_value != .string) return error.InvalidRendererRecord;
        const slot = std.meta.stringToEnum(Slot, slot_value.string) orelse return error.InvalidRendererRecord;
        const lines_value = object.get("lines") orelse return error.InvalidRendererFrame;
        if (lines_value != .array or lines_value.array.items.len > component_protocol.maximum_lines) return error.InvalidRendererFrame;
        const lines = try gpa.alloc([]u8, lines_value.array.items.len);
        var count: usize = 0;
        var bytes: usize = 0;
        errdefer {
            for (lines[0..count]) |line| gpa.free(line);
            gpa.free(lines);
        }
        for (lines_value.array.items, lines) |line, *owned| {
            if (line != .string or line.string.len > component_protocol.maximum_frame_bytes - bytes) return error.InvalidRendererFrame;
            owned.* = try gpa.dupe(u8, line.string);
            count += 1;
            bytes += line.string.len;
        }
        result.kind = .{ .frame = .{ .sequence = sequence, .revision = revision, .slot = slot, .width = width, .frame = .{ .gpa = gpa, .lines = lines, .bytes = bytes } } };
    } else if (std.mem.eql(u8, kind.string, "renderer_failure")) {
        const message = object.get("error") orelse return error.InvalidRendererRecord;
        if (message != .string or message.string.len > component_protocol.maximum_frame_bytes) return error.InvalidRendererRecord;
        const owned_message = try gpa.dupe(u8, message.string);
        result.kind = .{ .failure = owned_message };
    } else if (!std.mem.eql(u8, kind.string, "renderer_retire")) return error.InvalidRendererRecord;
    return result;
}

pub fn write(writer: *std.Io.Writer, record: *const Record) !void {
    const kind: []const u8 = switch (record.kind) {
        .register => "renderer_register",
        .frame => "renderer_frame",
        .retire => "renderer_retire",
        .failure => "renderer_failure",
    };
    try writer.print("{{\"type\":\"{s}\",\"version\":{d},\"ownerGeneration\":\"{d}\",\"extensionId\":\"{d}\",\"rowGeneration\":\"{d}\",\"toolCallId\":", .{ kind, version, record.fence.owner_generation, record.fence.extension_id, record.fence.row_generation });
    try std.json.Stringify.value(record.fence.tool_call_id, .{}, writer);
    switch (record.kind) {
        .register => |value| {
            try writer.writeAll(",\"toolName\":");
            try std.json.Stringify.value(value.tool_name, .{}, writer);
            try writer.print(",\"width\":{d}", .{value.width});
        },
        .frame => |value| {
            try writer.print(",\"sequence\":\"{d}\",\"revision\":\"{d}\",\"slot\":\"{s}\",\"width\":{d},\"lines\":", .{ value.sequence, value.revision, @tagName(value.slot), value.width });
            try std.json.Stringify.value(value.frame.lines, .{}, writer);
        },
        .failure => |value| {
            try writer.writeAll(",\"error\":");
            try std.json.Stringify.value(value, .{}, writer);
        },
        .retire => {},
    }
    try writer.writeByte('}');
}

/// Single direction FIFO shared by a process reader and one native consumer.
/// Ownership transfers only after enqueue succeeds.
pub const Queue = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    records: std.ArrayList(Record) = .empty,
    bytes: usize = 0,
    stopped: bool = false,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) Queue {
        return .{ .gpa = gpa, .io = io };
    }
    pub fn deinit(self: *Queue) void {
        for (self.records.items) |*record| record.deinit();
        self.records.deinit(self.gpa);
        self.* = undefined;
    }
    pub fn send(self: *Queue, record: Record) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopped) return error.RendererMailboxStopped;
        if (record.kind == .frame) {
            var index = self.records.items.len;
            while (index > 0) {
                index -= 1;
                const old = &self.records.items[index];
                if (!Fence.matches(old.fence, record.fence)) continue;
                if (old.kind != .frame) break;
                if (old.kind.frame.slot != record.kind.frame.slot) continue;
                if (old.kind.frame.sequence >= record.kind.frame.sequence or record.kind.frame.revision < old.kind.frame.revision) return error.StaleRendererFrame;
                const retained_bytes = self.bytes - old.bytes();
                if (record.bytes() > maximum_queue_bytes - retained_bytes) return error.RendererMailboxLimit;
                old.deinit();
                old.* = record;
                self.bytes = retained_bytes + record.bytes();
                return;
            }
        }
        if (self.records.items.len >= maximum_records or record.bytes() > maximum_queue_bytes - self.bytes) return error.RendererMailboxLimit;
        try self.records.append(self.gpa, record);
        self.bytes += record.bytes();
    }
    pub fn take(self: *Queue) ?Record {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.records.items.len == 0) return null;
        const record = self.records.orderedRemove(0);
        self.bytes -= record.bytes();
        return record;
    }
    pub fn stop(self: *Queue) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.stopped = true;
    }
};

pub const Control = struct {
    gpa: std.mem.Allocator,
    fence: Fence,
    kind: union(enum) { resize: usize, invalidate, retire },

    pub fn deinit(self: *Control) void {
        self.gpa.free(self.fence.tool_call_id);
        self.* = undefined;
    }
    pub fn clone(self: *const Control, gpa: std.mem.Allocator) !Control {
        var owned = self.*;
        owned.gpa = gpa;
        owned.fence.tool_call_id = try gpa.dupe(u8, self.fence.tool_call_id);
        return owned;
    }
};

pub fn readControl(gpa: std.mem.Allocator, object: *const std.json.ObjectMap) !Control {
    const actual_version = object.get("version") orelse return error.InvalidRendererVersion;
    if (actual_version != .integer or actual_version.integer != version) return error.InvalidRendererVersion;
    const value = object.get("control") orelse return error.InvalidRendererControl;
    if (value != .string) return error.InvalidRendererControl;
    const kind: @FieldType(Control, "kind") = if (std.mem.eql(u8, value.string, "resize")) .{ .resize = try dimension(object.get("width") orelse return error.InvalidRendererDimension) } else if (std.mem.eql(u8, value.string, "invalidate")) .invalidate else if (std.mem.eql(u8, value.string, "retire")) .retire else return error.InvalidRendererControl;
    const row = object.get("toolCallId") orelse return error.InvalidRendererIdentity;
    if (row != .string or row.string.len == 0 or row.string.len > 4096) return error.InvalidRendererIdentity;
    return .{ .gpa = gpa, .kind = kind, .fence = .{
        .owner_generation = try identity(object.get("ownerGeneration") orelse return error.InvalidRendererIdentity),
        .extension_id = try identity(object.get("extensionId") orelse return error.InvalidRendererIdentity),
        .row_generation = try identity(object.get("rowGeneration") orelse return error.InvalidRendererIdentity),
        .tool_call_id = try gpa.dupe(u8, row.string),
    } };
}

pub fn writeControl(writer: *std.Io.Writer, control: *const Control) !void {
    try writer.print("{{\"kind\":\"renderer_control\",\"version\":{d},\"ownerGeneration\":\"{d}\",\"extensionId\":\"{d}\",\"rowGeneration\":\"{d}\",\"toolCallId\":", .{ version, control.fence.owner_generation, control.fence.extension_id, control.fence.row_generation });
    try std.json.Stringify.value(control.fence.tool_call_id, .{}, writer);
    try writer.print(",\"control\":\"{s}\"", .{@tagName(control.kind)});
    if (control.kind == .resize) try writer.print(",\"width\":{d}", .{control.kind.resize});
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
    /// Called after the producer and its sink have joined/detached.
    pub fn deinit(self: *ControlQueue) void {
        for (self.controls.items) |*control| control.deinit();
        self.controls.deinit(self.gpa);
        self.* = undefined;
    }
    pub fn send(self: *ControlQueue, control: Control) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopped) return error.RendererMailboxStopped;
        if (control.fence.owner_generation != self.owner_generation) return error.StaleRendererOwner;
        if (self.controls.items.len >= maximum_records or control.fence.tool_call_id.len > maximum_queue_bytes - self.bytes) return error.RendererMailboxLimit;
        try self.controls.append(self.gpa, control);
        self.bytes += control.fence.tool_call_id.len;
        self.wake.set(self.io);
    }
    pub fn next(self: *ControlQueue) std.Io.Cancelable!?Control {
        while (true) {
            self.mutex.lockUncancelable(self.io);
            self.wake.reset();
            if (self.controls.items.len > 0) {
                const control = self.controls.orderedRemove(0);
                self.bytes -= control.fence.tool_call_id.len;
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

const frame_json = "{\"type\":\"renderer_frame\",\"version\":1,\"ownerGeneration\":\"7\",\"extensionId\":\"2\",\"rowGeneration\":\"11\",\"toolCallId\":\"owned-row\",\"sequence\":\"3\",\"revision\":\"4\",\"slot\":\"result\",\"width\":80,\"lines\":[\"Ω🦊\",\"second\"]}";
test "renderer records survive parsing writer roundtrip cloning and queued retirement" {
    const gpa = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, frame_json, .{});
    defer parsed.deinit();
    var record = try read(gpa, &parsed.value.object);
    defer record.deinit();
    var writer: std.Io.Writer.Allocating = .init(gpa);
    defer writer.deinit();
    try write(&writer.writer, &record);
    var reparsed = try std.json.parseFromSlice(std.json.Value, gpa, writer.written(), .{});
    defer reparsed.deinit();
    var copied = try read(gpa, &reparsed.value.object);
    defer copied.deinit();
    try std.testing.expect(Fence.matches(record.fence, copied.fence));
    try std.testing.expectEqualStrings("Ω🦊", copied.kind.frame.frame.lines[0]);
    var queue = Queue.init(gpa, std.testing.io);
    defer queue.deinit();
    const queued = try record.clone(gpa);
    queue.send(queued) catch |err| {
        var owned = queued;
        owned.deinit();
        return err;
    };
    var delivered = queue.take().?;
    defer delivered.deinit();
    try std.testing.expectEqual(@as(u64, 3), delivered.kind.frame.sequence);
    queue.stop();
    try std.testing.expectError(error.RendererMailboxStopped, queue.send(record));
}

test "renderer record allocations unwind and malformed versions types and identity fail closed" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var parsed = try std.json.parseFromSlice(std.json.Value, gpa, frame_json, .{});
            defer parsed.deinit();
            var record = try read(gpa, &parsed.value.object);
            defer record.deinit();
            var copied = try record.clone(gpa);
            defer copied.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
    for ([_][]const u8{
        "{\"version\":2}",
        "{\"version\":1,\"type\":true}",
        "{\"version\":1,\"type\":\"renderer_frame\",\"toolCallId\":\"x\",\"ownerGeneration\":\"9007199254740992\"}",
    }) |raw| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
        defer parsed.deinit();
        if (read(std.testing.allocator, &parsed.value.object)) |value| {
            var unexpected = value;
            unexpected.deinit();
            return error.MalformedRendererRecordAccepted;
        } else |_| {}
    }
}

test "renderer mailbox coalesces same slot while controls retain owner fence and stop ownership" {
    const gpa = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, frame_json, .{});
    defer parsed.deinit();
    var record = try read(gpa, &parsed.value.object);
    defer record.deinit();
    var queue = Queue.init(gpa, std.testing.io);
    defer queue.deinit();
    var first = try record.clone(gpa);
    var transferred = false;
    defer if (!transferred) first.deinit();
    try queue.send(first);
    transferred = true;
    record.kind.frame.revision -= 1;
    record.kind.frame.sequence += 1;
    try std.testing.expectError(error.StaleRendererFrame, queue.send(record));
    record.kind.frame.revision += 1;
    const latest = try record.clone(gpa);
    queue.send(latest) catch |err| {
        var owned = latest;
        owned.deinit();
        return err;
    };
    var received = queue.take().?;
    defer received.deinit();
    try std.testing.expectEqual(@as(u64, 4), received.kind.frame.sequence);
    try std.testing.expect(queue.take() == null);
    var control: Control = .{ .gpa = gpa, .fence = record.fence, .kind = .{ .resize = 67 } };
    control.fence.tool_call_id = try gpa.dupe(u8, record.fence.tool_call_id);
    defer control.deinit();
    var writer: std.Io.Writer.Allocating = .init(gpa);
    defer writer.deinit();
    try writeControl(&writer.writer, &control);
    var control_json = try std.json.parseFromSlice(std.json.Value, gpa, writer.written(), .{});
    defer control_json.deinit();
    var copied = try readControl(gpa, &control_json.value.object);
    defer copied.deinit();
    try std.testing.expect(Fence.matches(control.fence, copied.fence));
    try std.testing.expectEqual(@as(usize, 67), copied.kind.resize);
    var controls = ControlQueue.init(gpa, std.testing.io, 7);
    defer controls.deinit();
    copied.fence.owner_generation = 8;
    try std.testing.expectError(error.StaleRendererOwner, controls.send(copied));
    copied.fence.owner_generation = 7;
    const queued = try copied.clone(gpa);
    controls.send(queued) catch |err| {
        var owned = queued;
        owned.deinit();
        return err;
    };
    var adopted = (try controls.next()).?;
    defer adopted.deinit();
    controls.stop();
    try std.testing.expect((try controls.next()) == null);
    try std.testing.expectError(error.RendererMailboxStopped, controls.send(copied));
}

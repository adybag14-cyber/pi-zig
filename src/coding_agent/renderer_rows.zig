//! Owned renderer leases and call/result slots; no worker or JS pointers.
const std = @import("std");
pub const protocol = @import("../extensions/renderer_protocol.zig");

pub const Slot = struct {
    sequence: u64,
    revision: u64,
    width: usize,
    frame: protocol.Frame,
};
const Diagnostic = struct { gpa: std.mem.Allocator, text: []u8 };
pub const Row = struct {
    gpa: std.mem.Allocator,
    fence: protocol.Fence,
    tool_name: []u8,
    width: usize,
    requested_width: usize = 0,
    requested_expanded: ?bool = null,
    expanded: bool = false,
    requested_expansion_revision: ?u64 = null,
    retired: bool = false,
    attached: bool = false,
    needs_retire: bool = false,
    slots: [2]?Slot = .{ null, null },
    diagnostic: ?Diagnostic = null,

    fn bytes(self: *const Row) usize {
        var size = self.fence.tool_call_id.len + self.tool_name.len;
        for (self.slots) |slot| if (slot) |value| {
            size += value.frame.bytes;
        };
        if (self.diagnostic) |value| size += value.text.len;
        return size;
    }
    fn clearFrames(self: *Row) void {
        for (&self.slots) |*slot| if (slot.*) |*value| {
            value.frame.deinit();
            slot.* = null;
        };
        if (self.diagnostic) |value| value.gpa.free(value.text);
        self.diagnostic = null;
    }
    fn deinit(self: *Row) void {
        self.clearFrames();
        self.gpa.free(self.fence.tool_call_id);
        self.gpa.free(self.tool_name);
    }
    pub fn lines(self: *const Row, slot: protocol.Slot, width: usize) ?[]const []u8 {
        if (self.retired) return null;
        const value = self.slots[@intFromEnum(slot)] orelse return null;
        return if (value.width == width) value.frame.lines else null;
    }
};

pub const Rows = struct {
    gpa: std.mem.Allocator,
    rows: std.ArrayList(Row) = .empty,
    bytes: usize = 0,
    pub fn init(gpa: std.mem.Allocator) Rows {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *Rows) void {
        for (self.rows.items) |*row| row.deinit();
        self.rows.deinit(self.gpa);
        self.* = init(self.gpa);
    }
    pub fn find(self: *Rows, tool_call_id: []const u8) ?*Row {
        for (self.rows.items) |*row| if (std.mem.eql(u8, row.fence.tool_call_id, tool_call_id)) return row;
        return null;
    }
    fn capacity(self: *Rows, removed: usize, added: usize) !void {
        if (added > protocol.maximum_queue_bytes - (self.bytes - removed)) return error.RendererRowBytesLimit;
    }
    /// Moves admitted payloads out of record, retaining its remaining ownership.
    /// Stale records remain untouched; caller always deinitializes the record.
    pub fn adopt(self: *Rows, record: *protocol.Record) !bool {
        const old = self.find(record.fence.tool_call_id);
        if (record.kind == .register) {
            const registration = record.kind.register;
            if (old) |row| {
                if (protocol.Fence.matches(row.fence, record.fence)) {
                    if (row.retired) return false;
                    if (row.width == registration.width and row.expanded == registration.expanded) return false;
                    row.width = registration.width;
                    row.expanded = registration.expanded;
                    row.requested_width = 0;
                    return true;
                }
                if (record.fence.owner_generation < row.fence.owner_generation or
                    (record.fence.owner_generation == row.fence.owner_generation and record.fence.row_generation <= row.fence.row_generation)) return false;
            } else if (self.rows.items.len >= protocol.maximum_rows) return error.RendererRowCountLimit;
            var next: Row = .{ .gpa = record.gpa, .fence = record.fence, .tool_name = registration.tool_name, .width = registration.width, .expanded = registration.expanded };
            const removed = if (old) |row| row.bytes() else 0;
            try self.capacity(removed, next.bytes());
            if (old) |row| {
                row.deinit();
                row.* = next;
            } else try self.rows.append(self.gpa, next);
            self.bytes = self.bytes - removed + next.bytes();
            record.fence.tool_call_id = &.{};
            record.kind = .retire;
            return true;
        }
        const row = old orelse return false;
        if (row.retired or !protocol.Fence.matches(row.fence, record.fence)) return false;
        switch (record.kind) {
            .frame => |value| {
                const index = @intFromEnum(value.slot);
                if (row.slots[index]) |previous| if (value.sequence <= previous.sequence or value.revision < previous.revision) return false;
                const previous_bytes = if (row.slots[index]) |previous| previous.frame.bytes else 0;
                const diagnostic_bytes = if (row.diagnostic) |diagnostic| diagnostic.text.len else 0;
                try self.capacity(previous_bytes + diagnostic_bytes, value.frame.bytes);
                if (row.slots[index]) |*previous| previous.frame.deinit();
                if (row.diagnostic) |diagnostic| diagnostic.gpa.free(diagnostic.text);
                row.diagnostic = null;
                row.slots[index] = .{ .sequence = value.sequence, .revision = value.revision, .width = value.width, .frame = value.frame };
                self.bytes = self.bytes - previous_bytes - diagnostic_bytes + value.frame.bytes;
                record.kind = .retire;
            },
            .failure => |message| {
                const previous_bytes = row.bytes();
                const next_bytes = row.fence.tool_call_id.len + row.tool_name.len + message.len;
                try self.capacity(previous_bytes, next_bytes);
                row.clearFrames();
                row.diagnostic = .{ .gpa = record.gpa, .text = message };
                self.bytes = self.bytes - previous_bytes + next_bytes;
                record.kind = .retire;
            },
            .retire => {
                const previous_bytes = row.bytes();
                row.clearFrames();
                row.retired = true;
                self.bytes = self.bytes - previous_bytes + row.bytes();
            },
            .register => unreachable,
        }
        return true;
    }
    pub fn closeOwner(self: *Rows, generation: u64) bool {
        var changed = false;
        for (self.rows.items) |*row| if (!row.retired and row.fence.owner_generation == generation) {
            const previous_bytes = row.bytes();
            row.clearFrames();
            row.retired = true;
            self.bytes = self.bytes - previous_bytes + row.bytes();
            changed = true;
        };
        return changed;
    }
    pub fn detach(self: *Rows, row: *Row) void {
        if (row.retired) return;
        const previous_bytes = row.bytes();
        row.clearFrames();
        row.retired = true;
        row.needs_retire = true;
        self.bytes = self.bytes - previous_bytes + row.bytes();
    }
};

fn ownedRecord(gpa: std.mem.Allocator, kind: []const u8, sequence: u64, slot: []const u8, width: usize, text: []const u8) !protocol.Record {
    var encoded: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer encoded.deinit();
    try encoded.writer.print("{{\"version\":1,\"type\":\"renderer_{s}\",\"ownerGeneration\":\"1\",\"extensionId\":\"2\",\"rowGeneration\":\"3\",\"toolCallId\":\"tool-a\",\"toolName\":\"paint\",\"width\":{d},\"sequence\":\"{d}\",\"revision\":\"1\",\"slot\":\"{s}\",\"lines\":[", .{ kind, width, sequence, slot });
    try std.json.Stringify.value(text, .{}, &encoded.writer);
    try encoded.writer.writeAll("]}");
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, encoded.written(), .{});
    defer parsed.deinit();
    return protocol.read(gpa, &parsed.value.object);
}

fn ownershipCase(gpa: std.mem.Allocator) !void {
    var rows = Rows.init(gpa);
    defer rows.deinit();
    var registration = try ownedRecord(gpa, "register", 1, "call", 80, "");
    defer registration.deinit();
    try std.testing.expect(try rows.adopt(&registration));
    var call = try ownedRecord(gpa, "frame", 5, "call", 80, "call Ω🦊");
    defer call.deinit();
    try std.testing.expect(try rows.adopt(&call));
    // Different slots have independent sequences: mailbox coalescing can put
    // a newer call frame before an already-admitted result frame.
    var result = try ownedRecord(gpa, "frame", 4, "result", 80, "result");
    defer result.deinit();
    try std.testing.expect(try rows.adopt(&result));
    const row = rows.find("tool-a").?;
    try std.testing.expectEqualStrings("call Ω🦊", row.lines(.call, 80).?[0]);
    try std.testing.expectEqualStrings("result", row.lines(.result, 80).?[0]);
    try std.testing.expect(row.lines(.result, 70) == null);
    var stale = try ownedRecord(gpa, "frame", 3, "call", 80, "stale");
    defer stale.deinit();
    try std.testing.expect(!try rows.adopt(&stale));
    var retire = try ownedRecord(gpa, "retire", 1, "call", 80, "");
    defer retire.deinit();
    try std.testing.expect(try rows.adopt(&retire));
    var late = try ownedRecord(gpa, "frame", 9, "result", 80, "late");
    defer late.deinit();
    try std.testing.expect(!try rows.adopt(&late));
    var reopen = try ownedRecord(gpa, "register", 1, "call", 80, "");
    defer reopen.deinit();
    try std.testing.expect(!try rows.adopt(&reopen));
    reopen.fence.row_generation += 1;
    try std.testing.expect(try rows.adopt(&reopen));
    try std.testing.expect(rows.closeOwner(1));
}

test "renderer rows keep independent slots reject stale and retired leases and release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ownershipCase, .{});
}

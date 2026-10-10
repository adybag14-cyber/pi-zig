//! Parent-side process IO routing. Callbacks are native and hold a process
//! generation lease; SDK disposal and UI service rebinding do not replace it.
const std = @import("std");
const protocol = @import("process_stream_protocol.zig");
const bridge_mod = @import("process_stream_bridge.zig");
pub const SendFn = *const fn (?*anyopaque, []const u8) anyerror!void;
pub const Parent = struct {
    bridge: ?bridge_mod.Bridge = null,
    lease: ?protocol.Lease = null,
    metadata: ?protocol.Metadata = null,
    sink: ?bridge_mod.Sink = null,
    active: std.atomic.Value(bool) = .init(false),
    last_request_id: u64 = 0,
    input_ended: bool = false,
    pub fn configure(self: *Parent, bridge: bridge_mod.Bridge, lease: protocol.Lease) !void {
        if (self.bridge != null) return error.NativeProcessFrontendAlreadyConfigured;
        if ((bridge.attach_fn == null) != (bridge.detach_fn == null)) return error.InvalidNativeProcessBridge;
        if (lease.owner_generation == 0 or lease.process_generation == 0) return error.InvalidNativeProcessLease;
        try bridge.guard_fn(bridge.context);
        var metadata = try bridge.metadata_fn(bridge.context);
        metadata.has_shift_helper = bridge.is_shift_pressed_fn != null;
        metadata.has_vt_input_helper = bridge.enable_vt_input_fn != null;
        self.bridge = bridge;
        self.lease = lease;
        self.metadata = metadata;
        self.last_request_id = 0;
        self.input_ended = false;
        self.active.store(true, .release);
    }
    /// Called only after the load_group bootstrap has been written. A producer
    /// can immediately deliver input without displacing the first wire record.
    pub fn attach(self: *Parent, sink: bridge_mod.Sink) !void {
        if (!self.live(sink.lease)) return error.NativeProcessFrontendClosed;
        const bridge = self.bridge.?;
        if (bridge.attach_fn) |attach_fn| {
            self.sink = sink;
            attach_fn(bridge.context, sink) catch |err| {
                self.close();
                return err;
            };
        }
    }
    pub fn close(self: *Parent) void {
        self.active.store(false, .release);
        if (self.sink) |sink| {
            self.sink = null;
            const bridge = self.bridge.?;
            bridge.detach_fn.?(bridge.context, sink);
        }
    }
    pub fn live(self: *Parent, lease: protocol.Lease) bool {
        return self.active.load(.acquire) and if (self.lease) |current| current.matches(lease) else false;
    }
    pub fn writeStartup(self: *Parent, writer: *std.Io.Writer) !void {
        const lease = self.lease orelse return;
        try writer.writeAll(",\"processIO\":{");
        try protocol.writeLease(writer, lease);
        try writer.writeByte(',');
        try protocol.writeMetadata(writer, self.metadata.?);
        try writer.writeByte('}');
    }
    pub fn dispatch(self: *Parent, bytes: []const u8, context: ?*anyopaque, send: SendFn) !bool {
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer arena.deinit();
        const value = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), bytes, .{}) catch return false;
        if (value != .object) return false;
        const kind = value.object.get("type") orelse return false;
        if (kind != .string or !std.mem.eql(u8, kind.string, "native_process_request")) return false;
        const request = protocol.readRequest(&value.object) catch return true;
        if (!self.live(request.header.lease) or request.header.request_id <= self.last_request_id) return true;
        self.last_request_id = request.header.request_id;
        const result = self.execute(request.operation);
        var reply: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer reply.deinit();
        try reply.writer.writeAll("{\"kind\":\"native_process_response\",");
        try protocol.writeHeader(&reply.writer, request.header);
        if (result) |success| {
            try reply.writer.print(",\"ok\":true,\"result\":{s}}}", .{if (success) "true" else "false"});
        } else |err| {
            try reply.writer.writeAll(",\"ok\":false,\"error\":{\"name\":\"Error\",\"message\":");
            try std.json.Stringify.value(@errorName(err), .{}, &reply.writer);
            try reply.writer.writeAll("}}");
        }
        try send(context, reply.written());
        return true;
    }
    fn execute(self: *Parent, operation: protocol.Operation) !bool {
        const bridge = self.bridge orelse return error.NativeProcessFrontendClosed;
        try bridge.guard_fn(bridge.context);
        switch (operation) {
            .control => |control| try bridge.control_fn(bridge.context, control),
            .write => |payload| {
                const count = try std.base64.standard.Decoder.calcSizeForSlice(payload.base64);
                const bytes = try std.heap.page_allocator.alloc(u8, count);
                defer std.heap.page_allocator.free(bytes);
                try std.base64.standard.Decoder.decode(bytes, payload.base64);
                try bridge.write_fn(bridge.context, payload.output, bytes);
            },
            .is_shift_pressed => return if (bridge.is_shift_pressed_fn) |query| query(bridge.context) else false,
            .enable_vt_input => return if (bridge.enable_vt_input_fn) |query| query(bridge.context) else false,
        }
        return true;
    }
    pub fn input(self: *Parent, lease: protocol.Lease, bytes: []const u8, context: ?*anyopaque, send: SendFn) !void {
        if (!self.live(lease)) return error.NativeProcessFrontendClosed;
        if (self.input_ended) return error.NativeProcessInputEnded;
        var index: usize = 0;
        while (index < bytes.len) {
            if (!self.live(lease)) return error.NativeProcessFrontendClosed;
            const chunk_end = @min(bytes.len, index +| protocol.maximum_chunk_bytes);
            const chunk = bytes[index..chunk_end];
            const encoded = try std.heap.page_allocator.alloc(u8, std.base64.standard.Encoder.calcSize(chunk.len));
            defer std.heap.page_allocator.free(encoded);
            _ = std.base64.standard.Encoder.encode(encoded, chunk);
            var out: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
            defer out.deinit();
            try out.writer.writeAll("{\"kind\":\"native_process_input\",");
            try protocol.writeLease(&out.writer, lease);
            try out.writer.print(",\"bytesBase64\":\"{s}\"}}", .{encoded});
            try send(context, out.written());
            index = chunk_end;
        }
    }
    pub fn end(self: *Parent, lease: protocol.Lease, context: ?*anyopaque, send: SendFn) !void {
        if (!self.live(lease)) return error.NativeProcessFrontendClosed;
        if (self.input_ended) return;
        var out: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer out.deinit();
        try out.writer.writeAll("{\"kind\":\"native_process_end\",");
        try protocol.writeLease(&out.writer, lease);
        try out.writer.writeByte('}');
        try send(context, out.written());
        self.input_ended = true;
    }
    pub fn resize(self: *Parent, lease: protocol.Lease, columns: u32, rows: u32, context: ?*anyopaque, send: SendFn) !void {
        if (!self.live(lease)) return error.NativeProcessFrontendClosed;
        var out: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer out.deinit();
        try out.writer.writeAll("{\"kind\":\"native_process_resize\",");
        try protocol.writeLease(&out.writer, lease);
        try out.writer.print(",\"columns\":{d},\"rows\":{d}}}", .{ columns, rows });
        try send(context, out.written());
    }
};

test "process stream parent preserves binary requests and rejects retired generations with joined detach" {
    const Fixture = struct {
        live: bool = true,
        attached: ?bridge_mod.Sink = null,
        detach_count: usize = 0,
        write_count: usize = 0,
        bytes: [2]u8 = undefined,
        records: std.ArrayList([]u8) = .empty,
        fn guard(raw: ?*anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (!self.live) return error.ActualFrontendRetired;
        }
        fn metadata(_: ?*anyopaque) !protocol.Metadata {
            return .{ .stdin_tty = false, .stdin_raw = false, .stdout_tty = false, .stderr_tty = true, .columns = null, .rows = 0 };
        }
        fn control(_: ?*anyopaque, _: protocol.Control) !void {}
        fn write(raw: ?*anyopaque, output: protocol.Output, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqual(protocol.Output.stderr, output);
            try std.testing.expectEqual(@as(usize, 2), bytes.len);
            @memcpy(&self.bytes, bytes);
            self.write_count += 1;
        }
        fn attach(raw: ?*anyopaque, sink: bridge_mod.Sink) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.attached = sink;
        }
        fn detach(raw: ?*anyopaque, sink: bridge_mod.Sink) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            std.debug.assert(self.attached.?.matches(sink));
            self.attached = null;
            self.detach_count += 1;
        }
        fn send(raw: ?*anyopaque, bytes: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const owned = try std.testing.allocator.dupe(u8, bytes);
            errdefer std.testing.allocator.free(owned);
            try self.records.append(std.testing.allocator, owned);
        }
        fn input(_: ?*anyopaque, _: protocol.Lease, _: []const u8) !void {}
        fn resize(_: ?*anyopaque, _: protocol.Lease, _: u32, _: u32) !void {}
        fn end(_: ?*anyopaque, _: protocol.Lease) !void {}
    };
    var fixture: Fixture = .{};
    defer {
        for (fixture.records.items) |record| std.testing.allocator.free(record);
        fixture.records.deinit(std.testing.allocator);
    }
    var parent: Parent = .{};
    defer parent.close();
    const lease: protocol.Lease = .{ .owner_generation = 9007199254740993, .process_generation = std.math.maxInt(u64) };
    const bridge: bridge_mod.Bridge = .{ .context = &fixture, .guard_fn = Fixture.guard, .metadata_fn = Fixture.metadata, .control_fn = Fixture.control, .write_fn = Fixture.write, .attach_fn = Fixture.attach, .detach_fn = Fixture.detach };
    try parent.configure(bridge, lease);
    try parent.attach(.{ .context = &fixture, .lease = lease, .input_fn = Fixture.input, .resize_fn = Fixture.resize, .end_fn = Fixture.end });
    try std.testing.expectError(error.NativeProcessFrontendAlreadyConfigured, parent.configure(bridge, lease));
    const request = "{\"type\":\"native_process_request\",\"version\":1,\"ownerGeneration\":\"9007199254740993\",\"processGeneration\":\"18446744073709551615\",\"requestId\":\"1\",\"method\":\"write\",\"output\":\"stderr\",\"bytesBase64\":\"AP8=\"}";
    try std.testing.expect(try parent.dispatch(request, &fixture, Fixture.send));
    try std.testing.expectEqualSlices(u8, &.{ 0, 255 }, &fixture.bytes);
    try std.testing.expectEqual(@as(usize, 1), fixture.write_count);
    var response = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture.records.items[0], .{});
    defer response.deinit();
    try std.testing.expect((try protocol.readHeader(&response.value.object)).matches(.{ .lease = lease, .request_id = 1 }));
    try std.testing.expect(response.value.object.get("ok").?.bool);
    try std.testing.expect(try parent.dispatch(request, &fixture, Fixture.send));
    try std.testing.expectEqual(@as(usize, 1), fixture.write_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.records.items.len);
    try parent.input(lease, "last", &fixture, Fixture.send);
    try parent.end(lease, &fixture, Fixture.send);
    try parent.end(lease, &fixture, Fixture.send);
    try std.testing.expectEqual(@as(usize, 3), fixture.records.items.len);
    try std.testing.expect(std.mem.indexOf(u8, fixture.records.items[1], "native_process_input") != null);
    try std.testing.expect(std.mem.indexOf(u8, fixture.records.items[2], "native_process_end") != null);
    try std.testing.expectError(error.NativeProcessInputEnded, parent.input(lease, "late", &fixture, Fixture.send));
    parent.close();
    parent.close();
    try std.testing.expectEqual(@as(usize, 1), fixture.detach_count);
    try std.testing.expect(!parent.live(lease));
    try std.testing.expectError(error.NativeProcessFrontendClosed, parent.end(lease, &fixture, Fixture.send));
    try std.testing.expect(try parent.dispatch(request, &fixture, Fixture.send));
    try std.testing.expectEqual(@as(usize, 1), fixture.write_count);
}

//! Owner-thread process IO requests use exact byte-only replies. Guest jobs and
//! unrelated controls remain queued while a synchronous stream call is active.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const protocol = @import("process_stream_protocol.zig");
const streams = @import("native_process_streams.zig");
const sdk = @import("native_sdk.zig");
pub const Worker = struct {
    engine: *em.Engine,
    io: std.Io,
    writer: *std.Io.Writer,
    lease: protocol.Lease,
    stream_lease: ?streams.Lease = null,
    context: ?*anyopaque,
    take_fn: *const fn (?*anyopaque, protocol.Header) anyerror!?[]u8,
    wait_fn: *const fn (?*anyopaque, i64) anyerror!void,
    next_request_id: u64 = 1,
    closed: bool = false,
    owner: std.Thread.Id = std.Thread.getCurrentId(),
    pub fn bridge(self: *Worker, metadata: protocol.Metadata) streams.Bridge {
        return .{ .context = self, .guard_fn = guard, .control_fn = control, .write_fn = write, .is_shift_pressed_fn = if (metadata.has_shift_helper) shift else null, .enable_vt_input_fn = if (metadata.has_vt_input_helper) vtInput else null };
    }
    fn guard(context: ?*anyopaque) !void {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        if (self.closed) return error.NativeProcessFrontendClosed;
        if (self.owner != std.Thread.getCurrentId()) return error.NativeProcessWrongOwnerThread;
        if (self.stream_lease) |lease| if (!streams.ownsLease(self.engine, lease)) return error.NativeProcessFrontendClosed;
    }
    fn control(context: ?*anyopaque, operation: streams.Control) !void {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        const normalized: protocol.Control = switch (operation) {
            .raw_mode => |enabled| .{ .raw_mode = enabled },
            .@"resume" => .@"resume",
            .pause => .pause,
            .encoding => |encoding| .{ .encoding = encoding },
        };
        _ = try self.request(.{ .control = normalized });
    }
    fn write(context: ?*anyopaque, output: streams.Output, bytes: []const u8) !void {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        var start: usize = 0;
        while (true) {
            const end = @min(bytes.len, start +| protocol.maximum_chunk_bytes);
            const chunk = bytes[start..end];
            const encoded = try self.engine.gpa.alloc(u8, std.base64.standard.Encoder.calcSize(chunk.len));
            defer self.engine.gpa.free(encoded);
            _ = std.base64.standard.Encoder.encode(encoded, chunk);
            _ = try self.request(.{ .write = .{ .output = if (output == .stdout) .stdout else .stderr, .base64 = encoded } });
            if (end == bytes.len) break;
            start = end;
        }
    }
    fn shift(context: ?*anyopaque) !bool {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        return self.request(.is_shift_pressed);
    }
    fn vtInput(context: ?*anyopaque) !bool {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        return self.request(.enable_vt_input);
    }
    fn request(self: *Worker, operation: protocol.Operation) !bool {
        try guard(self);
        const id = self.next_request_id;
        self.next_request_id = std.math.add(u64, id, 1) catch return error.NativeProcessRequestIdentityExhausted;
        const header: protocol.Header = .{ .lease = self.lease, .request_id = id };
        var out: std.Io.Writer.Allocating = .init(self.engine.gpa);
        defer out.deinit();
        try out.writer.writeAll("{\"type\":\"native_process_request\",");
        try protocol.writeHeader(&out.writer, header);
        switch (operation) {
            .write => |payload| {
                try out.writer.print(",\"method\":\"write\",\"output\":\"{s}\",\"bytesBase64\":", .{@tagName(payload.output)});
                try std.json.Stringify.value(payload.base64, .{}, &out.writer);
            },
            .control => |op| switch (op) {
                .raw_mode => |enabled| try out.writer.print(",\"method\":\"raw_mode\",\"enabled\":{s}", .{if (enabled) "true" else "false"}),
                .@"resume" => try out.writer.writeAll(",\"method\":\"resume\""),
                .pause => try out.writer.writeAll(",\"method\":\"pause\""),
                .encoding => |encoding| {
                    try out.writer.writeAll(",\"method\":\"encoding\",\"encoding\":");
                    try std.json.Stringify.value(encoding, .{}, &out.writer);
                },
            },
            .is_shift_pressed => try out.writer.writeAll(",\"method\":\"is_shift_pressed\""),
            .enable_vt_input => try out.writer.writeAll(",\"method\":\"enable_vt_input\""),
        }
        try out.writer.writeByte('}');
        try self.writer.writeByte(0x1e);
        try self.writer.writeAll(out.written());
        try self.writer.writeByte('\n');
        try self.writer.flush();
        const deadline = std.Io.Clock.awake.now(self.io).toMilliseconds() +| 60_000;
        while (true) {
            if (try self.take_fn(self.context, header)) |bytes| {
                defer std.heap.page_allocator.free(bytes);
                var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
                defer arena.deinit();
                const value = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), bytes, .{});
                if (value != .object or !(try protocol.readHeader(&value.object)).matches(header)) return error.InvalidProcessStreamResponse;
                const ok = value.object.get("ok") orelse return error.InvalidProcessStreamResponse;
                if (ok != .bool) return error.InvalidProcessStreamResponse;
                if (!ok.bool) return self.throwParentError(value.object.get("error") orelse .null);
                const result = value.object.get("result") orelse return error.InvalidProcessStreamResponse;
                if (result != .bool) return error.InvalidProcessStreamResponse;
                return result.bool;
            }
            try self.wait_fn(self.context, deadline);
        }
    }
    fn throwParentError(self: *Worker, detail: std.json.Value) !bool {
        const engine = self.engine;
        const reason = try engine.checked(c.JS_NewError(engine.context));
        var owned = true;
        errdefer if (owned) engine.freeValue(reason);
        if (detail == .object) {
            inline for (.{ "message", "name", "code", "syscall" }) |name| if (detail.object.get(name)) |value| try sdk.put(engine, reason, name, try engine.fromJsonValue(value));
        } else {
            try sdk.put(engine, reason, "message", try engine.fromJsonValue(detail));
        }
        _ = c.JS_Throw(engine.context, reason);
        owned = false;
        return @import("native_js_values.zig").capture(engine);
    }
};
